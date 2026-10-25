# Tasks

Where the work stands. Short on purpose — this is a **register**, not a backlog.

> **Derived.** This file records what is in flight and nothing else. Every open question lives in the
> doc that owns it, and **those docs win** if the two disagree. See [`rules.md`](rules.md) §2. Do not
> let a second status list grow here.

Last updated: 2026-10-26.

## In flight

**Animated logo, detailed rooms, map music, stat cards — uncommitted.** The loading logo is the
animated `loading_screen_logo.gif`, decoded into a keyed sprite sheet (the old `logo.png` is gone). The four rooms have
more detail. The region map has its own route theme (`overworld.wav`), crossfading in and out and
playing through battles. Tapping a stat gauge shows its numbers like the level card. Details in
[`ui-and-assets.md`](ui-and-assets.md) §1, §2 and §4.

**Dirt decals, room art, level card, music crossfade, smooth logo — uncommitted.** Kuiz's dirt is
projected onto its shell (decals) instead of floating stickers. Settings drops the AI plan card.
The Study Room's bookshelf is even and its desk stands behind the charging arch; the Maintenance
Bay's wrench is a proper open-end wrench. Tapping the level pill shows the level's numbers. The
loading music crossfades into the home loop, and the loading logo is rebuilt at 2× with smooth
edges. Details in [`ui-and-assets.md`](ui-and-assets.md) §1, §2 and §4.

**Battery health, closet tabs, endless levels, happier music — uncommitted.** The check-up tablet
shows battery health (capacity, worn by charging; a worn battery drains energy faster) and sells a
new battery for 30 crystals, which minigame rounds now earn. The closet has Head, Face and Body tabs,
one costume worn per tab (five new costumes). Levels never cap (Level 5 still unlocks the campaign).
A tired Kuiz only dozes in the Study Room. The Study Room's items keep their look while Kuiz walks
out, the Playroom ball sits in the middle of the dock, and the home music is a bright, bouncy loop.
Save v10. Details in [`ui-and-assets.md`](ui-and-assets.md) §2 and
[`companion-care.md`](systems/companion-care.md).

**Petting, dirt, costumes, own audio — uncommitted.** Hold or stroke Kuiz to pet it. The
Maintenance Bay dock adds a check-up tablet (battery, frame, cleanliness, fuel) and a towel: Kuiz
now gets dirty over time (spots and scratches on its head, `CompanionState.dirt`) and is scrubbed
clean. The Playroom dock adds a closet of six costumes worn on Kuiz's head (`kuiz_look.gd`). The
kitchen arrows skip foods with none left. All music and sound effects are our own (synthesised
offline). Save v9. Details in [`ui-and-assets.md`](ui-and-assets.md) §2 and §4.

**Minigames, moods, dock, landscape map — uncommitted.** The Playroom dock has a Games button with
two minigames: Kuiz Keeper (swipe penalties past Kuiz in goal) and Sky Jump (bounce Kuiz up
platforms through Sky, Space, Galaxy and Deep Space, with trampolines, rockets, timed and moving
platforms and meteors), each round counting as play care. The Playroom ball waits in the dock.
Kuiz rests in a mood when a stat is low (sick, hungry, tired, sad), and a dozing Kuiz stays in its
room until tapped awake. The dock is a table the items stand on, and the dock/HUD icons are drawn
at 2.5× so they stay sharp. The region map is landscape 16:9 with a top-down minimap and asks the
player to turn the phone each way. Details in [`ui-and-assets.md`](ui-and-assets.md) §2 and
[`overworld.md`](systems/overworld.md).

**Home HUD, top room arrows — uncommitted.** The top of home has a level pill (badge + XP bar),
four stat gauges (Hunger, Energy, Mood, Health) and a crystal pill (the currency,
`GameState.crystals`, saved; nothing earns it yet). `CompanionState` gained `hunger` and `health`;
food, the screwdriver and the ball now call `care()` (`feed`, `fix`, `play`) and charging refills
energy. Save v8. The room arrows left the bar for the top, either side of the room sign. Details in
[`ui-and-assets.md`](ui-and-assets.md) §2 Home HUD.

**Model sounds, gem fix, study icons — uncommitted.** Kuiz's sounds are back, made in code like
its artifact makes them (`scripts/audio/synth.gd`, `clip_voice.gd`, `kuiz_voice.gd`; no sound
files): every clip fires the artifact's cues, so each tutorial line's clip carries its sounds, plus
hop/jump/land/whee on moves. The battle's Broken Bot (`robot_1.glb`) charges, blasts and powers
down the same way (`broken_bot_voice.gd`). The forehead gem no longer tips into
the head (`Antenna_*` tracks disabled). The Study Room bar uses new temporary icons
(`ui/icon_charge|upload|settings.svg`) as bare icons; the fridge moved from the kitchen art into
the kitchen bar, and the kitchen counter is back. Details in
[`ui-and-assets.md`](ui-and-assets.md) §2.

**Home loop — committed (`8c11f6e`).** After the tutorial's last line a tap starts `home.gd` (in
`peek.tscn`): a bottom bar walks Kuiz between the four rooms. Study Room: Charge (lights off,
`State_Charging`, `Wake_Up` on lights on), Play (new topic → upload screen), Settings (now with
music/sound volume and large text, save v5). Maintenance Bay: hold the screwdriver over Kuiz.
Data Kitchen: drag six foods to Kuiz, buy more at the fridge (free; no currency yet). Playroom:
fling the ball, Kuiz watches. Settings and the topic list now return home. New temporary art in
`assets/sprites/props/` and `ui/arrow.svg`. Details in [`ui-and-assets.md`](ui-and-assets.md) §2
Home.

**Gameplay structure Phases 0–3 — committed.** Battles load (`battle.tscn` no longer references
`bot_lv*.png`), progress saves after battles and topic confirmation (`SaveManager.save_progress()`),
questions carry `difficulty` (and `distractors` for Multiple Choice) with save `"v": 6`, the mock
extractor produces all three types and tiers, the categorizer edits them, battles scale by tier,
essays alone use the grading quota, and a third gym (Multiple Choice) stands at a marker on the
south road. Phase 3: trainers climb Easy → Hard along each road, the boss is the gym's hardest
question and stays locked until its trainers are beaten, gyms clear only through the boss (#17), and
the Champion falls back to every question, Easy to Hard (#6). Contract:
[`systems/gameplay-structure.md`](systems/gameplay-structure.md).

**3D battle arena, encounters and battle SFX — committed (`c3d3688`–`b87b51c`).** `battle.tscn` now
stages Kuiz and the foe in a 3D arena (`scripts/battle/arena_stage.gd`: intro, strikes, hurt/win
clips, `battle_backdrop.svg`), the overworld gained `encounter_trigger`, `gym_slot`, `map_collision`
and `gym_burst`, and `battle.gd` plays ten `sfx_*.wav` cues through `MusicManager.play_sfx_layered()`.
The old 2D care room (`main.tscn`), `hud_strip`, `companion_rig` and their SVGs are deleted. Not yet
played through end to end after the restructure. The docs were swept for the deleted scenes on
2026-10-24 (`known-issues.md` #3, #4, #12, #16 are gone with them).

**Flashcard Sanctuary (Phase 4) — committed.** `flashcards.tscn`: untimed review of a topic with
Again / Hard / Easy. Easy lifts New or Remaster to Learning (never Mastered); each lifted card pays
+1 XP and +2 focus once, a finished deck +3 mood. Opened from the island's Study button and from a
Cards button on each session-list row. Details in [`ui-and-assets.md`](ui-and-assets.md).
**Loading music — committed.** `splash.tscn` starts `MusicManager.play_loading()`, which begins
`loading.mp3` at 1 s and fades it in over 1 s; it runs through `loading.tscn`, and `peek.tscn`
switches back to `main room.mp3`. `assets/audio/loading.mp3` and its `.import` are untracked.

## Blocked

| Work | Blocked by |
|---|---|
| Pricing the fridge, and gating Play at Level 5 | Waiting on the design: what the shop charges (minigames earn crystals and a new battery costs 30 for now), and whether Play waits for Level 5 |
| Any real backend call | Issue #7 (endpoints disagree) and issue #2 (auth header is a redaction placeholder) |

## Next

P0/P1 first; each item's evidence and fix live in [`known-issues.md`](known-issues.md).

| Order | Item | Why now |
|---|---|---|
| 1 | #8 / #5 Care input that earns XP, once the top-bar design lands | Makes Level 5 reachable and gives the gate back |
| 2 | #2 `Bearer` header + a way to set `auth_token` | Required before `MOCK` can flip |
| 3 | #9 Standardise the job envelope (or add a `grade_result` signal) and handle non-2xx | Real responses are dropped today |

**Future, not started: Phase 5**, the real backend and the App Store / Google Play launch. The game
stays on mocks until the maintainer decides to begin. The researched plan, store requirements and
mock-first prep are in [`launch-plan.md`](launch-plan.md); items 4 and 5 above are part of it.

Hygiene, after the slice plays:

| Item | What |
|---|---|
| #13 | Emit `stats_changed` at ~5 Hz or only on change |
| #14 | Debounce the save instead of one full write per tap |
| #20 | Add a headless smoke-test script / CI |

## Needs a decision

1. **Backend contract.** Client `/battle/grade` + job envelope, or `backend/README.md`'s `/grade` +
   `/extract`? Pick the client shape (it already consumes it) and rewrite the backend doc (#7).
2. **Auth scope.** Is login part of the vertical slice, or does the client stay anonymous while
   `MOCK` is on (#2)?
3. **Codex.** The remote branch `feat/remove-codex` suggests it is being cut. Remove the button and
   the `codex` save field, or keep it?
4. **Save cadence.** Event-driven saves, a dirty flag with a timer, or save on app pause only (#14)?
5. **Hosting (when Phase 5 starts).** Recommended: FastAPI on Cloud Run or Fly.io + Supabase. See
   [`launch-plan.md`](launch-plan.md) §1.
6. **Purchases timing (when Phase 5 starts).** Recommended: free launch with server-side quotas,
   a premium plan later. See [`launch-plan.md`](launch-plan.md) §1.

## Done

- **2026-10-21** — repository layout, no behaviour change: all autoloads in `scripts/autoload/`,
  the theme in `assets/theme/`, boot flow and HUD widgets in `ui/boot/` and `ui/widgets/`, boot art
  in `assets/sprites/boot/`, `leaf.svg` in `assets/sprites/effects/`, `quizmon-build-plan.md` in `docs/`.
- **2026-10-21** — cleanup, no behaviour change: removed unused assets (`hmm.mp3`, the run-cycle and
  `loading_logo` PNGs, three companion SVGs), the five planning-stub READMEs, never-called helpers,
  `GameState.current_topic_id` (#18), the `campaign_unlocked` signal and the `# ponytail:` tags.
- **2026-10-21** — first-run tutorial and temporary rooms, the new `kuiz.glb` clips and prop
  hiding, the temporary Study Room art, the 3D island overworld with joystick explorer and random
  seasons (`5b3c22a`).
- **2026-10-21** — boot flow polish: splash → loading → peek handoffs on white with threaded
  loads, the loading screen's leaves, floating logo, striped bar and tips, the 3D `peek.tscn` with
  the artifact's look, and the text intro removed (`8db69c9`).
- **2026-10-20** — docs set written; root README corrected; `AGENTS.md`, `rules.md`, `skills.md`,
  `tasks.md`, `glossary.md`, and the Ponytail skill added; splash intro and loading-screen art
  (`fb90236`).
- **2026-10-20** — `godot_mcp` addon and its stale autoload removed (`0806d87`).
- **Phases 8–10** — per-question mastery with 7-day decay, gym/champion progression, battle juice,
  Rooms/night mode/table icons, Josefin Sans theme, the free-tier quota gate, and the reviewer
  extractor (see [`build-plan-status.md`](build-plan-status.md)).
