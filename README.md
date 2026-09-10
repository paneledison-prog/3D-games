# Lone Wolf

A 1v1 arena shooter in Godot 4.7 — the **Lone Wolf** duel mode only, as asked:
two combatants, one small symmetric arena, first to 5 rounds takes the match.

Runs out of the box. No assets to download before it works.

---

## Running it

The editor is already pointed at this project. Press **F5**, or:

```bash
godot --path . res://scenes/main/MainMenu.tscn
```

Pick an opponent tier, a character and a primary weapon, then **DEPLOY**.

### Controls

| Input | Action |
| --- | --- |
| `WASD` | Move |
| `Shift` | Sprint (forward only, not while aiming) |
| `Ctrl` / `C` | Crouch (won't stand up into geometry) |
| `Space` | Jump |
| Mouse | Look |
| `LMB` | Fire |
| `RMB` | Aim down sights |
| `R` | Reload |
| `Q` | Swap weapon |
| `1` / `2` | Primary / secondary |
| `Esc` | Pause / release mouse |

---

## What's in it

**Match flow** — warmup countdown, live round, round end, repeat. Rounds end on
a kill or on the 90s timer (higher health wins the timeout). First to 5.

**Weapons** — five data-driven guns in `resources/weapons/*.tres`. Hitscan with
per-pellet spread, distance falloff, headshot and limb multipliers, recoil that
kicks the camera and recovers, spread that grows as you spray and blooms while
moving, ADS with per-weapon FOV and movement penalty.

| Weapon | Damage | Rate | Mag | Character |
| --- | --- | --- | --- | --- |
| Talon .45 | 30 | 320 | 12 | Semi-auto sidearm |
| Viper SMG | 17 | 900 | 30 | Close-range shredder |
| Falcon AR | 24 | 620 | 30 | Balanced all-rounder |
| Specter Bolt | 90 | 48 | 5 | One-shot headshot |
| Breaker 12g | 12 ×9 | 90 | 6 | Lethal inside 6m |

Balancing is pure data — edit the `.tres`, no code changes.

**Opponent AI** — a state machine (patrol → chase → engage → reload) with a
vision cone plus real line-of-sight raycasts. It holds a preferred range band
per weapon class, strafes, breaks contact to reload, and snaps attention to a
shooter who hits it from out of view. Three difficulty tiers change reaction
time, aim error, aim speed, burst length and strafe frequency — set in
`GameState.bot_profile()`.

The bot has no aim-through-walls advantage: it needs genuine LOS to fire, and
its shots go through the same `WeaponSystem` as yours.

**Audio** — 30 sound effects, all synthesised from scratch by
`tools/gen_sfx.py` (noise + oscillators + envelopes). Original, no licensing
attached. Regenerate or retune any of them with `python tools/gen_sfx.py`.

Layered gunshots (transient crack + body thump + filtered tail), mechanical
reload clicks, three footstep variants, surface-aware impacts, hitmarkers with
a distinct headshot tone, and match-flow stingers.

**Arena** — a symmetric greybox built from a data table in
`scripts/arena/ArenaBuilder.gd`. Mirrored across X so neither duellist gets a
better side. Navigation is baked at runtime from the collision geometry, so you
can edit the layout freely and never re-bake by hand.

**Characters** — a five-strong roster (Swat Guy, Racer, Alien Soldier, Crypto,
Olivia), selectable in the menu. `CharacterRig` instances the Mixamo model,
auto-scales it to the 1.8m collider, and hangs a weapon socket off the right
hand bone so the gun is genuinely held rather than floating. Every model is
height-normalised, so character choice is cosmetic and never a competitive
edge.

No model file yet? You still get an articulated character, not a capsule:
`ProceduralHumanoid` builds a real `Skeleton3D` using **Mixamo's own bone
names**, with a procedural walk/run/crouch/jump/death set. The rifle attaches
to an actual `RightHand` bone, and Mixamo clips drive the same skeleton the
moment you add them. Preview every pose with `tools/CharacterPreview.tscn`.

**Animation** — full Mixamo pipeline, plus a procedural fallback so nothing is
blocked on downloading assets. See [docs/MIXAMO_PIPELINE.md](docs/MIXAMO_PIPELINE.md).

**Art drop-in** — characters and weapon models are pure data. Drop files into
`assets/`, run `tools/CheckAssets.gd`, and they appear. Any of `.glb` `.gltf`
`.fbx` `.obj` `.dae` `.blend` resolves, so you never edit paths to match a
download. See [docs/ASSET_GUIDE.md](docs/ASSET_GUIDE.md).

---

## Layout

```
scenes/
  main/        MainMenu.tscn, Main.tscn
  arena/       Arena.tscn
  characters/  Player.tscn, Bot.tscn
scripts/
  player/      PlayerController.gd
  ai/          BotController.gd
  weapons/     WeaponData.gd, WeaponSystem.gd, CombatFX.gd, ViewModel.gd
  characters/  CharacterProfile.gd, CharacterRig.gd
  animation/   MixamoPipeline.gd, CharacterAnimator.gd
  game/        GameState.gd, RoundManager.gd, Health.gd
  audio/       AudioManager.gd
  ui/          HUD.gd, Crosshair.gd, MainMenu.gd
  arena/       ArenaBuilder.gd
resources/weapons/     *.tres  — the arsenal
resources/characters/  *.tres  — the roster
assets/audio/sfx/    *.wav   — generated, 30 files
assets/mixamo/raw/        drop animation FBX here
assets/mixamo/characters/ drop character FBX here
assets/weapons/models/    drop weapon models here
tools/       gen_sfx.py, BuildMixamoLibrary.gd, CheckAssets.gd
```

The HUD and menu build their own widgets in code — there is no UI `.tscn` to
drift out of sync with its script.

---

## Tuning

| Want to change | Edit |
| --- | --- |
| Rounds to win, round length, sensitivity | `scripts/game/GameState.gd` |
| Weapon balance | `resources/weapons/*.tres` |
| Bot difficulty | `GameState.bot_profile()` |
| Arena layout | `COVER_HALF` / `CENTRE` in `ArenaBuilder.gd` |
| Character roster | `resources/characters/*.tres` |
| Weapon model fit in hand | `model_offset` / `model_rotation` in the weapon `.tres` |
| Sound design | `tools/gen_sfx.py`, then re-run it |
| Movement feel | constants at the top of `PlayerController.gd` |

---

## Not included

**Augmented reality.** The brief mentioned AR, and this is not that. It is a
conventional 3D first-person shooter. AR in Godot means OpenXR or an ARCore
plugin, an Android export chain with the SDK/NDK installed, and — more
importantly — a fundamentally different design: an FPS built around WASD, a
mouse-look camera and a 52m enclosed arena does not translate to a
camera-passthrough phone experience. Say the word if you want an AR prototype
and it's worth scoping as its own build rather than a flag on this one.

**The art files themselves.** Mixamo needs an Adobe sign-in and Free3D needs an
account, so I can't fetch either on your behalf. Everything that *consumes*
them is built, tested and documented — the five character profiles, the rig,
the weapon sockets, the viewmodel, the animation pipeline and a checker tool.
Drop the files in and they light up. Until then the game plays fine on
placeholders. Step-by-step in [docs/ASSET_GUIDE.md](docs/ASSET_GUIDE.md).

**One caution on Free3D:** licences there are per-model, and many are *Personal
Use Only* — not shippable. Check each model's licence tab, or use a CC0 source
(Kenney, Quaternius, Poly Pizza). Details in the asset guide.
