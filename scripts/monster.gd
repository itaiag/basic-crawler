class_name Monster
extends Node2D

var kind := 0
var grid_pos := Vector2i.ZERO
var hp := 1
var max_hp := 1

# Morale state. fleeing flips on a failed morale check; morale_checked guards the
# one-time "dropped to half HP" trigger so it only fires once per monster.
var fleeing := false
var morale_checked := false

const MOVE_DURATION := 0.1

var _font: Font
var _tween: Tween


func setup(monster_kind: int, pos: Vector2i) -> void:
	kind = monster_kind
	grid_pos = pos
	var data: Dictionary = GameData.MONSTERS[kind]
	max_hp = data["hp"]
	hp = max_hp
	position = GameData.grid_to_world(pos)


func _ready() -> void:
	_font = preload("res://resources/mono_font.tres")
	queue_redraw()


func _draw() -> void:
	var data: Dictionary = GameData.MONSTERS[kind]
	var glyph: String = data["glyph"]
	var color: Color = data["color"]
	var cw := float(GameData.CELL.x)
	var ch := float(GameData.CELL.y)
	draw_rect(Rect2(Vector2.ZERO, Vector2(cw, ch)), Color.BLACK)
	var ascent := _font.get_ascent(GameData.FONT_SIZE)
	draw_string(_font, Vector2(0, ascent), glyph, HORIZONTAL_ALIGNMENT_CENTER,
		cw, GameData.FONT_SIZE, color)


func move_to(target: Vector2i) -> void:
	grid_pos = target
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", GameData.grid_to_world(target), MOVE_DURATION)


func place_at(target: Vector2i) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	grid_pos = target
	position = GameData.grid_to_world(target)
