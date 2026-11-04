"""Reply engine: conversation in, suggested replies out.

    suggest_replies(messages, platform="imessage", n=3, tone=None, under_18=False)

messages is a list of {"speaker": "you"|"them", "text": str}, oldest first.
Nothing is stored: the chat is only sent to the model and then forgotten.
"""
import json
import re

from engine import openrouter, prompts, settings

TONES = ("funnier", "flirtier", "shorter")
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
            out.append({"speaker": speaker, "text": text})
    if not out:
        raise BadRequest("messages are all empty")
    out = out[-MAX_MESSAGES:]
    total, start = 0, len(out)
    while start > 0 and total + len(out[start - 1]["text"]) <= MAX_CHARS:
        start -= 1
        total += len(out[start]["text"])
    return out[max(0, min(start, len(out) - 1)):]


def parse_replies(raw):
    """Pull the list of reply strings out of the model's answer (JSON, or a plain list as fallback)."""
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
    replies = []
    for item in items:
        if isinstance(item, dict):
            item = item.get("text", "")
        if not isinstance(item, str):
            continue
        text = item.strip()
        if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'“”":
            text = text[1:-1].strip()
        if text.startswith("“") and text.endswith("”"):
            text = text[1:-1].strip()
        if text:
            replies.append(text[:MAX_REPLY_CHARS])
    return replies


def pick(replies, n):
    """Drop duplicates and stock phrases, keep the first n."""
    seen, out = set(), []
    for r in replies:
        key = re.sub(r"[^\w\s]", "", r.lower()).strip()
        if not key or key in seen or r.lower().strip(" .!") in GENERIC:
            continue
        seen.add(key)
        out.append(r)
    return out[:n]


def model_call(system, user, config):
    return openrouter.chat(
        settings.api_key(),
        config["model"],
        [{"role": "system", "content": system}, {"role": "user", "content": user}],
        provider=config.get("openrouter_provider"),
    )


def suggest_replies(messages, platform="imessage", n=None, tone=None, under_18=False,
                    call=None, config=None):
    """Return a list of up to n reply strings. call(system, user, config) -> raw text can be
    swapped in for tests; by default it calls OpenRouter."""
    config = config or settings.load_config()
    n = n or config.get("replies_per_request", 3)
    if not isinstance(n, int) or not 1 <= n <= 5:
        raise BadRequest("n must be 1 to 5")
    if tone is not None and tone not in TONES:
        raise BadRequest("tone must be one of: " + ", ".join(TONES))
    msgs = clean_messages(messages)
    system = prompts.system_prompt(under_18=bool(under_18))
    user = prompts.user_prompt(msgs, platform, n, tone)
    call = call or model_call
    replies = pick(parse_replies(call(system, user, config)), n)
    if len(replies) < n:   # one retry if the model came back short or malformed
        more = parse_replies(call(system, user, config))
        replies = pick(replies + more, n)
    if not replies:
        raise openrouter.ModelError("The model returned no usable replies")
    return replies


def stand_in_model(system, user, config):
    """Offline fake model for --dry-run and tests: echoes bits of the last match message."""
    last = [l for l in user.splitlines() if l.startswith("MATCH: ")]
    topic = last[-1][len("MATCH: "):][:40] if last else "this"
    return json.dumps({"replies": [
        "[stand-in] wait, %s?" % topic,
        "[stand-in] ok I need the full story on that",
        "[stand-in] haha what are you up to this weekend",
        "[stand-in] fair. coffee sometime?",
    ]})
