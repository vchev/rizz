"""Reply engine: conversation in, suggested replies out.

    suggest_replies(messages, platform="imessage", n=3, tone=None, under_18=False, voice=None)

messages is a list of {"speaker": "you"|"them", "text": str, "reply_to": str (optional)},
oldest first. reply_to is the start of an earlier message that this one quotes (a quoted reply).
voice is the user's optional voice profile from the app: sliders 0..1 (length, caps, humour,
emoji, forward) and up to 8 "examples" of their own texts from other chats. Without it the
prompt is exactly as before. Nothing is stored: the chat is only sent to the model and then forgotten.
"""
import json
import re

from engine import anthropic_api, openrouter, prompts, settings

TONES = ("funny", "flirty", "sweet", "chill", "bold", "shorter")
# Older app builds send these; they mean the same mood.
TONE_ALIASES = {"funnier": "funny", "flirtier": "flirty"}
MAX_MESSAGES = 80          # only the most recent messages are sent to the model
MAX_CHARS = 12000          # ... and at most this much text, to keep cost and speed in check
MAX_REPLY_CHARS = 400

GENERIC = {
    "haha nice", "that's awesome", "that's awesome!", "tell me more", "lol", "haha", "nice",
    "that's cool", "cool", "wow", "same", "omg", "yes", "ok",
}


class BadRequest(ValueError):
    pass


def clean_messages(messages):
    """Validate and trim the conversation. Raises BadRequest with a plain message."""
    if not isinstance(messages, list) or not messages:
        raise BadRequest("messages must be a non-empty list")
    out = []
    for m in messages:
        if not isinstance(m, dict):
            raise BadRequest("each message must be an object")
        speaker = m.get("speaker", m.get("from"))
        text = m.get("text")
        if speaker not in ("you", "them") or not isinstance(text, str):
            raise BadRequest('each message needs speaker "you" or "them" and text')
        text = " ".join(text.split())
        if text:
            item = {"speaker": speaker, "text": text}
            quoted = m.get("reply_to")
            if isinstance(quoted, str) and quoted.strip():
                item["reply_to"] = " ".join(quoted.split())[:300]
            out.append(item)
    if not out:
        raise BadRequest("messages are all empty")
    out = out[-MAX_MESSAGES:]
    total, start = 0, len(out)
    while start > 0 and total + len(out[start - 1]["text"]) <= MAX_CHARS:
        start -= 1
        total += len(out[start]["text"])
    return out[max(0, min(start, len(out) - 1)):]


def clean_label(label):
    """A short tag for the reply's angle ("playful", "direct"), or None if it looks off."""
    if not isinstance(label, str):
        return None
    label = " ".join(label.strip().strip("\"'.").lower().split())
    if not label or len(label) > 16 or len(label.split()) > 2 or not re.fullmatch(r"[a-z ]+", label):
        return None
    return label


def parse_items(raw):
    """Pull the replies out of the model's answer (JSON, or a plain list as fallback).
    Returns [{"text": str, "label": str or None}]."""
    raw = (raw or "").strip()
    raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw)
    items = None
    match = re.search(r"\{.*\}", raw, re.S)
    if match:
        try:
            data = json.loads(match.group(0))
            items = data.get("replies") if isinstance(data, dict) else None
        except ValueError:
            items = None
    if items is None:
        items = [re.sub(r"^\s*(?:\d+[.)]|[-*•])\s*", "", line) for line in raw.splitlines()]
    out = []
    for item in items:
        label = None
        if isinstance(item, dict):
            label = clean_label(item.get("label"))
            item = item.get("text", "")
        if not isinstance(item, str):
            continue
        text = item.strip()
        if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'“”":
            text = text[1:-1].strip()
        if text.startswith("“") and text.endswith("”"):
            text = text[1:-1].strip()
        if text:
            out.append({"text": text[:MAX_REPLY_CHARS], "label": label})
    return out


def parse_replies(raw):
    """Just the reply texts from the model's answer."""
    return [item["text"] for item in parse_items(raw)]


def pick_items(items, n):
    """Drop duplicates and stock phrases, keep the first n."""
    seen, out = set(), []
    for item in items:
        r = item["text"]
        key = re.sub(r"[^\w\s]", "", r.lower()).strip()
        if not key or key in seen or r.lower().strip(" .!") in GENERIC:
            continue
        seen.add(key)
        out.append(item)
    return out[:n]


def pick(replies, n):
    return [item["text"] for item in pick_items([{"text": r, "label": None} for r in replies], n)]


def model_call(system, user, config):
    name, key = settings.provider()
    if name == "anthropic":
        return anthropic_api.chat(key, config.get("anthropic_model", "claude-haiku-5-5"), system, user)
    return openrouter.chat(
        key,
        config["model"],
        [{"role": "system", "content": system}, {"role": "user", "content": user}],
        provider=config.get("openrouter_provider"),
    )


def suggest_replies(messages, platform="imessage", n=None, tone=None, under_18=False,
                    call=None, config=None, replying_to=None, voice=None):
    """Return a list of up to n reply strings. call(system, user, config) -> raw text can be
    swapped in for tests; by default it calls the configured model."""
    return [item["text"] for item in suggest_reply_items(
        messages, platform=platform, n=n, tone=tone, under_18=under_18, call=call, config=config,
        replying_to=replying_to, voice=voice)]


def suggest_reply_items(messages, platform="imessage", n=None, tone=None, under_18=False,
                        call=None, config=None, replying_to=None, voice=None, favorite_mood=None):
    """Like suggest_replies, but each reply comes with its short label (or None):
    [{"text": str, "label": str or None}]."""
    config = config or settings.load_config()
    n = n or config.get("replies_per_request", 3)
    if not isinstance(n, int) or not 1 <= n <= 5:
        raise BadRequest("n must be 1 to 5")
    tone = TONE_ALIASES.get(tone, tone)
    if tone is not None and tone not in TONES:
        raise BadRequest("tone must be one of: " + ", ".join(TONES))
    msgs = clean_messages(messages)
    system = prompts.system_prompt(under_18=bool(under_18))
    if not isinstance(replying_to, str) or not replying_to.strip():
        replying_to = None
    if voice is not None and not isinstance(voice, dict):
        raise BadRequest("voice must be an object")
    # The mood the user picks most (counted on their phone). Only a nudge: unknown
    # values are ignored, and teen mode never leans flirty.
    if not isinstance(favorite_mood, str) or favorite_mood not in prompts.MOODS \
            or (under_18 and favorite_mood == "flirty"):
        favorite_mood = None
    user = prompts.user_prompt(msgs, platform, n, tone, replying_to=replying_to, voice=voice,
                               favorite_mood=favorite_mood)
    call = call or model_call
    replies = pick_items(parse_items(call(system, user, config)), n)
    if len(replies) < n:   # one retry if the model came back short or malformed
        more = parse_items(call(system, user, config))
        replies = pick_items(replies + more, n)
    if not replies:
        raise openrouter.ModelError("The model returned no usable replies")
    return replies


def stand_in_model(system, user, config):
    """Offline fake model for --dry-run and tests: echoes bits of the last match message."""
    last = [l for l in user.splitlines() if l.startswith("MATCH: ")]
    topic = last[-1][len("MATCH: "):][:40] if last else "this"
    return json.dumps({"replies": [
        {"text": "[stand-in] wait, %s?" % topic, "label": "playful"},
        {"text": "[stand-in] ok I need the full story on that", "label": "sweet"},
        {"text": "[stand-in] haha what are you up to this weekend", "label": "flirty"},
        {"text": "[stand-in] fair. coffee sometime?", "label": "bold"},
    ]})
