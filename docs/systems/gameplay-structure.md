# Gameplay structure

The target design for how a reviewer becomes a playable world: which gyms exist, how difficulty
works, where flashcards fit, and the order to build what is missing. It supersedes the old
`gameplay_structure.md` draft (v2.6).

Status: **Phases 0–3 implemented** (battles load, progress saves, the question model and mock
generation, Multiple Choice and per-tier battles, a third gym spot on the map, tier-ordered
trainers, the boss lock and the Champion fallback). **Phases 4–5 are proposed.** Where this page and the code disagree, the code describes today. As each phase lands,
move its facts into the owning doc (see [`../rules.md`](../rules.md) §2) and update the status here.

- **Today's systems:** [`overworld.md`](overworld.md), [`battle.md`](battle.md),
  [`review-session.md`](review-session.md), [`companion-care.md`](companion-care.md)
- **Blockers this plan depends on:** [`../known-issues.md`](../known-issues.md)

---

## 1. Direction

1. The map has gyms; each gym plays **Multiple Choice, Identification or Essay**.
2. The map's topic comes from the **uploaded reviewer**. An AI generates the questions and every
   game in that world is grounded in the reviewer.
3. Questions and battles come in **Easy, Medium and Hard**.
4. A **Flashcard Sanctuary** gives untimed review. The **Subway Sprint runner is a future update.**

Open decisions (defaults assumed below; change here first if wrong):

| Decision | Assumed |
|---|---|
| Gym layout | One gym per question type (3 gyms): two in the map's gym buildings, the third at a marker on the south road (the third building is the Champion's) |
| Difficulty | AI-tagged per question; tiered progression inside each gym |
| Pet care | The teammate's home loop replaced the care room; stats, the top bar and the Level 5 gate wait on its design, so Play is ungated for now |

## 2. Draft versus new structure

| Draft item | Decision |
|---|---|
| Reviewer → AI → world ("your notes construct the universe") | **Keep.** Already the shape of `categorizer` → `region_map`. |
| Identification and Essay battles | **Keep**, add difficulty scaling. |
| 3-choice runner question | **Becomes a Multiple Choice battle** now (tap one of 4 options). The runner itself is future. |
| Subway Sprint 3-lane runner | **Future.** Reuses the MC question data, so no schema change later. |
| Flashcard Sanctuary | **Keep, now.** Untimed; repairs Remaster questions; no HP loss. |
| Champion exam, 4-state mastery, 7-day decay | **Keep**; fix the soft-lock (#6). |
| 80 % accuracy to beat the Champion | **Defer.** The HP-based fight stays until the structure works. |
| Endless Marathon / Create New World fork | **Future.** After the Champion, return to the session list (exists). |
| Charge / Fix / Data Feed, 5 stats, rank tiers, GIGO | **Future.** |
| Biomes by subject | **Future.** The four seasons in `season.gd` are the only reskin. |
| 8–15 node graph, hallway routes | **Dropped.** The 3D island and roads replace it. |
| Cloze, zen matching, AI mnemonics | **Future.** Ship flip plus Again / Hard / Easy only. |

## 3. Target structure

```text
Care room (Feed/Pet/Play) → Level 5 → Campaign
  → Session list → Upload reviewer (paste/file) → AI generates questions (editable)
  → Island map for that topic
       3 gyms, one per type:  Multiple Choice | Identification | Essay
       each gym = a road of trainers by difficulty:  Easy → Medium → Hard (boss)
       Study node: Flashcard Sanctuary (untimed, no penalties)
       Big gym: Champion (needs every gym cleared)
```

### 3.1 Question model (additive, save `"v": 6`)

Existing keys stay ([`../data-model.md`](../data-model.md) §2). New keys:

| Key | Values | Notes |
|---|---|---|
| `type` | `multiple_choice` \| `identification` \| `essay` | `multiple_choice` is new |
| `difficulty` | `easy` \| `medium` \| `hard` | AI-tagged; loader default `medium` |
| `distractors` | string[3] | MC only: the wrong options, from the same reviewer. `answer` is the correct option; the battle shuffles `[answer] + distractors` |

Generation rules for the extractor and the AI:

- Every question is grounded in `source`; no outside trivia.
- Easy recalls a term or definition. Medium explains or distinguishes. Hard applies, compares or synthesises.
- Per gym aim for at least 3 Easy, 3 Medium and 1 Hard. A short reviewer gets fewer tiers, never an empty gym.
- MC: one correct option and three plausible distractors from other concepts in the same reviewer, each under about 40 characters.
- Essay: 3–5 `key_concepts`; they are the rubric.

### 3.2 Gyms and progression

- A gym is a question **type** (`get_gym_structure()`), holding questions of all three tiers.
- Its questions are ranked Easy to Hard. The **hardest** (the last among ties) is the **boss**; every
  other question is a **trainer**, standing along the road in that order, Easy nearest the start.
  A gym with a single question has no trainers.
- The boss is **locked until every trainer of that gym is cleared**, so a boss win can no longer clear
  a gym whose trainers were skipped ([`overworld.md`](overworld.md) §5).
- Gym cleared means the boss is defeated. The Champion is available when every gym that has
  questions is cleared.
- A type with no questions gets no gym.

### 3.3 Difficulty scaling

Starting values; tune in [`battle.md`](battle.md) once implemented.

| Knob | Easy | Medium | Hard |
|---|---|---|---|
| Enemy HP | 60 | 100 | 150 (boss) |
| Counter damage on a miss | 15 | 25 | 35 |
| Identification accepts | exact, contains, or Levenshtein ≤ 2 | same as Easy | exact, or Levenshtein ≤ 1 (no containment) |
| Essay pass score | 0.5 | 0.65 | 0.8 |
| XP (boss ×2) | 5 | 8 | 12 |

Essay below the pass score deals no damage and the enemy counters
(`round(counter × (0.4 + 0.6 × (1 − score)))`).

MC has no typing: a correct tap is a one-hit KO, a wrong tap greys out that option and triggers the
counter. A Multiple Choice question with no correct answer or no wrong option is played as Identification.

### 3.4 Flashcard Sanctuary

- Deck is the topic's questions: front is the prompt, back is the answer and source excerpt. New and Remaster come first.
- Actions: **Again** (re-queue three ahead), **Hard** (end of deck), **Easy** (bank).
- Easy moves NEW or REMASTER to LEARNING only. **MASTERED is earned only in battle.**
- Rewards: a small focus and mood gain and a few XP. No timer, no HP loss, no quota use.
- It gives a safe way to repair mastery, which also eases the Champion soft-lock path.

### 3.5 Mastery, Champion and quota

- Keep `NEW → LEARNING → MASTERED`, with `REMASTER` after a miss or 7 days ([`overworld.md`](overworld.md) §6).
- Champion moveset is the MASTERED questions, **falling back to all questions** when none are
  mastered. The queue is sorted Easy to Hard (ties in question order), so the last step, the 150 HP
  boss, is the hardest question.
- Only Essay grading and extraction use the AI, so only they consume quota. Identification and MC
  grade locally and are free (resolves #15).

## 4. Implementation phases

Each phase ships on its own and ends with the gates in [`../rules.md`](../rules.md) §6.

| Phase | Scope | Main files |
|---|---|---|
| 0 Unblock — **done** | #1 battle scene parse; #10 save after battle, confirm and Champion win (`SaveManager.save_progress()`). #8 (care buttons) and the Level 5 gate are superseded by the home loop; #5 sits in `care()`, which nothing calls now | `scenes/battle/battle.tscn`, `save_manager.gd`, `session_manager.gd`, `battle.gd` |
| 1 Data and generation — **done** | `difficulty` and `distractors` keys with `normalize_question()`; mock extractor rotates three types, tags tiers by sentence-length terciles and builds MC distractors; save `"v": 6`; categorizer edits type, difficulty and wrong options. Mastery is still keyed by question index | `session_manager.gd`, `api.gd`, `save_manager.gd`, `categorizer.gd` |
| 2 Battle by type and difficulty — **done** | MC panel; per-tier constants and thresholds; essay-only quota; the third gym spot and `Trainers3` road so MC is reachable | `battle.gd`, `api.gd`, `region_map.gd`, `region_map.tscn` |
| 3 Overworld tiers — **done** | Trainers ordered by tier with the tier on their labels; the boss is the hardest question and stays locked until the gym's trainers are cleared; gyms clear only through the boss (so `_recheck_gym_clear()` is gone and a trainer win emits once, #17); Champion fallback and Easy-to-Hard order (#6); the Trainers3 road now walks toward its gym | `region_map.gd`, `region_map.tscn`, `session_manager.gd` |
| 4 Flashcard Sanctuary | New scene and script; entry from the map HUD and the session list; a mastery write that only allows NEW/REMASTER → LEARNING | `scenes/review_session/flashcards.tscn`, `flashcards.gd` |
| 5 Real AI backend | Pick the contract (#7); PDF text extraction, Claude generation using §3.1, essay grading; `Bearer` header (#2); handle non-envelope and non-2xx responses (#9); keep `Api.MOCK` working | `backend/main.py`, `api.gd` |

### Future

Subway Sprint runner on the MC question data; Endless Marathon and Create New World after the
Champion; Charge / Fix / Data Feed and the five-stat redesign; subject biomes; cloze and zen-matching
flashcards; the 80 % Champion accuracy rule.
