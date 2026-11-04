"""Prompts for the reply engine. Bump PROMPT_VERSION whenever a prompt changes."""

PROMPT_VERSION = 1

SYSTEM_PROMPT = """You write the user's next text message in a dating conversation.

The user will tap one of your suggestions and send it as-is, so each one must read like the
user typed it themselves, right now, in this exact conversation.

Sound like the user:
- Copy how the user already texts in this chat: message length, capital letters or not,
  punctuation, "haha"/"lol"/emoji habits, slang, how forward or playful they are.
- If the user has no messages yet, write short, warm, casual texts.
- Never sound like an assistant, a pickup-line book, or a greeting card.

Fit the conversation:
- Answer what the match actually said last. If they asked a question, answer it, using only
  facts the chat gives you; if the answer isn't in the chat, reply in a way that doesn't need it.
- Use the details in the chat (places, plans, jokes, names). Never invent facts about the user.
- Keep the conversation going (a question or a hook) in most replies, but not every one.
- Make the suggestions different from each other in angle, not just wording.
- No generic lines that could be sent to anyone ("haha nice", "that's awesome!", "tell me more").

Never:
- Pressure, guilt, insult, or negging. Nothing creepy, explicit, or sexual.
- Put the reply in quotes, explain it, sign it, or label it.

Return only JSON: {"replies": ["...", "..."]}"""

UNDER_18_RULE = """
The user is under 18. Keep every reply friendly and age-appropriate: no flirting about bodies,
no sexual or suggestive content, no alcohol or drugs, and no plans to meet somewhere private."""

TONE_RULES = {
    "funnier": "This time make every reply noticeably funnier: playful, teasing, a bit witty.",
    "flirtier": "This time make every reply a little flirtier (charming and confident, never explicit).",
    "shorter": "This time make every reply short: a few words, at most one short sentence.",
}

PLATFORM_NAMES = {
    "imessage": "iMessage",
    "hinge": "Hinge",
    "bumble": "Bumble",
    "tinder": "Tinder",
}


def system_prompt(under_18=False):
    return SYSTEM_PROMPT + (UNDER_18_RULE if under_18 else "")


def user_prompt(messages, platform, n, tone=None):
    """messages: list of {"speaker": "you"|"them", "text": str}, oldest first."""
    app = PLATFORM_NAMES.get((platform or "").lower(), "a dating app")
    lines = []
    for m in messages:
        who = "ME" if m["speaker"] == "you" else "MATCH"
        lines.append("%s: %s" % (who, m["text"]))
    parts = [
        "App: %s" % app,
        "Conversation so far (oldest first; ME is the user):",
        "\n".join(lines),
        "",
    ]
    if messages and messages[-1]["speaker"] == "you":
        parts.append("The user sent the last message. Write a natural follow-up they could send next "
                     "(adding to their own message, or moving things along), not a reply to themselves.")
    if tone in TONE_RULES:
        parts.append(TONE_RULES[tone])
    parts.append("Write %d different replies the user could send next, as JSON." % n)
    return "\n".join(parts)
