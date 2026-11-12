# Monetization and the crystal economy

**Real money is coming, not live.** Gold, a second currency topped up in pesos, exists in debug builds
only (decided 2026-11-12). Release builds hide its shop until Google Play Billing is wired, because a
purchase screen that cannot pay is a common store rejection. Until then crystals are earned and spent
only in the game. See Gold below.

**The weekly AI limit was removed** (save v12): it only blocked players. AI cost and abuse are
controlled on the server instead: per-IP daily limits and the daily neuron budget of the free AI allowance
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
| Fast travel | `GameState.TRAVEL_PRICE` (25) | a tap on the island's big map ([`overworld.md`](overworld.md)) |
| Food | 4 – 13 (table below) | the Data Kitchen fridge |
| Closet costume | 30 – 250, each unlocked at a level (`Costume.price` / `level_needed`, `assets/data/costumes/`); every costume is bought, only "None" is free | the Playroom closet |
| New battery | 30 | the check-up tablet |

Studying is meant to be the main income: a world's campaign (houses, three gyms, the Champion) pays
roughly one world slot. Level-ups are flat so care tapping cannot outpace studying, and the minigame
cap stops the one-minute Kuiz Keeper round from being a farm. The daily counters use the phone's
clock, which a player can change; that is accepted for an offline game.

## Food prices

Each food restores its own hunger (`FoodItem`, `assets/data/foods/`), priced from how fast hunger drains (0.105 / s,
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

## Gold (`GameState.gold`, saved)

The premium currency. It is topped up for pesos and spent on crystals or on premium costumes; everything
else stays priced in crystals. Tapping home's crystal pill opens the shop (`TopUp`, `top_up.tscn`): the two
balances, the Gold packs and the crystal trades. Both are data, one `.tres` each, listed on the scene's
root.

| Gold pack (`GoldPack`, `assets/data/gold_packs/`) | Price | Product id |
|---|---|---|
| 50 Gold | PHP 49 | `gold_50` |
| 120 Gold | PHP 99 | `gold_120` |
| 320 Gold | PHP 249 | `gold_320` |
| 700 Gold | PHP 499 | `gold_700` |

| Trade (`CrystalBundle`, `assets/data/crystal_bundles/`) | Gold | Crystals |
|---|---|---|
| Small | 10 | 100 |
| Medium | 50 | 550 |
| Large | 100 | 1200 |

Premium costumes are the one thing Gold buys directly: two per closet slot, any level
(`Costume.gold_price`, `GameState.buy_costume()`): Halo 30 and Wizard hat 40 (head), Pixel shades 30
and Star visor 40 (face), Gold chain 30 and Jewel collar 40 (body).

`GameState.buy_crystals(bundle)` trades, and refuses without enough Gold. The prices are placeholders
to tune. "PHP" is written out because the font has no peso sign.

**Not live yet.** `TopUp.available()` is `OS.is_debug_build()`: in a debug build a pack asks to confirm
a free test top-up and adds the Gold; a release build's crystal pill does nothing. To ship it:

1. Vendor the Godot Google Play Billing plugin and create the four products in the Play Console.
2. Buy through it, and verify each purchase on the study server (receipt check) before granting Gold,
   so a save file can never grant it. Consume the purchase after granting.
3. Make `available()` true in release, and update the store listing ("Contains in-app purchases"),
   the Data safety answers and the privacy page.
