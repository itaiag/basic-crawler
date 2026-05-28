# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Basic Crawler" — a NetHack/Rogue-inspired roguelike dungeon crawler built in **Godot 4.6.3** (GDScript). Randomly generated dungeons, turn-based play, OSR/Basic-Fantasy influence. The full design brief lives in `Basic Crawler Game Plan.md`. Targets desktop, mobile, and web via the GL Compatibility renderer — do not switch renderers or add desktop-only features that break web/mobile export.

## Workflow expectation (important)

The owner wants work delivered in **small, reviewable stages** and explicitly checks each stage before the next begins (e.g. dungeon generation → combat → stats/HUD → items → permadeath). Do not jump ahead to a later stage without confirmation. Stage 1 (dungeon generation, smooth movement, FOV, doors) is the current focus.

## Validating changes

There is no test suite. Validate that scripts/scenes parse and the main scene boots by running Godot **headless** (the console build streams errors to stdout):

```
"C:\Users\itaia\OneDrive\Desktop\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Users\itaia\git\godot\basic-crawler" --quit-after 30
```

Exit code 0 with no error lines means all `class_name` scripts compiled and `Game._ready()` (dungeon gen, FOV, lit-room logic, UI setup) ran without runtime errors. Headless cannot verify visuals or input — UI/feel changes must be confirmed by the user running the editor. Use `--quit-after <frames>` to run a few frames; `--check-only --script <file>` parses a single script.

## Architecture

**No autoloads.** Shared code is exposed via `class_name` (`GameData`, `DungeonGenerator`, `FOV`). The runnable scene is `scenes/game.tscn` with `scripts/game.gd` as the root controller.

Scene tree: `Game (Node2D, game.gd)` → `DungeonRenderer (Node2D)`, `Player (Node2D)` → `Camera (Camera2D)`, `UI (CanvasLayer)` → `MessageLog`, `StatusBar` (both `RichTextLabel`).

- **`game_data.gd`** — the single source of truth for the `Tile` enum, grid constants (`CELL`, `MAP_W/H`, `FONT_SIZE`, `FOV_RADIUS`), colors, and static tile predicates (`get_tile_char/color`, `is_passable`, `is_transparent`, `is_wall`, `is_door`, `grid_to_world`). Add new tile kinds and their glyph/color/passability here.
- **`dungeon_generator.gd`** — pure data, no nodes. Generates room **floor rects first**, builds a clean wall ring around each, then connects rooms in a chain with **BFS routed only through empty void** (never steps on walls/floors/doors). Each connection punches exactly one perpendicular door at each end. This is why corridors never run through or along walls and each room has ~1–2 doors. `rooms` stores FLOOR-only rects (walls are the surrounding ring, not part of the rect).
- **`fov.gd`** — static recursive shadowcasting (RogueBasin 8-octant). `game.gd` layers NetHack-style **lit rooms** on top: when the player stands in a room, the whole room + its wall ring (`rect.grow(1)`) is forced visible.
- **`dungeon_renderer.gd`** — custom `_draw()` over the whole map using `draw_string()` with the monospace `SystemFont` (`resources/mono_font.tres`). This **imitates ASCII with a graphic font rather than a TileMap**. Honors fog of war via `visible_cells`/`explored_cells`; `reveal_all` is a debug override. Open-door glyph orientation (`|` vs `-`) is computed from neighboring walls.
- **`player.gd`** — draws `@` (over a black cell to mask the floor). `grid_pos` is the logical cell (updates instantly); screen `position` is **tweened** for smooth movement (`MOVE_DURATION`). `place_at()` teleports and kills any in-flight tween (used by debug regen).

### Key conventions

- **Grid logic vs. smooth motion are decoupled:** all game logic uses integer `Vector2i` grid coordinates; only the visual `position` interpolates. The `Camera2D` is a child of `Player`, and `game.gd` pads its limits by the panel heights (`TOP_PANEL_H`, `BOTTOM_PANEL_H`) so edge rows never scroll behind the opaque top/bottom UI bars.
- **Turn model:** `game.gd._advance_turn()` increments `_turn` after each in-game action (move, open door, kick) and refreshes the status bar.
- **Input:** arrows + numpad 8/2/4/6 move; `k` then a direction kicks (locked doors need kicking, 50% per kick); `Esc` cancels a pending kick. Debug: **F5** regenerates the dungeon, **F6** toggles full-map reveal.

### GDScript gotchas in this project

- The project surfaces **"inferred Variant" warnings as errors.** Even with a typed array (`Array[Rect2i]`), `arr.back()` and `arr[i]` return `Variant` in this Godot version, so you **must** add explicit local type annotations (`var r: Rect2i = rooms[i]`). Same for `Dictionary` lookups and untyped-array elements. This is the most common cause of parse failures here.
- Indentation is **tabs** (Godot/GDScript convention; all existing scripts use tabs).
