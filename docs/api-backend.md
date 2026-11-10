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
| `upload_reviewer(job_id, topic, text, file, file_type, existing, types)` | `offline_questions()` on the text in `types` (§5), 0.8 s → `job_status(job_id, "completed", …)` | `processing`, then `POST /v1/extract` |
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
// optional on either: "types": ["multiple_choice", "identification", "essay"]  (1–3; default all three)
// result
{"topic_id": "topic_biology", "questions": [question…], "reviewer_text": "…"}         // question shape: §5
// result when the AI could not write them (budget spent, or the call failed)
{"topic_id": "topic_biology", "questions": [], "offline": true, "note": "<why>", "reviewer_text": "…"}
```

| `file_type` | Limit | Sent to the model as | Grounding text |
|---|---|---|---|
| `pdf` | 20 MB, 100 pages | its `pypdf` text in layout mode (a quiz item's lines stay together; plain mode is the fallback), spaces collapsed; a **scan** (no text layer) as up to 10 page images rendered by `pypdfium2` | that text, or none for a scan |
| `png`, `jpeg`, `webp` (a photo of notes) | 5 MB | an image | none: the source check is skipped |
| `docx`, `pptx` | 20 MB | text, converted here (`python-docx`, `python-pptx`; tables and slide text) | that text |

Gemma has no PDF input, so the server always sends text or images.

**Long reviewers go in parts.** Text over `CHUNK_CHARS` (6,000) is split between paragraphs, so a quiz
item stays whole, and up to `MAX_PARALLEL` (4) parts are asked at the same time
(`ai.generate_questions`). A part that fails is asked once more, then skipped; the call fails only when
every part fails. Measured 2026-11-09 on a 13-page, 78-item quiz PDF through Google: 4 parts, 70–120 s,
76–91 questions kept. Back-to-back runs sometimes lost parts to Google errors.

`reviewer_text` (the text above, capped at 200 000 chars; empty for a photo or scan) goes back so the
device can keep it with the world for "More questions". Questions whose text is in `existing` are
dropped, and so are questions of a type not in `types`.

**Question types.** The model is told to write only the `types` the player ticked, at least 3 of each.
**Quiz-style reviewers.** When the reviewer already has questions (a quiz, Q&A list, numbered items
with an answer key or a marked choice), the prompt keeps each one as a question and takes its answer
from the key, the marked choice or the notes. A question with no answer anywhere is left out.

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
  the process. `AI_JSON_SCHEMA=0` never sends it: Google's endpoint accepts it but then stops Gemma
  after one question.

The reply is parsed after any `<thought>…</thought>` block, which Gemma on Google's endpoint can send
first.

The reply is parsed tolerantly (`ai.parse_json`: code fences and stray text are ignored), and a reply
that does not parse is asked for once more.

The server then **checks every question and drops the ones the game cannot trust** (`ai.check_questions`):

| Check | On failure |
|---|---|
| an item that is not an object, or a list field that is not a list | dropped / emptied |
| every sentence of `source` appears in the reviewer (whitespace, case and Unicode forms such as math letters ignored; a quiz item's source may join its question to its answer line); skipped for a photo or scan | dropped |
| a duplicate question text | dropped |
| Identification: its answer is not inside its question; `accepted` starts with `answer`, deduplicated | dropped / repaired |
| Multiple Choice: a leading option letter (`C. `) is stripped from the answer and the wrong options; at least 3 distinct wrong options, none equal to the answer or an accepted alias; extras trimmed | dropped / repaired |
| Essay: 3–5 rubric points with weight > 0; weights rescaled to sum to 1; extras trimmed | dropped / repaired |

The server sets `id` (`q_<sha1 of the text>`) and `confidence` (1.0, −0.15 per repair), and caps the
bank at **100** (`MAX_QUESTIONS`), so a long quiz keeps every item. Notes still get at most 30 per
part from the prompt. Failures the
player sees: too short, a PDF over the limits or unreadable, a photo or scan when the AI is
unavailable.

### `POST /v1/grade`: one typed answer

```jsonc
{"job_id": "grade_12", "mode": "identification" | "essay", "question": "…", "answer": "<typed>",
 "expected": "…", "accepted": ["…"], "rubric": [{"point", "keywords", "weight"}],
 "model_answer": "…", "source": "…"}
// result, identification: {"score": 1.0 | 0.0, "feedback": "…"}
// result, essay:          {"score": 0..1, "covered": [bool per rubric point, true when fully covered], "feedback": "…"}
```

The typed answer is wrapped in `<answer>` tags as data. For an essay, the model returns per point
`{credit: full | partial | none, evidence}` and the **server** scores it: full is worth the point's
weight, partial half, and a point earns credit only when its evidence is really in the answer
([`systems/battle.md`](systems/battle.md) §5). Grading runs at temperature 0, and words addressed to
the grader are ignored. Feedback comes in the answer's language. Every model call retries a Google or
Cloudflare error up to 3 times (`max_retries`). Measured 2026-11-09 on Google: the 15 graded answers in
`evals/grading_cases.json` all passed, twice in a row (12 of 15 before). An essay request with no rubric fails. When
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
| `AI_JSON_SCHEMA` | `1`: send the schema as `response_format` too (§2) |

**Google, for development.** The same Gemma 4 runs on Google's Gemini API through its
OpenAI-compatible endpoint. The local `backend/.env` can point there:
`AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/`, `AI_API_KEY` = a Google AI
Studio key, both models `gemma-4-26b-a4b-it`, `NEURONS_PER_M_IN` and `_OUT` = `0` (Google counts no
neurons; its own rate limits answer 429, and the game goes offline), and `AI_JSON_SCHEMA=0`. Measured
2026-11-09 on a quiz-style PDF: every quiz item kept with its answer-key answer. Google sometimes
answers 500, and the call then goes offline. Release stays on Cloudflare (see the terms note below).

**Cost: $0** on Cloudflare's Workers Free plan, which includes **10,000 neurons a day** (UTC) for the
whole account. The plan cannot bill past that: further calls fail, and the game falls back offline.

| Route | Rough tokens | Neurons per call |
|---|---|---|
| `/v1/extract` | ~5k in, ~8k out per part (up to 30 questions) | ~260 per part |
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
# quality evals (real model: free, but an estimated ~5,000 of the day's 10,000 neurons)
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
- **Reviewers:** nine, in `evals/reviewers/`. The biology one is also sent again as a Word file and as
  a photo-like PNG (built at run time).

  | Reviewer | Tests |
  |---|---|
  | biology, Philippine history, economics, programming | the plain case: about 170–200 words of English prose |
  | `earth_science_long` | a long reviewer (1,821 words): coverage across the whole text |
  | `chemistry_tables` | Markdown tables: sources quoted from table rows |
  | `bahagi_ng_pananalita_fil` | Filipino: every question in the reviewer's language |
  | `algebra_geometry_math` | formulas with Unicode symbols (², √, ±, π, −) |
  | `short_simple_machines` | a very short reviewer (102 words): the minimum of 3 per type |

- **Graded answers:** fifteen in `evals/grading_cases.json`:
  - essays: perfect, partial, off-topic, filler, an injected instruction, and an instruction hidden
    in a partial answer (which must stay partial);
  - essays in Filipino: full, partial, off-topic;
  - Identification: a synonym, an abbreviation and a reordered Filipino term (all pass); a broader
    term, the wrong Filipino term and an injected instruction (all fail).
- **Pass rules:**
  - A reviewer passes when ≥ 80 % of its generated questions survive the checks, every type has ≥ 3,
    and it got at least 60 % of the questions the prompt asks for (one per 100 words, 9 to 30).
  - A reviewer whose file name ends in `_fil` also needs ≥ 80 % of its questions to read as Filipino
    (common function words such as *ang*, *ng*, *mga*).
  - An answer passes when its score lands in its expected band.
- **When to run:** on every prompt or model change, at most once a day. One run is estimated at about
  5,000 of the day's 10,000 neurons, the same allowance the game uses. It prints what it spent.
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
- The text must stay true to what the server sends: reviewer text, files and photos, and the
  battle answers the device cannot settle (essays, and Identification near-misses). So must
  `site/privacy.html` ([`store-listing.md`](store-listing.md) §1).

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
- the small flag (⚑) on each row of the battle's end-of-run **Review answers** list, beside the
  row's Easy / Hard rating.

The server only logs the report (`log.warning`); read reports in the host's log viewer.

### Still needed before release

Step by step in [`next-steps.md`](next-steps.md) Phase 1:
1. A Cloudflare account and token, and a check of Cloudflare's terms for a 13+ app.
2. A local run against the real model.
3. The eval run, prompt tuning, and the measured neurons recorded here (§3).
4. The integration played in the editor.
5. The Render deploy and the `X-Forwarded-For` limit test (§6).
6. `RELEASE_URL` in `api.gd`.
7. The policy pages, and their URLs in `settings.gd`.

**Planned (Phase 2): sessions.** `POST /v1/session` turns a Google Play Games server auth code into a
session token. The AI routes then require `Authorization: Bearer`, and limits count per player.
Not built; the design is in [`next-steps.md`](next-steps.md) Phase 2.

Later: Play Integrity, so only the real app can call the server.
