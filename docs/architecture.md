# Architecture

How the project is wired: configuration, autoloads, scene flow, and where state actually lives.

---

## 1. Project configuration

From `project.godot` (`config_version=5`):

```ini
[application]
config/name="Studymon"
run/main_scene="res://scenes/ui/splash.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/icon="res://icon.svg"

[display]
window/size/viewport_width=720.0
window/size/viewport_height=1280.0
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[gui]
theme/custom="res://ui/app_theme.tres"

[physics]
3d/physics_engine="Jolt Physics"      # unused — the only 3D is peek.tscn, which has no physics

[rendering]
rendering_device/driver.windows="d3d12"
renderer/rendering_method="mobile"
```

Notes:

- Portrait-first mobile target; `canvas_items` + `expand` means UI scales with window and gains
  extra space on non-9:16 aspect ratios.
- One shared `Theme` is set project-wide **and** re-assigned per screen in `_ready()`
  (`theme = load("res://ui/app_theme.tres")`). The per-screen assignment is redundant but harmless.
- The editor plugin `[editor_plugins]` section was intentionally removed and `addons/godot_mcp` is
  gitignored — see the commit `chore: remove godot_mcp addon and stale autoload/plugin references`.

---

## 2. Real folder layout

The repo uses **two parallel conventions**: gameplay code is grouped by feature under `scripts/`,
while the Phase-0 architecture docs also created top-level feature folders that now hold only
planning READMEs.

```text
res://
├── project.godot
├── icon.svg
├── assets/
│   ├── audio/            charge.mp3, charged.mp3, hmm.mp3, main room.mp3
│   ├── fonts/            JosefinSans-Regular.ttf, JosefinSans-Bold.ttf
│   ├── models/           kuiz.glb (peek scene), boy_explorer.glb + 2 .jpg textures (unused)
│   └── sprites/
│       ├── 1run_loading.png, 2run_loading.png, 3run_loading.png   # unused run cycle
│       ├── leaf.svg                                               # loading falling leaves
│       ├── loading.png                                            # loading background
│       ├── logo.png                                               # loading wordmark
│       ├── kuizmon_loading.gif                                    # splash source (not imported)
│       ├── kuizmon_splash.png                                     # 60-frame splash sheet
│       ├── companion/    idle, blink, sad, happy, charge, complete (.svg)
│       ├── rooms/        main.svg (day), dark_main.svg (night)
│       └── ui/           campaign.png, charge.png, loading_spark.svg, pomodoro.svg,
│                         settings.svg, table.svg, tip_bulb.svg, top_bar.svg
├── autoload/             api.gd, game_state.gd          ← 2 autoloads live here
├── scripts/
│   ├── autoload/         save_manager.gd, companion_state.gd,
│   │                     session_manager.gd, monetization_state.gd, music_manager.gd
│   ├── battle/           battle.gd
│   ├── companion/        companion.gd, companion_rig.gd
│   ├── overworld/        region_map.gd, player.gd
│   ├── review_session/   categorizer.gd
│   └── ui/               splash.gd, loading.gd, peek.gd, main.gd, session_list.gd,
│                         settings.gd, pomodoro.gd, hud_strip.gd, button_juice.gd
├── scenes/               splash, loading, peek, main, session_list, settings (ui/)
│                         companion_rig (companion/)
│                         region_map (overworld/), categorizer (review_session/)
│                         battle (battle/)
├── ui/                   app_theme.tres, hud_strip.tscn, pomodoro.tscn, README.md
├── backend/              main.py (FastAPI stub), requirements.txt, README.md
├── companion/, battle/, review_session/   ← planning READMEs only, no code
├── docs/                 ← this folder
├── README.md
└── quizmon-build-plan.md
```

**Not present** despite being described in `README.md` / the build plan: `resources/`,
`assets/themes/`, `tests/`, `upload_dialog.tscn`, `main_menu.tscn`, `companion_room.tscn`,
`battle_arena.tscn`, and the `GameManager` / `AIService` / `SoundManager` singletons.

The `scripts/autoload/` vs `autoload/` split is historical: `autoload/` holds the Phase-0
singletons (`Api`, `GameState`), `scripts/autoload/` holds everything added afterwards. New
autoloads should go in `scripts/autoload/`; do not move the existing two without updating
`project.godot` and every `get_node("/root/...")` string.

---

## 3. Autoloads

Declared in this order (Godot instantiates top-down, so earlier autoloads are `_ready()`-ed first):

| # | Name | File | Owns |
|---|---|---|---|
| 1 | `SaveManager` | `scripts/autoload/save_manager.gd` | JSON persistence of every other state |
| 2 | `GameState` | `autoload/game_state.gd` | account ids, auth token, campaign unlock flag, active region, large-text |
| 3 | `Api` | `autoload/api.gd` | HTTP wrapper **and** the whole mock backend |
| 4 | `CompanionState` | `scripts/autoload/companion_state.gd` | stats, XP/level, codex, pomodoro |
| 5 | `SessionManager` | `scripts/autoload/session_manager.gd` | topics, extraction, gyms, mastery, champion, battle handoff |
| 6 | `MonetizationState` | `scripts/autoload/monetization_state.gd` | weekly quotas, premium flag |
| 7 | `MusicManager` | `scripts/autoload/music_manager.gd` | looping BGM + one-shot SFX |

```text
                        ┌──────────────┐
                        │  SaveManager │  serialises 4 → 5 → 6
                        └──────┬───────┘
                               │ reads/writes
   ┌───────────┐   ┌───────────▼────┐   ┌──────────────┐
   │ GameState │◄──┤ CompanionState │──►│ MusicManager │
   └─────┬─────┘   └───────┬────────┘   └──────────────┘
         │                 │
         │           ┌─────▼─────────┐      ┌──────────────────┐
         └──────────►│ SessionManager│◄────►│ MonetizationState│
                     └─────┬─────────┘      └────────┬─────────┘
                           │                         │
                     ┌─────▼─────┐                   │
                     │    Api    │◄──────────────────┘ (quota gate)
                     └───────────┘
```

Dependency notes:

- `SessionManager` reaches into `Api` directly (`Api.job_status.connect(...)` in `_ready`).
- `Api` and the UI reach into `MonetizationState` **defensively** via
  `get_node_or_null("/root/MonetizationState")`, so scenes can run standalone in the editor.
- `CompanionState`, `GameState`, `SessionManager` are used as bare globals everywhere else —
  adding a new autoload with the same name as a `class_name` will break that.
- `GameState.current_topic_id` duplicates `SessionManager.current_topic_id`. Both are written in
  different places (`categorizer.gd:315`, `region_map.gd:45`); nothing reads the `GameState` copy.
  Treat `SessionManager`'s field as the source of truth.

---

## 4. Scene flow

```text
splash.tscn  (main scene)
   │  ~2.55 s: 60-frame intro, hold, fade out
   ▼
loading.tscn
   │  ~7.6 s scripted fill, 0.4 s fade to white
   ▼
peek.tscn  (3D, white)
      Kuiz peeks (5.7 s), greets (2.9 s), then idles. End of the boot flow for now:
      the tutorial that will lead from here into the room is not written yet.

main.tscn  (care room — not reachable from boot; open the scene directly to work on it)
   ├── CampaignButton (enabled only when campaign_unlocked) ─► session_list.tscn
   ├── PomodoroButton ─► toggles in-scene ui/pomodoro.tscn
   ├── ChargeButton   ─► toggles day/night room art + SFX
   └── SettingsButton ─► settings.tscn ──► back to main

session_list.tscn
   ├── Add New Topic ─► categorizer.tscn  (editing_topic_id = topic_<unix%100000>)
   └── Open topic    ─► categorizer.tscn  (loads stored questions)

categorizer.tscn
   └── Confirm & Play ─► confirm_topic() ─► region_generated ─► region_map.tscn

region_map.tscn
   ├── walk into Trainer/Gym/Champion Area2D ─► encounter panel
   └── Fight! ─► battle.tscn

battle.tscn
   ├── win (trainer/boss) ─► region_map.tscn
   ├── win (champion, more queue) ─► reload battle.tscn with next question
   ├── win (champion, last)      ─► region_map.tscn (region complete)
   ├── lose (Retry) ─► same scene, HP reset
   └── lose (Flee) / Flee button ─► region_map.tscn
```

Every transition is `get_tree().change_scene_to_file(...)` on a hard-coded `res://` path. There is
no scene router or transition manager. The boot chain preloads: splash and loading each
thread-load the next scene while they play, so those changes hit the resource cache (see
[`ui-and-assets.md`](ui-and-assets.md) §2).

---

## 5. State ownership

| Question | Answer lives in |
|---|---|
| Is the campaign unlocked? | `GameState.campaign_unlocked_flag` (mirrored from `CompanionState.campaign_ready`) |
| What level / XP / stats? | `CompanionState` |
| What topics exist? | `SessionManager._topics` (private, read via `get_topics_cache()`) |
| What is being edited? | `SessionManager.pending_questions` + `editing_topic_id` |
| What gyms exist? | derived on demand from `pending_questions` (`get_gym_structure()`) |
| Which trainer/gym is cleared? | `SessionManager._cleared_trainers` / `_cleared_gyms` |
| Mastery per question? | `SessionManager._mastery` |
| Which battle am I in? | `SessionManager.battle_topic_id` / `battle_q_index` / `battle_is_boss` / `battle_is_champion` |
| Free-tier usage? | `MonetizationState` |
| Auth token / user id? | `GameState.auth_token` / `user_id` — **never set today** |

Rule of thumb: **scenes read and call autoloads; autoloads never call scenes.** The only
scene↔scene coupling is `change_scene_to_file` and the `SessionManager` battle-handoff fields,
which exist precisely so the overworld can pass a question to the battle scene across a scene change.

---

## 6. Signal map

| Signal | Emitter | Listeners |
|---|---|---|
| `stats_changed` | `CompanionState` (every frame) | `hud_strip.gd`, `pomodoro.gd` |
| `xp_changed(current_xp, level)` | `CompanionState` | `companion.gd`, `hud_strip.gd` |
| `leveled_up(new_level)` | `CompanionState` | `companion.gd` |
| `codex_entry_added(text)` | `CompanionState` | `companion.gd` |
| `campaign_gate_ready` | `CompanionState` | `companion.gd` |
| `pomodoro_phase_changed(mode)` | `CompanionState` | `companion.gd` |
| `campaign_unlocked` | `GameState` | *(none)* |
| `large_text_changed(enabled)` | `GameState` | `companion.gd` (no UI emits it) |
| `job_status(job_id, status, progress, result)` | `Api` | `SessionManager`, `battle.gd` |
| `quota_exceeded(type)` | `Api` | `battle.gd`, `categorizer.gd` |
| `topics_listed`, `extraction_*`, `topic_saved`, `region_generated`, `overworld_progress_changed` | `SessionManager` | `session_list.gd`, `categorizer.gd`, `region_map.gd` |
| `mastery_changed`, `champion_defeated`, `insight_triggered` | `SessionManager` | `companion.gd`, `region_map.gd` |
| `quota_changed`, `premium_changed` | `MonetizationState` | `settings.gd`, `battle.gd`, `categorizer.gd` |

`Api.job_status` is a **shared bus**: extraction jobs, the `"topics"` listing, and the `"grade"`
result all arrive on the same signal and are disambiguated by `job_id` string. Any new async
operation must pick a unique `job_id` or it will be consumed by the wrong listener.

---

## 7. Boot sequence

1. `splash.tscn` `_ready()` — starts a threaded load of `loading.tscn`, slices `kuizmon_splash.png`
   into 60 `AtlasTexture` frames and starts playback at 30 ms/frame. After 1.8 s it holds the last
   frame for 0.5 s, fades the logo to white over 0.25 s, then changes to the already-loaded
   `loading.tscn`.
2. `loading.tscn` `_ready()` — loads theme, starts a threaded load of `peek.tscn`, asks
   `MusicManager.ensure_playing()`, fades its white `Fade` overlay out over 0.4 s, and starts tip
   rotation.
3. ~7.6 s tween: 0 → 96 % in 5 s, hold 0.6 s, crawl to 100 % in 2 s.
4. `loading.gd:_advance()` — fades `Fade` back to white over 0.4 s, then changes to `peek.tscn`.
5. `peek.tscn` `_ready()` — applies the artifact look to Kuiz (vertex colours, ink outline, flat
   self-lit parts, additive glows; see [`ui-and-assets.md`](ui-and-assets.md) §2), then plays
   `Peek_Surprise` → `Greetings` → looping `Idle`. Boot ends here.

**No save is read during boot.** The only loader calls are in the care room, which boot no longer
reaches: `main.gd:_ready()` calls `SaveManager.load_game()`, and the nested `Room` node's
`companion.gd:_ready()` calls it **again** (see known issues). A first-time companion starts from
`CompanionState`'s own defaults (level 1, energy 80, focus 70, mood 75, first codex line).

There is no login, no token exchange, and no read of `GameState.user_id` anywhere in the codebase —
the auth layer described in Phase 1 was deliberately skipped (`loading.gd:2`).
