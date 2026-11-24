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
- **Hosting:** Google Cloud Run from `backend/Dockerfile`, with the Gemini key as a Cloud Run secret
  (§4); Render's free web service (`render.yaml`) still works for the Cloudflare setup
- **Consumers:** `SessionManager` (extraction), `battle.gd` (grading)

Status: **the editor uses the local server (or the mock); every exported build, a debug tester APK
too, uses `RELEASE_URL`, and a debug APK falls back to the mock until it is set.** The backend is
checked with unit tests against a stubbed model. It has **not yet been run against Gemma**: that
needs a Cloudflare account ([`launch-plan.md`](launch-plan.md) §5).

---

## 1. Client surface

```gdscript
const RELEASE_URL := ""                     # the deployed HTTPS server; set before exporting
const DEV_USES_SERVER := true                # false: debug builds play on the mock
const DEV_URL := "http://127.0.0.1:8000"     # not localhost: it can resolve to IPv6, which uvicorn ignores
var BASE_URL := DEV_URL if OS.has_feature("editor") else RELEASE_URL   # exports never use DEV_URL
var MOCK := OS.is_debug_build() and (not DEV_USES_SERVER or BASE_URL == "")
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

Gemma has no PDF input, so the server always sends text or images. Text from a file is cut at 200 000
chars (`MAX_CHARS`), the same as pasted text.

**Long reviewers go in parts.** Text over `CHUNK_CHARS` (6,000) is split between paragraphs, so a quiz
item stays whole, and up to `MAX_PARALLEL` (4) parts are asked at the same time
(`ai.generate_questions`). There are never more than `MAX_PARTS` (6): a longer text gets bigger parts,
since each part's answer is what costs neurons. Each part is asked for at most
`ceil(MAX_QUESTIONS / parts)` questions (30 for one part, at least 3 per type). A part whose answer is
cut off at `max_tokens` is asked once more for half as many; a part that fails any other way is
skipped (a busy service has already been asked again). The call fails only when every part fails. The
whole extraction stops after `EXTRACT_SECONDS` (200), under the game's 240 s wait. Measured 2026-11-09 on a 13-page, 78-item quiz PDF through Google: 4 parts, 70–120 s,
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
tags as data. It ends with one worked example per type, on the water cycle (a topic no eval reviewer
covers), and asks that every essay rubric point state the fact itself ("the smooth ER makes lipids"),
never a label for it ("Mention of structure"): the grader can only check what a point says. That rule
took the labelled good questions from 66 % to 89 % (§4).

Each type leaves out the fields it does not use (an Identification item has no `distractors`,
`rubric` or `model_answer`), so only `type`, `difficulty`, `text`, `answer`, `explanation` and
`source` are required: the answer is about 14 % shorter. The server fills a missing `model_answer`
with the answer.

The JSON schema (`ai.QUESTION_SET_SCHEMA`) is sent two ways:
- in the prompt;
- as `response_format` (`json_schema`). If the endpoint refuses that, that one call goes again
  without it; the next call tries it again. `AI_JSON_SCHEMA=0` never sends it: Google's endpoint accepts it but then stops Gemma
  after one question.

The reply is parsed after any `<thought>…</thought>` block, which Gemma on Google's endpoint can send
first.

The reply is parsed tolerantly (`ai.parse_json`: code fences and stray text are ignored), and a reply
that does not parse is asked for once more.

The server then **checks every question and drops the ones the game cannot trust** (`ai.check_questions`):

| Check | On failure |
|---|---|
| an item that is not an object, or a list field that is not a list | dropped / emptied |
| every sentence of `source` appears in the reviewer (whitespace, case and Unicode forms such as math letters ignored; a quiz item's source may join its question to its answer line, and parts joined with "…" are checked one by one); skipped for a photo or scan | dropped |
| a duplicate question text, or (between parts of a long reviewer) one 85 % alike with the same answer | dropped |
| `difficulty` not `easy`, `medium` or `hard` | set to `medium` |
| Identification: its answer is not inside its question; `accepted` starts with `answer`, deduplicated | dropped / repaired |
| Multiple Choice: a leading option letter (`C. `) is stripped from the answer and the wrong options; at least 3 distinct wrong options, none equal to the answer or an accepted alias, none that contains the answer or sits inside it as whole words ("Ezekiel Bustamante Jr."; numbers are exempt, so "1" stays beside "−1"); extras trimmed. Options that mix numbers and words lose 0.3 confidence; otherwise an answer under half the shortest or over twice the longest wrong option (when any is 15+ chars) loses 0.15 | dropped / repaired / flagged |
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
Cloudflare server error (5xx) or lost connection up to 3 times (`MAX_RETRIES`, 2, 4 and 6 s apart),
never past the request's deadline: a grade stops after `GRADE_SECONDS` (60), under the game's 75 s wait. Measured 2026-11-09 on Google: the 15 graded answers in
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

**Gemini on Cloud Run.** The deployed server can call Gemini with either kind of Google key, set by
the same variables, and `NEURONS_PER_M_IN` and `_OUT` = `0` turn the neuron meter off (nothing is
counted, so `budget_fits` always passes; Google's own quota answers 429 instead):

| Key | `AI_BASE_URL` | Model (cheap example) | How it is called |
|---|---|---|---|
| Google AI Studio (`AIza…`) | `https://generativelanguage.googleapis.com/v1beta/openai/` | `gemini-3.1-flash-lite` | the OpenAI client, key as `Bearer` (config only) |
| Vertex AI express mode (`AQ.…`) | `https://aiplatform.googleapis.com/v1/publishers/google/models` | `gemini-2.5-flash-lite` | `ai._vertex_chat`: Gemini's own `:generateContent`, key in `x-goog-api-key` |

Vertex's OpenAI-compatible endpoint takes only OAuth tokens, not an express key, so an `AI_BASE_URL`
ending in `/publishers/google/models` sends each call through `_vertex_chat`. It turns the chat
messages into `contents` (images as `inlineData`), the schema into `responseJsonSchema`, and the
reply back into the chat shape (`MAX_TOKENS` → `length`, thought parts dropped). The openai client
still sends it, so errors and retries are unchanged; a 400 while the schema is on retries once
without it. Express mode serves only the models in its own list (the 2.5 Flash-Lite there is the
cheapest), at 10 requests a minute for 2.5 models: a 6-part extract can meet that, and `_chat`
then reports Google's 429. Neither path has been run against a real key yet.

**Google, for development.** The same Gemma 4 runs on Google's Gemini API through its
OpenAI-compatible endpoint. The local `backend/.env` can point there:
`AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/`, `AI_API_KEY` = a Google AI
Studio key, both models `gemma-4-26b-a4b-it`, `NEURONS_PER_M_IN` and `_OUT` = `0` (Google counts no
neurons; its own rate limits answer 429, and the game goes offline), and `AI_JSON_SCHEMA=0`. Measured
2026-11-09 on a quiz-style PDF: every quiz item kept with its answer-key answer. Google often answers
503 when busy (most calls failed for part of 2026-11-24) and 429 past its tokens-per-minute cap;
`_chat` asks again after a 503. Release stays on Cloudflare (see the terms note below).

**Cost: $0** on Cloudflare's Workers Free plan, which includes **10,000 neurons a day** (UTC) for the
whole account. The plan cannot bill past that: further calls fail, and the game falls back offline.

Measured 2026-11-24 by the eval run (§4) on Google's endpoint: the same model, so the same tokens,
priced here at Cloudflare's rates. Latency and JSON behaviour on Cloudflare are still to measure.

| Route | Tokens per call | Neurons per call | Seconds |
|---|---|---|---|
| `/v1/extract`, one part (9–17 questions) | ~2.0k in, ~1.6k out | ~63 (max 85) | 25–125 |
| `/v1/grade`, essay or Identification | ~0.4k in, ~0.07k out | ~5 | up to ~45 |

`LIKELY_NEURONS` (`main.py`) rounds these up: 100 per extract part, 10 per grade. So a day covers
roughly **90 short reviewers and 900 graded answers across all players**, fewer for long reviewers
(up to 6 parts each).

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
uv run --env-file .env --no-project --with-requirements requirements.txt python evals/run_evals.py --yes --pause 30
# the same, offline and free: score a saved run again after changing checks, labels or cases
uv run --no-project --with-requirements requirements.txt python evals/run_evals.py --rescore evals/runs/<run>
```

To use the server from the editor, set `Api.DEV_USES_SERVER = true` ([`skills.md`](skills.md) §*Use
the real study server*).

**Deploy on Cloud Run** (the mentor's setup; the key stays a Cloud Run secret and never reaches the
app). Run these in [Cloud Shell](https://shell.cloud.google.com), which has `gcloud` and `git`, from a
clone of the repo. `gcloud run deploy --source` builds `backend/Dockerfile` with Cloud Build;
`backend/.gcloudignore` keeps any `.env` out of the upload.

```bash
PROJECT=<project-id>; REGION=asia-southeast1; SERVICE=studymon-api
gcloud config set project $PROJECT
# 1. APIs (add aiplatform.googleapis.com for a Vertex express key)
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com   secretmanager.googleapis.com billingbudgets.googleapis.com
# 2. The key, as a secret. Make a NEW key first (see "Rotate" below); read -s keeps it out of history.
read -rs KEY && printf '%s' "$KEY" | gcloud secrets create gemini-api-key --data-file=- && unset KEY
NUM=$(gcloud projects describe $PROJECT --format='value(projectNumber)')
gcloud secrets add-iam-policy-binding gemini-api-key   --member=serviceAccount:$NUM-compute@developer.gserviceaccount.com --role=roles/secretmanager.secretAccessor
# 3. Deploy. One instance: the per-IP limits live in memory (§6). 600 s is above the game's 240 s wait.
gcloud run deploy $SERVICE --source backend --region $REGION --allow-unauthenticated   --timeout 600 --max-instances 1 --memory 1Gi   --set-secrets AI_API_KEY=gemini-api-key:latest   --set-env-vars AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/,EXTRACT_MODEL=gemini-3.1-flash-lite,GRADE_MODEL=gemini-3.1-flash-lite,NEURONS_PER_M_IN=0,NEURONS_PER_M_OUT=0
# for a Vertex express key instead: AI_BASE_URL=https://aiplatform.googleapis.com/v1/publishers/google/models
#   and both models gemini-2.5-flash-lite
URL=$(gcloud run services describe $SERVICE --region $REGION --format='value(status.url)')
curl $URL/health                       # -> {"ok": true}
# 4. Budget alert (it warns by email; it does not stop spending)
gcloud billing budgets create --billing-account=$(gcloud billing projects describe $PROJECT   --format='value(billingAccountName.basename())') --display-name="studymon" --budget-amount=10USD   --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
```

- **Rotate the key that was shared in chat.** Treat it as public: delete it where it was made (Google
  AI Studio → API keys, or the express-mode key page in the Cloud console), make a new one, and give
  only the new one to step 2. To rotate later: `read -rs KEY && printf '%s' "$KEY" | gcloud secrets
  versions add gemini-api-key --data-file=-`, then `gcloud run services update $SERVICE --region
  $REGION --update-labels rotated=$(date +%s)` so a new revision reads `latest`.
- **Then the game:** set `const RELEASE_URL := "<the $URL above>"` (`https://studymon-api-….run.app`)
  in `scripts/autoload/api.gd` and export again (§1). No server sleeps on Cloud Run, but a cold
  start still takes seconds; `Api.wake_server()` covers it.
- Run the `X-Forwarded-For` limit test from [`next-steps.md`](next-steps.md) §1.5 step 5 against
  `$URL`; `gcloud run services update $SERVICE --region $REGION --update-labels reset=$(date +%s)`
  restarts it to clear the counts afterwards.

**Deploy on Render** (the Cloudflare setup): `render.yaml` (repo root) is a Render Blueprint for a **free web service** built from
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

- **Graded answers:** 61 in `evals/grading_cases.json`, 29 essays and 32 Identification checks
  across the reviewers' subjects and Filipino. Each essay case lists the credit each rubric point
  should get (`"credits"`; `"none|partial"` allows either):
  - essays: full, partial, off-topic, filler, swapped or reversed facts, a keyword dump, an injected
    instruction, and one hidden in a partial answer (which must stay partial);
  - Identification: synonyms, abbreviations, reordered and longer forms (pass); a broader term, a
    sibling term (nucleus for nucleoid, price floor for price ceiling, arguments for parameters), a
    province for a town, and an injected instruction (fail).
- **Question labels:** `evals/question_labels.json`, keyed by question `id`: is the answer key
  correct, is the question ambiguous, are the options or the rubric fair (`null` for an
  Identification). A question is good when correct, unambiguous and not unfair. A new prompt writes
  new questions, so label the new ids from the run's `kept.json` before comparing.
- **Pass rules:**
  - A reviewer passes when ≥ 80 % of its generated questions survive the checks, every type has ≥ 3,
    and it got at least 60 % of the questions the prompt asks for (one per 100 words, 9 to 30).
  - A reviewer whose file name ends in `_fil` also needs ≥ 80 % of its questions to read as Filipino
    (common function words such as *ang*, *ng*, *mga*).
  - An answer passes when its score lands in its expected band.
- **Runs:** a live run saves every model reply under `evals/runs/<time>/` (`extract_<reviewer>.json`
  with the raw questions, tokens and seconds; `grading.json` with each reply; `kept.json`). `--rescore`
  replays a saved run with no model calls. `--into <run>` redoes only what failed in a run (Google's
  503s), `--pause` spaces calls under Google's per-minute cap, `--only` and `--no-grading` narrow it.
- **What it prints:** pass/fail per reviewer and case; the share of labelled questions that are good;
  grading cases in band and essay points whose credit agrees with the case; per half, model calls,
  cut-off answers, Cloudflare neurons, tokens per call and the slowest call.
- **When to run:** on every prompt or model change. A full run is about 1,100 neurons (11 extractions,
  61 grades), from the same daily allowance the game uses.
- **Status, 2026-11-24, on Google** (runs `20261124-002805` baseline; `tuned-2` with the examples, the
  per-type schema and the rubric rule):

  | | Baseline | Tuned |
  |---|---|---|
  | labelled questions good | 67 of 101 (66 %) | 101 of 114 (89 %) |
  | wrong answer keys / ambiguous / unfair options or rubric | 0 / 0 / 34 | 0 / 3 / 10 |
  | reviewers passing the structure rules | 6 of 11 | 6 of 11 |
  | extraction neurons, the 9 single-part reviewers | ~578 for 90 questions | ~554 for 103 |
  | replies that did not parse (asked again) | 0 | 2 |
  | grading cases in band (`tuned-1`: ID feedback in the question's language) | 55 of 61 | 56 of 61 |
  | essay points agreeing with the case | 101 of 101 | 98 of 98 |

  Still failing: a keyword dump with no explanation earns partial credit (0.40; the prompt counts
  naming a point as partial); "params" is refused as an abbreviation of "parameters"; a thin
  one-line ceiling answer scores 0.12 against an expected partial; Identification grades sometimes
  run past 2,000 tokens on Google and fail (8 of 66 calls at baseline, 1 tuned). Not yet run on
  Cloudflare.

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
- A route only starts when its likely cost still fits under `DAILY_NEURONS` (9,000, just under
  Cloudflare's 10,000): `LIKELY_NEURONS` per model call (extract 400 per part, grade 30) times the
  calls it makes. An extract makes one per part (`ai.text_chunks`, at most 6), a photo or scan one.
- After that, extraction answers `offline` and grading answers 429, and both fall back on the device.
- The count lives in memory, so a restart clears it (the free host restarts after sleeping). The
  Workers Free plan cannot bill past its allowance either way.

**Daily limits.** No accounts means anyone who finds the URL could spend the allowance.
- `main.py` counts calls per client IP per UTC day (`DAILY_LIMITS`: 5 extracts, 300 grades, 20
  reports) and for everyone together (`DAILY_TOTAL`, 20,000).
- Over a limit the reply is HTTP **429** with a `failed` envelope.
- An extract is counted only once its file is accepted: a file turned away (too big, unreadable, too
  little text) costs nothing of the day's 5.
- The IP is the last `X-Forwarded-For` entry (the one the host's proxy appends) or the socket
  address. Verify this on the host (§4).
- The counts live in memory, per instance: a second instance would double every limit. Deploy with
  one instance (`--max-instances 1` on Cloud Run, §4).

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
5. The deploy (Cloud Run, §4) and the `X-Forwarded-For` limit test (§6).
   On Gemini, `GameState.AI_CONSENT_TEXT` and `site/privacy.html` must stop naming Cloudflare, and
   the terms note in §3 needs a fresh check for the key type used.
6. `RELEASE_URL` in `api.gd`.
7. The policy pages, and their URLs in `settings.gd`.

**Planned (Phase 2): sessions.** `POST /v1/session` turns a Google Play Games server auth code into a
session token. The AI routes then require `Authorization: Bearer`, and limits count per player.
Not built; the design is in [`next-steps.md`](next-steps.md) Phase 2.

Later: Play Integrity, so only the real app can call the server.
