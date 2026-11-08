# Tasks

Where the work stands. Short on purpose — this is a **register**, not a backlog.

> **Derived.** This file records what is in flight and nothing else. Every open question lives in the
> doc that owns it, and **those docs win** if the two disagree. See [`rules.md`](rules.md) §2. Do not
> let a second status list grow here.

Last updated: 2026-11-08.

## In flight

Nothing intended is uncommitted. The working tree holds an accidental Godot 4.6 editor downgrade
(`project.godot` `config/features` back to `"4.6"`, three keys dropped from `explorer_girl.glb.import`
and `map.glb.import`); discard it and open the project only in 4.7.2.

Everything below **Done** is on `world-assets` and `origin/dev` (PR #9 merged into `dev` on
2026-11-02); the two 2026-11-06 commits are not yet on `origin/world-assets`, and nothing has been
merged to `main`.

Still unverified across the committed work: none of the 2026-10-26 → 11-06 batches has been opened in
the editor GUI or played on a phone; checks were headless (79 Godot checks, 15 `backend/tests`), the
scene gates, and a windowed scratch harness on Windows for the 11-06 batches. The houses have no door-swing animation (the glb merges all doors; needs a Blender
split).

## Next: before the store release

| Order | Item | Needs |
|---|---|---|
| 1 | Run `backend/evals/` with a real key (now also a Word and a photo reviewer), tune prompts, record cost in [`api-backend.md`](api-backend.md) §3; pick the model per route | an Anthropic key (about $2–3 a run) |
| 2 | Deploy the backend over HTTPS with rate limiting; set the workspace **monthly spend limit**; set `Api.RELEASE_URL` | a host (Cloud Run / Fly.io) |
| 3 | Host the privacy policy, terms and support pages; set the three URLs in `settings.gd` | a domain or static host |
| 4 | `export_presets.cfg` for Android (`.aab`, keystore out of git, **user-data backup on**) and iOS; **start Google's 14-day closed test** | developer accounts, a Mac or macOS CI for iOS |
| 5 | On real phones: pick a PDF, photo and .docx (issue #23), Export / Import a save, the whole loop | an Android phone and an iPhone |
| 6 | A real app icon (still Godot's default `icon.svg`), adaptive icon, iOS icon set | art |
| 7 | Privacy labels / Data safety, age rating 13+, screenshots, review notes with a sample reviewer | store consoles |
| later | Study reminders (needs a local-notifications plugin); App Attest / Play Integrity; Sentry; debounce saves (#14) | — |

**Phase 5**, the real backend and the App Store / Google Play launch, is partly built: the AI server
exists but has not met the real model or a host. The researched plan, store requirements and
mock-first prep are in [`launch-plan.md`](launch-plan.md); items 1–7 above are part of it.

Hygiene, after the slice plays:

| Item | What |
|---|---|
| #14 | Debounce the save instead of one full write per tap |
| #20 | Add a headless smoke-test script / CI |
| #22 | Find why the headless boot chain fails its threaded loads |

## Needs a decision

1. **Codex.** The remote branch `feat/remove-codex` suggests it is being cut. `CompanionState` still
   keeps `codex` / `codex_entry_added` and saves them, with no screen. Remove the data and the save
   field, or build the screen?
2. **Save cadence.** Event-driven saves, a dirty flag with a timer, or save on app pause only (#14)?
3. **Hosting.** Recommended: the stateless FastAPI gateway on Cloud Run or Fly.io. See
   [`launch-plan.md`](launch-plan.md) §1.

## Done

- **2026-11-06** — map, focus timer and battle polish (`19e5531`): a full Kuiz refuses food, the
  explorer picker opens first after the world intro, the map HUD as one top band, the minimap opens
  large, the settable focus timer with Kuiz reviewing, lullabies and refused navigation, a "Go home?"
  confirmation, the restyled battle and encounter panel, the explorer throwing Kuiz in, a simpler
  encounter pop-up, softer entrance sounds, battle music, and a mute for the map and battles
  (`adventure_music`).
- **2026-11-06** — transitions and restyles (`25f45d8`): boot music fades in, the Kuiz reveal after
  loading, the room sign's dropdown of the four rooms, the world intro (Kuiz leaves its house on Play,
  goes back in on the map's Back), Kuiz waddles on the island, the boy shows base colour only, the new
  Study icon, the restyled Worlds, Settings, World Builder and Flashcards, the slower white handoff
  after loading, the gear on the HUD, the focus timer on the table, a fix for the dark flash between
  scenes, and changing explorer from the map.
- **2026-10-29** — play-test fixes (`4dde4f1`): the intro asks only for the name; fridge food is
  priced (4–13 crystals); every closet costume is bought (40–250); each world keeps the explorer it
  picks; battles show only right or wrong during a run, with **Review answers** at the end; finishing
  below 70 % is a real defeat.
- **2026-10-29** — world slots, crystal economy, backups (`1c126b9`): 3 free world slots then 300
  crystals each; flat 25 per level-up, minigames capped at 60 a day; Export / Import save; photo,
  Word and PowerPoint reviewers in the reviewer's language; "More questions"; a daily study goal and
  streak; closet costumes unlock by level; the Study screen's focus timer; the Level 5 gate deleted
  (Play is open from the start). Contract: [`systems/monetization.md`](systems/monetization.md).
- **2026-10-29** — store readiness for a no-accounts free v1 (`0d1c4dc`): `POST /v1/extract` and
  `POST /v1/grade` on the study server, answer keys saved with the world, offline Multiple Choice /
  Identification checking, a per-request `HTTPRequest` + `job_id` (#7, #9), AI consent, the Settings
  legal links. Contract: [`api-backend.md`](api-backend.md), [`systems/battle.md`](systems/battle.md) §5.
- **2026-10-26** — editor-editable UI (`fbc382d`): the region map's quest chips and objective rows,
  `explorer_picker.tscn`, battle's gauge row, every flashcards style and the categorizer's question
  row are scene nodes, data rows copied from hidden templates. No gameplay change. Details in
  [`ui-and-assets.md`](ui-and-assets.md) §2.
- **2026-10-26** — Challenge Houses, Gyms, Champion runs, rewards (`4872cca`): fixed-length runs
  built by `SessionManager.build_run()`, 15 houses found by `MapHouses`, stars and first-clear
  rewards, care stats feeding battle. Contract: [`systems/battle.md`](systems/battle.md),
  [`systems/gameplay-structure.md`](systems/gameplay-structure.md) §3.2.
- **2026-10-26** — island UI (`d1b1eab`): Kuiz follows the explorer (`kuiz_follower.gd`), objective
  bullets beside the minimap, the quest card, the restyled Study screen, the explorer picker and
  `explorer_girl.glb`, the portrait map (rotate prompt removed), slower explorer, the weekly AI limit
  and `MonetizationState` removed. Details in [`systems/overworld.md`](systems/overworld.md) §3.
- **2026-10-26** — care room depth (`3be1f49`): animated logo, detailed rooms, map music, stat cards,
  dirt decals, level card, battery health, closet tabs, endless levels, petting, minigames (Kuiz
  Keeper, Sky Jump), moods, our own synthesised audio. Details in
  [`ui-and-assets.md`](ui-and-assets.md) and [`systems/companion-care.md`](systems/companion-care.md).
- **2026-10-24** — home HUD and model sounds (`3f1a39f`): level pill, four stat gauges, crystal pill,
  code-made Kuiz and Broken Bot voices, gem fix, study icons.
- **2026-10-22** — 3D battle arena, encounters and battle SFX (`c3d3688`–`b87b51c`); the old 2D care
  room and its rig deleted.
- **2026-10-21** — home loop (`8c11f6e`): four rooms after the tutorial, charge / tune-up / food /
  ball, Settings with volume and large text.
- **2026-10-21** — gameplay structure Phases 0–4 (`ea330ab`, `0e9b404`, `bf27b7a`): Multiple Choice,
  difficulty tiers, saving after battles, tier-ordered trainers, boss lock, Champion fallback, the
  Flashcard Sanctuary. Contract: [`systems/gameplay-structure.md`](systems/gameplay-structure.md).
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
