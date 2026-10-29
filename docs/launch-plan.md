# Launch plan: the real backend and the App Store / Google Play release

Status: **Future; 5.3 partly built.** The AI gateway's two routes exist (`/v1/extract`, `/v1/grade`,
see [`api-backend.md`](api-backend.md)) as a stateless server with no accounts, quotas, consent screen
or reports; release builds call it once `Api.RELEASE_URL` is set. This page is the researched plan for **Phase 5** of
[`systems/gameplay-structure.md`](systems/gameplay-structure.md), written down so it is not lost.
Where it disagrees with the code, the code describes today; this page describes the target.

- **Today's API state:** [`api-backend.md`](api-backend.md)
- **Usage limits today:** none (the client-side quota was removed), see [`systems/monetization.md`](systems/monetization.md)
- **Related known issues:** [`known-issues.md`](known-issues.md) #2, #7, #9

---

## 1. Decisions

Made by the maintainer:

| Decision | Choice |
|---|---|
| Audience | **13+** (students, teens, adults). Children under 13 would add COPPA, Apple Kids Category and Google Families work and roughly double the compliance scope |
| Login | **v1: no accounts** (decided 2026-10-29): saves stay on the device, so Sign in with Apple, in-app account deletion and Supabase are not needed for the first release; Settings offers "Delete my data" instead. Later: Google + Apple (iOS only) + Register with email at the tutorial's profile step |
| Purchases | **v1: free launch** (decided 2026-10-29): the placeholder Crystal Shop was removed; in-app purchases come in a later update |
| Backend | **None yet; mock first.** This whole page is future work |

Open until Phase 5 starts (recommendations recorded, not decided):

| Decision | Recommendation | Alternatives |
|---|---|---|
| Hosting | FastAPI (the existing stub) on Google Cloud Run or Fly.io, with Supabase for auth, database and PDF storage | Supabase Edge Functions only (short time limits for PDF jobs); Vercel (fine for the policy web pages, poor for big PDF jobs) |

## 2. What is most useful

Ranked by leverage for a store launch:

1. **A thin server-side AI gateway** with structured outputs and server-enforced quotas. The API
   key never reaches the phone, cost is capped per user, and models can change without an app update.
2. **An eval harness (a golden set)** for extraction and grading. The product *is* generated
   questions and grades; without measured quality a prompt or model change is a guess.
3. **A repeatable release pipeline** (CI → signed builds → TestFlight / Play internal testing).
   iOS needs macOS, so a macOS CI runner is the key enabler on a Windows team.
4. **Store compliance built into the app**, not bolted on: an AI-data consent screen, in-app account
   deletion, a Report button on AI content, a privacy policy, Sign in with Apple.
5. **Start Google's closed-testing clock early** (see §3); it is the longest wait on the schedule.

## 3. Store requirements and what they mean for the design

| Store | Requirement | Design consequence |
|---|---|---|
| Apple | Guideline 5.1.2(i) (Nov 2025): disclose **what** personal data goes to third-party AI, **to whom**, and get permission first | A consent screen before the first AI call that names the AI provider and what is sent (reviewer text or PDF, essay answers). Store consent per profile, show it again from Settings, and make sure App Review can see it |
| Apple | Account deletion must be possible in the app (5.1.1(v)) | `DELETE /me` plus a Settings button; cascade-delete database rows and stored PDFs |
| Apple | Sign in with Apple is expected when other social logins are offered (4.8) | The profile step offers Google, Apple (iOS) and Register |
| Apple | Digital goods use In-App Purchase (3.1.1); App Review needs a way in | Purchases are deferred; provide a reviewer **demo account** and a working Register path (a reviewer cannot use a personal Google account) |
| Google | Generative-AI policy: an in-app way to report or flag offensive AI content without leaving the app | A Report button on generated questions and on essay feedback, sent to `POST /reports` |
| Google | Data safety form; account-deletion URL plus in-app deletion | A hosted deletion-request page plus the same `DELETE /me` |
| Google | New personal developer accounts: a closed test with at least 12 testers opted in for 14 days before production (organisation accounts are reportedly exempt) | Put a minimal build into closed testing early; recruit 15–20 testers to absorb dropouts |
| Both | Privacy policy, terms and a support URL; Apple privacy labels, Google Data safety answers | Static pages (Vercel static hosting is a good fit); answers must match what the backend really collects |
| Apple | iOS export needs macOS with Xcode (Godot docs) | A macOS CI runner (GitHub Actions or Codemagic) builds, signs and uploads to TestFlight |

Sources (checked while planning; re-check the exact wording when the work starts):
[Apple: guideline update on third-party AI](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai),
[Google Play AI-generated content policy](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en),
[Google Play closed-testing requirement](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB),
[Godot: exporting for iOS](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html),
[Godot: Android in-app purchases](https://docs.godotengine.org/en/stable/tutorials/platform/android_in_app_purchases.html).

## 4. Target architecture

```text
Godot app ──HTTPS + Bearer token──► FastAPI gateway ──► Claude API
   │  login (Google / Apple / email)        │
   └──► Supabase Auth ◄─────────────────────┤  Supabase Postgres: profiles, topics, questions,
                                             │  mastery, usage ledger, entitlements, reports
                                             └► Supabase Storage: PDFs, deleted after extraction
```

The client never calls an LLM provider ([`api-backend.md`](api-backend.md)); secrets live only on
the server.

## 5. Sub-phases

Each is shippable and verified on its own.

| Step | Scope | Main files |
|---|---|---|
| **5.0 Accounts and decisions** | Apple Developer ($99/yr), Google Play Console ($25), Supabase project, an Anthropic workspace with a **monthly spend limit**, a domain for the policy pages; settle the open decisions in §1 | none |
| **5.1 Network layer and CI** | Replace the single shared `HTTPRequest` with a request queue; timeouts, retry with backoff for 408/429/5xx, non-2xx reported through a signal (#9), `Authorization: Bearer` (#2), unique `job_id`s, a job-polling helper; `MOCK` becomes a flag so dev builds stay on mocks; `BASE_URL` per environment through export feature tags; backend skeleton with `/health` and `/v1/config` (minimum client version, feature flags, quota limits); GitHub Actions running the `docs/rules.md` §6 gates, a committed `tests/` folder and backend tests; export presets without secrets. A minimal Android build goes to **Play closed testing** here to start the 14-day clock | `scripts/autoload/api.gd`, `project.godot`, `export_presets.cfg`, `backend/`, `.github/workflows/`, `tests/` |
| **5.2 Accounts and profile sync** | The tutorial's Continue stand-in becomes *Continue with Google*, *Continue with Apple* (iOS) and *Register a new profile* (Supabase email). Google and Apple sign-in through Supabase OAuth in the system browser with a deep-link return, so no heavy native SDK; check the plugin situation first (Godot has no first-party sign-in plugin). `GameState.set_user()` gets a caller; tokens go in the best available secure store (documented limit if only an encrypted file). Save `"v": 8` gains an `account` block (user id, signed-in flag; never raw tokens), and `player_name` and `tutorial_done` move into the profile so the tutorial stops replaying. Endpoints `GET /v1/me`, `PUT /v1/profile`, `DELETE /v1/me`, `GET/PUT /v1/topics`, `PUT /v1/mastery`. Settings gets **Delete account** and **Sign out**. A public deletion-request page for Google | `scripts/ui/boot/tutorial.gd`, `scenes/ui/boot/peek.tscn`, `game_state.gd`, `save_manager.gd`, `settings.gd`, `settings.tscn`, `backend/` |
| **5.3 AI gateway** (partly done: `/v1/extract` with structured outputs, grounding checks and the refusal fallback; `/v1/grade` for essays and Identification near-misses, server-scored; synchronous, so there is no `GET /v1/jobs/{id}`; delimited data against injection) | `POST /v1/extract` (PDF or pasted text → job), `GET /v1/jobs/{id}`, `POST /v1/grade` (essays). Keep the job envelope and the question schema in [`systems/gameplay-structure.md`](systems/gameplay-structure.md) §3.1 so `SessionManager._on_job_status` and `normalize_question()` need no change. **Structured outputs** (`output_config.format` with the question JSON schema); forced `tool_choice` is rejected on the current models. Check `stop_reason == "refusal"` and enable the documented server-side fallback for Sonnet 5.5; Haiku has none, so the app shows "couldn't grade this, try again". **Grounding checks** after the model answers (every `source` must appear in the reviewer text, Multiple Choice needs four distinct options, tiers must be spread; the server computes `confidence`). **Prompt-injection safety**: reviewer text and answers go in as delimited data; graders return only `{score, feedback, covered_concepts}`. **Server-side quota ledger** (weekly PDF and essay counters; the client has no limit since the old client-only `MonetizationState` was removed, so add a display cache of `/me` if limits come back), per-user and per-IP rate limits, a global daily spend cap; App Attest (iOS) and Play Integrity (Android) checks as hardening before public launch. **Consent screen** and **`POST /v1/reports`**. **Privacy**: PDFs deleted after extraction, logs hold metadata and token counts, not content | `backend/`, `api.gd`, `session_manager.gd`, `categorizer.gd`, `battle.gd` |
| **5.4 Store readiness** | Privacy policy, terms, support and deletion pages; Apple privacy labels and Google Data safety answers matching what the backend collects; age ratings; icon, screenshots and store text; a demo account and review notes for App Review; Sentry (Godot SDK and backend) for crashes | web pages, store consoles |
| **5.5 Release pipeline** | An Android job building a signed `.aab` from secrets; an iOS job on a macOS runner that exports the Xcode project, signs and uploads to **TestFlight** (fastlane or Codemagic); versions from CI. Release path: TestFlight internal → external beta; Play internal → closed → production with a **staged rollout**. The `/v1/config` minimum-version flag is the emergency lever | `.github/workflows/`, `export_presets.cfg` |

**Evals (the quality gate for 5.3).** A golden set of 8–10 reviewers (different subjects, text and PDF,
short and long, table-heavy) with checks for grounding, tier spread and distractor quality, and a
grading set of perfect, partial, off-topic and injection answers with expected score bands. Run it on
every prompt or model change in CI.

**Models and cost** (verify against the live pricing page when the work starts): extraction on
`claude-sonnet-5-5` ($2 / $10 per million tokens), grading on `claude-haiku-5-5` ($0.10 / $0.50). PDFs
go in as `document` blocks (API limit 32 MB and 600 pages on 1M-context models); the app caps uploads
lower (suggest 20 MB and 100 pages) so one bad file cannot burn the budget.

## 6. Mock-first prep that needs no server

These can be built and tested against the mocks before any backend exists, which also de-risks 5.2
and 5.3:

- ~~The **AI-data consent screen** and its stored flag.~~ Done (`GameState.ai_consent`, [`api-backend.md`](api-backend.md) §6).
- ~~A **Report button** on generated questions and essay feedback.~~ Done (`POST /v1/reports`).
- ~~**Delete account / Sign out** in Settings.~~ v1 has no accounts: Settings' **Delete my data** wipes the save.
- The tutorial's **profile step UI** (Google / Apple / Register buttons): only if accounts come later.
- ~~The `Api` request queue, timeout and error-signal handling.~~ Done (one `HTTPRequest` per call; no retry).

## 7. Later (not Phase 5)

Purchases (`godot-iap` or a similar plugin with server receipt validation and RevenueCat-style
entitlements), restore purchases, sharing topics between students, Endless Marathon, Subway Sprint
([`systems/gameplay-structure.md`](systems/gameplay-structure.md) "Future").

## 8. Risks

Google and Apple sign-in in Godot without an official plugin; iOS builds need macOS; a reviewer cannot
use a personal Google account (hence the demo account); runaway cost (spend cap and quotas);
hallucinated questions (grounding checks and evals); under-13 users if the audience decision changes;
Google's 14-day closed test.

## 9. Verification outline (when the work starts)

- **Backend:** tests for every route, quota and auth rule; contract tests that feed real responses
  through the client's `normalize_question()`; the eval run must clear agreed thresholds before a deploy.
- **Client:** the headless gates in [`rules.md`](rules.md) §6 and the committed scripted tests, against
  mock mode **and** a staging backend; Mock mode must still pass.
- **Device:** on a real Android phone and an iPhone (TestFlight): register, Google and Apple sign-in,
  the consent screen, a real PDF upload, a battle of each type, essay grading, reporting a question,
  hitting the quota, going offline, deleting the account and confirming the data is gone.
- **Store gates:** the Play pre-launch report, App Store Connect validation and a mock App Review pass
  using the demo account and the §3 checklist.
