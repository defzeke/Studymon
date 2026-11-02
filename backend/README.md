# Studymon API

A thin, **stateless** gateway between the game and Claude: it turns a reviewer into questions with
their answer keys, and grades essays. It holds the Claude API key (never put it in the Godot client)
and stores nothing; worlds and answer keys live in the player's save file.

Contract, models, cost and the checks it runs: [`../docs/api-backend.md`](../docs/api-backend.md).

## Run
```
copy .env.example .env        # set ANTHROPIC_API_KEY (or use `ant auth login`)
uv run --no-project --with-requirements requirements.txt uvicorn main:app --port 8000
curl 127.0.0.1:8000/health    # -> {"ok": true}
```
Then set `const DEV_USES_SERVER := true` in `scripts/autoload/api.gd` (release builds use
`RELEASE_URL` instead).

## Endpoints
| Method | Path | Body | Result |
|---|---|---|---|
| GET | `/health` | — | `{"ok": true}` |
| POST | `/v1/extract` | `{job_id, topic_name, text}` or `{job_id, topic_name, pdf_base64}` | `{topic_id, questions[]}` with answer keys |
| POST | `/v1/grade` | `{job_id, mode: "identification" \| "essay", question, answer, expected, accepted, rubric, model_answer, source}` | `{score, feedback, covered?}` |

Every response is the job envelope `{job_id, status: "completed" | "failed", progress, result}`.

## Test
```
uv run --no-project --with-requirements requirements.txt --with pytest --with httpx python -m pytest tests
uv run --no-project --with-requirements requirements.txt python evals/run_evals.py --yes   # calls Claude: costs money
```

## Before a public release
No accounts means the endpoint is open: add a per-IP rate limit and set a monthly spend limit on the
Anthropic workspace first (`../docs/launch-plan.md` §5.3).
