# Companion care (pet loop)

The pre-campaign gate. Three tap actions raise the companion from Level 1 to Level 5, unlocking
the review campaign. This is the loop that carries the "raise an AI" fantasy and teaches the
curriculum through `CURRICULUM` lines.

- **State / logic:** `scripts/autoload/companion_state.gd` (autoload `CompanionState`)
- **Care room UI:** `scripts/companion/companion.gd` → `scenes/ui/main.tscn`
- **Status strip:** `scripts/ui/hud_strip.gd` → `ui/hud_strip.tscn` (instanced on `main.tscn`)
- **Pomodoro UI:** `scripts/ui/pomodoro.gd` → `ui/pomodoro.tscn`
- **Skeletal rig (disabled):** `scripts/companion/companion_rig.gd` → `scenes/companion/companion_rig.tscn`

---

## 1. Stats

| Stat | Start | Range | Decay | Grown by |
|---|---|---|---|---|
| `energy` | 80.0 | 0–100 | **0.15 / s** | `feed` +8, rest complete +6, `play` −2, skip focus −3, missed rest −5 |
| `focus` | 70.0 | 0–100 | **0.12 / s** (0.8×) | `play` +8 |
| `mood` | 75.0 | 0–100 | **0.09 / s** (0.6×) | `pet` +8, rest complete +6, skip focus −2, missed rest −3 |
| `bond` | 0 | unbounded | — | +1 per care tap; **never read** |
| `level` | 1 | 1–5 | — | XP thresholds |
| `xp` | 0 | unbounded | — | care taps + battle rewards |

Decay is applied in `_process` (`companion_state.gd:62-67`), i.e. it runs whenever the game is
running, on every screen — decaying stats are global, not just in the care room. With `energy`
decaying 0.15/s, a full bar drains in ~11 minutes of real time.

`stats_changed` is emitted **every frame** from the same `_process`. All decay writes are `maxf(0, …)`
so stats bottom out cleanly at zero.

---

## 2. Care actions

`CompanionState.care(action)` (`companion_state.gd:99-129`) is the single entry point.

| Action | Effect | Base XP | Notes |
|---|---|---|---|
| `"feed"` | `energy += 8` | 2 | |
| `"pet"` | `mood += 8` | 1 | weakest XP; no side cost |
| `"play"` | `focus += 8`, `energy -= 2` | 2 | net positive stats, costs energy |

Returns:

```gdscript
{ "xp": int, "deltas": {"energy": 8.0}, "action": "feed", "tap_count": int }
```

`bond` increments inside `care()` regardless of action. The UI uses the return value only to render
the floating `+N XP` tick and an extra `(tired)` suffix once `tap_count > DAILY_CAP_BASE_XP`
(`companion.gd:127-135`).

### Diminishing returns

```gdscript
const DAILY_CAP_BASE_XP := 10   # taps of the SAME action per hour
if count >= 10: xp_mult = 0.3
gained = int(2 * xp_mult)       # feed / play
gained = int(1 * xp_mult)       # pet
```

Counter resets hourly via `_maybe_reset_hourly_cap()` (`companion_state.gd:70-74`).

> **This is currently a bug, not a balance knob.** `0.3` multiplied and truncated by `int()` yields
> **0** for all three actions (`int(2*0.3) == 0`, `int(1*0.3) == 0`). After 10 taps of one action in
> an hour, that action grants no XP at all until the hour rolls over. See `known-issues.md` #5.

---

## 3. XP curve and the Level 5 gate

```gdscript
const MAX_LEVEL := 5
const XP_PER_LEVEL := [0, 20, 45, 75, 110, 150]   # cumulative
```

| Level | Cumulative XP needed | Delta from previous |
|---|---|---|
| 1 | 0 | — |
| 2 | 20 | 20 |
| 3 | 45 | 25 |
| 4 | 75 | 30 |
| 5 | 150 | 35 |

`_check_level_up()` loops while `xp >= XP_PER_LEVEL[level]`, so a single large XP grant can cross
multiple levels. At 5 it sets `campaign_ready = true` and emits `campaign_gate_ready`.

Pacing as designed (source comment `companion_state.gd:12-16`): at 1–2 XP per tap with cycling
actions, ~90 taps ≈ 2.5–4 minutes.

Once `campaign_ready` is true and level is 5, `add_xp()` returns early — battle rewards stop being
applied, but the XP bar is displayed with `hi = lo + 1` so it sits full (`companion.gd:243`).

The gate reaches `GameState` through two paths:

```text
CompanionState.leveled_up(5) ─► campaign_gate_ready ─► companion.gd:_on_campaign_ready()
                                                        └─ GameState.set_campaign_unlocked(true)

main.tscn boot ─► companion.gd: if CompanionState.campaign_ready:
                                    GameState.set_campaign_unlocked(true)
```

`campaign_unlocked_flag` is what actually enables `CampaignButton`; `CompanionState.campaign_ready`
is what gets saved. They can drift if a save is hand-edited.

---

## 4. Codex / curriculum

`CURRICULUM` (`companion_state.gd:50-56`) is a level → line map, unlocked one entry per level-up
and backfilled on load for older saves:

| Level | Line (AI-literacy concept) |
|---|---|
| 1 | "I start out knowing NOTHING — like a baby! … (AI starts blank)" |
| 2 | "Feed me examples! That's called **TRAINING DATA**…" |
| 3 | "When you Pet me for a good answer, that's **FEEDBACK**…" |
| 4 | "Playing is **PRACTICE** — I try, fail, and try again…" |
| 5 | "I can **GENERALIZE** now! Show me your PDF reviewer…" |

There is **no Codex screen** — entries only appear as the `TidbitBubble` label, which is hidden
(see `known-issues.md` #4). A `feat/remove-codex` branch exists on `origin`, suggesting this was
abandoned deliberately.

---

## 5. Room interactions (`main.tscn`)

| Control | Node | Behaviour |
|---|---|---|
| Campaign | `Room/CampaignButton` | Disabled until `GameState.campaign_unlocked_flag`; otherwise shows "Locked! Reach Level 5 first. (N XP to next level)" in the tidbit bubble |
| Charge | `Room/ChargeButton` | Toggles day ↔ night room texture (`rooms/study_room.svg` / `study_room_night.svg`), shows `NightVeil`, dims every other child to 70 % via `_base_modulate`, plays `charge.mp3` then `charged.mp3` when switching to night |
| Pomodoro | `Room/PomodoroButton` | Toggles the in-scene `Pomodoro` panel visibility |
| Settings | `Room/SettingsButton` | `change_scene_to_file("res://scenes/ui/settings.tscn")` |
| Pet | *(none)* | **There are no Feed / Pet / Play buttons in the scene.** `_on_care()` exists in `companion.gd:127` but nothing connects a button to it. |

That last row matters: the care loop's *state machine* is complete and saveable, but the current
care-room scene has no way to trigger it. The `bot_lv*.png` sprites the scene expects are also
missing, so the room renders without a pet (`known-issues.md` #3).

---

## 6. Pomodoro (Phase 4)

Logic lives in `CompanionState`, UI in `ui/pomodoro.tscn`. One timer drives both phases.

```
                 start_pomodoro()
        ""  ──────────────────────►  "focus"  (25:00)
         ▲                              │ time out
         │ skip during rest             ▼
         │ (penalty)                 "rest"   (5:00)
         │                              │ time out → +6 energy, +6 mood
         └──────────────────────── "done" ◄┘
                                        │
                                     (stop, mode "")
```

| Constant | Value | Effect |
|---|---|---|
| `POMODORO_FOCUS_SEC` | 1500 | focus length |
| `POMODORO_REST_SEC` | 300 | rest length |
| `MISSED_REST_ENERGY_PENALTY` | 5.0 | applied on `skip_pomodoro()` during rest |
| `MISSED_REST_MOOD_PENALTY` | 3.0 | same |
| `REST_COMPLETE_ENERGY_BONUS` | 6.0 | natural rest completion |
| `REST_COMPLETE_MOOD_BONUS` | 6.0 | natural rest completion |

Skipping **focus** applies a soft −3 energy / −2 mood and jumps straight to rest (no
missed-rest penalty). Only the focus timer auto-advances to rest; there is no notification when a
phase ends — the companion just changes its bubble line (`companion.gd:177-187`).

Badge: `HudStrip` shows `FOCUS mm:ss` / `REST mm:ss` in `PomoBadge` while a phase is active.

The timer is a real `Timer` node with 1 s ticks, so it is affected by `Engine.time_scale`
(used by battle hit-stop) and by scene tree pauses; it is not a wall-clock countdown.

---

## 7. Companion rig (`companion_rig.gd`)

A hand-built skeletal setup used for squash/breathe/blink instead of frame animation:

- `Polygon2D` body + `Skeleton2D` with bones `Root/Body/{EarL,EarR,Antenna}`.
- Vertex weights are painted **at runtime** with Gaussian falloff around each bone plus hard
  spatial gates (`_gate()`), normalised per vertex (`_paint_weights`, `companion_rig.gd:110`).
- Idle = bob tween + 1.6 s breathe scale + antenna sway; blink = an `AnimatedSprite2D` overlay using
  `blink_companion.svg` on a random 2.4–4.8 s timer.
- Public API: `play_reaction(action)`, `celebrate()`, `set_mood("sad"|"sleepy"|…)`.

It is **switched off**: `companion.gd:36-37` forces `rig.visible = false`, and `main.tscn:83` sets
`visible = false` on the instance. Every rig call in `companion.gd` early-returns while hidden.
Running `main.tscn` headless also logs `Condition "det == 0" is true` several times from the
degenerate bone rests (`known-issues.md` #12).

---

## 8. Tuning checklist

If you want to change pacing, these are the only knobs that matter:

| Goal | Constant(s) |
|---|---|
| Faster/slower leveling | `XP_PER_LEVEL` (remember it's cumulative) |
| Faster/slower stat pressure | `STAT_DECAY_PER_SEC` |
| Softer tap spam | `DAILY_CAP_BASE_XP` **and** fix the `int()` truncation |
| Longer sessions | `POMODORO_FOCUS_SEC` / `POMODORO_REST_SEC` |
| Harsher missed rest | `MISSED_REST_*_PENALTY` |
