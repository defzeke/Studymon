# Monetization / quotas

The premium hook implemented so far is **AI-usage quota**, not cosmetics: free players get a
limited number of PDF ingestions and answer gradings per week. This matches the build plan's
recommendation (§Phase 10) because it maps to the real variable cost (LLM calls).

- **State:** `scripts/autoload/monetization_state.gd` (autoload `MonetizationState`)
- **Gates:** `autoload/api.gd`
- **UI:** `scenes/ui/settings.tscn`, `scenes/review_session/categorizer.tscn`,
  `scenes/battle/battle.tscn`
- **Persistence:** inside `SaveManager` (`monetization` block)

Status: **Mock.** `is_premium` is a checkbox. There is no store, no receipt, no server check.

---

## 1. Limits

```gdscript
const FREE_PDF_LIMIT   := 3      # extractions per week
const FREE_GRADE_LIMIT := 10     # gradings per week
const WEEK_SECONDS     := 604800
```

Premium bypasses both (`can_consume` returns true, `consume` is a no-op, `get_remaining` returns
999).

---

## 2. API

| Method | Behaviour |
|---|---|
| `can_consume(type)` | `true` for premium; otherwise `used < limit` (also triggers rollover) |
| `consume(type)` | `false` if not allowed; otherwise increments and emits `quota_changed` |
| `get_remaining(type)` | `999` for premium, else clamped remaining (also triggers rollover) |
| `get_quota_label()` | `"Premium: Unlimited"` or `"Free AI Uses: PDFs r/3 \| Grades r/10"` |
| `set_premium(bool)` | flips the flag, emits `premium_changed` + `quota_changed` |
| `reset_quota()` | zeroes both counters and restarts the week |
| `to_dict()` / `from_dict()` | save/restore the four fields |

Valid `type` values are `"pdf"` and `"grade"`; **any other string returns `false`**, so a typo in a
new call site silently blocks the action rather than failing loudly.

---

## 3. Weekly rollover

```text
week_start_unix == 0            → set to now (first ever call)
now >= week_start_unix + 604800 → reset both counters, week_start_unix = now
```

Checked lazily inside `can_consume()` / `get_remaining()` — never on a timer and never on load. A
player who leaves the app open for 8 days keeps the old counters until something calls these
methods.

The window is a rolling 7 × 24 h from first use, **not** aligned to a calendar week (no
"resets Monday" behaviour).

---

## 4. Gate points

| Gate | Location | Signal on failure |
|---|---|---|
| PDF extraction | `Api.mock_upload_pdf()` → `can_consume("pdf")` (`api.gd:99-105`) | `Api.quota_exceeded("pdf")` |
| Answer grading | `Api.grade_battle_question()` → `can_consume("grade")` (`api.gd:40-45`) | `Api.quota_exceeded("grade")` |

Both gates run **before** any work, and both consume **on success only**. Handlers:

- `battle.gd:118-124` — resets `_awaiting`, hides the "judging" label, re-enables submit, shows a
  `ConfirmationDialog` ("Weekly AI limit reached. Upgrade to Premium to continue.").
- `categorizer.gd:73-79` — same dialog; the `if type == "grade"` branch is a no-op duplicate of the
  line above it.

Neither handler provides a path to actually upgrade — the dialog is informational.

Note the asymmetry: the PDF gate fires *after* the categorizer has already switched to its
"AI is studying…" state, so a quota-blocked upload briefly looks like it is processing.

---

## 5. UI surfaces

### Settings (`settings.tscn`)

| Control | Behaviour |
|---|---|
| `PremiumCheck` | Toggles `set_premium()` and saves immediately |
| `QuotaLabel` | `Premium: Unlimited` or `Free AI Uses: PDFs r/3 \| Grades r/10` |
| `PdfQuotaLabel` / `GradeQuotaLabel` | Per-type remaining counts |
| `ResetButton` | `reset_quota()` — labelled as a simulated weekly rollover (a debug affordance) |
| `StatusLabel` | "Premium enabled — no limits." / "Free tier — weekly limits active." |

`settings.gd` guards every access with `get_node_or_null("/root/MonetizationState")`, so the scene
opens standalone in the editor without autoloads.

### Elsewhere

- Categorizer: `QuotaLabel` in the header.
- Battle: `QuotaLabel` under the top bar, refreshed on `quota_changed` / `premium_changed`.
- Both re-render on `premium_changed`, so toggling in Settings updates the next screen you open.

---

## 6. Persistence

Saved as:

```jsonc
"monetization": { "is_premium": false, "pdf_used_this_week": 0,
                  "grades_used_this_week": 0, "week_start_unix": 1760000000 }
```

`from_dict` clamps both counters to the free limits, which only matters for hand-edited saves. There
is no signature, no server-side counter, and no expiry — **the client is the source of truth**, so
this must move server-side before launch.

Quota is consumed before the next `SaveManager.save_game()` call, so usage can also be lost on a
crash (the counter resets to the last saved value) — generous to the player, but not something to
rely on.

---

## 7. Roadmap notes

The build plan names two follow-on layers that are **not implemented**:

1. **Async topic-deck sharing** (export/import a region as a code) as the multiplayer first step.
2. **Cosmetic / story milestones** for AI levels past 5, which currently do nothing because
   `add_xp()` early-returns at max level.

When a real store is added, the quota counters must move behind the backend so that
`is_premium` cannot be flipped from a save file.
