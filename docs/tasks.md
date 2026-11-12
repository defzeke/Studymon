# Tasks

Where the work stands. Short on purpose — this is a **register**, not a backlog.

> **Derived.** This file records what is in flight and nothing else. Every open question lives in the
> doc that owns it, and **those docs win** if the two disagree. See [`rules.md`](rules.md) §2. Do not
> let a second status list grow here.

Last updated: 2026-11-12.

## In flight

Uncommitted: **care pacing and the level-up notice.**
- Energy lasts an hour from full to low (25 %) on a new battery, faster on a worn one; below 25 % Kuiz
  cannot start a run or open flashcards until it charges ([`systems/companion-care.md`](systems/companion-care.md) §1).
- Dirt no longer builds with time or meals: only ball throws and minigames soil Kuiz.
- Battle HP follows readiness (all four home stats), not health alone ([`systems/battle.md`](systems/battle.md) §3).
- A **Level up!** notice on home, battle and flashcards (`ConfirmModal.level_up()`).
- The fridge's rows wrap their text, so they fit the panel.
- Time away counts: the stats decay for the time the game was closed or paused; Kuiz left charging
  charges instead (save field `charging`, [`data-model.md`](data-model.md)), and home reopens with Kuiz still
  asleep on the charger.
- The break's **Resume review** button, and the room dropdown opens under the review bar.
- The Study screen has no focus timer, and its progress line no longer shows Kuiz's focus.
- The map's music and explorer buttons sit in one column over Study, which has a new icon.
- Mood: a minigame round is its own care action, `game` (+25, was the ball's +8), each flashcard rated
  lifts it a little, and exploring the island lifts it. Decay is now minutes from full to low per stat:
  hunger 15, mood 20, focus 30, energy and health 60.
- The level-up party (`LevelUpModal`): jingle, confetti, Kuiz celebrating. Kuiz's school title per 10
  levels, Kindergarten to Einstein (100+), on the level pill.
- Gold, a peso top-up currency traded for crystals: the shop behind the crystal pill, **debug builds
  only**. Next: Play Billing and server receipt checks ([`systems/monetization.md`](systems/monetization.md)).
- The fridge's rows are cards: name, effect, stock, and a crystal Buy button.
- The closet: six more crystal costumes and six Gold-only ones (two per slot), in a scrolling grid. The
  level pill's title in mixed case so it clears the stats; a "+" on the crystal pill (debug builds).
  A Kuiz left asleep sleeps through the boot reveal (no hop, no `Happy`).
- Checked headless (all gates) and windowed screenshots of the party and the shop; not tapped through by hand.

Committed in `fb578cb` and `d44f7c7`: **the hand-over for the coworker** who takes over the backend, the AI and the release.
- [`next-steps.md`](next-steps.md) replaces `backend-next-steps.md`. It covers three phases in order:
  integrate the AI, add required Google sign-in through Play Games, and deploy the game.
- `.github/workflows/pages.yml` is back, since the coworker can turn GitHub Pages on.
- `rules.md` (Auth) and `launch-plan.md` §1 (Login) record the 2026-11-09 decision on sign-in.
- The World Builder's question-type ticks (Multiple choice, Identification, Essay; one or more), sent as
  `types` to `/v1/extract`. The prompt now keeps a quiz-style reviewer's own questions and answer-key
  answers. Google's Gemma 4 endpoint works for development (`api-backend.md` §3). Checked live on a
  quiz PDF from the server; not yet tapped through in the editor with `DEV_USES_SERVER`.
- Long reviewers: the PDF is read in layout mode and sent in parts at the same time, the bank holds up
  to 100, and a quiz item's answer line counts as its source. A 78-item quiz PDF kept 76–91 questions.
  The World Builder no longer decodes a PDF as text (the UTF-8 error flood), and a long file name is
  cut with an ellipsis.
- Smarter grading and options: essays get full, partial or no credit per rubric point, at temperature
  0, with feedback in the answer's language (grading evals 15 of 15, twice). Multiple Choice wrong
  options match the answer's kind (other ages for an age), invented when the reviewer has none.
- The island: runs play only questions of their own type, each once (no rewriting, no repeats; a
  one-question type plays a one-item run), and only the types a world has get houses and a gym. House
  badges replace the outlined labels. Fast travel: tap the big map, pay 25 crystals. Checked headless
  and in a windowed screenshot; not tapped through by hand.
- Houses are a route (House 1 nearest the spawn): only the next one opens, it is the green pin on the
  map, and the quest card names it. Fast travel shrinks the explorer and Kuiz away in a burst and pops
  them in at the pin. Review answers: Easy / Hard per question (sets its tier), and a small report flag
  instead of the Report button.
- `rules.md` §5 adds a rule: no objects hard-coded in scripts or scenes. Nodes go in scenes and
  content goes in `assets/data/`.

**Game check on 2026-11-09.** No errors were found.
- Headless: all 7 gates, plus every other scene.
- Windowed: the boot chain reaches home in about 12 s, and the world intro reaches the map in about
  6 s.
- The only failures are the known headless #22 cases.
- Not covered: tapping through the game by hand, and phones.

Phases A and B of the 2026-11-08 plan are committed, but neither has met the real world yet:
- **A, cloud saves** (`6415399`): not tried on a phone. It needs the Play Console Game ID and an Android
  export ([`skills.md`](skills.md) §*Export for Android with Play Games*).
- **B, Gemma 4 on Cloudflare** (`d869b04`): not run against the real model. It needs the Cloudflare
  token.

Branches: the batches through 2026-11-02 are also on `origin/dev` (PR #9). Nothing is on `main`.

Still unverified across the committed work:
- None of the 2026-10-26 → 11-08 batches has been opened in the editor GUI or played on a phone. The
  checks were headless: Godot checks, `backend/tests` and the scene gates, plus a windowed scratch
  harness on Windows for the 11-06 batches.
- The houses have no door-swing animation. The glb merges all the doors, so it needs a split in
  Blender.

## Next: AI → Google sign-in → deploy

Owner: the coworker, who has the backend, the AI integration and the release. The step-by-step guide
is [`next-steps.md`](next-steps.md); the researched background is [`launch-plan.md`](launch-plan.md).
Tick each step here when it is done.

**Phase 1 — Integrate the AI into the game:**

| Step | Item |
|---|---|
| 1.1 | A Cloudflare account, Account ID and Workers AI token; read Cloudflare's terms for a 13+ app (decision 2 below) |
| 1.2 | Run the server locally against Gemma 4 |
| 1.3 | Run `backend/evals/`, tune the prompts, and record the measured neurons in [`api-backend.md`](api-backend.md) §3 and in `LIKELY_NEURONS` |
| 1.4 | Play the integration in the editor (`DEV_USES_SERVER`): consent, every upload type, More questions, grading, Report, the offline fallbacks |
| 1.5 | Deploy `backend/` on Render (Blueprint from `render.yaml`) and pass the `X-Forwarded-For` limit test |
| 1.6 | Set `Api.RELEASE_URL` |
| 1.7 | Turn GitHub Pages on, publish `site/`, and set the three policy URLs in `settings.gd` |

**Phase 2 — Google sign-in, required (through Google Play Games):**

| Step | Item |
|---|---|
| 2.1 | Play Console ($25 once): app type Game, Play Games Services with Saved Games, the Android OAuth clients, and a **Game server** credential (a Web OAuth client) |
| 2.2 | The server: `POST /v1/session` redeems the Play Games server auth code, then the AI routes require `Authorization: Bearer`, with limits per player and tests |
| 2.3 | The game: request the server code after sign-in, keep the session in memory, send the header, and add the sign-in gate before the first-run intro (Android only) |
| 2.4 | Update the docs, the privacy page, the consent text and the Data safety answers (User IDs) |

**Phase 3 — Deploy the game (Android):**

| Step | Item |
|---|---|
| 3.1 | The Android export: Gradle, `.aab`, the Game ID, user-data backup on, the keystore kept out of git |
| 3.2 | A real app icon and the adaptive icon (needs art) |
| 3.3 | Internal testing on a phone: cloud saves, the sign-in gate, the file picker (#23), the AI loop against Render, the offline fallbacks |
| 3.4 | The closed test: 12 or more testers for 14 days. **Recruit them during Phase 1** |
| 3.5 | The store listing from [`store-listing.md`](store-listing.md), then production with a staged rollout |

**Later (not blocking):** iOS (macOS, $99 a year), study reminders (a local-notifications plugin),
Play Integrity, Sentry, purchases.

Hygiene: #22, find why the headless boot chain fails its threaded loads.

## Needs a decision

1. ~~**Save cadence** (#14)~~. Settled: one write every 5 s, at once on pause or close. The cloud copy
   uploads at most once a minute.
2. **Cloudflare terms:** confirm nothing in Cloudflare's Self-Serve Subscription Agreement or Workers AI
   terms rules out a 13+ app before launch ([`launch-plan.md`](launch-plan.md) §1). This is step 1.1.
3. **Offline returning players** (Phase 2): when a player who already finished the intro can't sign
   in because they are offline, the recommended default is to let them play their local save, with AI
   calls waiting for a session. Confirm it while building 2.3.

## Done

- **2026-11-09** — Backend hand-over runbook, and the eval prints neurons per call (`ed9ac8a`).
  Superseded by [`next-steps.md`](next-steps.md).

- **2026-11-09** — C4 (`997104d`): nine eval reviewers and fifteen graded answers, with coverage and
  Filipino-language checks.

- **2026-11-09** — CI on the Node 24 action majors (`39aaa11`).

- **2026-11-09** — C3 (`67c5b08`): GitHub Actions runs `tests/gates.sh` (the headless gates on
  Linux), `pytest backend/tests` and `tests/links.sh` on every push (#20). The first run passed.

- **2026-11-09** — C2 (`1166a6c`): the privacy, terms and support pages in `site/` with a Pages
  workflow, [`store-listing.md`](store-listing.md), and the consent text naming Identification
  near-misses.

- **2026-11-09** — C1 (`fa01fdd`): gameplay saves are debounced to one write every 5 s (#14), and this
  register lists the plan to release.

- **2026-11-08** — Phase A, cloud saves (`6415399`): the Google Play Games plugin
  (`addons/GodotPlayGameServices/`, v3.4.0, MIT) and the `CloudSave` autoload, an Android-only copy of
  the save in the player's Saved Games. Save v17 adds `saved_at`. Settings shows the account, and
  "Delete my data" deletes the cloud copy too. Contract: [`data-model.md`](data-model.md) §8.
- **2026-11-08** — Phase B, Gemma 4 on Cloudflare Workers AI (`d869b04`): the study server calls any
  OpenAI-compatible endpoint (free 10,000 neurons a day). It has a daily neuron budget, sends scanned
  PDFs as page images, and has `offline` fallbacks: questions written on the device and essays graded
  offline. `render.yaml` deploys it free. Contract: [`api-backend.md`](api-backend.md).

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
