"""Reads config.json and the API key. The key comes from the environment or a local .env file."""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_config():
    with open(ROOT / "config.json", encoding="utf-8") as f:
        return json.load(f)


def load_dotenv(path=None):
    """Put KEY=value lines from .env into os.environ (never overrides what is already set)."""
    path = Path(path) if path else ROOT / ".env"
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        os.environ.setdefault(key, value.strip().strip('"').strip("'"))


def api_key():
    load_dotenv()
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not key:
        raise RuntimeError("OPENROUTER_API_KEY is not set (put it in .env or the hosting secrets).")
    return key
