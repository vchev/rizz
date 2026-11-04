"""Gate 1 result from a ratings file downloaded from the review page.

    python3 harness/score.py                       # newest ratings-*.json in results/ or Downloads
    python3 harness/score.py ~/Downloads/ratings-run-20261110-120000.json

Would-send = "Send as-is" + "Send with a small edit". Gate 1 passes when the engine's
would-send rate is above gate1_would_send_rate_must_exceed in config.json.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from engine import settings  # noqa: E402
from harness.common import RESULTS  # noqa: E402

WOULD_SEND = ("as_is", "small_edit")


def find_latest():
    files = list(RESULTS.glob("ratings-*.json")) + list((Path.home() / "Downloads").glob("ratings-*.json"))
    return max(files, key=lambda p: p.stat().st_mtime) if files else None


def score(ratings, threshold):
    out = {}
    for source in ("engine", "actual"):
        rated = [r for r in ratings if r["source"] == source and r.get("rating")]
        sent = [r for r in rated if r["rating"] in WOULD_SEND]
        out[source] = {"rated": len(rated), "would_send": len(sent),
                       "as_is": sum(r["rating"] == "as_is" for r in rated),
                       "rate": (len(sent) / len(rated)) if rated else None}
    rate = out["engine"]["rate"]
    out["passes"] = rate is not None and rate > threshold
    out["threshold"] = threshold
    return out


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    path = Path(argv[0]).expanduser() if argv else find_latest()
    if not path or not path.exists():
        print("No ratings file found. Press 'Download ratings' on the review page first.")
        return 1
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    threshold = settings.load_config()["gate1_would_send_rate_must_exceed"]
    s = score(data["ratings"], threshold)
    e, a = s["engine"], s["actual"]
    if not e["rated"]:
        print("No engine replies rated yet.")
        return 1
    print("Ratings file: %s" % path)
    print("Engine replies: %d rated, %d you'd send (%d as-is) = %.0f%%"
          % (e["rated"], e["would_send"], e["as_is"], 100 * e["rate"]))
    if a["rated"]:
        print("Your real replies (hidden control): %d rated, %.0f%% you'd send" % (a["rated"], 100 * a["rate"]))
    print("Gate 1 (needs more than %.0f%%): %s" % (100 * threshold, "PASS" if s["passes"] else "NOT YET"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
