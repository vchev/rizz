"""Free web reply tool for the Coax guides site (the Spread lane's "free web reply tool").

    POST /api/try_tool  {"message": "her last message", "context": "optional earlier lines"}
    ->  200 {"reply": "...", "left_today": 2}
    GET  /api/try_tool  -> {"ok": true}

No token (it's public), so it's kept small and cheap:
- one reply, from at most 3 short messages
- always the stricter teen-safe prompt (the site has no age check)
- 3 replies per visitor per day and a daily cap per server instance, kept in memory only
Privacy: nothing pasted is written to disk or logs. The visitor's IP is held in memory as a
one-way hash for the day's count and dropped when the instance restarts.
"""
import hashlib
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from engine import openrouter, reply  # noqa: E402

PER_VISITOR = 3
PER_INSTANCE = int(os.environ.get("COAX_TRY_DAILY_CAP", "300"))
MAX_TEXT = 600
MAX_BODY = 5000

_counts = {}            # (day, visitor hash) -> replies used
_total = {"day": None, "n": 0}


def _today(now=None):
    return time.strftime("%Y-%m-%d", time.gmtime(now or time.time()))


def _visitor(ip):
    return hashlib.sha256(("coax-try:" + (ip or "?")).encode()).hexdigest()[:16]


def handle(body_bytes, ip, call=None, now=None):
    """Returns (status, dict). Pure, so it can be tested."""
    day = _today(now)
    if _total["day"] != day:
        _total.update(day=day, n=0)
        _counts.clear()
    key = (day, _visitor(ip))
    used = _counts.get(key, 0)
    if used >= PER_VISITOR:
        return 429, {"error": "That's 3 free replies today. Get Coax for unlimited replies.", "left_today": 0}
    if _total["n"] >= PER_INSTANCE:
        return 429, {"error": "The free tool is busy today. Try again tomorrow, or get Coax.", "left_today": 0}
    try:
        data = json.loads(body_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return 400, {"error": "Body must be JSON"}
    if not isinstance(data, dict):
        return 400, {"error": "Body must be a JSON object"}
    message = data.get("message")
    context = data.get("context") or ""
    if not isinstance(message, str) or not message.strip():
        return 400, {"error": "Paste the message you want to reply to."}
    if not isinstance(context, str):
        return 400, {"error": "context must be text"}
    if len(message) > MAX_TEXT or len(context) > MAX_TEXT:
        return 400, {"error": "That's a bit long. Paste just the last message or two."}
    msgs = [{"speaker": "them", "text": line} for line in context.splitlines() if line.strip()][-2:]
    msgs.append({"speaker": "them", "text": message})
    try:
        items = reply.suggest_reply_items(msgs, platform="dating app", n=1, under_18=True, call=call)
    except reply.BadRequest as e:
        return 400, {"error": str(e)}
    except (openrouter.ModelError, RuntimeError) as e:
        print("try failed: %s" % e, file=sys.stderr)   # error text only, never the message
        return 502, {"error": "Couldn't get a reply right now. Try again."}
    _counts[key] = used + 1
    _total["n"] += 1
    return 200, {"reply": items[0]["text"], "left_today": PER_VISITOR - used - 1}


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
        self._send(200, {"ok": True})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            self._send(400, {"error": "Body missing or too large"})
            return
        ip = (self.headers.get("X-Forwarded-For") or self.client_address[0] or "").split(",")[0].strip()
        status, payload = handle(self.rfile.read(length), ip)
        self._send(status, payload)

    def log_message(self, fmt, *args):  # keep request details out of logs
        pass
