# Mixamo animation pipeline

The game ships with a **procedural fallback** so it runs and plays correctly
with no animation assets at all. Everything below is how you upgrade that
placeholder motion to real Mixamo clips.

Nothing here needs code changes — drop files in a folder and run one script.

---

## Why this pipeline exists

Mixamo hands you three problems:

| Problem | What the pipeline does |
| --- | --- |
| Every clip is named `mixamo.com` | Derives the real name from the **filename** (`Rifle Run.fbx` → `run_fwd`) |
| Every bone is prefixed `mixamorig:` | Strips the prefix from every track path |
| Locomotion clips drift off the collider | Removes hip translation so clips play in place |

It also sets loop flags per clip and writes everything into a single
`AnimationLibrary`, so the runtime loads one resource instead of 18 scenes.

---

## Step 1 — Download the clips

Go to [mixamo.com](https://www.mixamo.com) (free Adobe account required) and
download each clip below.

**Export settings that match this pipeline:**

| Setting | Value |
| --- | --- |
| Format | **FBX Binary (.fbx)** |
| Skin | **Without Skin** for animation clips |
| Frames per second | **30** |
| Reduce Keyframes | **unchecked** |
| In Place | **checked** for all walk / run / strafe / crouch clips |

Download the **character** itself separately with **With Skin**.

> Keep Mixamo's default filenames. The pipeline matches on them.

---

## Step 2 — The clip list

Search terms are what to type into Mixamo's search box. The matcher is
case-insensitive and takes the longest match, so extra words in a filename are
harmless.

| Clip name | Mixamo search | Loops | In place | Used for |
| --- | --- | --- | --- | --- |
| `idle` | Rifle Idle | ✓ | ✓ | Standing still |
| `walk_fwd` | Rifle Walk Forward | ✓ | ✓ | Normal movement |
| `walk_back` | Walk Backward | ✓ | ✓ | Backpedalling |
| `walk_left` | Strafe Left | ✓ | ✓ | Left strafe |
| `walk_right` | Strafe Right | ✓ | ✓ | Right strafe |
| `run_fwd` | Rifle Run | ✓ | ✓ | Sprinting |
| `sprint` | Fast Run | ✓ | ✓ | Optional faster tier |
| `crouch_idle` | Crouch Idle | ✓ | ✓ | Crouched, still |
| `crouch_walk` | Crouched Walking | ✓ | ✓ | Crouched, moving |
| `jump_start` | Jump Up | — | — | Takeoff |
| `jump_loop` | Falling Idle | ✓ | — | Airborne |
| `jump_land` | Hard Landing | — | — | Touchdown |
| `fire` | Firing Rifle | — | ✓ | Shooting |
| `reload` | Reloading | — | ✓ | Reload |
| `aim` | Rifle Aiming Idle | ✓ | ✓ | ADS hold |
| `hit_react` | Hit Reaction | — | — | Taking damage |
| `death_1` | Dying | — | — | Death |
| `death_2` | Death From Headshot | — | — | Headshot death |

**Missing clips are fine.** `CharacterAnimator._fallbacks()` substitutes
sensibly — `run_fwd` falls back to `walk_fwd`, then to `idle`. You can start
with just `idle`, `walk_fwd` and `fire` and add the rest later.

---

## Step 3 — Drop the files in

```
LoneWolf/assets/mixamo/raw/
    Rifle Idle.fbx
    Rifle Run.fbx
    Reloading.fbx
    ...
```

Godot imports them automatically when the editor regains focus.

---

## Step 4 — Build the library

In the Godot editor:

1. Open `tools/BuildMixamoLibrary.gd` in the script editor
2. Press **Ctrl+Shift+X** (or *File → Run*)

Output appears in the Output panel:

```
=== Lone Wolf :: Mixamo library build ===
source files found : 12
clips extracted    : 12

  CLIP           SOURCE                        LENGTH  TRACKS LOOP
  fire           Firing Rifle.fbx               1.03s      65 -
  idle           Rifle Idle.fbx                 4.20s      65 yes
  ...

saved -> res://assets/mixamo/retargeted/lonewolf_anims.res
```

That `.res` file is the only thing the game loads at runtime.

Two switches at the top of `BuildMixamoLibrary.gd`:

- `STRIP_BONE_PREFIX` — turn **off** if your character rig kept `mixamorig:`
  bone names (i.e. the character is itself a Mixamo download that you did not
  rename). On by default.
- `FORCE_IN_PLACE` — turn **off** if you want genuine root motion driving
  movement. On by default, because the controller drives position itself.

---

## Step 5 — Attach the character mesh

The placeholder capsules live at `Body/Mesh` in
`scenes/characters/Player.tscn` and `Bot.tscn`.

1. Import your Mixamo character (the **With Skin** download)
2. Drag its scene under the `Body` node
3. Delete or hide the placeholder `Mesh`
4. Point the character's `Skeleton3D` at the scene's existing `AnimationPlayer`

`CharacterAnimator` finds the `AnimationPlayer` through the exported
`animation_player_path`, already wired to `../AnimationPlayer` in both scenes.
Once `lonewolf_anims.res` exists, `has_clips` flips to `true` and the
procedural lean/bob switches itself off.

---

## How the runtime picks a clip

`CharacterAnimator._resolve_state()` runs this priority order each frame:

```
dead              → death_1
reloading/firing  → reload / fire
airborne          → jump_loop
still + crouched  → crouch_idle
still + aiming    → aim
still             → idle
crouched + moving → crouch_walk
strafing          → walk_left / walk_right
moving backward   → walk_back
speed > 75%       → run_fwd
otherwise         → walk_fwd
```

Transitions crossfade over `BLEND_TIME` (0.14s).

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `No source files in res://assets/mixamo/raw` | Files not imported yet — refocus the editor, or *Project → Reload Current Project* |
| Character slides across the floor | Re-download with **In Place** checked, or leave `FORCE_IN_PLACE` on |
| Clip plays but the mesh does not move | Bone name mismatch — flip `STRIP_BONE_PREFIX` |
| `skipped: X (no AnimationPlayer)` | Downloaded **With Skin** instead of **Without Skin** |
| Clip name came out as the raw filename | No alias matched — rename the file, or add an alias to `MixamoPipeline.CLIP_ALIASES` |

---

## Adding your own clip names

Extend the table in `scripts/animation/MixamoPipeline.gd`:

```gdscript
const CLIP_ALIASES := {
    "vault": ["climbing over", "vault"],
    ...
}
```

Add it to `LOOPING` and/or `IN_PLACE` if appropriate, then rebuild.
