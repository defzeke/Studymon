# Known issues

Last reviewed 2026-10-29 against the `world-assets` branch (Godot **4.7.2**, headless). Each entry lists the
evidence, the player/code impact, and a concrete fix.

Severity: **P0** blocks the core loop · **P1** blocks a feature or silently corrupts state ·
**P2** correctness/performance wart · **P3** hygiene.

## Summary

| # | Issue | Severity |
|---|---|---|
| 2 | ~~Auth header uses `***` instead of `Bearer`~~ — removed (no accounts in v1) | — |
| 8 | ~~Nothing on home calls `CompanionState.care()`~~ — fixed | — |
| 3, 4, 12, 16 | ~~Hidden rig, hidden TidbitBubble, rig `det == 0` spam, double save load~~ — gone with the care room | — |
| 5 | ~~Hourly diminishing returns yields 0 XP~~ — fixed | — |
| 7 | ~~Client/backend endpoint drift~~ — fixed | — |
| 9 | ~~Real grade/extract responses are silently dropped~~ — fixed | — |
| 11 | ~~Large-text accessibility toggle is unreachable~~ — fixed | — |
| 13 | ~~`stats_changed` fires every frame~~ — fixed | — |
| 14 | Full save write on every care action | **P2** |
| 19 | ~~Fake "Biology 101" topic seeded on every boot~~ — fixed | — |
| 20 | Stale docs, no tests/CI | **P3** |
| 21 | ~~Theme and scene colours predate the canonical palette~~ — migrated | — |
| 22 | Headless boot chain fails its threaded loads | **P3** |
| 23 | Native file picker paths unverified on Android / iOS | **P1** |

---

## 2. Auth header uses `***` — removed

v1 has no accounts, so the broken header, `_auth_headers()`, `GameState.auth_token` / `user_id` and
`set_user()` were deleted. If accounts arrive, send `Authorization: Bearer <token>`
([`launch-plan.md`](launch-plan.md) §5.2).

---

## 5. Diminishing returns yields 0 XP — fixed (now `maxi(1, roundi(base * mult))`)

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

## 7. Client/backend endpoint drift — fixed

Both sides now use `POST /v1/extract` and `POST /v1/grade` with the job envelope, implemented in
`backend/main.py` and called by `api.gd` when `MOCK` is off. Contract: [`api-backend.md`](api-backend.md) §2.

---

## 8. Nothing on home calls `CompanionState.care()` — fixed

Home's room actions call it: food → `feed`, a finished screwdriver tune-up → `fix`, a fast ball
throw → `play`; charging calls `recharge()`. XP and Level 5 are reachable again. Petting has no
home action yet, so `pet` is unused.

---

## 9. Real grade/extract responses are dropped — fixed

Every request has its own `HTTPRequest` and a unique `job_id` (`Api.new_job_id()`); the server echoes
it in the envelope. A network failure, a timeout, a non-2xx code or an unreadable reply is emitted as
`job_status(job_id, "failed", …)` with a message, so no screen waits forever: the categorizer shows the
message, and battle grades the answer on the device instead.

---

## 11. Large-text accessibility toggle — fixed

`settings.tscn` now has a **Large text** checkbox bound to `GameState.set_large_text()`, saved on
toggle.

---

## 13. `stats_changed` fires every frame — fixed

The clock decay now emits it every `DECAY_EMIT_SEC` (0.2 s) instead of every frame; care actions
and battle items still emit at once.

---

## 14. Full save write on every care tap (P2)

Home saves after each care action (food, tune-up, ball throw); the save JSON includes every
question in every topic, so it grows with the content the player uploads. On mobile this is a
synchronous `FileAccess` write per tap.

**Fix:** debounce (e.g. save at most once every 5 s, plus on `NOTIFICATION_WM_CLOSE_REQUEST` /
`NOTIFICATION_APPLICATION_PAUSED`).

---

## 19. Fake "Biology 101" topic — fixed

`Api.mock_get_topics()` now returns an empty list, so the Worlds hub only shows worlds the player made.

---

## 20. Stale docs, no tests/CI (P3)

- Root `README.md` describes folders that do not exist (`resources/`, `tests/`, `assets/themes/`)
  and singletons that were never written (`GameManager`, `AIService`, `SoundManager`).
- `quizmon-build-plan.md` says "Godot 4.6, avoid 4.7"; the project is 4.7.2.
- No automated tests for the Godot client and no CI workflow. The backend has `backend/tests/` (pytest,
  no Claude calls) and `backend/evals/` (paid, run by hand).

**Fix:** the root README is corrected in this docs pass; consider a `tests/` folder with a headless
GUT suite and a GitHub Action that runs `godot --headless --import` (which is how issues #1/#12 were
caught).

---

## 21. Theme and scene colours — migrated

The shared theme, battle, settings, categorizer, flashcards and the Worlds hub use the canonical palette.
New inline `Color(...)` overrides should pick a palette role from [`ui-and-assets.md`](ui-and-assets.md) §1.

---

## 22. Headless boot chain fails its threaded loads (P3)

Running `splash.tscn` or `loading.tscn` **headless** fails the scene each one loads in the background
(`ResourceLoader.load_threaded_request`): a `preload()` in that scene's scripts reports
`Could not preload resource file …` (a different file from run to run: `loading_screen_logo.png`,
`kuiz_look.gd`'s costumes, `sky_jump.gd`'s backdrops), so `loading.tscn` or `peek.tscn` fails to
parse. All those files are committed and import cleanly. The same scenes run on their own, and the
same chain run **windowed**, load without errors. Reproduced on an untouched `git archive HEAD`
copy (2026-10-26), so it predates the editor-UI pass.

**Impact:** players are unaffected (windowed boot is clean), but the headless `splash.tscn` gate in
[`skills.md`](skills.md) cannot pass.

**Fix:** not yet known. First check whether it is a Godot 4.7.2 headless threaded-load bug (re-test
on the next patch release). Until then, verify the boot chain windowed, and verify `peek.tscn` headless
on its own.

---

## 23. Native file picker paths unverified on Android / iOS (P1)

The categorizer's reviewer picker and Settings' Export / Import dialogs are `FileDialog`s with
`use_native_dialog = true`, read and written with `FileAccess`. On Android the system picker can hand
back a `content://` address, and on iOS a security-scoped path; whether `FileAccess` can open those
has only been checked on Windows.

**Impact:** if it cannot, phones cannot upload a reviewer file (pasting still works) or export / import
a save.

**Fix:** try a PDF, a photo and a .docx, plus Export and Import, on a real Android phone and iPhone
early. If the path cannot be opened, add a picker plugin that copies the file into `user://` first.

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
