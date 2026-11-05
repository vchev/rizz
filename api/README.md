# Reply backend

`api/reply.py` is the one web endpoint the iPhone app calls. It holds the OpenRouter key so the
app never does. Request and response shapes are in the file's docstring and in
`ios/Shared/ReplyService.swift`.

## Hosting (Vercel)

Vercel runs `api/reply.py` as a serverless function straight from GitHub (`vercel.json`,
`.vercelignore`). Secrets set in Vercel, under Project › Settings › Environment Variables:

| Name | What |
| --- | --- |
| `ANTHROPIC_API_KEY` | A Claude API key (console.anthropic.com). Used first if set. Never in git or chat. |
| `OPENROUTER_API_KEY` | An OpenRouter key, used when there is no Claude key. |
| `COAX_APP_TOKEN` | A random string the app sends as `X-Coax-Token`. Blocks random callers. |

The endpoint is `https://<project>.vercel.app/api/reply`. Opening it in a browser shows
`{"ok": true, ...}`, which means it's up (no model call, costs nothing).

Vercel's free Hobby plan is for non-commercial use; move to Pro before the paid launch.

## On a Mac

```
python3 api/reply.py        # serves http://localhost:8787/api/reply, reads .env
```

## Privacy

Chats are never stored or logged by us. Through OpenRouter, every request asks for
zero-data-retention providers only (`openrouter_provider` in config.json). Through a Claude key,
Anthropic does not train on the data but keeps it up to 30 days unless the account has zero data
retention. Long threads are cut to the latest 80
messages / 12,000 characters before they're sent.

## Free web reply tool (`api/try_tool.py`)

Public endpoint behind the site's /reply/ page. No token, so it's kept small: one reply from at
most 3 short messages, always the stricter teen-safe prompt, 3 replies per visitor per day and a
daily cap per server instance (`COAX_TRY_DAILY_CAP`, default 300), all held in memory only.
Nothing pasted is stored or logged.
