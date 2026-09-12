# Review Session (GDD §5, Plan Phase 5)

Upload PDF → "AI is studying..." → editable question list → Play generates region.

- Scenes (Phase 5): `session_list.tscn`, `upload_dialog.tscn`, `categorizer.tscn`
- Data: `SessionManager.topics` (topic → categories → questions with type Essay/Identification + mastery state)
- Contract: client never calls the LLM directly — `Api.post_json("/extract", {pdf})` (mocked until backend lands); raw extraction and player edits stored separately.
