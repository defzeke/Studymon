# Data model

Everything persistent lives in one JSON file. There is no database, no `Resource`-based save, and
no cloud sync.

- **Path:** `user://studymon_save.json`
- **Written by:** `SaveManager.save_game()` — `scripts/autoload/save_manager.gd:6`
- **Read by:** `SaveManager.load_game()` — `scripts/autoload/save_manager.gd:24`
- **Schema tag:** `"v": 7` (v7 added `player_name` and `food_stock`; older saves load with defaults. The tutorial flag is deliberately not saved, so the intro plays every launch)
- **Loaded:** once at boot, deferred from `SaveManager._ready`
- **Format:** `JSON.stringify` of a single `Dictionary`, pretty-print off

The build plan originally proposed `Resource`-based saves; the implementation uses JSON instead.
That is fine for the current scope but means there is **no type safety and no automatic migration**.

---

## 1. Top-level save shape

```jsonc
{
  "v": 7,

  // CompanionState.to_dict()
  "level": 1,
  "xp": 0,
  "energy": 80.0,
  "focus": 70.0,
  "mood": 75.0,
  "bond": 0,
  "campaign_ready": false,
  "codex": ["I start out knowing NOTHING — like a baby! ..."],

  // GameState
  "campaign_unlocked_flag": false,
  "active_region_id": "",
  "large_text_enabled": false,
  "player_name": "",
  "food_stock": { "apple": 3 },

  // MusicManager (v5): settings sliders, 0..1; missing keys load as 1.0
  "music_volume": 1.0,
  "sfx_volume": 1.0,

  // SessionManager.to_dict()
  "session": {
    "mastery": { "topic_001:0": { "state": 1, "attempts": 2, "correct": 1, "last_correct": 1760000000 } },
    "cleared_trainers": ["topic_001:0"],
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
  },

  // MonetizationState.to_dict()
  "monetization": {
    "is_premium": false,
    "pdf_used_this_week": 0,
    "grades_used_this_week": 0,
    "week_start_unix": 1760000000
  }
}
```

Field-by-field:

| Field | Type | Written from | Notes |
|---|---|---|---|
| `v` | int | literal `7` | Never compared on load — see §6 |
| `level` | int | `CompanionState.level` | 1–5 |
| `xp` | int | `CompanionState.xp` | Lifetime XP, not per-level |
| `energy` / `focus` / `mood` | float | `CompanionState` | 0–100, clamped on mutation |
| `bond` | int | `CompanionState.bond` | Increments per care tap, **never read anywhere** |
| `campaign_ready` | bool | `CompanionState` | True once level hits 5 |
| `codex` | string[] | `CompanionState.codex` | Curriculum lines, backfilled on load |
| `campaign_unlocked_flag` | bool | `GameState` | Mirrors `campaign_ready` |
| `active_region_id` | string | `GameState` | `topic_id` of the region being played |
| `large_text_enabled` | bool | `GameState` | Applied to the Theme on load |
| `session.mastery` | dict | `SessionManager._mastery` | Keyed `"<topic_id>:<q_index>"` |
| `session.cleared_trainers` | string[] | keys of `_cleared_trainers` | Same key shape |
| `session.cleared_gyms` | string[] | keys of `_cleared_gyms` | `"<topic_id>:<gym_type>"` |
| `session.champion_defeated` | string[] | keys of `_champion_defeated` | Just `topic_id`s |
| `session.topics` | dict[] | `SessionManager._topics` | Full question banks — this is the bulk of the file |
| `monetization.*` | mixed | `MonetizationState` | Weekly quota counters |

---

## 2. Question dict

Produced by the mock extractor (`api.gd:138`) or by user edits in the categorizer, and stored
verbatim inside `session.topics[].questions`.

| Key | Type | Purpose |
|---|---|---|
| `id` | string | `q1`, `q2`… from extraction; `q_<n>_<rand>` for manually added |
| `text` | string | The prompt shown in battle / the editor |
| `type` | string | `"identification"`, `"essay"` or `"multiple_choice"` (always lowercased) |
| `difficulty` | string | `"easy"`, `"medium"` or `"hard"` (v6; a missing or unknown value loads as `"medium"`) |
| `answer` | string | Expected answer (Identification), a model excerpt (Essay) or the correct option (Multiple Choice) |
| `distractors` | string[] | Multiple Choice only (v6): the wrong options; blanks are dropped on load |
| `key_concepts` | string[] | Keywords used for essay coverage scoring |
| `confidence` | float | 0–1. Drives the categorizer's colour-coded badge; **not** sent to battle |
| `source` | string | Source sentence excerpt; forwarded as `source` to a real grade call |

Only `text`, `type`, `difficulty`, `answer`, `distractors` and `key_concepts` affect battle
outcome. `confidence` is purely a "how much should I double-check this" hint for the player.
`SessionManager.normalize_question()` applies the defaults and repairs unplayable Multiple Choice
rows (see [`systems/review-session.md`](systems/review-session.md) §6); a v5 save needs no migration.

---

## 3. Topic dict

| Key | Type | Purpose |
|---|---|---|
| `id` | string | `topic_<slug>` from `Api._slug_topic_id`, or `topic_<unix%100000>` for new topics |
| `name` | string | Player-visible name, defaults to the id |
| `question_count` | int | Denormalised `questions.size()`; `session_list.gd:38` falls back to the array length |
| `questions` | question[] | The actual question bank |

Topic ids are **not** guaranteed unique across sessions: `session_list.gd:60` builds
`topic_%d % (unix_time % 100000)`, which collides roughly every 27 hours of wall-clock use. The
saved-topic lookup is a linear scan by id, so a collision overwrites the older topic.

---

## 4. Mastery record

```jsonc
"topic_001:2": {
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
| `last_source_text` | `SessionManager` | Reviewer text is not persisted with the topic |
| Battle handoff (`battle_topic_id`, `battle_q_index`, `battle_is_boss`, `battle_is_champion`) | `SessionManager` | Correct by design — a battle doesn't survive a restart |
| Pomodoro (`_pomodoro_mode`, `_pomodoro_remaining`) | `CompanionState` | A running 25-minute focus timer is lost on quit |
| Tap-cap counters (`_action_tap_counts`, `_last_hour_reset`) | `CompanionState` | Relaunching clears the hourly diminishing-returns counter — an easy exploit |
| `GameState.user_id`, `auth_token` | `GameState` | Never set, never saved (no auth yet) |
| `GameState.player_name` | `GameState` | Set by the tutorial, never saved; every launch replays the tutorial and asks again |
| `GameState.tutorial_done` | `GameState` | Set when the tutorial ends; lets screens return to home without replaying it, until the app closes |
| `GameState.food_stock` | `GameState` | Home's food counts (id → count); a relaunch restocks the starting amounts |
| Trust/premium receipts | — | `is_premium` is a plain bool the player can flip in Settings |

---

## 6. Load semantics and versioning

`load_game()` is deliberately forgiving — it never fails hard and never migrates:

```text
file missing            → return false (nothing happens)
not valid JSON          → return false
CompanionState.from_dict(parsed)      # defaults for every missing key
if level >= 5: campaign_ready = true  # reconcile old saves
GameState.active_region_id  = parsed.get("active_region_id", "")
if has large_text_enabled:  set it + reapply theme
SessionManager.from_dict(parsed.get("session", {}))
if has monetization:        MonetizationState.from_dict(...)
→ return true
```

Behaviour worth knowing:

- **`"v"` is written but never read.** There is no branch on version; compatibility is achieved
  only by `.get(key, default)`. Bump `v` when you change a field's meaning, and add a real
  migration for anything that is not purely additive.
- `CompanionState.from_dict()` backfills curriculum entries for every level up to the saved level
  (`companion_state.gd:160`), so old saves regain missing codex lines.
- `MonetizationState.from_dict()` **clamps** counters to the free-tier limits
  (`monetization_state.gd:108-109`) — a tampered save can't grant extra usage, but it also means a
  future premium-limit change will rewrite existing counters.
- Quota counters ignore elapsed time on load; rollover only happens on the next
  `can_consume`/`get_remaining` call.
- `GameState.large_text_enabled` is applied by calling `_apply_theme_font_size()` directly on load,
  bypassing `set_large_text()` (so no signal is emitted and no scene re-layouts).

---

## 7. Save cadence

`SaveManager.save_game()` is called from:

| Site | Frequency |
|---|---|
| `companion.gd:135` `_on_care` | **every care tap** |
| `companion.gd:145` on level-up | rare |
| `companion.gd:196` on campaign ready | once |
| `settings.gd:49,56,63` premium toggle / quota reset | rare |
| `SaveManager.save_progress()` after a battle win or loss (`battle.gd`), and after a topic is confirmed (`confirm_topic`) | once per event |

`save_progress()` writes only when a save has already been loaded this session (`load_game()` /
`load_once()` set the flag), so a scene run on its own can never overwrite the real save with
defaults. Mastery, cleared gyms and trainers, Champion wins, XP and new topics now persist at the
moment they change. Mastery changed outside a battle (none today) would still wait for the next save.
