extends Node2D

signal finished_moving

var grid_pos := Vector2i.ZERO
var is_moving := false

const MOVE_DURATION := 0.1

var _font: Font
var _tween: Tween


func _ready() -> void:
	_font = preload("res://resources/mono_font.tres")


func _draw() -> void:
	var cw := GameData.CELL.x
	var ch := GameData.CELL.y
	draw_rect(Rect2(Vector2.ZERO, Vector2(cw, ch)), Color.BLACK)
	var ascent := _font.get_ascent(GameData.FONT_SIZE)
	draw_string(_font, Vector2(0, ascent), "@", HORIZONTAL_ALIGNMENT_CENTER,
		float(cw), GameData.FONT_SIZE, Color.WHITE)


func move_to(target: Vector2i) -> void:
	grid_pos = target
	is_moving = true
	_tween = create_tween()
	_tween.tween_property(self, "position", GameData.grid_to_world(target), MOVE_DURATION)
	_tween.finished.connect(_on_move_finished)


func place_at(target: Vector2i) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	is_moving = false
	grid_pos = target
	position = GameData.grid_to_world(target)


func _on_move_finished() -> void:
	is_moving = false
	finished_moving.emit()
