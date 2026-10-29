# Data model

Everything persistent lives in one JSON file. There is no database, no `Resource`-based save, and
no cloud sync.

- **Path:** `user://studymon_save.json`
- **Written by:** `SaveManager.save_game()` — `scripts/autoload/save_manager.gd:6`
- **Read by:** `SaveManager.load_game()` — `scripts/autoload/save_manager.gd:24`
- **Schema tag:** `"v": 15` (v15 keys `session.mastery` by question id (`"topic_id:question_id"`; v14 index keys `"topic_id:<index>"` are rekeyed on load) and adds `tutorial_done` (a save with a `player_name` but no flag loads as done) and `ai_consent`, and stops writing `campaign_ready` / `campaign_unlocked_flag` (the removed Level 5 gate; ignored on load); v14 keys `cleared_houses` per house, `"topic_id:gym_type#house_id"`, and `best_stars` house runs `"house:topic_id:gym_type#house_id"`; a v13 house key without an id still counts toward its type; v13 replaced `session.cleared_trainers` with `cleared_houses` and added `best_stars`; a gym cleared before counts as its house cleared; v12 dropped the `monetization` block with the weekly AI limit; an older save's block is ignored; v11 added `explorer`; v10 added `battery_health` and replaced `costume` with `outfit`; a v9 `costume` loads into its slot; v9 added `dirt` and `costume`; v8 added `hunger`, `health` and `crystals`; v7 added `player_name` and `food_stock`; older saves load with defaults)
- **Loaded:** once at boot, deferred from `SaveManager._ready`
- **Format:** `JSON.stringify` of a single `Dictionary`, pretty-print off

The build plan originally proposed `Resource`-based saves; the implementation uses JSON instead.
That is fine for the current scope but means there is **no type safety and no automatic migration**.

---

## 1. Top-level save shape

```jsonc
{
  "v": 14,

  // CompanionState.to_dict()
  "level": 1,
  "xp": 0,
  "energy": 80.0,
  "focus": 70.0,
  "mood": 75.0,
  "hunger": 80.0,   // v8; missing loads as 80
  "health": 100.0,  // v8; missing loads as 100
  "dirt": 0.0,      // v9; missing loads as 0 (clean)
  "battery_health": 100.0, // v10; missing loads as 100 (new)
  "bond": 0,
  "codex": ["I start out knowing NOTHING — like a baby! ..."],

  // GameState
  "active_region_id": "",
  "large_text_enabled": false,
  "player_name": "",
  "tutorial_done": true,
  "ai_consent": false,
  "food_stock": { "apple": 3 },
  "crystals": 0,    // v8: home's currency; missing loads as 0
  "world_slots": 3, // worlds the player can keep; bought slots are permanent; missing / below 3 loads as 3
  "minigame_day": "2026-10-29", "minigame_crystals": 20,   // today's minigame pay toward the daily cap
  "study_streak": 4, "study_goal_day": "2026-10-29",       // the daily study goal (monetization.md)
  "study_cards_day": "2026-10-29", "study_cards": 6,
  "owned_costumes": ["bow"],                               // closet costumes bought; a worn one counts as owned
  "outfit": { "head": "crown", "body": "scarf" }, // v10: closet slot -> kuiz_look.gd COSTUMES id; a missing slot is bare
  "explorer": "boy", // v11: the region map's explorer, "boy" or "girl"; missing loads as "boy"

  // MusicManager (v5): settings sliders, 0..1; missing keys load as 1.0
  "music_volume": 1.0,
  "sfx_volume": 1.0,

  // SessionManager.to_dict()
  "session": {
    "mastery": { "topic_001:0": { "state": 1, "attempts": 2, "correct": 1, "last_correct": 1760000000 } },
    "cleared_houses": ["topic_001:essay#h4"],
    "best_stars": {"house:topic_001:essay#h4": 3},
    "cleared_gyms": ["topic_001:identification"],
    "champion_defeated": [],
    "topics": [
      {
        "id": "topic_001",
        "name": "Biology 101",
        "question_count": 2,
        "questions": [ /* see §3 */ ]
      }
    ]
  }
}
```

Field-by-field:

| Field | Type | Written from | Notes |
|---|---|---|---|
| `v` | int | literal `7` | Never compared on load — see §6 |
| `level` | int | `CompanionState.level` | 1 and up, no cap |
| `xp` | int | `CompanionState.xp` | Lifetime XP, not per-level |
| `energy` / `focus` / `mood` | float | `CompanionState` | 0–100, clamped on mutation |
| `bond` | int | `CompanionState.bond` | Increments per care tap, **never read anywhere** |
| `codex` | string[] | `CompanionState.codex` | Curriculum lines, backfilled on load |
| `active_region_id` | string | `GameState` | `topic_id` of the region being played |
| `large_text_enabled` | bool | `GameState` | Applied to the Theme on load |
| `session.mastery` | dict | `SessionManager._mastery` | Keyed `"<topic_id>:<question id>"` (v15), so editing or deleting other questions keeps it |
| `session.cleared_houses` | string[] | keys of `_cleared_houses` | `"topic_id:gym_type#house_id"`; house ids `h1`..`h15` come from `MapHouses.find()` |
| `session.best_stars` | object | `_best_stars` | `"kind:topic_id:run_key"` → 0–3; run key is the type, or `type#house_id` for a house |
| `session.cleared_gyms` | string[] | keys of `_cleared_gyms` | `"<topic_id>:<gym_type>"` |
| `session.champion_defeated` | string[] | keys of `_champion_defeated` | Just `topic_id`s |
| `session.topics` | dict[] | `SessionManager._topics` | Full question banks — this is the bulk of the file |

---

## 2. Question dict

Produced by the study server (`POST /v1/extract`, [`api-backend.md`](api-backend.md) §5), the mock
extractor (`Api._build_questions_from_text`) or user edits in the categorizer, and stored verbatim
inside `session.topics[].questions`. Together `answer`, `accepted`, `distractors` and `rubric` are the
question's **answer key**: battles check answers against it on the device.

| Key | Type | Purpose |
|---|---|---|
| `id` | string | `q_<hash>` from the server, `q1`, `q2`… from the mock; `q_<n>_<rand>` for manually added |
| `text` | string | The prompt shown in battle / the editor |
| `type` | string | `"identification"`, `"essay"` or `"multiple_choice"` (always lowercased) |
| `difficulty` | string | `"easy"`, `"medium"` or `"hard"` (v6; a missing or unknown value loads as `"medium"`) |
| `answer` | string | Expected answer (Identification), a model excerpt (Essay) or the correct option (Multiple Choice) |
| `accepted` | string[] | Identification: other answers that count as exact (synonyms, abbreviations, spellings). Optional; loads as `[]` with blanks dropped |
| `distractors` | string[] | Multiple Choice only (v6): the wrong options; blanks are dropped on load |
| `rubric` | `{point, keywords[], weight}`[] | Essay marking guide. Optional; without it `Api.rubric_for()` makes one point per key concept |
| `key_concepts` | string[] | Essay key ideas (the rubric's points when the server wrote it); the fallback rubric |
| `model_answer` | string | Essay: the ideal answer shown on the review beat and flashcard. Optional |
| `explanation` | string | One line on why the answer is right, shown after answering and on the flashcard. Optional |
| `confidence` | float | 0–1. Drives the categorizer's colour-coded badge; **not** sent to battle |
| `source` | string | Source sentence excerpt; forwarded as `source` to a real grade call |

Only `text`, `type`, `difficulty`, `answer`, `accepted`, `distractors`, `rubric` and `key_concepts`
affect battle outcome. The answer-key keys are additive and optional, so saves keep `"v": 14`. `confidence` is purely a "how much should I double-check this" hint for the player.
`SessionManager.normalize_question()` applies the defaults and repairs unplayable Multiple Choice
rows (see [`systems/review-session.md`](systems/review-session.md) §6); a v5 save needs no migration.

---

## 3. Topic dict

| Key | Type | Purpose |
|---|---|---|
| `id` | string | `topic_<slug>` from `Api._slug_topic_id`, or `topic_<unix%100000>` for new topics |
| `name` | string | Player-visible name, defaults to the id |
| `question_count` | int | Denormalised `questions.size()`; `session_list.gd` reads `questions` when it is 0 |
| `questions` | question[] | The actual question bank |
| `source_text` | string | The reviewer text the world was built from (pasted, or read by the server from a PDF / Word / PowerPoint file); `""` for a photo or an older save. Used by "More questions" |

Topic ids are **not** guaranteed unique across sessions: `session_list.gd:_on_new_world` builds
`topic_%d % (unix_time % 100000)`, which collides roughly every 27 hours of wall-clock use. The
saved-topic lookup is a linear scan by id, so a collision overwrites the older topic.

---

## 4. Mastery record

```jsonc
"topic_001:q3": {
  "state": 3,            // 0 NEW, 1 LEARNING, 2 REMASTER, 3 MASTERED
  "attempts": 4,         // every battle result, win or loss
  "correct": 3,          // wins only
  "last_correct": 1760000000   // unix seconds, used for the 7-day decay
}
```

- Enum: `SessionManager.Mastery` (`session_manager.gd:301`).
- Names array for API payloads: `["new", "learning", "remaster", "mastered"]`.
- Decay is **computed lazily** in `get_mastery_state()`: if `state == MASTERED` and
  `now - last_correct > 7 * 86400`, the record is rewritten to `REMASTER` on read. Nothing runs on a
  timer, so a save can sit with stale `MASTERED` values forever and only correct itself when the
  question is queried.
- Keys use the question's **array index** in the active topic, not its `id`. Reordering or deleting
  a question therefore re-points every mastery record after it.

---

## 5. What is *not* persisted

These live only in memory and are lost on quit or scene change:

| State | Lives in | Consequence |
|---|---|---|
| `pending_questions`, `editing_topic_id` | `SessionManager` | Reopening a topic reloads from `session.topics`; unsaved edits are lost on app exit |
| `current_topic_id` | `SessionManager` | After a restart, the overworld falls back to its preview questions unless a topic is re-opened |
| `last_source_text` | `SessionManager` | Kept with the world it builds as `topics[].source_text` (for "More questions"); a photo reviewer has none |
| Battle handoff (`battle_topic_id`, `battle_q_index`, `battle_is_boss`, `battle_is_champion`) | `SessionManager` | Correct by design — a battle doesn't survive a restart |
| Pomodoro (`_pomodoro_mode`, `_pomodoro_remaining`) | `CompanionState` | A running 25-minute focus timer (started on the Study screen) is lost on quit |
| Tap-cap counters (`_action_tap_counts`, `_last_hour_reset`) | `CompanionState` | Relaunching clears the hourly diminishing-returns counter — an easy exploit |
| `GameState.player_name` | `GameState` | Set by the tutorial; saved as `player_name` (v7) |
| `GameState.tutorial_done` | `GameState` | Set when the tutorial ends, and by the Worlds hub and Settings on open (they are only reachable from home, so running one on its own still returns to home, not the intro). **Saved** as `tutorial_done` (v15) |
| `GameState.ai_consent` | `GameState` | The player agreed to send reviewers and typed answers to the AI (the categorizer asks before the first upload; Settings can withdraw it). Without it the server is never called and essays grade offline. Saved as `ai_consent` (v15) |
| `GameState.food_stock` | `GameState` | Home's food counts (id → count); saved as `food_stock` (v7) |

---

## 6. Load semantics and versioning

`load_game()` is deliberately forgiving — it never fails hard and never migrates:

```text
file missing            → return false (nothing happens)
not valid JSON          → return false
CompanionState.from_dict(parsed)      # defaults for every missing key
GameState.active_region_id  = parsed.get("active_region_id", "")
if has large_text_enabled:  set it + reapply theme
SessionManager.from_dict(parsed.get("session", {}))
→ return true
```

Behaviour worth knowing:

- **`"v"` is written but never read.** There is no branch on version; compatibility is achieved
  only by `.get(key, default)`. Bump `v` when you change a field's meaning, and add a real
  migration for anything that is not purely additive.
- `CompanionState.from_dict()` backfills curriculum entries for every level up to the saved level
  (`companion_state.gd:160`), so old saves regain missing codex lines.
- `GameState.large_text_enabled` is applied by calling `_apply_theme_font_size()` directly on load,
  bypassing `set_large_text()` (so no signal is emitted and no scene re-layouts).

---

## 7. Save cadence

`SaveManager.save_game()` is called from:

| Site | Frequency |
|---|---|
| `SaveManager.save_progress()` after a battle win or loss (`battle.gd`), and after a topic is confirmed (`confirm_topic`) | once per event |

`save_progress()` writes only when a save has already been loaded this session (`load_game()` /
`load_once()` set the flag), so a scene run on its own can never overwrite the real save with
defaults. Mastery, cleared gyms and trainers, Champion wins, XP and new topics now persist at the
moment they change. Mastery changed outside a battle (none today) would still wait for the next save.
