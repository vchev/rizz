"""The web endpoint the iPhone app calls. Keeps the API key on the server.

    POST /api/reply   {"platform": "imessage", "n": 3, "tone": "funny", "under_18": false,
                       "messages": [{"speaker": "them", "text": "...", "reply_to": "..."}],
                       "replying_to": "...",
                       "voice": {"length": 0.2, "caps": 0.1, "humour": 0.8, "emoji": 0.1,
                                 "forward": 0.5, "examples": ["..."]}}
                      (reply_to, replying_to and voice are optional)
    ->  200 {"replies": [{"text": "...", "label": "playful"}], "prompt_version": 9}   (label may be missing)

    GET  /api/reply   -> {"ok": true}   (health check, no model call)

Hosting: Vercel runs the `handler` class below as a serverless function.
On a Mac: `python3 api/reply.py` serves the same thing at http://localhost:8787/api/reply.

Privacy: chats are never written to disk or logs. They go to the model and are forgotten.
If the COAX_APP_TOKEN secret is set, requests must send it in the X-Coax-Token header.
"""
import hmac
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from engine import openrouter, prompts, reply  # noqa: E402

MAX_BODY = 200_000


def handle(body_bytes, token_header=None, call=None):
    """Pure request handling, so it can be tested without a server. Returns (status, dict)."""
    expected = os.environ.get("COAX_APP_TOKEN", "")
    if expected and not hmac.compare_digest((token_header or "").encode(), expected.encode()):
        return 401, {"error": "Not allowed"}
    try:
        data = json.loads(body_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return 400, {"error": "Body must be JSON"}
    if not isinstance(data, dict):
        return 400, {"error": "Body must be a JSON object"}
    try:
        items = reply.suggest_reply_items(
            data.get("messages"),
            platform=data.get("platform") or "imessage",
            n=data.get("n"),
            tone=data.get("tone"),
            under_18=bool(data.get("under_18", False)),
            call=call,
            replying_to=data.get("replying_to"),
            voice=data.get("voice"),
        )
    except reply.BadRequest as e:
        return 400, {"error": str(e)}
    except (openrouter.ModelError, RuntimeError) as e:
        print("reply failed: %s" % e, file=sys.stderr)   # error text only, never the chat
        return 502, {"error": "Couldn't get replies right now. Try again."}
    replies = [{"text": i["text"], "label": i["label"]} if i["label"] else {"text": i["text"]} for i in items]
    return 200, {"replies": replies, "prompt_version": prompts.PROMPT_VERSION}


class handler(BaseHTTPRequestHandler):  # Vercel looks for this exact name
    def _send(self, status, payload):
        out = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(out)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(out)

    def do_GET(self):
        self._send(200, {"ok": True, "prompt_version": prompts.PROMPT_VERSION})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            self._send(413 if length > MAX_BODY else 400, {"error": "Body missing or too large"})
            return
        status, payload = handle(self.rfile.read(length), self.headers.get("X-Coax-Token"))
        self._send(status, payload)

    def log_message(self, fmt, *args):  # keep request details out of logs
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8787"))
    print("Coax reply server on http://localhost:%d/api/reply (Ctrl+C to stop)" % port)
    ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()
