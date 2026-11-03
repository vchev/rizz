import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import pdf_to_cases as p  # noqa: E402


def bub(side, text, page=1, top=100, bottom=None, size=13.0, height=792):
    return {"page": page, "page_height": height, "side": side, "text": text, "size": size,
            "x0": 40 if side == "them" else 300, "x1": 300 if side == "them" else 570,
            "top": top, "bottom": bottom if bottom is not None else top + 20}


class Receipts(unittest.TestCase):
    def test_real_receipts_dropped(self):
        for t in ["Read", "Read 9:41 PM", "Read Yesterday", "Read Mon 11/2/26", "Read Wednesday",
                  "Read Nov 2 at 9:41 PM", "Delivered", "Edited", "2 Replies"]:
            msgs = p.clean([bub("them", "hello there"), bub("you", t, top=130)])
            self.assertEqual([m["text"] for m in msgs], ["hello there"], t)

    def test_messages_starting_with_read_kept(self):
        for t in ["Read the book yet?", "Read it last night", "Ready when you are", "read 2 chapters lol"]:
            msgs = p.clean([bub("you", t)])
            self.assertEqual([m["text"] for m in msgs], [t])


class PageBreaks(unittest.TestCase):
    def test_bubble_reprinted_on_next_page_kept_once(self):
        # macOS prints the row at a page break on both pages.
        msgs = p.clean([
            bub("them", "So I was thinking we could go to the lake", page=1, top=740, bottom=782),
            bub("them", "So I was thinking we could go to the lake on Saturday", page=2, top=-2, bottom=30),
        ])
        self.assertEqual(msgs, [{"from": "them", "text": "So I was thinking we could go to the lake on Saturday"}])

    def test_clipped_last_word_on_next_page(self):
        msgs = p.clean([
            bub("them", "that suitcase would smell like fish for months", page=1, top=748, bottom=779),
            bub("them", "months", page=2, top=-4, bottom=11),
        ])
        self.assertEqual(len(msgs), 1)

    def test_two_messages_at_a_break_stay_apart(self):
        # Real case: two separate bubbles at the bottom and top of consecutive pages.
        msgs = p.clean([
            bub("you", "Sounds good :)", page=1, top=737, bottom=752),
            bub("you", "My cold got worse today", page=2, top=31, bottom=46),
        ])
        self.assertEqual(len(msgs), 2)

    def test_overlapping_halves_not_repeated(self):
        msgs = p.clean([
            bub("you", "one two three four", page=1, top=700, bottom=770),
            bub("you", "three four five six", page=2, top=36, bottom=60),
        ])
        self.assertEqual(msgs[0]["text"], "one two three four five six")

    def test_page_header_does_not_block_merge(self):
        msgs = p.clean([
            bub("them", "first half and second", page=1, top=700, bottom=770),
            bub("center", "Tue, Aug 18 at 5:14 PM", page=2, top=-7, bottom=5),
            bub("them", "first half and second half", page=2, top=10, bottom=40),
        ])
        self.assertEqual(len(msgs), 1)

    def test_separate_bubbles_not_merged(self):
        msgs = p.clean([
            bub("them", "bubble mid page", page=1, top=400, bottom=420),
            bub("them", "bubble on next page", page=2, top=36, bottom=58),
        ])
        self.assertEqual(len(msgs), 2)


class Repeats(unittest.TestCase):
    def test_real_repeat_kept(self):
        msgs = p.clean([
            bub("them", "good morning!!", top=100),
            bub("you", "hiii", top=130),
            bub("them", "good morning!!", top=160),
        ])
        self.assertEqual([m["text"] for m in msgs], ["good morning!!", "hiii", "good morning!!"])

    def test_threaded_quote_dropped(self):
        msgs = p.clean([
            bub("them", "want to get dinner friday?", top=100),
            bub("them", "1 Reply", top=122),
            bub("them", "also how was the trip", top=150),
            bub("them", "want to get dinner friday?", top=180, size=10.0),
            bub("you", "yes!! friday works", top=200),
        ])
        self.assertEqual([m["text"] for m in msgs],
                         ["want to get dinner friday?", "also how was the trip", "yes!! friday works"])

    def test_link_preview_title_marked(self):
        msgs = p.clean([bub("you", "any bar ideas?", top=40), bub("you", "somewhere quiet", top=70),
                        bub("them", "You might like this:"), bub("them", "8 Great Speakeasies in SF", top=130, size=11.0),
                        bub("them", "instagram.com", top=150, size=10.0)])
        self.assertEqual([m["text"] for m in msgs][2:], ["You might like this:", "[link] 8 Great Speakeasies in SF"])

    def test_quote_dropped_from_old_extract_without_sizes(self):
        msgs = p.clean([dict(bub("them", "want to get dinner friday?"), size=None),
                        dict(bub("them", "1 Reply", top=122), size=None),
                        dict(bub("them", "want to get dinner friday?", top=160), size=None),
                        dict(bub("you", "yes", top=180), size=None)])
        self.assertEqual([m["text"] for m in msgs], ["want to get dinner friday?", "yes"])

    def test_small_font_quote_dropped_without_label(self):
        msgs = p.clean([
            bub("them", "want to get dinner friday?", top=100),
            bub("you", "omg", top=130),
            bub("them", "want to get dinner friday?", top=160, size=9.5),
            bub("you", "yes", top=180),
        ])
        self.assertEqual([m["text"] for m in msgs], ["want to get dinner friday?", "omg", "yes"])


class EmojiKey(unittest.TestCase):
    def test_same_picture_same_id_after_decoding(self):
        import extract_pdf

        class Stream:
            raw = b"compressed"

            def get_rawdata(self):
                return self.raw

            def get_data(self):  # decoding throws the raw bytes away, like pdfminer does
                self.raw = None
                return b"decoded"

        s, cache = Stream(), {}
        first = extract_pdf.emoji_key(s, cache)
        s.get_data()
        self.assertEqual(extract_pdf.emoji_key(s, cache), first)


class CutPoints(unittest.TestCase):
    msgs = [{"from": f, "text": "a fairly long message " + str(i)}
            for i, f in enumerate(["you", "them", "you", "them", "you", "them", "you", "them", "you"])]

    def test_one_case(self):
        self.assertEqual(p.cut_points(self.msgs, 1), [7])

    def test_zero_rejected(self):
        with self.assertRaises(ValueError):
            p.cut_points(self.msgs, 0)

    def test_spread(self):
        self.assertEqual(p.cut_points(self.msgs, 2), [3, 7])


class Output(unittest.TestCase):
    def test_full_thread_goes_in_out_dir(self):
        msgs = CutPoints.msgs
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "data" / "conversations"
            p.write_cases(msgs, "jacob", "imessage", 1, out)
            self.assertTrue((out / "_jacob-full.json").exists())
            self.assertFalse((out.parent / "_jacob-full.json").exists())
            case = json.loads((out / "jacob-01.json").read_text())
            self.assertEqual(case["actual_reply"], ["a fairly long message 8"])

    def test_cli_rejects_bad_count(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "t.json"
            src.write_text("[]")
            r = subprocess.run([sys.executable, str(ROOT / "tools" / "pdf_to_cases.py"), str(src),
                                "x", "imessage", "0", d], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("1 or more", r.stderr)


class MissingPoppler(unittest.TestCase):
    def test_clear_error(self):
        import extract_pdf
        with mock.patch("shutil.which", return_value=None):
            with self.assertRaises(SystemExit) as cm, mock.patch("sys.stderr") as err:
                extract_pdf.run_pdftotext("x.pdf")
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("brew install poppler", "".join(c.args[0] for c in err.write.call_args_list))


class GitIgnore(unittest.TestCase):
    def test_private_paths_ignored(self):
        rules = (ROOT / ".gitignore").read_text().split()
        for rule in [".env", "data/*", "results/", "*.pdf"]:
            self.assertIn(rule, rules)


if __name__ == "__main__":
    unittest.main()
