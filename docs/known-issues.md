# Known issues

Verified against the current `dev` working tree (Godot **4.7.2**, headless). Each entry lists the
evidence, the player/code impact, and a concrete fix.

Severity: **P0** blocks the core loop · **P1** blocks a feature or silently corrupts state ·
**P2** correctness/performance wart · **P3** hygiene.

## Summary

| # | Issue | Severity |
|---|---|---|
| 1 | Missing `bot_lv*.png` — `battle.tscn` fails to parse | **P0** |
| 8 | No Feed / Pet / Play input in the care room | **P0** |
| 2 | Auth header uses `***` instead of `Bearer` | **P1** |
| 3 | Companion is invisible | **P1** |
| 4 | `TidbitBubble` is permanently hidden | **P1** |
| 5 | Hourly diminishing returns yields **0 XP** | **P1** |
| 6 | Champion soft-lock | **P1** |
| 7 | Client/backend endpoint drift | **P1** |
| 9 | Real grade/extract responses are silently dropped | **P1** |
| 10 | Progress is not saved after battles or topic confirm | **P1** |
| 11 | Large-text accessibility toggle is unreachable | **P2** |
| 12 | `Condition "det == 0" is true` spam from the rig | **P2** |
| 13 | `stats_changed` fires every frame | **P2** |
| 14 | Full save write on every care tap | **P2** |
| 15 | Identification answers consume grading quota | **P2** |
| 16 | Save file loaded twice at boot | **P3** |
| 17 | Duplicate `overworld_progress_changed` emissions | **P3** |
| 19 | Fake "Biology 101" topic seeded on every boot | **P3** |
| 20 | Stale docs, no tests/CI | **P3** |
| 21 | Theme and scene colours predate the canonical palette | **P3** |

---

## 1. Missing `bot_lv*.png` — `battle.tscn` fails to parse (P0)

`region_map.tscn` no longer references the sprites (it is 3D now), so only the battle arena is
affected.

**Evidence**

```
$ Godot_v4.7.2 --headless --path . res://scenes/battle/battle.tscn --quit-after 20
ERROR: Resource file not found: res://assets/sprites/bot_lv1.png …
ERROR: Resource file not found: res://assets/sprites/bot_lv5.png …
ERROR: res://scenes/battle/battle.tscn:77 / :107 - Parse Error …
```

`companion.gd:80` also looks for `bot_lv1..5.png` at runtime and falls back.

**Impact:** `change_scene_to_file` to the battle fails, so the campaign is dead at the first
"Fight Trainer!" in the overworld, and the battle arena cannot even be run standalone in the
editor.

**Fix (either):**

- Add `assets/sprites/bot_lv1.png` … `bot_lv5.png` (the intended pet growth art), or
- Remove the `[ext_resource]` entries for `bot_lv1.png` / `bot_lv5.png` (`battle.tscn:4-5`)
  together with the `texture = ExtResource(…)` lines that use them (`battle.tscn:77`,
  `battle.tscn:107`), then let the script's null-guards take over.

Until then, note that a missing texture in a `.tscn` is a **parse error**, not a warning — it
cannot be caught at runtime.

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

## 3. Companion is invisible (P1)

- `scenes/ui/main.tscn:83` — the `CompanionRig` instance has `visible = false`.
- `scripts/companion/companion.gd:36-37` — re-forces `rig.visible = false` on `_ready()`.
- `bot_lv1..5.png` do not exist, so the `bot_sprite` fallback path also has nothing to draw.
- Running the care room logs: `WARNING: Companion: no bot textures found.`
- Every animation helper (`_pop_bot`, `_show_level`, `_burst_levelup`, `_show_xp_tick`) early-returns
  while the rig is hidden.

**Impact:** the room renders an empty table with no pet, and care feedback (pop, level-up burst) is
invisible. This is the app's core fantasy.

**Fix:** ship the level sprites, then delete the `visible = false` overrides and the early-returns
guarded by `if rig != null and not rig.visible`. If the skeletal rig is the intended final art, point
`_show_level()` at rig textures/scales instead of `bot_sprite`.

---

## 4. `TidbitBubble` is permanently hidden (P1)

`main.tscn:87-98` sets `TidbitBubble.visible = false`. The only writer is `companion.gd`, which
assigns `.text` in five places (`_on_tidbit`, `_on_tidbit_current`, `_on_insight`,
`_show_retention_insight_if_any`, `_on_pomodoro_phase`, `_on_campaign_pressed`) but **never sets
`.visible = true`**.

**Impact:** all curriculum lines, pomodoro prompts, mastery insights and the "Reach Level 5 first"
explanation are invisible. The Level-5 gate has no in-game explanation.

**Fix:** set `visible = true` wherever text is assigned (or start visible in the scene and only hide
when empty). Consider auto-hiding after a few seconds with a tween.

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

## 6. Champion soft-lock (P1)

`session_manager.gd:473-512`

- `is_champion_available()` requires **every gym cleared**.
- `begin_champion_battle()` returns `false` when `champion_moveset()` (Mastered questions only) is
  empty.
- A first-time win only promotes a question to `LEARNING`, so clearing every gym on the first
  attempt can leave **zero** Mastered questions.
- The comment above the section says the moveset "falls back to every question", but the code has no
  fallback anywhere.

**Impact:** the region can never be completed; the Champion stays "not ready" until the player
deliberately loses/rematches enough questions to reach `MASTERED`.

**Fix:** implement the documented fallback (all questions when no Mastered ones exist), or gate
availability on "all gyms cleared **or** ≥1 Mastered question" and message it in the encounter panel.

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

## 8. No Feed / Pet / Play input in the care room (P0)

`companion.gd:127` defines `_on_care(action)`, and `CompanionState.care()` is complete — but
`main.tscn` has no buttons wired to any action. `ButtonJuice` is applied only to the four icon
buttons (campaign / charge / settings / pomodoro).

**Impact:** the pet loop cannot be played, so Level 5 (and therefore the campaign) is unreachable
without editing the save file.

**Fix:** add three action buttons (or tap zones on the pet) and connect
`pressed → _on_care.bind("feed"|"pet"|"play")`, then play the matching reaction
(`rig.play_reaction(action)`) and SFX.

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

## 10. Progress is not saved after battles or topic confirm (P1)

`SaveManager.save_game()` is only called from care taps, level-up, campaign unlock and Settings.
Mastery changes, cleared trainers/gyms, champion clears, new/edited topics and extraction results
all mutate memory only (`data-model.md` §7).

**Impact:** quitting after a battle or a new topic loses that work; `CompanionState.add_xp()` from a
battle is also lost.

**Fix:** save in `SessionManager.report_battle_result()`, `confirm_topic()` and after a champion win.
Longer term, debounce a dirty flag instead of writing the whole file per event.

---

## 11. Large-text accessibility toggle is unreachable (P2)

`GameState.set_large_text()` exists, is persisted, applied on load, and `companion.gd` listens for
the signal — but nothing calls it. `settings.tscn` exposes only premium and quota reset.

**Fix:** add a `CheckBox` in Settings bound to `GameState.set_large_text(pressed)`. The root-theme
assignment in `_apply_theme_font_size()` already propagates to instantiated screens.

---

## 12. `Condition "det == 0" is true` from the rig (P2)

Running `main.tscn` headless prints:

```
WARNING: No Bone2D children of node EarL. Cannot calculate bone length or angle reliably.
WARNING: No Bone2D children of node EarR. …
WARNING: No Bone2D children of node Antenna. …
ERROR: Condition "det == 0" is true.        (×5)
```

Cause: leaf bones have zero length, and `companion_rig.gd:59-63` snaps `rest` to the current
transform while the skeleton contains degenerate bones; the weight painting then feeds a singular
transform into `Polygon2D` skinning.

**Fix:** give each leaf bone a non-zero rest length (a small child marker or an explicit
`rest` offset), or skip `_paint_weights()` for vertices dominated by zero-length bones. Harmless
today only because the rig is hidden.

---

## 13. `stats_changed` fires every frame (P2)

`companion_state.gd:62-67` emits inside `_process`, so `hud_strip.gd:_refresh()` re-reads five nodes
60×/s, and `pomodoro.gd` re-renders too, on every screen where they exist.

**Fix:** accumulate decay and emit at ~5 Hz, or emit only when a value actually changed. Keep the
signal semantic ("stats changed"), not "a frame passed".

---

## 14. Full save write on every care tap (P2)

`companion.gd:135` calls `SaveManager.save_game()` after each tap; the save JSON includes every
question in every topic, so it grows with the content the player uploads. On mobile this is a
synchronous `FileAccess` write per tap.

**Fix:** debounce (e.g. save at most once every 5 s, plus on `NOTIFICATION_WM_CLOSE_REQUEST` /
`NOTIFICATION_APPLICATION_PAUSED`).

---

## 15. Identification answers consume grading quota (P2)

`Api.grade_battle_question()` consumes a `"grade"` unit for every submission, including
Identification questions that are graded locally by string comparison. Free tier = 10/week, so a
topic with 12 ID questions exhausts the week's quota without a single LLM call.

**Fix:** only consume quota on the paths that would hit the API (essay grading / extraction), or
make the limit `pdfs` + `essays` and document it.

---

## 16. Save file loaded twice at boot (P3)

`main.gd:4` calls `SaveManager.load_game()`, then the child `Room` node's `companion.gd:34` calls it
again. The second load re-emits `stats_changed` / `xp_changed` and re-runs the monetization clamps.

**Fix:** keep only the `main.gd` call (or move the load into `SaveManager._ready()` once, ordered
after the state autoloads).

---

## 17. Duplicate `overworld_progress_changed` emissions (P3)

`_recheck_gym_clear()` (`session_manager.gd:230-240`) emits inside the `for` loop **and** again after
it, so a single trainer win can fire the signal N+1 times and rebuild the HUD each time.

**Fix:** move the emit out of the loop; only emit if a gym actually became cleared.

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
- `session_manager.gd:465-467` documents a fallback that was never implemented (see #6).

**Fix:** the root README is corrected in this docs pass; consider a `tests/` folder with a headless
GUT suite and a GitHub Action that runs `godot --headless --import` (which is how issues #1/#12 were
caught).

---

## 21. Theme and scene colours predate the canonical palette (P3)

**Evidence**

- `assets/theme/app_theme.tres:7,14,23` uses navy button/panel fills (`#1C264F`, `#0A122B`) and `#EDF5FF`
  button text; none are in the palette in [`ui-and-assets.md`](ui-and-assets.md#color-palette) §1.
- `scenes/ui/widgets/hud_strip.tscn:6-61`, `scenes/ui/session_list.tscn:21`, `scenes/battle/battle.tscn:28`, and
  `scenes/ui/main.tscn:43` hard-code other navy/cyan/blue values. (`loading.tscn` has been migrated.)
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
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/ui/main.tscn --quit-after 20
```

`--import` does **not** catch missing textures inside scenes; the per-scene runs do.
