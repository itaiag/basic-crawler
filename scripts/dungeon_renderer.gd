extends Node2D

var dungeon: DungeonGenerator
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
	var ascent := _font.get_ascent(fs)

	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			var pos := Vector2i(x, y)
			if not reveal_all and not explored_cells.has(pos):
				continue

			var tile: int = dungeon.get_tile(x, y)
			if tile == GameData.Tile.NOTHING:
				continue

			var color := GameData.get_tile_color(tile)
			if not reveal_all and not visible_cells.has(pos):
				color = color.darkened(0.6)

			if GameData.is_wall(tile):
				_draw_wall(x, y, color)
				continue

			if tile == GameData.Tile.CORRIDOR:
				_draw_corridor(x, y, color)
				continue

			var ch := GameData.get_tile_char(tile)
			if tile == GameData.Tile.DOOR_OPEN:
				ch = _open_door_glyph(x, y)
			var draw_pos := Vector2(x * cx, y * cy + ascent)
			draw_string(_font, draw_pos, ch, HORIZONTAL_ALIGNMENT_CENTER,
				float(cx), fs, color)


func _wall_like(x: int, y: int) -> bool:
	var t: int = dungeon.get_tile(x, y)
	return GameData.is_wall(t) or GameData.is_door(t)


func _draw_wall(x: int, y: int, color: Color) -> void:
	# Draw walls as connected line segments so they form a solid outline.
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var left := x * cx
	var top := y * cy
	var center := Vector2(left + cx * 0.5, top + cy * 0.5)
	var th := 2.0
	var connected := false
	if _wall_like(x, y - 1):
		draw_line(center, Vector2(center.x, top), color, th)
		connected = true
	if _wall_like(x, y + 1):
		draw_line(center, Vector2(center.x, top + cy), color, th)
		connected = true
	if _wall_like(x - 1, y):
		draw_line(center, Vector2(left, center.y), color, th)
		connected = true
	if _wall_like(x + 1, y):
		draw_line(center, Vector2(left + cx, center.y), color, th)
		connected = true
	if not connected:
		if dungeon.get_tile(x, y) == GameData.Tile.WALL_V:
			draw_line(Vector2(center.x, top), Vector2(center.x, top + cy), color, th)
		else:
			draw_line(Vector2(left, center.y), Vector2(left + cx, center.y), color, th)


func _corridor_link(x: int, y: int) -> bool:
	var t: int = dungeon.get_tile(x, y)
	return t == GameData.Tile.CORRIDOR or GameData.is_door(t)


func _draw_corridor(x: int, y: int, color: Color) -> void:
	# Draw corridors as filled connected bands so the path looks solid.
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var left := x * cx
	var top := y * cy
	var center := Vector2(left + cx * 0.5, top + cy * 0.5)
	var w := 12.0
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


func _open_door_glyph(x: int, y: int) -> String:
	# A door in a horizontal wall opens to a vertical leaf "|"; otherwise "-".
	if GameData.is_wall(dungeon.get_tile(x - 1, y)) \
			or GameData.is_wall(dungeon.get_tile(x + 1, y)):
		return "|"
	return "-"
