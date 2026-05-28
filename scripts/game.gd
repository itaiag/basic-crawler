extends Node2D

const TOP_PANEL_H := 72
const BOTTOM_PANEL_H := 60

var _dungeon := DungeonGenerator.new()
var _turn := 1
var _awaiting_kick := false

@onready var _renderer: Node2D = $DungeonRenderer
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Player/Camera
@onready var _msg_log: RichTextLabel = $UI/MessageLog
@onready var _status: RichTextLabel = $UI/StatusBar


func _ready() -> void:
	_dungeon.generate(GameData.MAP_W, GameData.MAP_H)
	_renderer.dungeon = _dungeon

	_setup_camera()
	_setup_ui()

	var start := _dungeon.get_start_pos()
	_player.grid_pos = start
	_player.position = GameData.grid_to_world(start)
	_player.finished_moving.connect(_on_player_moved)

	_update_fov()
	_add_message("Welcome to the dungeon, adventurer!")
	_add_message("[Debug] F5: new dungeon   F6: reveal map")
	_update_status()


func _setup_camera() -> void:
	_camera.limit_left = 0
	_camera.limit_top = -TOP_PANEL_H
	_camera.limit_right = GameData.MAP_W * GameData.CELL.x
	_camera.limit_bottom = GameData.MAP_H * GameData.CELL.y + BOTTOM_PANEL_H


func _setup_ui() -> void:
	var font := preload("res://resources/mono_font.tres")
	var vp := get_viewport().get_visible_rect().size

	_msg_log.position = Vector2.ZERO
	_msg_log.size = Vector2(vp.x, TOP_PANEL_H)
	_msg_log.bbcode_enabled = true
	_msg_log.scroll_following = true
	_msg_log.focus_mode = Control.FOCUS_NONE
	_msg_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var msg_style := StyleBoxFlat.new()
	msg_style.bg_color = Color.BLACK
	msg_style.content_margin_left = 8
	msg_style.content_margin_top = 4
	_msg_log.add_theme_stylebox_override("normal", msg_style)
	_msg_log.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_msg_log.add_theme_font_override("normal_font", font)
	_msg_log.add_theme_font_size_override("normal_font_size", 16)

	_status.position = Vector2(0, vp.y - BOTTOM_PANEL_H)
	_status.size = Vector2(vp.x, BOTTOM_PANEL_H)
	_status.bbcode_enabled = true
	_status.focus_mode = Control.FOCUS_NONE
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color.BLACK
	status_style.content_margin_left = 8
	status_style.content_margin_top = 4
	_status.add_theme_stylebox_override("normal", status_style)
	_status.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_status.add_theme_font_override("normal_font", font)
	_status.add_theme_font_size_override("normal_font_size", 16)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	if event.keycode == KEY_F5:
		_regenerate()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F6:
		_toggle_reveal()
		get_viewport().set_input_as_handled()
		return

	if _player.is_moving:
		return

	if _awaiting_kick:
		_handle_kick_input(event)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_K:
		_awaiting_kick = true
		_add_message("Kick in which direction?")
		get_viewport().set_input_as_handled()
		return

	var dir := _dir_from_key(event.keycode)
	if dir != Vector2i.ZERO:
		_try_move(dir)
		get_viewport().set_input_as_handled()


func _dir_from_key(keycode: int) -> Vector2i:
	if keycode in [KEY_UP, KEY_KP_8]:
		return Vector2i(0, -1)
	elif keycode in [KEY_DOWN, KEY_KP_2]:
		return Vector2i(0, 1)
	elif keycode in [KEY_LEFT, KEY_KP_4]:
		return Vector2i(-1, 0)
	elif keycode in [KEY_RIGHT, KEY_KP_6]:
		return Vector2i(1, 0)
	return Vector2i.ZERO


func _handle_kick_input(event: InputEvent) -> void:
	_awaiting_kick = false
	if event.keycode == KEY_ESCAPE:
		_add_message("Never mind.")
		return
	var dir := _dir_from_key(event.keycode)
	if dir == Vector2i.ZERO:
		_add_message("Never mind.")
		return
	_kick(dir)


func _try_move(dir: Vector2i) -> void:
	var target: Vector2i = _player.grid_pos + dir
	if target.x < 0 or target.y < 0 or target.x >= GameData.MAP_W or target.y >= GameData.MAP_H:
		return

	var tile: int = _dungeon.get_tile(target.x, target.y)

	if tile == GameData.Tile.DOOR_CLOSED:
		_dungeon.set_tile(target.x, target.y, GameData.Tile.DOOR_OPEN)
		_add_message("You open the door.")
		_update_fov()
		_advance_turn()
		return

	if tile == GameData.Tile.DOOR_LOCKED:
		_add_message("This door is locked.  Kick it open with (k).")
		return

	if GameData.is_passable(tile):
		_player.move_to(target)


func _kick(dir: Vector2i) -> void:
	var target: Vector2i = _player.grid_pos + dir
	var tile: int = _dungeon.get_tile(target.x, target.y)

	if tile == GameData.Tile.DOOR_LOCKED or tile == GameData.Tile.DOOR_CLOSED:
		if randf() < 0.5:
			_dungeon.set_tile(target.x, target.y, GameData.Tile.DOOR_OPEN)
			_add_message("WHAMM!!  The door crashes open!")
			_update_fov()
		else:
			_add_message("WHAMM!!  The door holds firm.")
	elif GameData.is_wall(tile) or tile == GameData.Tile.NOTHING:
		_add_message("Ouch!  That hurts!")
	elif tile == GameData.Tile.DOOR_OPEN:
		_add_message("You kick at the open doorway.")
	else:
		_add_message("You kick at empty space.")

	_advance_turn()


func _on_player_moved() -> void:
	_advance_turn()
	_update_fov()
	var tile := _dungeon.get_tile(_player.grid_pos.x, _player.grid_pos.y)
	if tile == GameData.Tile.STAIRS_DOWN:
		_add_message("There is a staircase down here.")
	elif tile == GameData.Tile.STAIRS_UP:
		_add_message("There is a staircase up here.")


func _update_fov() -> void:
	var opaque_check := func(pos: Vector2i) -> bool:
		return not GameData.is_transparent(_dungeon.get_tile(pos.x, pos.y))
	var visible: Dictionary = FOV.compute(_player.grid_pos, GameData.FOV_RADIUS, opaque_check)

	var ri := _dungeon.room_index_at(_player.grid_pos)
	if ri >= 0:
		var room: Rect2i = _dungeon.rooms[ri].grow(1)
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				visible[Vector2i(x, y)] = true

	_renderer.update_visibility(visible)


func _regenerate() -> void:
	_dungeon.generate(GameData.MAP_W, GameData.MAP_H)
	_renderer.dungeon = _dungeon
	_renderer.visible_cells.clear()
	_renderer.explored_cells.clear()
	_awaiting_kick = false
	_turn = 1
	_player.place_at(_dungeon.get_start_pos())
	_update_fov()
	_add_message("[Debug] Generated a new dungeon.")
	_update_status()


func _toggle_reveal() -> void:
	_renderer.set_reveal_all(not _renderer.reveal_all)
	if _renderer.reveal_all:
		_add_message("[Debug] Revealing the whole dungeon.")
	else:
		_add_message("[Debug] Fog of war restored.")


func _advance_turn() -> void:
	_turn += 1
	_update_status()


func _add_message(text: String) -> void:
	_msg_log.append_text(text + "\n")


func _update_status() -> void:
	_status.clear()
	_status.append_text("Adventurer the Aspirant     St:16 Dx:12 Co:14 In:9 Wi:10 Ch:11     Lawful\n")
	_status.append_text("$:0  HP:10(10)  Pw:0(0)  AC:10  Exp:1  T:%d" % _turn)
