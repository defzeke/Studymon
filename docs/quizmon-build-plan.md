# QUIZMON — Tech Stack & Build Plan

*Godot 4.6.x + AI backend, built incrementally with your Hermes agent harness driving scene/script generation.*

---

## 1. Tech Stack

### 1.1 Engine & Client
| Layer | Choice | Why |
|---|---|---|
| Engine | **Godot 4.6.x (stable)** | Current stable line; 4.7 is still early-access, avoid it for a real build. |
| Language | **GDScript** for all gameplay/UI logic | Fastest iteration loop for an agent harness to generate/edit — plain text, no compile step, easy diffing. Reach for C# only if you hit heavy numeric workloads (you won't for this game). |
| 2D framework | Godot's native 2D nodes (`CharacterBody2D`, `TileMapLayer`, `AnimatedSprite2D`, `Control`) | No need for a third-party framework; Godot 4's 2D pipeline is enough for Pou-style + overworld JRPG. |
| UI | Godot `Control` nodes + a single shared `Theme` resource | Keeps companion-home UI, battle UI, and Codex UI visually consistent without re-styling every scene. |
| State/data | Autoload singletons: `GameState`, `CompanionState`, `SessionManager`, `Api` | Godot's answer to global state; each owns one domain so Hermes can safely touch one file at a time. |
| Save format | `Resource`-based custom classes (`.tres`/binary), not raw JSON | Native serialization, versionable, and diffs cleanly with Git. |

### 1.2 Backend (you need one — never call an LLM API directly from the client)
| Layer | Choice | Why |
|---|---|---|
| API server | **Node.js (Fastify/Express) or Python (FastAPI)** | Thin proxy between Godot and Claude — keeps your API key off the client and lets you add auth/rate-limiting. |
| LLM | **Claude API** (Sonnet-tier model for extraction/grading, cheaper Haiku-tier for lightweight "Did You Know?" flavor text if you ever generate it dynamically) | Handles PDF ingestion → concept/question extraction, essay grading, and Champion moveset generation. Claude's document support (`type: document`, base64 PDF) means you don't need a separate PDF-parsing library server-side — send the PDF straight to the API for extraction. |
| Auth | **Supabase Auth** (or Firebase Auth) | Email/social login, matches "cloud-saved account, no guest mode" requirement (§3.1 of your GDD). |
| Database | **Supabase (Postgres) or Firebase Firestore** | Stores accounts, companion state, topics/regions, question banks, mastery states. Postgres is the better fit long-term because your data is relational (topic → gym → question → mastery record). |
| File storage | Supabase Storage / Firebase Storage / S3 | Store uploaded PDFs briefly for processing; you don't need to keep them post-extraction unless you want re-ingestion. |
| Hosting | Fly.io / Render / Railway for the API; Supabase handles its own hosting | Cheap, simple deploys, good for a solo/small-team indie project. |

### 1.3 Godot ↔ Backend glue
- Use Godot's built-in `HTTPRequest` node (wrapped in your `Api` autoload) to call your backend — no native HTTP addon needed.
- All Claude calls happen server-side; Godot only ever talks to *your* API, never `api.anthropic.com` directly.
- Long-running calls (PDF ingestion, essay grading) should be async: client POSTs, gets a job id, polls or gets a websocket/push update — keeps the "AI is studying..." loading beat (§5.2) honest instead of blocking the UI thread.

### 1.4 Tooling
- **Git + GitHub**, trunk-based with short feature branches per phase below.
- **Hermes** (your agent harness) — treat it as the primary author of scenes/scripts; you review/merge. Structure the repo so each subsystem (companion, review-session, battle) lives in its own folder with a short `README.md` describing its public API (autoload functions, signals) so Hermes has a stable contract to generate against without re-reading the whole codebase each time.
- **Godot's built-in profiler + remote scene tree** for debugging the two loops.
- Export templates for Android + iOS from day one (Pou-style games live and die on mobile feel — test on-device early, not just in-editor).

---

## 2. Build Plan — Phased, Mapped to Your GDD Sections

Each phase ends in something *playable*, so Hermes always has a working baseline to branch from.

### Phase 0 — Project Skeleton (½–1 day)
- Godot project + folder structure: `/companion`, `/review_session`, `/battle`, `/ui`, `/autoload`, `/backend`.
- Autoloads: `GameState`, `Api` (stubbed with mock responses so client dev isn't blocked on backend).
- Shared `Theme` resource + placeholder art (blocks/circles) so screens can be laid out before final art exists.
- Backend skeleton: FastAPI/Fastify project, health-check route, Supabase project created (auth + empty tables).

### Phase 1 — Accounts & First Meeting (1–2 days)
- Supabase email/social auth wired into a login/signup screen.
- On first login: `CompanionState` record created server-side, "meet your baby AI" cutscene scene.
- **UI enhancement:** make this a short, skippable-on-replay *scripted* scene (dialogue box + simple companion idle animation), not a wall of text — first impressions matter for a Pou-style hook.

### Phase 2 — Pet-Care Loop: Pet / Feed / Play (2–4 days)
This is your GDD's §4.2–4.3 — the whole pre-campaign gate.
- `CompanionState`: Energy, Focus, Mood, Bond, AI XP, Level — all as simple floats/ints with clamped ranges.
- Three tap interactions, each: input → stat delta → XP gain → animation/particle feedback → optional "Did You Know?" bubble (first N times per action + on level-up, per your curriculum table).
- Stat decay over time (`_process`/timer-based drain) so the loop has a reason to return.
- Level-up sequence: XP threshold check → evolution animation → unlock gate check (Level 5 → Review Campaign flag flips in `GameState`).
- **Logic enhancement:** add soft daily caps or diminishing XP returns per action (your Open Design Question #2) — otherwise players tap-spam to Level 5 in one sitting and the "bonding tutorial" intent (§4.3, last paragraph) is defeated. A simple formula: XP per tap decays after the 5th same-action tap that hour, resets next hour.
- **UI enhancement:** a persistent small HUD strip (Energy/Focus/Mood bars + Level) visible from every screen, not just the companion-home screen — reinforces the "always caring for it" fantasy even while in Study Prep or Battle.

### Phase 3 — AI Codex (1–2 days)
- Every unlocked "Did You Know?" tidbit saves to a `Codex` list in `CompanionState`, viewable from the companion's profile.
- **Enhancement (answers Open Design Question #4):** make the Codex lightly interactive rather than pure reference — a 2–3 question "pop quiz" the companion offers *after* Level 5, using the same quiz UI you're already building for battles. This reuses your battle-question component instead of building a separate quiz widget, and gives the AI-literacy content a payoff beyond flavor text.

### Phase 4 — Scheduler / Pomodoro (1–2 days, parallel-able with Phase 3)
- Timer-based focus/rest intervals; companion "asks" for rest at interval end.
- Missed-rest → soft Energy/Mood penalty, tied into the same `CompanionState` stats from Phase 2.
- **UI enhancement:** surface the *next* scheduled break as a small countdown badge on the companion HUD (from Phase 2) rather than a separate screen — keeps the wellness nudge ambient instead of another thing to check.

### Phase 5 — Review Session System: Upload & Categorize (3–5 days, client) + backend extraction pipeline
Backend:
- Endpoint: accept PDF → send to Claude as a document input → structured-JSON-only prompt returning proposed concepts/questions with suggested type (Essay/Identification).
- Store the raw extraction + player's edited version separately (so re-running extraction never clobbers a player's edits).

Client:
- Upload flow (native file picker via Godot's file dialog on desktop, platform picker on mobile).
- "AI is studying..." loading state — poll job status from Phase 5 backend.
- Editable list UI: add/remove/rewrite question, change type — this is essentially a lightweight CRUD list view, reusable component.
- Confirm → **Play** generates the region/map.
- **Logic enhancement:** cap or flag very short/garbled PDFs client-side before sending to the backend (word-count/page-count sanity check) — saves API cost and gives a better error than a vague empty extraction.
- **UI enhancement:** show each proposed question with a confidence/quality indicator from the extraction (e.g., "AI is fairly sure about this one" vs "double-check this") so players know where to spend their editing effort instead of reading all of them with equal scrutiny.

### Phase 6 — 2D Overworld & Gym Structure (3–5 days)
- Procedural-enough tilemap generator: N gyms (one per question category the player created) arranged along a route, hallway trainer spawns before each gym boss.
- Simple top-down movement (`CharacterBody2D` + 4/8-directional animation).
- Trainer/boss encounter triggers → hands off to Battle scene with the relevant question(s) bound.
- **UI enhancement:** a mini-map or gym-progress tracker (badges collected / gyms remaining) always accessible — Pokémon players expect this, and it doubles as a visible "how much material is left to review" indicator, which is the actual pedagogical point.

### Phase 7 — Battle Mechanics by Question Type (4–6 days)
Client:
- Battle scene: enemy sprite, HP bars, question prompt panel, answer input (text field for Essay/Identification).
- Identification: exact/fuzzy string match → instant KO or counter, per §6.2.
- Essay: submit free text → backend grades via Claude → damage value returned → applied with a short "judging..." beat.

Backend:
- Grading endpoint: rubric-based prompt (source excerpt + player answer + concept) → Claude returns a structured score (0–1) + one-line feedback, converted to damage server-side so grading logic is centralized and tunable without a client update.
- **Logic enhancement (answers your open rubric question):** use a hybrid rubric — 50% keyword/concept coverage (does the answer mention the key ideas extracted in Phase 5), 50% Claude's holistic quality judgment. This gives you a deterministic floor so grading doesn't feel arbitrary, plus the qualitative judgment your GDD wants.
- **UI enhancement:** always show the one-line AI feedback alongside the damage number ("Good — you covered the mechanism but missed the exception case") — turns every battle turn into a micro study-review moment instead of just a number, which is the core fantasy (§1: "the harder you hit *because* you understand it").

### Phase 8 — Mastery States & Champion Battle (2–3 days)
- Per-question mastery enum (New → Learning → Remaster → Mastered) stored server-side, updated after every battle result.
- **Logic enhancement (answers Open Design Question #9):** add time-based decay — a Mastered question flips to Remaster automatically after N days without a correct re-encounter (classic spaced-repetition), not only on a missed battle. This is what makes the Champion recap actually test *retention*, not just "did you get it right once."
- Champion battle: pull all current Mastered questions across the region as the Champion's moveset; clearing it is the region-complete state.
- **UI enhancement:** a visible mastery-state badge (color-coded) on every question everywhere it appears — gym hallway preview, Codex, pre-Champion summary screen — so players can *see* their retention decaying, which nudges them back into the app (this is your retention loop, make it visible, not buried in a stat).

### Phase 9 — Polish Pass (ongoing, but budget 1 real week before any playtest/launch)
- Companion "AI Insight" commentary reacting to real performance patterns (e.g., flags a subject the player keeps failing) — a simple rule-based trigger off the mastery data you already have; no need for an LLM call here, keep it cheap and instant.
- Juice: hit-stop/screen-shake on strong essay answers, particle bursts on level-ups and gym clears, sound design pass.
- Accessibility: font-size options, colorblind-safe mastery-state colors (don't rely on red/green alone for New/Mastered).
- Onboarding polish: re-check that Levels 1–5 genuinely take "minutes, not hours" as your GDD specifies — playtest and tune the XP curve from Open Design Question #1 here, not earlier, once you can feel the real pacing.

### Phase 10 — Stretch / Post-Launch (from your Open Design Questions)
- Monetization: recommend **AI-processing quota as the premium hook** (free tier = N PDF ingestions/essay-gradings per week, subscription = unlimited) over cosmetic-only — it directly funds your real variable cost (Claude API calls) rather than being disconnected from it.
- Multiplayer: start with **async topic-deck sharing** (export/import a region as a shareable code) before PvP — much lower engineering cost, and turns players' study materials into user-generated content for others, which is a strong organic-growth loop for a study app.
- Continued AI leveling past Level 5 as cosmetic/story-only milestones (per Open Design Question #3) — keeps the pet-care loop from feeling "finished" once the campaign unlocks.

---

## 3. Suggested Cross-Cutting Enhancements

- **One judging pipeline, not two.** Your GDD already anticipates extensibility (Multiple Choice, True/False, Enumeration). Build the Essay/Identification judging endpoint as `POST /grade {type, question, answer, source_context}` from day one, with `type` branching server-side. Adding a new question type later becomes a backend-only change — no client battle-logic rewrite.
- **Make the AI companion's commentary data-driven, not scripted per-line.** Store "Insight" triggers as simple condition→line mappings (e.g., `mastery.remaster_count_in_topic > 3` → pick from a line pool) so writers/designers can add commentary without touching Hermes-generated gameplay code.
- **Log every extraction and grading call with player feedback ("was this fair?" thumbs).** You'll need this data to tune the rubric in Phase 7 and to catch bad extractions in Phase 5 — build the thumbs-up/down UI cheaply now, you'll want the dataset before you want the fanciest UI for it.
- **Treat the hallway-vs-boss retry question (Open Design Question #6) as a difficulty setting, not a fixed rule** — e.g., default to "boss only" retry for approachable difficulty, full hallway retry for "hard mode," toggleable per player. Costs little and resolves the open question by not forcing one answer.

---

## 4. Suggested Order of Operations Summary

```
Phase 0  Project skeleton + backend skeleton
Phase 1  Accounts + first-meeting scene
Phase 2  Pet-care loop (Pet/Feed/Play, stats, XP, leveling)
Phase 3  AI Codex (+ optional pop-quiz reuse)
Phase 4  Scheduler/Pomodoro
Phase 5  Upload → AI extraction → categorize/edit
Phase 6  2D overworld + gym structure
Phase 7  Battle mechanics (Identification + Essay grading)
Phase 8  Mastery states + Champion battle
Phase 9  Polish pass
Phase 10 Monetization + stretch multiplayer
```

Each phase is scoped to be a self-contained Hermes task: give it the phase's scene/script targets plus the relevant `README.md` contracts from Section 1.4, and it should be able to produce a mergeable branch without needing the full GDD re-fed each time.
