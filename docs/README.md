# Studymon — Documentation

Technical documentation for the current state of the `Studymon` Godot project.

This folder describes **what the code does today**, not what the build plan hopes it will do.
Where the two disagree, the docs say so explicitly.

> Studymon is a gamified study app: you raise an AI companion through tap-care, then feed it
> reviewer material that becomes a Pokémon-style gym campaign of Identification and Essay battles.

---

## Start here

| If you want to… | Read |
|---|---|
| **Change anything (start here)** | [`rules.md`](rules.md) |
| Pick up in-flight work | [`tasks.md`](tasks.md) |
| Run a repeatable procedure | [`skills.md`](skills.md) |
| Look up a term | [`glossary.md`](glossary.md) |
| Understand the runtime shape of the project | [`architecture.md`](architecture.md) |
| Know what is on disk / in the save file | [`data-model.md`](data-model.md) |
| Work on the pet-care loop | [`systems/companion-care.md`](systems/companion-care.md) |
| Work on upload → questions | [`systems/review-session.md`](systems/review-session.md) |
| Work on the map, gyms, mastery, Champion | [`systems/overworld.md`](systems/overworld.md) |
| Work on battles and answer grading | [`systems/battle.md`](systems/battle.md) |
| See the target gyms / difficulty / flashcard design | [`systems/gameplay-structure.md`](systems/gameplay-structure.md) |
| Work on free-tier limits / paywall | [`systems/monetization.md`](systems/monetization.md) |
| Change a screen or add art | [`ui-and-assets.md`](ui-and-assets.md) |
| Wire the real backend | [`api-backend.md`](api-backend.md) |
| **Fix something that is broken** | [`known-issues.md`](known-issues.md) |
| See plan-vs-reality per phase | [`build-plan-status.md`](build-plan-status.md) |

---

## Quick facts

| Item | Value |
|---|---|
| Engine | Godot **4.7.2** stable (`config/features = ("4.7", "Mobile")`) |
| Main scene | `res://scenes/ui/splash.tscn` |
| Viewport | 720 × 1280, stretch `canvas_items`, aspect `expand` |
| Renderer | `mobile`, D3D12 on Windows |
| Language | GDScript only (25 files, ~145 KB) |
| Scenes | 12 (`.tscn`) |
| Autoloads | 7 |
| Backend | FastAPI stub, `/health` only — client runs on `Api.MOCK = true` |
| Persistence | Single JSON file `user://studymon_save.json`, schema `"v": 4` |
| Tests / CI | None |

---

## Status vocabulary

Used consistently across these docs:

| Tag | Meaning |
|---|---|
| **Implemented** | Logic exists and runs end-to-end in the current code |
| **Mock** | Runs, but behind `Api.MOCK` / canned data instead of a real service |
| **Partial** | Some of the feature exists, some is missing or unreachable |
| **Missing** | Referenced by the build plan or README, not present in the repo |
| **Broken** | Present, but fails at runtime (see `known-issues.md`) |

---

## Relationship to the other docs in the repo

- [`../quizmon-build-plan.md`](../quizmon-build-plan.md) — the original 10-phase plan. Still the design
  intent, but its stack notes are stale (it says "Godot 4.6, avoid 4.7"; the project is on 4.7.2).
- [`../README.md`](../README.md) — player-facing overview.
- [`../AGENTS.md`](../AGENTS.md) — the agent entry point; it links to `rules.md`, this index and `tasks.md`.

---

## Conventions in these docs

- `file.gd:123` means line 123 of that file at the time of writing. Line numbers drift; symbol
  names do not — search by function name if a reference looks stale.
- Signal names are written as `signal_name`.
- "Autoload" always means an entry in `[autoload]` in `project.godot`.
- Constants are quoted with their real values so you can tune from the docs, but the code is
  always authoritative.

## Maintenance

The docs are part of every change, not a follow-up. [`rules.md`](rules.md) §2 has the full
change → document mapping, and it wins over anything listed here.

In short: behaviour, structure, tuning, a scene, an asset, an autoload, the save schema or a
procedure all update the page that owns them in the same change. When a bug is fixed, remove its
entry from [`known-issues.md`](known-issues.md) and update [`build-plan-status.md`](build-plan-status.md); see
[`tasks.md`](tasks.md) for how status is tracked.
