"""Turn a printed Messages PDF into bubbles using the alignment rule.

Groups text into bubbles with pdftotext's blocks, then rebuilds each bubble's
text from pdfplumber characters so emoji (stored as pictures) can be tagged
by image hash. Output: JSON list of
{page, page_height, side, text, size, x0, x1, top, bottom}.

Usage: python3 tools/extract_pdf.py thread.pdf /tmp/thread.json /tmp/emoji
Needs: pip3 install pdfplumber pillow, and poppler (brew install poppler).
"""
import hashlib
import json
import re
import shutil
import statistics
import subprocess
import sys
from html import unescape
from pathlib import Path

POPPLER_HELP = (
    "pdftotext was not found. It comes with poppler.\n"
    "On your Mac, open Terminal and run:  brew install poppler\n"
    "Then run this command again."
)


def fail(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def run_pdftotext(pdf_path):
    """Return one HTML chunk per page from pdftotext -bbox-layout, or exit with a clear error."""
    if shutil.which("pdftotext") is None:
        fail(POPPLER_HELP)
    proc = subprocess.run(["pdftotext", "-bbox-layout", str(pdf_path), "-"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        fail("pdftotext could not read {}:\n{}".format(pdf_path, proc.stderr.strip()))
    pages = re.findall(r'<page width="[\d.]+" height="[\d.]+">(.*?)</page>', proc.stdout, re.S)
    if not pages:
        fail("pdftotext returned no pages for {}. Is it a Messages PDF?".format(pdf_path))
    return pages


def emoji_png(img, key, emoji_dir):
    from PIL import Image
    p = emoji_dir / "{}.png".format(key)
    if p.exists():
        return
    try:
        w, h = img["srcsize"]
        data = img["stream"].get_data()
        mode = "RGB" if len(data) >= w * h * 3 else "L"
        if len(data) == w * h * 6:  # 16-bit RGB: keep high bytes
            data = bytes(data[i] for i in range(0, len(data), 2))
        Image.frombytes(mode, (w, h), data[: w * h * (3 if mode == "RGB" else 1)]).save(p)
    except Exception as e:  # keep going; the key still identifies the emoji
        print("could not save", key, e, file=sys.stderr)


def emoji_key(stream, cache):
    """Stable id for an emoji picture: hash of its raw (compressed) bytes.

    The same picture is shared across pages, and decoding it to save the PNG replaces the raw
    bytes in memory, so the hash is taken once per picture and remembered. Hashing on every use
    gave a different id for the same emoji depending on whether its PNG was already saved.
    """
    sid = id(stream)
    if sid not in cache:
        raw = stream.get_rawdata()
        cache[sid] = hashlib.md5(raw if raw is not None else stream.get_data()).hexdigest()[:8]
    return cache[sid]


def extract(pdf_path, emoji_dir):
    import pdfplumber

    emoji_dir.mkdir(parents=True, exist_ok=True)
    pages_html = run_pdftotext(pdf_path)
    bubbles = []
    keys = {}
    with pdfplumber.open(pdf_path) as pdf:
        if len(pdf.pages) != len(pages_html):
            fail("pdftotext saw {} pages but the PDF has {}.".format(len(pages_html), len(pdf.pages)))
        for pno, (page, ph) in enumerate(zip(pdf.pages, pages_html), start=1):
            emoji_imgs = [im for im in page.images if tuple(im["srcsize"]) == (160, 160)]
            for b in re.finditer(r'<block xMin="(-?[\d.]+)" yMin="(-?[\d.]+)" xMax="(-?[\d.]+)" yMax="(-?[\d.]+)">', ph):
                x0, top, x1, bottom = map(float, b.groups())
                chars = [c for c in page.chars
                         if c["x0"] >= x0 - 1 and c["x1"] <= x1 + 1 and c["top"] >= top - 1 and c["bottom"] <= bottom + 1]
                chars.sort(key=lambda c: (round(c["top"] / 4), c["x0"]))
                lines, cur, last_top, last_x1 = [], "", None, None
                for c in chars:
                    if last_top is not None and abs(c["top"] - last_top) > 4:
                        lines.append(cur)
                        cur, last_x1 = "", None
                    ch = c["text"]
                    if "Emoji" in c["fontname"]:
                        cx, cy = (c["x0"] + c["x1"]) / 2, (c["top"] + c["bottom"]) / 2
                        hit = min(emoji_imgs, key=lambda im: abs((im["x0"] + im["x1"]) / 2 - cx)
                                  + abs((im["top"] + im["bottom"]) / 2 - cy), default=None)
                        if hit is None:
                            ch = "{E:?}"
                        else:
                            key = emoji_key(hit["stream"], keys)
                            emoji_png(hit, key, emoji_dir)
                            ch = "{E:" + key + "}"
                    if last_x1 is not None and c["x0"] - last_x1 > c["size"] * 0.2:
                        cur += " "
                    cur += ch
                    last_top, last_x1 = c["top"], c["x1"]
                if cur:
                    lines.append(cur)
                text = unescape(" ".join(l.strip() for l in lines)).strip()
                sizes = [c["size"] for c in chars if "Emoji" not in c["fontname"]]
                # Left edge = them, right edge = you, anything else (timestamps, notices) = center.
                side = "them" if x0 <= 45 else ("you" if x1 >= 550 else "center")
                bubbles.append({"page": pno, "page_height": round(page.height), "side": side, "text": text,
                                "size": round(statistics.median(sizes), 1) if sizes else None,
                                "x0": round(x0), "x1": round(x1), "top": round(top), "bottom": round(bottom)})
    return bubbles


def main(argv):
    if len(argv) != 4:
        fail("usage: python3 tools/extract_pdf.py thread.pdf out.json emoji_folder")
    pdf_path, out_path, emoji_dir = Path(argv[1]), Path(argv[2]), Path(argv[3])
    if not pdf_path.is_file():
        fail("{} not found.".format(pdf_path))
    bubbles = extract(pdf_path, emoji_dir)
    if not any(b["text"] for b in bubbles):
        fail("No text found in {}. Was it saved with File > Print > Save as PDF?".format(pdf_path))
    out_path.write_text(json.dumps(bubbles, ensure_ascii=False, indent=1))
    print("{}: {} blocks, ".format(pdf_path, len(bubbles))
          + ", ".join("{}={}".format(s, sum(b["side"] == s for b in bubbles)) for s in ("you", "them", "center")))


if __name__ == "__main__":
    main(sys.argv)
