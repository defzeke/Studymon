# Backend: next steps

The study server (`backend/`) is built and tested against a stubbed model, but it has never met the
real AI and is not online yet. This page is the hand-over: the remaining backend steps, in order,
written so someone new to the project can do them alone. Status lives in [`tasks.md`](tasks.md) (rows
D3, D4, E1–E3); how the server works is in [`api-backend.md`](api-backend.md).

**What you need:** a free Cloudflare account, a free Render account, and
[uv](https://docs.astral.sh/uv/) (it installs Python for you). Every step is free.

**What you don't need:** admin rights on the GitHub repository.
- The repo is public, so Render can deploy it straight from its URL.
- The policy pages are uploaded to Cloudflare by hand.
- Code changes (step 5) go to the maintainer as a file diff or a pull request. Only the maintainer
  commits ([`rules.md`](rules.md) §1).

**Never commit secrets.** The token lives only in `backend/.env`, which git ignores, and in Render's
environment settings.

---

## Step 1 — Cloudflare account and Workers AI token

1. Sign up at [dash.cloudflare.com](https://dash.cloudflare.com). The Workers **Free** plan is
   enough, and it needs no card.
2. Copy the **Account ID**. It is in the dashboard's account home, and in the URL after
   `dash.cloudflare.com/`.
3. Create an API token. Go to **AI → Workers AI → Use REST API → Create a Workers AI API Token**, or
   go to *My Profile → API Tokens → Create Token* and give it the **Workers AI** permission (Read and
   Edit). Copy it now: Cloudflare shows it only once.
4. **Read the terms before the store launch.** This is open decision 2 in [`tasks.md`](tasks.md).
   - Cloudflare's privacy policy says its services are "not intended for … individuals under the age
     of eighteen". Studymon is a 13+ app.
   - Read the *Self-Serve Subscription Agreement* and the *Workers AI* terms. Write down whether
     anything rules out a teen audience.
   - If they do rule it out, stop and tell the maintainer. The fallbacks are in
     [`launch-plan.md`](launch-plan.md) §1.

**Done when** you have the Account ID, a token, and a written answer on the terms.

## Step 2 — Run the server locally

From the repository root:

```bash
cd backend
cp .env.example .env    # Windows PowerShell: copy .env.example .env
```

Edit `backend/.env`:
- `AI_BASE_URL`: put your Account ID in place of `YOUR_ACCOUNT_ID`.
- `AI_API_KEY`: the token.
- Leave the rest as it is.

Then:

```bash
# the tests use no model and spend nothing; all must pass
uv run --no-project --with-requirements requirements.txt --with pytest --with httpx python -m pytest tests

# start the server
uv run --no-project --with-requirements requirements.txt uvicorn main:app --port 8000 --env-file .env
```

In a second terminal, run the two calls below. On Windows, use Git Bash or `curl.exe`.

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/v1/extract -H "Content-Type: application/json" \
  -d '{"job_id":"t1","topic_name":"Cells","text":"The mitochondria produce ATP through cellular respiration. The nucleus holds the DNA of eukaryotic cells. Ribosomes build proteins from amino acids."}'
```

- `/health` must answer `{"ok":true}`.
- The extract call takes up to a minute. It should answer `"status":"completed"` with a list of
  `questions`.
- An answer with `"offline": true` and a `note` means the model call failed: read the note.
  - A 401 or 403 means the token or the Account ID is wrong.
  - A 404 means the model name is wrong.

**Done when** both calls work against the real model.

## Step 3 — Run the evals and tune the prompts

The evals are the quality gate: nine reviewers and fifteen graded answers
([`api-backend.md`](api-backend.md) §4). One run is estimated at about **5,000 of the day's 10,000
free neurons**, so run it at most once a day. Don't run it on a day when testers are playing; they
share the same allowance.

```bash
cd backend
uv run --env-file .env --no-project --with-requirements requirements.txt python evals/run_evals.py --yes
```

**Reading the output:**
- Each reviewer line says PASS or FAIL. A reviewer passes when:
  - ≥ 80 % of its questions survive the server's checks;
  - every type (identification, essay, multiple_choice) has ≥ 3;
  - it got enough questions for its length;
  - for the `_fil` reviewer, the questions are in Filipino.
- Each grading line says PASS when the score lands in the expected band.
- The last lines give the neurons **per model call** for extraction and for grading.

**When something fails:**
- The prompts are the constants at the top of `backend/ai.py`: `EXTRACT_SYSTEM`, `GRADE_ID_SYSTEM`
  and `GRADE_ESSAY_SYSTEM`. Change one rule at a time and re-run the next day.
- Don't loosen the checks in `check_questions()` to make a run pass. They protect players from
  questions their reviewer doesn't support.
- Keep `MAX_QUESTIONS = 30` in `ai.py` unless the long reviewer (`earth_science_long`) shows that
  questions get worse near the cap.

**Record the results:**
- In [`api-backend.md`](api-backend.md) §3, replace the estimated neurons per call in the table with
  the measured ones.
- In `backend/main.py`, set `LIKELY_NEURONS` to the measured figures, rounded up. The server uses
  them to decide whether a call still fits in the day's budget.
- In [`api-backend.md`](api-backend.md) §4, change "Status: not yet run against Gemma" to the date
  and the result.

**Done when** every line passes, or the remaining failures are written down with a reason the
maintainer agrees to.

## Step 4 — Deploy on Render

1. In the [Render dashboard](https://dashboard.render.com): **New → Web Service → Public Git
   Repository**, and paste `https://github.com/defzeke/Studymon`. If Render offers to use the
   repo's `render.yaml` (a Blueprint), accept: it holds everything below.
2. Settings, all from `render.yaml`:

   | Setting | Value |
   |---|---|
   | Branch | `world-assets` (`main` once the maintainer merges) |
   | Root directory | `backend` |
   | Runtime | Python 3 |
   | Build command | `pip install -r requirements.txt` |
   | Start command | `uvicorn main:app --host 0.0.0.0 --port $PORT` |
   | Instance type | **Free** |
   | Health check path | `/health` |

3. Environment variables:
   - Set as **secrets**: `AI_BASE_URL` and `AI_API_KEY`, the same values as your `.env`.
   - Plain values: `PYTHON_VERSION=3.12.7`, `EXTRACT_MODEL=@cf/google/gemma-4-26b-a4b-it`,
     `GRADE_MODEL=@cf/google/gemma-4-26b-a4b-it` and `DAILY_NEURONS=9000`.
4. Deploy. Copy the service URL (`https://<name>.onrender.com`) and check that `/health` answers.
   The free service sleeps after 15 idle minutes, and the first call after that takes about a
   minute; the game allows for this.
5. **Redeploys:** a service made from a public repo URL may not deploy each new commit by itself.
   After a backend change is merged, use **Manual Deploy → Deploy latest commit**.
6. **Check the per-player limit.** The server counts calls per address and reads the last
   `X-Forwarded-For` entry, which should be the one Render adds. Without this, a player could fake
   the header and use up everyone's allowance. This test spends no neurons: text that is too short
   is refused before the model is called, but it still counts toward the limit.

   ```bash
   URL=https://<name>.onrender.com
   for i in 1 2 3 4 5 6; do
     curl -s -o /dev/null -w "%{http_code}\n" -X POST "$URL/v1/extract" -H "Content-Type: application/json" \
       -H "X-Forwarded-For: 10.0.0.$i" -d '{"job_id":"t'$i'","topic_name":"x","text":"x"}'
   done
   ```

   - Calls 1–5 should give `200` (a "Too short" failure) and call **6 must give `429`**. That means
     the faked header was ignored, which is correct.
   - If call 6 gives `200`, the server is trusting the faked header. Change `client_ip()` in
     `backend/main.py` to use the entry Render adds, and tell the maintainer.
   - Afterwards, **Manual Deploy → Restart service** clears the counts, which live only in memory.

**Done when** the service answers on its `https://` URL and the limit test gives `429` on call 6.

## Step 5 — Point the game at the server (a one-line code change)

In `scripts/autoload/api.gd`, set:

```gdscript
const RELEASE_URL := "https://<name>.onrender.com"
```

Only release exports use it. The editor and debug builds stay on the mock, so the gates and the
editor are unaffected. Send the change to the maintainer to commit.

## Step 6 — Put the policy pages online

The privacy policy, terms and support pages are in `site/`. Both stores need them reachable.
1. Cloudflare dashboard → **Workers & Pages → Create application → Pages → Upload assets**. Name the
   project (for example `studymon`) and drop the `site/` folder in.
2. Open `https://<project>.pages.dev/privacy.html` to check it.
3. In `scripts/ui/settings.gd`, set `PRIVACY_URL`, `TERMS_URL` and `SUPPORT_URL` to the three page
   URLs.
4. In [`store-listing.md`](store-listing.md) §1, replace `<project>` with the real name.
5. Send both changes to the maintainer.

Whenever `site/` changes, upload the folder again (open the project, then Create deployment).

## When everything is done

Tell the maintainer what you found, so [`tasks.md`](tasks.md) can be updated:
- the terms answer (step 1);
- the eval results and the measured neurons (step 3);
- the Render URL and the limit-test result (step 4);
- the Pages URL (step 6).

The maintainer marks D3, D4 and E1–E3 done. After that, the server waits for the Android build and
phone testing (phase F in [`tasks.md`](tasks.md)).

**Later, not needed for the first release:** Play Integrity checks, so that only the real app can
call the server ([`api-backend.md`](api-backend.md) §6).
