# Rules

Non-negotiables for anyone — human or agent — changing this repo. Rationale lives in the linked doc,
not here.

## 1. The maintainer runs git

The maintainer owns the repository's history. **Never run anything that changes the index, the
working tree or history** — `add`, `commit`, `amend`, `push`, `merge`, `rebase`, `reset`, `restore`,
`checkout`, `stash`, `clean`, or creating branches and tags.

Read-only inspection is expected: `git status`, `git diff`, `git log`, `git show`. Verifying a claim
often means looking at the tree. This holds **unless the maintainer explicitly asks for a git action
in the current task** — then do only that action, not a wider history rewrite.

**Hand off instead.** Report what changed and propose a commit message; let the maintainer run it. If
a commit looks wrong, say so rather than repairing it.

## 2. The docs are the contract

Any change that alters behaviour, structure, tuning, scenes, assets, autoloads, the save schema or a
workflow updates the owning doc **in the same change**. If a doc and the code disagree, one of them
is a bug — fix the wrong one now. Stale documentation is a defect, not a chore for later.

| You changed | Update |
|---|---|
| an autoload, its order, or scene flow | [`architecture.md`](architecture.md) |
| a save field, its default, or `"v"` | [`data-model.md`](data-model.md) |
| a tuning constant or formula | the owning [`systems/*.md`](systems) |
| a scene, node path, screen or control | [`ui-and-assets.md`](ui-and-assets.md) |
| an HTTP call, signal, mock shape or `MOCK` behaviour | [`api-backend.md`](api-backend.md) |
| an asset (add, remove, rename) | the inventory in [`ui-and-assets.md`](ui-and-assets.md) |
| a feature's status, or you fixed a bug | [`build-plan-status.md`](build-plan-status.md), [`known-issues.md`](known-issues.md) |
| a new term | [`glossary.md`](glossary.md) |
| a repeatable procedure | [`skills.md`](skills.md) |
| what is in flight, blocked or next | [`tasks.md`](tasks.md) |

[`tasks.md`](tasks.md) is **derived**: it records status only. When it disagrees with the doc that
owns the subject, the owning doc wins.

## 3. Comments state invariants; docs carry explanations

Code comments are for the *why* the code cannot show, in one line. No narration, no section banners,
no author or tool tags (`# ponytail:`), no restating what the next line does, no commented-out code.

Pointers are the preferred form:

```gdscript
# Contract: docs/systems/battle.md
```

A deliberate deferral gets exactly one form, so it can be found later:

```gdscript
# shortcut: identification grades locally, move to the API when essay grading ships
```

Reasoning, history and design rationale belong in `docs/` — see §2. If a block needs a paragraph to
explain itself, the explanation goes in the doc and the code gets a pointer.

## 4. The approach is Ponytail

Take the first rung that fully works: **does it need to exist → already in this codebase → the Godot
built-in or platform feature → an installed dependency → one line → the minimum that works.**

No abstraction, wrapper, option, config or "for later" code nobody asked for. Deletion beats
addition, and the shortest working diff wins — once you know everything it must touch, including
callers, scenes and docs.

Never cut: validation at trust boundaries, error handling that prevents data loss, security,
accessibility, or anything the user asked for.

The full skill is at [`.opencode/skills/ponytail/SKILL.md`](../.opencode/skills/ponytail/SKILL.md).
It is **project-scoped**; do not install it globally, and do not add a global dependency for
anything this repo can vendor.

## 5. Godot contracts

**Generated files are not source.** Never hand-edit `.godot/`, `*.import` or `*.uid`. Godot rewrites
them; a hand edit is lost or corrupts the import cache. Change the source asset and let the editor
re-import.

**A missing `ext_resource` is a parse error.** A `.tscn` that references a missing texture, scene or
script does not load at all — it is not a runtime warning and no null-guard can catch it. Only
reference files that exist in the repo (see issue #1 in [`known-issues.md`](known-issues.md)).

**Autoloads are API.** Registering, removing or reordering an entry in `[autoload]` in
`project.godot` changes global names and `_ready()` order. Update [`architecture.md`](architecture.md)
and [`data-model.md`](data-model.md) in the same change.

**Scene transitions go through `change_scene_to_file()`** with a path that already resolves. Do not
build paths by string concatenation.

**Save changes are versioned.** Additive fields get a default in the loader; a semantic change bumps
the version literal (`data["v"] = 7` in `save_manager.gd`) and documents the migration in
[`data-model.md`](data-model.md). Never silently reinterpret an existing field.

**Mock mode stays working.** The editor, the headless gates and debug builds run on `Api.MOCK`. When
you add a real request, keep the mock branch functional and keep the response shape in
[`api-backend.md`](api-backend.md) truthful.

**Async results carry a unique `job_id`.** `Api.job_status` is a broadcast bus; a handler that
matches on `"grade"` instead of a per-request id will consume another screen's result (issue #9).

**UI is one portrait screen at a time.** 720 × 1280, stretch `canvas_items`, aspect `expand`. Use
`assets/theme/app_theme.tres` for type and colour; do not hard-code a second font or palette in a screen. Every
interactive control needs a visible focus/pressed state and a touch target of at least 44 × 44 px.

**Use the canonical palette.** New UI takes its colours from
[`ui-and-assets.md`](ui-and-assets.md#color-palette); do not introduce off-palette colours. Existing
screens still carry pre-palette values (issue #21).

**Assets are committed with their import.** New art goes under `assets/` with a lowercase
`snake_case` name, and the inventory in [`ui-and-assets.md`](ui-and-assets.md) is updated. Do not
leave untracked art that a scene references.

## 6. Verify before handing off

A change is not done until the gates pass. This repo has no test framework; the gates are headless
Godot runs. `$GODOT` is the 4.7.2 **console** binary — its path on the current machine is in
[`skills.md`](skills.md) §*Verify a change*.

```powershell
# whole-project import / parse check
& $GODOT --headless --path . --import

# every scene you touched (and the main scene)
& $GODOT --headless --path . res://scenes/ui/boot/splash.tscn --quit-after 10
& $GODOT --headless --path . res://scenes/ui/boot/peek.tscn --quit-after 30
& $GODOT --headless --path . res://scenes/battle/battle.tscn --quit-after 20
& $GODOT --headless --path . res://scenes/overworld/region_map.tscn --quit-after 30
```

`--import` does **not** catch missing textures inside scenes; the per-scene runs do. Expected noise
(ObjectDB leaks, resources still in use on early `--quit-after` exits, `det == 0`) is listed in
[`skills.md`](skills.md#verify-a-change) and issues #3/#12 — new errors are not.

Also check that every relative Markdown link you touched resolves, and verify the claim in the same
way a reader would (open the file, run the scene). [`skills.md`](skills.md) has the procedure.

## 7. Known gaps are tracked, not hidden

[`known-issues.md`](known-issues.md) is the register: numbered, with evidence and a fix. Do not
delete an entry to make a status table look green — fix it, or say in [`tasks.md`](tasks.md) that it
is blocked and why. Severity definitions live in that file.

## Open questions

These are unresolved and belong to the docs that own them:

1. ~~**Backend contract.**~~ Settled: `/v1/extract` and `/v1/grade` with the job envelope on both
   sides ([`api-backend.md`](api-backend.md) §2; issue #7 fixed).
2. ~~**Auth.**~~ Settled for v1: no accounts; saves stay on the device and the header was removed
   (issue #2).
3. **Codex.** The remote branch `feat/remove-codex` suggests it is being cut. Keep the button out of
   the UI until that lands.
