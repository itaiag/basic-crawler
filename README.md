# Basic Crawler

A NetHack/Rogue-inspired roguelike dungeon crawler built in **Godot 4.6.3** (GDScript).
Randomly generated dungeons, turn-based OSR/Basic-Fantasy combat, and permadeath.

Rendered with a custom `_draw()` pass over a monospace grid (not a TileMap), using only
drawn primitives and radial gradients — **no shaders** — so it stays
**GL-Compatibility / web / mobile** safe.

## Features

- Procedurally generated dungeons (rooms, MST corridors, doors, blocking pillars)
- Recursive-shadowcasting field of view with NetHack-style lit rooms
- Turn-based bump combat with visible attack/saving-throw rolls
- Ability scores & character creation (4d6-drop-lowest)
- Monsters with greedy chase AI and 2d6 morale (fleeing)
- Gold, potions, weapons & armor (two-handed-vs-shield rule), wield/wear/quaff
- Kick brawling, close-door, rest/sleep with fatigue
- Faked torchlight, vignette, and atmosphere polish (room moods, wall bevels, halos)

## Running

Open the project in Godot 4.6.3 and run the main scene (`scenes/game.tscn`), or from the CLI:

```
godot --path .
```

**Controls:** arrows / numpad `8 2 4 6` move (bump to attack/open) · `k`+dir kick ·
`c`+dir close door · `q` quaff · `w` wield · `W` wear · `R` rest · `i` inventory ·
`F5` new dungeon · `F6` reveal map (debug).

## Project layout

- `scripts/game.gd` — root controller; owns gameplay state and turn logic
- `scripts/game_data.gd` — data tables and pure helpers (`GameData`)
- `scripts/dungeon_generator.gd`, `scripts/fov.gd` — generation and visibility
- `scripts/dungeon_renderer.gd`, `scripts/light_overlay.gd` — drawing
- `scripts/player.gd`, `scripts/monster.gd` — actors
- `Basic Crawler Game Plan.md` — full design brief
- `CLAUDE.md` — architecture notes and headless-validation workflow
