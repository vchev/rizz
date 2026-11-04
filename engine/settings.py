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


def provider():
    """Which model service to use, from the key that is set: a Claude key wins over OpenRouter."""
    load_dotenv()
    if os.environ.get("ANTHROPIC_API_KEY", "").strip():
        return "anthropic", os.environ["ANTHROPIC_API_KEY"].strip()
    if os.environ.get("OPENROUTER_API_KEY", "").strip():
        return "openrouter", os.environ["OPENROUTER_API_KEY"].strip()
    raise RuntimeError("No model key set: add ANTHROPIC_API_KEY or OPENROUTER_API_KEY "
                       "(in .env or the hosting secrets).")


def api_key():
    return provider()[1]
