"""Build the Coax guides site into public/ from site/*.md. Standard library only.

    python3 tools/build_site.py                          # preview build: noindex, no domain
    python3 tools/build_site.py --domain hicoax.com --app-store "https://apps.apple.com/app/idNNN"

Until --domain is given, every page says noindex and robots.txt blocks crawlers, so Google
doesn't index the temporary vercel.app address. site/drafts/ is never published (comparison
pages wait for verified competitor facts and legal review).
"""
import argparse
import html
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
OUT = ROOT / "public"
BLUE = "#0A7CFF"


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: '<a href="%s">%s</a>' % (m.group(2).replace('"', "%22"), m.group(1)), text)


def markdown(md):
    """A small Markdown subset: headings, paragraphs, lists, tables, rules, bold, italic, links."""
    out, para, lst, table = [], [], None, []

    def flush():
        nonlocal para, lst, table
        if para:
            out.append("<p>%s</p>" % inline(" ".join(para)))
            para = []
        if lst:
            tag, items = lst
            out.append("<%s>%s</%s>" % (tag, "".join("<li>%s</li>" % inline(i) for i in items), tag))
            lst = None
        if table:
            rows = [[c.strip() for c in r.strip().strip("|").split("|")] for r in table]
            head, body = rows[0], [r for r in rows[2:]]
            out.append("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % (
                "".join("<th>%s</th>" % inline(c) for c in head),
                "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r) for r in body)))
            table = []

    for line in md.splitlines():
        s = line.strip()
        if not s:
            flush()
        elif s.startswith("|"):
            if para or lst:
                flush()
            table.append(s)
        elif re.fullmatch(r"-{3,}", s):
            flush()
            out.append("<hr>")
        elif m := re.match(r"(#{1,4})\s+(.*)", s):
            flush()
            level = len(m.group(1))
            out.append("<h%d>%s</h%d>" % (level, inline(m.group(2)), level))
        elif m := re.match(r"(?:[-*]|(\d+)\.)\s+(.*)", s):
            if para or table:
                flush()
            tag = "ol" if m.group(1) else "ul"
            if not lst or lst[0] != tag:
                flush()
                lst = (tag, [])
            lst[1].append(m.group(2))
        else:
            if lst or table:
                flush()
            para.append(s)
    flush()
    return "\n".join(out)


def split_front(text):
    meta = {}
    if text.startswith("---"):
        _, front, text = text.split("---", 2)
        for line in front.strip().splitlines():
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip('"').replace('\\"', '"')
    return meta, text.strip()


CSS = """*{box-sizing:border-box}body{margin:0;font:17px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#111;background:#fff}
a{color:%s}header,main,footer{max-width:720px;margin:0 auto;padding:0 16px}header{display:flex;justify-content:space-between;align-items:center;padding-top:16px}
.logo{font-weight:800;font-size:22px;text-decoration:none;color:%s}.cta{background:%s;color:#fff;padding:10px 16px;border-radius:22px;text-decoration:none;font-weight:600}
h1{font-size:32px;line-height:1.2}table{border-collapse:collapse;width:100%%;font-size:15px}td,th{border:1px solid #ddd;padding:8px;text-align:left;vertical-align:top}
.wrap{overflow-x:auto}footer{color:#666;font-size:14px;padding:32px 16px}textarea{width:100%%;font:inherit;padding:12px;border:1px solid #ccc;border-radius:12px}
button{background:%s;color:#fff;border:0;padding:12px 20px;border-radius:22px;font:inherit;font-weight:600}.bubble{background:%s;color:#fff;padding:12px 16px;border-radius:18px;display:inline-block;margin:12px 0}
@media (prefers-color-scheme:dark){body{background:#000;color:#eee}td,th{border-color:#333}textarea{background:#111;color:#eee;border-color:#333}footer{color:#999}}""" % ((BLUE,) * 5)


def page(title, body, desc, robots, canonical):
    return """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s</title><meta name="description" content="%s">%s%s<style>%s</style></head><body>
<header><a class="logo" href="/">Coax</a><a class="cta" href="/#get">Get Coax</a></header>
<main>%s</main><footer>Coax writes dating replies that sound like you. Screenshots stay on your phone. No account. &middot; <a href="/guides/">All guides</a> &middot; <a href="/reply/">Free reply tool</a></footer>
</body></html>""" % (html.escape(title), html.escape(desc), robots, canonical, CSS, body)


def build(domain=None, app_store=None):
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    robots = "" if domain else '<meta name="robots" content="noindex">'
    store = app_store or "/#get"
    urls, guides = [], []

    def write(path, title, body, desc):
        canonical = '<link rel="canonical" href="https://%s%s">' % (domain, path) if domain else ""
        body = re.sub(r"APPSTORE_LINK(\?ct=[\w-]+)?", lambda m: store + (m.group(1) or "") if app_store else store, body)
        target = OUT / path.strip("/") / "index.html" if path != "/" else OUT / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page(title, body, desc, robots, canonical), encoding="utf-8")
        urls.append(path)

    for f in sorted((SITE / "guides").glob("*.md")):
        meta, text = split_front(f.read_text(encoding="utf-8"))
        slug = meta["slug"]
        first = re.search(r"\*\*Short answer:\*\*\s*(.+)", text)
        desc = re.sub(r"[*_`\[\]]", "", first.group(1))[:155] if first else meta["title"]
        body = "<article><h1>%s</h1><p><small>Updated %s</small></p>%s</article>" % (
            html.escape(meta["title"]), meta.get("updated", ""), markdown(text).replace("<table>", '<div class="wrap"><table>').replace("</table>", "</table></div>"))
        write("/guides/%s/" % slug, meta["title"] + " | Coax", body, desc)
        guides.append((slug, meta["title"]))

    listing = "".join('<li><a href="/guides/%s/">%s</a></li>' % (s, html.escape(t)) for s, t in guides)
    write("/guides/", "Texting guides for dating apps | Coax",
          "<h1>Texting guides</h1><p>Short, honest answers to the texts everyone gets stuck on.</p><ul>%s</ul>" % listing,
          "Short answers to the dating texts everyone gets stuck on: wyd, left on read, asking her out, and more.")
    write("/reply/", "Free AI reply generator for dating apps | Coax", TOOL_HTML,
          "Paste her last message and get a reply that sounds like a real person. 3 free replies a day.")
    home = HOME_HTML.replace("STORE", html.escape(store)).replace("GUIDES", listing)
    write("/", "Coax: dating replies that sound like you", home,
          "Coax reads your dating chat from a screenshot and writes 3 replies in your own texting style. Screenshots stay on your phone. 3 days free, no card.")
    if domain:
        (OUT / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://%s/sitemap.xml\n" % domain)
        (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">%s</urlset>\n'
                                         % "".join("<url><loc>https://%s%s</loc></url>" % (domain, u) for u in sorted(urls)))
    else:
        (OUT / "robots.txt").write_text("User-agent: *\nDisallow: /\n")
    return urls


HOME_HTML = """<h1>Your next text, in your words.</h1>
<p>Coax reads your Hinge, Tinder, Bumble or iMessage chat from a screenshot and suggests 3 replies that sound like you, not like a pickup line. It remembers each match, and your screenshots never leave your phone.</p>
<p id="get"><a class="cta" href="STORE">Get Coax for iPhone</a></p>
<p><small>3 days free with no card and no account. Then $4.99/week or $99/year. Coming to the App Store January 17.</small></p>
<h2>Stuck on a reply right now?</h2><p><a href="/reply/">Try the free reply tool</a>: paste her message, get a reply.</p>
<h2>Texting guides</h2><ul>GUIDES</ul>"""

TOOL_HTML = """<h1>Free reply tool</h1>
<p>Paste the message you're stuck on. You'll get one reply that sounds like a real person. 3 free replies a day.</p>
<p><label>Her last message<br><textarea id="msg" rows="3" maxlength="600" placeholder="e.g. wyd"></textarea></label></p>
<p><label>Earlier messages (optional)<br><textarea id="ctx" rows="2" maxlength="600"></textarea></label></p>
<p><button id="go">Get a reply</button></p><div id="out" aria-live="polite"></div>
<p><small>We don't store what you paste. It's sent to our AI model to write the reply and then forgotten.</small></p>
<p>Want 3 options every time, in your own style, right in your keyboard? <a href="/#get">Get Coax</a>.</p>
<script>
document.getElementById('go').onclick=async()=>{const out=document.getElementById('out');const msg=document.getElementById('msg').value.trim();
if(!msg){out.textContent='Paste a message first.';return}out.textContent='Thinking...';
try{const r=await fetch('/api/try_tool',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:msg,context:document.getElementById('ctx').value})});
const d=await r.json();out.innerHTML='';if(d.reply){const b=document.createElement('div');b.className='bubble';b.textContent=d.reply;out.appendChild(b);
const s=document.createElement('p');s.textContent=d.left_today+' free replies left today.';out.appendChild(s)}else{out.textContent=d.error||'Something went wrong.'}}
catch(e){out.textContent='Something went wrong. Try again.'}};
</script>"""


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain")
    ap.add_argument("--app-store")
    a = ap.parse_args()
    print("built %d pages into public/" % len(build(a.domain, a.app_store)))
