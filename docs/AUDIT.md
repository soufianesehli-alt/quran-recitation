# Phase 1 — Repository Audit

Date: 2026-11-08 · Repo: `soufianesehli-alt/quran-recitation` (branch `main`, HEAD `012ee27`)

## 1. What exists

| Path | What it is |
|---|---|
| `main.py` (223 lines) | FastAPI app "المثابة — Quran API", the whole backend |
| `requirements.txt` | fastapi 0.115.0, uvicorn 0.30.6, anthropic 0.40.0, httpx 0.27.2, python-dotenv, pydantic ≥ 2.9.2 |
| `Procfile` | `web: uvicorn main:app --host 0.0.0.0 --port $PORT` (Render) |
| `.python-version` | `3.11.9`, **UTF-16 encoded** (see §3) |
| `.gitignore` | Contains only `.env`, **UTF-16 encoded**, so git does not read it |
| `.env`, `.env.example` | One variable, `ANTHROPIC_API_KEY`. **`.env` is tracked in a public repo** |
| `venv/` (~2,770 files, ~60 MB) | A committed Windows virtualenv |
| `__pycache__/main.cpython-311.pyc` | Committed bytecode |

**There is no Flutter frontend in this repository.** The spec says one exists. The only other
repository visible to this session is `soufianesehli-alt/AVISMEN-wallet`, which by its name looks
unrelated, so I did not open it. → **Decided: no frontend exists. The app is built fresh in `app/`.**

### Backend endpoints

| Endpoint | Behaviour | External calls |
|---|---|---|
| `GET /surahs` | Proxies `api.quran.com/api/v4/chapters?language=ar` | quran.com |
| `GET /verses/range?surah&start_ayah&end_ayah&riwaya` | Words of several ayahs in parallel | quran.com |
| `GET /verse?surah&ayah&riwaya` | Words of one ayah (`text_uthmani`) | quran.com |
| `POST /tajweed/explain` | Asks Claude (`claude-sonnet-4-6`) for a one-sentence explanation of a wrong word | Anthropic API (paid) |
| `POST /check` | Fetches the ayah, asks Claude to compare it with `transcribed_text`, returns JSON `{is_correct, score, errors[], general_feedback}` | quran.com + Anthropic API |
| `GET /page/{n}` | Words of a Madina-mushaf page (1–604) | quran.com |
| `GET /surah/{id}/meta` | Surah metadata and page range | quran.com |
| `GET /health` | `{"status":"ok"}` | — |

## 2. What is reusable

| Item | Reuse in V1? | Notes |
|---|---|---|
| `/check` contract (`surah, ayah, riwaya, transcribed_text`) | Kept as is | Ground rule: never break it. V1 does not call it (V1 makes no network calls). |
| Endpoint shapes (`/verse`, `/verses/range`, `/page`) | Design reference only | The V1 app reads the bundled SQLite instead. |
| Arabic error strings and riwaya labels (`حفص عن عاصم`, `ورش عن نافع`) | Yes | Moved to the app's ARB file. |
| FastAPI app | V2 base | `/v2` WebSocket goes next to it in V2; `/check` stays untouched. |
| Claude-based tajweed judgement | **No** | See §3.2. |
| Flutter frontend | Unknown | Not in this repo. |

## 3. Problems found (reported, not fixed: they need the product owner's go-ahead)

### 3.1 Security: committed secret and broken `.gitignore` — **urgent**
- `.env` is tracked in a **public** repository. I did not read its value. If it holds a real
  Anthropic key, consider that key leaked: **revoke it in the Anthropic console and create a new
  one**, then set it only as a Render environment variable.
- The cause is that `.gitignore` is saved as UTF-16 (with BOM), which git cannot parse, so
  `.env`, `venv/` and `__pycache__/` were all committed.
- In Phase 1 I **rewrote `.gitignore` as UTF-8** and, with approval, untracked
  `venv/ __pycache__/ .env` (`git rm -r --cached`). Removing them from the tip does not remove them from
  history; rotating the key is the real fix.
- `.python-version` is also UTF-16. Render may be ignoring it. Left untouched, because changing it
  could change the Python version of the live deployment.

### 3.2 Religious accuracy: `/check` with `riwaya=warsh` uses Hafs text
- `_fetch_verse_words` always reads `text_uthmani` from quran.com, which is the Hafs (Madina)
  text. The `riwaya` parameter is only echoed back. So a correct Warsh recitation is compared
  against Hafs wording and can be reported as wrong. Example: Al-Fātiḥa 1:4 is `مَٰلِكِ` in Hafs
  and `مَلِكِ` in Warsh.
- Ayah **numbering** also differs (Kufan vs Madani). For example, in Warsh the basmala is not
  counted as ayah 1 of Al-Fātiḥa. So `surah:ayah` keys point to different text under the two
  riwayat.
- `/check` judges tajweed from **transcribed text only**. Text from speech recognition carries no
  durations, nasalisation or makharij, so any "rule" the model returns for madd or ghunnah is
  unsupported by the input. This breaks ground rule 5 (a false correction is worse than a missed
  one).
- Not changed (ground rule: never break `/check`). Proposed for V2: route Warsh to a Warsh text
  source, and limit the LLM to wording differences.

### 3.3 Robustness and cost (backend, minor)
- The synchronous `anthropic.Anthropic` client is called inside `async` endpoints, which blocks
  the event loop under load.
- `CORS *`, no authentication and no rate limit on endpoints that call a paid API: anyone can
  spend the key's credit.
- `/check` returns `score: 0, is_correct: false` when the model's JSON fails to parse, which shows
  the user an error that was never detected.
- The `/page` endpoint requests `per_page=50` and does not paginate.

I could not reach `https://quran-recitation.onrender.com` from this sandbox (blocked by its
network policy), so the live deployment was not tested.

## 4. Decisions taken in Phase 1

1. **The backend stays at the repo root**, not in `backend/` as §4 of the spec shows. Moving it
   would change the Render build root (Procfile and start command) and could take `/check`
   offline. Proposal: move it later together with the Render "Root Directory" setting, once
   approved.
2. The Flutter app is created as a new project in `app/`. If an existing Flutter frontend turns
   up, I will audit it and merge in whatever is reusable (screens, assets) before Phase 3.
3. No existing file was deleted or moved.
