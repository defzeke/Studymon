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

### Large text (partial)

`GameState` can scale the theme at runtime:

```gdscript
const FONT_SIZE_STANDARD := 28     const FONT_SIZE_LARGE := 36
const BUTTON_FONT_STANDARD := 32   const BUTTON_FONT_LARGE := 40
func set_large_text(enabled)        # mutates the loaded Theme + assigns it to root
```

It is saved, applied on load, and `companion.gd` listens for `large_text_changed` — but **nothing
in the UI ever calls `set_large_text()`**. `settings.tscn` has no accessibility control
(`known-issues.md` #11).

---

## 2. Screens

| Scene | Root type | Script | Purpose |
|---|---|---|---|
| `scenes/ui/splash.tscn` | `Control` | `scripts/ui/splash.gd` | white intro, then loading |
| `scenes/ui/loading.tscn` | `Control` | `scripts/ui/loading.gd` | boot + routing |
| `scenes/companion/meet_companion.tscn` | `Control` | `scripts/companion/meet_companion.gd` | 6-line intro cutscene |
| `scenes/ui/main.tscn` | `Control` | `scripts/ui/main.gd` (+ `companion.gd` on child) | care room |
| `scenes/ui/session_list.tscn` | `Control` | `scripts/ui/session_list.gd` | topic history |
| `scenes/review_session/categorizer.tscn` | `Control` | `scripts/review_session/categorizer.gd` | upload + question editor |
| `scenes/overworld/region_map.tscn` | `Node2D` | `scripts/overworld/region_map.gd` (+ `player.gd`) | route, gyms, champion |
| `scenes/battle/battle.tscn` | `Control` | `scripts/battle/battle.gd` | arena |
| `scenes/ui/settings.tscn` | `Control` | `scripts/ui/settings.gd` | premium + quota debug |
| `ui/hud_strip.tscn` | `VBoxContainer` | `scripts/ui/hud_strip.gd` | status strip (instanced) |
| `ui/pomodoro.tscn` | `VBoxContainer` | `scripts/ui/pomodoro.gd` | timer panel (instanced) |
| `scenes/companion/companion_rig.tscn` | `Node2D` | `scripts/companion/companion_rig.gd` | skeletal pet (hidden) |

### `main.tscn` — care room

```text
Main                      (main.gd)  — only calls SaveManager.load_game()
└── Room                  (companion.gd)
    ├── BgFill            ColorRect, sky blue fallback
    ├── Background        TextureRect, rooms/main.svg
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

### `loading.tscn`

`Loading` → `Background` (`loading.png`), `Logo` (`logo.png`, top-centre), `Content` → `LoadBar`
(`ProgressBar`; its `RunBot` TextureRect is hidden) + `TipLabel`. Sequence: 0 → 96 % in 5 s,
0.6 s hold, → 100 % in 2 s, then route. Tips rotate every 2.5 s with a 0.25 s fade out/in.

### `meet_companion.tscn`

Outer `MeetCompanion` → inner `MeetCompanion` (holds the script) → `Center` → `Dialogue`,
`NextButton`, `SkipButton`. The last line's button becomes "Enter Care Room"; skipping jumps straight
to `main.tscn`. `_ready()` also calls `Api.mock_get_companion()`, which overwrites companion stats
with the starter set — **entering this scene any time after starting resets the companion**.

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
| `audio/charge.mp3`, `audio/charged.mp3` | `companion.gd` day/night toggle |
| `fonts/JosefinSans-Regular.ttf` | theme default font |
| `fonts/JosefinSans-Bold.ttf` | theme button font |
| `sprites/1run_loading.png`, `2run_loading.png`, `3run_loading.png` | `loading.gd` run-cycle (RunBot hidden in the scene) |
| `sprites/loading.png` | `loading.tscn` background |
| `sprites/logo.png` | `loading.tscn` top-centre wordmark |
| `sprites/kuizmon_splash.png` | `splash.gd` 60-frame intro sheet (6 × 10 cells, 480 × 264) |
| `sprites/rooms/main.svg` | care-room background (day) |
| `sprites/rooms/dark_main.svg` | care-room background (night) |
| `sprites/ui/campaign.png` | CampaignButton icon |
| `sprites/ui/charge.png` | ChargeButton icon |
| `sprites/ui/pomodoro.svg` | PomodoroButton icon |
| `sprites/ui/settings.svg` | SettingsButton icon |
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
