# UI and assets

Screen inventory, shared styling, controls, and a full asset audit.

---

## 1. Theme

Single resource: `assets/theme/app_theme.tres`, referenced by `project.godot` (`gui/theme/custom`) and re-assigned
per screen in every `_ready()`.

| Token | Value |
|---|---|
| Default font | `JosefinSans-Regular.ttf` |
| Default font size | 28 (large-text mode: 36) |
| `Button` font | `JosefinSans-Bold.ttf`, size 32 (large-text: 40) |
| `Button` font colour | Warm Off-White `#F7F5EF` (pressed: Deep Slate) |
| `Button` styles | `StyleBoxFlat` radius 20, 3 px Warm Off-White border; normal Muted Teal, hover lighter teal, pressed Muted Amber, disabled Slate Gray |
| `PanelContainer` panel | `StyleBoxFlat` fill Deep Slate at 0.88 alpha, 3 px Warm Off-White border, radius 24 |

Some scenes still override sizes and colours inline (`theme_override_*`) instead of extending the theme.

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

The shared theme and every screen use this palette. New UI picks a role from it.

### Large text

`GameState` can scale the theme at runtime:

```gdscript
const FONT_SIZE_STANDARD := 28     const FONT_SIZE_LARGE := 36
const BUTTON_FONT_STANDARD := 32   const BUTTON_FONT_LARGE := 40
func set_large_text(enabled)        # mutates the loaded Theme + assigns it to root
```

It is saved and applied on load. The **Large
text** checkbox in `settings.tscn` calls `set_large_text()` and saves.

---

## 2. Screens

| Scene | Root type | Script | Purpose |
|---|---|---|---|
| `scenes/ui/boot/splash.tscn` | `Control` | `scripts/ui/boot/splash.gd` | white intro, then loading |
| `scenes/ui/boot/loading.tscn` | `Control` | `scripts/ui/boot/loading.gd` | boot loading bar |
| `scenes/ui/boot/peek.tscn` | `Node3D` | `scripts/ui/boot/peek.gd`, `scripts/ui/boot/tutorial.gd`, `scripts/ui/home.gd` | 3D Kuiz peeks, runs the tutorial, then the home loop across four rooms; the hub every other screen returns to |
| `scenes/ui/session_list.tscn` | `Control` | `scripts/ui/session_list.gd` | Worlds hub: saved worlds (play, cards, edit, reset, delete) and New World |
| `scenes/review_session/categorizer.tscn` | `Control` | `scripts/review_session/categorizer.gd` | upload + question editor |
| `scenes/overworld/region_map.tscn` | `Node3D` | `scripts/overworld/region_map.gd` (+ `player.gd`, `joystick.gd`) | 3D island: explorer, trainers, gyms, champion |
| `scenes/battle/battle.tscn` | `Control` | `scripts/battle/battle.gd`, `scripts/battle/arena_stage.gd` | 3D arena behind the battle HUD: intro, strikes, ten SFX cues |
| `scenes/review_session/flashcards.tscn` | `Control` | `scripts/review_session/flashcards.gd` | Flashcard Sanctuary: untimed card review |
| `scenes/ui/settings.tscn` | `Control` | `scripts/ui/settings.gd` | one card, "Sound & display" (music, sounds, large text); Back returns home. The "AI plan" card (quota, premium, debug reset) was removed |


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
├── Logo            TextureRect, the animated logo, 638 × 207 (1:1) from y = 60, floats
├── Content         VBoxContainer pinned to the bottom
│   ├── Title       HBox: SparkL, LoadingLabel ("Loading...", bold 40), SparkR (flip_h)
│   ├── BarTrack    PanelContainer, 520 px wide, centred: Deep Slate fill, Warm Off-White border, radius 28
│   │   └── LoadBar ProgressBar, 36 px tall: Muted Teal fill, empty background, stripe shader
│   └── TipRow      HBox: TipIcon (tip_bulb.svg), TipLabel (bold 22, Soft Sage)
└── Fade            ColorRect, pure white: 0.4 s fade out on entry, 0.4 s fade in on exit
```

Sequence: 0 → 96 % in 5 s, 0.6 s hold, → 100 % in 2 s, fade to white, then `peek.tscn` (thread-loaded
from `_ready()`). Tips rotate every 2.5 s with a 0.25 s fade out/in.

The logo is `loading_screen_logo.gif` (60 frames, 25 fps, a shine sweeping across the wordmark),
which Godot cannot load. Its frames are decoded offline into `loading_screen_logo.png`: the white
reachable from each frame's edge is keyed out (the white letters inside the outline stay), the
anti-aliased band where the teal rim met that white is un-blended so no white halo shows over the
sky, and the frames are cropped to the wordmark (638 × 207) and packed six per row (3828 × 2070,
imported lossless, no mipmaps). `loading.gd` slices it into `AtlasTexture`s and loops them at
0.04 s a frame, drawn 1:1 on the 720-wide screen.
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
│                     lights are off), MaintenanceBay, DataKitchen, Playroom, each covering;
│                     the minigame backdrops SoccerField and SkyJump (Sky + JumpWorld: Ground and
│                     the platforms, which scroll)
├── Tutorial          CanvasLayer (tutorial.gd)
│   └── Speech        bottom: "Kuiz" name tag over the Dialogue box (Text, Continue, NameRow with
│                     NameInput + NameOk, and a bobbing ▼ Hint)
├── Look              Node (kuiz_look.gd): dirt and the outfit, stickers on Kuiz's Head bone
├── Voice             Node (kuiz_voice.gd): Kuiz's sounds, made in code, on clip cues and moves
├── Top               CanvasLayer: RoomSign, the room-name pill under the HUD row
└── Home              CanvasLayer (home.gd), hidden until the tutorial ends
    ├── Level         top-left pill: teal level badge, "LEVEL" and an amber XP bar
    ├── Stats         top-centre: four stat gauges (stat_gauge.gd): Hunger, Energy, Mood, Health
    ├── Crystals      top-right pill: crystal icon and the count
    ├── RoomPrev/Next outlined arrows either side of the room sign; walk to the previous / next room
    ├── Table         ui/dock_table.svg across the bottom: the dock the items stand on
    ├── Bar           the dock row over the table (no panel of its own): one action group per
    │                 room; every item is a bare icon (no circle) with an Off-White caption on the cloth
    ├── Ball          props/ball.svg, Playroom only
    ├── Shop          the fridge: one row per food with a Buy button, and Close
    ├── Picker        the Games card: Kuiz Keeper, Sky Jump, Close
    ├── CheckPanel    the tablet's check-up: a Deep Slate bezel around a teal screen (rows built in
    │                 code), New battery, Close
    ├── Wardrobe      the closet: Head / Face / Body tabs and a grid of costumes (both built in code), Close
    ├── Toast         a pill above the dock for short hints ("Kuiz is sleeping…")
    └── Held          the food or screwdriver being dragged
├── Soccer            CanvasLayer (minigames/soccer.gd): score pill, back arrow, SoccerBall
└── SkyJumpHud        CanvasLayer (minigames/sky_jump.gd): height pill, back arrow
```

The forehead gem is skinned to the `Antenna_1` bone, which every clip swings and scales, so it
tipped into the head. Kuiz has no visible antenna, so `peek.gd` disables the `Antenna_*` tracks at
load and the gem stays on the forehead.

`peek.gd` owns Kuiz and the rooms for both scripts on top: `act()`, the stage moves, `show_room()`,
`set_lights()`, `look_at_point()` / `look_ahead()`, and `head_point()` / `hits()` for drops. A
one-shot clip falls back into `rest`, the resting clip home sets with `set_rest()`; `place()` puts
Kuiz's head on a screen point for the minigames and `home_pose()` brings it back.

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
- **Unused clips:** `Angry`, `Confused`, `Look_Around`, `Sad`, `State_Mid`,
  `State_Sad`, `State_Tired`.
- **The name** is kept in `GameState.player_name`, in memory only (no backend yet); it is not saved.
- **Rooms are temporary.** All four are flat placeholder SVGs in the canonical palette
  (`study_room.svg`, `maintenance_bay.svg`, `data_kitchen.svg`,
  `playroom.svg`), drawn with empty space in the middle for Kuiz. The Study Room's charging arch
  and floor ring sit where Kuiz stands, so it docks in its cradle; its desk stands against the
  wall behind the arch, and its bookshelf's books fill each shelf evenly. The Maintenance Bay's
  pegboard holds a screwdriver, an open-end wrench and a hammer. Each room has a wallpaper repeat,
  trim and small props drawn in the same flat style, with soft highlights and contact shadows:
  - **Study Room:** pinstripe wallpaper, panelled wainscot, curtains and a sill plant at the
    window, a wall clock and framed certificate, banded book spines, a rug under the cradle, a
    floor plant, and a desk drawer and steaming mug. The night art matches, with a darker rug and
    curtains.
  - **Maintenance Bay:** riveted wall plates, pegboard hooks and a tape roll, a warning sign, a
    pipe with a valve wheel, a parts crate, a toolbox latch, an oil drip and a floor drain.
  - **Data Kitchen:** sprig wallpaper, faint floor checks, panelled cabinets, a wall clock,
    hanging utensils, a steaming pot on the data oven and a striped mat.
  - **Playroom:** star wallpaper above a chair rail, a framed crayon drawing of Kuiz, a fringed
    rug, a toy box with a plush bunny, and dice blocks.

  They are backdrops only: nothing in them is interactive. The generator
  (`rooms.py`) is kept outside the repo.
- **Known limit:** on a phone the on-screen keyboard can cover the name field, since the dialogue
  box sits at the bottom and nothing moves it up yet.
- **The end.** The last line waits for a tap like the others; then the dialogue fades,
  `GameState.tutorial_done` is set, Kuiz settles back to room size in the Study Room and the home
  bar fades in.

### Home (`home.gd`, inside `peek.tscn`)

The game loop after the tutorial. A ◀ and ▶ arrow either side of the room sign at the top walk
Kuiz to the previous or next room (Study Room → Maintenance Bay → Data Kitchen → Playroom,
wrapping), Pou-style; `home.gd` keeps them hugging the sign, whose width follows the room name. The
dock at the bottom is a table (`ui/dock_table.svg`: an amber wooden top on two legs, a Muted Teal
cloth with off-white stitching over its front edge). The current room's items stand on the tabletop,
each a bare icon with its caption on the cloth (Charge, Study, Settings · Check-up, Tighten, Clean ·
Fridge and the food picker · Closet, Ball, Games, the ball in the middle). While Kuiz walks to
another room only the arrows lock; the room's items keep their look and ignore taps until it
arrives:

| Room | Action | Kuiz |
|---|---|---|
| Study Room | **Charge** (`ui/icon_charge.svg`, a toggle; the bolt pulses while on) turns the lights off: the 3D lights and ambient drop to 30 %, the night art and a dark veil fade in, and the charge sounds play. Energy refills 6 / s while it is on. Arrows, Play and Settings are disabled until it is pressed again | `State_Charging` (loops; its bolt and gem glow in the dark), then `Wake_Up` when the lights come back on |
| Study Room | **Play** (`ui/icon_upload.svg`) opens the Worlds hub, `session_list.tscn` | — |
| Study Room | **Settings** (`ui/icon_settings.svg`) opens `settings.tscn` | — |
| Maintenance Bay | **Check-up** (`props/tablet.svg`) opens the tablet: Battery health (`battery_health`, the battery's capacity like a phone's, not its charge; the Energy gauge shows the charge), Frame (health), Clean (100 − dirt) and Fuel (hunger) bars, off-white when fine, amber below half, coral below a quarter, and a hint naming the most urgent fix. **New battery** (30 crystals) puts battery health back to 100 % (`replace_battery()`); without enough crystals a toast says to win minigames, and at 100 % it is greyed out | `Celebrate` on a new battery |
| Maintenance Bay | **Clean** (`props/towel.svg`): drag the towel over Kuiz and rub; every pixel scrubbed takes 0.06 dirt off, and getting Kuiz spotless in one scrub is `care("clean")` (mood +5, XP) and a "Squeaky clean!" toast | `Pet` while it is rubbed, `Celebrate` when spotless |
| Maintenance Bay | **Tighten**: drag the **screwdriver** from the bar and hold it over Kuiz: it twists, and after 2 s the tune-up is done (`care("fix")`: health +25) and it returns to the bar | `State_Sick` (screws working loose) while it is held there, `Celebrate` when done, `Idle` if it is taken away early |
| Data Kitchen | **Food**: ‹ › step through the foods in stock (one with none left is skipped; it is only in the fridge), then drag it onto Kuiz to eat it (one from stock; `care("feed")`: hunger +12, and a little dirt); dropped anywhere else it goes back. With nothing in stock the slot reads "Empty! Check the fridge" | `Surprised` (mouth open) when the food reaches it, then `Happy`, or `Pet` (hearts) for Spicy Memory Chips, its favourite |
| Data Kitchen | **Fridge** (`props/fridge.svg`, the first item in the kitchen bar): a list of the six foods with how many you have and a **Buy** button each (+1, still free) | — |
| Playroom | **Ball**: it waits in the dock; drag it out and fling it (a fast throw is `care("play")`: mood +8, energy −2). It falls, bounces off the screen edges, the floor above the dock and Kuiz's head, and once it settles it rolls back into its dock slot | Turns its head to follow the ball (and anything being dragged), `Happy` on a throw, `Surprised` when hit |
| Playroom | **Closet** (`props/closet.svg`) opens tabs for **Head** (Party hat, Crown, Beanie, Bow, Flower), **Face** (Glasses, Shades, Hero mask) and **Body** (Bow tie, Scarf, Medal), each with None; Kuiz wears one per tab at once, so a hat, glasses and a scarf go together. A tap wears it at once and saves it (`GameState.outfit`) | `Happy` |
| Playroom | **Games** (`ui/icon_games.svg`) opens the Minigames card: Kuiz Keeper or Sky Jump (below) | — |
| Anywhere | **Pet**: hold a finger on Kuiz for 0.35 s or stroke it 70 px; it plays `Pet` (hearts, purr) and keeps playing it while the hand stays; `care("pet")` (mood +8) counts at most every 3 s | `Pet`, looking at the hand |

- Foods (`props/*.svg`): Data Chips (3 to start), Spicy Memory Chips (1), Cache Cookie (2), Pi Pie
  (1), Byte Burger (1), Java Juice (2). Stock is kept in `GameState.food_stock`, in memory only.
### Model sounds (`scripts/audio/`)

The models come from artifact pages that make every sound in JavaScript with WebAudio when it
plays; the `.glb` files carry no audio (glTF has none). The game does the same in GDScript, so
there are no sound files for them:

- **`synth.gd`** ports the building blocks: oscillator sweeps with vibrato, the artifacts'
  exponential envelopes and ramps, RBJ biquad filters and filtered noise, mixed into an
  `AudioStreamWAV` (22 050 Hz mono).
- **`clip_voice.gd`** is the shared voice node. Each clip has a cue table (seconds, sound,
  volume); every frame, the cues the playhead passed since the last frame play, and a looping mood
  fires them again every loop. Sounds are built once per run on a worker thread (about 1 s for
  Kuiz's 40) and shared by every instance; one needed before the worker reaches it is built on the
  spot. Eight players round-robin, each at its cue volume × the Sounds slider. The owner hands it
  the model's AnimationPlayer (it lives inside the glb).
- **Kuiz** (`ui/boot/kuiz_voice.gd`, from the "KUIZMON Pet Bot 3D – Rigged" artifact): its 40
  sounds and `CUES` table, ×2 gain baked in (the artifact leaned on a compressor and had no music
  under it). Each tutorial line's clip carries its sounds: the peek's eep, ding and hello,
  `Greetings`' jump and twinkles, `Charging`'s power-up, `State_Charging`'s hum, `Celebrate`'s
  whee and confetti, `State_Sick`'s wobble and glitch, `State_Hungry`'s rumble, `Pet`'s purr,
  `Learn_Something_New`'s page and ding. `peek.gd` adds move sounds: a hop on each hop of a walk,
  jump and land for the tutorial's jump, whee as Kuiz comes close.
- **Broken Bot** (`battle/broken_bot_voice.gd`, `robot_1.glb`, from the "Broken Bot" artifact):
  `Attack` plays the rising charge at 0 s and the distorted sonic blast at 0.5 s (while its
  speaker is out), `Defeat` the power-down with crackles. The artifact's compressor evens the three
  out, so each is normalised to the same peak. `ArenaStage.FOE_VOICES` attaches it to a foe whose
  glb has a `BrokenBot` root node.
- Kuiz has no voice in battle, and `robot_2.glb` has no sounds (no artifact for it yet).

### Home HUD

The top row fades in with the bar. Every piece uses the palette, a Deep Slate 3 px outline and a
soft drop shadow, like the props.

- **Level** (top left): an Off-White pill with a teal badge holding the level number, "LEVEL" in
  Slate Gray and an amber bar for the XP between this level and the next (levels never cap). It
  follows `CompanionState.xp_changed`. Tapping it shows a card below it (`LevelInfo`, drawn over
  the room arrow) with the numbers: "Level 6", "2 / 45 XP" into this level and "43 XP to Level
  7"; it fades after 3 s or on a second tap.
- **Stats** (top centre): four round gauges (`scripts/ui/widgets/stat_gauge.gd`): an icon on an
  Off-White disc, ringed by an arc that fills clockwise from the top. **Hunger** (Data Chips,
  amber), **Energy** (the charge bolt, teal), **Mood** (`ui/stat_mood.svg`, lavender), **Health**
  (`ui/stat_health.svg`, coral). Below 25 % the ring turns coral and pulses. They follow
  `CompanionState.stats_changed`. Tapping one shows a card below it (`StatInfo`, like the level
  card): its name, its value out of 100 (live) and where to raise it ("Charge Kuiz in the Study
  Room"); one card shows at a time, and it fades after 3 s or on a second tap; stats and their sources are in
  [`companion-care.md`](systems/companion-care.md) §1.
- **Crystals** (top right): the currency, `GameState.crystals`, with the forehead gem from the
  logo (`ui/crystal.svg`), saved (v8). Minigame rounds earn it (Kuiz Keeper 1 per goal, Sky Jump
  1 per 50 m) and a new battery spends it (30); the fridge is still free.

### Kuiz's look (`kuiz_look.gd`)

Everything hangs off a `BoneAttachment3D` on Kuiz's `Head` bone, so it follows every clip and
turn. Positions are in Head-bone space: the white shell's forehead band is y 0.62–1.05,
the dark screen covers the face below it, the ears rise to y 1.45 behind z 0.26, and the shell's
bottom edge is at y −0.9 (Kuiz is all head; body items hang from that edge).

- **Dirt** (`CompanionState.dirt`, 0–100): builds up at 0.06 / s, plus a little with each meal
  (+3), fast throw (+1.5) and minigame round (+4). Six `Decal`s (three mud/grime spots, two
  scratches, one more spot) project onto the shell itself, so they hug its curve from every angle:
  each sits on a rest-pose vertex of `Head_Shell` (or `EarMesh_R`) with its box (0.5 deep) along
  that vertex's normal. They sit on the forehead, the sides, the lower edge and the right ear; each fades in over
  10 points once dirt passes its threshold (12, 28, 42, 56, 70, 84), so Kuiz gets grubbier
  gradually. The towel scrubs them off; the tablet's Clean bar shows it.
- **Outfit** (`GameState.outfit`, saved): one costume per closet slot (`SLOTS`: head, face, body),
  each its own sticker (`Sprite3D`, unshaded). `COSTUMES` holds each one's name, art, centre, width, tilt and slot; hats
  sit between the ears, the bow and flower beside an ear, the face items over the eyes, and the bow
  tie, scarf and medal along the bottom edge.

### Kuiz's moods

Twice a second home checks the stats in this order and rests Kuiz in the first low one's mood
(below 25 %, where its gauge turns coral): health → `State_Sick`, hunger → `State_Hungry`, energy
→ `State_Tired` (dozing, in the Study Room only), mood → `State_Sad`; otherwise `Idle`. Every one-shot (eating, a tune-up, a throw)
falls back into that mood, and a mood that is playing switches when the stats change. A clip asked
for on its own, such as `State_Charging` while charging, plays on undisturbed. During a minigame
Kuiz rests in `Idle`.

**Kuiz only sleeps in the Study Room.** A tired Kuiz (energy below 25 %) dozes (`State_Tired`) only
in the Study Room, by its charger; in any other room it stays awake and shows the next low mood, or
`Idle`, and dozes once it is walked back. While Kuiz dozes or charges, the room arrows dim.
Charging disables them; pressing one while it dozes shows "Shh… Kuiz is sleeping. Tap Kuiz to wake
it up." Tapping a dozing Kuiz plays `Wake_Up` and keeps it awake for 20 s, after which it dozes
again if its energy is still low.

### Minigames (`scripts/ui/minigames/`)

**Games** in the Playroom opens a card with two games. A game takes the whole screen: the home HUD,
dock and room sign hide, its backdrop (under `Rooms`, behind Kuiz) fades in, and the 3D Kuiz is
moved on screen with `peek.place()`. The ◀ arrow at the top left leaves; each finished round pops
up the score and the crystals it earned with **Play again** / **Back** (`ConfirmModal`) and counts
as play care (`care("play")`: mood +8, energy −2, XP). Best scores last for the session only. `minigame.gd` is the shared base.

- **Kuiz Keeper** (`soccer.gd`, Pou-style penalty shots): the ball sits on the spot; swipe it up
  at the goal. The swipe's direction aims and its speed lifts the shot; the fastest sail over the
  bar. Kuiz keeps goal: it sways while you aim, then dives toward where the ball will cross after a
  short reaction, so shots near it are saved and corners score. Ten shots a round; each goal makes
  Kuiz a little quicker. Kuiz looks at the ball, `Happy` on a save or miss, `Sad` on a goal. The
  ball flies at a steady speed in depth, so on screen it slows and shrinks into the distance with a
  soft shadow on the grass; each new ball rolls up onto the spot. A press near the ball picks it
  up, the swipe speed is read from its last 0.08 s, and a long flick shoots before the finger
  lifts. Kuiz steers with capped acceleration, easing into and out of each dive and leaning into
  its motion; a save punches the ball back to the grass, a goal settles into the net, a miss sails
  on.
- **Sky Jump** (`sky_jump.gd`, like Pou's): Kuiz bounces by itself from the ground up the
  platforms. Hold or drag left and right (or use the arrow keys) to steer; leaving one side brings
  it in from the other. The view climbs with Kuiz, platform gaps widen with height (always under a
  jump's reach), and falling off the bottom ends the round with the height in metres. Higher up
  the sky mixes in: **trampolines** (from 5 m) on some platforms, which launch Kuiz about three
  times as high (`boing`, `Happy`); **timed platforms** (cracked stone with a clock, from 15 m),
  which shake for 0.9 s once Kuiz lands on them, then drop; **moving platforms** (from 30 m), which
  slide between the edges; and **rockets** (from 40 m), floating pickups that carry Kuiz straight
  up for 1.7 s (`powerup`, `Celebrate`). The climb passes through zones: Sky, then **Space** at
  300 m, **Galaxy** at 900 m and **Deep Space** at 1800 m. Each new zone's backdrop fades in, its
  name flashes on the height pill, and new platforms take its look (metal, crystal, asteroid); from
  Space up a star layer scrolls slower than the world. It gets harder over the first 2000 m:
  platforms narrow from 180 to 120 px, gaps widen toward the 330 px cap (always within a jump),
  moving platforms become more common and faster, timed platforms drop sooner (0.9 → 0.5 s), and
  rockets get a little more common. From Space up, **meteors** cross the screen diagonally (one
  every 3.2 s, down to 1.5 s); a hit knocks Kuiz down (`Surprised`) instead of ending the run, and
  a rocket smashes them. The zone backdrops and star layers are built in code inside
  `Rooms/SkyJump`.
- Art (temporary placeholders): `rooms/soccer_field.svg`, `rooms/sky_jump.svg`,
  `props/soccer_ball.svg`, `props/platform.svg`, `props/platform_timed.svg`,
  `props/trampoline.svg`, `props/rocket.svg`, `props/ground.svg`, `ui/game_soccer.svg`,
  `ui/game_jump.svg`; the Sky Jump zones `rooms/sky_space.svg`, `sky_galaxy.svg`, `sky_deep.svg`,
  `props/platform_space.svg`, `platform_galaxy.svg`, `platform_deep.svg`, `props/stars.svg`,
  `props/meteor.svg`.
- Every screen that used to return to the old care room (now deleted) (`settings.tscn`, the topic list) now
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

### `session_list.tscn` — Worlds hub

A world is a topic. Same look as `settings.tscn`: the Study Room art, a Deep Slate veil, themed buttons.
Every menu screen (Worlds, World Builder, Settings) shares one look: Study Room art, Deep Slate veil, a 24 px `MarginContainer`, a Muted Amber bold 44 title and bordered cards with amber section headers.
`Title`, `SavedPage` (`EmptyLabel`, `Scroll` → `ListBox`), `NewButton` ("+ New World"), `BackButton`, and a shared
`ConfirmModal` (see Pop-ups below).

Saved cards are built in code (`PanelContainer` → name, "N questions · X/Y trainers cleared", then two
rows of 64 px buttons): **Play** (straight to `region_map.tscn`), **Cards** (Flashcard Sanctuary), **Edit**
(`categorizer.tscn`), **Reset progress** and **Delete** (Soft Coral). Play and Cards are disabled for a world
with no questions. Reset and Delete ask first; Reset keeps the questions, Delete removes the world.
**+ New World** opens the World Builder directly: upload a file, paste text or add questions by hand there.

### `flashcards.tscn`

`Flashcards` (`Control`) → `Background` (`ColorRect`, Soft Sage), `Margin` → `List`: `TopBar`
(`BackButton`, `ProgressLabel` "N left · M banked"), `CardPanel` → `CardBox` (`BadgeLabel`,
`FrontLabel` 36 px, `Sep`, `AnswerLabel`, `SourceLabel`), `FlipButton` ("Show answer"), `RateRow`
(`AgainButton` Soft Coral, `HardButton` Muted Amber, `EasyButton` Soft Green) and `DoneLabel`.
The answer, source and rate row are hidden until the card is flipped. Colours and button styles
are applied in `_style()` from the canonical palette; every button is at least 56 px tall.

### `categorizer.tscn`

Titled "World Builder", on the Study Room art under a Deep Slate veil (`Veil`, 0.88 alpha) so text stays readable.
Inside `Margin` → `Content`: `Title` (Muted Amber, bold 44), a `SourceCard` panel ("1 · Your reviewer":
`TopicName` `LineEdit`, `FileButton` which shows the picked file name, `PasteArea`, `SanityLabel`,
`StudyButton`, `StatusLabel`, `LoadingBar`; there is no on-screen quota line, Settings shows it), then `QuestionsBlock` ("2 · Questions": `Scroll` → `QuestionsBox`
with rows built in code, `AddQuestionButton`), `PlayButton` and `BackButton`. `FileDialog` is the native
OS dialog (`use_native_dialog`) where the platform has one; the weekly-limit notice is a `ConfirmModal`.

Each question row (built in `_make_question_row`) has a header (index, confidence, delete), the
prompt `TextEdit`, a type row (`Type:` label, type `OptionButton` with Essay / Identification /
Multiple Choice, tier `OptionButton` with Easy / Medium / Hard), the answer `LineEdit`, and for
Multiple Choice three `Wrong option N` `LineEdit`s.

`FileDialog` uses `file_mode = 0` (open file) and `access = 2` (filesystem), with **no filters** —
any file type can be selected. Only the first 4000 characters of a text file are shown in the paste
box, although all bytes are kept for the upload call (`categorizer.gd:89-96`).

### `region_map.tscn`

The 3D island overworld; structure and rules in [`overworld.md`](systems/overworld.md). It is the
one landscape screen: while it is open the window is a 1280×720 base at exactly 16:9
(`CONTENT_SCALE_ASPECT_KEEP`), the phone turns to landscape (a desktop window swaps its sides; the
editor's embedded Game view cannot, so it letterboxes there), and
leaving the map in any way restores 720×1280 portrait (`region_map.gd` `_enter_tree` /
`_exit_tree`). Each switch shows a "Turn your phone sideways / upright" card
(`widgets/rotate_prompt.gd`: a phone turning a quarter with an amber arrow, on dimmed Deep Slate),
which fades after 2.2 s or on a tap. The rest of the game is portrait on phones
(`display/window/handheld/orientation` = portrait). A 220 px minimap at the top left (`minimap.gd`; Off-White frame, Deep Slate outline,
like home's HUD pills) shows the whole island from straight above, rendered once into a small
SubViewport, with live dots for the explorer (teal), trainers, gyms (amber) and the Champion
(coral). The top bar and hint sit to its right, the joystick bottom-left and Study bottom-right.

### `battle.tscn`

`Battle` (`Control`) → `Camera2D`, `Background`, `Margin` → `List`: `TopBar` (flee, title),
`QuotaLabel`, `EnemyCard` (sprite, name, HP), `PlayerCard` (sprite, name, HP), `QuestionCard`
(type, text), `AnswerInput` (`TextEdit`), `SubmitButton`, `JudgingLabel`, `ResultLabel`,
`ResultPanel` (title, XP label, retry/continue); the weekly-limit notice is a `ConfirmModal`.

The enemy and player cards sit over `ArenaStage`, the 3D scene that holds the models. The Broken
Bot foe makes its own sounds on its clips (§2 Model sounds). For a Multiple Choice question
`battle.gd` hides `AnswerInput` and `SubmitButton` and builds a `VBoxContainer` of four option
`Button`s (56 px tall) in their place at runtime.


---

### Pop-ups

`scripts/ui/widgets/confirm_modal.gd` (`ConfirmModal.open(host, title, message, confirm_text, on_confirm, danger, cancel_text)`) is the one pop-up: a dimmed screen, a card that scales in (0.85 → 1, back-ease, 0.28 s) and out (0.14 s), a bold title (coral when `danger`), centred wrapped text and full-width buttons. An empty `cancel_text` makes it a notice. Esc cancels. Tweens ignore `Engine.time_scale`, so battle hit-stop does not freeze it. Callers `preload` the script instead of relying on a `class_name`. Used by the Worlds hub (reset, delete), the World Builder and the battle (weekly limit).

## 3. Interaction conventions

- **Buttons:** flat icon buttons (`flat = true`, `icon_alignment = CENTER`, `expand_icon = true`)
  for room actions, full-width text buttons for flow actions.
- **Input:** movement uses the built-in `ui_left` / `ui_right` / `ui_up` / `ui_down` actions, so
  arrows **and** WASD work with no custom `InputMap`. Everything else is mouse/touch on `Control`s.
- **No on-screen touch controls** — the overworld is currently desktop/keyboard-only in practice.
- **No pause menu, no transition animation, no loading indicator between scenes.**

---

## 4. Audio

All of Studymon's audio is our own, composed and synthesised from scratch for its cosy, pastel
study-pet mood: bright marimba, ukulele and glockenspiel, music box and soft bells, with rounded
cues and no harsh noise. The music and one-shots are WAVs rendered by a Python generator kept outside the repo
(additive sine partials, wavetable pads, a Schroeder reverb, gentle `tanh` rounding); Kuiz's and
the Broken Bot's sounds are synthesised in the game itself (§2 Model sounds).

`MusicManager` (autoload) owns two `AudioStreamPlayer`s:

- `MusicPlayer` — starts `music/home_room.wav` at `-6 dB` on `_ready()` and persists across scene
  changes. `splash.tscn` calls `play_loading()`, which starts `music/loading.wav` at 1 s and fades
  it in over 1 s; `loading.tscn` keeps the same track playing, and `peek.tscn` calls
  `play_main_room()` to swap back: the loading track fades out on its own player while the home
  loop fades in, over `CROSSFADE` (2.5 s). `region_map.gd` calls `play_overworld()` on entering
  the map, the same crossfade to `music/overworld.wav`; battles have no music, so it carries on
  through them, and `session_list.gd`, `flashcards.gd` and `peek.tscn` call `play_main_room()` to
  fade back. Each track is written as a seamless loop (its note
  and reverb tails wrap onto its start) and is set to loop forward over its whole length at runtime.
  - **Home Room** (34 s, 112 bpm, C major): a sunny, bouncy tune — a marimba melody over
    ukulele strums on an island pattern (C · F · G · C, C · Am · F · G, F · G · C · G,
    C · F · G · C), a plucky bass on roots and fifths, glockenspiel twinkles at phrase ends and
    doubling the third phrase, and a soft kick, clap and shaker groove; only a light room reverb.
  - **Loading** (38 s, 100 bpm, C major): rolling marimba arpeggios, a soft pad, a gentle
    woodblock tick on the off-beats and a bell call every two bars.
  - **Overworld** (46 s, 126 bpm, G major): a Pokémon-route-style walking theme — a soft pulse
    lead (band-limited 25 % pulse with gentle vibrato) over off-beat ukulele chops and a bouncy
    octave bass; A (G · D · Em · C · G · D · C · D), a bridge B (C · D · G · Em · C · D · Am · D)
    with marimba broken chords, then A again doubled by glockenspiel; kick, clap and shaker with a
    tom fill every 8 bars, light room reverb.
- `SfxPlayer` — single voice, so overlapping SFX cut each other off; `play_sfx_chain()` serialises a
  list with `await` and cancels itself if another chain starts (guarded by `_sfx_chain_id`).
  `play_sfx_layered()` plays on a throwaway player so battle cues overlap.

One-shots (`sfx/`, 22 050 Hz mono, each with a short soft reverb tail):

| Cue | Sound | Played by |
|---|---|---|
| `sfx_click` | a soft wooden tok | battle buttons |
| `sfx_whoosh` | a band-passed air swell | battle intro, bots flying in |
| `sfx_land` | a round low thump | a bot landing on its pad |
| `sfx_vs` | a rising C–G–C bell chime with a shimmer | the VS banner |
| `sfx_correct` | a music-box C major arpeggio up | a right answer |
| `sfx_wrong` | two soft falling triangle "boops" | a wrong answer |
| `sfx_hit` | a rounded pop | Kuiz's blow landing |
| `sfx_hurt` | a wobbly falling tone | Kuiz being hit |
| `sfx_win` | a music-box arpeggio into a bell chord with sparkles | winning a battle |
| `sfx_lose` | a gentle falling music-box line over a soft pad | losing a battle |
| `sfx_charge` | a soft rising hum and a bell | Study Room lights off (Charge) |
| `sfx_charged` | two low, sleepy bells and a warm swell | right after `sfx_charge` |

Kuiz and the Broken Bot make their sounds in code on their own players (§2 Model sounds).

---

## 5. Asset inventory

### Used

Icons and props that are shown large (the dock, the HUD, the minigame card, the soccer ball, the
new Sky Jump art) are drawn with their root `width`/`height` at 2.5× the viewBox, so Godot
rasterises them sharp on high-density phones; the drawing itself is unchanged.

| Asset | Used by |
|---|---|
| `audio/sfx/sfx_*.wav` (ten battle cues: click, whoosh, land, vs, correct, wrong, hit, hurt, win, lose; our own) | `battle.gd` exports, assigned in `battle.tscn`; played through `MusicManager.play_sfx_layered()` |
| `sprites/battle/battle_backdrop.svg` | `battle.tscn` arena backdrop |
| `audio/music/home_room.wav` | `MusicManager`: home loop (our own; 34 s, upbeat C major, seamless) |
| `audio/music/loading.wav` | `MusicManager.play_loading()`: splash/loading loop (our own; 38 s, seamless) |
| `audio/music/overworld.wav` | `MusicManager.play_overworld()`: region map (and battle) loop (our own; 46 s, G major route theme, seamless) |
| `audio/sfx/sfx_charge.wav`, `sfx_charged.wav` | home's Charge button (our own) |
| `fonts/JosefinSans-Regular.ttf` | theme default font |
| `fonts/JosefinSans-Bold.ttf` | theme button font; `loading.tscn` title and tip labels |
| `sprites/boot/loading.png` | `loading.tscn` background |
| `sprites/boot/loading_screen_logo.gif` | source of the loading logo animation (not imported; Godot has no GIF loader) |
| `sprites/boot/loading_screen_logo.png` | `loading.gd`: the loading logo's 60 frames, white keyed out, 6 per row |
| `sprites/effects/leaf.svg` | `loading.tscn` falling leaves, overworld autumn leaves (white so particle colour tints it) |
| `sprites/ui/loading_spark.svg` | `loading.tscn` sparks either side of "Loading..." |
| `sprites/ui/tip_bulb.svg` | `loading.tscn` tip icon |
| `models/map.glb`, `models/map_0.png` | `region_map.tscn` island (the PNG is its road texture) |
| `models/boy_explorer.glb`, `boy_explorer_basecolor_v2.jpg`, `boy_explorer_normal_v2.jpg` | `region_map.tscn` explorer (`Idle`, `Walk`, `Run` used) |
| `models/robot_1.glb` | battle foe, the Broken Bot (`Idle`, `Attack`, `Defeat`); its sounds are made in code (`broken_bot_voice.gd`) |
| `models/robot_2.glb` | battle foe (`Idle`, `Attack`, `Defeat`); silent |
| `models/kuiz.glb` | `peek.tscn` 3D Kuiz head; 21 clips (13 one-shots, `Celebrate`, `Learn_Something_New`, six `State_*` moods), face and props on blend shapes |
| `sprites/boot/kuizmon_splash.png` | `splash.gd` 60-frame intro sheet (6 × 10 cells, 480 × 264) |
| `sprites/rooms/study_room.svg` | settings and categorizer background (day); the tutorial's Study Room (temporary placeholder) |
| `sprites/rooms/study_room_night.svg` | home's lights-off Study Room (temporary placeholder) |
| `sprites/rooms/maintenance_bay.svg` | tutorial Maintenance Bay (temporary placeholder) |
| `sprites/rooms/data_kitchen.svg` | tutorial and home Data Kitchen (temporary placeholder) |
| `sprites/rooms/playroom.svg` | tutorial and home Playroom; no painted ball, the real one is flung (temporary placeholder) |
| `sprites/ui/icon_charge.svg`, `icon_upload.svg`, `icon_settings.svg` | home's Charge, Play and Settings buttons (temporary placeholders, same style as the props) |
| `sprites/ui/campaign.png`, `charge.png`, `settings.svg` | **unused** since home took the icons above; safe to delete |
| `sprites/ui/arrow.svg` | home's room arrows (top) and food arrows (bar); an Off-White chevron with a Deep Slate outline, flipped for ◀ |
| `sprites/ui/crystal.svg` | home's crystal (currency) pill: the logo's forehead gem (temporary placeholder) |
| `sprites/ui/stat_mood.svg`, `stat_health.svg` | home's Mood and Health gauges (temporary placeholders) |
| `sprites/props/data_chips.svg`, `spicy_chips.svg`, `cache_cookie.svg`, `pi_pie.svg`, `byte_burger.svg`, `java_juice.svg` | home's six foods (temporary placeholders); `data_chips.svg` is also the Hunger gauge icon |
| `sprites/props/fridge.svg` | home's Data Kitchen fridge button, in the kitchen bar (temporary placeholder) |
| `sprites/props/ball.svg` | home's Playroom ball (temporary placeholder) |
| `sprites/props/soccer_ball.svg`, `platform.svg`, `ground.svg` | Kuiz Keeper's ball; Sky Jump's platforms and starting ground (temporary placeholders) |
| `sprites/props/platform_timed.svg`, `trampoline.svg`, `rocket.svg` | Sky Jump's timed platform, trampoline and rocket (temporary placeholders) |
| `sprites/rooms/sky_space.svg`, `sky_galaxy.svg`, `sky_deep.svg` | Sky Jump's Space, Galaxy and Deep Space backdrops (temporary placeholders) |
| `sprites/props/stars.svg` | Sky Jump's parallax star layer from Space up (tiles vertically) |
| `sprites/props/platform_space.svg`, `platform_galaxy.svg`, `platform_deep.svg` | Sky Jump's platforms in Space, Galaxy and Deep Space (temporary placeholders) |
| `sprites/props/meteor.svg` | Sky Jump's meteor hazard (temporary placeholder) |
| `sprites/ui/dock_table.svg` | home's dock: the table the room items stand on (temporary placeholder) |
| `sprites/ui/icon_phone.svg`, `icon_turn.svg` | the rotate-your-phone card (`rotate_prompt.gd`) |
| `sprites/rooms/soccer_field.svg`, `sky_jump.svg` | the minigame backdrops, behind Kuiz (temporary placeholders) |
| `sprites/ui/icon_games.svg`, `game_soccer.svg`, `game_jump.svg` | the Playroom's Games button and the Minigames card (temporary placeholders) |
| `sprites/props/screwdriver.svg` | home's Maintenance Bay screwdriver (temporary placeholder) |
| `sprites/props/tablet.svg`, `towel.svg` | home's Maintenance Bay check-up tablet and towel (temporary placeholders) |
| `sprites/props/closet.svg` | home's Playroom closet (temporary placeholder) |
| `sprites/props/dirt_spot_1.svg`, `dirt_spot_2.svg`, `dirt_spot_3.svg`, `scratch_1.svg`, `scratch_2.svg` | dirt on Kuiz (`kuiz_look.gd`; temporary placeholders) |
| `sprites/props/costume_party_hat.svg`, `costume_crown.svg`, `costume_beanie.svg`, `costume_bow.svg`, `costume_flower.svg`, `costume_glasses.svg`, `costume_shades.svg`, `costume_hero_mask.svg`, `costume_bow_tie.svg`, `costume_scarf.svg`, `costume_medal.svg` | Kuiz's costumes, worn and shown in the closet (temporary placeholders) |
| `icon.svg` | project icon |

### Source / not imported

| Asset | Note |
|---|---|
| `sprites/boot/kuizmon_loading.gif` | source for `kuizmon_splash.png`; Godot has no GIF importer |

### Referenced but **missing**

None known. `bot_lv1..5.png` was only read by the deleted `companion.gd`.

---

## 6. Layout notes

- Art is authored for 720 × 1280 and positioned with absolute offsets inside anchored containers;
  anything wider than 9:16 will reflow but not re-layout the room props.
- Several nodes still use `layout_mode = 0` with raw offsets (legacy from the first room), so they
  ignore container sizing.
- `unique_id` attributes appear on nodes in the newer scenes (4.7 scene format); they are editor
  metadata, not something to reproduce by hand.
