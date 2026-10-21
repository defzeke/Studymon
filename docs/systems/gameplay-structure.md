# Gameplay structure

The target design for how a reviewer becomes a playable world: which gyms exist, how difficulty
works, where flashcards fit, and the order to build what is missing. It supersedes the old
`gameplay_structure.md` draft (v2.6).

Status: **Proposed.** Nothing here is implemented yet. Where this page and the code disagree, the
code describes today; this page describes the target. As each phase lands, move its facts into the
owning doc (see [`../rules.md`](../rules.md) §2) and update the status below.

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
| Gym layout | One gym per question type (3 gyms), matching the three gym buildings in `map.glb` |
| Difficulty | AI-tagged per question; tiered progression inside each gym |
| Pet care | Stays Feed / Pet / Play; only wire the missing buttons (#8) |

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

### 3.1 Question model (additive, save `"v": 5`)

Existing keys stay ([`../data-model.md`](../data-model.md) §2). New keys:

| Key | Values | Notes |
|---|---|---|
| `type` | `multiple_choice` \| `identification` \| `essay` | `multiple_choice` is new |
| `difficulty` | `easy` \| `medium` \| `hard` | AI-tagged; loader default `medium` |
| `options` | string[4] | MC only; distractors come from the same reviewer |
| `correct_index` | 0..3 | MC only; `answer` also holds the correct option text |

Generation rules for the extractor and the AI:

- Every question is grounded in `source`; no outside trivia.
- Easy recalls a term or definition. Medium explains or distinguishes. Hard applies, compares or synthesises.
- Per gym aim for at least 3 Easy, 3 Medium and 1 Hard. A short reviewer gets fewer tiers, never an empty gym.
- MC: one correct option and three plausible distractors from other concepts in the same reviewer, each under about 40 characters.
- Essay: 3–5 `key_concepts`; they are the rubric.

### 3.2 Gyms and progression

- A gym is a question **type** (as today, `get_gym_structure()`), now with three tiers.
- Trainers on the road are ordered Easy then Medium; the **Hard** question(s) form the gym boss.
- The boss is **locked until every non-Hard trainer in that gym is cleared.** This closes the
  current gap where a boss win clears the gym without its trainers ([`overworld.md`](overworld.md) §5).
- Gym cleared means the boss is defeated. The Champion is available when every gym that has
  questions is cleared.
- A type with no questions gets no gym (current behaviour).

### 3.3 Difficulty scaling

Starting values; tune in [`battle.md`](battle.md) once implemented.

| Knob | Easy | Medium | Hard |
|---|---|---|---|
| Enemy HP | 60 | 100 | 150 (boss) |
| Counter damage on a miss | 15 | 25 | 35 |
| Identification accepts | contains, or Levenshtein ≤ 2 | Levenshtein ≤ 2 | exact, or Levenshtein ≤ 1 |
| Essay pass score | 0.5 | 0.65 | 0.8 |
| Multiple Choice | wrong option greys out after one miss | none | none |
| XP | 5 | 8 | 12 |

MC has no typing: a correct tap damages the enemy fully, a wrong tap triggers the counter.

### 3.4 Flashcard Sanctuary

- Deck is the topic's questions: front is the prompt, back is the answer and source excerpt. New and Remaster come first.
- Actions: **Again** (re-queue three ahead), **Hard** (end of deck), **Easy** (bank).
- Easy moves NEW or REMASTER to LEARNING only. **MASTERED is earned only in battle.**
- Rewards: a small focus and mood gain and a few XP. No timer, no HP loss, no quota use.
- It gives a safe way to repair mastery, which also eases the Champion soft-lock path.

### 3.5 Mastery, Champion and quota

- Keep `NEW → LEARNING → MASTERED`, with `REMASTER` after a miss or 7 days ([`overworld.md`](overworld.md) §6).
- Champion moveset is the MASTERED questions, **falling back to all questions** when none are
  mastered (what the code comments already claim; resolves #6). The queue is sorted Easy to Hard so
  the last step is a Hard boss.
- Only Essay grading and extraction use the AI, so only they consume quota. Identification and MC
  grade locally and are free (resolves #15).

## 4. Implementation phases

Each phase ships on its own and ends with the gates in [`../rules.md`](../rules.md) §6.

| Phase | Scope | Main files |
|---|---|---|
| 0 Unblock | #1 battle scene parse; #8 care buttons; #5 XP floor; #10 save after battle/confirm; decide what follows the tutorial so boot reaches the care room | `scenes/battle/battle.tscn`, `scenes/ui/main.tscn`, `companion.gd`, `companion_state.gd`, `session_manager.gd` |
| 1 Data and generation | Accept the new question keys; mock extractor rotates three types and tags difficulty, builds MC distractors; save `"v": 5` with a real version branch; categorizer edits type, difficulty and MC options; optionally key mastery by question `id` | `session_manager.gd`, `api.gd`, `save_manager.gd`, `categorizer.gd` |
| 2 Battle by type and difficulty | MC panel; per-difficulty constants and thresholds; MC and Identification grade locally; essay-only quota | `battle.gd`, `battle.tscn`, `api.gd` |
| 3 Overworld tiers | Order trainers by difficulty; boss lock; tier on labels; MC gym gets its building; Champion fallback; `_recheck_gym_clear()` emits once (#17) | `region_map.gd`, `session_manager.gd` |
| 4 Flashcard Sanctuary | New scene and script; entry from the map HUD and the session list; a mastery write that only allows NEW/REMASTER → LEARNING | `scenes/review_session/flashcards.tscn`, `flashcards.gd` |
| 5 Real AI backend | Pick the contract (#7); PDF text extraction, Claude generation using §3.1, essay grading; `Bearer` header (#2); handle non-envelope and non-2xx responses (#9); keep `Api.MOCK` working | `backend/main.py`, `api.gd` |

### Future

Subway Sprint runner on the MC question data; Endless Marathon and Create New World after the
Champion; Charge / Fix / Data Feed and the five-stat redesign; subject biomes; cloze and zen-matching
flashcards; the 80 % Champion accuracy rule.
