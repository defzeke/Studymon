# Skills

Repeatable procedures. Each one is written to be run start to finish without needing the history
behind it.

## Verify a change

This repo has no test framework and no CI. Verification is a headless Godot run.

**Prerequisite.** Godot **4.7.2** console build. It is not on `PATH` on the current machine:

```powershell
$GODOT = "C:\Users\user\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
```

**Steps.**

1. Import the project. This catches script parse errors and broken `.import` files, but **not**
   missing textures inside scenes:

   ```powershell
   & $GODOT --headless --path . --import
   ```

2. Run every scene you touched, plus the main scene. `--quit-after` takes frames, not seconds.

   ```powershell
   & $GODOT --headless --path . res://scenes/ui/main.tscn          --quit-after 20
   & $GODOT --headless --path . res://scenes/ui/splash.tscn        --quit-after 10
   & $GODOT --headless --path . res://scenes/ui/loading.tscn       --quit-after 10
   & $GODOT --headless --path . res://scenes/ui/peek.tscn          --quit-after 30
   & $GODOT --headless --path . res://scenes/battle/battle.tscn    --quit-after 20
   & $GODOT --headless --path . res://scenes/overworld/region_map.tscn --quit-after 30
   ```

3. Read the output, not the exit code. Godot exits `0` after a parse error in a scene. A touched
   scene must load with no new `ERROR:` lines.

4. Check links you added or moved:

   ```powershell
   Get-ChildItem -Recurse -Filter *.md |
     Where-Object { $_.FullName -notmatch '\\\.godot\\' } |
     ForEach-Object {
       $file = $_
       [regex]::Matches((Get-Content $file.FullName -Raw), '\]\(([^)]+)\)') | ForEach-Object {
         $link = $_.Groups[1].Value.Split('#')[0]
         if ($link -and $link -notmatch '^(https?:|mailto:)') {
           if (-not (Test-Path (Join-Path $file.DirectoryName $link))) {
             "{0}: missing {1}" -f $file.FullName, $link
           }
         }
       }
     }
   ```

   No output means every relative link resolves.

**Expected noise** (not new failures): `ObjectDB instances leaked at exit`, `1 resources still in
use at exit` when `--quit-after` ends a scene mid-tween, and the rig warnings listed as issues #3 and
#12 in [`known-issues.md`](known-issues.md). Anything else is a regression.

**Optional backend check** (only when working in `backend/`):

```powershell
cd backend
uvicorn main:app --port 8000    # GET /health
```

## Add or fix a scene

1. Edit `.tscn` files in the Godot editor when possible; it keeps `uid`, `load_steps` and import
   metadata consistent. If you must edit text, keep the header intact and do not renumber
   `ExtResource` ids.
2. Every `[ext_resource]` must point at a file that exists. A missing one is a **parse error**, not a
   warning — see issue #1. Verify with the per-scene run above.
3. Node paths are a contract with the script. `$Node` / `%UniqueName` / `get_node()` paths in the
   attached script must match the scene after the edit. Search the script for `@onready` and the node
   name before renaming.
4. A scene opened directly (not through the `splash.tscn` → `loading.tscn` → `peek.tscn` boot path) gets no
   autoload guarantees beyond `project.godot`. Keep the `get_node_or_null("/root/...")` guards where
   they already exist.
5. Update [`ui-and-assets.md`](ui-and-assets.md) if the node tree, screen or referenced asset
   changed.

## Add a screen

1. Scene under `scenes/<area>/`, script under `scripts/<area>/`, same base name.
2. Root should be a `Control` (full rect) for UI, `Node2D` for a world. Set the shared theme through
   `project.godot`; do not assign a local theme unless the screen genuinely differs.
3. Wire entry and exit with `get_tree().change_scene_to_file("res://scenes/...")`. Add a back path —
   every screen reachable from the care room or overworld must be escapable on a phone with no
   keyboard.
4. Apply `ButtonJuice` to new buttons if the screen is part of the main loop; it is the existing
   press-feedback helper.
5. Add the screen to the node-tree table in [`ui-and-assets.md`](ui-and-assets.md) and to the scene
   flow in [`architecture.md`](architecture.md) if it adds a transition.

## Rebuild the splash sprite sheet

Godot has no GIF importer. `splash.gd` reads a baked 6 × 10 sheet: 60 frames of 480 × 264 at 30 ms
each. The source is [`assets/sprites/kuizmon_loading.gif`](../assets/sprites/kuizmon_loading.gif).

1. Regenerate the sheet with Windows PowerShell and `System.Drawing`:

   ```powershell
   Add-Type -AssemblyName System.Drawing
   $gif = [System.Drawing.Image]::FromFile((Resolve-Path "assets\sprites\kuizmon_loading.gif").Path)
   $fd = [System.Drawing.Imaging.FrameDimension]::Time
   $n = $gif.GetFrameCount($fd)
   $cols = 6; $rows = [math]::Ceiling($n / $cols); $fw = 480; $fh = 264
   $sheet = New-Object System.Drawing.Bitmap ($cols * $fw), ($rows * $fh)
   $g = [System.Drawing.Graphics]::FromImage($sheet)
   $g.Clear([System.Drawing.Color]::White)
   $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
   $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
   for ($i = 0; $i -lt $n; $i++) {
     $gif.SelectActiveFrame($fd, $i) | Out-Null
     $g.DrawImage($gif, ($i % $cols) * $fw, [math]::Floor($i / $cols) * $fh, $fw, $fh)
   }
   $g.Dispose()
   $sheet.Save((Join-Path (Get-Location) "assets\sprites\kuizmon_splash.png"), [System.Drawing.Imaging.ImageFormat]::Png)
   $sheet.Dispose(); $gif.Dispose()
   ```

2. Let Godot reimport it (using `$GODOT` from §*Verify a change*):

   ```powershell
   & $GODOT --headless --path . --import
   ```

3. If the frame count, cell size or grid changed, update `FRAME_COUNT`, `FRAME_SIZE`, `COLUMNS`
   and `FRAME_TIME` at the top of `scripts/ui/splash.gd` in the same change.

4. Smoke-test `res://scenes/ui/splash.tscn` and capture a frame to confirm the logo is centred on
   white.

## Add a question type

The two live types are `"identification"` and `"essay"`; the type is also the gym bucket. A third
type touches five places:

1. **Categorizer UI** — `categorizer.gd:247-251` builds the `OptionButton` with two hard-coded
   entries, and `_on_type_changed()` (`:273-276`) maps index → type. Add the item and the mapping.
2. **Mock grading** — `Api._execute_mock_grade()` (`autoload/api.gd:276-329`) branches on
   `identification` vs everything else. Add the branch, or the new type is graded as an essay.
3. **Battle input** — `battle.gd:86` sets the placeholder and `:151` branches on type for KO juice.
   Check the answer field is usable for the new shape.
4. **Gym bucketing** — `SessionManager` groups questions by `type` when it builds gyms
   (`scripts/autoload/session_manager.gd:183`, `:202`, `:293`). Decide whether the new type is its
   own gym or joins an existing one.
5. **Docs** — update [`data-model.md`](data-model.md) (question shape), [`systems/battle.md`](systems/battle.md)
   (grading and damage), [`systems/overworld.md`](systems/overworld.md) (gym rules).

Then run the four verification scenes. A new type that only exists in the mock is still a change to
the contract — say so in [`api-backend.md`](api-backend.md).

## Tune the XP or decay curve

All companion tuning is in `scripts/autoload/companion_state.gd`:

| Constant | Current | Effect |
|---|---|---|
| `XP_PER_LEVEL` | `[0, 20, 45, 75, 110, 150]` | Cumulative XP per level (Lv5 at 150) |
| `DAILY_CAP_BASE_XP` | `10` | Same-action taps per hour before diminishing returns |
| `STAT_DECAY_PER_SEC` | `0.15` | Energy drain per second (focus ×0.8, mood ×0.6) |
| `POMODORO_FOCUS_SEC` / `REST_SEC` | `1500` / `300` | Focus and rest lengths |
| `care()` | `feed +2`, `pet +1`, `play +2` | XP per tap; also ±8 to a stat |

1. Change the constant, not the caller.
2. Recompute the pacing note in the comment block above `XP_PER_LEVEL` if the level budget moved.
   That note is the only tuning comment allowed to be long — it is a formula, not narration.
3. Update the table in [`systems/companion-care.md`](systems/companion-care.md).
4. Re-check the interaction with the hourly cap: `int(2 * 0.3) == 0`, so any multiplier path must
   floor at 1 XP (issue #5). Fix that before adding another multiplier.

## Add companion art

The game looks for `res://assets/sprites/bot_lv1.png` … `bot_lv5.png`.

1. Export five PNGs at the same canvas size and baseline, transparent background, and drop them in
   `assets/sprites/`.
2. Let the editor import them (`.import` files are generated — never hand-write them).
3. `companion.gd:77-86` auto-loads any that exist. `battle.tscn` references `bot_lv1.png` /
   `bot_lv5.png` directly, so adding the five files also resolves issue #1 (its parse errors).
4. Art alone does not make the pet appear. `_show_level()` and every care animation early-return
   while `rig.visible` is false, and both `main.tscn:83` and `companion.gd:36-37` force it false.
   Removing those flags is issue #3, and is what actually reveals the art.
5. Add the files to the asset inventory in [`ui-and-assets.md`](ui-and-assets.md).

## Wire the real backend

1. The switch is `const MOCK := true` in `autoload/api.gd:11`. Flipping it disables every mock path,
   so the endpoints below must exist first.
2. Contract the client already calls:
   - `POST /battle/grade` — `{type, question, answer, source, expected, key_concepts}`
   - `PUT /topics/{topic_id}` — `{questions: [...]}`
   - `PUT /mastery/{topic_id}/{question_id}` — `{state}`
   - `GET /health` — exists in the FastAPI stub.
3. `_on_request_completed()` (`api.gd:21-32`) only emits `job_status` when the body has a `job_id`.
   Either return `{job_id, status, progress, result}` for every call, or add a separate signal for
   plain payloads (issue #9). Also handle non-2xx: today `401`, `500` and a timeout are
   indistinguishable from an empty success.
4. Keep the mock branch working while the real path lands: the game still ships on it.
5. Update [`api-backend.md`](api-backend.md) and `backend/README.md` in the same change, or the
   drift in issue #7 gets worse.

## Reset a save / debug progression

The save is `user://studymon_save.json`, which on Windows is:

```
%APPDATA%\Godot\app_userdata\Studymon\studymon_save.json
```

Delete it (or call `SaveManager.reset_save()`) to start again at Level 1. Boot reads the save when
home first opens after the tutorial; the old 2D care room is only reachable by opening
`res://scenes/ui/main.tscn` directly. To test the campaign
without earning 150 XP, set `"level": 5`, `"xp": 150`, `"campaign_ready": true` in the JSON, or call
`CompanionState.add_xp(150)` from a temporary debug line. Do not commit debug lines or edited saves.

## Clean up comments

1. Find the tagged ones: `rg -n '#\s*(ponytail|TODO|FIXME|HACK)' .`
2. Delete narration and author tags. Keep an invariant only if removing it would let the next reader
   break the code.
3. Convert real explanations into a `# Contract: docs/...` pointer and move the prose into the doc.
4. Convert deliberate deferrals to `# shortcut: <limit>, <when to upgrade>`.
5. Run the verification scenes — a deleted comment is harmless, a deleted guard is not.

## Run Ponytail

The project skill is at [`.opencode/skills/ponytail/SKILL.md`](../.opencode/skills/ponytail/SKILL.md).
Load it when implementing, reviewing, refactoring or choosing an approach. It is project-scoped by
design — do not install it globally or copy it into a global config.

Use the ladder before writing: does it need to exist → already in this codebase → a Godot built-in →
an installed dependency → one line → the minimum that works.

## Update docs in the same change

[`rules.md`](rules.md) §2 has the full mapping. The short version: if the change alters behaviour,
structure, tuning, a scene, an asset, an autoload, the save schema or a procedure, the owning doc is
part of the change. `tasks.md` only records status; the owning doc wins if they disagree.
