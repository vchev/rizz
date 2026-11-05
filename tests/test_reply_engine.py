import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from api import reply as api  # noqa: E402
from engine import openrouter, prompts, reply  # noqa: E402
from harness import make_review, score  # noqa: E402
from harness.common import load_cases  # noqa: E402

CONFIG = {"model": "test/model", "replies_per_request": 3, "openrouter_provider": {"zdr": True}}
CHAT = [{"speaker": "them", "text": "where was that photo?"}, {"speaker": "you", "text": "mission peak!"},
        {"speaker": "them", "text": "do you hike a lot?"}]


def fake(answer):
    calls = []

    def call(system, user, config):
        calls.append((system, user))
        return answer if isinstance(answer, str) else answer[min(len(calls), len(answer)) - 1]
    call.calls = calls
    return call


class Parsing(unittest.TestCase):
    def test_json(self):
        self.assertEqual(reply.parse_replies('{"replies": ["a b", "c d"]}'), ["a b", "c d"])

    def test_code_fence_and_quotes(self):
        raw = '```json\n{"replies": ["\\"haha yes\\"", "“ok fine”", {"text": "obj form"}]}\n```'
        self.assertEqual(reply.parse_replies(raw), ["haha yes", "ok fine", "obj form"])

    def test_plain_list_fallback(self):
        self.assertEqual(reply.parse_replies("1. first one\n2) second one\n- third"),
                         ["first one", "second one", "third"])

    def test_pick_drops_dupes_and_generic(self):
        self.assertEqual(reply.pick(["Haha nice!", "wait really?", "Wait, really", "coffee?"], 3),
                         ["wait really?", "coffee?"])


    def test_labels_kept_and_cleaned(self):
        raw = ('{"replies": [{"text": "a", "label": "Playful"}, {"text": "b", "label": "way too long a label here"},'
               ' {"text": "c"}, "d", {"text": "e", "label": "<b>x</b>"}]}')
        self.assertEqual([(i["text"], i["label"]) for i in reply.parse_items(raw)],
                         [("a", "playful"), ("b", None), ("c", None), ("d", None), ("e", None)])

    def test_pick_items_keeps_labels(self):
        items = [{"text": "wait really?", "label": "curious"}, {"text": "Wait, really", "label": "x"},
                 {"text": "coffee?", "label": "direct"}]
        self.assertEqual(reply.pick_items(items, 3), [items[0], items[2]])


class Messages(unittest.TestCase):
    def test_accepts_from_and_speaker(self):
        out = reply.clean_messages([{"from": "them", "text": " hi  there "}, {"speaker": "you", "text": "hey"}])
        self.assertEqual(out, [{"speaker": "them", "text": "hi there"}, {"speaker": "you", "text": "hey"}])

    def test_rejects_bad(self):
        for bad in [None, [], [{"speaker": "me", "text": "x"}], [{"speaker": "you"}], ["text"],
                    [{"speaker": "you", "text": "   "}]]:
            with self.assertRaises(reply.BadRequest):
                reply.clean_messages(bad)

    def test_trims_long_threads_keeps_latest(self):
        msgs = [{"speaker": "them", "text": "m%d " % i + "x" * 500} for i in range(200)]
        out = reply.clean_messages(msgs)
        self.assertLessEqual(sum(len(m["text"]) for m in out), reply.MAX_CHARS)
        self.assertTrue(out[-1]["text"].startswith("m199"))

    def test_one_huge_message_still_sent(self):
        out = reply.clean_messages([{"speaker": "them", "text": "y" * 20000}])
        self.assertEqual(len(out), 1)


class Prompts(unittest.TestCase):
    def test_user_prompt(self):
        p = prompts.user_prompt(reply.clean_messages(CHAT), "hinge", 3, "funny")
        self.assertIn("App: Hinge", p)
        self.assertIn("MATCH: do you hike a lot?", p)
        self.assertIn("ME: mission peak!", p)
        self.assertIn("every reply is funny", p)
        self.assertIn("3 different replies", p)

    def test_last_message_mine(self):
        p = prompts.user_prompt([{"speaker": "you", "text": "so anyway"}], "imessage", 3)
        self.assertIn("The user sent the last message", p)

    def test_quoted_reply_leaves_a_later_compliment_unanswered(self):
        # Vanessa's Bumble chat with Chai (Nov 4): her last message quotes his older one,
        # so his compliment after it still needs an answer.
        chat = reply.clean_messages([
            {"speaker": "you", "text": "So it's dependent on who updates their app"},
            {"speaker": "them", "text": "Maybe. Not necessary. Sometimes it's just an experiment variant",
             "reply_to": "So it's dependent on who updates thei..."},
            {"speaker": "them", "text": "Btw! I'm sure you get this a lot but your have a really nice smile"},
            {"speaker": "you", "text": "Ohh that's true!", "reply_to": "Maybe. Not necessary. Sometimes it's j\u2026"},
        ])
        self.assertEqual(prompts.unanswered_match_messages(chat),
                         ["Btw! I'm sure you get this a lot but your have a really nice smile"])
        p = prompts.user_prompt(chat, "bumble", 3)
        self.assertIn("still unanswered", p)
        self.assertIn('ME (quoting MATCH: "Maybe. Not necessary.', p)
        self.assertNotIn("The user sent the last message", p)

    def test_plain_last_message_mine_has_nothing_unanswered(self):
        chat = [{"speaker": "them", "text": "hi"}, {"speaker": "you", "text": "hey!"}]
        self.assertEqual(prompts.unanswered_match_messages(chat), [])

    def test_replying_to_bar(self):
        p = prompts.user_prompt([{"speaker": "them", "text": "nice smile"}, {"speaker": "you", "text": "haha"}],
                                "bumble", 3, replying_to="nice smile")
        self.assertIn('replying to this message from the match: "nice smile"', p)

    def test_under_18(self):
        self.assertIn("under 18", prompts.system_prompt(under_18=True))
        self.assertNotIn("under 18", prompts.system_prompt())


class Suggest(unittest.TestCase):
    def test_returns_n(self):
        call = fake('{"replies": ["one thing", "two things", "three things", "four"]}')
        self.assertEqual(reply.suggest_replies(CHAT, n=3, call=call, config=CONFIG),
                         ["one thing", "two things", "three things"])
        self.assertEqual(len(call.calls), 1)

    def test_retries_when_short(self):
        call = fake(['{"replies": ["only one"]}', '{"replies": ["only one", "second", "third"]}'])
        self.assertEqual(reply.suggest_replies(CHAT, call=call, config=CONFIG), ["only one", "second", "third"])
        self.assertEqual(len(call.calls), 2)

    def test_nothing_usable_is_error(self):
        with self.assertRaises(openrouter.ModelError):
            reply.suggest_replies(CHAT, call=fake(""), config=CONFIG)

    def test_bad_tone_and_n(self):
        with self.assertRaises(reply.BadRequest):
            reply.suggest_replies(CHAT, tone="meaner", call=fake("{}"), config=CONFIG)
        with self.assertRaises(reply.BadRequest):
            reply.suggest_replies(CHAT, n=50, call=fake("{}"), config=CONFIG)

    def test_moods_and_old_tone_names(self):
        seen = []
        def spy(system, user, config):
            seen.append(user)
            return reply.stand_in_model(system, user, config)
        for tone in reply.TONES:
            reply.suggest_replies(CHAT, tone=tone, call=spy, config=CONFIG)
        reply.suggest_replies(CHAT, tone="funnier", call=spy, config=CONFIG)
        reply.suggest_replies(CHAT, tone="flirtier", call=spy, config=CONFIG)
        self.assertIn("every reply is sweet", seen[2])
        self.assertIn("every reply is funny", seen[-2])
        self.assertIn("every reply is flirty", seen[-1])

    def test_default_asks_for_different_moods(self):
        self.assertIn("give each reply a different mood", prompts.system_prompt())

    def test_model_call_sends_zdr(self):
        with mock.patch.object(reply.settings, "provider", return_value=("openrouter", "k")), \
                mock.patch.object(openrouter, "chat", return_value='{"replies": []}') as chat:
            reply.model_call("sys", "usr", CONFIG)
        self.assertEqual(chat.call_args.kwargs["provider"], {"zdr": True})
        self.assertEqual(chat.call_args.args[1], "test/model")


    def test_claude_key_uses_claude_api(self):
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "a", "OPENROUTER_API_KEY": "o"}):
            self.assertEqual(reply.settings.provider(), ("anthropic", "a"))
        cfg = dict(CONFIG, anthropic_model="claude-haiku-5-5")
        with mock.patch.object(reply.settings, "provider", return_value=("anthropic", "k")), \
                mock.patch.object(reply.anthropic_api, "chat", return_value="{}") as chat:
            reply.model_call("sys", "usr", cfg)
        self.assertEqual(chat.call_args.args[:4], ("k", "claude-haiku-5-5", "sys", "usr"))

    def test_claude_request_shape(self):
        sent = {}

        class Resp:
            def __enter__(self):
                return self

            def __exit__(self, *a):
                pass

            def read(self):
                return json.dumps({"stop_reason": "end_turn", "content": [
                    {"type": "thinking", "thinking": ""}, {"type": "text", "text": '{"replies": ["hi"]}'}]}).encode()

        def urlopen(req, timeout):
            sent["body"] = json.loads(req.data)
            sent["headers"] = dict(req.header_items())
            return Resp()
        from engine import anthropic_api
        with mock.patch.object(anthropic_api.urllib.request, "urlopen", urlopen):
            out = anthropic_api.chat("k", "claude-haiku-5-5", "sys", "usr")
        self.assertEqual(out, '{"replies": ["hi"]}')
        self.assertNotIn("temperature", sent["body"])
        self.assertEqual(sent["body"]["system"], "sys")
        self.assertEqual(sent["headers"]["Anthropic-version"], "2026-10-21")


class Api(unittest.TestCase):
    def body(self, **kw):
        d = {"platform": "imessage", "n": 3, "messages": CHAT}
        d.update(kw)
        return json.dumps(d).encode()

    def test_ok_matches_app_contract(self):
        status, out = api.handle(self.body(tone="shorter"), call=reply.stand_in_model)
        self.assertEqual(status, 200)
        self.assertEqual(len(out["replies"]), 3)
        self.assertTrue(all(set(r) <= {"text", "label"} and "text" in r for r in out["replies"]))
        self.assertEqual([r.get("label") for r in out["replies"]], ["playful", "sweet", "flirty"])

    def test_bad_json_and_bad_messages(self):
        self.assertEqual(api.handle(b"nope")[0], 400)
        self.assertEqual(api.handle(self.body(messages=[]))[0], 400)

    def test_model_failure_is_502_without_details(self):
        def boom(*a):
            raise openrouter.ModelError("OpenRouter returned 401 secret stuff")
        status, out = api.handle(self.body(), call=boom)
        self.assertEqual(status, 502)
        self.assertNotIn("secret", out["error"])

    def test_token(self):
        with mock.patch.dict(os.environ, {"COAX_APP_TOKEN": "abc"}):
            self.assertEqual(api.handle(self.body(), None, call=reply.stand_in_model)[0], 401)
            self.assertEqual(api.handle(self.body(), "abc", call=reply.stand_in_model)[0], 200)

    def test_real_server_round_trip(self):
        import threading
        import urllib.request
        from http.server import ThreadingHTTPServer
        srv = ThreadingHTTPServer(("127.0.0.1", 0), api.handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            url = "http://127.0.0.1:%d/api/reply" % srv.server_address[1]
            with mock.patch.object(reply, "model_call", reply.stand_in_model):
                req = urllib.request.Request(url, data=self.body(), headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(req) as r:
                    self.assertEqual(len(json.loads(r.read())["replies"]), 3)
            with urllib.request.urlopen(url) as r:
                self.assertTrue(json.loads(r.read())["ok"])
        finally:
            srv.shutdown()
            srv.server_close()


class Harness(unittest.TestCase):
    def test_review_and_score(self):
        cases = {c["id"]: c for c in load_cases(ROOT / "tests" / "fixtures")}
        run = {"name": "run-x", "cases": [{"id": "sample-01", "replies": ["a <b>", "c"], "error": None}]}
        page = make_review.build(run, cases)
        self.assertIn("a &lt;b&gt;", page)
        self.assertIn('data-source="actual"', page)
        ratings = [{"source": "engine", "rating": "as_is"}, {"source": "engine", "rating": "no"},
                   {"source": "engine", "rating": "small_edit"}, {"source": "actual", "rating": "as_is"},
                   {"source": "engine", "rating": None}]
        s = score.score(ratings, 0.5)
        self.assertEqual(s["engine"]["rated"], 3)
        self.assertTrue(s["passes"])
        self.assertEqual(s["actual"]["rate"], 1.0)

    def test_dry_run(self):
        from harness import run_eval
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "run.json"
            self.assertEqual(run_eval.main(["--dry-run", "--conversations", str(ROOT / "tests" / "fixtures"),
                                            "--out", str(out)]), 0)
            data = json.loads(out.read_text())
            self.assertEqual(len(data["cases"]), 2)
            self.assertTrue(all(len(c["replies"]) == 3 for c in data["cases"]))


if __name__ == "__main__":
    unittest.main()


class VoiceProfile(unittest.TestCase):
    MSGS = [{"speaker": "them", "text": "how was your week"}]

    def test_no_voice_keeps_prompt_unchanged(self):
        base = prompts.user_prompt(self.MSGS, "hinge", 3)
        self.assertEqual(base, prompts.user_prompt(self.MSGS, "hinge", 3, voice=None))
        self.assertEqual(base, prompts.user_prompt(self.MSGS, "hinge", 3, voice={}))
        # all sliders in the middle and no examples: nothing to say, prompt unchanged
        middle = {k: 0.5 for k in prompts.VOICE_SLIDERS}
        self.assertEqual(base, prompts.user_prompt(self.MSGS, "hinge", 3, voice=middle))

    def test_sliders_become_plain_words(self):
        text = prompts.user_prompt(self.MSGS, "hinge", 3, voice={
            "length": 0.1, "caps": 0.0, "humour": 0.9, "emoji": 0.5, "forward": True})
        self.assertIn("very short texts", text)
        self.assertIn("mostly lowercase", text)
        self.assertIn("dry, teasing humour", text)
        self.assertNotIn("emoji", text)          # middle value says nothing
        self.assertNotIn("openly keen", text)    # booleans are ignored
        self.assertLess(text.index("voice profile"), text.index("Conversation so far"))

    def test_examples_trimmed_and_deduped(self):
        examples = ["haha wait  that's impressive", "haha wait that's impressive"] + ["x%d" % i for i in range(20)]
        lines = prompts.voice_lines({"examples": examples + [5, None]})
        mine = [l for l in lines if l.startswith("ME: ")]
        self.assertEqual(len(mine), prompts.MAX_VOICE_EXAMPLES)
        self.assertEqual(mine[0], "ME: haha wait that's impressive")
        self.assertIn("never the content", "\n".join(lines))

    def test_voice_reaches_the_model_through_the_api(self):
        seen = {}

        def fake(system, user, config):
            seen["user"] = user
            return reply.stand_in_model(system, user, config)

        body = json.dumps({"messages": self.MSGS, "voice": {"length": 0.0, "examples": ["ok fair"]}})
        status, out = api.handle(body.encode(), call=fake)
        self.assertEqual(status, 200)
        self.assertIn("ME: ok fair", seen["user"])
        self.assertIn("very short texts", seen["user"])

    def test_bad_voice_is_a_400(self):
        body = json.dumps({"messages": self.MSGS, "voice": "short"})
        status, out = api.handle(body.encode(), call=reply.stand_in_model)
        self.assertEqual(status, 400)
