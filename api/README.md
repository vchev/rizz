# Reply backend

`api/reply.py` is the one web endpoint the iPhone app calls. It holds the OpenRouter key so the
app never does. Request and response shapes are in the file's docstring and in
`ios/Shared/ReplyService.swift`.

## Hosting (Vercel)

Vercel runs `api/reply.py` as a serverless function straight from GitHub (`vercel.json`,
`.vercelignore`). Secrets set in Vercel, under Project › Settings › Environment Variables:

| Name | What |
| --- | --- |
| `OPENROUTER_API_KEY` | The OpenRouter key. Never in git or chat. |
| `COAX_APP_TOKEN` | A random string the app sends as `X-Coax-Token`. Blocks random callers. |

The endpoint is `https://<project>.vercel.app/api/reply`. Opening it in a browser shows
`{"ok": true, ...}`, which means it's up (no model call, costs nothing).

Vercel's free Hobby plan is for non-commercial use; move to Pro before the paid launch.

## On a Mac

```
python3 api/reply.py        # serves http://localhost:8787/api/reply, reads .env
```

## Privacy

Chats are never stored or logged. Every model request asks OpenRouter for zero-data-retention
providers only (`openrouter_provider` in config.json). Long threads are cut to the latest 80
messages / 12,000 characters before they're sent.
