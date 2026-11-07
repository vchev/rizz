"""Build the Coax guides site into public/ from site/*.md. Standard library only.

    python3 tools/build_site.py                          # preview build: noindex, no domain
    python3 tools/build_site.py --domain hicoax.com --app-store "https://apps.apple.com/app/idNNN"

Until --domain is given, every page says noindex and robots.txt blocks crawlers, so Google
doesn't index the temporary vercel.app address. site/drafts/ is never published (comparison
pages wait for verified competitor facts and legal review).
"""
import argparse
import html
import json
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


def short(text, limit=155):
    """Cut a search description at a word break, not mid-word."""
    return text if len(text) <= limit else text[:limit].rsplit(" ", 1)[0].rstrip(",;:") + "..."


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


def page(title, body, desc, robots, canonical, extra=""):
    return """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s</title><meta name="description" content="%s">%s%s%s<style>%s</style></head><body>
<header><a class="logo" href="/">Coax</a><a class="cta" href="/#get">Get Coax</a></header>
<main>%s</main><footer>Coax writes dating replies that sound like you. Screenshots stay on your phone. No account. &middot; <a href="/guides/">All guides</a> &middot; <a href="/reply/">Free reply tool</a> &middot; <a href="/privacy/">Privacy</a> &middot; <a href="/terms/">Terms</a></footer>
</body></html>""" % (html.escape(title), html.escape(desc), robots, canonical, extra, CSS, body)


def head_tags(domain, path, title, desc, schema):
    """Link-preview (Open Graph / Twitter) tags and schema.org data, so shares show a card
    and search engines and AI assistants can read what each page is."""
    url = "https://%s%s" % (domain, path)
    tags = "".join('<meta property="%s" content="%s">' % (k, html.escape(v)) for k, v in (
        ("og:title", title), ("og:description", desc), ("og:url", url), ("og:site_name", "Coax"),
        ("og:type", "article" if schema and schema.get("@type") == "Article" else "website")))
    tags += '<meta name="twitter:card" content="summary">'
    if schema:
        data = dict({"@context": "https://schema.org", "url": url}, **schema)
        tags += '<script type="application/ld+json">%s</script>' % json.dumps(data).replace("</", "<\\/")
    return tags


def build(domain=None, app_store=None):
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    robots = "" if domain else '<meta name="robots" content="noindex">'
    store = app_store or "/#get"
    urls, guides = [], []

    def write(path, title, body, desc, schema=None):
        canonical = '<link rel="canonical" href="https://%s%s">' % (domain, path) if domain else ""
        extra = head_tags(domain, path, title, desc, schema) if domain else ""
        body = re.sub(r"APPSTORE_LINK(\?ct=[\w-]+)?", lambda m: store + (m.group(1) or "") if app_store else store, body)
        target = OUT / path.strip("/") / "index.html" if path != "/" else OUT / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page(title, body, desc, robots, canonical, extra), encoding="utf-8")
        urls.append(path)

    for f in sorted((SITE / "guides").glob("*.md")):
        meta, text = split_front(f.read_text(encoding="utf-8"))
        slug = meta["slug"]
        first = re.search(r"\*\*Short answer:\*\*\s*(.+)", text)
        desc = short(re.sub(r"[*_`\[\]]", "", first.group(1))) if first else meta["title"]
        body = "<article><h1>%s</h1><p><small>Updated %s</small></p>%s</article>" % (
            html.escape(meta["title"]), meta.get("updated", ""), markdown(text).replace("<table>", '<div class="wrap"><table>').replace("</table>", "</table></div>"))
        write("/guides/%s/" % slug, meta["title"] + " | Coax", body, desc, {
            "@type": "Article", "headline": meta["title"], "description": desc,
            "dateModified": meta.get("updated", ""), "author": {"@type": "Organization", "name": "Coax"},
            "publisher": {"@type": "Organization", "name": "Coax"}})
        guides.append((slug, meta["title"]))

    listing = "".join('<li><a href="/guides/%s/">%s</a></li>' % (s, html.escape(t)) for s, t in guides)
    write("/guides/", "Texting guides for dating apps | Coax",
          "<h1>Texting guides</h1><p>Short, honest answers to the texts everyone gets stuck on.</p><ul>%s</ul>" % listing,
          "Short answers to the dating texts everyone gets stuck on: wyd, left on read, asking her out, and more.")
    write("/reply/", "Free AI reply generator for dating apps | Coax", TOOL_HTML,
          "Paste her last message and get a reply that sounds like a real person. 3 free replies a day.")
    write("/privacy/", "Privacy policy | Coax", PRIVACY_HTML,
          "Coax has no account, no ads and no analytics. Screenshots are read on your phone; only the chat text goes out, to write replies, and nobody keeps it.")
    write("/terms/", "Terms of use | Coax", TERMS_HTML,
          "The terms for using Coax and its subscription.")
    home = HOME_HTML.replace("STORE", html.escape(store)).replace("GUIDES", listing)
    write("/", "Coax: dating replies that sound like you", home,
          "Coax reads your dating chat from a screenshot and writes 3 replies in your own texting style. Screenshots stay on your phone. 3 days free, no card.",
          {"@type": "WebSite", "name": "Coax", "publisher": {"@type": "Organization", "name": "Coax"}})
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


POLICY_DATE = "November 7, 2026"

PRIVACY_HTML = """<article><h1>Privacy policy</h1><p><small>Effective """ + POLICY_DATE + """</small></p>
<p><strong>The short version:</strong> Coax has no account, no ads, no analytics and no tracking. Your screenshots are read on your phone and never uploaded. To write replies, the text of the chat goes to our server and our AI provider, and neither of them keeps it.</p>
<h2>What stays on your phone</h2>
<ul><li>Your screenshots. Coax reads the text in them on your iPhone (Apple's on-device text recognition). The images never leave your phone.</li>
<li>The chats Coax has read, your texting style (quiz answers and what Coax learned from your own messages), your settings, and simple counts such as how many replies you picked. These are stored in the app on your phone and included in your iPhone backup. Deleting the app deletes them.</li></ul>
<h2>What leaves your phone, and why</h2>
<p>When you ask for replies, Coax sends: the text of the chat (up to the last 60 messages, marked as yours or theirs), which app it came from, the mood you picked, anything you typed into "Tell Coax what to say", your texting-style settings with a few of your own recent texts as examples, and whether you are under 18 (so replies stay age-appropriate).</p>
<p>This goes over an encrypted connection to our server, which passes it to our AI provider, Anthropic (the Claude API), to write the replies. The replies come back to your phone. Our server does not write the chat to disk or to logs. Anthropic processes it under a zero data retention agreement: it is not stored after the reply is written and is never used to train AI models.</p>
<p>Our host (Vercel) keeps standard technical logs, such as IP address and time of a request, for a short period to run and secure the service. These logs never contain your chats.</p>
<h2>What we don't do</h2>
<ul><li>No account, name, email or phone number is needed.</li><li>No advertising, no ad tracking and no selling or sharing of personal data.</li><li>No analytics or third-party SDKs in the app.</li></ul>
<h2>Purchases</h2>
<p>Subscriptions are handled by Apple. We never see your payment details. Coax asks Apple only whether your subscription is active.</p>
<h2>The free reply tool on this website</h2>
<p>What you paste is sent to our AI provider to write one reply and is not stored. To limit free use, we keep a one-way hash of your IP address in memory for the day; it is never written to disk.</p>
<h2>Ages</h2>
<p>Coax is for people 16 and older. Users aged 16 and 17 get a stricter mode: no flirting about bodies, nothing sexual, no alcohol or drugs, and no plans to meet somewhere private.</p>
<h2>Other people's messages</h2>
<p>Chats include messages from the people you talk to. Coax uses them only to write your reply, keeps them only on your phone, and sends them only for that request.</p>
<h2>Your choices</h2>
<p>Turn off texting-style learning or reset it in the app's Settings. Delete the app to remove everything Coax stored. Because we don't keep your data on our servers, there is nothing else for us to delete; if you have a question or request, email <a href="mailto:press@hicoax.com">press@hicoax.com</a>.</p>
<h2>Changes</h2>
<p>If this policy changes, we'll update the date above and, for important changes, tell you in the app.</p></article>"""

TERMS_HTML = """<article><h1>Terms of use</h1><p><small>Effective """ + POLICY_DATE + """</small></p>
<p>These terms apply on top of Apple's <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Standard End User License Agreement</a>, which covers your use of the Coax app.</p>
<h2>Who can use Coax</h2><p>You must be 16 or older. If you are 16 or 17, a parent or guardian must agree to these terms.</p>
<h2>Subscription</h2>
<ul><li>Coax is free for your first 3 days with no card. After that, replies need a subscription: $4.99 per week or $99 per year (prices may differ by country and are shown before you buy).</li>
<li>A new subscription starts with a 7-day free trial when you're eligible. Payment is charged to your Apple ID when the trial ends.</li>
<li>Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in Settings &gt; your name &gt; Subscriptions.</li>
<li>Refunds are handled by Apple.</li></ul>
<h2>Using replies</h2>
<p>Coax suggests messages; you decide what to send. Suggestions come from AI and can be wrong or not fit your situation. Read them before sending. You're responsible for what you send.</p>
<p>Don't use Coax to harass, threaten, deceive or pressure anyone, to send sexual content involving minors, or for anything illegal. Don't try to break, overload or copy the service.</p>
<h2>No guarantees</h2>
<p>Coax is provided as is. We can't promise any result in your conversations or that the service is always available. To the extent the law allows, our liability is limited to what you paid for Coax in the last 12 months.</p>
<h2>Changes and contact</h2>
<p>We may update these terms; the date above shows the latest version. Questions: <a href="mailto:press@hicoax.com">press@hicoax.com</a>.</p></article>"""


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain")
    ap.add_argument("--app-store")
    a = ap.parse_args()
    print("built %d pages into public/" % len(build(a.domain, a.app_store)))
