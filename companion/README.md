# Companion (GDD §4, Plan Phase 2)

Pou-style care room + AI-literacy curriculum (Lv 1–5 gate).

- Scenes: `companion_room.tscn` (Phase 2 target; current working room is `scenes/ui/main.tscn` until migration)
- Art: `assets/sprites/bot_lv1..lv5.png`, `room_bg.png`
- Contract (when `CompanionState` lands): taps call `CompanionState.care("feed"|"pet"|"play")`; UI listens to `stats_changed` / `leveled_up` / `tidbit_unlocked`; HUD strip (`ui/hud_strip.tscn`, Phase 2) reads the same signals from every screen.
