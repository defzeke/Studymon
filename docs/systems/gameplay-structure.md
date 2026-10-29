# Gameplay structure

The target design for how a reviewer becomes a playable world: which gyms exist, how difficulty
works, where flashcards fit, and the order to build what is missing. It supersedes the old
`gameplay_structure.md` draft (v2.6).

Status: **Phases 0–4 implemented** (battles load, progress saves, the question model and mock
generation, Multiple Choice, a third gym spot on the map, Challenge Houses, Gyms and the Champion
Gym as fixed-length runs with streaks, rewards and the defeat flow, and the Flashcard Sanctuary). **Phase 5 (the real
AI backend and the store launch) is partly built: the AI gateway exists, the game stays on mocks**
([`../launch-plan.md`](../launch-plan.md)). Where this page and the code disagree, the code describes today. As each phase lands,
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
| Pet care | The teammate's home loop replaced the care room. **No Level 5 gate**: Play is open from the start, and levels unlock closet costumes instead |

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
Home care (any level) ↔ Campaign
  → Session list → Upload reviewer (paste/file) → AI generates questions (editable)
  → Island map for that topic
       3 gyms, one per type:  Multiple Choice | Identification | Essay
       each type = a Challenge House (Easy run) then a Gym (Medium run)
       Study node: Flashcard Sanctuary (untimed, no penalties)
       Big gym: Champion Gym, a 40-item Hard run (needs every gym cleared)
```

### 3.1 Question model (additive, save `"v": 6`)

Existing keys stay ([`../data-model.md`](../data-model.md) §2). New keys:

| Key | Values | Notes |
|---|---|---|
| `type` | `multiple_choice` \| `identification` \| `essay` | `multiple_choice` is new |
| `difficulty` | `easy` \| `medium` \| `hard` | AI-tagged; loader default `medium` |
| `distractors` | string[3] | MC only: the wrong options, from the same reviewer. `answer` is the correct option; the battle shuffles `[answer] + distractors` |
| `accepted`, `rubric`, `model_answer`, `explanation` | see [`../data-model.md`](../data-model.md) §2 | The rest of the **answer key**, written by the study server with the questions; all optional |

Generation rules for the extractor and the AI:

- Every question is grounded in `source`; no outside trivia.
- Easy recalls a term or definition. Medium explains or distinguishes. Hard applies, compares or synthesises.
- Per gym aim for at least 3 Easy, 3 Medium and 1 Hard. A short reviewer gets fewer tiers, never an empty gym.
- MC: one correct option and three plausible distractors from other concepts in the same reviewer, each under about 40 characters.
- Identification: the question must not contain its answer; `accepted` lists genuine equivalents only.
- Essay: a 3–5 point `rubric` (point, 2–4 keywords, weight) and a `model_answer`; its points are the `key_concepts`.
- Count: about one question per 80 words, at least 3 per type, at most 45.

These rules are the server's system prompt (`backend/ai.py` `EXTRACT_SYSTEM`); the server also checks
the output and drops what breaks them ([`../api-backend.md`](../api-backend.md) §2).

### 3.2 Houses, gyms and runs (replaces the trainer road and the boss)

Every house on the island is a **Challenge House** (15, five per type), and each question type
(Identification, Essay, Multiple Choice) has a **Gym**;
the **Champion Gym** closes the region. Each is one **run** of a fixed item count against one foe
([`battle.md`](battle.md) §1):

| Building | Tier | MC | ID | Essay | Built to last |
|---|---|---|---|---|---|
| Challenge House | Easy | 10 | 5 | 5 (per house, by its type) | 10 min |
| Gym | Medium | 20 | 10 | 10 (per type) | 20 min |
| Champion Gym | Hard | 20 + 10 + 10 = 40, all types | | | 30 min |

- Gate: any house of a type → that gym → Champion (all gyms cleared). The other houses are optional
  practice, each paying its own first-clear bonus. A run is cleared by surviving every item with at least one star (70 % right).
- Questions are not one-to-one with items: `build_run()` rewrites a question as the needed type and
  cycles through the pool, so a short reviewer still fills the quota.
- Time: counts give about a minute per item; the review beat after each answer (1.5 s right, 4 s wrong)
  makes a miss get read. There is no timer.

### 3.3 Difficulty scaling

| Knob | Easy (house) | Medium (gym) | Hard (Champion) |
|---|---|---|---|
| Counter damage on a miss | 15 | 25 | 35 |
| Identification accepts | the answer key, or a typo within the allowance (0 / 1 / 2 by key length) | same | the key, or one typo fewer |
| Essay pass score | 0.5 | 0.65 | 0.8 |
| Foe | normal | large | large |

The question's own `difficulty` now only chooses which questions a run prefers. Rewards, stars and the
stat effects are in [`battle.md`](battle.md) §3–4.

### 3.4 Flashcard Sanctuary

Scene `scenes/review_session/flashcards.tscn`, logic `scripts/review_session/flashcards.gd`, built in
the canonical palette (Soft Sage room, Warm Off-White card, Muted Teal controls).

- Deck is the topic's questions (`SessionManager.flashcard_deck()`): front is the prompt and a
  mastery badge, back is the answer (an Essay also shows its model answer and key ideas), the
  `explanation` and the source excerpt.
  Order: Remaster, New, Learning, Mastered; ties in question order.
- Show answer first; then **Again** (re-queue three cards ahead), **Hard** (to the end of the
  deck) or **Easy** (bank it). The deck is done when the queue is empty.
- Easy moves NEW or REMASTER to LEARNING only (`promote_from_review()`); a Learning or Mastered
  card is unchanged. **MASTERED is earned only in battle.**
- Rewards, each paid once per card because only a card that moves up pays: `+1 XP` and `+2 focus`
  per promotion (`CompanionState.reward_card_banked()`), `+3 mood` when a deck with banked cards
  finishes (`reward_deck_done()`). No timer, no HP loss, no game over.
- Entry points: the **Study** button on the island HUD (returns to the island) and the **Cards**
  button on each session-list row (returns to the list). The caller sets
  `SessionManager.flashcards_return`. Progress saves when the deck ends or on Back.
- It gives a safe way to repair mastery before the Champion.

### 3.5 Mastery, Champion and AI use

- Keep `NEW → LEARNING → MASTERED`, with `REMASTER` after a miss or 7 days ([`overworld.md`](overworld.md) §6).
- The Champion Gym is one 40-item run that prefers Hard questions and falls back to the rest; the Mastered-only moveset is gone ([`battle.md`](battle.md) §1).
- Only extraction, Essay grading and an Identification near-miss use the AI; MC and Identification are checked on the device against the saved answer key ([`battle.md`](battle.md) §5). Resolves #15.
  There is no usage limit: the weekly quota was removed.

## 4. Implementation phases

Each phase ships on its own and ends with the gates in [`../rules.md`](../rules.md) §6.

| Phase | Scope | Main files |
|---|---|---|
| 0 Unblock — **done** | #1 battle scene parse; #10 save after battle, confirm and Champion win (`SaveManager.save_progress()`). #8 (care buttons) and the Level 5 gate are superseded by the home loop; #5 sits in `care()`, which nothing calls now | `scenes/battle/battle.tscn`, `save_manager.gd`, `session_manager.gd`, `battle.gd` |
| 1 Data and generation — **done** | `difficulty` and `distractors` keys with `normalize_question()`; mock extractor rotates three types, tags tiers by sentence-length terciles and builds MC distractors; save `"v": 6`; categorizer edits type, difficulty and wrong options. Mastery is still keyed by question index | `session_manager.gd`, `api.gd`, `save_manager.gd`, `categorizer.gd` |
| 2 Battle by type and difficulty — **done** | MC panel; per-tier constants and thresholds; essay-only quota (since removed); the third gym spot and `Trainers3` road so MC is reachable | `battle.gd`, `api.gd`, `region_map.gd`, `region_map.tscn` |
| 3 Overworld tiers — **superseded** | Replaced by the run structure in §3.2: a Challenge House and a Gym per type, the Champion as one 40-item run, `build_run()`, rewards and the stat effects (save v13) | `region_map.gd`, `battle.gd`, `session_manager.gd`, `companion_state.gd` |
| 4 Flashcard Sanctuary — **done** | New scene and script; entry from the map HUD and the session list; a mastery write that only allows NEW/REMASTER → LEARNING; small once-per-card rewards | `scenes/review_session/flashcards.tscn`, `flashcards.gd`, `session_manager.gd`, `companion_state.gd` |
| 5 Real AI backend and store launch — **Partly built (AI gateway); the game stays on mocks**, plan in [`../launch-plan.md`](../launch-plan.md) | Done: the contract (#7), PDF and text extraction with Claude using §3.1 and its answer keys, essay and near-miss grading, failure reporting (#9), `Api.MOCK` still working. Open: `Bearer` header (#2), accounts, quotas, consent, reports, deployment | `backend/main.py`, `api.gd` |

### Future

Subway Sprint runner on the MC question data; Endless Marathon and Create New World after the
Champion; Charge / Fix / Data Feed and the five-stat redesign; subject biomes; cloze and zen-matching
flashcards; the 80 % Champion accuracy rule.
