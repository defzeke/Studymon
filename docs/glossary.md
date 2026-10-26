# Glossary

Terms used throughout this repo, in the sense this repo means them.

## Game and companion

| Term | Meaning |
|---|---|
| **Studymon** | The project: a study-review game where a companion is raised, then used to fight through a campaign built from reviewer material. |
| **Companion** | Kuiz, the AI creature in the home rooms. Its state is `CompanionState` (level, XP, hunger, energy, mood, health, focus, bond, codex). |
| **Dirt** | `CompanionState.dirt`, 0 (clean) to 100: builds up over time and with meals and play, shows as spots and scratches on Kuiz, scrubbed off with the towel. |
| **Outfit** | What Kuiz wears from the Playroom closet, `GameState.outfit`: one costume per slot (head, face, body), each a sticker on its head. |
| **Battery health** | `CompanionState.battery_health`: the battery's capacity, like a phone's. Charging wears it, a worn battery drains energy faster, and a new one (30 crystals, the check-up tablet) restores 100 %. |
| **Crystals** | Home's currency, `GameState.crystals`, shown top right with the logo's forehead gem. Saved; minigame rounds earn it, a new battery spends it. Buying it with real money is "Coming soon" in the Crystal Shop. |
| **Care tap** | One press of Feed, Pet or Play. Grants XP, nudges one stat, increments bond, and is subject to hourly diminishing returns. |
| **Hunger / Energy / Mood / Health** | The four 0–100 stats on home's HUD gauges. Energy drains fastest; Hunger, Mood and Health drain at 0.7×, 0.6× and 0.2× of `STAT_DECAY_PER_SEC`. Focus (0.8×) is also 0–100 but only flashcards use it. |
| **Bond** | A monotonic tap counter. It is saved, but nothing gates on it yet. |
| **XP curve** | `CompanionState.xp_to_reach(lv)`: 20 XP for Level 2, then 5 more per level (Level 5 at 110, Level 6 at 150); no cap. |
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
| **World** | The player-facing name for a topic: the Worlds hub lists saved worlds, and a new one is built from a reviewer. |
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
| **Gym** | A group of encounters for one question type (`identification`, `essay`, `multiple_choice`). Clearing every gym is the Champion prerequisite. |
| **Trainer** | A single-question encounter on a gym's road, ordered Easy to Hard. Every trainer of a gym must be beaten before its boss opens. |
| **Boss** | The gym's hardest question, fought after its trainers; winning it clears the gym. 150 HP and double XP. |
| **Tier** | A question's `difficulty`: `easy`, `medium` or `hard`. It sets the enemy's HP, the counter damage, the XP and the grading thresholds in battle. |
| **Distractors** | The wrong options of a Multiple Choice question (`distractors`, three strings); the correct option is its `answer`. |
| **Champion** | The region finale: the Mastered questions (or every question when none is), Easy to Hard, back to back. |
| **Moveset** | The Champion's question list, derived from `Mastery.MASTERED` questions. |
| **Mastery** | Per-question progress: wins take `NEW → LEARNING → MASTERED`; a loss steps it back (`MASTERED → REMASTER → LEARNING`). |
| **Remaster** | The state between `MASTERED` and `LEARNING`; only reached by losing a `MASTERED` question. The name is the enum's, not a separate feature. |
| **Badge** | The per-gym clear marker shown on the route. |

## Monetization

| Term | Meaning |
|---|---|
| **Weekly limit** | Removed. The free tier's weekly PDF and grading quota, the premium flag and the "Weekly limit reached" pop-up are gone; every AI use is unlimited. See [`systems/monetization.md`](systems/monetization.md). |

## Engine and project

| Term | Meaning |
|---|---|
| **Autoload** | A singleton registered in `[autoload]` in `project.godot`. Six exist: `SaveManager`, `GameState`, `Api`, `CompanionState`, `SessionManager`, `MusicManager`. |
| **Splash** | The white intro screen (`splash.tscn`) that plays the 60-frame Kuizmon animation, then loads the loading screen. |
| **Main scene** | `res://scenes/ui/boot/splash.tscn`. It hands off to `loading.tscn`, then `peek.tscn` (tutorial, then home). |
| **Peek** | `peek.tscn`: the 3D Kuiz head (`assets/models/kuiz.glb`) peeking up on white after the loading screen. The tutorial then runs in the same scene. |
| **Sanctuary** | The Flashcard Sanctuary (`flashcards.tscn`): untimed card review of a topic. Again / Hard / Easy; Easy lifts a New or Remaster card to Learning, never to Mastered. |
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
