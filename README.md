```
# 🎒🤖 Studymon

> A gamified study-review app built in Godot where you raise an AI/robot companion and use it to turn your class notes and reviewers into a Pokémon-style battle campaign.

---

## 🌟 Overview

**Studymon** bridges the gap between productive studying and engaging gameplay. By uploading your study materials (PDF reviewers), your companion digests the content and generates a region of gym battles, trainer encounters, and a cumulative Champion exam. Care for your companion, keep its energy and focus high, and master your subjects to conquer the campaign!

---

## 📁 Project Folder Structure

This repository follows a clean, feature-driven folder organization optimized for Godot 4.x:

```text
res://
├── assets/                    # Raw source files (art, audio, fonts)
│   ├── audio/                 # SFX and background music
│   ├── fonts/                 # Typography (.ttf / .otf)
│   ├── sprites/               # Companion animations, UI icons, battle backgrounds
│   └── themes/                # Godot Theme resources (.tres) for UI styling
│
├── scenes/                    # Reusable scene files (.tscn)
│   ├── battle/                # Battle arena, health bars, damage numbers, question prompts
│   ├── companion/             # AI companion pet-care room, avatar, feeding/tap animations
│   ├── overworld/             # 2D region map, gym hallways, trainer nodes
│   └── ui/                    # Menus (Main Menu, Session List, Upload/Categorizer, AI Codex, Scheduler)
│
├── scripts/                   # GDScript code files (.gd)
│   ├── autoload/              # Global singletons (GameManager, SaveManager, AIService, SoundManager)
│   ├── battle/                # Turn logic, essay grading calculator, ID check handlers
│   ├── companion/             # Pet-care state machine, XP curve, AI literacy curriculum tracker
│   ├── overworld/             # Map navigation, gym progression, mastery state machine
│   └── ui/                    # Menu controllers, session list management, PDF parser UI
│
├── resources/                 # Custom Resource files (.tres)
│   ├── companion_profiles/    # Base companion stats, evolution milestones, cosmetic unlocks
│   ├── questions/             # Topic schemas, question templates, mastery badges
│   └── ai_codex/              # Literacy tidbits curriculum data (Levels 1–5)
│
└── tests/                     # Optional debug scenes or prototype sandboxes (e.g., PDF parser test)
```

---

## 🚀 Core Gameplay Loops

1. **Pre-Campaign Loop (Level 1–5):** Meet your baby AI companion, perform Pou-style care taps (*Feed*, *Pet*, *Play*) that teach beginner AI concepts, earn XP, and unlock the review campaign at Level 5.
2. **Main Campaign Loop (Level 5+):** Upload study PDFs $
ightarrow$ AI extracts concepts $
ightarrow$ Navigate the 2D overworld gym hallways $
ightarrow$ Clear Essay and Identification encounters $
ightarrow$ Face the regional Champion!
```

