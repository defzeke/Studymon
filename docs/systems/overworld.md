# Overworld, gyms and mastery

The campaign map: a vertical route built from the topic's questions, with one gym per question
type, a trainer per question, and a Champion fight that closes the region.

- **Map logic:** `scripts/overworld/region_map.gd` → `scenes/overworld/region_map.tscn`
- **Player:** `scripts/overworld/player.gd`
- **Progress + mastery state:** `scripts/autoload/session_manager.gd`
- **Question data:** `SessionManager.pending_questions` (see `review-session.md`)

Status: **Implemented but currently unloadable.** `region_map.tscn` references
`res://assets/sprites/bot_lv5.png`, which does not exist, so the scene fails to parse at runtime
(`known-issues.md` #1). Everything below describes the code as written.

---

## 1. What it reads

The overworld is a *derived* view. It holds no map data of its own:

| Value | Source |
|---|---|
| Active topic id | `SessionManager.current_topic_id`, falling back to `editing_topic_id` |
| Questions | `SessionManager.get_pending_questions()` |
| Gyms | `SessionManager.get_gym_structure()` |
| Clear state | `SessionManager.is_trainer_cleared()` / `is_gym_cleared()` |
| Mastery | `SessionManager.get_mastery_state()` + `mastery_badge()` |
| Champion state | `SessionManager.is_champion_available()` / `is_champion_defeated()` / `champion_moveset()` |

If `pending_questions` is empty (direct scene run), `region_map.gd:36-43` seeds a two-question
`topic_preview` so the route still renders.

---

## 2. Gym structure

`get_gym_structure()` (`session_manager.gd:198-210`) buckets question indices by `type`, preserving
first-seen order:

```gdscript
[
  {"type": "identification", "question_indices": [0, 2, 4]},
  {"type": "essay",          "question_indices": [1, 3]}
]
```

So **a gym is a question type**, not a topic or a chapter. One Identification gym and one Essay gym
per topic, regardless of question count. Re-typing a question in the categorizer moves it between
gyms.

---

## 3. Route generation (`_build_route`, `region_map.gd:54-92`)

```text
y = 1100  ── player start (360, 1100)
   │
y -= 320  ── gym 1  (360, 780)
   ├── trainers for gym 1 interpolated between the previous point and the gym,
   │   alternating ±120 px horizontally
y -= 320  ── gym 2  (360, 460)
   ├── ...
y -= 320  ── Champion (360, 140)
```

- Gyms are 320 px apart on a single `Line2D` (`Route`), width 14, tan colour.
- Trainer positions: `frac = (i+1)/(n+1)` along the segment, `side = -120` for even indices,
  `+120` for odd.
- Every node is created at runtime — `Trainers/` and `Gyms/` start empty in the scene.
- Rebuilding clears both roots first, so nothing accumulates.

Each trainer node is an `Area2D` + `CircleShape2D(36)` + `Label` `"T<N> <mastery emoji>"`. Cleared
trainers are dimmed to `Color(0.5, 0.5, 0.5, 0.7)`.

Each gym node is an `Area2D` + `CircleShape2D(56)` + label `"GYM"` / `"GYM-CLEAR"` plus
`"<Type> G<n>"`.

The Champion node is an `Area2D` + `CircleShape2D(64)` with one of `CHAMPION DOWN`,
`CHAMPION FIGHT!`, `CHAMPION LOCKED`.

Movement is `ui_left`/`ui_right`/`ui_up`/`ui_down` (arrows + WASD by default) at 300 px/s on a
`CharacterBody2D` with `move_and_slide()` and a smoothed `Camera2D` child. The sprite flips on the
x axis only — no directional animation exists.

---

## 4. Encounter panel

One shared `PanelContainer` (`HUD/EncounterPanel`) is reconfigured per encounter type. Touching an
`Area2D` sets `_pending_encounter` and fills the title, body and action button.

| Encounter | `_pending_encounter` | Button |
|---|---|---|
| Trainer (uncleared) | `{kind: "trainer", q_index, gym}` | `Fight Trainer!` → `begin_battle(topic, q_idx, false)` |
| Trainer (cleared) | same | `Already Cleared` (disabled) |
| Gym boss | `{kind: "gym", gym, question_indices}` | `Fight Boss!` → `begin_battle(topic, last index of gym, true)` |
| Gym (cleared) | — | `Badge Earned` (disabled) |
| Champion (region complete) | `{}` | `Crowned` (disabled) |
| Champion (locked) | `{}` | `Locked` (disabled) |
| Champion (ready) | `{kind: "champion"}` | `Challenge Champion!` → `begin_champion_battle(topic)` |

The boss is **the last question index in that gym's bucket**, not a separate boss question. The
Champion panel doubles as the pre-fight summary: it lists up to 6 Mastered questions with mastery
badges plus `...and N more.`

Confirming an encounter hides the panel and does `change_scene_to_file("res://scenes/battle/battle.tscn")`.

---

## 5. Clear state

Two independent dictionaries, both keyed by strings:

| Store | Key | Set by |
|---|---|---|
| `_cleared_trainers` | `"<topic_id>:<q_index>"` | `mark_trainer_cleared()` after a win |
| `_cleared_gyms` | `"<topic_id>:<gym_type>"` | `mark_gym_cleared()` (boss win) or `_recheck_gym_clear()` |

`_recheck_gym_clear()` runs after every trainer win and clears the gym when **all** of its
`question_indices` are cleared.

Consequence worth knowing: beating the **boss directly** marks the whole gym cleared even if the
other trainers in that gym were never fought. Gym progress and trainer progress are therefore not
strictly ordered, and the HUD can show `Trainers 1/5  Gyms 1/2`.

`get_progress(topic_id)` returns:

```gdscript
{"cleared": int, "total": int, "gyms_cleared": int, "gyms_total": int}
```

`total` is `pending_questions.size()` — **all** questions in the topic, not just the ones in the
current gym.

HUD strings (`_refresh_progress`):

- `progress_label`: `Trainers c/t  CROWNED | CHAMP-READY | CHAMP-LOCKED`
- `badges_label`: `Gyms g/G [X][ ]`

`reset_progress(topic_id)` wipes trainers, gyms, mastery and the champion flag for that topic.

---

## 6. Mastery states

```gdscript
enum Mastery { NEW, LEARNING, REMASTER, MASTERED }   // 0..3
const MASTERY_DECAY_DAYS := 7
```

Recorded after **every** battle result, win or loss (`record_battle_outcome`,
`session_manager.gd:422-455`):

| Current | On win | On loss |
|---|---|---|
| `NEW` | `LEARNING` | `NEW` (unchanged) |
| `LEARNING` | `MASTERED` | `LEARNING` (unchanged) |
| `REMASTER` | `MASTERED` | `LEARNING` |
| `MASTERED` | `MASTERED` | `REMASTER` |

Plus: `MASTERED` decays to `REMASTER` after 7 days without a correct answer — evaluated lazily on
read (`get_mastery_state`), not on a timer. `last_correct` is only refreshed on a win.

Badges (`mastery_badge()`):

| State | Emoji | Colour | Rationale |
|---|---|---|---|
| New | ⚪ | `(0.75, 0.75, 0.8)` grey | — |
| Learning | 🟡 | `(1.0, 0.82, 0.2)` amber | distinct hue from grey/blue |
| Remaster | 🟠 | `(1.0, 0.55, 0.1)` orange | distinct from both ends |
| Mastered | 🔵 | `(0.2, 0.65, 1.0)` blue | deliberately **not** green, to stay colourblind-safe |

Badges appear on trainer labels, in the Champion summary, and in the encounter panel text.

---

## 7. Champion

```gdscript
func is_champion_available(topic_id) -> bool:
    # every gym must be cleared; empty gym list is not enough
func champion_moveset(topic_id) -> Array:   # indices where mastery == MASTERED
func begin_champion_battle(topic_id) -> bool
func advance_champion() -> bool
```

- **Availability:** at least one gym and *all* gyms cleared.
- **Moveset:** all questions currently `MASTERED`. If none are mastered, `begin_champion_battle()`
  returns false and the panel shows "No Mastered questions yet…".
- **Queue:** `battle_champion_queue` holds `{topic_id, q_idx, boss}`, `boss` true only on the last
  entry. `advance_champion()` steps the index and applies the next question to
  `SessionManager.battle_*`, returning `false` when the queue is exhausted — at which point it sets
  `_champion_defeated[topic_id]` and emits `champion_defeated`.
- **Region complete:** `is_region_complete()` is simply `is_champion_defeated()`.

> **Soft-lock risk.** Clearing every gym on the first attempt can leave you with no `MASTERED`
> questions (a single win only takes a question to `LEARNING`), so the Champion stays locked with
> no in-game explanation beyond "Win rematches to master questions". See `known-issues.md` #6.

---

## 8. Feedback effects

`_spawn_gym_burst(pos)` fires when `_refresh_progress` observes a gym that was not cleared at build
time: 26 one-shot `CPUParticles2D` in green, auto-freed after 1.2 s. The cleared-state snapshot
(`_prev_cleared_gyms`) is taken in `_build_route` so loading an already-cleared save does not
replay the effect.

---

## 9. Known gaps

| Gap | Detail |
|---|---|
| Scene won't load | Missing `bot_lv5.png` ext_resource → parse error |
| No save on progress | Clear state and mastery persist only when something else triggers a save |
| Champion soft-lock | Availability and moveset requirements can deadlock |
| Gym ≠ trainer progress | Boss win clears the gym without clearing its trainers |
| No mini-map / gym tracker | The plan called for one; the HUD badge row is the only progress view |
| No region regeneration | The map is rebuilt from `pending_questions`; editing a saved topic changes the live map silently |
| Movement is flat | No diagonal sprite, no walk animation, no tilemap/obstacles |
