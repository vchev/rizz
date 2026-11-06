"""Prompts for the reply engine. Bump PROMPT_VERSION whenever a prompt changes."""

PROMPT_VERSION = 10

SYSTEM_PROMPT = """You write the user's next text message in a dating conversation.

The user will tap one of your suggestions and send it as-is, so each one must read like the
user typed it themselves, right now, in this exact conversation.

Sound like the user:
- Copy how the user already texts in this chat: message length, capital letters or not,
  punctuation, "haha"/"lol"/emoji habits, slang, how forward or playful they are.
- If the user has no messages yet, write short, warm, casual texts.
- Never sound like an assistant, a pickup-line book, or a greeting card.

The conversation was read from screenshots, so it can contain junk that is not a message:
app buttons and prompts ("Aa", "Type a message", "Ask them out", "Your turn", "Send a like"),
names, times, or garbled fragments. Ignore anything that doesn't read like a real text, and
never reply to it or mention it.

Fit the conversation:
- Reply to the match's LATEST message(s), the ones after the user's last message. Earlier
  questions that were already answered are done; don't go back to them.
- If the match asked a question, every reply answers it directly, first. Never dodge,
  deflect, or answer a question with a question.
- If the answer needs a fact the chat doesn't give (when the user is free, what they do, where
  they live), give a natural, specific answer anyway that the user can quickly edit, and vary
  it across the replies (e.g. "weekends are best for me, saturday morning?", "weeknights after
  7 usually"). Never make up big facts (job, age, relationships, past events).
- Keep straight who is who. What ME said, did, or has belongs to the user; what MATCH said,
  did, or has belongs to the match. If the match asks how the user's thing went (their
  appointment, trip, day), answer as the user about their own thing. Never swap these.
- Use what the chat already says about the user (if they said they're sick, busy, or traveling,
  that is still true unless the chat says otherwise).
- Don't invent stories about the user's life: no made-up events, numbers, people, places they
  went, or things they bought. If the answer needs facts about the user's past that the chat
  doesn't give, keep it short and plain ("yes finally!", "it turned out fine") so it's true or
  easy to edit. Availability and plans are the exception above.
- A simple question gets a simple answer. Match the size of the reply to the size of the
  match's message.
- If the match suggests meeting or asks about plans, treat it as good news: say yes in a way
  that moves toward an actual plan, unless the chat shows the user doesn't want to.
- Once a plan is already agreed, don't steer back to it: don't mention it, confirm it again,
  or ask "still down for ...?". Only talk logistics if the match brings them up. Stay with what the match just said: if they're joking or sharing something,
  play along or react to that.
- Use the details in the chat (places, plans, jokes, names).
- Keep the conversation going (a question or a hook) in most replies, but not every one.
  A question must be one this person would naturally ask right now, about what the match just
  said. Never ask the match about the user's own thing (if the user got a lash lift, don't ask
  the match about their lash lifts). If no natural question fits, end without one.
- Make the suggestions different from each other in angle, not just wording.
- No generic lines that could be sent to anyone ("haha nice", "that's awesome!", "tell me more").

Never:
- Pressure, guilt, insult, or negging. Nothing creepy, explicit, or sexual.
- Put the reply in quotes, explain it, sign it, or put a label inside the text.

Return only JSON: {"replies": [{"text": "...", "label": "..."}, ...]}
"label" is the reply's mood, one plain lowercase word from: playful, flirty, sweet, chill, bold,
funny. It is shown as a small tag next to the reply and is never sent. Unless told otherwise,
give each reply a different mood, and make each reply really sound like its mood."""

UNDER_18_RULE = """
The user is under 18. Keep every reply friendly and age-appropriate: no flirting about bodies,
no sexual or suggestive content, no alcohol or drugs, and no plans to meet somewhere private."""

TONE_RULES = {
    "funny": "This time every reply is funny: playful, teasing, a bit witty. Label each \"funny\".",
    "flirty": "This time every reply is flirty: charming and confident, never explicit. Label each \"flirty\".",
    "sweet": "This time every reply is sweet: warm, kind, a little affectionate. Label each \"sweet\".",
    "chill": "This time every reply is chill: relaxed, easygoing, low-key, no pressure. Label each \"chill\".",
    "bold": "This time every reply is bold: direct and confident, says what the user wants (still kind, "
            "never pushy). Label each \"bold\".",
    "shorter": "This time make every reply short: a few words, at most one short sentence. "
               "Keep the different moods.",
}

# The user's voice profile (optional, sent by the app). Each slider is 0..1; the middle third
# says nothing, so a half-way answer never pushes the replies either way.
VOICE_SLIDERS = {
    "length": ("very short texts, often just a few words", "longer texts, often a few sentences"),
    "caps": ("mostly lowercase, light on punctuation", "proper capital letters and punctuation"),
    "humour": ("sincere and straightforward", "dry, teasing humour"),
    "emoji": ("almost never uses emoji", "uses emoji often"),
    "forward": ("plays it cool, never over-eager", "says what they feel, openly keen"),
}
MAX_VOICE_EXAMPLES = 8


def voice_lines(voice):
    """Plain-word lines describing how the user texts, from the app's voice profile.
    Returns [] when there is nothing useful, so the prompt stays exactly as before."""
    if not isinstance(voice, dict):
        return []
    traits = []
    for key, (low, high) in VOICE_SLIDERS.items():
        value = voice.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        if value <= 1 / 3:
            traits.append(low)
        elif value >= 2 / 3:
            traits.append(high)
    examples = []
    for text in voice.get("examples") or []:
        if isinstance(text, str):
            text = " ".join(text.split())[:200]
            if text and text not in examples:
                examples.append(text)
    examples = examples[:MAX_VOICE_EXAMPLES]
    if not traits and not examples:
        return []
    lines = ["How the user texts (their voice profile; if this chat shows their style, the chat wins):"]
    lines += ["- %s" % t for t in traits]
    if examples:
        lines.append("Texts the user wrote in other chats (copy the style only, never the content):")
        lines += ["ME: %s" % t for t in examples]
    lines.append("")
    return lines


PLATFORM_NAMES = {
    "imessage": "iMessage",
    "hinge": "Hinge",
    "bumble": "Bumble",
    "tinder": "Tinder",
}


def system_prompt(under_18=False):
    return SYSTEM_PROMPT + (UNDER_18_RULE if under_18 else "")


def _norm(text):
    return " ".join("".join(c.lower() if c.isalnum() else " " for c in text).split())


def _quoted_index(messages, before, quote):
    """Index of the earlier message that `quote` (a shortened copy) comes from, or None."""
    q = _norm(quote.rstrip(".…"))
    if len(q) < 4:
        return None
    for i in range(before - 1, -1, -1):
        if _norm(messages[i]["text"]).startswith(q) or q.startswith(_norm(messages[i]["text"])):
            return i
    return None


def unanswered_match_messages(messages):
    """Match messages still waiting for an answer although the user sent the last message.

    Happens with quoted replies: the user's last message answers an older match message
    (it quotes it), so a match message sent after that one is still unanswered.
    """
    if not messages or messages[-1]["speaker"] != "you":
        return []
    answered = set()
    for i, m in enumerate(messages):
        if m["speaker"] != "you":
            continue
        j = _quoted_index(messages, i, m["reply_to"]) if m.get("reply_to") else None
        if j is not None and messages[j]["speaker"] == "them":
            answered.add(j)          # a quoted reply answers just that message
        else:
            answered.update(k for k in range(i) if messages[k]["speaker"] == "them")
    return [m["text"] for k, m in enumerate(messages) if m["speaker"] == "them" and k not in answered]


# Moods a reply can be labelled with (the "label" in the JSON).
MOODS = ("playful", "flirty", "sweet", "chill", "bold", "funny")


def user_prompt(messages, platform, n, tone=None, replying_to=None, voice=None, favorite_mood=None):
    """messages: list of {"speaker": "you"|"them", "text": str, "reply_to": str?}, oldest first."""
    app = PLATFORM_NAMES.get((platform or "").lower(), "a dating app")
    lines = []
    for m in messages:
        who = "ME" if m["speaker"] == "you" else "MATCH"
        if m.get("reply_to"):
            other = "MATCH" if who == "ME" else "ME"
            lines.append('%s (quoting %s: "%s"): %s' % (who, other, m["reply_to"], m["text"]))
        else:
            lines.append("%s: %s" % (who, m["text"]))
    parts = [
        "App: %s" % app,
    ] + voice_lines(voice) + [
        "Conversation so far (oldest first; ME is the user; \"quoting\" means a reply to that earlier message):",
        "\n".join(lines),
        "",
    ]
    waiting = unanswered_match_messages(messages)
    if replying_to:
        parts.append('The user is replying to this message from the match: "%s". Every reply answers '
                     "that message." % replying_to)
    elif waiting:
        parts.append("The user's last message answered an older message, so the match's message(s) "
                     "below are still unanswered. Every reply answers them (not the user's own message):\n"
                     + "\n".join("MATCH: %s" % t for t in waiting))
    elif messages and messages[-1]["speaker"] == "you":
        parts.append("The user sent the last message. Write a natural follow-up they could send next "
                     "(adding to their own message, or moving things along), not a reply to themselves.")
    if tone in TONE_RULES:
        parts.append(TONE_RULES[tone])
    elif favorite_mood in MOODS and n > 1:
        parts.append('The user most often picks "%s" replies, so make one of the replies %s.'
                     % (favorite_mood, favorite_mood))
    parts.append("Write %d different replies the user could send next, as JSON." % n)
    return "\n".join(parts)
