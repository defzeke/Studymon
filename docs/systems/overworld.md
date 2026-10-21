# Overworld, gyms and mastery

The campaign map: the 3D island in `assets/models/map.glb`, seen from an angled top-down camera,
with one gym per question type in the map's gym buildings, a trainer per question on the road
leading to its gym, and a Champion fight in the big gym that closes the region.

- **Map logic:** `scripts/overworld/region_map.gd` → `scenes/overworld/region_map.tscn`
- **Player:** `scripts/overworld/player.gd` (the explorer, `assets/models/boy_explorer.glb`)
- **Joystick:** `scripts/overworld/joystick.gd`
- **Progress + mastery state:** `scripts/autoload/session_manager.gd`
- **Question data:** `SessionManager.pending_questions` (see `review-session.md`)

Status: **Implemented; loads and plays on mocks.** Confirming an encounter opens `battle.tscn`,
which now loads. Gym tiers and the boss lock are Phase 3 of
[`gameplay-structure.md`](gameplay-structure.md).

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

`get_gym_structure()` buckets question indices by `type`, preserving first-seen order:

```gdscript
[
  {"type": "identification", "question_indices": [0, 1, 2],
   "trainer_indices": [1, 2], "boss_index": 0},     # Q1 easy, Q2 medium, Q0 hard
  {"type": "essay", "question_indices": [3], "trainer_indices": [], "boss_index": 3}
]
```

So **a gym is a question type**, not a topic or a chapter. At most one gym per type (Identification,
Essay, Multiple Choice) per topic, regardless of question count. Re-typing a question in the
categorizer moves it between gyms.

Inside a gym, questions are ranked Easy to Hard (ties in question order). The **last** one is the
boss; the rest are the trainers, in that order along the road: the Easy trainers stand nearest the
start of the road, the hardest nearest the gym. A gym with one question has no trainers, so its boss
is open at once.

---

## 3. The island, the route and the explorer

```text
RegionMap            Node3D (region_map.gd)
├── WorldEnvironment  sky-blue background, ambient colour 0.7
├── Sun               DirectionalLight3D with shadows (30 units)
├── Map               instance of assets/models/map.glb
├── Season            Node3D (season.gd): the real-world season, its weather particles
├── MapCollision      Node (map_collision.gd): builds the island's collision; keyword lists and layers are exports
├── Spawn             Marker3D (−2, 0, 9), on the south road
├── GymSlot1          GymSlot (gym_slot.gd) for gyms[0]: Entrance (13.5, 0, 5.0), trainers From (2, 0, 9) → To (12.5, 0, 9), Gym2 door clips
├── GymSlot2          gyms[1]: Entrance (−14.2, 0, −5.7), From (−9, 0, 7.5) → To (−9, 0, −0.5), Gym3 door clips
├── GymSlot3          gyms[2]: Entrance (−15, 0, 9), no door; From (−4, 0, 9) → To (−12, 0, 9), walking toward the gym
├── ChampionSlot      GymSlot: Entrance (−5.2, 0, −6.8), the big `Gym` door clips
├── Trainers, Gyms    filled at runtime
├── Player            CharacterBody3D (player.gd), floating motion, capsule r 0.22 h 0.9
│   ├── Boy           instance of assets/models/boy_explorer.glb (Idle / Walk / Run looped)
│   └── Camera3D      (0, 7, 4.7), pitched −54°, fov 40 across the width
└── HUD               TopBar, HintLabel, Joystick (bottom-left), StudyButton (bottom-right,
                      opens the Flashcard Sanctuary and returns here), EncounterPanel
```

**Where things go.** Every gym is a `GymSlot` node in `region_map.tscn`, listed in the root's
`gym_slots` export in question-type order, plus `champion_slot` for the Champion. `gyms[0]` uses
`GymSlot1` (the blue building by the south road), `gyms[1]` `GymSlot2` (orange, west), `gyms[2]`
`GymSlot3` (no building, so no door clips), and the Champion `ChampionSlot` (the big red `Gym`,
north). A slot's `Entrance` marker is where its trigger stands (0.8 in front of the double door for
the buildings), and its `door_open_clip` / `door_close_clip` are the map's own animation names,
played as the explorer walks in and out. A gym's trainers are spread between the slot's `From` and
`To` markers at `frac = (i+1)/(n+1)`. Move a marker in the editor to re-route; add a slot to the
list for a fourth gym. Nothing is looked up by node name. Triggers come from
`encounter_trigger.tscn` and the clear burst from `gym_burst.tscn`, both exported on the root.

**Triggers.** Each is an `Area3D` with a cylinder (trainers r 0.45, doors r 0.7) on mask 4 (the
player's layer), and a billboard `Label3D` (Josefin Bold, Deep Slate outline, drawn over geometry):
`T<N>` over trainers, `GYM <n>` / `BADGE` plus the type over gyms, `CHAMPION` plus
`LOCKED` / `FIGHT!` / `DOWN` over the Champion. A trainer also has a flat disc in its mastery colour
(section 6); cleared trainers are darkened. Every node is created at runtime, and rebuilding clears
both roots first.

**Collision.** `map.glb` ships none, so `_add_collisions()` builds a trimesh body per mesh, by name:

| Layer | Meshes | Used for |
|---|---|---|
| 1, ground | roads, grass blocks, sand, foundations, door steps, gym plinths, courts and paths, gym interior floors | the explorer's height only |
| 2, obstacles | house walls, windows, doors; gym walls, glass, trim, signs, bands, interior back walls; tree trunks and canopies; lamp poles; rocks | blocking |
| none | water, seabed, foam, roofs, chimneys, flags, domes, lamp glow, court lines, the gym door leaves | — |

**Movement** (`player.gd`). The joystick (or arrows/WASD through `ui_*`) gives a direction in screen
axes, mapped to the ground plane (up is −z). Below 75 % deflection the explorer walks at 2.2 u/s
with `Walk`; beyond it, runs at 4.2 u/s with `Run`; at rest, `Idle` (0.15 s blends). The body moves
flat against layer 2 only, then a ray onto layer 1 sets its height, so the 0.15 grass curbs and
plinths never block it. A step whose ground is missing or below −0.05 (the water surface is −0.07)
is undone, so the beach stops at the waterline. The `Boy` model turns smoothly to face the way it
moves. `locked` freezes it while an encounter panel is open.

**Seasons** (`season.gd`). The island follows the real-world season, from the device's local date,
on a Northern Hemisphere calendar (`season_for(month, day)`), so a season lasts for months and the
same date always gives the same one:

| Months | Season |
|---|---|
| Dec, Jan, Feb | Snowy |
| Mar, Apr, May | Sunny |
| Jun, Jul, Aug | Sunny, with a Rainy day every fourth day of the month (4th, 8th, …) |
| Sep, Oct, Nov | Autumn |

| Season | Light and sky | Foliage and grass | Weather around the explorer |
|---|---|---|---|
| Sunny | warm sun 1.15, sky blue | as authored | none |
| Rainy | grey sun 0.35, grey sky, fog 0.025 | darker, wetter greens (30 %) | 400 rain streaks, fast |
| Autumn | amber sun 1.0, warm sky | canopies 75 % toward Muted Amber, Soft Coral and two in-between tones; grass 45 % toward straw | 90 `leaf.svg` leaves drifting and spinning |
| Snowy | cool sun 0.9, pale sky, fog 0.015 | canopies 55 % and grass 85 % toward snow white | 300 snowflakes, slow |

The weather is one `GPUParticles3D` in world space, prewarmed so it is already falling on the first
frame. It is emitted through the whole volume the camera sees around the explorer (0.5–4.5 units
up, 14 wide, from 10 behind to 4 in front) rather than from above: at the camera's 54° pitch,
anything spawned higher only crosses the view right at the lens. Particle colours are sRGB
(`vertex_color_is_srgb`). Foliage is tinted on duplicated materials, because the imported ones are shared
with every later load. The `Environment` resource is also shared, so every field is set every time.
To drop a season, remove it from `Season` and `LOOKS`.

**Joystick** (`joystick.gd`). A 320 px square at the bottom-left; base radius 120, knob 52, dead zone
15 %. Touch reaches it as emulated mouse events, so one finger drives it; the knob springs back on
release. Drawn with `_draw()` in Deep Slate, Warm Off-White and Muted Teal, so it needs no assets.

---

## 4. Encounter panel

One shared `PanelContainer` (`HUD/EncounterPanel`) is reconfigured per encounter type. Walking into
an `Area3D` sets `_pending_encounter` and fills the title, body and action button.

| Encounter | `_pending_encounter` | Button |
|---|---|---|
| Trainer (uncleared) | `{kind: "trainer", q_index, gym}` | `Fight Trainer!` → `begin_battle(topic, q_idx, false)` |
| Trainer (cleared) | same | `Already Cleared` (disabled) |
| Gym boss (trainers cleared) | `{kind: "gym", gym, boss_index}` | `Fight Boss!` → `begin_battle(topic, boss_index, true)` |
| Gym boss (trainers left) | same | `Boss Locked` (disabled); the text says how many trainers remain |
| Gym (cleared) | — | `Badge Earned` (disabled) |
| Champion (region complete) | `{}` | `Crowned` (disabled) |
| Champion (locked) | `{}` | `Locked` (disabled) |
| Champion (ready) | `{kind: "champion"}` | `Challenge Champion!` → `begin_champion_battle(topic)` |

The boss is the gym's **hardest question** (the last one among ties) and is not also a trainer.
The Champion panel doubles as the pre-fight summary: it lists up to 6 of the Champion's questions
with mastery badges plus `...and N more.`, and says so when it fields every question because none
is Mastered yet.

Confirming an encounter hides the panel and does `change_scene_to_file("res://scenes/battle/battle.tscn")`.

---

## 5. Clear state

Two independent dictionaries, both keyed by strings:

| Store | Key | Set by |
|---|---|---|
| `_cleared_trainers` | `"<topic_id>:<q_index>"` | `mark_trainer_cleared()` after a win |
| `_cleared_gyms` | `"<topic_id>:<gym_type>"` | `mark_gym_cleared()` on a boss win |

A gym is cleared **only by its boss**, and the boss only opens once every trainer of that gym is
cleared (`gym_trainers_left()` is 0), so progress is strictly ordered. A boss win also marks the
boss question's own trainer key cleared, so it counts in `Trainers c/t`. `mark_trainer_cleared()`
emits `overworld_progress_changed` once. Saves made under the old rule (a gym cleared once all its
trainers were) keep their cleared gyms.

`get_progress(topic_id)` returns:

```gdscript
{"cleared": int, "total": int, "gyms_cleared": int, "gyms_total": int}
```

`total` is `pending_questions.size()` — **all** questions in the topic, not just the ones in the
current gym.

HUD strings (`_refresh_progress`):

- `progress_label`: `Trainers c/t  CROWNED | CHAMP-READY | CHAMP-LOCKED`
- `badges_label`: `Gyms g/G [X][ ]`

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
- **Moveset:** the `MASTERED` questions, **falling back to every question** when none is mastered,
  sorted Easy to Hard (ties in question order) so the last step, the 150 HP boss, is the hardest.
  `mastered_indices()` gives the Mastered subset.
- **Queue:** `battle_champion_queue` holds `{topic_id, q_idx, boss}`, `boss` true only on the last
  entry. `advance_champion()` steps the index and applies the next question to
  `SessionManager.battle_*`, returning `false` when the queue is exhausted — at which point it sets
  `_champion_defeated[topic_id]` and emits `champion_defeated`.
- **Region complete:** `is_champion_defeated()`.

---

## 8. Feedback effects

`_spawn_gym_burst(pos)` fires when `_refresh_progress` observes a gym that was not cleared at build
time: 26 one-shot green `CPUParticles3D` spheres at the gym door, freed when they finish. The cleared-state snapshot
(`_prev_cleared_gyms`) is taken in `_build_route` so loading an already-cleared save does not
replay the effect.

---

## 9. Known gaps

| Gap | Detail |
|---|---|
| No mini-map / gym tracker | The plan called for one; the HUD badge row is the only progress view |
| No region regeneration | The map is rebuilt from `pending_questions`; editing a saved topic changes the live map silently |
| Fixed layout | Three gyms at most (a fourth type needs a fourth `GymSlot`); the third has no building, and the slot markers are hand-placed for this map only |
| One-finger joystick | Touch is read as emulated mouse, so the stick and a second finger cannot act at once |
