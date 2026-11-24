# Monetization and the crystal economy

**Real money goes through RevenueCat (built 2026-11-22, not live yet).** Gold is a second currency,
topped up in pesos and sold through RevenueCat's Android SDK. Release builds hide its shop until
RevenueCat's key is set (setup below), because a purchase screen that cannot pay is a common store
rejection. Debug builds keep a free test top-up. Crystals are earned and spent only in the game. See
Gold below.

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
| Closet costume | 30 – 250, each unlocked at a level (`Costume.price` / `level_needed`, `assets/data/costumes/`); every costume is bought, only "None" is free; the six premium ones cost Gold instead (any level) | the Playroom closet |
| New battery | 30 | the check-up tablet |

Studying is meant to be the main income: a world's campaign (houses, three gyms, the Champion) pays
roughly one world slot. Level-ups are flat so care tapping cannot outpace studying, and the minigame
cap stops the one-minute Kuiz Keeper round from being a farm. The daily counters use the phone's
clock, which a player can change; that is accepted for an offline game.

## Food prices

Each food restores its own hunger (`FoodItem`, `assets/data/foods/`), at **about 0.4 crystals per hunger
point**. Bigger meals are a little cheaper per point, and a second effect costs a little more.

**Since 2026-11-22 hunger drains on a real-life clock**: full to low in 4 hours, about 19 points an hour,
also while the game is closed, plus 0.4 per battle item. A player who checks in through the day spends
about 75 hunger, roughly 30 crystals, between meals. A 20-minute session alone uses only about 6 hunger
plus its battles, so food is now a small share of a session's ~135 crystals. Before, at 15 minutes, it
was 15–20 %. The prices were kept; tune them here if food should cost more.

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
| Sprout, Blush | 1 | 30 |
| Party hat, Glasses, Bow tie | 1 | 40 |
| Beanie, Scarf | 2 | 60 |
| Necktie | 3 | 70 |
| Bow, Shades | 3 | 80 |
| Monocle | 4 | 90 |
| Flower | 4 | 100 |
| Bandana | 5 | 110 |
| Grad Cap | 5 | 120 |
| Hero mask | 6 | 150 |
| Crown | 8 | 200 |
| Medal | 10 | 250 |

The six Gold-only costumes are listed under Gold below.

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

### Buying Gold: RevenueCat (`Store` autoload)

`Store` (`scripts/autoload/store.gd`) sells the packs through the vendored
[Godotx RevenueCat](https://github.com/godot-x/revenuecat) plugin (v2.6.0, MIT, RevenueCat Android SDK
10.14.1): `addons/godotx_revenue_cat/` and `android/revenue_cat/*.aar`. The four packs are
**consumables**.
- **Live** means Android, `Store.ANDROID_KEY` set, and the plugin's `GodotxRevenueCat` singleton present.
  The shop's Buy opens Google's payment sheet (`Store.buy(pack)`, which calls `purchase(product_id)`).
- **Granting.** RevenueCat checks the Google receipt on its own servers before `purchase_result`
  reports success, and it consumes the purchase so the pack can be bought again. On success `Store`
  adds the pack's Gold and calls `SaveManager.save_game()` at once, not the 5-second debounce. A
  cancel says nothing. Any other error shows "The purchase did not go through: …". The Buy buttons
  wait while a purchase is open. The study server is not involved, so it needs no receipt check.
- **Prices.** The buttons show the store's own localized price (`fetch_products`, with "₱" spelled
  "PHP"), or the pack's `pesos` until it answers.
- **Not live** means the editor, desktop, the headless gates, or a build without the key. Then
  `TopUp.available()` is `Store.is_live() or OS.is_debug_build()`. A debug build asks to confirm a free
  test top-up and adds the Gold. A release build's crystal pill does nothing.
- **Player id.** The app user id is anonymous for now. When Play Games sign-in ships
  ([`../next-steps.md`](../next-steps.md) Phase 2), call the plugin's `login(player_id)` so purchases
  follow the player.
- **Accepted gaps** (issue #24): Gold lives in the save, so an edited save can grant it, like
  crystals. A purchase interrupted between Google's sheet and `purchase_result` (the app killed) is
  not re-granted. RevenueCat's dashboard still has the order, so support can refund it.

**Cost.** RevenueCat is free up to USD 2,500 of tracked revenue a month. Above that it charges 1 %.

**To go live** (needs the Play Console from [`../next-steps.md`](../next-steps.md) 2.1):
1. **Play Console**, Monetize → In-app products: create `gold_50`, `gold_120`, `gold_320` and
   `gold_700` at the prices above, and activate them. Uploading a build with the billing permission
   comes first. The RevenueCat SDK adds that permission.
2. **RevenueCat** (free account): create a project and a Google Play app with the package name. Upload
   a Google Cloud service-account JSON that has the Play Console's financial and order permissions, as
   RevenueCat's "Google Play service credentials" guide describes. Import the four products and set
   each to **Consumable**.
3. Copy the app's **public Android SDK key** (`goog_…`) into `Store.ANDROID_KEY`. It is a public key,
   safe in the game. Remove the `# shortcut` line.
4. **Export**: Android with **Use Gradle Build** (Project → Install Android Build Template), and the
   preset's `revenue_cat/enable_revenue_cat` on. That is the default; the plugin adds the SDK from
   Maven ([`../skills.md`](../skills.md) §*Export for Android with Play Games*).
5. **Test**: add a license tester in the Play Console, install from internal testing, buy each pack
   (test cards are not charged), and see it in RevenueCat's dashboard. Then cancel one and fail one,
   with the network off.
6. Store listing "Contains in-app purchases", the Data safety form (Financial info → Purchase
   history), and the privacy page (done, `site/privacy.html`).
