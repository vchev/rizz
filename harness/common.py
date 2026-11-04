"""Shared helpers for the test harness."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"


def load_cases(folder):
    """Test cases are data/conversations/*.json. Files starting with _ are whole threads, skipped."""
    cases = []
    for path in sorted(Path(folder).glob("*.json")):
        if path.name.startswith("_"):
            continue
        with open(path, encoding="utf-8") as f:
            case = json.load(f)
        case.setdefault("id", path.stem)
        cases.append(case)
    return cases


def to_speaker(messages):
    """Test cases use {"from": ...}; the engine and app use {"speaker": ...}."""
    return [{"speaker": m.get("speaker", m.get("from")), "text": m.get("text", "")} for m in messages]


def latest(pattern):
    files = sorted(RESULTS.glob(pattern))
    return files[-1] if files else None
