# API and backend

The rule the whole project is built around: **the Godot client never talks to an LLM provider.**
It talks only to our own API, which holds the keys. Today the client doesn't talk to anything at
all — every call is mocked.

- **Client wrapper:** `scripts/autoload/api.gd` (autoload `Api`)
- **Backend skeleton:** `backend/main.py`, `backend/requirements.txt`, `backend/README.md`
- **Consumers:** `SessionManager` (extraction), `battle.gd` (grading), `companion` (starter data)

Status: **Client = 100 % mock. Backend = health check only.**

---

## 1. Client surface

```gdscript
const MOCK := true
const BASE_URL := "http://localhost:8000"

signal job_status(job_id: String, status: String, progress: float, result: Variant)
signal quota_exceeded(type: String)
```

| Method | MOCK behaviour | Real behaviour |
|---|---|---|
| `mock_upload_pdf(topic, source_text)` | quota gate → 0.8 s timer → `job_status("job_001", "completed", …)` | **no HTTP call is made even when `MOCK = false`** |
| `mock_get_topics()` | `job_status("topics", "completed", …, {topics: [...]})` with one fake "Biology 101" | — |
| `grade_battle_question(q, answer)` | quota gate (essays only) → local rubric, which reads `q.difficulty` for the Hard Identification rule → `job_status("grade", "completed", …, {score, feedback, damage, type})`. Multiple Choice is graded in `battle.gd` and never calls this | `POST /battle/grade` |
| `save_topic(topic_id, questions)` | fires HTTP anyway (fails silently against localhost) | `PUT /topics/{id}` |
| `update_mastery(topic, qid, state)` | not called (guarded by `if not Api.MOCK`) | `PUT /mastery/{topic}/{qid}` |

Internal helpers use `_post` / `_put` / `_http_get` prefixes on purpose — plain `_get` would collide
with `Object._get(StringName)` (noted in the file header).

### HTTP plumbing

One `HTTPRequest` child is created in `_ready()`. Every call reuses it, so **requests are serialised
implicitly** — a second call while one is in flight will error out. There is no queue, timeout,
retry or cancellation.

```gdscript
func _on_request_completed(result, _response_code, _headers, body) -> void:
    if result != HTTPRequest.RESULT_SUCCESS: return          # silent
    var parsed = JSON.parse_string(body.get_string_from_utf8())
    if typeof(parsed) != TYPE_DICTIONARY: return             # silent
    if data.has("job_id"):                                   # <-- only dicts with job_id are surfaced
        job_status.emit(jid, status, progress, data.get("result", null))
```

Two consequences for anyone wiring the backend:

1. **A plain `{score, feedback, damage}` response is dropped** — `_on_request_completed` only emits
   when the payload contains a `job_id`, and `battle.gd` only listens for `job_id == "grade"`.
   Either wrap the response as `{"job_id": "grade", "status": "completed", "result": {...}}` or
   change the parser.
2. HTTP status codes are ignored (`_response_code` is unused), so a 401/500 looks identical to a
   network failure: nothing happens.

### Auth

```gdscript
func _auth_headers() -> Array:
    var headers: Array = []
    if GameState.auth_token != "":
        headers.append("Authorization: *** " + GameState.auth_token)
    return headers
```

The scheme is literally `*** `, not `Bearer `. This is almost certainly a redaction that was
committed into the source. `GameState.auth_token` is never set anyway (no login flow), so the header
never ships. See `known-issues.md` #2.

---

## 2. Endpoints the client expects

| Call site | Method + path | Body | Expected response |
|---|---|---|---|
| `save_topic()` | `PUT /topics/{topic_id}` | `{"questions": [question…]}` | ignored |
| `grade_battle_question()` | `POST /battle/grade` | see below | `{"job_id": "grade", "status": "completed", "result": {"score": 0…1, "feedback": str, "damage": int}}` |
| `update_mastery()` | `PUT /mastery/{topic_id}/{question_id}` | `{"state": "new"\|"learning"\|"remaster"\|"mastered"}` | ignored |
| *(not implemented)* | `POST /extract` | PDF / text | `{"job_id", "status", "progress", "result": {"topic_id", "questions": […]}}` |

Grade request payload (`api.gd:49-56`):

```jsonc
{
  "type": "essay",                 // or "identification"; Multiple Choice never reaches the API
  "question": "Explain how …",
  "answer": "The player's text",
  "source": "original excerpt",
  "expected": "model answer / key term",
  "key_concepts": ["feedback", "reward"]
}
```

Mastery names are lowercased strings from `SessionManager.MASTERY_NAMES`; question ids come from the
question dict (`q1`, `q_3_4821`, …) and fall back to `"q_<index>"` when missing.

---

## 3. Drift from the documented backend

`backend/README.md` describes a **different** contract than the client implements:

| Concern | Backend README | Client actually does |
|---|---|---|
| Grading path | `POST /grade` | `POST /battle/grade` |
| Extraction path | `POST /extract` | never called — `mock_upload_pdf()` has no real branch |
| Grade response | `{score_0_1, feedback}` | `{job_id, status, result: {score, feedback, damage}}` |
| PDF upload | `{pdf}` | no request at all |
| Auth | Supabase anon key server-side | header never sent |

Treat `backend/README.md` as intent, not as a spec. Whichever side you keep, one of them must change.

---

## 4. Backend state

```python
# backend/main.py — 13 lines
app = FastAPI(title="Studymon API")

@app.get("/health")
def health() -> dict:
    return {"ok": True}
```

- `requirements.txt`: `fastapi>=0.115`, `uvicorn[standard]>=0.30`. No Anthropic SDK, no Supabase
  client, no PDF library, no `.env` handling.
- No auth, no database, no object storage, no rate limiting, no CORS setup (relevant if you ever run
  the client in a browser export).
- Run: `uvicorn main:app --reload --port 8000` from `backend/`, then `curl localhost:8000/health`.

---

## 5. Contract for the mock extractor

If you replace `mock_upload_pdf()` with a real call, the response must preserve this shape because
`SessionManager._on_job_status` depends on it:

```jsonc
{
  "job_id": "job_001",
  "status": "processing"            // or "completed" / "failed"
  "progress": 0.0,
  "result": null
}
```

and on completion:

```jsonc
{
  "job_id": "job_001",
  "status": "completed",
  "progress": 1.0,
  "result": {
    "topic_id": "topic_biology_101",
    "questions": [
      {
        "id": "q1",
        "text": "What key term is described here? \"…\"",
        "type": "identification",          // or "essay"
        "answer": "photosynthesis",
        "key_concepts": ["chlorophyll", "light"],
        "confidence": 0.85,
        "source": "…excerpt…"
      }
    ]
  }
}
```

Missing `confidence` defaults to 0.7; `type` is lowercased; missing `questions` becomes
`extraction_failed`. Any `job_id` other than `"grade"` / `"topics"` is treated as an extraction job,
so keep `"job_001"` or generate ids that cannot collide with those two.

---

## 6. Suggested minimum to go live

> The fuller, store-aware plan (accounts, quotas, evals, release pipeline) is in
> [`launch-plan.md`](launch-plan.md). It is future work; the game stays on mocks for now.

1. Decide the real paths (`/grade` vs `/battle/grade`) and fix the client **and** `backend/README.md`.
2. Teach `_on_request_completed` to surface non-`job_id` payloads (or standardise every response on
   the job envelope) and to report non-2xx codes through a signal.
3. Fix the `Authorization` scheme to `Bearer ` and add a real token source (Supabase or your own).
4. Implement `POST /extract` server-side: PDF → Claude document input → structured JSON, matching
   §5. Keep raw extraction separate from player edits (the plan's requirement).
5. Implement grading server-side with the hybrid rubric (50 % key-concept coverage, 50 % holistic)
   and return `damage` so scoring is tunable without a client update.
6. Move `MonetizationState` counters behind the API — a client-side `is_premium` bool is not a paywall.
7. Add timeouts/retries and a request queue before shipping; the single shared `HTTPRequest` will
   drop concurrent calls.
