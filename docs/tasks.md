# Tasks

Where the work stands. Short on purpose — this is a **register**, not a backlog.

> **Derived.** This file records what is in flight and nothing else. Every open question lives in the
> doc that owns it, and **those docs win** if the two disagree. See [`rules.md`](rules.md) §2. Do not
> let a second status list grow here.

Last updated: 2026-11-09.

## In flight

Uncommitted, for the maintainer to commit: **C3**. `.github/workflows/checks.yml` runs three checks
on every push and pull request (#20):
- `tests/gates.sh`: the headless Godot gates on Linux;
- `pytest backend/tests`;
- `tests/links.sh`.

Checked locally on a fresh `git archive` copy, where all 7 gates pass and a planted parse error fails
the run. The first run on GitHub is still to watch.

The C2 pages are committed (`1166a6c`). Their first deploy failed only because Pages is not turned on
yet (D5). Re-run it after D5 from Actions → Pages → Run workflow.

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

## Next: the plan to the store release

Each step ends with the gates, the docs, a hand-off with a proposed commit, and a pause for the
maintainer's commit. The researched background is in [`launch-plan.md`](launch-plan.md).

**C — In the repo, no accounts needed (the agent):**

| Step | Item |
|---|---|
| C1 | ~~Record this plan; debounce saves (#14)~~ (`fa01fdd`) |
| C2 | ~~Privacy, terms and support pages in `site/` on GitHub Pages; [`store-listing.md`](store-listing.md)~~ (`1166a6c`). URLs once live: `https://defzeke.github.io/Studymon/privacy.html`, `…/terms.html`, `…/support.html` |
| C3 | ~~GitHub Actions: the headless gates, `backend/tests` and the docs' links on every push (#20)~~ (uncommitted, above). The splash, loading and Worlds screens stay out until #22 is fixed |
| C4 | A bigger eval set in `backend/evals/` (8–10 reviewers): table-heavy, long, Filipino, math, very short. Plus more grading cases: partial, off-topic, injection |

**D — Accounts (the maintainer; start now, alongside C):**

| Step | Item |
|---|---|
| D1 | Play Console ($25 once): create the app as a **Game**, turn on Play Games Services with **Saved Games**, copy the Game ID, add an Android OAuth client per signing key ([`skills.md`](skills.md) §*Export for Android with Play Games*) |
| D2 | Recruit **15–20 closed testers** now: Google's 14-day test is the longest wait |
| D3 | Cloudflare: a free account, its Account ID and a Workers AI token. Read its terms for the 13+ question (decision 2 below) |
| D4 | A free Render account, connected to the GitHub repo |
| D5 | GitHub → Settings → Pages → Source: **GitHub Actions** (for C2). If the deploy from `world-assets` is refused, add that branch under Settings → Environments → `github-pages` ([`store-listing.md`](store-listing.md) §1) |

**E — With the accounts (together):**

| Step | Item |
|---|---|
| E1 | Run `backend/evals/` against Gemma 4, tune the prompts, confirm `MAX_QUESTIONS = 30`, record neurons per call in [`api-backend.md`](api-backend.md) §3 |
| E2 | Deploy `backend/` on Render (`render.yaml`). Check `/health`, the cold-start wake and that `X-Forwarded-For` reaches the per-IP limit. `curl` a PDF, a scan, a .docx and a photo. Set `Api.RELEASE_URL` |
| E3 | Set `PRIVACY_URL`, `TERMS_URL` and `SUPPORT_URL` in `scripts/ui/settings.gd` once the pages are live |

**F — Android build and phones:**

| Step | Item |
|---|---|
| F1 | In the editor: install the Android build template, add the Android export (Gradle, `.aab`, the Game ID, **user-data backup on**, a release keystore kept out of git). The agent checks `export_presets.cfg` for secrets before it is committed |
| F2 | A real app icon and the adaptive icon (Godot's default `icon.svg` today; needs art) |
| F3 | Internal testing on a phone: the cloud-save checklist in [`skills.md`](skills.md), the file picker with a PDF, a photo and a .docx plus Export / Import (#23), the whole loop against Render, and the offline fallbacks when the AI budget runs out. Fix what breaks |
| F4 | The closed test: 12 or more testers opted in for 14 days |

**G — Release:** fill in Data safety, the content rating (13+), the listing and the screenshots from
`docs/store-listing.md`, then roll out to production in stages.

**Later (not blocking):** iOS (macOS CI, $99 a year), study reminders (a local-notifications plugin),
Play Integrity, Sentry, purchases.

Hygiene: #22, find why the headless boot chain fails its threaded loads.

## Needs a decision

1. ~~**Save cadence** (#14)~~. Settled: one write every 5 s, at once on pause or close. The cloud copy
   uploads at most once a minute.
2. **Cloudflare terms:** confirm nothing in Cloudflare's Self-Serve Subscription Agreement or Workers AI
   terms rules out a 13+ app before launch ([`launch-plan.md`](launch-plan.md) §1).

## Done

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
