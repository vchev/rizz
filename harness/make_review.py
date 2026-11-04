"""Build a blind rating page for the latest run: results/review-<run>.html.

For each test case you see the end of the chat and a shuffled list of replies. One of them is
what you really sent (a hidden control); the rest come from the engine. Rate each one, then press
"Download ratings" and run harness/score.py.

    python3 harness/make_review.py                 # latest results/run-*.json
    python3 harness/make_review.py --run results/run-20261110-120000.json
"""
import argparse
import html
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from harness.common import RESULTS, ROOT, latest, load_cases  # noqa: E402

SHOW_LAST = 12

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rate replies</title>
<style>
body{font:16px -apple-system,system-ui,sans-serif;margin:0;background:#f4f4f6;color:#111}
main{max-width:640px;margin:0 auto;padding:16px}
.case{background:#fff;border-radius:14px;padding:14px;margin:0 0 18px}
.chat{display:flex;flex-direction:column;gap:4px;margin:8px 0 14px}
.b{max-width:78%%;padding:7px 11px;border-radius:16px;line-height:1.3}
.them{align-self:flex-start;background:#e9e9eb}.you{align-self:flex-end;background:#0a7cff;color:#fff}
.opt{border-top:1px solid #eee;padding:10px 0}.opt p{margin:0 0 6px}
label{margin-right:10px;white-space:nowrap;font-size:14px}
.meta{color:#777;font-size:13px}button{font-size:16px;padding:10px 16px;border-radius:10px}
#bar{position:sticky;bottom:0;background:#fff;padding:12px 16px;border-top:1px solid #ddd;text-align:center}
</style></head><body><main>
<h1>Rate replies</h1>
<p class="meta">Run %(run)s. For each reply: would you send it? Your progress is kept in this browser.</p>
%(cases)s
</main>
<div id="bar"><span id="count"></span> &nbsp; <button id="dl">Download ratings</button></div>
<script>
const RUN = %(run_json)s;
const KEY = "ratings:" + RUN;
let saved = {};
try { saved = JSON.parse(localStorage.getItem(KEY) || "{}"); } catch (e) {}
const radios = [...document.querySelectorAll("input[type=radio]")];
radios.forEach(r => { if (saved[r.name] === r.value) r.checked = true; r.onchange = () => {
  saved[r.name] = r.value; try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {} count(); }; });
function count() {
  const total = document.querySelectorAll(".opt").length;
  document.getElementById("count").textContent = Object.keys(saved).length + " of " + total + " rated";
}
count();
document.getElementById("dl").onclick = () => {
  const ratings = [...document.querySelectorAll(".opt")].map(o => ({
    case: o.dataset.case, source: o.dataset.source, text: o.dataset.text, rating: saved[o.dataset.key] || null }));
  const blob = new Blob([JSON.stringify({run: RUN, ratings}, null, 1)], {type: "application/json"});
  const a = document.createElement("a"); a.href = URL.createObjectURL(blob);
  a.download = "ratings-" + RUN + ".json"; a.click();
};
</script></body></html>
"""

CHOICES = [("as_is", "Send as-is"), ("small_edit", "Send with a small edit"), ("no", "Wouldn't send")]


def build(run, cases_by_id, seed=7):
    rng = random.Random(seed)
    blocks = []
    for item in run["cases"]:
        case = cases_by_id.get(item["id"])
        if not case or not item["replies"]:
            continue
        chat = "".join('<div class="b %s">%s</div>' % ("you" if m["from"] == "you" else "them", html.escape(m["text"]))
                       for m in case["messages"][-SHOW_LAST:])
        options = [("engine", t) for t in item["replies"]]
        actual = case.get("actual_reply") or []
        if actual:
            options.append(("actual", " / ".join(actual) if isinstance(actual, list) else str(actual)))
        rng.shuffle(options)
        rows = []
        for j, (source, text) in enumerate(options):
            key = "%s#%d" % (item["id"], j)
            radios = "".join('<label><input type="radio" name="%s" value="%s"> %s</label>' % (html.escape(key), v, lbl)
                             for v, lbl in CHOICES)
            rows.append('<div class="opt" data-key="%s" data-case="%s" data-source="%s" data-text="%s"><p>%s</p>%s</div>'
                        % (html.escape(key), html.escape(item["id"]), source, html.escape(text), html.escape(text), radios))
        blocks.append('<section class="case"><div class="meta">%s · %s</div><div class="chat">%s</div>%s</section>'
                      % (html.escape(item["id"]), html.escape(case.get("app", "")), chat, "".join(rows)))
    name = run.get("name", "run")
    return PAGE % {"run": html.escape(name), "run_json": json.dumps(name), "cases": "\n".join(blocks)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", default="")
    ap.add_argument("--conversations", default=str(ROOT / "data" / "conversations"))
    args = ap.parse_args(argv)
    run_path = Path(args.run) if args.run else latest("run-*.json")
    if not run_path or not run_path.exists():
        print("No run found. Run harness/run_eval.py first.")
        return 1
    with open(run_path, encoding="utf-8") as f:
        run = json.load(f)
    run["name"] = run_path.stem
    cases = {c["id"]: c for c in load_cases(args.conversations)}
    out = RESULTS / ("review-%s.html" % run_path.stem)
    RESULTS.mkdir(exist_ok=True)
    out.write_text(build(run, cases), encoding="utf-8")
    print("Open this file in Safari or Chrome: %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
