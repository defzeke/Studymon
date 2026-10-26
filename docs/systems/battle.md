# Battle and answer grading

Turn-based arena. One question is bound before the scene loads. Identification and Essay are
answered in free text and scored; Multiple Choice is tapped and graded locally. The question's
difficulty tier sets the enemy's HP, the counter damage and the thresholds
([`gameplay-structure.md`](gameplay-structure.md) §3.3).

- **Scene / logic:** `scripts/battle/battle.gd` → `scenes/battle/battle.tscn`
- **Handoff state:** `SessionManager.battle_*` (`begin_battle`, `get_battle_question`)
- **Judging:** `scripts/autoload/api.gd` — `grade_battle_question()`, `_execute_mock_grade()`
- **Outcome recording:** `SessionManager.report_battle_result()` → `record_battle_outcome()`

Status: **Implemented, fully mocked grading.** The enemy and player cards have no sprites yet (the
old `bot_lv*.png` references were removed from `battle.tscn`).

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
index is stale. `battle.gd` substitutes a hard-coded preview question in that case
(`"What is the capital of France?"` → `Paris`), which is what makes the scene testable standalone.

---

## 2. Constants

```gdscript
const PLAYER_MAX_HP := 100
const BOSS_HP       := 150
const CHAMPION_XP_REWARD  := 15  # bonus for finishing the gauntlet

const TIERS := {
	"easy":   {"hp": 60,  "counter": 15, "xp": 5,  "essay_pass": 0.5},
	"medium": {"hp": 100, "counter": 25, "xp": 8,  "essay_pass": 0.65},
	"hard":   {"hp": 150, "counter": 35, "xp": 12, "essay_pass": 0.8},
}

const STRONG_ESSAY_SCORE  := 0.7   # juice threshold
const SHAKE_BASE_INTENSITY := 8.0
const HIT_STOP_BASE       := 0.06
```

The tier is the question's `difficulty` (default `medium`). Enemy max HP is `BOSS_HP` when
`battle_is_boss` (gym boss **and** the final champion step), else the tier's `hp`. A boss also
doubles the tier's XP. The player always starts at 100.

---

## 3. Turn flow

```text
_ready()
  bind question, resolve tier, set title ("Battle" / "Boss Battle" / "CHAMPION n/total")
  type label shows "<Type> · <Tier>"
  Multiple Choice: build four option buttons (answer + wrong options, shuffled), hide the text
    input and Attack button. A MC row with no answer or no wrong option is played as Identification.
  reset HP bars, hide result panel
  connect Api.job_status

multiple choice tap (local, no Api call)
  correct ─► enemy HP = 0, "ONE-HIT KO!" + light shake
  wrong   ─► that button greys out, player HP -= tier counter

submit (Identification / Essay)
  empty answer ─► "Type an answer first."
  otherwise:
     judge → Api.grade_battle_question(q, answer)
              └─ MOCK ─► _execute_mock_grade() ─► call_deferred
                          job_status("grade", "completed", 1.0, {score, feedback, damage, type})

job_status("grade")
  IDENTIFICATION:
     score >= 0.7 ─► enemy HP = 0, "ONE-HIT KO!" + light shake
     else         ─► player HP -= tier counter
  ESSAY:
     score >= tier essay_pass ─► enemy HP -= damage (default round(score*100)), else 0 damage
     if enemy survives: player HP -= round(counter * (0.4 + 0.6 * (1 - score)))
     strong hit (score >= 0.7, damage > 0): shake + hit-stop
  then: win / lose / keep fighting (_finish_turn)
```

There is **no turn cap and no enemy AI** — the enemy only ever "counters" as a damage formula.

---

## 4. Scoring (mock)

`Api._execute_mock_grade()` implements the hybrid rubric the build plan asked for, entirely
locally. Multiple Choice never reaches it.

### Identification (`type == "identification"` or `"id"`)

| Condition | Score | Feedback |
|---|---|---|
| empty answer | 0.0 | "No answer — the enemy shrugs it off." |
| exact match (lowercased, trimmed) | 1.0 | "Exact hit — that's the one!" |
| one contains the other (**not on Hard**) | 0.8 | "Close enough — core term landed." |
| Levenshtein distance ≤ 2 (±3 length); **≤ 1 on Hard** | 0.7 | "Near miss on spelling, but the idea connected." |
| no answer key set | 0.5 if ≥ 2 chars | "No answer key — effort counts for half." |
| anything else | 0.0 | "That missed — review the concept and strike again." |

`_fuzzy_match(a, b, max_distance)` / `_edit_distance` are hand-written, not Godot helpers.

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
2. Reward: the tier's XP (5 / 8 / 12), doubled for a boss.
3. If champion: `advance_champion()`; if the queue is finished add `+15` and show
   "CHAMPION DEFEATED — Region Complete!".
4. `CompanionState.add_xp(reward)` — silently dropped at max level.
5. Result panel; `Continue` either reloads the battle scene (next champion) or returns to the
   overworld.

`_lose()`:

1. `SessionManager.report_battle_result(false)` → mastery demotion only; **no** trainer/gym clear.
2. `Retry` resets both HP bars and the answer field **in place**, re-enabling Multiple Choice
   options — no scene reload, and the loss is only recorded once (it is not re-recorded on retry).
3. `Continue` ("Flee") returns to the overworld.

`Flee()` (top bar) sets `battle_is_champion = false` and leaves — a flee from a Champion gauntlet
forfeits the run even though completed questions keep their mastery.

`_win()` and `_lose()` end with `SaveManager.save_progress()`, so mastery, clears and XP persist
at once. It does nothing until a save has been loaded, so a battle run on its own cannot overwrite
the real save (`data-model.md` §7).

---

## 6. Champion gauntlet

- Every entry in `battle_champion_queue` is fought in sequence.
- All steps except the last use normal enemy HP, so only the finale is a 150 HP boss.
- `Continue` after a win reloads `battle.tscn`; `_ready()` re-reads
  `SessionManager.get_battle_question()`, which `advance_champion()` has already re-pointed.
- If the player loses mid-gauntlet, `Retry` is available; fleeing ends the run without clearing
  `_champion_defeated`.
- The last win sets `_champion_defeated[topic_id]`, which is what `is_champion_defeated()` reports.

---

## 7. Juice (Phase 9)

| Effect | Trigger | Implementation |
|---|---|---|
| Screen shake | ID one-hit KO (6.0, 0.18 s); essay score ≥ 0.7 (8 + score·10 intensity) | `Camera2D.offset` tweened in 5 jittered pairs; falls back to tweening the root `Control.position` if no camera |
| Hit-stop | strong essay hit | `Engine.time_scale = 0.08` for `0.06 + score·0.04` s, restored in an `await` |
| Camera fix | always in `_ready` | `Camera2D.anchor_mode = FIXED_TOP_LEFT`, position/offset zeroed — a previous "Drag Center" mode shifted the whole Control canvas during shakes |

The camera is a child of the `Battle` Control, not of a 2D world — everything here is UI.

---

## 8. Usage limits

None. The weekly grading quota (and its "Weekly limit reached" pop-up and `QuotaLabel`) was removed;
every essay is graded. Identification and Multiple Choice grade locally either way.

---

## 9. Known gaps

| Gap | Detail |
|---|---|
| Grading is local | no Claude call; `/battle/grade` only fires when `MOCK == false` |
| No true/false | only Multiple Choice, `identification` and `essay` are understood |
| Boss is not the Hard tier | the boss is the gym's hardest question, not necessarily Hard; it always has 150 HP |
| `Camera2D` in a `Control` | workaround-heavy; a `CanvasLayer` or pure-UI shake would be simpler |
