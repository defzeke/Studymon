# Architecture

How the project is wired: configuration, autoloads, scene flow, and where state actually lives.

---

## 1. Project configuration

From `project.godot` (`config_version=5`):

```ini
[application]
config/name="Studymon"
run/main_scene="res://scenes/ui/boot/splash.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/icon="res://icon.svg"

[display]
window/size/viewport_width=720.0
window/size/viewport_height=1280.0
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[gui]
theme/custom="res://assets/theme/app_theme.tres"

[physics]
3d/physics_engine="Jolt Physics"      # region_map.tscn: trimesh map collision, explorer body

[rendering]
rendering_device/driver.windows="d3d12"
renderer/rendering_method="mobile"
anti_aliasing/quality/msaa_3d=2       # 4x MSAA: smooths Kuiz's ink outline in peek.tscn
```

Notes:

- Portrait-first mobile target; `canvas_items` + `expand` means UI scales with window and gains
  extra space on non-9:16 aspect ratios.
- One shared `Theme` is set project-wide **and** re-assigned per screen in `_ready()`
  (`theme = load("res://assets/theme/app_theme.tres")`). The per-screen assignment is redundant but harmless.
- The editor plugin `[editor_plugins]` section was intentionally removed and `addons/godot_mcp` is
  gitignored — see the commit `chore: remove godot_mcp addon and stale autoload/plugin references`.

---

## 2. Real folder layout

Gameplay code is grouped by feature: `scripts/<feature>/` holds the scripts and `scenes/<feature>/`
the matching scenes. The boot flow and the reusable HUD widgets are sub-folders of `ui/`.

```text
res://
├── project.godot
├── icon.svg
├── assets/
│   ├── audio/            music/ (home_room.wav, loading.wav, overworld.wav), sfx/ (ten battle cues, sfx_charge,
│   │                     sfx_charged); all our own, synthesised offline
│   ├── fonts/            JosefinSans-Regular.ttf, JosefinSans-Bold.ttf
│   ├── models/           kuiz.glb (peek scene); map.glb + map_0.png, boy_explorer.glb + 2 .jpg,
│   │                     explorer_girl.glb + 2 .jpg
│   │                     textures (overworld)
│   ├── theme/            app_theme.tres (the one shared Theme)
│   └── sprites/
│       ├── boot/         kuizmon_splash.png (60-frame splash sheet), kuizmon_loading.gif (its
│       │                 source, not imported), loading.png (background), loading_screen_logo.gif (logo animation source, not imported) and
│       │                 loading_screen_logo.png (its frames, keyed, as a sheet)
│       ├── effects/      leaf.svg (loading leaves, autumn weather)
│       ├── props/        foods, fridge, ball, screwdriver, soccer_ball, platform, ground,
│       │                 platform_timed, trampoline, rocket, platform_space|galaxy|deep,
│       │                 stars, meteor, tablet, towel, closet, dirt_spot_1-3, scratch_1-2,
│       │                 costume_* (11)
│       │                 (temporary placeholders)
│       ├── rooms/        temporary placeholders: study_room.svg (+ _night), maintenance_bay.svg,
│       │                 data_kitchen.svg, playroom.svg; soccer_field.svg, sky_jump.svg,
│       │                 sky_space.svg, sky_galaxy.svg, sky_deep.svg
│       ├── battle/       battle_backdrop.svg
│       └── ui/           arrow.svg, icon_charge.svg, icon_upload.svg, icon_settings.svg,
│                         crystal.svg, stat_mood.svg, stat_health.svg, icon_games.svg,
│                         game_soccer.svg, game_jump.svg, dock_table.svg,
│                         icon_back.svg, icon_trainer.svg, icon_badge.svg, icon_crown.svg,
│                         icon_lock.svg, icon_study.svg (region map HUD),
│                         loading_spark.svg, tip_bulb.svg; campaign.png, charge.png,
│                         settings.svg (unused)
├── scripts/
│   ├── autoload/         the 6 autoloads: save_manager.gd, game_state.gd, api.gd,
│   │                     companion_state.gd, session_manager.gd, music_manager.gd
│   ├── audio/            synth.gd, clip_voice.gd (model sounds made in code)
│   ├── battle/           battle.gd, arena_stage.gd, broken_bot_voice.gd
│   ├── overworld/        region_map.gd, player.gd, joystick.gd, season.gd, encounter_trigger.gd,
│   │                     gym_slot.gd, map_collision.gd, minimap.gd, explorer_picker.gd,
│   │                     kuiz_follower.gd
│   ├── review_session/   categorizer.gd, flashcards.gd
│   └── ui/               home.gd, session_list.gd, settings.gd
│       ├── boot/         splash.gd, loading.gd, peek.gd, tutorial.gd, kuiz_voice.gd, kuiz_look.gd
│       ├── minigames/    minigame.gd, soccer.gd, sky_jump.gd (Playroom games)
│       └── widgets/      confirm_modal.gd, stat_gauge.gd
├── scenes/               session_list, settings (ui/)
│   │                     encounter_trigger, gym_burst, region_map (overworld/)
│   │                     categorizer, flashcards (review_session/), battle (battle/)
│   └── ui/boot/          splash, loading, peek
├── backend/              main.py (FastAPI stub), requirements.txt, README.md
├── docs/                 ← this folder (includes quizmon-build-plan.md)
└── README.md
```

**Not present** despite being described in `README.md` / the build plan: `resources/`,
`assets/themes/`, `tests/`, `upload_dialog.tscn`, `main_menu.tscn`, `companion_room.tscn`,
`battle_arena.tscn`, and the `GameManager` / `AIService` / `SoundManager` singletons.

All autoload scripts live in `scripts/autoload/`. Moving one means updating `project.godot` and
every `get_node("/root/...")` string.

---

## 3. Autoloads

Declared in this order (Godot instantiates top-down, so earlier autoloads are `_ready()`-ed first):

| # | Name | File | Owns |
|---|---|---|---|
| 1 | `SaveManager` | `scripts/autoload/save_manager.gd` | JSON persistence of every other state |
| 2 | `GameState` | `scripts/autoload/game_state.gd` | account ids, auth token, campaign unlock flag, active region, large-text |
| 3 | `Api` | `scripts/autoload/api.gd` | HTTP wrapper **and** the whole mock backend |
| 4 | `CompanionState` | `scripts/autoload/companion_state.gd` | stats, XP/level, codex, pomodoro |
| 5 | `SessionManager` | `scripts/autoload/session_manager.gd` | topics, extraction, gyms, mastery, champion, battle handoff |
| 6 | `MusicManager` | `scripts/autoload/music_manager.gd` | main-room + loading BGM, one-shot SFX |

```text
                        ┌──────────────┐
                        │  SaveManager │  serialises 2, 4, 5 and 6
                        └──────┬───────┘
                               │ reads/writes
   ┌───────────┐   ┌───────────▼────┐   ┌──────────────┐
   │ GameState │◄──┤ CompanionState │──►│ MusicManager │
   └─────┬─────┘   └───────┬────────┘   └──────────────┘
         │                 │
         │           ┌─────▼─────────┐
         └──────────►│ SessionManager│
                     └─────┬─────────┘
                           │
                     ┌─────▼─────┐
                     │    Api    │
                     └───────────┘
```

Dependency notes:

- `SessionManager` reaches into `Api` directly (`Api.job_status.connect(...)` in `_ready`).
- `CompanionState`, `GameState`, `SessionManager` are used as bare globals everywhere else —
  adding a new autoload with the same name as a `class_name` will break that.
- `SessionManager.current_topic_id` is the only current-topic field.

---

## 4. Scene flow

```text
splash.tscn  (main scene)
   │  ~2.55 s: 60-frame intro, hold, fade out
   ▼
loading.tscn
   │  ~7.6 s scripted fill, 0.4 s fade to white
   ▼
peek.tscn  (3D Kuiz over 2D rooms; the hub)
   │  Kuiz peeks (5.7 s), then the tutorial: intro, profile Continue, name, and a tour of the
   │  Study Room, Maintenance Bay, Data Kitchen and Playroom. A tap after the last line starts
   │  the home loop; once the tutorial is done this session, the scene opens straight into it.
   ├── ◀ / ▶   walk between the four rooms
   ├── Play     ─► session_list.tscn  (Worlds hub)
   └── Settings ─► settings.tscn ──► back to peek.tscn


session_list.tscn  (Worlds hub; home Play opens it)
   ├── Saved worlds: Play ─► region_map.tscn · Cards ─► flashcards.tscn · Edit ─► categorizer.tscn
   │                 Reset progress / Delete (confirmed) ─► SessionManager.reset_topic_progress / delete_topic
   ├── + New World ─► categorizer.tscn (World Builder)  (editing_topic_id = topic_<unix%100000>)
   └── Back ─► peek.tscn (home)

categorizer.tscn
   └── Confirm & Play ─► confirm_topic() ─► region_generated ─► region_map.tscn

region_map.tscn
   ├── walk into a Trainer/Gym/Champion Area3D ─► encounter panel
   ├── Study button / session-list Cards ─► flashcards.tscn
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
| Auth token / user id? | `GameState.auth_token` / `user_id` — **never set today** |
| Player's name? | `GameState.player_name`, set by the tutorial; memory only, never saved |
| Tutorial seen / food in stock? | `GameState.tutorial_done` / `food_stock`; memory only, never saved |
| Music / sound volume? | `MusicManager.music_volume` / `sfx_volume` (0–1), saved |

Rule of thumb: **scenes read and call autoloads; autoloads never call scenes.** The only
scene↔scene coupling is `change_scene_to_file` and the `SessionManager` battle-handoff fields,
which exist precisely so the overworld can pass a question to the battle scene across a scene change.

---

## 6. Signal map

| Signal | Emitter | Listeners |
|---|---|---|
| `stats_changed`, `xp_changed`, `leveled_up`, `codex_entry_added`, `campaign_gate_ready`, `pomodoro_phase_changed` | `CompanionState` | nobody since the care room was removed |
| `large_text_changed(enabled)` | `GameState` | nobody (settings applies it directly) |
| `job_status(job_id, status, progress, result)` | `Api` | `SessionManager`, `battle.gd` |
| `topics_listed`, `extraction_*`, `topic_saved`, `region_generated`, `overworld_progress_changed` | `SessionManager` | `session_list.gd`, `categorizer.gd`, `region_map.gd` |
| `mastery_changed`, `champion_defeated`, `insight_triggered` | `SessionManager` | `region_map.gd` (the rest have no listener) |

`Api.job_status` is a **shared bus**: extraction jobs, the `"topics"` listing, and the `"grade"`
result all arrive on the same signal and are disambiguated by `job_id` string. Any new async
operation must pick a unique `job_id` or it will be consumed by the wrong listener.

---

## 7. Boot sequence

1. `splash.tscn` `_ready()` — calls `MusicManager.play_loading()` (starts `loading.mp3` at 1 s and
   fades it in over 1 s), starts a threaded load of `loading.tscn`, slices `kuizmon_splash.png` into
   60 `AtlasTexture` frames and starts playback at 30 ms/frame. After 1.8 s it holds the last frame
   for 0.5 s, fades the logo to white over 0.25 s, then changes to the already-loaded
   `loading.tscn`.
2. `loading.tscn` `_ready()` — loads theme, starts a threaded load of `peek.tscn`, calls
   `MusicManager.play_loading()` (a no-op while the same track is already playing), fades its white
   `Fade` overlay out over 0.4 s, and starts tip rotation.
3. ~7.6 s tween: 0 → 96 % in 5 s, hold 0.6 s, crawl to 100 % in 2 s.
4. `loading.gd:_advance()` — fades `Fade` back to white over 0.4 s, then changes to `peek.tscn`.
5. `peek.tscn` `_ready()` — switches the BGM back to `main room.mp3`, applies the artifact look to
   Kuiz (vertex colours, ink outline, flat self-lit parts, additive glows; see
   [`ui-and-assets.md`](ui-and-assets.md) §2), then plays
   `Peek_Surprise` → looping `Idle`, and `peeked` starts `tutorial.gd`. A tap after its last line
   emits `finished`, and `home.gd` takes over.
6. `home.gd:start()` — `SaveManager.load_once()` reads the save the first time home opens in a
   session (later calls keep the in-memory state, which may be newer), then shows the bar.

**The save is read when home first opens**, not during splash/loading/tutorial. A first-time companion starts from
`CompanionState`'s own defaults (level 1, energy 80, focus 70, mood 75, first codex line).

There is no login, no token exchange, and no read of `GameState.user_id` anywhere in the codebase —
the auth layer described in Phase 1 was deliberately skipped (`loading.gd:2`).
