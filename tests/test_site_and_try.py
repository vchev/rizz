import json
import unittest
from pathlib import Path

from api import try_tool
from tools import build_site


class MarkdownTest(unittest.TestCase):
    def test_basics(self):
        out = build_site.markdown("# Hi\n\nSome **bold** and [a link](/x).\n\n- one\n- two\n\n| a | b |\n| --- | --- |\n| 1 | 2 |")
        self.assertIn("<h1>Hi</h1>", out)
        self.assertIn("<strong>bold</strong>", out)
        self.assertIn('<a href="/x">a link</a>', out)
        self.assertIn("<ul><li>one</li><li>two</li></ul>", out)
        self.assertIn("<td>1</td><td>2</td>", out)

    def test_escapes_html(self):
        self.assertIn("&lt;script&gt;", build_site.markdown("<script>x</script>"))


class BuildTest(unittest.TestCase):
    def test_preview_build_is_noindex_and_skips_drafts(self):
        urls = build_site.build()
        out = build_site.OUT
        self.assertIn("/reply/", urls)
        self.assertFalse(any("rizz" in u for u in urls))   # drafts never published
        self.assertIn("Disallow: /", (out / "robots.txt").read_text())
        self.assertIn('content="noindex"', (out / "index.html").read_text())
        for page in out.rglob("*.html"):
            self.assertNotIn("APPSTORE_LINK", page.read_text())

    def test_domain_build_has_sitemap(self):
        try:
            build_site.build("example.com", "https://apps.apple.com/app/id1")
            out = build_site.OUT
            self.assertIn("https://example.com/guides/", (out / "sitemap.xml").read_text())
            self.assertNotIn("noindex", (out / "index.html").read_text())
        finally:
            build_site.build()   # leave the committed preview build in place


class TryToolTest(unittest.TestCase):
    def setUp(self):
        try_tool._counts.clear()
        try_tool._total.update(day=None, n=0)
        self.seen = []

    def fake(self, system, user, config):
        self.seen.append(system)
        return json.dumps({"replies": [{"text": "Making pasta badly. Best thing you ate this week?"}]})

    def post(self, body, ip="1.2.3.4"):
        return try_tool.handle(json.dumps(body).encode(), ip, call=self.fake)

    def test_reply_and_daily_limit(self):
        for left in (2, 1, 0):
            status, data = self.post({"message": "wyd"})
            self.assertEqual(status, 200)
            self.assertEqual(data["left_today"], left)
        status, data = self.post({"message": "wyd"})
        self.assertEqual(status, 429)
        self.assertEqual(self.post({"message": "wyd"}, ip="5.6.7.8")[0], 200)   # other visitor fine

    def test_rejects_empty_and_long(self):
        self.assertEqual(self.post({"message": " "})[0], 400)
        self.assertEqual(self.post({"message": "x" * 700})[0], 400)
        self.assertEqual(try_tool.handle(b"not json", "1.1.1.1", call=self.fake)[0], 400)

    def test_always_uses_teen_safe_prompt(self):
        from engine import prompts
        self.post({"message": "hey"})
        self.assertEqual(self.seen[0], prompts.system_prompt(under_18=True))


if __name__ == "__main__":
    unittest.main()
