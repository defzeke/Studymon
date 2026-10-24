# Known issues

Last reviewed 2026-10-24 against the `world-assets` branch (Godot **4.7.2**, headless). Each entry lists the
evidence, the player/code impact, and a concrete fix.

Severity: **P0** blocks the core loop · **P1** blocks a feature or silently corrupts state ·
**P2** correctness/performance wart · **P3** hygiene.

## Summary

| # | Issue | Severity |
|---|---|---|
| 8 | Nothing on home calls `CompanionState.care()` | **P0** |
| 2 | Auth header uses `***` instead of `Bearer` | **P1** |
| 3, 4, 12, 16 | ~~Hidden rig, hidden TidbitBubble, rig `det == 0` spam, double save load~~ — gone with the care room | — |
| 5 | Hourly diminishing returns yields **0 XP** | **P1** |
| 7 | Client/backend endpoint drift | **P1** |
| 9 | Real grade/extract responses are silently dropped | **P1** |
| 11 | ~~Large-text accessibility toggle is unreachable~~ — fixed | — |
| 13 | `stats_changed` fires every frame (no listeners left) | **P2** |
| 14 | Full save write on every care tap (applies once care input returns) | **P2** |
| 19 | Fake "Biology 101" topic seeded on every boot | **P3** |
| 20 | Stale docs, no tests/CI | **P3** |
| 21 | Theme and scene colours predate the canonical palette | **P3** |

---

## 2. Auth header uses `***` (P1)

`scripts/autoload/api.gd:65`

```gdscript
headers.append("Authorization: *** " + GameState.auth_token)
```

A redaction placeholder ended up in source. Any real request carrying a token will be rejected.

**Fix:** `"Authorization: Bearer " + GameState.auth_token`, and add the login flow that actually
sets `GameState.auth_token` (currently `set_user()` has no callers).

---

## 5. Diminishing returns yields 0 XP (P1)

`scripts/autoload/companion_state.gd:107-124`

```gdscript
var xp_mult = 1.0
if count >= DAILY_CAP_BASE_XP:   # 10 taps of the same action this hour
    xp_mult = 0.3
…
gained = int(2 * xp_mult)        # int(0.6) == 0
gained = int(1 * xp_mult)        # int(0.3) == 0
```

The comment says "30 % XP after cap"; the truncation makes it **0 %**. After 10 taps of an action,
that action stops granting XP entirely until the hour resets — and the reset is also lost on
relaunch, so a determined player can cycle actions and farm.

**Fix:** never truncate to zero:

```gdscript
gained = maxi(1, int(round(base * xp_mult)))
```

and persist `_action_tap_counts` / `_last_hour_reset` if the cap is meant to survive restarts.

---

## 7. Client/backend endpoint drift (P1)

| Concern | `backend/README.md` | `api.gd` |
|---|---|---|
| Grade | `POST /grade` | `POST /battle/grade` |
| Extract | `POST /extract` | never called |
| Grade response | `{score_0_1, feedback}` | `{job_id, status, result:{score, feedback, damage}}` |

**Impact:** neither side can be implemented against the docs without breaking the other. A backend
built to `backend/README.md` will never be hit.

**Fix:** pick the client contract (`/battle/grade` + job envelope) since the client already consumes
it, and update `backend/README.md`. Add `/extract` to the client when `MOCK` flips.

---

## 8. Nothing on home calls `CompanionState.care()` (P0)

`CompanionState.care()` is complete, but the old care room that called it (`main.tscn`, `companion.gd`) was
deleted. Nothing routes to it now.

The 3D home (`home.gd`) now has care actions (food, screwdriver, ball, charge), but by design they
do not touch `CompanionState` yet: there are no stats until their design lands.

**Impact:** the pet loop cannot be played, so Level 5 (and therefore the campaign) is unreachable
without editing the save file.

**Fix:** once the top-bar design lands, call `CompanionState.care("feed"|"pet"|"play")` from the home
actions (food drop, screwdriver, ball) and play the matching Kuiz clip and SFX.

---

## 9. Real grade/extract responses are dropped (P1)

`api.gd:21-32` only emits `job_status` when the parsed body contains `job_id`. `battle.gd:140`
additionally requires `job_id == "grade"`. So a real `POST /battle/grade` returning
`{score, feedback, damage}` is silently discarded, and `_awaiting` stays `true` forever (submit
button disabled, "judging…" label stuck).

**Fix:** either standardise every backend response on the job envelope, or emit a new
`grade_result(data)` signal for non-`job_id` payloads. Also handle non-2xx `_response_code` — right
now 401/500/timeout are indistinguishable from success-with-no-body.

---

## 11. Large-text accessibility toggle — fixed

`settings.tscn` now has a **Large text** checkbox bound to `GameState.set_large_text()`, saved on
toggle.

---

## 13. `stats_changed` fires every frame (P2)

`companion_state.gd:67` emits inside `_process`. The HUD strip and Pomodoro widget that listened are gone,
so today it only wastes a signal emit; it matters again once a top bar listens.

**Fix:** accumulate decay and emit at ~5 Hz, or emit only when a value actually changed. Keep the
signal semantic ("stats changed"), not "a frame passed".

---

## 14. Full save write on every care tap (P2)

The old `companion.gd` saved after each tap, and the next care input will do the same unless debounced; the save JSON includes every
question in every topic, so it grows with the content the player uploads. On mobile this is a
synchronous `FileAccess` write per tap.

**Fix:** debounce (e.g. save at most once every 5 s, plus on `NOTIFICATION_WM_CLOSE_REQUEST` /
`NOTIFICATION_APPLICATION_PAUSED`).

---

## 19. Fake "Biology 101" topic seeded on every boot (P3)

`Api.mock_get_topics()` returns `Biology 101` with `question_count: 2` but no `questions` array.
`SessionManager` merges it into the cache, so the session list always shows a phantom topic that,
when opened, drops the player into the categorizer with whatever `pending_questions` was left over.

**Fix:** return `{"topics": []}` in mock mode, or seed it with real questions.

---

## 20. Stale docs, no tests/CI (P3)

- Root `README.md` describes folders that do not exist (`resources/`, `tests/`, `assets/themes/`)
  and singletons that were never written (`GameManager`, `AIService`, `SoundManager`).
- `quizmon-build-plan.md` says "Godot 4.6, avoid 4.7"; the project is 4.7.2.
- No automated tests, no CI workflow, no formatting/lint config beyond `.editorconfig`.

**Fix:** the root README is corrected in this docs pass; consider a `tests/` folder with a headless
GUT suite and a GitHub Action that runs `godot --headless --import` (which is how issues #1/#12 were
caught).

---

## 21. Theme and scene colours predate the canonical palette (P3)

**Evidence**

- `assets/theme/app_theme.tres:7,14,23` uses navy button/panel fills (`#1C264F`, `#0A122B`) and `#EDF5FF`
  button text; none are in the palette in [`ui-and-assets.md`](ui-and-assets.md#color-palette) §1.
- `scenes/ui/session_list.tscn:21` and `scenes/battle/battle.tscn:28`
  hard-code other navy/cyan/blue values. (`loading.tscn` has been migrated.)
- The palette was documented after those files were written.

**Impact:** New screens that follow the palette will visibly clash with the existing theme; the
shared theme does not represent the intended art direction.

**Fix:** migrate `assets/theme/app_theme.tres` first (button, panel, font colour), then replace the inline
`Color(...)` overrides in the scenes above with palette roles. Update the token table in
[`ui-and-assets.md`](ui-and-assets.md) §1 in the same change; leave the art assets alone.

---

## Verification commands

```powershell
# whole-project import / parse check
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# individual scene smoke test (catches missing ext_resources)
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/battle/battle.tscn --quit-after 20
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/overworld/region_map.tscn --quit-after 30
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/ui/boot/peek.tscn --quit-after 20
```

`--import` does **not** catch missing textures inside scenes; the per-scene runs do.
