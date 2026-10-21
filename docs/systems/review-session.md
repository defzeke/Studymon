# Review session (upload → questions → region)

Turns reviewer material into an editable question bank, then into the region data the overworld
consumes.

- **State / pipeline:** `scripts/autoload/session_manager.gd` (autoload `SessionManager`)
- **Extraction (mock):** `scripts/autoload/api.gd` — `mock_upload_pdf()`, `_build_questions_from_text()`
- **Topic list screen:** `scripts/ui/session_list.gd` → `scenes/ui/session_list.tscn`
- **Upload / edit screen:** `scripts/review_session/categorizer.gd` → `scenes/review_session/categorizer.tscn`

Status: **Implemented, fully mocked.** No PDF text is ever really parsed and no network call is made.

---

## 1. Flow

```text
session_list.tscn
   │  + Add New Topic                     Open existing topic
   ▼                                        │
categorizer.tscn  ◄─────────────────────────┘
   │  1. name the topic
   │  2. paste text  OR  pick a file
   │  3. "AI is studying..." (0.8 s mock job)
   │  4. editable question list (add / edit / retype / delete)
   │  5. Confirm & Play
   ▼
SessionManager.confirm_topic(name)
   ├─ add_topic_to_history()   → topics cache
   ├─ Api.save_topic()         → PUT /topics/{id}  (no-op in MOCK)
   ├─ topic_saved signal
   └─ build_map_data() → region_generated → region_map.tscn
```

---

## 2. Input validation

`validate_source_text()` (`session_manager.gd:57-64`):

| Constant | Value | Error text |
|---|---|---|
| `MIN_CHARS` | 80 | "Too short — add more material (N/80 chars)." |
| `MIN_WORDS` | 20 | "Too brief — AI needs ~20 words, you have N." |

Returns `{ok, words, chars}` or `{ok: false, error}`. The categorizer renders this live under the
paste box as a green ✓ or a red warning (`categorizer.gd:103-117`).

The gate always runs. A picked file is decoded as UTF-8 in `_on_file_selected` and its full text goes
into the paste box, so it is validated like pasted text. A file that does not decode as text (a PDF)
is refused with a status message and the box is left untouched.

---

## 3. Upload precedence

The categorizer always calls `start_upload_from_text()`, which validates, sets `last_source_text`,
and delegates to `start_upload()`. That emits `extraction_started`, then hands off to
`Api.mock_upload_pdf()`.

Binary detection is literally `decoded.contains("�")` — the U+FFFD replacement character
(`categorizer.gd`, `_on_file_selected`). A real PDF will almost always trip it and is refused.

---

## 4. Mock extraction

`Api.mock_upload_pdf()` → quota gate → `_execute_mock_upload()`:

```text
job_status("job_001", "processing", 0.0)     immediately
Timer 0.8 s
job_status("job_001", "completed", 1.0, {topic_id, questions})
```

### Sentence splitter — `_split_sentences()` (`api.gd:217`)

- Normalises `\r\n` → `\n`, splits on newlines.
- Breaks each line on `.` `!` `?`, discarding fragments under 20 chars.
- Keeps trailing text without punctuation if ≥ 20 chars.

### Question builder — `_build_questions_from_text()` (`api.gd:138`)

- Keeps sentences with **≥ 6 words and ≥ 40 chars**, up to **12** sentences.
- **Tier** (`difficulty`): by sentence length, the shortest third `easy`, the middle `medium`, the
  longest third `hard`; an essay is never `easy`.
- Rotates by created-question index:
  - 0 → **Identification**: `What key term is described here? "<excerpt>"`, answer = the
    highest-ranked extracted term, confidence `0.85`
  - 1 → **Essay**: `Explain in your own words: <excerpt>`, confidence `0.7`
  - 2 → **Multiple Choice**: `Which term is described here? "<excerpt>"`, answer = the top term,
    `distractors` = top terms of the *other* sentences (`_distractors_for`), confidence `0.8`. With
    fewer than three distinct wrong options it becomes an Identification.
- `key_concepts` = first ≤ 3 extracted terms.
- `source` = first 220 chars of the sentence.

### Term extraction — `_extract_terms()` (`api.gd:242`)

- Lowercases, strips punctuation, keeps words **≥ 5 chars** that are valid identifiers and not in
  the ~45-entry `_STOPWORDS` list.
- Mid-sentence capitalised words are treated as proper terms and **ranked first**.
- Dedupes, caps at 6 candidates; Identification answers take the first.

This is a deterministic heuristic, not an LLM. It produces usable questions from prose notes and
garbage from tables/bullet fragments.

### Fallback — `_fallback_questions()` (`api.gd:189`)

Five canned AI-literacy questions when nothing usable survives, covering every type and tier:
an easy Identification and Multiple Choice about training data, a medium Essay on feedback and
Multiple Choice on generalization, and a hard Essay on trial-and-error practice — confidences
0.4–0.5.

---

## 5. Job contract

`Api.job_status(job_id, status, progress, result)` is a shared bus. `SessionManager._on_job_status`
(`session_manager.gd:99-143`) filters by id and status:

| `job_id` | `status` | Handling |
|---|---|---|
| `"grade"` | any | **ignored** — belongs to `battle.gd` |
| `"topics"` | `completed` | Merges `result.topics` into the cache, emits `topics_listed` |
| anything else | `processing` | `extraction_progress(job_id, progress)` |
| anything else | `completed` with `questions` | Normalises each `type` to lowercase, defaults `confidence` to 0.7, sets `pending_questions` / `editing_topic_id` / `current_topic_id`, emits `extraction_completed` |
| anything else | `completed` without `questions` | `extraction_failed(job_id, "No questions extracted")` |
| anything else | `failed` | `extraction_failed(job_id, str(result))` |

Any new async job type **must** pick a unique `job_id`, or `SessionManager` will swallow it as an
extraction result.

---

## 6. Editing (categorizer)

| Action | Call | Effect |
|---|---|---|
| Edit prompt | `update_question(i, {"text": ...})` | writes into `pending_questions[i]` |
| Change type | `update_question(i, {"type": "essay"\|"identification"\|"multiple_choice"})` | dropdown; re-renders the list (MC rows show their wrong-option fields); remaps the gym later |
| Change tier | `update_question(i, {"difficulty": "easy"\|"medium"\|"hard"})` | second dropdown on the type row |
| Edit answer | `update_question(i, {"answer": ...})` | same field used as key concepts for essays; the correct option for MC |
| Edit wrong options | `update_question(i, {"distractors": [3 strings]})` | three `LineEdit`s, MC rows only |
| Delete | `remove_question(i)` | `remove_at`, then full re-render |
| Add | `add_question(text, type, answer, key_concepts, difficulty, distractors)` | id `q_<n>_<rand0-9999>`, tier `medium`, confidence 0.5 |

`SessionManager.normalize_question()` runs on extraction results, saved topics and reopened topics:
it lowercases the type, defaults an unknown tier to `medium`, and turns a Multiple Choice row with
no correct answer or no wrong option into an Identification. Rows the player leaves incomplete in
the editor are kept as typed; the battle plays them as Identification.

Rows are built in code (`_make_question_row`), not as a reusable scene. Each row shows:

- `#N` index
- confidence badge: ✓ green ≥ 85 %, ○ yellow ≥ 60 %, ⚠ red below
- delete button
- prompt `TextEdit`
- type `OptionButton` and tier `OptionButton`
- answer/key-concepts `LineEdit`
- for Multiple Choice, three wrong-option `LineEdit`s

Edits are applied by index, so **deleting a row while editing others is safe only because the whole
list is re-rendered** after every delete. Note that mastery keys also use indices (see
`data-model.md` §4) — editing a confirmed topic reshuffles mastery.

`Play` is disabled while the list is empty and its label doubles as the count
(`▶ Confirm & Play (N Q)`).

---

## 7. Confirm and region handoff

`SessionManager.confirm_topic(name)` (`session_manager.gd:162-176`):

1. `add_topic_to_history(editing_topic_id, name, pending_questions)` — overwrites an entry with the
   same id, else appends a `{id, name, question_count, questions}` record.
2. `Api.save_topic()` — `PUT /topics/{id}`; in MOCK mode `_put` still fires an HTTPRequest at
   `localhost:8000`, which simply fails and is ignored by `_on_request_completed`.
3. `SaveManager.save_progress()` — the new topic is saved at once (a no-op until a save has been loaded).
4. Emits `topic_saved`, then `_enter_overworld()` → `build_map_data()` → `region_generated`.

`build_map_data()` (`session_manager.gd:178-187`) produces:

```gdscript
{
  "topic_id": "topic_biology_101",
  "gyms": ["identification", "essay"],        // distinct types, in first-seen order
  "trainers": [
    {"q_index": 0, "gym": "identification", "id": "q1"},
    {"q_index": 1, "gym": "essay", "id": "q2"}
  ]
}
```

`categorizer.gd:311-317` then waits 0.6 s, sets `GameState.active_region_id`, and changes scene to
`region_map.tscn`. The overworld **recomputes** gym structure from `pending_questions` instead of
reading the map data.

---

## 8. Session list

`session_list.gd` renders `SessionManager.get_topics_cache()` as one `Button` per topic
(`"  <name>  ·  N Qs"`). Empty state: "No topics yet — tap Add New Topic to turn a PDF into gyms!".

`_ready()` connects `topics_listed`, renders the cache immediately, then calls
`SessionManager.list_topics()` which returns canned data (`Biology 101`, 2 questions) from
`Api.mock_get_topics()`. That mock topic gets merged into the cache, so **a fresh install always
shows a fake "Biology 101" entry** that has no questions attached — opening it goes to the
categorizer with the previous `pending_questions` still loaded.

---

## 9. Known gaps in this subsystem

| Gap | Detail |
|---|---|
| No real PDF parsing | Files that do not decode as UTF-8 text are refused with a status message |
| No real extraction | `Api.MOCK = true`; `/extract` is not called |
| Fake topic injection | `mock_get_topics()` seeds "Biology 101" every boot |
| Source text not persisted | Re-opening a topic later cannot re-run extraction on the original reviewer |
| Topic id collisions | `topic_<unix%100000>` repeats every ~27.8 hours |