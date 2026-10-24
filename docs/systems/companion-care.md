# Companion care (pet loop)

The pre-campaign gate. Three tap actions raise the companion from Level 1 to Level 5, unlocking
the review campaign. This is the loop that carries the "raise an AI" fantasy and teaches the
curriculum through `CURRICULUM` lines.

- **State / logic:** `scripts/autoload/companion_state.gd` (autoload `CompanionState`)
> The 3D home in `peek.tscn` (`home.gd`, see `ui-and-assets.md` §2 Home) is now where the player
> cares for Kuiz. **The old 2D care room was removed** (`main.tscn`, `companion.gd`, the HUD strip,
> the Pomodoro panel and the skeletal rig). `CompanionState` keeps its care and Pomodoro logic with no
> UI attached, and its save fields are unchanged. Sections below that describe the room, the strip,
> the Pomodoro panel and the rig are historical.

---

## 1. Stats

| Stat | Start | Range | Decay | Grown by |
|---|---|---|---|---|
| `hunger` | 80.0 | 0–100 | **0.105 / s** (0.7×) | `feed` +12 |
| `energy` | 80.0 | 0–100 | **0.15 / s** | charging +6 / s (`recharge()`), rest complete +6, `play` −2, skip focus −3, missed rest −5 |
| `mood` | 75.0 | 0–100 | **0.09 / s** (0.6×) | `pet` +8, `play` +8, rest complete +6, skip focus −2, missed rest −3 |
| `health` | 100.0 | 0–100 | **0.03 / s** (0.2×) | `fix` +25 |
| `focus` | 70.0 | 0–100 | **0.12 / s** (0.8×) | flashcards +2 per card; not on the home HUD |
| `bond` | 0 | unbounded | — | +1 per care tap; **never read** |
| `level` | 1 | 1–5 | — | XP thresholds |
| `xp` | 0 | unbounded | — | care taps + battle rewards |

Decay is applied in `_process` (`companion_state.gd:62-67`), i.e. it runs whenever the game is
running, on every screen. With `energy`
decaying 0.15/s, a full bar drains in ~11 minutes of real time.

`stats_changed` is emitted **every frame** from the same `_process`. All decay writes are `maxf(0, …)`
so stats bottom out cleanly at zero.

---

## 2. Care actions

`CompanionState.care(action)` (`companion_state.gd:99-129`) is the single entry point.

| Action | Effect | Base XP | Notes |
|---|---|---|---|
| `"feed"` | `hunger += 12` | 2 | home: food dropped on Kuiz |
| `"pet"` | `mood += 8` | 1 | weakest XP; no home action yet |
| `"play"` | `mood += 8`, `energy -= 2` | 2 | home: a fast ball throw |
| `"fix"` | `health += 25` | 2 | home: a finished screwdriver tune-up |

Energy has no tap: `recharge(delta)` adds 6 / s while home's Charge toggle is on. Home saves after
each care action (`SaveManager.save_progress()`).

Returns:

```gdscript
{ "xp": int, "deltas": {"hunger": 12.0}, "action": "feed", "tap_count": int }
```

`bond` increments inside `care()` regardless of action. The UI uses the return value only to render
the floating `+N XP` tick and an extra `(tired)` suffix once `tap_count > DAILY_CAP_BASE_XP`
(the removed `companion.gd`).

### Diminishing returns

```gdscript
const DAILY_CAP_BASE_XP := 10   # taps of the SAME action per hour
if count >= 10: xp_mult = 0.3
gained = int(2 * xp_mult)       # feed / play / fix
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
applied.

The gate reaches `GameState` on load only:

```text
CompanionState.leveled_up(5) ─► campaign_gate_ready ─► (no listener since companion.gd was removed)

```

`SaveManager.load_game()` sets `campaign_unlocked_flag` from `CompanionState.campaign_ready`, which
is what gets saved. With no care input, Level 5 is unreachable without editing the save.

### Other XP and stat sources

Battle wins add XP (`add_xp`). The Flashcard Sanctuary adds a little more
(`reward_card_banked()`: +1 XP and +2 focus per card it lifts a mastery step; `reward_deck_done()`:
+3 mood), see [`gameplay-structure.md`](gameplay-structure.md) §3.4. None of these go through
`care()`, so the hourly cap does not apply; each card pays once.

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

There is **no Codex screen** and the `TidbitBubble` that showed entries was deleted with the care room.
A `feat/remove-codex` branch exists on `origin`, suggesting the codex was abandoned deliberately.
abandoned deliberately.

---

## 5. Room interactions

The old care room was deleted. The 3D home (`home.gd`) calls `care()` from its room actions —
food (`feed`), the screwdriver (`fix`), the ball (`play`) — and `recharge()` while charging. Its
top HUD shows level, XP, the four home stats and crystals. Details in
[`ui-and-assets.md`](../ui-and-assets.md) §2 Home.

---

## 6. Pomodoro (Phase 4)

Logic lives in `CompanionState`; the Pomodoro panel was deleted, so nothing starts it. One timer drives both phases.

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
phase ends.

The timer is a real `Timer` node with 1 s ticks, so it is affected by `Engine.time_scale`
(used by battle hit-stop) and by scene tree pauses; it is not a wall-clock countdown.

---

## 7. Companion rig (removed)

The 2D skeletal rig (`companion_rig.gd`, its scene and the idle/blink/sad SVGs) was deleted. Kuiz is the
3D `kuiz.glb` in `peek.tscn` and the battle arena.

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
