# Tasks

Where the work stands. Short on purpose — this is a **register**, not a backlog.

> **Derived.** This file records what is in flight and nothing else. Every open question lives in the
> doc that owns it, and **those docs win** if the two disagree. See [`rules.md`](rules.md) §2. Do not
> let a second status list grow here.

Last updated: 2026-10-21.

## In flight

**3D overworld — uncommitted.** `region_map.tscn` is now the 3D island (`map.glb`) under an angled
top-down camera, dressed in a random season each load (`season.gd`: sunny, rainy, autumn, snowy), with the explorer (`boy_explorer.glb`) walking on a left-hand joystick
(`joystick.gd`), collision built from the map's meshes, and the existing encounter logic re-homed:
gyms in the map's gym buildings (animated doors), trainers on the roads to them, the Champion in the
big gym. Details in [`systems/overworld.md`](systems/overworld.md) §3.

**Study Room art — uncommitted.** The old room art (`rooms/main.svg`, `dark_main.svg`) was deleted;
`study_room.svg` and `study_room_night.svg` (temporary placeholders) replace it in the tutorial, the
care room and its night toggle, settings and the categorizer.

**Tutorial — uncommitted.** After the peek, `tutorial.gd` (in `peek.tscn`) plays Kuiz's first-run
lines with a fitting clip each, a Continue stand-in for sign-in, a name prompt
(`GameState.player_name`, memory only), and a tour through the four temporary rooms. It also
uses the new `kuiz.glb` clips (`State_Charging`, `State_Sick`, `State_Hungry`, `Celebrate`,
`Learn_Something_New`), loops `State_*` moods, and hides props a clip does not key. It also carries
the earlier peek polish: `Greetings` dropped after the peek, and 4× 3D MSAA for the ink
outline. Details in [`ui-and-assets.md`](ui-and-assets.md) §2.

## Blocked

| Work | Blocked by |
|---|---|
| Reaching the care room from boot | What follows the tutorial's last line ("Ready to jump into our very first review session?") is not decided; all four rooms are temporary art |
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
| #11 | Add the large-text toggle to Settings |
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

- **2026-10-21** — cleanup, no behaviour change: removed unused assets (`hmm.mp3`, the run-cycle and
  `loading_logo` PNGs, three companion SVGs), the five planning-stub READMEs, never-called helpers,
  `GameState.current_topic_id` (#18), the `campaign_unlocked` signal and the `# ponytail:` tags.
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
