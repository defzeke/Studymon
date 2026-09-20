# Autoloads — global singletons, one domain each

| Singleton | Owns | Key API |
|---|---|---|
| `GameState` | Cross-game progression: current phase, campaign unlock flag | `campaign_unlocked: bool`, signal `campaign_unlocked_changed(bool)` |
| `CompanionState` | Pet-care stats (Phase 2): Energy/Focus/Integrity/Bond, AI XP, Level, Codex | `care(action)`, `add_xp(n)`, signals `stats_changed`, `leveled_up(n)` |
| `SessionManager` | Review topics/regions (Phase 5+) | `topics: Array`, `create_topic()`, `current_topic` |
| `Api` | Backend glue (Phase 0: mocked; Phase 5: real HTTP) | `post_json(path, body) -> Dictionary` (mock data until backend lands) |

Rules: scenes call autoloads, never the reverse. `GameManager`/`SaveManager` in `scripts/autoload/` are the pre-plan implementation — they stay working until Phase 2 migrates the care room onto `GameState`+`CompanionState`, then they are deleted.
