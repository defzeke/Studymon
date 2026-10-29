# Battle runs and answer grading

A battle is a **run**: a fixed list of items fought against one foe, in a Challenge House, a Gym or
the Champion Gym. Multiple Choice is tapped and Identification typed, both checked on the device against
the question's answer key; an Essay is typed and graded by the study server (offline mark as fallback). Every item is always played: the foe's bar is progress, not a kill condition.

- **Scene / logic:** `scripts/battle/battle.gd` → `scenes/battle/battle.tscn`; the arena in `arena_stage.gd`
- **Run building and rewards:** `SessionManager` — `begin_run()`, `build_run()`, `report_run()`
- **Judging:** `scripts/autoload/api.gd` — `check_identification()`, `essay_offline()`, `grade_battle_question()`; server: `backend/ai.py`
- **Mastery:** `SessionManager.record_battle_outcome()`, once per question per run

Status: **Implemented on mocks.** Not yet played end to end by a person (the 3D arena and the review
panel were checked headless only).

---

## 1. Runs

| Building | Tier | Multiple Choice | Identification | Essay | Built to last |
|---|---|---|---|---|---|
| Challenge House | Easy | 10 | 5 | 5 | 10 min |
| Gym | Medium | 20 | 10 | 10 | 20 min |
| Champion Gym | Hard | 20, then | 10, then | 10 (one run of 40) | 30 min |

`SessionManager.RUN_QUOTAS`, `RUN_TIER`, `RUN_MINUTES`. Every one of the island's 15 houses is a Challenge House (5 per type, each its own run and first-clear
bonus; `begin_run()` takes the house id and a `variant` that starts each house at a different point of the
pool), and each type has one gym; the Champion plays all three types back to back against the toughest foe.

`build_run(topic, kind, type)` returns `[{q_index, question}]`:

1. For each segment of the quota, rank the topic's questions: same type first, then nearest the run's
   tier, then Remaster, New, Learning, Mastered, then question order.
2. A question of another type is **rewritten** to the segment's type when it can be. Its correct answer
   is the answer key, or else its first key idea. Identification needs one; Multiple Choice needs one
   plus wrong options (its own, then other questions' answers and key ideas) and is played as
   Identification without any; Essay takes its key ideas from the answer and the prompt becomes
   "Explain: …". When **no** question can take the segment's type, the segment uses the forms they
   can take instead (a world of one unanswered essay plays that essay in every house), so every house
   and gym can always be entered. The house panel says when a world has fewer questions than items.
3. If the pool is shorter than the count, it **cycles**, so a short reviewer still gets a full run
   with no item twice in a row (unless it has a single question).
4. `reshuffle_run()` (Try Again) shuffles each segment.

Handoff: `SessionManager.begin_run(topic_id, kind, gym_type)` sets `battle_topic_id`, `battle_kind`,
`battle_type` and `battle_run`, then the map changes scene. A scene run on its own plays one preview
item and pays nothing.

## 2. Turn flow

```text
_bind_item          question, type controls (MC buttons / text box), "Item n/N · Streak s"
answer              MC tap → _resolve;  ID → Api.check_identification → _resolve (a near-miss goes on to the server)
                    Essay / near-miss → Api.grade_battle_question → job_status(own job_id) → _resolve
_resolve(correct)   mastery (first time this run), streak/HP maths, result line
_finish_turn        Kuiz strikes (correct) or the foe strikes (wrong), bars drop as the blow lands
then                Kuiz at 0 HP → _lose;  last item → _win;  otherwise the review beat
review beat         answer (Essay: model answer, ✓ / ✗ per rubric point), explanation, feedback,
                    source excerpt; Next is held back
                    1.5 s after a right answer, 4 s after a wrong one
```

Correct means: Multiple Choice tapped right; Identification matches its answer key (§5); Essay score ≥
the tier's `essay_pass` (Easy 0.5, Medium 0.65, Hard 0.8). Multiple Choice gets one attempt per item.

### Streaks (Kuiz's hits)

| Streak after the answer | Hit | Look |
|---|---|---|
| 1–2 | HIT! | normal shake and flash |
| 3–4 | STRONG! | shake ×1.6, hit-stop, brighter flash, higher pitch |
| 5–7 | HEAVY!! | ×2.2 |
| 8+ | ULTIMATE!!! | ×2.8 |

The foe's bar (`HP_PER_ITEM` = 10 per item) drops one item's worth per correct answer and never reaches
0 before the last item, whatever the streak. The streak changes the look and the end bonus
(§4), never the item count. A correct answer also heals Kuiz `HEAL_ON_CORRECT` (4).

### Misses and defeat

A miss costs Kuiz the tier's counter (Easy 15, Medium 25, Hard 35) × `MISS_MULT` for the 1st, 2nd and
3rd+ miss in a row (1.0, 1.25, 1.5) × hunger (`counter_mult`, down to 0.8). A failed essay lands
`0.4 + 0.6 × (1 − score)` of it. The streak resets; the first miss of a run is forgiven when
`CompanionState.has_streak_shield()` (focus ≥ 50).

Kuiz at 0 HP ends the run: it topples over (`ArenaStage.pet_defeat()`), the banner reads DEFEATED, and
the panel offers **Exit** or **↻ Try Again**. Try Again reshuffles the run, resets the counters and
puts Kuiz back at full HP (`pet_stand()`); the run's mastery is not recorded a second time. Leaving
mid-run (Flee) forfeits it with no pay.

## 3. Stats

Kuiz's care stats do one job each. Nothing blocks play; a low stat only weakens its multiplier.

| Stat | Effect in a run | Where |
|---|---|---|
| Health | Kuiz's battle HP, 70 to 120 | `battle_max_hp()` |
| Energy | XP paid ×0.8 to ×1.2 | `xp_mult()` |
| Mood | Crystals paid ×0.8 to ×1.2 | `crystal_mult()` |
| Hunger | Counter damage down to −20 % | `counter_mult()` |
| Focus (flashcards) | Forgives the first miss | `has_streak_shield()` |

Playing moves the stats as it happens, so the cost is visible. The clock decay of every care stat is paused
while a run is on (`CompanionState.in_run`), and instead:

| Event | Energy | Hunger | Mood | Health |
|---|---|---|---|---|
| Each item answered | −0.5 | −0.4 | | |
| Each correct answer | | | +1.5 | |
| Each wrong answer | | | +0.3 | |
| Each time Kuiz is hit | | | | −counter × 0.3, never below 10 |

`play_item(correct)` and `hurt(counter)` in `companion_state.gd` (constants `PLAY_*`, `HURT_*`). A clean House of
10 to 20 items costs about 5 to 10 energy and raises mood about 15 to 30; the 40-item Champion costs 20 energy
and 16 hunger. Being hit hurts the health stat itself, which sets the next run's battle HP, so a hurt Kuiz
needs the screwdriver at home. Kuiz's card in the battle shows the four stats live.
`readiness()` (the four home stats averaged) is shown on a house / gym panel with a warning under 25 %.
`bond` and `dirt` have no battle effect.

## 4. Rewards

`SessionManager.report_run(survived, correct, total, best_streak)` runs once when a run ends, adds the
crystals (`GameState.add_crystals`) and XP (`CompanionState.add_xp`), saves, and returns
`{stars, coins, xp, first, replay, cleared}`. **A run clears its building only when Kuiz survives with
at least one star** (70 % right): surviving without a star pays like a defeat, clears nothing, and the
result panel says "Kuiz made it through!" with Try Again.

| | House | Gym | Champion |
|---|---|---|---|
| Crystals / XP per correct item | 1 / 1 | 2 / 2 | 3 / 3 |
| First-clear bonus, crystals / XP | 20 / 10 | 60 / 30 | 200 / 100 |
| Streak bonus | + best streak ÷ 5 crystals | same | same |

On a clear: (items + bonuses) × star multiplier (1 star ×1.0, 2 stars ×1.25, 3 stars ×1.5; accuracy
70 / 85 / 95 % earns 1 / 2 / 3 stars), × mood (crystals) or energy (XP). A replay of a cleared building
pays 25 %. A defeat pays 50 % of the per-item pay only. Reaching a level pays a flat 25 crystals
(`CompanionState.LEVEL_CRYSTALS`). A finished run (cleared or not, but not fled) also meets the day's
study goal ([`monetization.md`](monetization.md)); the result panel says so when it pays. A battery costs 30 crystals, so one house pays for one.

## 5. Grading

Every question carries an **answer key**, written when the reviewer was turned into questions (by
Claude on the study server, or by the mock extractor). It is saved on the device with the world
([`../data-model.md`](../data-model.md) §2), so Multiple Choice and Identification are checked on the
phone, offline. Only an Essay and an Identification near-miss go to the server. Code:
`Api.check_identification()`, `Api.essay_offline()`, `Api.rubric_for()`, `Api.grade_battle_question()`;
the server side is `backend/ai.py`.

| Type | Checked by | Correct when |
|---|---|---|
| Multiple Choice | `battle.gd`, on the device | the tapped option is `answer` |
| Identification | `Api.check_identification()`, on the device; a near-miss asks the server | see below |
| Essay | the server (`POST /v1/grade`); `Api.essay_offline()` when it cannot answer | score ≥ the run tier's `essay_pass` |

### Identification

Both sides are normalised first (`Api.normalize_answer()`): lowercase, punctuation stripped, spaces
collapsed, a leading "a / an / the" dropped. The keys are `answer` plus `accepted`.

| Check, in order | Verdict |
|---|---|
| empty answer | wrong |
| equals a key | **correct** |
| edit distance to a key within the allowance: 0 for keys of ≤ 4 letters, 1 for 5–8, 2 for 9+; **one fewer on a Hard run** | **correct** (typo) |
| shares a word of ≥ 3 letters with a key, or edit distance ≤ a third of the key's length; also a card with no key | **near-miss** → server |
| anything else | wrong, with "the key says …" |

A substring no longer counts, so typing one letter of the answer fails. A near-miss is sent to
`POST /v1/grade` (`mode: "identification"`), where Claude decides whether it names the same thing as
the key, judged by the source (a broader or vaguer word is wrong). The grade is correct at score ≥ 0.5.
Offline, on an error, or on mocks, a near-miss counts as a miss.

### Essay

The marking guide is the question's `rubric`: 3–5 `{point, keywords, weight}`. Without one,
`Api.rubric_for()` makes one point per key idea (or one from the answer).

- **Server** (`mode: "essay"`): Claude marks each point covered or not. It must quote the player's
  own words as evidence, and **the server computes the score**: the sum of the weights of covered
  points whose evidence really is in the answer. The model never sets the number itself, so an answer
  asking for full marks gets nothing. Reply: `{score, covered[], feedback}`.
- **Offline** (`Api.essay_offline()`, used on mocks and whenever the server cannot answer): a point
  counts when one of its keywords (or the point itself) appears as whole words in the answer.

  ```text
  coverage = weight of covered points / total weight
  score    = 0                                         if coverage == 0   # filler alone scores nothing
           = 0.7 * coverage + 0.3 * clamp(words / 30, 0, 1)   otherwise
  ```

  The feedback starts "Graded offline." when the server could not be reached.

A failed essay still lands only part of the counter (`0.4 + 0.6 × (1 − score)`, §2). The review beat
shows the model answer, a ✓ / ✗ per rubric point, the `explanation` and the feedback.

Each grade request has its own `job_id` (`Api.new_job_id("grade")`), and battle only takes the result
with its id.

## 6. Known gaps

| Gap | Detail |
|---|---|
| Not play-tested | Review panel layout and the defeat fall are unseen; the review panel may be tight on small phones |
| Rewritten items | An Identification rewritten as Essay is graded by key ideas taken from its answer, which is coarse |
| Foe look | Houses, Gyms and the Champion share `robot_1.glb` / `robot_2.glb`; only size and counters differ |
| House doors | The map's houses have no door animation (one merged `Door` mesh); a dark doorway panel stands in for it |
| Server grading untested live | `/v1/grade` was checked against a stubbed server only; no real Claude grade has been run yet (`backend/evals/`) |
