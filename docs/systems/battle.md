# Battle runs and answer grading

A battle is a **run**: a fixed list of items fought against one foe, in a Challenge House, a Gym or
the Champion Gym. Identification and Essay are typed and scored; Multiple Choice is tapped and graded
locally. Every item is always played: the foe's bar is progress, not a kill condition.

- **Scene / logic:** `scripts/battle/battle.gd` → `scenes/battle/battle.tscn`; the arena in `arena_stage.gd`
- **Run building and rewards:** `SessionManager` — `begin_run()`, `build_run()`, `report_run()`
- **Judging:** `scripts/autoload/api.gd` — `grade_battle_question()`, `_execute_mock_grade()`
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
answer              MC tap → _resolve;  ID/Essay → Api.grade_battle_question → job_status("grade") → _resolve
_resolve(correct)   mastery (first time this run), streak/HP maths, result line
_finish_turn        Kuiz strikes (correct) or the foe strikes (wrong), bars drop as the blow lands
then                Kuiz at 0 HP → _lose;  last item → _win;  otherwise the review beat
review beat         answer / key ideas, feedback, source excerpt; Next is held back
                    1.5 s after a right answer, 4 s after a wrong one
```

Correct means: Multiple Choice tapped right; Identification score ≥ 0.7; Essay score ≥ the tier's
`essay_pass` (Easy 0.5, Medium 0.65, Hard 0.8). Multiple Choice gets one attempt per item.

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

`SessionManager.report_run(won, correct, total, best_streak)` runs once on a win or a defeat, adds the
crystals (`GameState.add_crystals`) and XP (`CompanionState.add_xp`), marks the building cleared on a
win, saves, and returns `{stars, coins, xp, first, replay}`.

| | House | Gym | Champion |
|---|---|---|---|
| Crystals / XP per correct item | 1 / 1 | 2 / 2 | 3 / 3 |
| First-clear bonus, crystals / XP | 20 / 10 | 60 / 30 | 200 / 100 |
| Streak bonus | + best streak ÷ 5 crystals | same | same |

On a win: (items + bonuses) × star multiplier (0 or 1 star ×1.0, 2 stars ×1.25, 3 stars ×1.5; accuracy
70 / 85 / 95 % earns 1 / 2 / 3 stars), × mood (crystals) or energy (XP). A replay of a cleared building
pays 25 %. A defeat pays 50 % of the per-item pay only. Reaching a level pays `level × 10` crystals
(`CompanionState.LEVEL_CRYSTALS`). A battery costs 30 crystals, so one house pays for one.

## 5. Grading (mock)

`Api._execute_mock_grade()`; Multiple Choice never reaches it.

### Identification

| Condition | Score |
|---|---|
| empty answer | 0.0 |
| exact match (lowercased, trimmed) | 1.0 |
| one contains the other (**not on Hard**) | 0.8 |
| Levenshtein distance ≤ 2 (±3 length); **≤ 1 on Hard** | 0.7 |
| no answer key set | 0.5 if ≥ 2 chars |
| anything else | 0.0 |

### Essay

```text
coverage  = hits / key_concepts.size()          # substring match, lowercase
holistic  = clamp(words / 30, 0, 1)             # effort proxy
score     = 0.5 * coverage + 0.5 * holistic
```

With no `key_concepts`, coverage defaults to 0.5 if the answer is ≥ 10 chars, else 0. The real rubric
belongs server-side: `POST /battle/grade` fires when `MOCK == false` and returns `{score, feedback, damage}`.

## 6. Known gaps

| Gap | Detail |
|---|---|
| Not play-tested | Review panel layout and the defeat fall are unseen; the review panel may be tight on small phones |
| Rewritten items | An Identification rewritten as Essay is graded by key ideas taken from its answer, which is coarse |
| Foe look | Houses, Gyms and the Champion share `robot_1.glb` / `robot_2.glb`; only size and counters differ |
| House doors | The map's houses have no door animation (one merged `Door` mesh); a dark doorway panel stands in for it |
| Grading is local | no Claude call; `/battle/grade` only fires when `MOCK == false` |
