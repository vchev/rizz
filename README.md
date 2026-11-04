# Reply Assistant

iPhone app that suggests replies that sound like you and fit the conversation.
See `CLAUDE.md` for the plan and rules.

| Folder | What lives there |
| --- | --- |
| `engine/` | Reply engine: prompts, OpenRouter call, reply parsing and filtering |
| `api/` | Web endpoint the app calls; keeps the API key server-side (see `api/README.md`) |
| `harness/` | Test run, blind rating page, Gate 1 scoring |
| `tools/` | Turn a Messages PDF into test cases |
| `tests/` | Unit tests: `python3 -m unittest discover -s tests` |
| `data/`, `results/` | Real conversations and run output. Git-ignored, never shared |

App code is Python standard library only and runs on macOS's built-in Python 3.9.
The PDF tools are the one exception: they need `pdfplumber`, `pillow` and poppler.
