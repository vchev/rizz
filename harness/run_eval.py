"""Generate replies for every test case and save them to results/run-<time>.json.

    python3 harness/run_eval.py --dry-run --conversations tests/fixtures   # offline, stand-in model
    python3 harness/run_eval.py --limit 3                                  # real run, needs .env
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from engine import openrouter, prompts, reply, settings  # noqa: E402
from harness.common import RESULTS, ROOT, load_cases, to_speaker  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--conversations", default=str(ROOT / "data" / "conversations"))
    ap.add_argument("--limit", type=int, default=0, help="only the first N cases")
    ap.add_argument("--dry-run", action="store_true", help="use a fake model, no key or internet needed")
    ap.add_argument("--under-18", action="store_true", help="test the under-18 mode")
    ap.add_argument("--out", default="")
    args = ap.parse_args(argv)

    cases = load_cases(args.conversations)
    if args.limit:
        cases = cases[:args.limit]
    if not cases:
        print("No test cases found in %s" % args.conversations)
        return 1
    config = settings.load_config()
    call = reply.stand_in_model if args.dry_run else None
    if not args.dry_run:
        settings.api_key()  # fail early with a clear message if the key is missing

    run = {
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "prompt_version": prompts.PROMPT_VERSION,
        "model": "stand-in" if args.dry_run else config["model"],
        "under_18": args.under_18,
        "cases": [],
    }
    failures = 0
    for i, case in enumerate(cases, 1):
        started = time.time()
        try:
            replies = reply.suggest_replies(to_speaker(case["messages"]), platform=case.get("app"),
                                            under_18=args.under_18, call=call, config=config)
            error = None
        except (openrouter.ModelError, reply.BadRequest, RuntimeError) as e:
            replies, error = [], str(e)
            failures += 1
        seconds = round(time.time() - started, 2)
        run["cases"].append({"id": case["id"], "replies": replies, "error": error, "seconds": seconds})
        print("%2d/%d %-18s %s" % (i, len(cases), case["id"], "error: " + error if error else "%d replies, %.1fs" % (len(replies), seconds)))

    RESULTS.mkdir(exist_ok=True)
    out = Path(args.out) if args.out else RESULTS / ("run-%s.json" % time.strftime("%Y%m%d-%H%M%S"))
    with open(out, "w", encoding="utf-8") as f:
        json.dump(run, f, ensure_ascii=False, indent=1)
    print("Saved %s (%d failed)" % (out, failures))
    return 1 if failures == len(cases) else 0


if __name__ == "__main__":
    sys.exit(main())
