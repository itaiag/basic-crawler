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

			var ch := GameData.get_tile_char(tile)
			if tile == GameData.Tile.DOOR_OPEN:
				ch = _open_door_glyph(x, y)
			var color := GameData.get_tile_color(tile)

			if not reveal_all and not visible_cells.has(pos):
				color = color.darkened(0.6)

			var draw_pos := Vector2(x * cx, y * cy + ascent)
			draw_string(_font, draw_pos, ch, HORIZONTAL_ALIGNMENT_CENTER,
				float(cx), fs, color)


func _open_door_glyph(x: int, y: int) -> String:
	# A door in a horizontal wall opens to a vertical leaf "|"; otherwise "-".
	if GameData.is_wall(dungeon.get_tile(x - 1, y)) \
			or GameData.is_wall(dungeon.get_tile(x + 1, y)):
		return "|"
	return "-"
