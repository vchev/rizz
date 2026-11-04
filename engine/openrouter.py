"""Minimal OpenRouter chat client (standard library only)."""
import json
import urllib.error
import urllib.request

URL = "https://openrouter.ai/api/v1/chat/completions"


class ModelError(Exception):
    pass


def chat(api_key, model, messages, provider=None, temperature=0.9, max_tokens=600, timeout=25):
    """Send chat messages, return the reply text. Raises ModelError on any failure.

    Error messages never include the request (it holds private chats) or the key."""
    body = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "response_format": {"type": "json_object"},
    }
    if provider:
        body["provider"] = provider
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
            "X-Title": "Coax",
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
        raise ModelError("OpenRouter returned %d %s" % (e.code, detail[:200]))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise ModelError("Could not reach OpenRouter: %s" % type(e).__name__)
    try:
        return data["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError):
        raise ModelError("OpenRouter sent an unexpected answer")
