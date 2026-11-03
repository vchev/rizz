"""Clean extracted bubbles and cut a thread into test cases.

Each case = the conversation up to a moment where the match wrote and the
user replied next. The user's real reply is kept as "actual_reply" (never
shown to the model) so generated replies can be compared with it later.

Usage: python3 tools/pdf_to_cases.py thread.json <name> imessage <num_cases> data/conversations
Writes <name>-01.json ... plus _<name>-full.json (the whole thread), all in the
output folder. Standard library only.
"""
import json
import re
import statistics
import sys
from pathlib import Path

EMOJI = {
    "08851096": "🤷‍♂️", "0f4c5c45": "🤦‍♀️", "17a0ddec": "🏋️‍♀️", "2fa50618": "🫠", "49fa4c9e": "🙁",
    "4d1e20ae": "🤔", "5b6dd63d": "💁‍♀️", "5b6da6da": "😢", "5bef788f": "😅", "6586ac57": "🥹",
    "66153367": "🥲", "680f1532": "😤", "6f4c4dc6": "😒", "6fabc681": "🙅‍♀️", "7267f8ef": "😬",
    "8ba447c8": "😃", "8fa457ee": "😊", "91fd4bc1": "😳", "924ec772": "😭", "97ded2a9": "🥲",
    "9c354d5a": "🍝", "a1da9ada": "🦞", "a57b40b3": "😥", "a9ddef7a": "😮‍💨", "b1e2f815": "💁‍♀️",
    "b2ee6096": "🫠", "b8a1831d": "☺️", "b96d5573": "😉", "b9eaeb13": "😤", "c2f45349": "🤗",
    "cc6454c2": "🙅‍♀️", "cd747962": "👀", "d342ea40": "😂", "d3b26e88": "🥺", "d6645696": "😳",
    "dbfe23a6": "😢", "de8a5c3f": "😆", "ef7b951f": "😁", "f11c7930": "😏", "f361273b": "😓",
    # Added 2026-11-03 from the Jacob, Avi, Sebastian and Brad threads.
    "2cbce222": "🫣", "36bca746": "🤣", "6bf26205": "😌", "7faa1d39": "🙈", "015f6238": "🏃‍♀️",
    "97dc743b": "🙌", "ef2db2e2": "❌", "02716924": "🥸", "cf93ef08": "🙃", "57e3cfad": "🤓",
    "6d743f23": "😵‍💫", "12c0f619": "😜", "8b350389": "🤩", "d19fa89b": "😴", "4a04f8ed": "🤷‍♀️",
}

# "Read" only counts as a receipt when everything after it is a time or date
# ("Read 9:41 PM", "Read Yesterday", "Read Mon 11/2/26"). "Read the book?" is a message.
_WHEN = (r"(today|yesterday|at|[ap]\.?m\.?|"
         r"(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(day|nesday|rsday|urday)?\.?|"
         r"(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?|"
         r"[\d/:.,-]+)")
LABEL = re.compile(r"^(Replay|Delivered( Quietly)?|(?-i:Read)(\s+" + _WHEN + r")*|Edited|Kept|Not Delivered"
                   r"|Sent as Text Message)$", re.I)
REPLIES = re.compile(r"^\d+ Repl(y|ies)$", re.I)       # printed under a message that has a threaded reply
DOMAIN = re.compile(r"^[\w-]+(\.[\w-]+)+$")          # link-preview captions like youtube.com
PHONE = re.compile(r"\(?\b\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}\b")
ADDRESS = re.compile(r"\b\d{2,5}\s+\w+(\s\w+)?\s(st|street|ave|avenue|blvd|rd|road|way|dr|drive|ln|lane)\b\.?", re.I)

PAGE_HEIGHT = 792   # US Letter, used when the extract has no page_height
EDGE = 60           # points from the top/bottom of a page that count as "at the page break"
# Font size relative to normal bubbles (13pt in macOS Messages prints). Measured on 4 real
# threads: quoted copies above threaded replies, "N Replies", "Edited" and link domains are
# 10pt (0.77); link-preview titles are 11pt (0.85).
SMALL = 0.8
LINK_TITLE = 0.95

def normalize(text):
    t = re.sub(r"\{E:([0-9a-f]{8})\}", lambda m: EMOJI.get(m.group(1), ""), text)
    t = t.replace("{E:?}", "")
    t = PHONE.sub("[phone]", t)
    t = ADDRESS.sub("[address]", t)
    return re.sub(r"\s+", " ", t).strip()


def merge_split(first, second):
    """Join the two halves of a bubble cut by a page break, or return None if they don't overlap.

    macOS prints the row at a page break on both pages, so a split bubble's halves always share
    text. Two separate bubbles that happen to sit at the break share none and stay apart.
    """
    if first == second:
        return first
    short, long_ = sorted((first, second), key=len)
    if long_.startswith(short) or long_.endswith(short) or (len(short) >= 8 and short in long_):
        return long_
    a, b = first.split(" "), second.split(" ")
    for k in range(min(len(a), len(b)), 1, -1):  # longest run of 2+ words that ends a and starts b
        if a[-k:] == b[:k]:
            return " ".join(a + b[k:])
    return None


def _same_or_truncated(quote, original):
    if quote == original:
        return True
    q = quote.rstrip("…").rstrip(".").rstrip()
    return quote != q and len(q) > 5 and original.startswith(q)


def clean(bubbles):
    sizes = [b["size"] for b in bubbles if b.get("size") and b["side"] != "center"]
    body_size = statistics.median(sizes) if sizes else None
    msgs = []
    last = None        # (bubble, index in msgs) of the previous kept bubble, for page-break merges
    threaded = []      # messages marked "N Replies": a quoted copy of each shows up later
    for b in bubbles:
        raw = b["text"].strip()
        h = b.get("page_height") or PAGE_HEIGHT
        if REPLIES.match(raw):
            if msgs:
                threaded.append(msgs[-1]["text"])
            continue
        if b["side"] == "center":
            # A timestamp between bubbles ends a run; a page header or footer does not.
            if EDGE <= b["top"] and b["bottom"] <= h - EDGE:
                last = None
            continue
        t = normalize(raw)
        if not t or LABEL.match(t) or DOMAIN.match(t):
            continue
        rel = b["size"] / body_size if body_size and b.get("size") else None
        if rel is not None and rel < SMALL:
            # Quoted copy above a threaded reply (or a label/domain): never a new message.
            continue
        if rel is not None and rel < LINK_TITLE:
            t = "[link] " + t
        # A bubble straddling a page break comes out as two blocks that overlap.
        if last is not None:
            pb, idx = last
            ph = pb.get("page_height") or PAGE_HEIGHT
            if (pb["side"] == b["side"] and b["page"] == pb["page"] + 1
                    and pb["bottom"] > ph - EDGE and b["top"] < EDGE):
                merged = merge_split(msgs[idx]["text"], t)
                if merged is not None:
                    msgs[idx]["text"] = merged
                    last = (b, idx)
                    continue
        # Without font sizes, fall back to the "N Replies" label to spot a quoted copy, so a
        # message someone really sent twice is kept.
        if rel is None:
            recent = [m["text"] for m in msgs[-6:]]
            match = next((r for r in reversed(recent) if _same_or_truncated(t, r)), None)
            if match is not None and match in threaded:
                threaded.remove(match)
                last = None
                continue
        msgs.append({"from": b["side"], "text": t})
        last = (b, len(msgs) - 1)
    return msgs


def cut_points(msgs, want, min_context=4):
    """Indices i where msgs[i] is the match and msgs[i+1] is the user, spread across the thread."""
    if want < 1:
        raise ValueError("num_cases must be 1 or more")
    pts = []
    for i in range(min_context - 1, len(msgs) - 1):
        if msgs[i]["from"] == "them" and msgs[i + 1]["from"] == "you":
            # How much the match said in this turn (consecutive 'them' messages ending at i).
            j, said = i, 0
            while j >= 0 and msgs[j]["from"] == "them":
                said += len(msgs[j]["text"])
                j -= 1
            if said >= 15:
                pts.append(i)
    if len(pts) <= want:
        return pts
    if want == 1:
        return [pts[-1]]  # the moment with the most context
    step = (len(pts) - 1) / (want - 1)
    return sorted({pts[round(k * step)] for k in range(want)})


def write_cases(msgs, name, app, want, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    # The full thread stays next to the cases (git-ignored); the leading _ keeps it out of test runs.
    full = out_dir / "_{}-full.json".format(name)
    full.write_text(json.dumps({"id": "_{}-full".format(name), "app": app, "messages": msgs},
                               ensure_ascii=False, indent=1))
    pts = cut_points(msgs, want)
    for k, i in enumerate(pts, start=1):
        # The user's real next reply: consecutive 'you' messages after the cut.
        actual, j = [], i + 1
        while j < len(msgs) and msgs[j]["from"] == "you":
            actual.append(msgs[j]["text"])
            j += 1
        case = {"id": "{}-{:02d}".format(name, k), "app": app, "match": "", "profile_notes": "",
                "messages": msgs[: i + 1], "actual_reply": actual,
                "source": "{} thread, messages 1-{} of {}".format(name, i + 1, len(msgs))}
        (out_dir / "{}-{:02d}.json".format(name, k)).write_text(json.dumps(case, ensure_ascii=False, indent=1))
    return pts


def main(argv):
    if len(argv) != 6:
        sys.exit("usage: python3 tools/pdf_to_cases.py thread.json <name> <app> <num_cases> <out_dir>")
    src, name, app, want, out_dir = argv[1], argv[2], argv[3], argv[4], Path(argv[5])
    if not want.isdigit() or int(want) < 1:
        sys.exit("num_cases must be a whole number, 1 or more (got {!r})".format(want))
    msgs = clean(json.loads(Path(src).read_text()))
    pts = write_cases(msgs, name, app, int(want), out_dir)
    you = sum(m["from"] == "you" for m in msgs)
    print("{}: {} messages ({} yours), {} test cases in {}".format(name, len(msgs), you, len(pts), out_dir))


if __name__ == "__main__":
    main(sys.argv)
