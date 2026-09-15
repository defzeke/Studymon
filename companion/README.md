# Companion (GDD §4, Plan Phase 2)

Pou-style care room + AI-literacy curriculum (Lv 1–5 gate).

- Scenes: `companion_room.tscn` (Phase 2 target; current working room is `scenes/ui/main.tscn` until migration)
- Art: `assets/sprites/companion/idle_companion.svg` (base) + `blink_companion.svg` (AnimatedSprite2D blink overlay on a randomized timer) + `sad_companion.svg` (sad, cross-fades in on low energy) on a skeletal rig (`companion_rig.tscn` + `companion_rig.gd`): Polygon2D body + Skeleton2D (Root/Body/EarL/EarR/Antenna), weights painted at runtime, bones posed with tweens
- Contract (when `CompanionState` lands): taps call `CompanionState.care("feed"|"pet"|"play")`; UI listens to `stats_changed` / `leveled_up` / `tidbit_unlocked`; HUD strip (`ui/hud_strip.tscn`, Phase 2) reads the same signals from every screen.
