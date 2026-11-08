# Next steps: AI, Google sign-in, deploy

The hand-over for whoever takes over the backend, the AI and the release. Work through the three
phases in order:

1. **Integrate the AI into the game.** The server exists but has never met the real model.
2. **Google sign-in, required to play.** It goes through Google Play Games, and the server learns
   who each player is.
3. **Deploy the game** on Google Play (Android; iOS later).

**What exists today:**
- The study server is in `backend/`: [`api-backend.md`](api-backend.md).
- The client side is in `scripts/autoload/api.gd`: consent, offline fallbacks and the Report
  buttons.
- Google Play Games sign-in and cloud saves are in `scripts/autoload/cloud_save.gd`
  ([`data-model.md`](data-model.md) §8).
- How the game is put together: [`architecture.md`](architecture.md).

Status lives in [`tasks.md`](tasks.md); this page is the *how*. When a step is done, mark it in
`tasks.md`, and update the doc that owns what you changed ([`rules.md`](rules.md) §2).

**Ground rules:**
- **Secrets** live only in `backend/.env`, which git ignores, and in Render's settings. Never in a
  commit.
- Every change keeps **mock mode** and the **headless gates** working (`bash tests/gates.sh`,
  [`skills.md`](skills.md) §*Verify a change*). CI runs them on every push.
- **You commit your own work.** AI agents working in this repo never commit; they hand off a
  proposed commit message instead ([`rules.md`](rules.md) §1).
- Every step here uses free tools. The one cost is the Google Play registration ($25 once).

You will need [uv](https://docs.astral.sh/uv/), which installs Python for you, and Godot **4.7.2**.

---

## Phase 1 — Integrate the AI into the game

### 1.1 Cloudflare account and Workers AI token

1. Sign up at [dash.cloudflare.com](https://dash.cloudflare.com). The Workers **Free** plan is enough,
   and it needs no card.
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
   - If they do rule it out, stop and raise it. The fallbacks are in
     [`launch-plan.md`](launch-plan.md) §1.

**Done when** you have the Account ID, a token, and a written answer on the terms.

### 1.2 Run the server locally

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

### 1.3 Run the evals and tune the prompts

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
- In [`api-backend.md`](api-backend.md) §3, replace the estimated neurons per call with the measured
  ones.
- In `backend/main.py`, set `LIKELY_NEURONS` to the measured figures, rounded up. The server uses
  them to decide whether a call still fits in the day's budget.
- In [`api-backend.md`](api-backend.md) §4, change "Status: not yet run against Gemma" to the date
  and the result.

**Done when** every line passes, or the remaining failures are written down with a reason the team
agrees to.

### 1.4 Play the integration in the editor

The editor normally runs on the mock. To play against your local server:
1. Keep the server from 1.2 running.
2. Set `const DEV_USES_SERVER := true` in `scripts/autoload/api.gd`. The game then talks to
   `http://127.0.0.1:8000` ([`skills.md`](skills.md) §*Use the real study server*).
3. Run the game from the editor and check each item. Each one must behave as
   [`api-backend.md`](api-backend.md) describes:

| Check | Where | Expected |
|---|---|---|
| Consent | World Builder, first **Extract questions with AI** | The AI notice appears once. **Not now** sends nothing |
| Upload paths | World Builder | Pasted text, a PDF, a scanned PDF, a .docx, a .pptx and a photo each give questions |
| More questions | World Builder on a saved world | New questions that don't repeat the old ones |
| Report | **Report** on a question row | The server log shows `content report` |
| Essay grading | A battle with an essay question | A score and feedback from the server |
| Identification near-miss | Type a close but not exact answer | The server decides it, and feedback appears |
| Review answers | End of a run | **Report** on an answer works |
| Free allowance spent | Restart the server with `DAILY_NEURONS=0` | Extraction comes back `offline` with simpler questions written on the device. Essays say "Graded offline." A near-miss Identification answer counts as wrong |
| Server down | Stop the server | Extraction shows an error. After the timeout, grading behaves as in the row above |
| Consent withdrawn | Settings → untick *Let the AI read my reviewers and answers* | Nothing is sent; answers grade on the device |

Write any bug you find in [`known-issues.md`](known-issues.md), with the steps to reproduce it.
**Set `DEV_USES_SERVER` back to `false` before committing.**

**Done when** every row behaves as expected.

### 1.5 Deploy the server on Render

1. In the [Render dashboard](https://dashboard.render.com): **New → Blueprint**. Connect the GitHub
   repo and pick `render.yaml`, which holds every setting below. Blueprints redeploy on each push to
   the chosen branch.
2. To create it by hand instead: **New → Web Service** on the repo, with these settings:

   | Setting | Value |
   |---|---|
   | Branch | `world-assets` (`main` once merged) |
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
5. **Check the per-player limit.** The server counts calls per address and reads the last
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
     `backend/main.py` to use the entry Render adds.
   - Afterwards, **Manual Deploy → Restart service** clears the counts, which live only in memory.

**Done when** the service answers on its `https://` URL and call 6 gives `429`.

### 1.6 Point the game at the server

In `scripts/autoload/api.gd`, set:

```gdscript
const RELEASE_URL := "https://<name>.onrender.com"
```

Only release exports use it. The editor and debug builds stay on the mock.

### 1.7 Put the policy pages online

The privacy policy, terms and support pages are in `site/`. Both stores need them reachable.
`.github/workflows/pages.yml` publishes them to GitHub Pages.
1. GitHub → **Settings → Pages → Source: GitHub Actions**. This needs admin rights on the repo.
2. **Actions → Pages → Run workflow.** If the deploy from `world-assets` is refused, add that branch
   under Settings → Environments → `github-pages`.
3. Open `https://defzeke.github.io/Studymon/privacy.html` to check it.
4. In `scripts/ui/settings.gd`, set `PRIVACY_URL`, `TERMS_URL` and `SUPPORT_URL` to the three page
   URLs ([`store-listing.md`](store-listing.md) §1).

**Phase 1 is done when** 1.1–1.7 are done and `tasks.md` is updated.

---

## Phase 2 — Google sign-in (required)

**Goal:** every player signs in with **Google Play Games** before playing, and the study server
knows which player is calling.
- AI limits count **per player** instead of per network.
- Only signed-in players can use the server.
- Still no accounts or passwords of our own: Google holds the identity. Decided 2026-11-09.

**What exists:**
- `CloudSave` already signs in silently at boot (`_on_authenticated`). It has `sign_in()` for a
  button, `is_available()` (true only on Android with the plugin), and `signed_in`.
- The plugin can hand the game a one-time **server auth code**:
  `PlayGamesSignInClient.request_server_side_access(server_client_id, force_refresh_token)` emits
  `server_side_access_requested(code)` (`addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd`).
- The server redeems that code with Google to learn the player's Play Games ID. This is Google's
  documented server-side access flow for Play Games.

### 2.1 Console setup

1. The Play Console steps in [`skills.md`](skills.md) §*Export for Android with Play Games*:
   - App type: Game.
   - Play Games Services with **Saved Games** turned on.
   - An Android OAuth client per signing key.
2. In Play Games Services → **Configuration → Credentials**, add a **Game server** credential. It
   creates a **Web application OAuth client**.
   - Its **client ID** goes in the game (`SERVER_CLIENT_ID`) and on the server.
   - Its **client secret** goes only on the server.

### 2.2 Server: sessions

Build in `backend/main.py`, with tests in `backend/tests/`:

**`POST /v1/session`**, body `{"job_id", "code"}`:
1. Redeem `code` at `https://oauth2.googleapis.com/token` with `GOOGLE_CLIENT_ID`,
   `GOOGLE_CLIENT_SECRET` and `grant_type=authorization_code`.
2. With the access token, call `https://games.googleapis.com/games/v1/players/me` to get
   `playerId`.
3. Return the job envelope with `{"token": <session token>, "expires_in": <seconds>}`.
   - The token is `playerId` plus an expiry, signed with `SESSION_SECRET` using the standard
     library's `hmac` and `hashlib`. No new dependency.
   - Use about 7 days. Store nothing.

**Protect the AI routes:**
- `/v1/extract`, `/v1/grade` and `/v1/reports` read `Authorization: Bearer <token>`.
- A missing, bad or expired token gives HTTP **401** with a `failed` envelope.
- `over_limit()` counts per `playerId`. Keep the per-IP count as a looser backstop.

**Settings:**
- New env vars: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (secret), `SESSION_SECRET` (secret, a long
  random string) and `AUTH_REQUIRED`.
- `AUTH_REQUIRED=false` is the default in `.env.example`, so local development and the editor work
  without Play Games. Set `true` on Render.
- Add all four to `render.yaml`, with `sync: false` for the secrets.

**Tests:** stub Google's two HTTP calls, then cover:
- a good code;
- a code Google rejects;
- an expired or tampered token;
- a missing header when `AUTH_REQUIRED=true`;
- the per-player limit.

### 2.3 Game: the session and the sign-in gate

**The session** (`cloud_save.gd`, `api.gd`):
- When `CloudSave._on_authenticated(true)` runs, call
  `_sign_in.request_server_side_access(SERVER_CLIENT_ID, false)`.
- On `server_side_access_requested(code)`, call a new `Api.start_session(code)`. It posts to
  `/v1/session` with a unique `job_id`, the same as every other request (rules §5).
- Keep the token **in memory only**: never in the save. Each launch gets a fresh code.
- `Api._request()` adds `Authorization: Bearer <token>` when a token is held.
- On a 401, ask `CloudSave` for one new code and retry once. If that fails too, use the offline
  fallbacks that already exist.

**The gate:**
- Before the first-run intro starts (`scripts/ui/boot/tutorial.gd`, launched from `peek.tscn`), show
  a sign-in screen: "Sign in with Google Play Games" (`CloudSave.sign_in()`), and "Connect to the
  internet to sign in" when it fails offline.
- The intro starts once `CloudSave.signed_in` is true.
- The gate runs **only when `CloudSave.is_available()`**. The editor, desktop, the headless gates
  and `Api.MOCK` skip it, so the gates and mock mode keep working.
- **Confirm while building:** a returning player (tutorial done) whose silent sign-in fails because
  they are offline. The recommended default is to let them play their saved game, and AI calls wait
  until a session exists. Raise it if you choose otherwise.
- Settings already shows the signed-in account. Play Games v2 has no sign-out: players manage that
  in the Play Games app.

### 2.4 Docs and store answers that ship with Phase 2

| Doc | Change |
|---|---|
| [`api-backend.md`](api-backend.md) | `/v1/session`, the `Authorization` header, the 401, per-player limits, the new env vars |
| [`architecture.md`](architecture.md) | the boot order: sign-in → session → intro |
| [`data-model.md`](data-model.md) §8 | the session token is never saved |
| [`rules.md`](rules.md) | open question 2 (*Auth*) |
| [`launch-plan.md`](launch-plan.md) §1 | the Login row: built |
| [`known-issues.md`](known-issues.md) | #2: the auth header is back, as `Bearer` |
| [`glossary.md`](glossary.md) | *session token* |
| `site/privacy.html`, `GameState.AI_CONSENT_TEXT` | sign-in is required; the server receives the Play Games player ID to apply limits, and does not store it |
| [`store-listing.md`](store-listing.md) | Data safety: **User IDs** are collected, for app functionality, and not shared. App access: "Sign in with any Google account through Google Play Games" |

**Phase 2 is done when** a phone build signs in, gets a session, and the AI calls are counted per
player on Render.

---

## Phase 3 — Deploy the game (Android)

1. **The Android export.** Follow [`skills.md`](skills.md) §*Export for Android with Play Games*:
   - Install the Android build template.
   - Use Gradle build and `.aab`.
   - Set `godot_play_game_services/game_id`.
   - Turn **user-data backup** on.
   - Use a release keystore kept out of git.

   Check that `export_presets.cfg` holds no passwords before committing it. Godot keeps those in
   `.godot/export_credentials.cfg`, which is ignored.
2. **The app icon.** A 512 × 512 icon and the adaptive icon. The game still has Godot's default
   `icon.svg`, so this needs art ([`store-listing.md`](store-listing.md) §6).
3. **Internal testing on a phone.** Upload to the internal track and check:
   - the cloud-save checklist in [`skills.md`](skills.md);
   - the sign-in gate on a fresh install;
   - the file picker with a PDF, a photo and a .docx, plus Export and Import (issue #23 in
     [`known-issues.md`](known-issues.md));
   - the whole AI loop against Render;
   - the offline fallbacks.

   Fix what breaks, and record it in `known-issues.md`.
4. **The closed test.** At least 12 testers stay opted in for 14 days; Google requires this for new
   personal developer accounts. **Start recruiting during Phase 1.** It is the longest wait.
5. **The store listing.** Use [`store-listing.md`](store-listing.md): the Data safety and content
   rating answers, the text, the review notes, the graphics and the screenshots.
6. **Production** with a staged rollout. Then update [`tasks.md`](tasks.md) and
   [`launch-plan.md`](launch-plan.md).

iOS comes later. It needs macOS for the export and an Apple Developer account at $99 a year
([`launch-plan.md`](launch-plan.md) §5).
