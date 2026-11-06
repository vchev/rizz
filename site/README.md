# Coax guides site

Marketing site for the Search lane of the go-to-market plan: texting guides that rank on Google,
plus the free web reply tool (`api/try_tool.py`). Plain HTML built by a standard-library script.

```
python3 tools/build_site.py                       # preview: noindex, robots blocks crawlers
python3 tools/build_site.py --domain hicoax.com --app-store "https://apps.apple.com/app/idNNN"
```

- `site/guides/*.md`: one guide per file (front matter: title, slug, keyword, updated).
- `site/drafts/`: comparison pages. Never built. They publish only after competitor facts marked
  [VERIFY] are checked on the live App Store pages and pass legal review.
- `public/`: the built site, committed, served by Vercel as-is. Rebuild after editing a guide.

Until the domain is connected, the site stays out of Google on purpose (noindex), so the temporary
vercel.app address never competes with the real one.
