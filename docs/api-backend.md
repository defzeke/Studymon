# API and backend

The rule the whole project is built around: **the Godot client never talks to an LLM provider.**
It talks only to our own API, which holds the Claude key. The API is a **stateless gateway**: it turns
a reviewer into questions with their answer keys and grades essays, and stores nothing. Worlds,
questions and answer keys live only in the device's save file ([`data-model.md`](data-model.md)).

- **Client wrapper:** `scripts/autoload/api.gd` (autoload `Api`)
- **Backend:** `backend/main.py` (routes, limits), `backend/ai.py` (Claude calls, answer-key checks,
  essay score), `backend/tests/`, `backend/evals/`
- **Consumers:** `SessionManager` (extraction), `battle.gd` (grading)

Status: **The editor and debug builds run on mocks; release builds use the server. Backend implemented; checked with unit tests and
against a stubbed Claude, not yet against the real model.**

---

## 1. Client surface

```gdscript
const RELEASE_URL := ""                     # the deployed HTTPS server; set before exporting
const DEV_USES_SERVER := false               # true: the editor talks to DEV_URL instead of the mock
const DEV_URL := "http://127.0.0.1:8000"     # not localhost: it can resolve to IPv6, which uvicorn ignores
var MOCK := OS.is_debug_build() and not DEV_USES_SERVER
var BASE_URL := DEV_URL if OS.is_debug_build() else RELEASE_URL
const EXTRACT_TIMEOUT := 180.0
const GRADE_TIMEOUT := 30.0

signal job_status(job_id: String, status: String, progress: float, result: Variant)
```

| Method | MOCK behaviour | Real behaviour |
|---|---|---|
| `new_job_id(kind)` | `"<kind>_<n>"`, unique per session | same |
| `upload_reviewer(job_id, topic, text, pdf)` | the mock extractor (§5), 0.8 s → `job_status(job_id, "completed", …)` | `processing`, then `POST /v1/extract` |
| `grade_battle_question(job_id, q, answer, mode)` | `mode "essay"` → `essay_offline()`; `"identification"` → score 0 (a near-miss stays a miss) | `POST /v1/grade` |
| `check_identification(q, answer, strict)` | on the device, never networked: `{verdict, feedback}` | same |
| `essay_offline(q, answer)` / `rubric_for(q)` | the offline essay mark ([`systems/battle.md`](systems/battle.md) §5) | used when the server cannot answer |
| `report_content(job_id, kind, text)` | `completed` at once | `POST /v1/reports` |
| `mock_get_topics()` | `job_status("topics", "completed", …, {topics: []})` | — |

### HTTP plumbing

Every call makes its **own `HTTPRequest`** (freed when done), so requests never cancel each other.
Every outcome reaches `job_status` under the caller's `job_id`:

| Outcome | Emitted |
|---|---|
| 2xx with an envelope whose `job_id` matches | the envelope's `status`, `progress`, `result` |
| network failure or timeout | `"failed"`, `"No connection to the study server."` |
| 429 (a daily limit, §6) | `"failed"`, `"You've reached today's AI limit. Try again tomorrow."` |
| other non-2xx | `"failed"`, `"The study server returned an error (<code>)."` |
| unreadable body, or a different `job_id` | `"failed"`, `"The study server sent an unreadable reply."` |

`SessionManager` only takes its own extraction id and `battle.gd` only its own grade id (rules §5).
Against a local server that is down, the failure arrives only at the timeout (30 s for a grade); with
no network at all, the address lookup fails at once.

### Auth

None: v1 has no accounts, and the client sends no `Authorization` header. Worlds and mastery never
leave the device; only the reviewer and typed answers are sent, to be processed and dropped. See §6
for what protects the gateway.

---

## 2. Endpoints

Every response is HTTP 200 with the job envelope; a problem the player should read is
`status: "failed"` with a message in `result`. Request validation errors are 422 (reported by the
client as a server error).

```jsonc
{"job_id": "<echoed>", "status": "completed" | "failed", "progress": 1.0, "result": …}
```

### `POST /v1/extract`: reviewer → questions + answer keys

```jsonc
// request: text, or a PDF
{"job_id": "extract_3", "topic_name": "Biology", "text": "…"}            // 80 – 200 000 chars
{"job_id": "extract_3", "topic_name": "Biology", "pdf_base64": "…"}      // ≤ 20 MB, ≤ 100 pages
// result
{"topic_id": "topic_biology", "questions": [question…]}                    // question shape: §5
```

One streamed Claude call with a JSON-schema structured output (`ai.QUESTION_SET_SCHEMA`),
`effort: "high"`, adaptive thinking and the server-side refusal fallback (`fallbacks: "default"`). The
reviewer is wrapped in `<reviewer>` tags as data. The system prompt (`ai.EXTRACT_SYSTEM`) carries the
generation rules of [`systems/gameplay-structure.md`](systems/gameplay-structure.md) §3.1.

The server then **checks every question and drops the ones the game cannot trust** (`ai.check_questions`):

| Check | On failure |
|---|---|
| `source` appears in the reviewer (whitespace and case ignored); for a PDF against its `pypdf` text, skipped when it has none (a scan) | dropped |
| a duplicate question text | dropped |
| Identification: its answer is not inside its question; `accepted` starts with `answer`, deduplicated | dropped / repaired |
| Multiple Choice: at least 3 distinct wrong options, none equal to the answer or an accepted alias; extras trimmed | dropped / repaired |
| Essay: 3–5 rubric points with weight > 0; weights rescaled to sum to 1; extras trimmed | dropped / repaired |

The server sets `id` (`q_<sha1 of the text>`) and `confidence` (1.0, −0.15 per repair), and caps the
bank at 45. Failures the player sees: too short, a PDF over the limits or unreadable, a refusal, an
answer cut off at `max_tokens`, rate limits, no usable questions.

### `POST /v1/grade`: one typed answer

```jsonc
{"job_id": "grade_12", "mode": "identification" | "essay", "question": "…", "answer": "<typed>",
 "expected": "…", "accepted": ["…"], "rubric": [{"point", "keywords", "weight"}],
 "model_answer": "…", "source": "…"}
// result, identification: {"score": 1.0 | 0.0, "feedback": "…"}
// result, essay:          {"score": 0..1, "covered": [bool per rubric point], "feedback": "…"}
```

The typed answer is wrapped in `<answer>` tags as data. For an essay, Claude returns per point
`{covered, evidence}` and the **server** scores it: a point counts only when its evidence is really in
the answer ([`systems/battle.md`](systems/battle.md) §5). `effort` is `low` for an Identification
check, `medium` for an essay. An essay request with no rubric fails.

### `GET /health`

`{"ok": true}`.

---

## 3. Models and cost

| Route | Model (`backend/ai.py`) | Rough cost per call |
|---|---|---|
| `/v1/extract` | `EXTRACT_MODEL = "claude-opus-5-5"` | $0.20 – 0.30 per reviewer (most of it the ~10k tokens of questions written) |
| `/v1/grade` | `GRADE_MODEL = "claude-opus-5-5"` | about $0.01 per essay, less for an Identification check |

Estimates, not measurements; record real figures after the first eval run. [`launch-plan.md`](launch-plan.md)
suggests Sonnet 5.5 for extraction and Haiku 5.5 for grading to cut cost; that is a one-constant change
per route, to be decided by the maintainer and checked with the evals.

---

## 4. Running the backend

```powershell
cd backend
copy .env.example .env      # put ANTHROPIC_API_KEY in it, or `ant auth login`
uv run --no-project --with-requirements requirements.txt uvicorn main:app --port 8000
# tests (no Claude calls)
uv run --no-project --with-requirements requirements.txt --with pytest --with httpx python -m pytest tests
# quality evals (calls Claude, costs money)
uv run --no-project --with-requirements requirements.txt python evals/run_evals.py --yes
```

The SDK reads `ANTHROPIC_API_KEY` from the environment. To use it from the editor, set
`Api.DEV_USES_SERVER = true` ([`skills.md`](skills.md) §*Use the real study server*).

**Evals** (`backend/evals/`): four reviewers (biology, Philippine history, economics, programming) and
seven graded answers (essay perfect, partial, off-topic, filler, injection; Identification synonym,
broader term). A reviewer passes when ≥ 80 % of its generated questions survive the checks and every
type has ≥ 3; an answer passes when its score lands in its expected band. Run it on every prompt or
model change. **Not yet run.**

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

The **mock extractor** (`Api._build_questions_from_text`) produces the older subset (`text`, `type`,
`difficulty`, `answer`, `distractors`, `key_concepts`, `source`, `confidence`): up to 12 sentences of
pasted text, rotating the three types, with the answer term blanked (`_____`) out of Identification
and Multiple Choice questions. Its essays still quote the passage they ask about. A PDF cannot be read
on mocks and gets the five canned fallback questions.

---

## 6. Protection, consent and reports

**Consent.** Nothing is sent until the player agrees: the categorizer shows `GameState.AI_CONSENT_TEXT`
before the first upload, and Settings can withdraw it (`GameState.ai_consent`, saved). Without it
`upload_reviewer()` and `grade_battle_question()` fail at once on the real path, so essays grade on
the device. The text must stay true to what the server sends (Apple 5.1.2(i)).

**Daily limits.** No accounts means anyone who finds the URL could spend the key, so `main.py` counts
calls per client IP per UTC day (`DAILY_LIMITS`: 5 extracts, 300 grades, 20 reports) and for everyone
together (`DAILY_TOTAL`, 20 000). Over a limit the reply is HTTP **429** with a `failed` envelope, and the
client shows "You've reached today's AI limit. Try again tomorrow." The IP is the last
`X-Forwarded-For` entry (the one the host's proxy appends) or the socket address. The counts live in
memory per instance, so they are a brake, not a guarantee: the real cap is the Anthropic workspace's
**monthly spend limit**, which must be set before release.

### `POST /v1/reports`: flag AI content

```jsonc
{"job_id": "report_4", "kind": "question" | "feedback", "text": "…"}   // ≤ 4000 chars
// result: {"ok": true}
```

Google Play requires an in-app way to report offensive AI output. The categorizer's **Report** on each
question row and the battle review beat's **Report** call `Api.report_content()`. The server only
logs the report (`log.warning`); read reports in the host's log viewer.

### Still needed before release

- Set the workspace monthly spend limit; later add App Attest / Play Integrity
  ([`launch-plan.md`](launch-plan.md) §5.3).
- Set `RELEASE_URL` to the deployed HTTPS server, and the policy URLs in `settings.gd`, before exporting.
- If accounts arrive, send `Authorization: Bearer <token>` ([`launch-plan.md`](launch-plan.md) §5.2).
