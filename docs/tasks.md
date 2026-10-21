# Tasks

Where the work stands. Short on purpose — this is a **register**, not a backlog.

> **Derived.** This file records what is in flight and nothing else. Every open question lives in the
> doc that owns it, and **those docs win** if the two disagree. See [`rules.md`](rules.md) §2. Do not
> let a second status list grow here.

Last updated: 2026-10-21.

## In flight

**Home loop — committed (`8c11f6e`).** After the tutorial's last line a tap starts `home.gd` (in
`peek.tscn`): a bottom bar walks Kuiz between the four rooms. Study Room: Charge (lights off,
`State_Charging`, `Wake_Up` on lights on), Play (new topic → upload screen), Settings (now with
music/sound volume and large text, save v5). Maintenance Bay: hold the screwdriver over Kuiz.
Data Kitchen: drag six foods to Kuiz, buy more at the fridge (free; no currency yet). Playroom:
fling the ball, Kuiz watches. Settings and the topic list now return home. New temporary art in
`assets/sprites/props/` and `ui/arrow.svg`. Details in [`ui-and-assets.md`](ui-and-assets.md) §2
Home.

**Loading music — uncommitted.** `splash.tscn` starts `MusicManager.play_loading()`, which begins
`loading.mp3` at 1 s and fades it in over 1 s; it runs through `loading.tscn`, and `peek.tscn`
switches back to `main room.mp3`. `assets/audio/loading.mp3` and its `.import` are untracked.

## Blocked

| Work | Blocked by |
|---|---|
| Kuiz's stats and the top bar | Waiting on the design: what goes at the top (including the currency), and what feeding, fixing, playing and charging should change |
| Playing the core loop end to end | The row above, issue #1 (`battle.tscn` fails to parse on missing `bot_lv*.png`) and issue #8 (no care input, so Level 5 is unreachable without editing the save) |
| Any real backend call | Issue #7 (endpoints disagree) and issue #2 (auth header is a redaction placeholder) |
| Claiming the Champion | Issue #6 (soft-lock when no question is `MASTERED`) |

## Next

P0/P1 first; each item's evidence and fix live in [`known-issues.md`](known-issues.md).

| Order | Item | Why now |
|---|---|---|
| 1 | #1 Add `bot_lv1..5.png` (or strip the `[ext_resource]` lines) | Unblocks the battle scene; also the prerequisite for #3 |
| 2 | #8 Add Feed / Pet / Play buttons wired to `_on_care()` | Makes the pet loop playable and Level 5 reachable |
| 3 | #3 Un-hide the companion rig and its animation guards | Core fantasy; depends on #1 |
| 4 | #4 Show `TidbitBubble` when text is assigned | Level-5 gate and every curriculum line are currently invisible |
| 5 | #5 `maxi(1, …)` instead of truncating XP to 0 | Diminishing returns currently stops XP entirely |
| 6 | #10 Save after battle results and topic confirm | Quitting after a battle loses the work |
| 7 | #6 Implement the documented Champion fallback | Region is otherwise impossible to finish |
| 8 | #2 `Bearer` header + a way to set `auth_token` | Required before `MOCK` can flip |
| 9 | #9 Standardise the job envelope (or add a `grade_result` signal) and handle non-2xx | Real responses are dropped today |
| 10 | #15 Charge grading quota only for API-graded types | Identification exhausts the free week locally |

Hygiene, after the slice plays:

| Item | What |
|---|---|
| #13 | Emit `stats_changed` at ~5 Hz or only on change |
| #14 | Debounce the save instead of one full write per tap |
| #12 | Give leaf bones non-zero rest length, or skip degenerate weights |
| #16, #17, #19 | Double save load, duplicate signal, phantom "Biology 101" |
| #20 | Add a headless smoke-test script / CI |
| #21 | Migrate the shared theme and inline scene colours to the canonical palette |

## Needs a decision

1. **Backend contract.** Client `/battle/grade` + job envelope, or `backend/README.md`'s `/grade` +
   `/extract`? Pick the client shape (it already consumes it) and rewrite the backend doc (#7).
2. **Auth scope.** Is login part of the vertical slice, or does the client stay anonymous while
   `MOCK` is on (#2)?
3. **Champion rule.** Fallback to all questions when none is `MASTERED`, or require a Mastered
   moveset and explain it (#6)?
4. **Codex.** The remote branch `feat/remove-codex` suggests it is being cut. Remove the button and
   the `codex` save field, or keep it?
5. **Save cadence.** Event-driven saves, a dirty flag with a timer, or save on app pause only (#14)?

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
