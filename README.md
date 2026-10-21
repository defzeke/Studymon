# 🎒🤖 Kuizmon

> A gamified study-review app built in Godot where you raise an AI/robot companion and use it to turn your class notes and reviewers into a Pokémon-style battle campaign.

---

## 🌟 Overview

**Kuizmon** bridges the gap between productive studying and engaging gameplay. By uploading your study materials (PDF reviewers), your companion digests the content and generates a region of gym battles, trainer encounters, and a cumulative Champion exam. Care for your companion, keep its energy and focus high, and master your subjects to conquer the campaign!

**Current state:** a playable-on-mocks vertical slice. The full loop (care → Level 5 → upload → edit questions → overworld → battle → mastery → Champion) is implemented in GDScript, with the AI backend stubbed behind `Api.MOCK`. See [`docs/known-issues.md`](docs/known-issues.md) before running it — the battle scene currently references missing pet sprites.

---

## 📁 Project Structure

```text
res://
├── project.godot              # Godot 4.7.2, portrait 720×1280, Mobile renderer
├── icon.svg
│
├── assets/
│   ├── audio/                 # BGM + SFX (main room loop, charge/charged)
│   ├── fonts/                 # Josefin Sans (Regular + Bold) — the project theme font
│   └── sprites/
│       ├── kuizmon_loading.gif # splash source (not imported by Godot)
│       ├── kuizmon_splash.png  # 60-frame splash sheet
│       ├── loading.png         # loading background
│       ├── logo.png            # loading wordmark
│       ├── companion/          # idle / blink / sad / happy / charge / complete (SVG)
│       ├── rooms/              # temporary rooms: study_room (+ night), maintenance_bay, data_kitchen, playroom
│       └── ui/                 # campaign, charge, pomodoro, settings, table, top bar
│
├── autoload/                  # Phase-0 global singletons
│   ├── api.gd                 # Api — HTTP wrapper + the entire mock backend
│   └── game_state.gd          # GameState — campaign unlock, region, large-text
│
├── scripts/
│   ├── autoload/              # SaveManager, CompanionState, SessionManager,
│   │                          # MonetizationState, MusicManager
│   ├── battle/                # battle.gd — turn resolution, damage, juice
│   ├── companion/             # care room, skeletal rig
│   ├── overworld/             # region map generation, player movement
│   ├── review_session/        # upload + editable question list
│   └── ui/                    # splash, loading, peek + tutorial, care room root, session list,
│                              # settings, pomodoro, HUD strip, button feedback
│
├── scenes/                    # .tscn files mirroring scripts/<feature>/
│   ├── battle/                ├── companion/      ├── overworld/
│   ├── review_session/        └── ui/
│
├── ui/                        # Shared theme + reusable HUD widgets
│   ├── app_theme.tres         # single shared Theme (all screens use it)
│   ├── hud_strip.tscn         # Energy / Focus / Mood + Level, instanced per screen
│   └── pomodoro.tscn          # focus/rest timer panel
│
├── backend/                   # FastAPI skeleton (health check only, for now)
│
├── docs/                      # 📖 technical documentation — start at docs/README.md
├── README.md
└── quizmon-build-plan.md      # original phase plan (historical; see docs/build-plan-status.md)
```

`companion/`, `battle/`, and `review_session/` at the repository root hold planning contracts only;
their implementation lives under `scripts/` and `scenes/`.

---

## 🚀 Core Gameplay Loops

1. **Pre-Campaign Loop (Level 1–5):** Meet your baby AI companion, perform Pou-style care taps (*Feed*, *Pet*, *Play*) that teach beginner AI concepts, earn XP, and unlock the review campaign at Level 5.
2. **Main Campaign Loop (Level 5+):** Upload study materials → AI extracts concepts → navigate the 3D island overworld → clear Identification and Essay encounters → face the regional Champion!

Supporting systems: an hourly-capped XP curve, stat decay and a Pomodoro focus/rest cycle, a
five-step AI-literacy codex, colourblind-safe per-question mastery that decays after 7 days, and a
free-tier quota gate on AI usage.

---

## 🛠 Running the project

Requires **Godot 4.7.x** (the project was built and verified on 4.7.2).

```bash
# open in the editor
godot --path . --editor

# or run the game directly
godot --path .
```

Optional backend (not used by the client while `Api.MOCK = true`):

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000   # GET /health -> {"ok": true}
```

Saves live at `user://studymon_save.json`; delete that file to reset progress.

---

## 📖 Documentation

| Document | What's inside |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Entry point for agents — links to the rules, index and task register |
| [`docs/rules.md`](docs/rules.md) | **The contract**: git ownership, doc updates, comment style, Godot rules, verification gates |
| [`docs/README.md`](docs/README.md) | Index and how to read the docs folder |
| [`docs/skills.md`](docs/skills.md) | Repeatable procedures (verify, add a screen, add a question type, wire the backend) |
| [`docs/tasks.md`](docs/tasks.md) | What is in flight, blocked, next, or waiting on a decision |
| [`docs/glossary.md`](docs/glossary.md) | Domain, engine and process terms |
| [`docs/architecture.md`](docs/architecture.md) | Autoloads, scene flow, state ownership, signals |
| [`docs/data-model.md`](docs/data-model.md) | Save schema, question/topic shapes, mastery records |
| [`docs/systems/`](docs/systems) | Per-system deep dives (care, review, overworld, battle, monetization) |
| [`docs/ui-and-assets.md`](docs/ui-and-assets.md) | Screens, theme, controls, asset inventory |
| [`docs/api-backend.md`](docs/api-backend.md) | Client API surface, mock mode, backend contract |
| [`docs/known-issues.md`](docs/known-issues.md) | **Known bugs and gaps, with fixes** |
| [`docs/build-plan-status.md`](docs/build-plan-status.md) | Phase 0–10 status vs the original plan |

---

## 📄 License

No license file is present in this repository yet.
