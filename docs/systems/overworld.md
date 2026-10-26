# Overworld, gyms and mastery

The campaign map: the 3D island in `assets/models/map.glb`, seen from an angled top-down camera,
with one gym per question type in the map's gym buildings, every one of the island's 15 houses a
Challenge House you walk into, and a Champion fight in the big gym that closes the region.

- **Houses:** `scripts/overworld/map_houses.gd` (`MapHouses.find()`, reads the houses out of `map.glb`)

- **Map logic:** `scripts/overworld/region_map.gd` → `scenes/overworld/region_map.tscn`
- **Player:** `scripts/overworld/player.gd` (the explorer: `assets/models/boy_explorer.glb` or
  `explorer_girl.glb`, picked in `explorer_picker.gd`)
- **Joystick:** `scripts/overworld/joystick.gd`
- **Progress + mastery state:** `scripts/autoload/session_manager.gd`
- **Question data:** `SessionManager.pending_questions` (see `review-session.md`)

Status: **Implemented; loads and plays on mocks.** Confirming an encounter opens `battle.tscn`,
which now loads. Houses, gyms and runs are described in
[`gameplay-structure.md`](gameplay-structure.md).

---

## 1. What it reads

The overworld is a *derived* view. It holds no map data of its own:

| Value | Source |
|---|---|
| Active topic id | `SessionManager.current_topic_id`, falling back to `editing_topic_id` |
| Questions | `SessionManager.get_pending_questions()` |
| Gyms | `SessionManager.get_gym_structure()` |
| Houses | `MapHouses.find(map)`: footprint, door and facing of each house in `map.glb` |
| Clear state | `SessionManager.is_house_cleared()` / `houses_cleared()` / `is_gym_cleared()` |
| Mastery | `SessionManager.get_mastery_state()` + `mastery_badge()` |
| Champion state | `SessionManager.is_champion_available()` / `is_champion_defeated()` / `champion_moveset()` |

If `pending_questions` is empty (direct scene run), `region_map.gd` `_ready()` seeds a two-question
`topic_preview` so the route still renders.

---

## 2. Houses and gyms

`get_gym_structure()` returns one entry per question type, `[{type}]` in GymSlot order (Identification,
Essay, Multiple Choice), as soon as the topic has a question; the runs fill themselves from the
questions ([`battle.md`](battle.md) §1).

- **Every house is a Challenge House** (Easy; 10 MC, 5 ID or 5 Essay). The island has 15, so each type
  gets 5: `_assign_types()` gives each house to the nearest gym that still has room (`ceil(15 / 3)`),
  so a type's houses cluster around its gym. Each house is its own run with its own first-clear
  bonus and stars, and starts at a different point of the question pool (its number is the
  `variant` passed to `begin_run()`), so two houses of one type do not play the same items.
- A **Gym** (Medium, 20 / 10 / 10) at the slot's `entrance` opens once **any** house of its type is
  cleared. The other houses stay open for practice and their first-clear pay.
- The Champion Gym (all three types, 40 items) opens once all three gyms are cleared.

### Finding the houses

`map.glb` merges its houses by material: one `House_Foundation` mesh, one `Door` mesh and so on, with no
node per house. `MapHouses.find()` rebuilds them at startup:

1. One box per `House_Foundation` triangle, merged while boxes overlap: one cluster per house (15).
2. The `Door` triangles within 0.5 of a footprint are its door. A door is a thin slab, so it faces
   along its thin axis, away from the middle of the house.
3. Sorted north to south, then west to east, giving ids `h1`..`h15` that stay put between runs (they
   are the save keys, so re-exporting `map.glb` with houses moved or added re-deals them).

The footprint measured this way matches the walls and roof to within 0.06.

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
├── GymSlot1          GymSlot (gym_slot.gd) for gyms[0]: Entrance (13.5, 0, 5.0), Gym2 door clips
├── GymSlot2          gyms[1]: Entrance (−14.2, 0, −5.7), Gym3 door clips
├── GymSlot3          gyms[2]: Entrance (−15, 0, 9), no door
├── ChampionSlot      GymSlot: Entrance (−5.2, 0, −6.8), the big `Gym` door clips
├── Trainers          the 15 house triggers, filled at runtime (the name is historical)
├── Gyms              the gym and Champion triggers, filled at runtime
├── Kuiz              Node3D (kuiz_follower.gd): kuiz.glb, 0.6 tall, following the Player
├── Player            CharacterBody3D (player.gd), floating motion, capsule r 0.22 h 0.9
│   ├── Explorer      instance of assets/models/boy_explorer.glb (Idle / Walk / Run looped);
│   │                 player.gd swaps in explorer_girl.glb when she is picked
│   └── Camera3D      (0, 7, 4.7), pitched −54°, fov 40 horizontal (keep width, portrait)
└── HUD               BackButton (round, top-left), QuestCard (task chips built in code), Minimap
                      (minimap.gd), Objectives (bullet list beside it), Joystick (bottom-left), StudyButton
                      (bottom-right icon card, opens the Flashcard Sanctuary and returns here),
                      EncounterPanel
```

**Where things go.** Every gym is a `GymSlot` node in `region_map.tscn`, listed in the root's
`gym_slots` export in question-type order, plus `champion_slot` for the Champion. `gyms[0]` uses
`GymSlot1` (the blue building by the south road), `gyms[1]` `GymSlot2` (orange, west), `gyms[2]`
`GymSlot3` (no building, so no door clips), and the Champion `ChampionSlot` (the big red `Gym`,
north). A slot's `Entrance` marker is where its trigger stands (0.8 in front of the double door for
the buildings), and its `door_open_clip` / `door_close_clip` are the map's own animation names,
played as the explorer walks in and out. Move a marker in the editor to re-route; add a slot to the
list for a fourth gym. Triggers come from `encounter_trigger.tscn` and the clear burst from
`gym_burst.tscn`, both exported on the root.

**Triggers.** Each is an `Area3D` on mask 4 (the player's layer) with a billboard `Label3D` (Josefin
Bold, Deep Slate outline, drawn over geometry). Every node is created at runtime, and rebuilding
clears both roots first.

| Trigger | Shape | Label |
|---|---|---|
| House | **the house itself**: bumping into it (below) opens the panel; a box of the footprint grown by `house_margin` (0.6) only opens the doorway and re-arms the house | the type and `Easy` or its stars, 2.6 up; shown only within `house_label_near` (4.0) of the explorer, so 15 labels do not crowd the screen |
| Gym | cylinder r 0.7 at the slot's `Entrance` | `GYM n` / `LOCKED` / stars, and the type |
| Champion | cylinder r 0.7 | `CHAMPION` and `LOCKED` / `FIGHT!` / `DOWN` |

**Walking into a house.** `_physics_process` reads the explorer's slide collisions each frame: a contact
point within `house_contact` (0.35) of a house's footprint (its walls, the windows that stick out of
them, its door) opens that house's panel. An invisible box around the house would not do: windows,
trees and a lamp post stop the explorer short of any thin box on 13 of the 60 sides (the first
version's bug), but they cannot hide the bump itself. Walking along a street past a house opens
nothing, since there is no contact. Closing a house's panel shuts that house (`_dismissed_house`) until
the explorer leaves its 0.6 box, so leaning on the wall does not reopen it every frame. Checked
headless by pushing the explorer at every house from all four sides: every house opens, from at
least three sides each (the misses are the narrow gaps between the h1/h2, h9/h10 and h11/h15 pairs,
where the neighbour is bumped first). Each house also carries a bobbing
`icon_trainer.svg` over its roof in its type's colour (Identification teal, Essay lilac `8D82A8`,
Multiple Choice amber), faint once cleared: the icons mark the houses from afar.

### Entering a building (houses and gyms alike)

The house plays the part the gyms' animated doors play:

1. **Walk up.** Touching a gym trigger plays its door-open clip (and door-close on leaving). Coming near
   a house "opens" its door: a dark doorway panel (`DOORWAY` `1E2829`, the door's own size, just in front
   of it) unfolds from zero width over 0.25 s, and folds shut again when the explorer walks away. The
   houses have no door animation of their own because `map.glb` merges all their doors into one mesh.
2. **The panel.** The encounter panel opens (§4) and the explorer stands still.
3. **Go inside.** On confirm the explorer walks through the doorway (`player.walk_into()`, 0.55 s, no
   collision): to the house's door when it touched the house on the door's side, or to the midpoint
   of a gym's double door (`<clip base>_Left` / `_Right` in the map). Then the screen fades to off-white
   (`FADE_SEC` 0.35) and the battle loads. Touching a house on another side, or GymSlot3 (no building),
   it only fades.
4. **Come back out.** The map remembers the doorway (`_return_to`, a static, so it survives the scene
   change): back from the battle, the explorer stands where it touched the house (a spot it could
   reach, unlike the door of a house with a tree in front) or just outside the gym, facing away from
   it, as the screen fades in. Otherwise (first visit, GymSlot3) it starts at the spawn.

**Collision.** `map.glb` ships none, so `_add_collisions()` builds a trimesh body per mesh, by name:

| Layer | Meshes | Used for |
|---|---|---|
| 1, ground | roads, grass blocks, sand, foundations, door steps, gym plinths, courts and paths, gym interior floors | the explorer's height only |
| 2, obstacles | house walls, windows, doors; gym walls, glass, trim, signs, bands, interior back walls; tree trunks and canopies; lamp poles; rocks | blocking |
| none | water, seabed, foam, roofs, chimneys, flags, domes, lamp glow, court lines, the gym door leaves | — |

**Movement** (`player.gd`). The joystick (or arrows/WASD through `ui_*`) gives a direction in screen
axes, mapped to the ground plane (up is −z). Below 75 % deflection the explorer walks at 1.8 u/s
with `Walk`; beyond it, runs at 2.8 u/s with `Run` (the clips were timed for 2.2 / 4.2, so they
play at 0.82× / 0.67× to keep the feet in step); at rest, `Idle` (0.15 s blends). The body moves
flat against layer 2 only, then a ray onto layer 1 sets its height, so the 0.15 grass curbs and
plinths never block it. A step whose ground is missing or below −0.05 (the water surface is −0.07)
is undone, so the beach stops at the waterline. The `Explorer` model turns smoothly to face the way
it moves. `locked` freezes it while an encounter panel or the explorer picker is open.

**Kuiz** (`kuiz_follower.gd`). Kuiz follows the explorer like a partner in a Pokémon game: a
0.6-unit `kuiz.glb` dressed as at home and in battle (ink outline, thicker at this size, vertex
colours, self-lit parts; `Antenna_*` tracks off), playing `Idle` and floating 0.32 above the
ground with a gentle bob. The explorer drops a breadcrumb every 0.08 units it moves; Kuiz heads for
the point 0.85 back along that trail, so it rounds corners the way the explorer did instead of
cutting through walls, catching up smoothly (it trails a little further while running). It faces
where it is going and, once the explorer stops, turns to face them. It has no collision and stays
off the minimap. `region_map.gd` places it just behind the explorer at the spawn.

**Explorer** (`explorer_picker.gd`). Each visit to the map from the worlds list starts with a
"Choose your explorer" card over the map: a live 3D preview of each explorer (its own small
world, idling; the chosen one cheers and gets a teal border) and **Let's go!**. The pick is
`GameState.explorer` (`"boy"` or `"girl"`, saved, v11) and `player.set_explorer()` swaps the
model; both share the same rig, size (about 1 unit tall) and clips. `GameState.explorer_picked`
(memory only) skips the card when coming back from a battle or flashcards; opening the worlds
list clears it.

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

**Portrait.** The map is portrait like every other screen (720×1280; the camera keeps the width,
`keep_aspect` = width, fov 40). The landscape mode, its rotate-your-phone cards
(`rotate_prompt.gd`) and the minimap beside the top bar were removed.
**Music:** entering the map crossfades to its own route theme (`MusicManager.play_overworld()`,
`music/overworld.wav`), which keeps playing through battles; the session list, flashcards and home
crossfade back to the home loop.
**Minimap** (`minimap.gd`). A 200 px Warm Off-White frame at the left, under the quest card and next pill, (Deep Slate 3 px
outline, rounded, soft shadow, like home's HUD pills) showing the whole island from straight above.
A 206 px `SubViewport` shares the map's `World3D`; its orthographic camera sees only layer 11,
which `_ready()` adds to every mesh in `Map`, so the explorer, trigger labels and weather stay out.
It is framed on the island's bounds, leaving out the water and seabed planes (wider than 150 units,
they run to the horizon but are still drawn). The picture is rendered **once**
(`UPDATE_ONCE`), so it costs one small extra render per visit; it keeps the season's lighting from
that moment. Dots are drawn in 2D every frame on top: the explorer (teal on off-white), trainers
(small off-white on slate), gyms (amber) and the Champion (coral), placed with the minimap
camera's `unproject_position()`.

**Joystick** (`joystick.gd`). A 320 px square at the bottom-left; base radius 120, knob 52, dead zone
15 %. Touch reaches it as emulated mouse events, so one finger drives it; the knob springs back on
release. Drawn with `_draw()` in Deep Slate, Warm Off-White and Muted Teal, so it needs no assets.

---

## 4. Encounter panel

One shared `PanelContainer` (`HUD/EncounterPanel`) is reconfigured per encounter. Walking into an
`Area3D` sets `_pending_encounter` and fills the title, body (items, tier, minutes, Kuiz readiness)
and action button.

| Encounter | `_pending_encounter` | Button |
|---|---|---|
| House | `{kind: "house", gym, house}` | `Go inside` / `Replay` → `begin_run(topic, "house", type, house id, house number)` |
| Gym (a house of its type cleared) | `{kind: "gym", gym}` | `Enter Gym` / `Replay` → `begin_run(topic, "gym", type)` |
| Gym (none cleared yet) | same | `Locked` (disabled); the text points at the type's icons over the roofs |
| Champion (ready or crowned) | `{kind: "champion"}` | `Challenge Champion!` / `Replay` → `begin_run(topic, "champion")` |
| Champion (locked) | `{}` | `Locked` (disabled) |

A house's panel is titled `Challenge House · <type>` (with its stars once cleared) and adds how many
of that type's houses are cleared, and that clearing one opens the gym. Confirming hides the panel
and plays the entrance (§3 *Entering a building*) before `change_scene_to_file()`.

---

## 5. Clear state

| Store | Key | Set by |
|---|---|---|
| `_cleared_houses` | `"<topic_id>:<gym_type>#<house_id>"` | `report_run()` on a house win |
| `_cleared_gyms` | `"<topic_id>:<gym_type>"` | `report_run()` on a gym win |
| `_champion_defeated` | `topic_id` | `report_run()` on a Champion win |
| `_best_stars` | `"<kind>:<topic_id>:<run key>"` (run key: the type, or `type#house_id`) | best of 0–3 per run |

A run is cleared by surviving every item; stars (accuracy) only scale the pay. A gym opens with the
first house of its type (`houses_cleared(topic, type) > 0`), the Champion with all three gyms.
`overworld_progress_changed` fires on each clear. A v13 key without a house id still counts toward its
type, so an older save keeps its open gyms.

The HUD's quest card (`_refresh_progress`) shows Houses cleared of 15 with a bar, a badge per cleared
gym, and the Champion as Locked / Ready! / Crowned. The bullet list beside the minimap shows the next
three steps (`_objectives()`): "Enter a house marked <type>" for each type whose gym is still shut, the
gyms, the Champion, and then "Clear the other houses (n left)". Layout in
[`ui-and-assets.md`](../ui-and-assets.md) §2 `region_map.tscn`.

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

Badges colour the mastery state in the Flashcard Sanctuary and the encounter panel text.

---

## 7. Champion

- **Availability:** `is_champion_available()` — at least one gym and *all* gyms cleared.
- **The run:** one 40-item run (20 MC, 10 ID, 10 Essay) against the toughest foe, built by
  `build_run(topic, "champion", "")` ([`battle.md`](battle.md) §1). It prefers Hard questions and falls
  back to the rest; the old Mastered-only moveset and the question-by-question gauntlet are gone.
- **Region complete:** `is_champion_defeated()`, set by `report_run()` on a win.

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
| Minimap is a still picture | Rendered once per visit, so door animations and later light changes do not show in it; only the dots move |
| No region regeneration | The map is rebuilt from `pending_questions`; editing a saved topic changes the live map silently |
| Fixed layout | Three gyms at most (a fourth type needs a fourth `GymSlot`); the third has no building, and the slot markers are hand-placed for this map only |
| One-finger joystick | Touch is read as emulated mouse, so the stick and a second finger cannot act at once |
