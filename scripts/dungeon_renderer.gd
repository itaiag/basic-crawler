extends Node2D

var dungeon: DungeonGenerator
var items: Dictionary = {}
var visible_cells: Dictionary = {}
var explored_cells: Dictionary = {}
var reveal_all := false

var _font: Font


func _ready() -> void:
	_font = preload("res://resources/mono_font.tres")


func update_visibility(new_visible: Dictionary) -> void:
	visible_cells = new_visible
	for pos in new_visible:
		explored_cells[pos] = true
	queue_redraw()


func set_reveal_all(value: bool) -> void:
	reveal_all = value
	queue_redraw()


func _draw() -> void:
	if dungeon == null:
		return

	var fs := GameData.FONT_SIZE
	var cx := GameData.CELL.x
	var cy := GameData.CELL.y
	# Baseline that vertically centers a glyph in the cell (text is baseline-anchored).
	var baseline := (float(cy) - (_font.get_ascent(fs) + _font.get_descent(fs))) * 0.5 + _font.get_ascent(fs)

	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			var pos := Vector2i(x, y)
			if not reveal_all and not explored_cells.has(pos):
				continue

			var tile: int = dungeon.get_tile(x, y)
			if tile == GameData.Tile.NOTHING:
				continue

			var visible_now := reveal_all or visible_cells.has(pos)

			# Items rest on the floor and are remembered once explored.
			if items.has(pos):
				var it: Dictionary = items[pos]
				_draw_item(x, y, it, visible_now, baseline, fs)
				continue

			if tile == GameData.Tile.FLOOR:
				_draw_floor(x, y, visible_now)
				# Plain floor only -- items/stairs/doors/pillars never reach this branch.
				var fd: int = int(dungeon.floor_details.get(pos, -1))
				if fd >= 0:
					_draw_floor_detail(x, y, fd, visible_now)
				continue

			var color := GameData.get_tile_color(tile)
			if GameData.is_wall(tile):
				var wri: int = dungeon.tile_room_at(pos)
				if wri >= 0:
					color = GameData.apply_mood(color, int(dungeon.room_moods[wri]))
			if not visible_now:
				color = _dim(color)

			if GameData.is_wall(tile):
				_draw_wall(x, y, color)
				continue

			if tile == GameData.Tile.CORRIDOR:
				_draw_corridor(x, y, color)
				continue

			if GameData.is_door(tile):
				_draw_door(x, y, tile, visible_now)
				continue

			if tile == GameData.Tile.PILLAR:
				_draw_pillar(x, y, visible_now)
				continue

			# Stairs (and anything else): a floor base with the glyph on top.
			_draw_floor(x, y, visible_now)
			var ch := GameData.get_tile_char(tile)
			draw_string(_font, Vector2(x * cx, y * cy + baseline), ch,
				HORIZONTAL_ALIGNMENT_CENTER, float(cx), fs, color)


# Dim + desaturate for explored-but-not-currently-visible cells (memory look).
func _dim(c: Color) -> Color:
	var g := (c.r + c.g + c.b) / 3.0
	var desat := c.lerp(Color(g, g, g), 0.65)
	return desat.darkened(0.5)


# Stable per-cell value in [0,1). Depends only on x/y, so the floor texture is
# deterministic and never flickers between frames.
func _cell_noise(x: int, y: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663)
	h = (h >> 13) ^ h
	return float(absi(h) % 1000) / 1000.0


func _draw_floor(x: int, y: int, visible_now: bool) -> void:
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var col := GameData.COLOR_FLOOR_BG
	# Faint per-room mood tint (10% lerp; subtle on purpose).
	var ri: int = dungeon.tile_room_at(Vector2i(x, y))
	if ri >= 0:
		col = GameData.apply_mood(col, int(dungeon.room_moods[ri]))
	if not visible_now:
		col = _dim(col)
	draw_rect(Rect2(x * cx, y * cy, cx, cy), col)


# Small aging marks on plain floor cells. Stable per dungeon (placement comes
# from the decoration layer; only sub-cell jitter uses the deterministic noise).
func _draw_floor_detail(x: int, y: int, kind: int, visible_now: bool) -> void:
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var px := x * cx + cx * 0.5
	var py := y * cy + cy * 0.5
	var ox := (_cell_noise(x, y) - 0.5) * 4.0
	var oy := (_cell_noise(y, x + 7) - 0.5) * 4.0
	var col: Color
	if kind == 2:  # moss -- a hint of green only on this kind
		col = GameData.COLOR_FLOOR_BG.lerp(Color(0.28, 0.42, 0.26), 0.55)
	else:
		col = GameData.COLOR_FLOOR_BG.darkened(0.5)
	if not visible_now:
		col = _dim(col)
	match kind:
		0:  # short diagonal crack
			draw_line(Vector2(px + ox - 2.0, py + oy + 1.0),
				Vector2(px + ox + 2.0, py + oy - 1.0), col, 1.0)
		1:  # small dark stain
			draw_circle(Vector2(px + ox, py + oy + 1.0), 1.6, col)
		2:  # moss spot
			draw_circle(Vector2(px + ox, py + oy), 2.0, col)
		3:  # tiny rubble cluster
			draw_rect(Rect2(px + ox - 2.0, py + oy + 1.0, 1.0, 1.0), col)
			draw_rect(Rect2(px + ox + 1.0, py + oy - 1.0, 1.0, 1.0), col)
			draw_rect(Rect2(px + ox + 2.0, py + oy + 2.0, 1.0, 1.0), col)


func _draw_wall_crack(x: int, y: int, variant: int, color: Color) -> void:
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var left := x * cx
	var top := y * cy
	# Slightly darker than the wall body for a subtle chipped/cracked look.
	var c := color.darkened(0.55)
	match variant:
		0:
			draw_line(Vector2(left + 4.0, top + 4.0), Vector2(left + 7.0, top + 9.0), c, 1.0)
		1:
			draw_line(Vector2(left + 10.0, top + 6.0), Vector2(left + 12.0, top + 14.0), c, 1.0)
		2:
			draw_line(Vector2(left + 5.0, top + 16.0), Vector2(left + 9.0, top + 19.0), c, 1.0)
		3:
			draw_rect(Rect2(left + 6.0, top + 10.0, 1.0, 1.0), c)
			draw_rect(Rect2(left + 7.0, top + 11.0, 1.0, 1.0), c)


func _draw_item(x: int, y: int, it: Dictionary, visible_now: bool, baseline: float, fs: int) -> void:
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	_draw_floor(x, y, visible_now)
	var icolor: Color = it["color"]
	var glyph: String = it["glyph"]
	if not visible_now:
		icolor = _dim(icolor)
	var center := Vector2(x * cx + cx * 0.5, y * cy + cy * 0.5)
	var glow_a := 0.18 if visible_now else 0.08
	if glyph == "$" or glyph == "!":  # gold and potions glow a touch more
		glow_a += 0.12
	draw_circle(center, 6.0, Color(icolor.r, icolor.g, icolor.b, glow_a))
	draw_string(_font, Vector2(x * cx, y * cy + baseline), glyph,
		HORIZONTAL_ALIGNMENT_CENTER, cx, fs, icolor)


func _draw_wall(x: int, y: int, color: Color) -> void:
	# Walls are solid stone blocks (the whole cell is filled), so rooms read as
	# carved-out spaces instead of thin outlines. Faces that border open space
	# get a thin warm highlight, like torchlight catching the inner rim.
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var left := x * cx
	var top := y * cy
	draw_rect(Rect2(left, top, cx, cy), color.darkened(0.6))

	var hi := Color(color.r, color.g, color.b, 0.5)
	if _is_open_space(x, y - 1):
		draw_line(Vector2(left, top), Vector2(left + cx, top), hi, 1.5)
	if _is_open_space(x, y + 1):
		draw_line(Vector2(left, top + cy), Vector2(left + cx, top + cy), hi, 1.5)
	if _is_open_space(x - 1, y):
		draw_line(Vector2(left, top), Vector2(left, top + cy), hi, 1.5)
	if _is_open_space(x + 1, y):
		draw_line(Vector2(left + cx, top), Vector2(left + cx, top + cy), hi, 1.5)

	# Sparse chip/crack overlay from the atmosphere layer. Dim follows `color`.
	var crack_v: int = int(dungeon.wall_cracks.get(Vector2i(x, y), -1))
	if crack_v >= 0:
		_draw_wall_crack(x, y, crack_v, color)


# True for walkable-ish space a wall can border (floor / corridor / door / stairs).
func _is_open_space(x: int, y: int) -> bool:
	var t: int = dungeon.get_tile(x, y)
	return t != GameData.Tile.NOTHING and not GameData.is_wall(t)


func _draw_door(x: int, y: int, tile: int, visible_now: bool) -> void:
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var left := x * cx
	var top := y * cy
	# Doors sit on the floor (a threshold), not a wall block.
	_draw_floor(x, y, visible_now)
	# The wall run is horizontal when the side neighbours are walls -> the door
	# blocks a vertical passage, so a closed leaf spans left-right (and vice versa).
	var horizontal_wall := GameData.is_wall(dungeon.get_tile(x - 1, y)) \
			or GameData.is_wall(dungeon.get_tile(x + 1, y))
	var wood := GameData.COLOR_DOOR
	if not visible_now:
		wood = _dim(wood)

	if tile == GameData.Tile.DOOR_OPEN:
		# Open: passage stays clear; a thin leaf folded against one jamb shows it's a door.
		if horizontal_wall:
			draw_rect(Rect2(left, top + 2.0, 2.5, cy - 4.0), wood)
		else:
			draw_rect(Rect2(left + 2.0, top, cx - 4.0, 2.5), wood)
		return

	# Closed / locked: a thin wood slab spanning the passage, with a lighter edge.
	var thick := 6.0
	if horizontal_wall:
		var sy := top + (cy - thick) * 0.5
		draw_rect(Rect2(left, sy, cx, thick), wood.darkened(0.15))
		draw_rect(Rect2(left, sy, cx, 1.0), wood.lightened(0.12))
	else:
		var sx := left + (cx - thick) * 0.5
		draw_rect(Rect2(sx, top, thick, cy), wood.darkened(0.15))
		draw_rect(Rect2(sx, top, 1.0, cy), wood.lightened(0.12))


func _draw_pillar(x: int, y: int, visible_now: bool) -> void:
	# A stone column standing on the room floor: a dark capsule with a lit top cap.
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	_draw_floor(x, y, visible_now)
	var px := x * cx + cx * 0.5
	var py := y * cy + cy * 0.5
	var body := GameData.COLOR_PILLAR
	var ri: int = dungeon.tile_room_at(Vector2i(x, y))
	if ri >= 0:
		body = GameData.apply_mood(body, int(dungeon.room_moods[ri]))
	if not visible_now:
		body = _dim(body)
	var w := 9.0
	var hh := 6.0
	draw_rect(Rect2(px - w * 0.5, py - hh, w, hh * 2.0), body)
	draw_circle(Vector2(px, py - hh), w * 0.5, body)
	draw_circle(Vector2(px, py + hh), w * 0.5, body)
	if visible_now:
		draw_circle(Vector2(px, py - hh), w * 0.5 - 1.5, body.lightened(0.22))


func _corridor_link(x: int, y: int) -> bool:
	var t: int = dungeon.get_tile(x, y)
	return t == GameData.Tile.CORRIDOR or GameData.is_door(t)


func _draw_corridor(x: int, y: int, color: Color) -> void:
	# Two passes -- a darker, slightly wider edge then a narrower lighter core --
	# so the path reads as carved stone instead of a thick flat highway.
	_corridor_band(x, y, color.darkened(0.5), 10.0)
	_corridor_band(x, y, color, 7.0)
	if _cell_noise(x, y) > 0.88:  # sparse grit fleck
		var cx := float(GameData.CELL.x)
		var cy := float(GameData.CELL.y)
		var c := Vector2(x * cx + cx * 0.5, y * cy + cy * 0.5)
		draw_rect(Rect2(c.x, c.y, 1.0, 1.0), color.darkened(0.35))


func _corridor_band(x: int, y: int, color: Color, w: float) -> void:
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var left := x * cx
	var top := y * cy
	var center := Vector2(left + cx * 0.5, top + cy * 0.5)
	var h := w * 0.5
	draw_rect(Rect2(center.x - h, center.y - h, w, w), color)
	if _corridor_link(x, y - 1):
		draw_rect(Rect2(center.x - h, top, w, center.y - top), color)
	if _corridor_link(x, y + 1):
		draw_rect(Rect2(center.x - h, center.y, w, top + cy - center.y), color)
	if _corridor_link(x - 1, y):
		draw_rect(Rect2(left, center.y - h, center.x - left, w), color)
	if _corridor_link(x + 1, y):
		draw_rect(Rect2(center.x, center.y - h, left + cx - center.x, w), color)
