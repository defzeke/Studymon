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
| Food | 4 – 13 (table below) | the Data Kitchen fridge |
| Closet costume | 40 – 250, each unlocked at a level (`kuiz_look.gd` `COSTUME_UNLOCKS`); every costume is bought, only "None" is free | the Playroom closet |
| New battery | 30 | the check-up tablet |

Studying is meant to be the main income: a world's campaign (houses, three gyms, the Champion) pays
roughly one world slot. Level-ups are flat so care tapping cannot outpace studying, and the minigame
cap stops the one-minute Kuiz Keeper round from being a farm. The daily counters use the phone's
clock, which a player can change; that is accepted for an offline game.

## Food prices

Each food restores its own hunger (`home.gd` `FOODS`), priced from how fast hunger drains (0.105 / s,
≈ 6.3 a minute on every screen except battles, and 0.4 per battle item). A typical 20-minute session
uses about 62 hunger and earns about 135 crystals; at **about 0.4 crystals per hunger point**, eating
costs 15–20 % of income. Bigger meals are a little cheaper per point, and a second effect costs a
little more.

| Food | Hunger | Extra | Price | Crystals per hunger |
|---|---|---|---|---|
| Data Chips | +10 | — | 4 | 0.40 |
| Cache Cookie | +15 | — | 6 | 0.40 |
| Spicy Memory Chips (Kuiz's favourite) | +12 | +8 mood | 7 | 0.58 |
| Java Juice | +8 | +10 focus | 8 | — |
| Pi Pie | +25 | — | 9 | 0.36 |
| Byte Burger | +40 | — | 13 | 0.33 |

A new player starts with a free welcome stock (3 Data Chips, 1 Spicy Memory Chips, 2 Cache Cookies,
1 Pi Pie, 1 Byte Burger, 2 Java Juice: about 150 hunger) so nobody is stuck before earning.

## Closet prices

| Costume | Level | Price |
|---|---|---|
| Party hat, Glasses, Bow tie | 1 | 40 |
| Beanie, Scarf | 2 | 60 |
| Bow, Shades | 3 | 80 |
| Flower | 4 | 100 |
| Hero mask | 6 | 150 |
| Crown | 8 | 200 |
| Medal | 10 | 250 |

A costume Kuiz already wears counts as owned, so no save loses one.

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
