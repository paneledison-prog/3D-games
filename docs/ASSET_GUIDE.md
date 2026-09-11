# Asset guide — characters and weapons

The game runs right now with an articulated stand-in character and blocky
weapons. This is how you swap in the real art.

**About the stand-in:** with no downloads at all you get a proper humanoid, not
a capsule - `ProceduralHumanoid` builds a real `Skeleton3D` that uses Mixamo's
bone names (`Hips`, `Spine`, `RightHand`, ...), holds its weapon in an actual
hand bone, and animates through walk, sprint, crouch, jump and death. Because
the bone names match, dropping in Mixamo clips drives that same skeleton. Run
`tools/CharacterPreview.tscn` (F6 in the editor) to see every pose side by
side.

**Nothing here requires code changes.** Drop files into the right folder, run
the checker, done. Everything degrades gracefully: a missing file means a
placeholder, never a crash.

| What | Where it goes | Source |
| --- | --- | --- |
| Characters | `assets/mixamo/characters/` | [mixamo.com](https://www.mixamo.com) |
| Animation clips | `assets/mixamo/raw/` | [mixamo.com](https://www.mixamo.com) |
| Weapon models | `assets/weapons/models/` | [free3d.com](https://free3d.com/3d-models/weapons) or CC0 sources |

After adding anything, run **`tools/CheckAssets.gd`** in the editor
(Ctrl+Shift+X). It tells you exactly what landed, what's missing, and whether
each skeleton has the bones the rig needs.

---

## 1. Characters

Five profiles ship in `resources/characters/`, matched to the Mixamo characters
you asked for:

| Profile | Mixamo character | Expected file |
| --- | --- | --- |
| `swat_guy` | Swat Guy | `Swat Guy.fbx` |
| `racer` | Racer | `Racer.fbx` |
| `alien_soldier` | Alien Soldier | `Alien Soldier.fbx` |
| `crypto` | Crypto | `Crypto.fbx` |
| `olivia` | Olivia | `Olivia.fbx` |

### Downloading

1. Sign in at [mixamo.com](https://www.mixamo.com) (free Adobe account)
2. **Characters** tab → search the name → select it
3. **Download** with these settings:

| Setting | Value |
| --- | --- |
| Format | **FBX Binary (.fbx)** |
| Pose | **T-pose** |

4. Save into `assets/mixamo/characters/` — **keep the default filename**

Godot imports on the next editor focus. Pick your character in the main menu;
the status line under the name tells you whether the model actually loaded.

> **File format is flexible.** The profile lists `.fbx`, but `.glb`, `.gltf`,
> `.dae` and `.blend` with the same basename all resolve automatically. Convert
> if you prefer — you don't have to edit anything.

### Height is normalised on purpose

Every model is auto-scaled to **1.8 m** regardless of what it imports as. Alien
Soldier is much taller than Olivia in Mixamo, but in-game they present the same
silhouette height against the same 1.8 m collider.

That's deliberate: in a 1v1, a taller character with the same hitbox would be a
strictly worse pick, and a shorter one would be a free advantage. Character
choice here is cosmetic only.

To disable it for a specific character, set `auto_fit_height = false` and dial
`model_scale` by hand in its `.tres`.

---

## 2. Animation clips

Separate from characters, and covered in full by
[MIXAMO_PIPELINE.md](MIXAMO_PIPELINE.md). Short version:

1. Download clips **Without Skin**, **In Place**, 30 fps
2. Drop them in `assets/mixamo/raw/`
3. Run `tools/BuildMixamoLibrary.gd`

One shared library drives every character, so you download the clip set once,
not once per body.

---

## 3. Weapon models

**Already installed.** Seven models from [Poly Pizza](https://poly.pizza), all by
**Quaternius**, all **CC0 public domain** — free for any use, commercial
included, no attribution required (crediting him is still decent form).

| Slot | Weapon | File |
| --- | --- | --- |
| 1 | Falcon AR | `rifle.glb` |
| 1 | Viper SMG | `smg.glb` |
| 1 | Breaker 12g | `shotgun.glb` |
| 1 | Specter Bolt | `sniper.glb` |
| 2 | Talon .45 | `pistol.glb` |
| 3 | Bayonet (melee) | `knife.glb` |
| 4 | Frag Grenade (throwable) | `grenade.glb` |

### Scale is handled automatically

Downloaded models arrive at arbitrary scales — the Quaternius rifle imports
**5.17 m long**. Rather than hand-tuning a factor per model, each weapon `.tres`
declares a real-world `target_length` and the game measures the mesh on load and
scales to match. Drop in any replacement model and it sizes itself.

If a replacement points the wrong way, adjust `model_rotation` /
`viewmodel_rotation` (these models run along X, so they use a 90 degree Y turn).

### Replacing them

The five gun slots look for these files:

| Weapon | Expected file |
| --- | --- |
| Talon .45 | `assets/weapons/models/pistol.glb` |
| Viper SMG | `assets/weapons/models/smg.glb` |
| Falcon AR | `assets/weapons/models/rifle.glb` |
| Specter Bolt | `assets/weapons/models/sniper.glb` |
| Breaker 12g | `assets/weapons/models/shotgun.glb` |

Same flexibility as characters: `.glb`, `.gltf`, `.fbx`, `.obj`, `.dae` and
`.blend` all resolve. Free3D mostly hands out `.obj` or `.fbx`, so
`rifle.obj` works with no edits.

Each model is used in **both** places — the first-person viewmodel and the gun
in the character's hand — so you only need one file per weapon.

### ⚠️ Check the licence before you download

This one genuinely matters. **Free3D licences vary per model**, and a large
share are *Personal Use Only*, which means you cannot ship a game with them —
not commercially, and in some cases not publicly at all. The licence is on each
model's page, next to the download button. Read it per model; there is no
blanket Free3D licence.

If this project might ever be released, prefer sources with a single clear
licence:

| Source | Licence | Notes |
| --- | --- | --- |
| [Kenney.nl](https://kenney.nl/assets) | **CC0** | Public domain, no attribution needed. Stylised, low-poly. |
| [Quaternius](https://quaternius.com) | **CC0** | Public domain. Good sci-fi and modern weapon packs. |
| [Poly Pizza](https://poly.pizza) | CC0 / CC-BY | Filterable by licence. |
| [Sketchfab](https://sketchfab.com) | varies | Filter to "Downloadable" + CC licence. |
| Free3D | **varies per model** | Read each model's licence tab. |

Mixamo characters are fine on this front — Adobe's terms allow royalty-free use
in projects, including commercial ones.

### Lining the gun up in the hand

A downloaded weapon will almost never sit correctly first time. Two layers of
adjustment, and you generally only need the first:

**Per weapon** — in `resources/weapons/<id>.tres`:

```gdscript
model_scale      # overall size in the hand
model_offset     # position relative to the grip
model_rotation   # degrees; most models need a Y flip
muzzle_local     # barrel tip, drives flash + tracer origin
viewmodel_rotation      # first-person orientation, separate from third-person
viewmodel_model_scale   # first-person size, separate from third-person
```

**Per character** — in `resources/characters/<id>.tres`, if one character's
hand sits differently from the rest:

```gdscript
grip_offset      # added on top of the weapon's own offset
grip_rotation
```

Tune with the game running: edit the `.tres` in the inspector, and the change
applies the next time the weapon is equipped (press `Q` to swap and back).

---

## 4. Verifying

Run `tools/CheckAssets.gd` (Ctrl+Shift+X). Sample output once things are in:

```
-- Characters ------------------------------------------------
  [OK]      Swat Guy         67 bones, 2 meshes, 1.63m tall
            hand bone : mixamorig:RightHand
            head bone : mixamorig:Head
            auto-fit  : x1.104 -> 1.80m
  [MISSING] Racer            expects Racer.fbx

-- Weapon models ---------------------------------------------
  [OK]          Falcon AR        rifle.glb
  [MISSING]     Talon .45        expects pistol.glb
```

It resolves bone names the same way the game does, so if it prints a hand bone,
the weapon will attach to it.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Blocky stand-in showing instead of your character | File not imported. Refocus the editor, or *Project → Reload Current Project*. Run the checker to confirm. |
| `no Skeleton3D - re-download 'With Skin'` | You downloaded a clip, not a character. Characters come from the **Characters** tab. |
| Character faces backwards | Set `model_rotation_y` to `0` instead of `180` in the profile. |
| Character sunk into the floor / floating | Adjust `model_offset.y`. Auto-fit handles scale, not origin placement. |
| Gun floating beside the hand | Tune `model_offset` / `model_rotation` in the weapon `.tres`. |
| Character imports but stays in T-pose while others animate | Mixamo namespaces some characters (`mixamorig1_`, `mixamorig6_`) instead of plain `mixamorig_`, so clip tracks do not bind. The game detects the prefix per character and rewrites the clips automatically — if you hit this in your own tooling, that is the cause. |
| `no bone matching 'RightHand'` | Non-Mixamo rig. Run the checker to see the real bone names, then set `right_hand_bone` in the profile. |
| Weapon huge or microscopic | `model_scale` (hand) and `viewmodel_model_scale` (first-person) are separate knobs. |
| Muzzle flash in the wrong place | `muzzle_local` — the barrel tip in model space. |
