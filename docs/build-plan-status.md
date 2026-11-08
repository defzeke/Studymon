# Build plan status

Phase-by-phase comparison of [`quizmon-build-plan.md`](quizmon-build-plan.md) against the
current code. Statuses follow the vocabulary in [`README.md`](README.md#status-vocabulary).

**Headline:** every phase has client-side code, and the whole loop runs on mocks. Boot ends on the
home loop, whose Play button opens the upload screen; upload → edit → island → battle →
mastery → Champion now plays end to end, with Multiple Choice, Identification and Essay gyms and
Easy/Medium/Hard battles ([`systems/gameplay-structure.md`](systems/gameplay-structure.md)). What is
still missing: the store launch (future, mock first: [`launch-plan.md`](launch-plan.md)). The Flashcard Sanctuary lets players review and repair mastery. Trainers and bosses gave way to
fixed-length runs: a Challenge House and a Gym per question type, then the Champion Gym
([`systems/battle.md`](systems/battle.md)).

---

## 1. Phase matrix

| Phase | Plan scope | Status | Where |
|---|---|---|---|
| **0** | Project skeleton, folder structure, autoloads, theme, backend health | **Implemented** (layout differs) | `project.godot`, 6 autoloads, `assets/theme/app_theme.tres`, `backend/main.py` |
| **1** | Accounts, first login, meet-your-companion cutscene | **Implemented** (no accounts, by design) — 3D peek + a name-only tutorial, run once | `scenes/ui/boot/peek.tscn`, `tutorial.gd`; `player_name` and `tutorial_done` saved |
| **2** | Pet-care loop: Pet/Feed/Play, stats, XP, decay, level gate, HUD strip | **Implemented** (Level 5 gate removed by design) — petting, food, tune-up, ball and charging call `care()`; the top HUD shows level, XP, hunger/energy/mood/health and crystals | `companion_state.gd`, `home.gd` |
| **3** | AI Codex + optional pop-quiz reuse | **Removed** (save v16) — it never had a screen | — |
| **4** | Scheduler / Pomodoro with missed-rest penalty, HUD badge | **Implemented** — the Study screen's focus timer; focus shows on the check-up tablet | `companion_state.gd` `start_pomodoro()`, `flashcards.gd:58` |
| **5** | Upload PDF → extraction → editable list → region | **Implemented (mock; Claude server built, untested live)** | `categorizer.gd`, `session_manager.gd`, `api.gd`, `backend/` |
| **6** | Overworld + gym structure + trainer encounters | **Implemented (mock)** | 3D island `region_map.tscn`, `player.gd`, `joystick.gd`; three gyms (one at a marker, no building) |
| **7** | Battle per question type, one judging pipeline | **Implemented (mock)** | `battle.gd`: Identification, Essay and Multiple Choice, per-tier HP/counter/thresholds |
| **8** | Mastery states + 7-day decay + Champion recap | **Implemented** | `session_manager.gd`; Champion falls back to every question |
| **9** | Polish: insights, juice, accessibility, pacing | **Partial** | particles/shake/hit-stop/colourblind badges and the large-text toggle done; the never-shown insight lines were removed (save v16) |
| **10** | Monetization quota + stretch | **Partial (mock)** | the client-side quota was removed; free launch; crystals buy world slots, food and costumes; no real-money shop; no deck sharing |

---

## 2. Phase details

### Phase 0 — Skeleton ✅

Delivered: Godot project on 4.7.2, portrait 720×1280, Mobile renderer, shared Josefin-Sans theme,
`Api` stubbed with mocks, FastAPI `/health`.

Deviations:

- The plan's top-level `companion/`, `battle/`, `review_session/` folders exist but contain only
  planning READMEs; real code lives under `scripts/<feature>/`.
- `resources/` and `tests/` were never created.
- Save format is JSON, not `Resource`-based. For this project that is the better call: the data is
  plain dictionaries and diffs readably, but it loses type safety (see `data-model.md` §6).
- A Godot MCP editor addon was used during development and has since been removed and gitignored.

### Phase 1 — Accounts & first meeting ✅ (no accounts)

Done: the first meeting is `peek.tscn`. After the loading screen, the 3D Kuiz peeks up, then the
tutorial (`tutorial.gd`) asks only for the player's name and tours the four rooms; its last line
hands off to the home loop. The name (`player_name`) and `tutorial_done` are saved, so the tutorial
runs once. The old text cutscene (`meet_companion.tscn`) and its starter-stats mock were removed;
`CompanionState`'s defaults are the same starter stats.

Not built, by decision: accounts. v1 ships without them ("no accounts, ever",
[`launch-plan.md`](launch-plan.md) §1), and the unused `GameState.user_id` / `auth_token` /
`set_user()` were removed.

### Phase 2 — Pet-care loop ✅

Done: stats with clamped ranges and per-second decay, care actions with distinct stat effects
(petting, food, the screwdriver tune-up, the ball, charging), hourly diminishing returns that never
reach zero (#5), level-up signals, endless levels that unlock closet costumes, the home HUD, save/load.
The Level 5 campaign gate was removed: Play is open from the start.


### Phase 3 — AI Codex (removed)

The curriculum lines, the `codex` list and `codex_entry_added` never had a screen; they were removed in
save v16 (an older save's `codex` key is ignored).

### Phase 4 — Pomodoro ✅

Done: 25/5 cycles owned by `CompanionState`, skip-focus penalty, missed-rest penalty, rest-complete
bonuses, companion dialogue lines per phase. The Study screen's focus timer starts it
(`flashcards.gd:58`); a finished focus session adds focus, shown on the check-up tablet.

Gaps: no notification/sound when a phase ends, and timer state is not persisted.

### Phase 5 — Review session ✅ (mock)

Done: paste-or-file input, word/char sanity gate, "AI is studying…" beat, deterministic mock
extractor that turns real reviewer prose into Identification / Essay / Multiple Choice questions tagged Easy, Medium or Hard, editable
list with confidence indicators, topic history, region data generation.

Built, not yet run against the real model: `POST /v1/extract` (Claude writes the questions and their
answer keys from pasted text or a PDF; the server checks grounding and drops bad items), used when
the server is on (release builds). On mocks a PDF is refused (`review-session.md` §2). Raw-vs-edited extraction storage
was not built: the server is stateless and stores nothing.

### Phase 6 — Overworld ✅ (mock)

Done: the 3D island (`map.glb`) under an angled top-down camera, the explorer (`boy_explorer.glb`)
with Idle/Walk/Run on a left-hand joystick (keys too), collision built from the map's meshes,
derived gym structure (one gym per question type) placed in the map's gym buildings with animated
doors, 15 Challenge Houses found in the map's house meshes (`map_houses.gd`), the Champion in the
big gym, encounter panel, quest card and minimap, Kuiz following the explorer, gym-clear particles.
Clear state saves the moment a battle ends.

### Phase 7 — Battle ✅ (mock)

Done: one judging pipeline that branches on `type`, Multiple Choice tapped and graded locally,
Identification one-hit-KO and counter, Essay damage from score with an enemy counter formula, boss
HP, hit-stop and camera shake, and enemy HP, counters, XP and thresholds
from the question's difficulty tier.

Gaps: no enemy or player art (the missing `bot_lv*.png` references were removed). Multiple Choice and
Identification are checked on the device against the answer key; essays and Identification near-misses
go to `POST /v1/grade` with an offline mark as fallback (`battle.md` §5). The server path has been
checked against a stubbed Claude only.

### Phase 8 — Mastery & Champion ✅

Done: `NEW → LEARNING → REMASTER → MASTERED`, demotion on loss, lazy 7-day decay, colourblind-safe
badges surfaced on trainers / summaries / encounter text, champion queue with per-step questions and
region-complete state.

The Champion's moveset is the Mastered questions, falling back to every question when none is, sorted
Easy to Hard.

Mastery is keyed by question id since save v15, so editing or deleting other questions keeps it
(`data-model.md` §4).

### Phase 9 — Polish ⚠️

Done: level-up and
gym-clear `CPUParticles2D`, screen shake + hit-stop on strong hits, colourblind-safe mastery colours,
XP curve explicitly tuned and documented, hover/press juice helper.

Missing: SFX for level-ups and
gym clears (battle has its own cues),
onboarding pacing verification on device, and any accessibility options beyond the colour choices.

### Phase 10 — Monetization & stretch ⚠️

Removed: the free-tier PDF (3/week) and grading (10/week) quotas, the premium flag, the quota
labels and the "Weekly limit reached" pop-up (`MonetizationState`). Every AI use is unlimited. The
placeholder Crystal Shop was removed for the free launch.

Done: an in-game crystal economy (world slots, food, costumes, battery; earned from runs, level-ups,
minigames and the study goal), [`systems/monetization.md`](systems/monetization.md).

Missing: a real store/IAP, server-side entitlement, and async topic-deck sharing.

---

## 3. Cross-cutting items from the plan's §3

| Recommendation | Status |
|---|---|
| One judging pipeline, branch by `type` | **Implemented** — single `grade_battle_question()` + mock rubric that switches on type |
| Data-driven companion insights, not scripted lines | **Removed** — the `INSIGHT_TRIGGERS` lines were never shown, so they went in save v16 |
| Log extractions/gradings + thumbs feedback | **Missing** — no telemetry, no feedback UI |
| Hallway-vs-boss retry as a difficulty toggle | **Missing** — retry always re-runs the same battle in place |

---

## 4. Path back to a playable vertical slice

Ordered by leverage; the first two are the whole game.

Done: the battle scene loads, progress saves after battles and topic confirmation, and the Champion
fallback, tier-ordered trainers and boss lock are in.

1. ~~Care input that earns XP and the Level 5 gate~~: care earns XP, and the Level 5 gate was removed (the campaign is open from the start).
2. ~~Un-hide `TidbitBubble`~~: gone with the care room; the tidbits and insights it showed were removed.
3. ~~Fix the `Authorization` scheme~~: removed with accounts (#2).

The loop upload → edit → overworld → battle → mastery → Champion is playable end to end on mocks.

---

## 5. Deviations from the plan's stack table

| Plan says | Reality | Note |
|---|---|---|
| Godot 4.6.x, "avoid 4.7" | 4.7.2 stable | 4.7 is the shipping line now; keep it |
| `Resource`-based saves | JSON file, `"v": 16` | simpler diffs, no type safety |
| FastAPI **or** Node backend with Claude + Supabase | FastAPI gateway with Claude (`/v1/extract`, `/v1/grade`) | stateless: no Supabase, no DB, no accounts |
| Supabase Auth / DB / Storage | none | no accounts, ever (decided 2026-10-29) |
| Job polling for long tasks | `job_status` signal; synchronous requests with a per-call `HTTPRequest` and timeout | no polling loop |
| Android + iOS export templates from day one | not configured | no `export_presets.cfg` in the repo |
