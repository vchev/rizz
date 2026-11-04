"""Minimal Claude API (Anthropic) client, standard library only.

Used when ANTHROPIC_API_KEY is set. Raw HTTP because the project is standard-library only."""
import json
import urllib.error
import urllib.request

from engine.openrouter import ModelError

URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2026-10-21"   # no temperature/top_p/top_k allowed on this version


def chat(api_key, model, system, user, max_tokens=4000, effort="low", timeout=25):
    """Send one system + user prompt, return the text answer. Raises ModelError.

    Error messages never include the request (it holds private chats) or the key."""
    body = {
        "model": model,
        "max_tokens": max_tokens,
        "system": system,
        "messages": [{"role": "user", "content": user}],
        "output_config": {"effort": effort},
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "x-api-key": api_key,
            "anthropic-version": API_VERSION,
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = json.loads(e.read().decode("utf-8")).get("error", {}).get("message", "")
        except Exception:
            pass
        raise ModelError("Claude API returned %d %s" % (e.code, detail[:200]))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise ModelError("Could not reach the Claude API: %s" % type(e).__name__)
    if data.get("stop_reason") == "refusal":
        raise ModelError("Claude declined this request")
    texts = [b.get("text", "") for b in data.get("content") or [] if b.get("type") == "text"]
    return "".join(texts)
