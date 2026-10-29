# Monetization

**The weekly AI limit was removed.** The game used to cap AI use per week on the client (3 PDF
extractions and 10 essay gradings, `MonetizationState`), with a mock premium flag and a "Weekly
limit reached" pop-up. With no way to buy premium, that only blocked players, so the autoload, the
gates in `Api`, the battle's quota label, the pop-ups and the save's `monetization` block are gone
(save v12; an older save's block is ignored). Every extraction and grading is unlimited.

## What exists now

- **Crystals** (`GameState.crystals`, saved): home's currency. Minigame rounds earn them (Kuiz
  Keeper 1 per goal, Sky Jump 1 per 50 m) and a new battery on the check-up tablet costs 30.
- **No purchases.** v1 is a free launch: the placeholder Crystal Shop (disabled real-money packs
  marked "Coming soon") was removed, because unfinished purchase UI is a common App Review
  rejection. The crystal pill only shows the balance ([`ui-and-assets.md`](../ui-and-assets.md) §2 Home HUD).

## Future work

Real purchases (store, receipts, entitlements) and any usage limits belong on the server, so a
save file can never grant them; see [`launch-plan.md`](../launch-plan.md).
