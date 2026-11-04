# Reply Assistant — project context for Claude Code

An iOS app that suggests dating-app / iMessage replies that sound like the user and fit the
specific conversation (an improved Rizz). Owner: Vanessa.

## Working model
- Vanessa is the CEO: she makes decisions; Claude is the whole build team (PM, design, iOS,
  backend/AI, QA, release). Keep her involvement to about an hour a week.
- Every decision goes to her as a short multiple-choice question with a recommended option.
  If she doesn't answer within 2 days, the recommendation stands.
- Dates hold, scope flexes: if a sprint runs long, cut the lowest-priority task, not the date.
  New ideas go on a "later" list.
- If work is ahead of plan, ask her before pulling the next sprint's work forward.
- She is not a developer. Explain in plain words; give click-by-click steps for anything she
  must do on her Mac.

## Source of truth (Claude Docs; read with the docs tools)
- Development plan: https://claude.ai/artifact/VTx2hRiPrDFRHNUoK5LG4m
- PRD: https://claude.ai/artifact/Y6c2BjHTH7JGALboTvR3kx
Tick tasks off in the plan as they're confirmed done. A scheduled task posts a status note every
Monday morning (Pacific).

## Plan (5 two-week sprints, started early on Nov 2, 2026)
1. Nov 9–22 Reply engine in the backend. Gate 1: most replies on the test set are ones
   she'd send (would-send = "send as-is" + "send with a small edit", threshold in config.json).
   We do NOT benchmark against Rizz.
2. Nov 23–Dec 6 iPhone app v0 (SwiftUI, share extension, Apple Vision OCR). Finish line 1: she uses it.
3. Dec 7–20 Thread per match, voice profile, onboarding, TestFlight. Finish line 2: friends on TestFlight.
4. Dec 21–Jan 3 Paywall (StoreKit 2, free tier, no card), privacy, beta fixes. Gate 2.
5. Jan 4–17 App Store submission. Finish line 3: live. iMessage continuity is post-launch.

## Status (as of Nov 4, 2026)
- Sprint 1 done early. Reply engine is live at https://rizz-olive.vercel.app/api/reply
  (Vercel free Hobby plan; engine changes go live on merge, no app rebuild). Model: Claude
  Haiku 5.5 on her own Claude API key, zero data retention (see config.json). Prompt v6.
- GATE 1 PASSED Nov 4 (prompt v5): she'd send one of the 3 replies in 13 of 15 chats.
  Open tuning item: who-is-who on nicknames and pet names.
- Sprint 2 started early on Nov 4. Built and working on her iPhone: Back Tap shortcut
  (screenshot -> 3 replies wait in the Coax keyboard), Coax keyboard (reads a new screenshot,
  1-2-3 picker, tone tags), Coax iMessage app. Share extension is a backup way in.
- Not built yet: voice profile (moved to Sprint 3), second-pass generic-reply scorer (later
  list; today a prompt rule plus a stock-phrase list), thread per match / SwiftData.
- 43 test cases from 6 threads: jacob, avi, sebastian, brad (iMessage PDFs), jeff and
  bumble-common (Bumble screenshots, transcribed by hand). Kept in data/conversations/
  (git-ignored) and in the project's shared files under rizz-private/conversations/.
- Wanted: more threads from different people, ideally inside Hinge/Bumble/Tinder.

## Decisions (full log in the PRD's "Decision log")
- Name: Coax; App Store name "Coax AI: Dating Assistant". Dating only at launch. Lawyer check
  before launch.
- Data stays on the phone, no account, no analytics. Minimum age 16+; ages 16-17 get teen mode.
- Pricing: $4.99/week or $99/year, no monthly; 3 free days with no card, then a 7-day trial.
- Hosting: Vercel free now; Pro ($20/mo) only when she decides to launch. Apple Developer fee
  paid once the app fully works (around Dec 6).
- Brand color: iMessage-style blue (#0A7CFF). Never add a blocking step to the main path
  (double-tap back -> tap message box -> tap reply).
- Later list: iMessage continuity, friendship mode, live-screen mode, second-pass generic
  scorer, blind check against her own ChatGPT shortcut.

## Rules
- Speakers by alignment only: right-aligned bubble = "you", left-aligned = "them", centered
  text (timestamps, "Seen", "Delivered") dropped.
- Never ask for, print, or commit the API key. It lives in `.env` (ANTHROPIC_API_KEY, or the older
  OPENROUTER_API_KEY) on her Mac and as a Vercel secret. If she pastes a key in chat, tell her to revoke and replace it.
- `.env`, `data/conversations/`, `results/` hold secrets and other people's messages: never
  commit, upload, or share them.
- Bump PROMPT_VERSION in engine/prompts.py whenever prompts change.
- Python is standard library only and must run on macOS's built-in Python 3.9.

## Commands
```
python3 -m unittest discover -s tests
python3 harness/run_eval.py --dry-run --conversations tests/fixtures   # offline, stand-in model
python3 harness/run_eval.py --limit 3                                  # real run, needs .env
python3 harness/make_review.py                                         # blind rating page
python3 harness/score.py                                               # Gate 1 result
```

## Turning a new conversation into test cases
She exports a Messages thread to PDF (File > Print > Save as PDF). Then:
```
pip3 install pdfplumber pillow        # also needs poppler: brew install poppler
python3 tools/extract_pdf.py thread.pdf /tmp/thread.json /tmp/emoji
python3 tools/pdf_to_cases.py /tmp/thread.json <name> imessage <num_cases> data/conversations
```
Emoji in these PDFs are images; `pdf_to_cases.py` maps known image hashes to emoji (EMOJI dict).
Unknown emoji are dropped; look at the PNGs in the emoji folder and add them to the dict.
Check page breaks: a bubble split across pages should appear once, whole (the EDGE setting in
pdf_to_cases.py decides what counts as "at the page break"). A message repeated word for word is
kept unless it is a threaded-reply quote (marked by an "N Replies" label or a smaller font).
