# API and backend

The rule the whole project is built around: **the Godot client never talks to an LLM provider.**
It talks only to our own API, which holds the AI key. The API is a **stateless gateway**: it turns a
reviewer into questions with their answer keys and grades typed answers, and stores nothing. Worlds,
questions and answer keys live only in the player's save file ([`data-model.md`](data-model.md)).

- **Client wrapper:** `scripts/autoload/api.gd` (autoload `Api`)
- **Backend:** `backend/main.py` (routes, limits, the daily neuron budget), `backend/ai.py` (model
  calls, answer-key checks, essay score), `backend/tests/`, `backend/evals/`
- **Model:** **Gemma 4 26B on Cloudflare Workers AI** (`@cf/google/gemma-4-26b-a4b-it`), free up to
  10,000 neurons a day, behind any OpenAI-compatible endpoint (§3)
- **Hosting:** Render's free web service (`render.yaml`, §4)
- **Consumers:** `SessionManager` (extraction), `battle.gd` (grading)

Status: **the editor and debug builds run on mocks; release builds use the server.** The backend is
checked with unit tests against a stubbed model. It has **not yet been run against Gemma**: that
needs a Cloudflare account ([`launch-plan.md`](launch-plan.md) §5).

---

## 1. Client surface

```gdscript
const RELEASE_URL := ""                     # the deployed HTTPS server; set before exporting
const DEV_USES_SERVER := false               # true: the editor talks to DEV_URL instead of the mock
const DEV_URL := "http://127.0.0.1:8000"     # not localhost: it can resolve to IPv6, which uvicorn ignores
var MOCK := OS.is_debug_build() and not DEV_USES_SERVER
var BASE_URL := DEV_URL if OS.is_debug_build() else RELEASE_URL
const EXTRACT_TIMEOUT := 240.0               # a whole bank, plus the free host's ~1 min wake-up
const GRADE_TIMEOUT := 75.0

signal job_status(job_id: String, status: String, progress: float, result: Variant)
```

| Method | MOCK behaviour | Real behaviour |
|---|---|---|
| `new_job_id(kind)` | `"<kind>_<n>"`, unique per session | same |
| `upload_reviewer(job_id, topic, text, file, file_type, existing)` | `offline_questions()` on the text (§5), 0.8 s → `job_status(job_id, "completed", …)` | `processing`, then `POST /v1/extract` |
| `grade_battle_question(job_id, q, answer, mode)` | `mode "essay"` → `essay_offline()`; `"identification"` → score 0 (a near-miss stays a miss) | `POST /v1/grade` |
| `check_identification(q, answer, strict)` | on the device, never networked: `{verdict, feedback}` | same |
| `essay_offline(q, answer)` / `rubric_for(q)` | the offline essay mark ([`systems/battle.md`](systems/battle.md) §5) | used whenever the server cannot answer |
| `offline_questions(text)` | the device's question builder (§5) | used when extraction comes back `offline` |
| `wake_server()` | nothing | fire-and-forget `GET /health`, so the sleeping free host is up by the first real call; the World Builder and every battle call it on open |
| `report_content(job_id, kind, text)` | `completed` at once | `POST /v1/reports` |
| `mock_get_topics()` | `job_status("topics", "completed", …, {topics: []})` | — |

### HTTP plumbing

Every call makes its **own `HTTPRequest`** (freed when done), so requests never cancel each other.
Every outcome reaches `job_status` under the caller's `job_id`:

| Outcome | Emitted |
|---|---|
| 2xx with an envelope whose `job_id` matches | the envelope's `status`, `progress`, `result` |
| network failure or timeout | `"failed"`, `"No connection to the study server."` |
| 429 (a daily limit or the spent budget, §6) | `"failed"`, `"You've reached today's AI limit. Try again tomorrow."` |
| other non-2xx | `"failed"`, `"The study server returned an error (<code>)."` |
| unreadable body, or a different `job_id` | `"failed"`, `"The study server sent an unreadable reply."` |

`SessionManager` only takes its own extraction id and `battle.gd` only its own grade id (rules §5).
Any failed grade falls back to the device: `essay_offline()` for an essay, a miss for a near-miss
Identification answer.

### Auth

None: there are no accounts of our own, and the client sends no `Authorization` header. Worlds and
mastery never reach the server; only the reviewer and typed answers are sent, to be processed and
dropped. See §6 for what protects the gateway.

---

## 2. Endpoints

Every response is the job envelope; a problem the player should read is `status: "failed"` with a
message in `result`. Request validation errors are 422 (reported by the client as a server error).

```jsonc
{"job_id": "<echoed>", "status": "completed" | "failed", "progress": 1.0, "result": …}
```

### `POST /v1/extract`: reviewer → questions + answer keys

```jsonc
// request: text, or a file
{"job_id": "extract_3", "topic_name": "Biology", "text": "…"}                         // 80 – 200 000 chars
{"job_id": "extract_3", "topic_name": "Biology", "file_base64": "…", "file_type": "pdf"}
// optional on either: "existing": ["question text", …]  (≤ 60, "More questions": do not repeat these)
// result
{"topic_id": "topic_biology", "questions": [question…], "reviewer_text": "…"}         // question shape: §5
// result when the AI could not write them (budget spent, or the call failed)
{"topic_id": "topic_biology", "questions": [], "offline": true, "note": "<why>", "reviewer_text": "…"}
```

| `file_type` | Limit | Sent to the model as | Grounding text |
|---|---|---|---|
| `pdf` | 20 MB, 100 pages | its `pypdf` text; a **scan** (no text layer) as up to 10 page images rendered by `pypdfium2` | that text, or none for a scan |
| `png`, `jpeg`, `webp` (a photo of notes) | 5 MB | an image | none: the source check is skipped |
| `docx`, `pptx` | 20 MB | text, converted here (`python-docx`, `python-pptx`; tables and slide text) | that text |

Gemma has no PDF input, so the server always sends text or images.

`reviewer_text` (the text above, capped at 200 000 chars; empty for a photo or scan) goes back so the
device can keep it with the world for "More questions". Questions whose text is in `existing` are
dropped.

**Offline answer.** When the day's budget (§6) is spent, or the model call fails, or no question
survives the checks, the result is `offline` with the reviewer's text. `SessionManager` then builds
the questions with `Api.offline_questions()`, and the World Builder says why. A photo or a scan has no
text to build from, so it fails with the reason instead.

One chat call (`ai._chat`). The system prompt (`ai.EXTRACT_SYSTEM`) carries the generation rules of
[`systems/gameplay-structure.md`](systems/gameplay-structure.md) §3.1 and asks for everything **in the
reviewer's own language** (for example Filipino or English). The reviewer is wrapped in `<reviewer>`
tags as data.

The JSON schema (`ai.QUESTION_SET_SCHEMA`) is sent two ways:
- in the prompt;
- as `response_format` (`json_schema`). If the endpoint refuses that, it is dropped for the rest of
  the process.

The reply is parsed tolerantly (`ai.parse_json`: code fences and stray text are ignored), and a reply
that does not parse is asked for once more.

The server then **checks every question and drops the ones the game cannot trust** (`ai.check_questions`):

| Check | On failure |
|---|---|
| an item that is not an object, or a list field that is not a list | dropped / emptied |
| `source` appears in the reviewer (whitespace and case ignored); skipped for a photo or scan | dropped |
| a duplicate question text | dropped |
| Identification: its answer is not inside its question; `accepted` starts with `answer`, deduplicated | dropped / repaired |
| Multiple Choice: at least 3 distinct wrong options, none equal to the answer or an accepted alias; extras trimmed | dropped / repaired |
| Essay: 3–5 rubric points with weight > 0; weights rescaled to sum to 1; extras trimmed | dropped / repaired |

The server sets `id` (`q_<sha1 of the text>`) and `confidence` (1.0, −0.15 per repair), and caps the
bank at **30** (`MAX_QUESTIONS`; fewer output tokens keep more of the free allowance). Failures the
player sees: too short, a PDF over the limits or unreadable, a photo or scan when the AI is
unavailable.

### `POST /v1/grade`: one typed answer

```jsonc
{"job_id": "grade_12", "mode": "identification" | "essay", "question": "…", "answer": "<typed>",
 "expected": "…", "accepted": ["…"], "rubric": [{"point", "keywords", "weight"}],
 "model_answer": "…", "source": "…"}
// result, identification: {"score": 1.0 | 0.0, "feedback": "…"}
// result, essay:          {"score": 0..1, "covered": [bool per rubric point], "feedback": "…"}
```

The typed answer is wrapped in `<answer>` tags as data. For an essay, the model returns per point
`{covered, evidence}` and the **server** scores it: a point counts only when its evidence is really in
the answer ([`systems/battle.md`](systems/battle.md) §5). An essay request with no rubric fails. When
the day's budget is spent the reply is a 429, and the battle grades on the device.

### `GET /health`

`{"ok": true}`. `Api.wake_server()` calls it to wake the sleeping free host.

---

## 3. Models and cost

| Setting (env var, `backend/ai.py`) | Default |
|---|---|
| `AI_BASE_URL` | `https://api.cloudflare.com/client/v4/accounts/<account id>/ai/v1` (Cloudflare's OpenAI-compatible endpoint) |
| `AI_API_KEY` | a Cloudflare API token with Workers AI permission |
| `EXTRACT_MODEL`, `GRADE_MODEL` | `@cf/google/gemma-4-26b-a4b-it` (Gemma 4, Apache 2.0, 256K context, vision) |
| `NEURONS_PER_M_IN`, `NEURONS_PER_M_OUT` | 9,091 and 27,273 (Cloudflare's price for that model, in neurons per million tokens) |

**Cost: $0** on Cloudflare's Workers Free plan, which includes **10,000 neurons a day** (UTC) for the
whole account. The plan cannot bill past that: further calls fail, and the game falls back offline.

| Route | Rough tokens | Neurons per call |
|---|---|---|
| `/v1/extract` | ~5k in, ~8k out (30 questions) | ~260 |
| `/v1/grade`, essay | ~1.5k in, ~0.2k out | ~20 |
| `/v1/grade`, Identification check | ~0.5k in, ~0.1k out | ~7 |

So a day covers roughly **20 reviewers and 200 graded answers across all players**. These are
estimates; the eval run prints the real neurons (§4). Record them here once measured.

Changing provider or model is configuration only, because any OpenAI-compatible endpoint works. Past
the free allowance, Workers Paid is $5 a month plus $0.011 per 1,000 neurons. **Gemma on Google's own
Gemini API is not an option for this game:** its terms forbid apps likely to be used by under-18s, and
free-tier inputs may be reviewed and used for training ([`launch-plan.md`](launch-plan.md) §1).

---

## 4. Running the backend

```powershell
cd backend
copy .env.example .env      # set AI_BASE_URL (your Cloudflare account id) and AI_API_KEY
uv run --no-project --with-requirements requirements.txt uvicorn main:app --port 8000 --env-file .env
# tests (no model calls)
uv run --no-project --with-requirements requirements.txt --with pytest --with httpx python -m pytest tests
# quality evals (real model: free, but uses ~3,000 of the day's neurons)
uv run --env-file .env --no-project --with-requirements requirements.txt python evals/run_evals.py --yes
```

To use the server from the editor, set `Api.DEV_USES_SERVER = true` ([`skills.md`](skills.md) §*Use
the real study server*).

**Deploy:** `render.yaml` (repo root) is a Render Blueprint for a **free web service** built from
`backend/`. Put `AI_BASE_URL` and `AI_API_KEY` in the Render dashboard as secret environment
variables, then set `Api.RELEASE_URL` to its `https://…onrender.com` address. The free service sleeps
after 15 idle minutes and takes about a minute to wake: `Api.wake_server()` and the longer timeouts
(§1) absorb that. After the first deploy, check in the logs that `X-Forwarded-For`'s last entry is
the player's address (§6); if Render puts its own proxy last, take the entry before it.

**Evals** (`backend/evals/`):
- **Reviewers:** four (biology, Philippine history, economics, programming), plus the biology one
  again as a Word file and as a photo-like PNG (built at run time).
- **Graded answers:** seven (essay perfect, partial, off-topic, filler, injection; Identification
  synonym, broader term).
- **Pass rules:** a reviewer passes when ≥ 80 % of its generated questions survive the checks and
  every type has ≥ 3. An answer passes when its score lands in its expected band.
- **When to run:** on every prompt or model change. It prints the neurons it spent.
- **Status: not yet run against Gemma.**

---

## 5. The question shape (both paths)

`SessionManager._on_job_status` takes any completed envelope with `result.questions`, passes each
through `normalize_question()`, and defaults a missing `confidence` to 0.7.

```jsonc
{
  "id": "q_1a2b3c4d5e",
  "type": "identification",               // or "essay", "multiple_choice"
  "difficulty": "easy",                   // "medium", "hard"
  "text": "Which organelle holds chlorophyll?",
  "answer": "chloroplast",
  "accepted": ["chloroplast", "chloroplasts"],     // Identification
  "distractors": ["mitochondrion", "nucleus", "ribosome"],   // Multiple Choice
  "rubric": [{"point": "…", "keywords": ["…"], "weight": 0.4}],   // Essay
  "key_concepts": ["…"],                  // rubric points (Essay) or [answer]
  "model_answer": "…",
  "explanation": "…",
  "source": "…verbatim reviewer excerpt…",
  "confidence": 1.0
}
```

The **offline builder** (`Api.offline_questions`) produces the older subset (`text`, `type`,
`difficulty`, `answer`, `distractors`, `key_concepts`, `source`, `confidence`):
- it takes up to 12 sentences of text and rotates the three types;
- the answer term is blanked (`_____`) out of Identification and Multiple Choice questions;
- its essays still quote the passage they ask about;
- it returns `[]` when the text has no usable sentences.

The mock uses it too, and on mocks a PDF (which the device cannot read) gets the five canned fallback
questions.

---

## 6. Protection, consent and reports

**Consent.** Nothing is sent until the player agrees.
- The World Builder shows `GameState.AI_CONSENT_TEXT` before the first upload. It names Gemma and
  Cloudflare Workers AI.
- Settings can withdraw it (`GameState.ai_consent`, saved).
- Without consent, `upload_reviewer()` and `grade_battle_question()` fail at once on the real path,
  so essays grade on the device.
- The text must stay true to what the server sends.

**Daily neuron budget.** The free allowance is shared by every player, so `main.py` meters it:
- Each model call reports the neurons it used (`ai.spend` → `main.spend`, from the reply's token
  usage).
- A route only starts a call when its likely cost (`LIKELY_NEURONS`: extract 400, grade 30) still
  fits under `DAILY_NEURONS` (9,000, just under Cloudflare's 10,000).
- After that, extraction answers `offline` and grading answers 429, and both fall back on the device.
- The count lives in memory, so a restart clears it (the free host restarts after sleeping). The
  Workers Free plan cannot bill past its allowance either way.

**Daily limits.** No accounts means anyone who finds the URL could spend the allowance.
- `main.py` counts calls per client IP per UTC day (`DAILY_LIMITS`: 5 extracts, 300 grades, 20
  reports) and for everyone together (`DAILY_TOTAL`, 20,000).
- Over a limit the reply is HTTP **429** with a `failed` envelope.
- The IP is the last `X-Forwarded-For` entry (the one the host's proxy appends) or the socket
  address. Verify this on Render (§4).

### `POST /v1/reports`: flag AI content

```jsonc
{"job_id": "report_4", "kind": "question" | "feedback", "text": "…"}   // ≤ 4000 chars
// result: {"ok": true}
```

Google Play requires an in-app way to report offensive AI output. These call `Api.report_content()`:
- the World Builder's **Report** on each question row;
- each row of the battle's end-of-run **Review answers** list.

The server only logs the report (`log.warning`); read reports in the host's log viewer.

### Still needed before release

- A Cloudflare account and token, and an eval run against Gemma
  ([`launch-plan.md`](launch-plan.md) §5).
- Deploy on Render, then set `RELEASE_URL` and the policy URLs in `settings.gd` before exporting.
- Read Cloudflare's Self-Serve Subscription Agreement and the Workers AI terms for anything on apps
  used by teens ([`launch-plan.md`](launch-plan.md) §1).
- Later: Play Integrity, so only the real app can call the server.
