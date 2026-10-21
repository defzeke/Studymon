# Glossary

Terms used throughout this repo, in the sense this repo means them.

## Game and companion

| Term | Meaning |
|---|---|
| **Studymon** | The project: a study-review game where a companion is raised, then used to fight through a campaign built from reviewer material. |
| **Companion** | The AI creature on the care-room table. Its state is `CompanionState` (level, XP, energy, focus, mood, bond, codex). |
| **Care tap** | One press of Feed, Pet or Play. Grants XP, nudges one stat, increments bond, and is subject to hourly diminishing returns. |
| **Energy / Focus / Mood** | The three 0–100 stats. Energy drains fastest; Focus and Mood drain at 0.8× and 0.6× of `STAT_DECAY_PER_SEC`. |
| **Bond** | A monotonic tap counter. It is saved, but nothing gates on it yet. |
| **XP curve** | The cumulative table `XP_PER_LEVEL = [0, 20, 45, 75, 110, 150]`. Level 5 is 150 XP. |
| **Level gate** | Level 5 unlocks the campaign (`campaign_ready`). Before that, the care loop is the whole game. |
| **Curriculum** | The five AI-literacy lines in `CompanionState.CURRICULUM`, one unlocked per level. |
| **Tidbit** | A curriculum line or other short prompt shown in the speech bubble. The bubble is currently always hidden (issue #4). |
| **Codex** | The accumulated list of unlocked tidbits. A five-step AI-literacy track; its UI is reachable from the care room, and a remote branch proposes cutting it. |
| **Insight** | A retention message produced by `SessionManager.last_insight` (missed question, mastery milestone), shown in the bubble. |
| **Pomodoro** | The 25-minute focus / 5-minute rest timer. Missing the rest costs energy and mood; finishing it grants a small bonus. |
| **Decay** | The per-second stat drain in `CompanionState._process`. It runs on every screen because the autoload is always alive. |
| **Campaign ready** | `CompanionState.campaign_ready`, set at Level 5. Gates the Campaign button. |

## Review material and questions

| Term | Meaning |
|---|---|
| **Reviewer** | The study material the player uploads or pastes (PDF or text). In mock mode, pasted text is parsed; binary bytes fall back to canned questions. |
| **Topic** | One reviewer's worth of content, identified by a slug (`topic_<name>`, or `topic_001`). Has a name, a question list, mastery records and gym progress. |
| **Extraction** | Turning a reviewer into questions. `Api.mock_upload_pdf()` is the current implementation; a real endpoint is not wired. |
| **Question** | `{id, text, type, answer, key_concepts, confidence, source}`. See [`data-model.md`](data-model.md). |
| **Identification** | A one-term answer graded locally: exact, contained, or within edit distance 2; 0.7–1.0. |
| **Essay** | A free-text answer graded in mock mode by 50 % key-concept coverage + 50 % length proxy. |
| **Key concepts** | The expected ideas for an essay. Coverage drives the mock score and the "missed:" feedback. |
| **Confidence** | The extractor's 0–1 self-rating. Displayed in the editor; not used for grading. |
| **Categorizer** | The upload/edit screen: pick a file or paste text, review the generated questions, change a type, add or delete one, then Confirm & Play. |
| **Fallback questions** | The canned trio used only when no usable text survived extraction (e.g. raw PDF bytes). |

## Campaign and battle

| Term | Meaning |
|---|---|
| **Region** | The overworld for one topic: the 3D island (`map.glb`) with its gyms, trainers and the Champion's gym, filled from the topic's questions. |
| **Explorer** | The player's walking character on the island (`boy_explorer.glb`), steered with the on-screen joystick at the bottom-left. |
| **Gym** | A group of encounters for one question type (`identification`, `essay`). Clearing every gym is the Champion prerequisite. |
| **Trainer** | A single-question encounter on the route. Winning it counts toward its gym. |
| **Boss** | The gym's final encounter. Same battle rules, larger presentation. |
| **Champion** | The region finale. Intended to use the player's Mastered questions as a moveset; currently soft-locks when there are none (issue #6). |
| **Moveset** | The Champion's question list, derived from `Mastery.MASTERED` questions. |
| **Mastery** | Per-question progress: wins take `NEW → LEARNING → MASTERED`; a loss steps it back (`MASTERED → REMASTER → LEARNING`). |
| **Remaster** | The state between `MASTERED` and `LEARNING`; only reached by losing a `MASTERED` question. The name is the enum's, not a separate feature. |
| **Badge** | The per-gym clear marker shown on the route. |

## Monetization

| Term | Meaning |
|---|---|
| **Free tier** | The default: 3 PDF uploads and 10 gradings per week (`FREE_PDF_LIMIT`, `FREE_GRADE_LIMIT`). |
| **Quota unit** | `"pdf"` (upload/extract) or `"grade"` (battle grading). Counted in `MonetizationState`, reset every 7 days. |
| **Premium** | `MonetizationState.is_premium`, persisted. Removes both limits; no purchase flow exists (the Settings toggle is the stub). |
| **Paywall dialog** | The `quota_exceeded` response: a modal saying the weekly AI limit was reached. |

## Engine and project

| Term | Meaning |
|---|---|
| **Autoload** | A singleton registered in `[autoload]` in `project.godot`. Seven exist: `SaveManager`, `GameState`, `Api`, `CompanionState`, `SessionManager`, `MonetizationState`, `MusicManager`. |
| **Splash** | The white intro screen (`splash.tscn`) that plays the 60-frame Kuizmon animation, then loads the loading screen. |
| **Main scene** | `res://scenes/ui/boot/splash.tscn`. It hands off to `loading.tscn`, then `peek.tscn` (tutorial, then home). |
| **Peek** | `peek.tscn`: the 3D Kuiz head (`assets/models/kuiz.glb`) peeking up on white after the loading screen. The tutorial then runs in the same scene. |
| **Home** | `home.gd` in `peek.tscn`: the game loop after the tutorial. A bottom bar walks Kuiz between the four rooms, each with its own action (charge, play, settings; screwdriver; food and fridge; ball). |
| **Tutorial** | `tutorial.gd` in `peek.tscn`: Kuiz's first-run lines, the profile and name prompts, and the tour of the Study Room, Maintenance Bay, Data Kitchen and Playroom. The last three rooms are temporary art. |
| **Ink outline** | The dark silhouette around Kuiz: an inverted hull (the mesh grown along its normals, front faces culled) in Deep Slate, sized by each node's `extras.outline`. |
| **`.tscn` / `.tres`** | Godot scene and resource text files. Both are source here, not build output. |
| **`ext_resource`** | A `.tscn` reference to an external file. If the target is missing, the scene fails to **parse** — no runtime fallback (issue #1). |
| **`.import` / `.uid`** | Generated metadata for assets. Never hand-edit; let the editor regenerate them. |
| **`user://`** | Godot's per-project writable directory. The save is `user://studymon_save.json`. |
| **`MOCK`** | `const MOCK := true` in `scripts/autoload/api.gd`. When true, every API call is served by canned or locally computed data. |
| **Job envelope** | The mock's async response shape: `{job_id, status, progress, result}`, broadcast on `Api.job_status`. |
| **`job_status`** | The global signal every async result travels on. Handlers match a `job_id`; `"grade"` is currently a magic id (issue #9). |
| **Rig** | `CompanionRig`, the skeletal `Skeleton2D` pet. Hidden in favour of `bot_sprite`, and the source of the `det == 0` warnings. |
| **Scene smoke test** | A headless run of one scene with `--quit-after N`; catches parse errors that `--import` misses. |
| **Headless** | `--headless`: no window or renderer. The only automated check this repo has. |

## Process and writing

| Term | Meaning |
|---|---|
| **Contract** | A doc that the code must match. If they disagree, one is a bug — see [`rules.md`](rules.md) §2. |
| **Gate** | A check that must pass before hand-off: import, per-scene smoke test, link check. |
| **Derived doc** | A doc that only records status, never rationale. [`tasks.md`](tasks.md) is the only one. |
| **Ponytail** | The project skill for the smallest complete change. Also the ladder it enforces. See [`.opencode/skills/ponytail/SKILL.md`](../.opencode/skills/ponytail/SKILL.md). |
| **Ladder** | The six rungs: need it → already here → Godot built-in → installed dependency → one line → minimum that works. |
| **`shortcut:`** | The one permitted deferral comment: `# shortcut: <limit>, <when to upgrade>`. |
| **Hand-off** | Ending a task with a summary and a proposed commit message instead of committing. |
| **P0–P3** | Severity in [`known-issues.md`](known-issues.md): blocks the loop / blocks a feature / wart / hygiene. |
| **Implemented, Mock, Partial, Missing, Broken** | The status vocabulary used across `docs/`; defined in [`README.md`](README.md#status-vocabulary). |
