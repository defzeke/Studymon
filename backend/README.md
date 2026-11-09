# Studymon API

A thin, **stateless** gateway between the game and the AI model: it turns a reviewer into questions
with their answer keys, and grades typed answers. It holds the AI key (never put it in the Godot
client) and stores nothing; worlds and answer keys live in the player's save file.

The model is **Gemma 4 on Cloudflare Workers AI** by default, which is free up to 10,000 neurons a day.
Any OpenAI-compatible endpoint works: the provider is four environment variables. When the day's
allowance is spent, extraction answers `offline` (the game writes simpler questions on the device) and
grading answers 429 (the game grades on the device).

Contract, models, budget and the checks it runs: [`../docs/api-backend.md`](../docs/api-backend.md).

## Run
```
copy .env.example .env        # set AI_BASE_URL (your Cloudflare account id) and AI_API_KEY
uv run --no-project --with-requirements requirements.txt uvicorn main:app --port 8000 --env-file .env
curl 127.0.0.1:8000/health    # -> {"ok": true}
```
Then set `const DEV_USES_SERVER := true` in `scripts/autoload/api.gd` (release builds use
`RELEASE_URL` instead).

## Endpoints
| Method | Path | Body | Result |
|---|---|---|---|
| GET | `/health` | — | `{"ok": true}` |
| POST | `/v1/extract` | `{job_id, topic_name, text}` or `{job_id, topic_name, file_base64, file_type}` | `{topic_id, questions[], reviewer_text}`, or `{…, questions: [], offline: true, note}` |
| POST | `/v1/grade` | `{job_id, mode: "identification" \| "essay", question, answer, expected, accepted, rubric, model_answer, source}` | `{score, feedback, covered?}` |
| POST | `/v1/reports` | `{job_id, kind, text}` | `{ok: true}` |

Every response is the job envelope `{job_id, status: "completed" | "failed", progress, result}`.

## Test
```
uv run --no-project --with-requirements requirements.txt --with pytest --with httpx python -m pytest tests
uv run --env-file .env --no-project --with-requirements requirements.txt python evals/run_evals.py --yes   # real model: free, an estimated ~5,000 of the day's 10,000 neurons
```

## Deploy (free)
`render.yaml` at the repo root is a Render Blueprint for a free web service from this folder. Add
`AI_BASE_URL` and `AI_API_KEY` as secret environment variables in the Render dashboard, then set
`Api.RELEASE_URL` to the service's `https://…onrender.com` address. The free service sleeps after 15
idle minutes; the game wakes it with `GET /health` before it needs it.
