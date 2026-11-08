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
├── assets/               every file is listed in ui-and-assets.md §5
│   ├── data/             the tuning tables as Resources, edited in the Inspector: foods/ (FoodItem),
│   │                     costumes/ (Costume), sky_zones/ (SkyZone), seasons/ (SeasonLook)
│   ├── audio/            music/ (home_room, loading, overworld, battle, four focus_* lullabies),
│   │                     sfx/ (battle cues, sfx_charge, sfx_charged); all our own, synthesised offline
│   ├── fonts/            JosefinSans-Regular.ttf, JosefinSans-Bold.ttf
│   ├── materials/        ink_outline.tres (Kuiz's and the foes' inverted-hull outline)
│   ├── models/           kuiz.glb; map.glb + map_0.png; boy_explorer.glb, explorer_girl.glb (+ textures);
│   │                     robot_1.glb, robot_2.glb (battle foes)
│   ├── theme/            app_theme.tres (the one shared Theme)
│   └── sprites/          boot/, effects/, props/, rooms/, battle/, ui/
├── scripts/
│   ├── autoload/         our 6 script autoloads: save_manager.gd, game_state.gd, api.gd,
│   │                     companion_state.gd, session_manager.gd, music_manager.gd; and
│   │                     cloud_save.gd (the CloudSave autoload scene's script)
│   ├── audio/            synth.gd, clip_voice.gd (model sounds made in code)
│   ├── battle/           battle.gd, arena_stage.gd, broken_bot_voice.gd
│   ├── data/             food_item.gd, costume.gd, sky_zone.gd, season_look.gd (the Resource classes)
│   ├── kuiz/             kuiz_look.gd (dirt and outfit), kuiz_voice.gd: Kuiz in any scene
│   ├── overworld/        region_map.gd, world_intro.gd, player.gd, joystick.gd, season.gd,
│   │                     encounter_trigger.gd, gym_slot.gd, map_collision.gd, map_houses.gd,
│   │                     minimap.gd, explorer_picker.gd, kuiz_follower.gd
│   ├── review_session/   categorizer.gd, flashcards.gd
│   └── ui/               home.gd, session_list.gd, settings.gd, palette.gd (Palette colours)
│       ├── boot/         splash.gd, loading.gd, peek.gd, tutorial.gd
│       ├── minigames/    minigame.gd, soccer.gd, sky_jump.gd (Playroom games)
│       └── widgets/      confirm_modal.gd (ConfirmModal), stat_gauge.gd, music_toggle.gd
├── addons/GodotPlayGameServices/   the Google Play Games plugin (v3.4.0, MIT; Android .aar files and its
│                                  GDScript clients), used for cloud saves
├── scenes/
│   ├── autoload/         cloud_save (the CloudSave autoload: the plugin's SignIn, Snapshots, Players nodes)
│   ├── battle/           battle
│   ├── kuiz/             kuiz_head (dirt decals and outfit stickers on Kuiz's Head bone)
│   ├── overworld/        world_intro, region_map, encounter_trigger, house_trigger, gym_burst,
│   │                     explorer_picker; weather/ rain, leaves, snow
│   ├── review_session/   categorizer, flashcards
│   └── ui/               session_list, settings; boot/ splash, loading, peek; widgets/ confirm_modal
├── backend/              the study server: main.py (FastAPI), ai.py, tests/, evals/ (api-backend.md)
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
| 2 | `GameState` | `scripts/autoload/game_state.gd` | player name, tutorial flag, AI consent, crystals and their spends, food stock, outfit, daily study goal, large text |
| 3 | `Api` | `scripts/autoload/api.gd` | HTTP wrapper **and** the whole mock backend |
| 4 | `CompanionState` | `scripts/autoload/companion_state.gd` | care stats, XP/level, the focus timer |
| 5 | `SessionManager` | `scripts/autoload/session_manager.gd` | worlds, extraction, houses / gyms / Champion, runs and the battle handoff, mastery, flashcards |
| 6 | `MusicManager` | `scripts/autoload/music_manager.gd` | every music track (boot, home, focus lullabies, map, battle), one-shot SFX |
| 7 | `GodotPlayGameServices` | `addons/GodotPlayGameServices/scripts/autoloads/godot_play_game_services.gd` | the Play Games plugin's entry point (third-party, MIT, v3.4.0); only `CloudSave` uses it |
| 8 | `CloudSave` | `scenes/autoload/cloud_save.tscn` (`scripts/autoload/cloud_save.gd`) | the save's copy in the player's Google Play Games Saved Games; Android only ([`data-model.md`](data-model.md) §8) |

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
   │  ~7.6 s scripted fill, 0.9 s fade to white
   ▼
peek.tscn  (3D Kuiz over 2D rooms; the hub)
   │  Kuiz peeks (5.7 s), then the tutorial: intro, profile Continue, name, and a tour of the
   │  Study Room, Maintenance Bay, Data Kitchen and Playroom. A tap after the last line starts
   │  the home loop; once the tutorial is done, the scene opens straight into it, with the
   │  Kuiz reveal on the session's first opening.
   ├── ◀ / ▶ or the room sign's dropdown   walk between the four rooms
   ├── Play     ─► session_list.tscn  (Worlds hub)
   ├── Focus    the focus timer (a panel on home)
   └── gear, any room ─► settings.tscn ──► back to peek.tscn


session_list.tscn  (Worlds hub; home Play opens it)
   ├── Saved worlds: Play ─► world_intro.tscn ─► region_map.tscn · Cards ─► flashcards.tscn · Edit ─► categorizer.tscn
   │                 Reset progress / Delete (confirmed) ─► SessionManager.reset_topic_progress / delete_topic
   ├── + New World ─► categorizer.tscn (World Builder)  (editing_topic_id = topic_<unix%100000>)
   └── Back ─► peek.tscn (home)

categorizer.tscn
   └── Confirm & Play ─► confirm_topic() ─► region_generated ─► world_intro.tscn ─► region_map.tscn

region_map.tscn
   ├── Back ─► "Go home?" ─► world_intro.tscn (Kuiz goes indoors) ─► peek.tscn (home)
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
| What level / XP / stats? | `CompanionState` |
| What topics exist? | `SessionManager._topics` (private, read via `get_topics_cache()`) |
| What is being edited? | `SessionManager.pending_questions` + `editing_topic_id` |
| What gyms exist? | derived on demand from `pending_questions` (`get_gym_structure()`) |
| Which house / gym is cleared? | `SessionManager._cleared_houses` / `_cleared_gyms` / `_champion_defeated`, with `_best_stars` |
| Mastery per question? | `SessionManager._mastery` |
| Which battle am I in? | `SessionManager.battle_topic_id` / `battle_kind` / `battle_type` / `battle_house` / `battle_run` |
| Player's name? | `GameState.player_name`, set by the tutorial; saved |
| Tutorial seen / food in stock? | `GameState.tutorial_done` / `food_stock`; both saved |
| Music / sound volume? | `MusicManager.music_volume` / `sfx_volume` (0–1), saved |

Rule of thumb: **scenes read and call autoloads; autoloads never call scenes.** The only
scene↔scene coupling is `change_scene_to_file` and the `SessionManager` battle-handoff fields,
which exist precisely so the overworld can pass a question to the battle scene across a scene change.

---

## 6. Signal map

| Signal | Emitter | Listeners |
|---|---|---|
| `stats_changed` | `CompanionState` | `home.gd`, `battle.gd` |
| `xp_changed`, `pomodoro_phase_changed` | `CompanionState` | `home.gd` |
| `crystals_changed` | `GameState` | `home.gd` |
| `job_status(job_id, status, progress, result)` | `Api` | `SessionManager`, `battle.gd` |
| `topics_listed` | `SessionManager` | `session_list.gd` |
| `extraction_*`, `region_generated` | `SessionManager` | `categorizer.gd` |
| `overworld_progress_changed` | `SessionManager` | `region_map.gd` |

`Api.job_status` is a **shared bus**: extraction jobs, the `"topics"` listing, and the `"grade"`
result all arrive on the same signal and are disambiguated by `job_id` string. Any new async
operation must pick a unique `job_id` or it will be consumed by the wrong listener.

---

## 7. Boot sequence

1. `splash.tscn` `_ready()` — starts a threaded load of `loading.tscn`, slices `kuizmon_splash.png`
   into 60 `AtlasTexture` frames and starts playback at 30 ms/frame. Two frames in, it calls
   `MusicManager.play_loading()` (starts `loading.wav` at 1 s and fades it in over 2 s). After 1.8 s
   it holds the last frame for 0.5 s, fades the logo to white over 0.25 s, then changes to the
   already-loaded `loading.tscn`.
2. `loading.tscn` `_ready()` — loads theme, starts a threaded load of `peek.tscn`, calls
   `MusicManager.play_loading()` (a no-op while the same track is already playing), fades its white
   `Fade` overlay out over 0.4 s, and starts tip rotation.
3. ~7.6 s tween: 0 → 96 % in 5 s, hold 0.6 s, crawl to 100 % in 2 s.
4. `loading.gd:_advance()` — fades `Fade` back to white over 0.9 s, then changes to `peek.tscn`.
5. `peek.tscn` `_ready()` — crossfades the BGM to `home_room.wav`, applies the artifact look to
   Kuiz (vertex colours, ink outline, flat self-lit parts, additive glows; see
   [`ui-and-assets.md`](ui-and-assets.md) §2). With the tutorial done, the session's first opening runs the reveal:
   `%BootWhite` holds pure white for 0.35 s, then dissolves off a large Kuiz over 0.9 s while it
   grows slightly. After a 0.45 s rest Kuiz jumps, and at the top of the jump a teal-ringed circle opens
   from its head over `IRIS_TIME` (1 s) to show the Study Room (a shader on `Rooms/White`), and it
   lands at room size and plays `Happy`. Later openings go straight to the room. With the tutorial not
   done it plays `Peek_Surprise` → looping `Idle`, and `peeked` starts `tutorial.gd`. A tap after its
   last line emits `finished`, and `home.gd` takes over.
6. `home.gd:start()` — shows the bar and HUD; after the reveal (`peek.revealed`) the HUD drops in from
   the top and the dock rises from the bottom.

**The save is read at boot**, by a deferred `SaveManager.load_once()` from its `_ready()`. A first-time companion starts from
`CompanionState`'s own defaults (level 1, energy 80, focus 70, mood 75). Gameplay saves are
debounced to one write every 5 s and written at once on pause or close
([`data-model.md`](data-model.md) §7).

**On Android, `CloudSave` signs in to Google Play Games at boot** (silently, when the player already
uses it) and loads the cloud copy:
- On a new install it restores silently.
- When the cloud copy is newer than this phone's progress, home asks which to keep.
- Otherwise the phone's save is uploaded.

Off Android it does nothing. See [`data-model.md`](data-model.md) §8.

There is no login of our own (only the player's Google Play Games profile), no token exchange, and no read of `GameState.user_id` anywhere in the codebase —
the auth layer described in Phase 1 was deliberately skipped (`loading.gd:2`).
