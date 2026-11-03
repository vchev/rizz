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


def bub(side, text, page=1, top=100, bottom=None, size=12.0, height=792):
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
    def test_split_bubble_joined_into_one(self):
        msgs = p.clean([
            bub("them", "So I was thinking we could", page=1, top=700, bottom=770),
            bub("them", "go to the lake on Saturday", page=2, top=36, bottom=60),
        ])
        self.assertEqual(msgs, [{"from": "them", "text": "So I was thinking we could go to the lake on Saturday"}])

    def test_overlapping_halves_not_repeated(self):
        msgs = p.clean([
            bub("you", "one two three four", page=1, top=700, bottom=770),
            bub("you", "three four five six", page=2, top=36, bottom=60),
        ])
        self.assertEqual(msgs[0]["text"], "one two three four five six")

    def test_page_header_does_not_block_merge(self):
        msgs = p.clean([
            bub("them", "first half", page=1, top=700, bottom=770),
            bub("center", "Jacob", page=2, top=10, bottom=25),
            bub("them", "second half", page=2, top=36, bottom=58),
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

    def test_small_font_quote_dropped_without_label(self):
        msgs = p.clean([
            bub("them", "want to get dinner friday?", top=100),
            bub("you", "omg", top=130),
            bub("them", "want to get dinner friday?", top=160, size=9.5),
            bub("you", "yes", top=180),
        ])
        self.assertEqual([m["text"] for m in msgs], ["want to get dinner friday?", "omg", "yes"])


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
