# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Basic Crawler" — a NetHack/Rogue-inspired roguelike dungeon crawler built in **Godot 4.6.3** (GDScript). Randomly generated dungeons, turn-based OSR/Basic-Fantasy combat, permadeath. The full design brief is in `Basic Crawler Game Plan.md`. Targets desktop, mobile, and web via the GL Compatibility renderer — do not switch renderers or add features that break web/mobile export.

## Workflow expectation (important)

Work is delivered in **small, reviewable stages, and within a stage in incremental steps**; the owner checks each step (usually by running the editor and sending a screenshot) before the next. Do not jump ahead. When a stage is broad, confirm scope/order with the owner first (use the question tool), then implement one reviewable step at a time.

Status: Stage 1 (dungeon + movement + FOV + doors), Stage 2 (monsters, bump combat, chase AI, death), and Stage 3 (ability scores + character-creation screen) are done. Stage 4 (items & features) is in progress — gold/potions/inventory/quaff are in; **descend-to-deeper-levels** and **traps & searching** (with *hidden* search rolls) are not yet built. Per the design doc: attack and saving-throw rolls are shown to the player; trap/secret-door search rolls must stay hidden.

## Validating changes

There is no test suite. Validate by running Godot **headless** (the console build streams errors to stdout):

```
"C:\Users\itaia\OneDrive\Desktop\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Users\itaia\git\godot\basic-crawler" --quit-after 30
```

Exit 0 with no error lines means scripts compiled and `Game._ready()` ran. Important limits and patterns:

- **Headless boots the scene but does not simulate input or combat.** Whole code paths (attacking, quaffing, monster turns, overlays) never execute, so runtime errors there slip through `--quit-after`. After renaming/removing a field or method, **grep every call site** rather than relying on the boot check.
- **Adding a new `class_name` requires registering it** before a plain headless run can resolve it. Run an editor pass once: `--headless --editor --quit --path <project>` (watch for `update_scripts_classes | <YourClass>`), then validate normally.
- **To exercise logic headless**, write a throwaway `extends SceneTree` script with an `_init()` that constructs objects and `print()`s results, run it with `--script res://scripts/_tmp.gd`, then delete it (and its `.uid`). This is how stat/item math has been spot-checked.
- **Gameplay smoke test (`tests/smoke_test.gd`).** A persistent `extends SceneTree` script that instances the real `game.tscn`, waits a frame for `_ready`, then drives one move and one bump-attack through the actual turn/combat code (`_try_move` → `_run_round` → `_do_move_action`/`_attack_monster`). This covers the move/combat paths the boot check skips. Run:

  ```
  "C:\Users\itaia\OneDrive\Desktop\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Users\itaia\git\godot\basic-crawler" --script res://tests/smoke_test.gd
  ```

  Pass = exit 0 with `SMOKE TEST PASSED` and no `SCRIPT ERROR` lines; failures print `SMOKE TEST FAILURE: ...` and exit 1. It's a dev-only tool (never referenced by `game.tscn`), so it doesn't affect the game or exports. Re-run it after touching turn/combat/input code.

## Architecture

**No autoloads.** Shared code is exposed via `class_name`: `GameData`, `DungeonGenerator`, `FOV`, `Monster`. The runnable scene is `scenes/game.tscn`; `scripts/game.gd` is the root controller and owns essentially all game state and turn logic.

Scene tree: `Game (Node2D, game.gd)` → `DungeonRenderer (Node2D)`, `Player (Node2D, player.gd)` → `Camera (Camera2D)`, `UI (CanvasLayer)` → `MessageLog`, `StatusBar` (both `RichTextLabel`). Monsters and the two full-screen overlays (character creation, inventory) are created at runtime as children of `Game`/`UI`.

- **`game_data.gd`** — single source of truth for data and pure helpers: `Tile` enum + glyph/color/passability predicates; grid constants (`CELL`, `MAP_W=80`, `MAP_H=21`, `FONT_SIZE`, `FOV_RADIUS`); `MonsterKind` enum + `MONSTERS` stat table; `ItemKind` enum + `ITEMS` table (`is_potion()` keys off each item's `category`); dice (`roll`, `roll_ability` = 4d6-drop-lowest) and Basic Fantasy `ability_mod`.
- **`dungeon_generator.gd`** — pure data, no nodes. Places room **floor rects** (spaced `grow(3)` apart so wall rings never touch), builds a wall ring per room, then connects rooms with a **minimum spanning tree**; corridors are carved by **BFS through empty void only** (never stepping on walls/floors/doors), punching exactly one perpendicular door per end. Then adds *mess*: a few extra MST-edge connections (loops/crossings) and random dead-end stubs. `rooms` holds FLOOR-only rects (walls are the surrounding ring).
- **`fov.gd`** — static recursive shadowcasting (RogueBasin 8-octant). `game.gd` layers NetHack **lit rooms** on top (standing in a room reveals the whole room + ring).
- **`dungeon_renderer.gd`** — custom `_draw()` over the whole map; **imitates ASCII with a monospace `SystemFont` (`resources/mono_font.tres`), not a TileMap**. Walls and corridors are drawn as connected line/band primitives (not glyphs) so they read as solid; floors/doors/stairs/items are `draw_string` glyphs. Honors fog via `visible_cells`/`explored_cells`; `reveal_all` is the F6 debug override. Holds an `items` dict reference (set once by `game.gd`) and draws floor items, remembered once explored.
- **`player.gd`** — `extends Node2D`, **no `class_name`**. Holds the six ability scores, HP/XP/level, gold, and `inventory`. Combat values are **derived methods**, not stored: `str_mod/dex_mod/con_mod`, `armor_class()` (= base armor 14 + DEX), `melee_attack_bonus()` (= level + STR), `damage_bonus()`, `gain_level_hp()`. Draws `@` over a black cell; `grid_pos` is logical (instant), screen `position` is **tweened** (`move_to`); `place_at()` teleports and kills any in-flight tween. `roll_new_character()` re-rolls everything for a new game.
- **`monster.gd`** — `class_name Monster`, mirrors the player node (draws its letter on a black cell, tweened `move_to`/`place_at`). Carries `kind` (index into `GameData.MONSTERS`) and `hp`.

### Turn & combat model (central to `game.gd`)

- A **round** is `_run_round(player_action: Callable)`. Player input classifies the intent and passes a *callable* (`_do_move_action`/`_do_kick_action`/`_do_quaff_action`, bound with args) — the action is **re-derived at execution time** so it stays correct if monsters move first.
- **Group initiative (Basic Fantasy):** when combat is joined (`_engaged()` = an active monster within `ENGAGE_RANGE`), both sides roll 1d6 each round; the higher side takes its whole phase first (player wins ties). The roll is shown in the log.
- **Monsters** (`_monsters_act` → `_monster_take_turn`): active only when in the player's current view (`_last_visible`); greedy-chase toward the player, attack when adjacent. Occupancy is tracked in `_monster_at` (Vector2i→Monster), kept in sync on every move/kill.
- **Combat:** ascending AC; attack = d20 + bonus vs AC; rolls shown in the message log. Player death blocks input until **F5**. Items live in `_items_at` (Vector2i→Dictionary); walking onto a cell auto-picks-up.
- UI state flags gate input: `_creating` (character screen), `_inventory_open`, `_awaiting_kick`, `_awaiting_quaff`, `_player_alive`, `_player.is_moving`.

### Input map

Arrows / numpad 8·2·4·6 move (move into a monster = attack, into a closed door = open, locked door = must kick). `k`+direction kick. `i` inventory overlay (free). `q` quaff → potion-selection prompt (letters), turn-consuming. Debug: **F5** new dungeon + character screen, **F6** reveal map.

## GDScript gotchas in this project

- **"Inferred Variant" warnings are treated as errors.** Typed-array `arr.back()`/`arr[i]`, `Dictionary` lookups, untyped-array elements, and any expression involving an unsafe property all return `Variant`, so results used in `var x :=` need explicit annotation (`var r: Rect2i = rooms[i]`, `var idx: int = event.keycode - KEY_A`). This is the most common parse failure here.
- **`_player` and `_monster_at` values are typed `Node2D`/`Monster` accessed loosely**, so `_player.foo` compiles even if `foo` doesn't exist and only fails at runtime (this is why renamed fields must be grepped). `player.gd` deliberately has no `class_name`.
- New `class_name` scripts need the editor-pass registration described above before headless runs see them.
- Indentation is **tabs** (all existing scripts use tabs).
