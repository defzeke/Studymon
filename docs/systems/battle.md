# Battle and answer grading

Turn-based arena. One question is bound before the scene loads; the player answers in free text;
the answer is scored; the score becomes damage.

- **Scene / logic:** `scripts/battle/battle.gd` → `scenes/battle/battle.tscn`
- **Handoff state:** `SessionManager.battle_*` (`begin_battle`, `get_battle_question`)
- **Judging:** `autoload/api.gd` — `grade_battle_question()`, `_execute_mock_grade()`
- **Outcome recording:** `SessionManager.report_battle_result()` → `record_battle_outcome()`

Status: **Implemented, fully mocked grading**, and currently **unloadable** — `battle.tscn`
references `bot_lv1.png` / `bot_lv5.png`, which do not exist (`known-issues.md` #1).

---

## 1. Handoff contract

The overworld sets the battle context *before* changing scene, because the question dict cannot be
passed through `change_scene_to_file`:

```gdscript
SessionManager.begin_battle(topic_id, q_index, is_boss)   # trainer / gym boss
SessionManager.begin_champion_battle(topic_id)            # champion (fills a queue)
```

| Field | Meaning |
|---|---|
| `battle_topic_id` | topic the question belongs to |
| `battle_q_index` | index into `pending_questions` (or the champion step's index) |
| `battle_is_boss` | boss HP + bigger reward |
| `battle_is_champion` | gauntlet mode |
| `battle_champion_queue` / `battle_champion_index` | remaining Mastered questions |

`get_battle_question()` returns a deep copy of `pending_questions[battle_q_index]`, or `{}` if the
index is stale. `battle.gd:61-63` substitutes a hard-coded preview question in that case
(`"What is the capital of France?"` → `Paris`), which is what makes the scene testable standalone.

---

## 2. Constants

```gdscript
const PLAYER_MAX_HP := 100
const ENEMY_HP      := 100
const BOSS_HP       := 150

const ID_COUNTER    := 30      # damage taken on a failed Identification
const XP_REWARD     := 5       # trainer win
const BOSS_XP_REWARD      := 10
const CHAMPION_XP_REWARD  := 15  # bonus for finishing the gauntlet

const STRONG_ESSAY_SCORE  := 0.7   # juice threshold
const SHAKE_BASE_INTENSITY := 8.0
const HIT_STOP_BASE       := 0.06
```

Enemy max HP is `BOSS_HP` when `battle_is_boss` (gym boss **and** the final champion step), else
`ENEMY_HP`. The player always starts at 100.

---

## 3. Turn flow

```text
_ready()
  bind question, set title ("Battle" / "Boss Battle" / "CHAMPION n/total")
  reset HP bars, hide result panel
  connect Api.job_status, Api.quota_exceeded, MonetizationState signals

submit
  empty answer ─► "Type an answer first." (no quota consumed)
  otherwise:
     judge → Api.grade_battle_question(q, answer)
              ├─ quota exhausted ─► Api.quota_exceeded("grade") ─► paywall dialog, no grading
              └─ MOCK ─► _execute_mock_grade() ─► call_deferred
                          job_status("grade", "completed", 1.0, {score, feedback, damage, type})

job_status("grade")
  IDENTIFICATION:
     score >= 0.7 ─► enemy HP = 0, "ONE-HIT KO!" + light shake
     else         ─► player HP -= 30, "Blocked! Enemy counters for 30."
  ESSAY:
     enemy HP -= damage (default round(score*100))
     if enemy survives: player HP -= 10 + (1-score)*20
     strong hit (score >= 0.7): shake + hit-stop
  then: win / lose / keep fighting
```

There is **no turn cap and no enemy AI** — the enemy only ever "counters" as a damage formula.

---

## 4. Scoring (mock)

`Api._execute_mock_grade()` (`api.gd:276-329`) implements the hybrid rubric the build plan asked
for, entirely locally.

### Identification (`type == "identification"` or `"id"`)

| Condition | Score | Feedback |
|---|---|---|
| empty answer | 0.0 | "No answer — the enemy shrugs it off." |
| exact match (lowercased, trimmed) | 1.0 | "Exact hit — that's the one!" |
| one contains the other | 0.8 | "Close enough — core term landed." |
| Levenshtein distance ≤ 2 (±3 length) | 0.7 | "Near miss on spelling, but the idea connected." |
| no answer key set | 0.5 if ≥ 2 chars | "No answer key — effort counts for half." |
| anything else | 0.0 | "That missed — review the concept and strike again." |

`_fuzzy_match` / `_edit_distance` are hand-written (`api.gd:333-351`), not Godot helpers.

### Essay

```text
coverage  = hits / key_concepts.size()          # substring match, lowercase
holistic  = clamp(words / 30, 0, 1)             # effort proxy
score     = 0.5 * coverage + 0.5 * holistic
damage    = round(score * 100)
```

With no `key_concepts`, coverage defaults to 0.5 if the answer is ≥ 10 chars, else 0.

Feedback strings call out the missed concepts explicitly ("Good — covered 2/3 ideas, missed: …"),
which is the one-line study nudge the plan wanted.

**The real rubric should live server-side.** `POST /battle/grade` is called when `MOCK == false`
and is expected to return `{score, feedback, damage}` in the same shape.

---

## 5. Damage and outcomes

| Result | What happens |
|---|---|
| Enemy HP ≤ 0 | `_win()` |
| Player HP ≤ 0 | `_lose()` |
| otherwise | submit re-enabled, fight continues |

`_win()`:

1. `SessionManager.report_battle_result(true)` → mastery update, trainer cleared,
   gym badge if `battle_is_boss`.
2. Reward: `10` for boss, else `5`.
3. If champion: `advance_champion()`; if the queue is finished add `+15` and show
   "CHAMPION DEFEATED — Region Complete!".
4. `CompanionState.add_xp(reward)` — silently dropped at max level.
5. Result panel; `Continue` either reloads the battle scene (next champion) or returns to the
   overworld.

`_lose()`:

1. `SessionManager.report_battle_result(false)` → mastery demotion only; **no** trainer/gym clear.
2. `Retry` resets both HP bars and the answer field **in place** — no scene reload, and the loss is
   only recorded once (it is not re-recorded on retry).
3. `Continue` ("Flee") returns to the overworld.

`Flee()` (top bar) sets `battle_is_champion = false` and leaves — a flee from a Champion gauntlet
forfeits the run even though completed questions keep their mastery.

**XP is not saved here.** `CompanionState.add_xp` mutates memory; persistence waits for the next
care tap or settings change (`data-model.md` §7).

---

## 6. Champion gauntlet

- Every entry in `battle_champion_queue` is fought in sequence.
- All steps except the last use normal enemy HP, so only the finale is a 150 HP boss.
- `Continue` after a win reloads `battle.tscn`; `_ready()` re-reads
  `SessionManager.get_battle_question()`, which `advance_champion()` has already re-pointed.
- If the player loses mid-gauntlet, `Retry` is available; fleeing ends the run without clearing
  `_champion_defeated`.
- The last win sets `_champion_defeated[topic_id]`, which is what `is_region_complete()` checks.

---

## 7. Juice (Phase 9)

| Effect | Trigger | Implementation |
|---|---|---|
| Screen shake | ID one-hit KO (6.0, 0.18 s); essay score ≥ 0.7 (8 + score·10 intensity) | `Camera2D.offset` tweened in 5 jittered pairs; falls back to tweening the root `Control.position` if no camera |
| Hit-stop | strong essay hit | `Engine.time_scale = 0.08` for `0.06 + score·0.04` s, restored in an `await` |
| Camera fix | always in `_ready` | `Camera2D.anchor_mode = FIXED_TOP_LEFT`, position/offset zeroed — a previous "Drag Center" mode shifted the whole Control canvas during shakes |

The camera is a child of the `Battle` Control, not of a 2D world — everything here is UI.

---

## 8. Quota interaction

`Api.grade_battle_question()` checks `MonetizationState.can_consume("grade")` **before** grading
and consumes one unit on success (`api.gd:39-45`). Consequences:

- Identification questions cost the same quota as essays (see `known-issues.md` #15).
- A failed/empty submit is blocked earlier by `battle.gd`, so it does not consume quota.
- When exhausted, `quota_exceeded.emit("grade")` fires, `_awaiting` is reset, the submit button
  re-enables, and a `ConfirmationDialog` offers "Upgrade to Premium" (which is a mock flag in
  Settings, not a purchase).

---

## 9. Known gaps

| Gap | Detail |
|---|---|
| Scene unloadable | missing `bot_lv1.png` / `bot_lv5.png` textures |
| Grading is local | no Claude call; `/battle/grade` only fires when `MOCK == false` |
| Grading is quota-gated even when mocked | free-tier counter drains without any API cost |
| No result persistence | mastery/XP/clears rely on a later unrelated save |
| No multiple choice / true-false | only `identification` and `essay` are understood |
| No audio | no SFX or music cues for hits, victory, defeat |
| `Camera2D` in a `Control` | workaround-heavy; a `CanvasLayer` or pure-UI shake would be simpler |
