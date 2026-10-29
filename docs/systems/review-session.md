# Review session (upload → questions → region)

Turns reviewer material into an editable question bank, then into the region data the overworld
consumes.

- **State / pipeline:** `scripts/autoload/session_manager.gd` (autoload `SessionManager`)
- **Extraction:** `scripts/autoload/api.gd` — `upload_reviewer()`; mock: `_build_questions_from_text()`;
  real: `POST /v1/extract` on the study server ([`../api-backend.md`](../api-backend.md) §2)
- **Worlds hub (topic list):** `scripts/ui/session_list.gd` → `scenes/ui/session_list.tscn`
- **Upload / edit screen:** `scripts/review_session/categorizer.gd` → `scenes/review_session/categorizer.tscn`

Status: **Implemented.** The editor runs on the mock extractor (`Api.MOCK`); with the server on (release builds),
Claude writes the questions and their answer keys, and PDFs are accepted.

---

## 1. Flow

```text
session_list.tscn  (Worlds hub: reached from home Play)
   │  + New World                             Edit a saved world
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

The gate runs for text. A picked file is decoded as UTF-8 in `_on_file_selected` and its full text goes
into the paste box, so it is validated like pasted text. A file that does not decode as text is a
**file upload** when the server is on (`Api.MOCK` false) and its extension is one of `categorizer.gd`
`FILE_TYPES`: PDF, a photo (PNG, JPG, WebP; at most 5 MB) or Word / PowerPoint (`.docx`, `.pptx`;
at most 20 MB). The bytes are kept in `_file` with their type, the paste box is cleared, and the
server checks and reads them ([`../api-backend.md`](../api-backend.md) §2). Typing in the paste box
afterwards drops the file. On mocks, or for any other file, it is refused with a status message.

---

## 3. Upload precedence

For text the categorizer calls `start_upload_from_text()`, which validates, sets `last_source_text`,
and delegates to `start_upload()`; for a PDF it calls `start_upload(name, bytes)`. `start_upload()`
sends bytes that do not decode as text on as a PDF, takes a fresh `Api.new_job_id("extract")`,
emits `extraction_started` and calls `Api.upload_reviewer(job_id, name, text, pdf)`.

Binary detection is literally `decoded.contains("�")` — the U+FFFD replacement character
(`categorizer.gd`, `_on_file_selected`; `session_manager.gd`, `start_upload`).

---

## 4. Mock extraction

`Api.upload_reviewer()` on mocks → `_execute_mock_upload()`:

```text
job_status(job_id, "processing", 0.0)     immediately
Timer 0.8 s
job_status(job_id, "completed", 1.0, {topic_id, questions})
```

The questions carry the older subset of the answer key ([`../api-backend.md`](../api-backend.md) §5):
Identification and Multiple Choice blank their answer term out of the quoted excerpt (`_blank()`).

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
| `"topics"` | `completed` | Merges `result.topics` into the cache, emits `topics_listed` |
| not the current upload's id | any | **ignored** (grades, older uploads) |
| the current upload's id | `processing` | `extraction_progress(job_id, progress)` |
| the current upload's id | `completed` with `questions` | Normalises each `type` to lowercase, defaults `confidence` to 0.7, sets `pending_questions` / `editing_topic_id` / `current_topic_id`, emits `extraction_completed` |
| the current upload's id | `completed` without `questions` | `extraction_failed(job_id, "No questions extracted")` |
| the current upload's id | `failed` | `extraction_failed(job_id, str(result))`: the server's or the network's message |

Every job takes its id from `Api.new_job_id()`, so results never cross between screens.

---

## 6. Editing (categorizer)

| Action | Call | Effect |
|---|---|---|
| Edit prompt | `update_question(i, {"text": ...})` | writes into `pending_questions[i]` |
| Change type | `update_question(i, {"type": "essay"\|"identification"\|"multiple_choice"})` | dropdown; re-renders the list (MC rows show their wrong-option fields); remaps the gym later |
| Change tier | `update_question(i, {"difficulty": "easy"\|"medium"\|"hard"})` | second dropdown on the type row |
| Edit answer | `update_question(i, {"answer": ...})` | same field used as key concepts for essays; the correct option for MC |
| Edit wrong options | `update_question(i, {"distractors": [3 strings]})` | three `LineEdit`s, MC rows only |
| Edit accepted answers | `update_question(i, {"accepted": [...]})` | "Also accept" `LineEdit`, comma-separated, Identification rows only |
| Delete | `remove_question(i)` | `remove_at`, then full re-render |
| Add | `add_question(text, type, answer, key_concepts, difficulty, distractors)` | id `q_<n>_<rand0-9999>`, tier `medium`, confidence 0.5 |

`SessionManager.normalize_question()` runs on extraction results, saved topics and reopened topics:
it lowercases the type, defaults an unknown tier to `medium`, and turns a Multiple Choice row with
no correct answer or no wrong option into an Identification. Rows the player leaves incomplete in
the editor are kept as typed; the battle plays them as Identification.

Each row is a copy of the hidden `RowTemplate` in `categorizer.tscn` (edit its layout and look in
the Godot editor); `_make_question_row` fills the copy and wires its signals. Each row shows:

- `#N` index
- confidence badge: ✓ green ≥ 85 %, ○ yellow ≥ 60 %, ⚠ red below
- delete button
- prompt `TextEdit`
- type `OptionButton` and tier `OptionButton`
- answer/key-concepts `LineEdit`
- for Identification, an "Also accept" `LineEdit` (`Accepted`)
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
2. `SaveManager.save_progress()` — the new topic is saved at once (a no-op until a save has been loaded).
3. Emits `topic_saved`, then `_enter_overworld()` → `build_map_data()` → `region_generated`.

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

## 8. Worlds hub

`session_list.gd` renders `SessionManager.get_topics_cache()` as one card per world (see
[`ui-and-assets.md`](../ui-and-assets.md) §2 Worlds hub). `SessionManager.reset_topic_progress()` wipes a
world's mastery, cleared trainers/gyms and Champion (keys starting `<topic_id>:`) and keeps its questions;
`delete_topic()` also removes the world and clears the active ids if they pointed at it. Both save.
`list_topics()` merges `Api.mock_get_topics()`, which is now an empty list.

---

## 9. Known gaps in this subsystem

| Gap | Detail |
|---|---|
| Mock cannot read PDFs | On mocks a PDF is refused; it needs the server |
| Real extraction unproven | `/v1/extract` has been checked against a stubbed Claude only; run `backend/evals/` |
| Photo reviewers keep no text | "More questions" needs the reviewer's text, which a photo does not have |
| Topic id collisions | `topic_<unix%100000>` repeats every ~27.8 hours |

---

## 10. More questions

A saved world keeps its reviewer text (`topics[].source_text`: the pasted text, or the text the server
read from a PDF / Word / PowerPoint file and sent back as `reviewer_text`). Editing such a world shows
**More questions from this reviewer** (`%MoreButton`) in the categorizer:
`SessionManager.start_more_questions()` sends the saved text with the world's current question texts
as `existing`, and the new questions are **added** to the world (deduplicated by text) instead of
replacing it. The world keeps its id, slot and mastery. On mocks the same text regenerates the same
questions, so nothing new is added.
