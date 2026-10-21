# UI and assets

Screen inventory, shared styling, controls, and a full asset audit.

---

## 1. Theme

Single resource: `ui/app_theme.tres`, referenced by `project.godot` (`gui/theme/custom`) and re-assigned
per screen in every `_ready()`.

| Token | Value |
|---|---|
| Default font | `JosefinSans-Regular.ttf` |
| Default font size | 28 (large-text mode: 36) |
| `Button` font | `JosefinSans-Bold.ttf`, size 32 (large-text: 40) |
| `Button` font colour | `(0.93, 0.96, 1)` |
| `Button` normal style | `StyleBoxFlat` fill `(0.11, 0.15, 0.31)`, radius 16 |
| `PanelContainer` panel | `StyleBoxFlat` fill `(0.04, 0.07, 0.17, 0.85)`, radius 24 |

There is no hover/pressed/disabled style box — only `normal` — so buttons do not visually react on
press beyond the `ButtonJuice` scale tween. Several scenes override sizes and colours inline
(`theme_override_*`) instead of extending the theme.

### Color palette

Canonical palette for new UI work. These are sRGB values.

| Color | Hex | Use |
|---|---|---|
| Soft Sage | `#E8F0EA` | Main room backgrounds |
| Warm Off-White | `#F7F5EF` | Walls, furniture, surfaces |
| Muted Teal | `#4F8F89` | Technology, controls, accents |
| Dusty Blue | `#6F8FA8` | Secondary details |
| Soft Green | `#78A982` | Growth and positive feedback |
| Muted Amber | `#D6A85F` | Gold accents and rewards |
| Soft Coral | `#C97970` | Damage and warnings |
| Dusty Lavender | `#8D82A8` | Special AI details |
| Deep Slate | `#29383A` | Text and dark details |
| Slate Gray | `#687778` | Secondary text |

The shared theme and several inline scene overrides were written before this palette and still use
the older navy/cyan values. New UI uses the palette above; migrating the existing screens is tracked
in [`known-issues.md`](known-issues.md) #21.

### Large text

`GameState` can scale the theme at runtime:

```gdscript
const FONT_SIZE_STANDARD := 28     const FONT_SIZE_LARGE := 36
const BUTTON_FONT_STANDARD := 32   const BUTTON_FONT_LARGE := 40
func set_large_text(enabled)        # mutates the loaded Theme + assigns it to root
```

It is saved, applied on load, and `companion.gd` listens for `large_text_changed`. The **Large
text** checkbox in `settings.tscn` calls `set_large_text()` and saves.

---

## 2. Screens

| Scene | Root type | Script | Purpose |
|---|---|---|---|
| `scenes/ui/splash.tscn` | `Control` | `scripts/ui/splash.gd` | white intro, then loading |
| `scenes/ui/loading.tscn` | `Control` | `scripts/ui/loading.gd` | boot loading bar |
| `scenes/ui/peek.tscn` | `Node3D` | `scripts/ui/peek.gd`, `tutorial.gd`, `home.gd` | 3D Kuiz peeks, runs the tutorial, then the home loop across four rooms; the hub every other screen returns to |
| `scenes/ui/main.tscn` | `Control` | `scripts/ui/main.gd` (+ `companion.gd` on child) | care room |
| `scenes/ui/session_list.tscn` | `Control` | `scripts/ui/session_list.gd` | topic history |
| `scenes/review_session/categorizer.tscn` | `Control` | `scripts/review_session/categorizer.gd` | upload + question editor |
| `scenes/overworld/region_map.tscn` | `Node3D` | `scripts/overworld/region_map.gd` (+ `player.gd`, `joystick.gd`) | 3D island: explorer, trainers, gyms, champion |
| `scenes/battle/battle.tscn` | `Control` | `scripts/battle/battle.gd` | arena |
| `scenes/ui/settings.tscn` | `Control` | `scripts/ui/settings.gd` | music and sound volume, large text, premium + quota debug; Back returns home |
| `ui/hud_strip.tscn` | `VBoxContainer` | `scripts/ui/hud_strip.gd` | status strip (instanced) |
| `ui/pomodoro.tscn` | `VBoxContainer` | `scripts/ui/pomodoro.gd` | timer panel (instanced) |
| `scenes/companion/companion_rig.tscn` | `Node2D` | `scripts/companion/companion_rig.gd` | skeletal pet (hidden) |

### `main.tscn` — care room

```text
Main                      (main.gd)  — only calls SaveManager.load_game()
└── Room                  (companion.gd)
    ├── BgFill            ColorRect, sky blue fallback
    ├── Background        TextureRect, rooms/study_room.svg (study_room_night.svg at night)
    ├── TopBanner         TextureRect, AtlasTexture slice of ui/top_bar.svg (0, 79.5, 866, 130.4)
    ├── Table             TextureRect, ui/table.svg, pinned to bottom (−516 px height)
    ├── CompanionRig      instance of companion_rig.tscn — visible = false
    ├── TidbitBubble      Label — visible = false  (never re-shown)
    ├── XPTick            floating "+N XP" label, alpha 0
    ├── CampaignButton    90×90 flat icon, bottom-right, disabled until campaign unlock
    ├── ChargeButton      160×160 flat icon, bottom-centre — day/night toggle
    ├── HudStrip          instance of ui/hud_strip.tscn
    ├── Pomodoro          instance of ui/pomodoro.tscn — visible = false
    ├── SettingsButton    64×64 flat icon, top-left
    ├── PomodoroButton    64×64 flat icon, under settings
    └── NightVeil         ColorRect, rgba(0,0,0,0.35), visible = false
```

Note there is **no Feed / Pet / Play button** — the care loop has no trigger in this scene.

### `splash.tscn`

`Splash` → `White` (`ColorRect`, full rect) and `Logo` (`TextureRect`, 480 × 264, centred). The script
slices the 6 × 10 `kuizmon_splash.png` sheet into 60 `AtlasTexture` frames, advances one every 30 ms,
holds the last frame for 0.5 s, fades the logo to white over 0.25 s, then changes to `loading.tscn`.

`loading.tscn` is requested with `ResourceLoader.load_threaded_request()` in `_ready()`, so it loads
on a worker thread while the animation plays. `_finish()` holds the result of
`load_threaded_get()` and then calls `change_scene_to_file()`, which hits the resource cache instead
of blocking on disk.

### `loading.tscn`

```text
Loading
├── Background      TextureRect, loading.png
├── Leaves          CPUParticles2D, leaf.svg tinted Soft Green / Muted Amber
├── Logo            TextureRect, logo.png, 800 × 418 from y = −91 (wordmark ≈ 530 px wide), floats
├── Content         VBoxContainer pinned to the bottom
│   ├── Title       HBox: SparkL, LoadingLabel ("Loading...", bold 40), SparkR (flip_h)
│   ├── BarTrack    PanelContainer, 520 px wide, centred: Deep Slate fill, Warm Off-White border, radius 28
│   │   └── LoadBar ProgressBar, 36 px tall: Muted Teal fill, empty background, stripe shader
│   └── TipRow      HBox: TipIcon (tip_bulb.svg), TipLabel (bold 22, Soft Sage)
└── Fade            ColorRect, pure white: 0.4 s fade out on entry, 0.4 s fade in on exit
```

Sequence: 0 → 96 % in 5 s, 0.6 s hold, → 100 % in 2 s, fade to white, then `peek.tscn` (thread-loaded
from `_ready()`). Tips rotate every 2.5 s with a 0.25 s fade out/in.

`logo.png` carries transparent padding (its opaque area is 373 × 114 of 561 × 293), so the
`TextureRect` is wider than the screen and starts above it to put the wordmark at y ≈ 80–243.
`_bob_logo()` floats it up 12 px and back on a looping sine tween (`LOGO_BOB_TIME` = 1.6 s each way).

`TipLabel` is a single line; the longest tip measures 562 of the 624 px available, so a longer tip
needs a smaller font or `autowrap_mode`.

- **Fade** is `#FFFFFF`, not a palette colour, on purpose: it must match the white baked into
  `kuizmon_splash.png` and the peek scene's background, so both scene changes happen on identical
  white frames.
- **Stripes** are an inline `canvas_item` shader on `LoadBar`. It tints the fill with Soft Sage at
  40 % in 26 px diagonal bands that scroll right, and keeps the fill's alpha so the rounded corners
  survive. The background stylebox is empty, so the shader only ever touches the fill.
- **Leaves**: 16 particles, 10 s lifetime, prewarmed (`preprocess = 10`) so they are already falling
  when `Fade` clears. A constant-interpolation `Gradient` picks exactly Soft Green or Muted Amber
  (70 / 30), never a blend.

### `peek.tscn`

```text
Peek                Node3D (peek.gd)
├── WorldEnvironment  background = canvas (Rooms shows through); ambient + reflections from a
│                     ProceduralSky "studio"
├── Camera3D          (0, 0.25, 16.5), fov 13.6, keep_aspect = width (near-orthographic front view)
├── Key / Fill / Rim  DirectionalLight3D 0.7 / 0.36 / 0.4, the artifact's three lights × 0.8
├── Stage             Node3D the tutorial moves and scales (room size, walks, coming close)
│   ├── Shadow        PlaneMesh 2.9 × 2.1 at y −0.935, radial Deep Slate GradientTexture2D
│   └── Kuiz          instance of assets/models/kuiz.glb
├── Rooms             CanvasLayer −1, drawn behind the 3D: White (#FFFFFF), StudyRoom
│                     (rooms/study_room.svg, with Night art and a Deep Slate Veil faded in when the
│                     lights are off), MaintenanceBay, DataKitchen, Playroom, each covering
├── Tutorial          CanvasLayer (tutorial.gd)
│   └── Speech        bottom: "Kuiz" name tag over the Dialogue box (Text, Continue, NameRow with
│                     NameInput + NameOk, and a bobbing ▼ Hint)
├── Top               CanvasLayer: RoomSign, the top-centre pill naming the current room
└── Home              CanvasLayer (home.gd), hidden until the tutorial ends
    ├── Fridge        TextureButton (props/fridge.svg), Data Kitchen only; opens Shop
    ├── Bar           bottom Deep Slate bar: Prev / Next arrows and one action group per room
    ├── Ball          props/ball.svg, Playroom only
    ├── Held          the food or screwdriver being dragged
    └── Shop          the fridge: one row per food with a Buy button, and Close
```

`peek.gd` owns Kuiz and the rooms for both scripts on top: `act()`, the stage moves, `show_room()`,
`set_lights()`, `look_at_point()` / `look_ahead()`, and `head_point()` / `hits()` for drops.

`peek.gd` plays `Peek_Surprise` (5.7 s): Kuiz rises from the bottom edge, the eyes widen with an
"!", then a happy face with sparkles. `Idle` (4 s, set to loop at runtime) follows with a 0.18 s
blend as in the artifact, and `peeked` starts the tutorial.

### Tutorial (`tutorial.gd`, inside `peek.tscn`)

Kuiz introduces the game, takes a profile and a name, then tours the rooms. Text types at 40
characters a second; a tap (or `ui_accept`) finishes the typing, the next tap advances, and a line
with a prompt waits for it instead. The script is the `LINES` table in `tutorial.gd`: text, clip,
and optionally a `room` + `move` to make before the line, or a `prompt` after it. `{name}` is the
player's name.

| # | Line (start) | Clip | Before the line | After the line |
|---|---|---|---|---|
| 1 | "Hi there! Welcome to the hub!…" | `Greetings` | — (on white) | tap |
| 2 | "First things first—let's set up our shared user profile…" | `Blink` | — | **Continue** button: the stand-in for Google sign-in / register |
| 3 | "Awesome! Connection established…what name should I call you, Partner?" | `Charging` (the bolt reads as syncing) | — | **name** field + OK (1–16 characters; Enter also submits) |
| 4 | "{name}! What a cool name!…" | `Happy` | — | tap |
| 5 | "Alright, {name}, welcome to our main hub—The Study Room!…" | `State_Charging` (docked in the cradle: eyes closed, bolt, gem glowing) | **jump**: Kuiz hops, the white gives way to the Study Room at the top, and Kuiz lands at room size | tap |
| 6 | "Since we're an official team now…Follow me!" | `Celebrate` (confetti) | — | tap |
| 7 | "Welcome to The Maintenance Bay! Mind the loose gears!…" | `Surprised` | **walk** to the Maintenance Bay | tap |
| 8 | "If you ever see me squeaking or moving a bit slow…" | `State_Sick` (screws working loose) | — | tap |
| 9 | "Ooh, listen to that… Welcome to The Data Kitchen!" | `State_Hungry` (drooling, dreaming of a chip) | **walk** to the Data Kitchen | tap |
| 10 | "I don't eat regular food…Spicy Memory Chips…" | `Pet` (hearts for its favourite snack) | — | tap |
| 11 | "And last, but definitely not least… The Playroom!…" | `Happy` | **walk** to the Playroom | tap |
| 12 | "And that's the whole tour!…" | `Greetings` (sparkles) | **close**: walk back to the Study Room, then drift up to the screen and keep hovering | tap |
| 13 | "Ready to jump into our very first review session?" | `Learn_Something_New` (reads a book, then "!") | — | nothing yet: the tutorial ends here |

- **Moves** live in `peek.gd` (`jump`, `walk`, `come_close`); the dialogue box fades out while Kuiz
  moves, and taps are ignored. A walk hops Kuiz off to the right with a lean, swaps the room, and
  hops it in from the left. Rooms cross-fade over 0.35 s and the room sign updates with them.
- **Clips** are one-shots that fall back into `Idle`, except the `State_*` moods (charging, hungry,
  sick…), which `peek.gd` sets to loop and holds until the next line.
- **Props** (hearts, confetti, sparkles, the bolt, screws, the thought bubble, the book, tears) are
  blend shapes, and each clip keys only its own. Every frame, before the `AnimationPlayer` runs,
  `peek.gd` zeroes the prop shapes the current clip does not key: an outgoing clip's props fade
  during the 0.18 s blend and then stay hidden, however early a tap cuts the clip.
- **Unused clips:** `Angry`, `Confused`, `Look_Around`, `Sad`, `Wake_Up`, `State_Mid`,
  `State_Sad`, `State_Tired`.
- **The name** is kept in `GameState.player_name`, in memory only (no backend yet); it is not saved.
- **Rooms are temporary.** All four are flat placeholder SVGs in the canonical palette
  (`study_room.svg`, also the care room's background, `maintenance_bay.svg`, `data_kitchen.svg`,
  `playroom.svg`), drawn with empty space in the middle for Kuiz. The Study Room's charging arch
  and floor ring sit where Kuiz stands, so it docks in its cradle. They are
  backdrops only: nothing in them is interactive.
- **Known limit:** on a phone the on-screen keyboard can cover the name field, since the dialogue
  box sits at the bottom and nothing moves it up yet.
- **The end.** The last line waits for a tap like the others; then the dialogue fades,
  `GameState.tutorial_done` is set, Kuiz settles back to room size in the Study Room and the home
  bar fades in.

### Home (`home.gd`, inside `peek.tscn`)

The game loop after the tutorial. The bottom bar has a ◀ and ▶ arrow at its ends that walk Kuiz
to the previous or next room (Study Room → Maintenance Bay → Data Kitchen → Playroom, wrapping),
and the middle shows the current room's action:

| Room | Action | Kuiz |
|---|---|---|
| Study Room | **Charge** (`ui/charge.png`, a toggle) turns the lights off: the 3D lights and ambient drop to 30 %, the night art and a dark veil fade in, and the charge sounds play. Arrows, Play and Settings are disabled until it is pressed again | `State_Charging` (loops; its bolt and gem glow in the dark), then `Wake_Up` when the lights come back on |
| Study Room | **Play** (`ui/campaign.png`) starts a new topic (`topic_<unix%100000>`, like the topic list's Add) and opens the upload screen, `categorizer.tscn` | — |
| Study Room | **Settings** (`ui/settings.svg`) opens `settings.tscn` | — |
| Maintenance Bay | Drag the **screwdriver** from the bar and hold it over Kuiz: it twists, and after 2 s the tune-up is done and it returns to the bar | `State_Sick` (screws working loose) while it is held there, `Celebrate` when done, `Idle` if it is taken away early |
| Data Kitchen | **Food**: ‹ › pick one of six foods, then drag it onto Kuiz to eat it (one from stock); dropped anywhere else it goes back. An empty food is greyed out and cannot be picked up | `Surprised` (mouth open) when the food reaches it, then `Happy`, or `Pet` (hearts) for Spicy Memory Chips, its favourite |
| Data Kitchen | **Fridge** (in the room, left): a list of the six foods with how many you have and a **Buy** button each (+1, free until there is a currency) | — |
| Playroom | **Ball**: it rests on the floor above the bar; drag and fling it. It falls, bounces off the screen edges, the floor and Kuiz's head, and settles | Turns its head to follow the ball (and anything being dragged), `Happy` on a throw, `Surprised` when hit |

- Foods (`props/*.svg`): Data Chips (3 to start), Spicy Memory Chips (1), Cache Cookie (2), Pi Pie
  (1), Byte Burger (1), Java Juice (2). Stock is kept in `GameState.food_stock`, in memory only.
- There are no stats, rewards or currency yet, and nothing on the top of the screen except the
  room sign: those come later.
- Every screen that used to return to the old care room (`settings.tscn`, the topic list) now
  returns here, and with `GameState.tutorial_done` set the scene opens straight into the Study
  Room. The save is read the first time home opens in a session (`SaveManager.load_once()`).

**Why it needs code.** The model was authored in the "KUIZMON Pet Bot 3D – Rigged" artifact, whose
three.js page renders it with its own code. The `.glb` carries only geometry, rig, animations,
colours and `extras` hints, which Godot imports as `get_meta("extras")` on nodes and materials.
`peek.gd` ports the page's look from those hints:

| Artifact | Godot |
|---|---|
| Vertex colours on (`COLOR_0` holds the face, bezel and glow colours; `baseColorFactor` is white) | `vertex_color_use_as_albedo = true` on every surface; the importer leaves it off, and without it the face renders white |
| Inked silhouette: an inverted hull grown by node `extras.outline` (shell 0.024, ears 0.017, cups 0.018), `#29383A` | `material_overlay` per mesh: unshaded, `CULL_FRONT`, `grow_amount` = the outline width |
| `selfLit` mixes the lit colour toward the base colour (screen 0.86, gold 0.88, gem 0.9, panels 0.97, props 0.9) | `selfLit ≥ 0.85` → `SHADING_MODE_UNSHADED`; the cups (0.45) stay lit |
| `blend: additive` on halos and the visor glint | `BLEND_MODE_ADD` |
| Studio environment: gradient sphere + soft boxes, hemisphere light 0.62 | `ProceduralSkyMaterial` gradient as ambient (0.9) and reflection source; no soft boxes |
| Key 0.85, fill 0.45, rim 0.5, ACES tonemap, exposure 0.8 | Same directions and colours at × 0.8 energy, **linear** tonemap |
| Peek re-anchored to the visible bottom edge, only while the peek clip plays | `_process` moves `Kuiz` by `(1.828 − half_height) × peek`, where `peek = clamp(0.9 − Head.y, 0, 1)` while `Peek_Surprise` is current, else 0 |
| Contact shadow shrinks as the head lifts, hidden while peeking | Same formula on `Shadow` scale and alpha |
| Smooth silhouette edges in the browser | `rendering/anti_aliasing/quality/msaa_3d` = 4× in `project.godot`; without it the ink outline stair-steps |

Not ported: the `rim` edge/underside tint and the `env` per-material reflection strength (both
subtle), the soft-box reflections, and the page's off-white radial background.

- The 3D draws over the `Rooms` canvas layer (`background_mode` = canvas). Its bottom child is a
  `#FFFFFF` `White` rect, so the cut from the loading screen's `Fade` is invisible; the tonemap stays
  linear so that white is not greyed (ACES would). Light energies are scaled × 0.8 to stand in for the
  artifact's exposure.
- The handoff into this scene measured 9–33 ms on desktop while materials compile; it lands on white.

### `session_list.tscn`

`Background` (`ColorRect`), `Title`, `EmptyLabel`, `Scroll` → `ListBox`, `AddButton`, `BackButton`.
Rows are built as `Button`s with `alignment = LEFT` and text `  <name>  ·  <N> Qs`.

### `categorizer.tscn`

Vertical stack: `Title`, `QuotaLabel`, `TopicRow` (label + `TopicName` `LineEdit`), `UploadRow`
(label + `FileButton`), `PasteLabel`, `PasteArea` (`TextEdit`), `SanityLabel`, `StudyButton`,
`StatusLabel`, `LoadingBar`, `QuestionsHeader`, `Scroll` → `QuestionsBox` (rows built in code),
`AddQuestionButton`, `PlayButton`, `BackButton`, plus `FileDialog` and `QuotaDialog`.

`FileDialog` uses `file_mode = 0` (open file) and `access = 2` (filesystem), with **no filters** —
any file type can be selected. Only the first 4000 characters of a text file are shown in the paste
box, although all bytes are kept for the upload call (`categorizer.gd:89-96`).

### `region_map.tscn`

`Node2D` root: `Background` (`ColorRect`, 2720×3400 world rect), `Route` (`Line2D`), `Trainers`,
`Gyms`, `Player` (`CharacterBody2D` + `CollisionShape2D` r24 + `Sprite2D` + `Camera2D`), and a
`HUD` `CanvasLayer` with `TopBar` (back / progress / badges), `HintLabel`, and the shared
`EncounterPanel`. Trainers, gyms and the champion are instantiated at runtime.

### `battle.tscn`

`Battle` (`Control`) → `Camera2D`, `Background`, `Margin` → `List`: `TopBar` (flee, title),
`QuotaLabel`, `EnemyCard` (sprite, name, HP), `PlayerCard` (sprite, name, HP), `QuestionCard`
(type, text), `AnswerInput` (`TextEdit`), `SubmitButton`, `JudgingLabel`, `ResultLabel`,
`ResultPanel` (title, XP label, retry/continue), plus `QuotaDialog`.

Both sprite slots (`EnemySprite`, `PlayerSprite`) reference missing `bot_lv*.png` textures.

### `hud_strip.tscn`

`VBoxContainer` with `StatusRow` (`LevelLabel`, `EnergyCell`, `FocusCell`, `MoodCell`, `PomoBadge`)
and `XPRow` (`XPLabel`, `XPBar`). The three stat bars are *vertical* (`fill_mode = 3`) 24×44
capsules with nub caps and two segment lines, styled per-stat (energy teal, focus amber, mood red).
`PomoBadge` is hidden unless a timer is running.

### `pomodoro.tscn`

`ModeLabel`, `TimerLabel`, `StartButton`, `SkipButton` (hidden unless a phase is active). Purely a
renderer — all logic is in `CompanionState`.

### `companion_rig.tscn`

`Node2D` → `Mesh` → `Skeleton2D` (`Root` → `Body` → `EarL`, `EarR`, `Antenna`), `Art` (`Polygon2D`),
`SadArt` (`Polygon2D`, alpha 0), `Face` (`AnimatedSprite2D`, hidden until a blink). Weights are
painted at runtime; see `systems/companion-care.md` §7.

---

## 3. Interaction conventions

- **Buttons:** flat icon buttons (`flat = true`, `icon_alignment = CENTER`, `expand_icon = true`)
  for room actions, full-width text buttons for flow actions.
- **`ButtonJuice.wire(button)`** (`scripts/ui/button_juice.gd`) adds hover 1.06× / press 0.96× scale
  via a tween stored in the button's metadata; disabled buttons never pop. Currently wired only to
  the four care-room icon buttons.
- **Input:** movement uses the built-in `ui_left` / `ui_right` / `ui_up` / `ui_down` actions, so
  arrows **and** WASD work with no custom `InputMap`. Everything else is mouse/touch on `Control`s.
- **No on-screen touch controls** — the overworld is currently desktop/keyboard-only in practice.
- **No pause menu, no transition animation, no loading indicator between scenes.**

---

## 4. Audio

`MusicManager` (autoload) owns two `AudioStreamPlayer`s:

- `MainRoomPlayer` — `main room.mp3`, looping (set on the `AudioStreamMP3` resource), `-6 dB`,
  started on `_ready()` and kept alive across scene changes.
- `SfxPlayer` — single voice, so overlapping SFX cut each other off; `play_sfx_chain()` serialises a
  list with `await` and cancels itself if another chain starts (guarded by `_sfx_chain_id`).

Only the day/night toggle plays sound (`charge.mp3`, then `charged.mp3` when going dark). Battles,
level-ups, taps and gym clears are silent.

---

## 5. Asset inventory

### Used

| Asset | Used by |
|---|---|
| `audio/main room.mp3` | `music_manager.gd` (looping BGM) |
| `audio/charge.mp3`, `audio/charged.mp3` | `companion.gd` day/night toggle; home's Charge button |
| `fonts/JosefinSans-Regular.ttf` | theme default font |
| `fonts/JosefinSans-Bold.ttf` | theme button font; `loading.tscn` title and tip labels |
| `sprites/loading.png` | `loading.tscn` background |
| `sprites/logo.png` | `loading.tscn` top-centre wordmark |
| `sprites/leaf.svg` | `loading.tscn` falling leaves, overworld autumn leaves (white so particle colour tints it) |
| `sprites/ui/loading_spark.svg` | `loading.tscn` sparks either side of "Loading..." |
| `sprites/ui/tip_bulb.svg` | `loading.tscn` tip icon |
| `models/map.glb`, `models/map_0.png` | `region_map.tscn` island (the PNG is its road texture) |
| `models/boy_explorer.glb`, `boy_explorer_basecolor_v2.jpg`, `boy_explorer_normal_v2.jpg` | `region_map.tscn` explorer (`Idle`, `Walk`, `Run` used) |
| `models/kuiz.glb` | `peek.tscn` 3D Kuiz head; 21 clips (13 one-shots, `Celebrate`, `Learn_Something_New`, six `State_*` moods), face and props on blend shapes |
| `sprites/kuizmon_splash.png` | `splash.gd` 60-frame intro sheet (6 × 10 cells, 480 × 264) |
| `sprites/rooms/study_room.svg` | care-room, settings and categorizer background (day); the tutorial's Study Room (temporary placeholder) |
| `sprites/rooms/study_room_night.svg` | care-room background at night; home's lights-off Study Room (temporary placeholder) |
| `sprites/rooms/maintenance_bay.svg` | tutorial Maintenance Bay (temporary placeholder) |
| `sprites/rooms/data_kitchen.svg` | tutorial and home Data Kitchen; left floor kept clear for the fridge (temporary placeholder) |
| `sprites/rooms/playroom.svg` | tutorial and home Playroom; no painted ball, the real one is flung (temporary placeholder) |
| `sprites/ui/campaign.png` | CampaignButton icon; home's Play button |
| `sprites/ui/charge.png` | ChargeButton icon; home's Charge button |
| `sprites/ui/pomodoro.svg` | PomodoroButton icon |
| `sprites/ui/settings.svg` | SettingsButton icon; home's Settings button |
| `sprites/ui/arrow.svg` | home bar's room and food arrows (flipped for ◀) |
| `sprites/props/data_chips.svg`, `spicy_chips.svg`, `cache_cookie.svg`, `pi_pie.svg`, `byte_burger.svg`, `java_juice.svg` | home's six foods (temporary placeholders) |
| `sprites/props/fridge.svg` | home's Data Kitchen fridge (temporary placeholder) |
| `sprites/props/ball.svg` | home's Playroom ball (temporary placeholder) |
| `sprites/props/screwdriver.svg` | home's Maintenance Bay screwdriver (temporary placeholder) |
| `sprites/ui/table.svg` | care-room table |
| `sprites/ui/top_bar.svg` | HUD banner (atlas slice) |
| `sprites/companion/idle_companion.svg` | rig body + blink idle frames |
| `sprites/companion/blink_companion.svg` | rig blink frame |
| `sprites/companion/sad_companion.svg` | rig `SadArt` layer |
| `icon.svg` | project icon |

### Source / not imported

| Asset | Note |
|---|---|
| `sprites/kuizmon_loading.gif` | source for `kuizmon_splash.png`; Godot has no GIF importer |

### Present but unused

| Asset | Note |
|---|---|
| `audio/hmm.mp3` | no call site |
| `sprites/loading_logo.png` | full cat logo; the loading screen uses the `logo.png` wordmark |
| `sprites/companion/happy_companion.svg` | rig only uses idle/blink/sad |
| `sprites/companion/charge_companion.svg` | unused |
| `sprites/companion/complete_companion.svg` | unused |

### Referenced but **missing** (breaks scenes)

| Asset | Referenced by | Effect |
|---|---|---|
| `sprites/bot_lv1.png` | `battle.tscn:77` | parse error — battle scene will not load |
| `sprites/bot_lv5.png` | `battle.tscn:107`, `region_map.tscn:5`, `player.gd:12` | parse error — overworld scene will not load |
| `sprites/bot_lv1..5.png` | `companion.gd:80` | runtime warning "no bot textures found", pet invisible |

Adding these five files restores the pet, the overworld and the battle arena. Until then the
campaign flow stops at the first scene change after "Confirm & Play".

---

## 6. Layout notes

- Art is authored for 720 × 1280 and positioned with absolute offsets inside anchored containers;
  anything wider than 9:16 will reflow but not re-layout the care-room props.
- Several nodes still use `layout_mode = 0` with raw offsets (legacy from the first room), so they
  ignore container sizing.
- `unique_id` attributes appear on nodes in the newer scenes (4.7 scene format); they are editor
  metadata, not something to reproduce by hand.
