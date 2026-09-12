# Studymon API (FastAPI thin proxy — Godot never calls the LLM directly)

## Run (Phase 0: health check only)
```
cd backend
uv venv && uv pip install -r requirements.txt   # or: pip install -r requirements.txt
uvicorn main:app --reload --port 8000
curl localhost:8000/health   # -> {"ok": true}
```

## Endpoints
| Method | Path | Phase | Notes |
|---|---|---|---|
| GET | `/health` | 0 | Liveness |
| POST | `/extract` | 5 | PDF → Claude document input → structured concepts/questions JSON |
| POST | `/grade` | 7 | `{type, question, answer, source_context}` → `{score_0_1, feedback}`; hybrid rubric (50% keyword coverage + 50% holistic) |

## Supabase checklist (Phase 1)
1. Create project at supabase.com; enable Email + social providers (Auth).
2. Tables: `profiles` (companion state), `topics` (regions), `questions` (+ mastery), `extractions` (raw vs edited).
3. Buckets: `pdfs` (short-lived uploads for processing).
4. Copy anon key + URL into backend `.env` (see `.env.example`, Phase 1) — never into the Godot client.
