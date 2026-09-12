# Battle (GDD §6, Plan Phases 6–8)

Overworld gyms (Phase 6) → turn battles per question type (Phase 7) → mastery + Champion recap (Phase 8).

- Scenes (later): `region_map.tscn`, `battle_arena.tscn`
- Contract: battles read questions from `SessionManager.current_topic`; Identification judged locally (exact/fuzzy → KO or counter); Essay graded via `Api.post_json("/grade", {type, question, answer, source_context})` → `{score_0_1, feedback}` → damage; results update mastery states, Champion pulls all Mastered questions.
