# Monetization and the crystal economy

**No real money.** Studymon is a free launch with no in-app purchases; the placeholder Crystal Shop
was removed because unfinished purchase UI is a common App Review rejection. Crystals are earned and
spent only in the game.

**The weekly AI limit was removed** (save v12): it only blocked players. AI cost and abuse are
controlled on the server instead: per-IP daily limits and the Anthropic workspace spend limit
([`../api-backend.md`](../api-backend.md) §6).

## Crystals (`GameState.crystals`, saved)

| Earn | Amount | Where |
|---|---|---|
| Battle runs | per correct item, first-clear bonus, stars, × mood ([`battle.md`](battle.md) §4) | `SessionManager.report_run()` |
| Daily study goal | `STUDY_GOAL_CRYSTALS` (15) once a local day: finish one run, or rate `STUDY_GOAL_CARDS` (10) flashcards | `GameState.note_study()` |
| Level-up | flat `CompanionState.LEVEL_CRYSTALS` (25) per level | `_check_level_up()` |
| Minigames | Kuiz Keeper 1 per goal, Sky Jump 1 per 50 m, at most `MINIGAME_DAILY_CRYSTALS` (60) a local day | `GameState.pay_minigame()` |

| Spend | Price | Where |
|---|---|---|
| **World slot** | `GameState.WORLD_SLOT_PRICE` (300) | the worlds list's New World, when every slot is full |
| Closet costume | 60 – 250, each unlocked at a level (`kuiz_look.gd` `COSTUME_UNLOCKS`); one costume per slot is free | the Playroom closet |
| New battery | 30 | the check-up tablet |

Studying is meant to be the main income: a world's campaign (houses, three gyms, the Champion) pays
roughly one world slot. Level-ups are flat so care tapping cannot outpace studying, and the minigame
cap stops the one-minute Kuiz Keeper round from being a farm. The daily counters use the phone's
clock, which a player can change; that is accepted for an offline game.

## World slots

- `GameState.world_slots` (saved) starts at `FREE_WORLD_SLOTS` (3). A new world needs a free slot
  (`SessionManager.has_free_world_slot()`); re-saving or editing an existing world uses none.
- With every slot in use, New World on the worlds list offers one more slot for 300 crystals
  (`GameState.buy_world_slot()`), or explains how to earn crystals and that deleting a world frees
  its slot. The categorizer checks again before it saves a brand-new world.
- **Bought slots are permanent**: deleting a world frees its slot and never refunds or removes one.
  "Delete my data" resets the slots to 3.
- Slots live in the local save, so they are a game mechanic, not cost control: AI cost is protected
  by the server's daily limits.

## Future work

Any real purchase, if it ever comes, would need store billing and server-side receipt checks, so a
save file can never grant it.
