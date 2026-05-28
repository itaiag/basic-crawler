extends Node2D

const TOP_PANEL_H := 72
const BOTTOM_PANEL_H := 60
const ENGAGE_RANGE := 5

# Rest/sleep tuning (per sleep-turn interruption chance).
const SLEEP_TURNS := 15
const REST_INTERRUPT_SAFE := 0.02
const REST_INTERRUPT_OPEN := 0.15
const FATIGUE_PENALTY := 2

var _dungeon := DungeonGenerator.new()
var _turn := 1
var _awaiting_kick := false

var _monsters: Array[Monster] = []
var _monster_at: Dictionary = {}
var _last_visible: Dictionary = {}
var _player_alive := true
var _items_at: Dictionary = {}
var _creating := false
var _inventory_open := false
var _awaiting_quaff := false
var _awaiting_close := false
var _awaiting_wield := false
var _awaiting_wear := false
var _quaff_options: Array[int] = []
var _wield_options: Array[int] = []
var _wear_options: Array[int] = []
var _create_bg: ColorRect
var _create_label: RichTextLabel
var _inv_bg: ColorRect
var _inv_label: RichTextLabel

@onready var _renderer: Node2D = $DungeonRenderer
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Player/Camera
@onready var _msg_log: RichTextLabel = $UI/MessageLog
@onready var _status: RichTextLabel = $UI/StatusBar


func _ready() -> void:
	_dungeon.generate(GameData.MAP_W, GameData.MAP_H)
	_renderer.dungeon = _dungeon
	_renderer.items = _items_at

	_setup_camera()
	_setup_ui()
	_setup_overlays()

	var start := _dungeon.get_start_pos()
	_player.grid_pos = start
	_player.position = GameData.grid_to_world(start)

	_spawn_monsters()
	_spawn_items()
	_update_fov()
	_enter_creation()


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


func _setup_overlays() -> void:
	_create_bg = _new_overlay()
	_create_label = _create_bg.get_child(0) as RichTextLabel
	_inv_bg = _new_overlay()
	_inv_label = _inv_bg.get_child(0) as RichTextLabel


func _new_overlay() -> ColorRect:
	var font := preload("res://resources/mono_font.tres")
	var vp := get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = Vector2.ZERO
	bg.size = vp
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible = false
	$UI.add_child(bg)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.position = Vector2.ZERO
	label.size = vp
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_override("bold_font", font)
	label.add_theme_font_size_override("normal_font_size", 18)
	label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	bg.add_child(label)
	return bg


func _enter_creation() -> void:
	_creating = true
	_player.roll_new_character()
	_update_create_label()
	_update_status()
	_create_bg.visible = true


func _begin_play() -> void:
	_creating = false
	_create_bg.visible = false
	_add_message("Welcome to the dungeon, Adventurer the Human Fighter!")
	_add_message("Commands: arrows move, k kick, c close door, i inventory, q quaff, R rest.")
	_add_message("[Debug] F5: new dungeon   F6: reveal map")
	_update_status()


func _handle_create_input(event: InputEvent) -> void:
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_begin_play()
	elif event.keycode == KEY_R or event.keycode == KEY_SPACE:
		_player.roll_new_character()
		_update_create_label()
		_update_status()


func _update_create_label() -> void:
	var st: int = _player.strength
	var dx: int = _player.dexterity
	var co: int = _player.constitution
	var intel: int = _player.intelligence
	var wi: int = _player.wisdom
	var cha: int = _player.charisma
	var hp: int = _player.max_hp
	var ac: int = _player.armor_class()

	var t := "\n\n\n\n[center][font_size=30][b]Create Your Character[/b][/font_size]\n\n"
	t += "Human Fighter,  Lawful\n\n"
	t += "St %2d (%+d)    Dx %2d (%+d)    Co %2d (%+d)\n" % [
		st, GameData.ability_mod(st), dx, GameData.ability_mod(dx),
		co, GameData.ability_mod(co)]
	t += "In %2d (%+d)    Wi %2d (%+d)    Ch %2d (%+d)\n\n" % [
		intel, GameData.ability_mod(intel), wi, GameData.ability_mod(wi),
		cha, GameData.ability_mod(cha)]
	t += "HP %d        AC %d\n\n\n" % [hp, ac]
	t += "[ R ] Reroll          [ Enter ] Begin[/center]"
	_create_label.text = t


func _open_inventory() -> void:
	_inventory_open = true
	_update_inv_label()
	_inv_bg.visible = true


func _update_inv_label() -> void:
	var gold: int = _player.gold
	var inv: Array = _player.inventory
	var t := "\n\n\n\n[center][font_size=30][b]Inventory[/b][/font_size]\n\n"
	t += "Gold:  %d\n\n" % gold
	if inv.is_empty():
		t += "(carrying nothing else)\n"
	else:
		var counts := {}
		for k in inv:
			counts[k] = int(counts.get(k, 0)) + 1
		var idx := 0
		for k in counts.keys():
			var kind: int = k
			var c: int = counts[k]
			var iname: String = GameData.ITEMS[kind]["name"]
			if c != 1:
				iname += "s"
			t += "%s)  %d  %s\n" % [char(97 + idx), c, iname]
			idx += 1
	t += "\n\n[ any key ] close[/center]"
	_inv_label.text = t


func _try_quaff() -> void:
	# Build a menu of the distinct potions carried; non-potions are excluded.
	_quaff_options.clear()
	var seen := {}
	for k in _player.inventory:
		var kind: int = k
		if GameData.is_potion(kind) and not seen.has(kind):
			seen[kind] = true
			_quaff_options.append(kind)

	if _quaff_options.is_empty():
		_add_message("You have no potions to quaff.")
		return

	var prompt := "Quaff which potion?  "
	for i in range(_quaff_options.size()):
		var kind: int = _quaff_options[i]
		prompt += "[%s] %s" % [char(97 + i), GameData.ITEMS[kind]["name"]]
		var c := _count_item(kind)
		if c > 1:
			prompt += " (%d)" % c
		prompt += "   "
	prompt += "[Esc] cancel"
	_add_message(prompt)
	_awaiting_quaff = true


func _handle_quaff_input(event: InputEvent) -> void:
	_awaiting_quaff = false
	if event.keycode == KEY_ESCAPE:
		_add_message("Never mind.")
		return
	var idx: int = event.keycode - KEY_A
	if idx >= 0 and idx < _quaff_options.size():
		var kind: int = _quaff_options[idx]
		_run_round(_do_quaff_action.bind(kind))
	else:
		_add_message("Never mind.")


func _count_item(kind: int) -> int:
	var c := 0
	for k in _player.inventory:
		if int(k) == kind:
			c += 1
	return c


func _do_quaff_action(kind: int) -> void:
	var data: Dictionary = GameData.ITEMS[kind]
	_player.remove_item(kind)
	var amount := GameData.roll(int(data["heal_n"]), int(data["heal_d"])) + int(data["heal_bonus"])
	_player.heal(amount)
	_add_message("You quaff the %s.  You feel better!  (+%d HP)" % [data["name"], amount])


func _try_rest() -> void:
	if _engaged():
		_add_message("You can't rest with enemies nearby.")
		return
	if _player.hp >= _player.max_hp and not _player.fatigued:
		_add_message("You don't need to rest right now.")
		return

	var safe := _in_closed_room()
	var chance := REST_INTERRUPT_SAFE if safe else REST_INTERRUPT_OPEN
	var interrupted := false
	for _i in range(SLEEP_TURNS):
		_turn += 1
		if randf() < chance:
			interrupted = true
			break

	if interrupted:
		_player.fatigued = true
		var mname := _spawn_wandering_near_player()
		if mname != "":
			_add_message("A %s wanders in and wakes you!  You feel groggy." % mname)
		else:
			_add_message("Something disturbs your sleep.  You feel groggy.")
	else:
		var amount := maxi(1, GameData.roll(1, 8) + int(_player.con_mod()))
		_player.heal(amount)
		_player.fatigued = false
		_add_message("You sleep%s and recover %d HP." % ["" if safe else " uneasily", amount])

	_update_fov()
	_update_status()


func _in_closed_room() -> bool:
	var ri := _dungeon.room_index_at(_player.grid_pos)
	if ri < 0:
		return false
	var ring: Rect2i = _dungeon.rooms[ri].grow(1)
	for x in range(ring.position.x, ring.end.x):
		if _dungeon.get_tile(x, ring.position.y) == GameData.Tile.DOOR_OPEN:
			return false
		if _dungeon.get_tile(x, ring.end.y - 1) == GameData.Tile.DOOR_OPEN:
			return false
	for y in range(ring.position.y, ring.end.y):
		if _dungeon.get_tile(ring.position.x, y) == GameData.Tile.DOOR_OPEN:
			return false
		if _dungeon.get_tile(ring.end.x - 1, y) == GameData.Tile.DOOR_OPEN:
			return false
	return true


func _random_spawn_cell_near(center: Vector2i, min_r: int, max_r: int) -> Vector2i:
	for _t in range(30):
		var dx := randi_range(-max_r, max_r)
		var dy := randi_range(-max_r, max_r)
		var dist := absi(dx) + absi(dy)
		if dist < min_r or dist > max_r:
			continue
		var cell := center + Vector2i(dx, dy)
		if cell == _player.grid_pos or _monster_at.has(cell):
			continue
		if not GameData.is_passable(_dungeon.get_tile(cell.x, cell.y)):
			continue
		return cell
	return Vector2i(-1, -1)


func _spawn_wandering_near_player() -> String:
	var cell := _random_spawn_cell_near(_player.grid_pos, 2, 5)
	if cell.x < 0:
		return ""
	var kind := randi() % GameData.MONSTERS.size()
	_add_monster(kind, cell)
	var nm: String = GameData.MONSTERS[kind]["name"]
	return nm


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

	if _creating:
		_handle_create_input(event)
		get_viewport().set_input_as_handled()
		return

	if _inventory_open:
		_inventory_open = false
		_inv_bg.visible = false
		get_viewport().set_input_as_handled()
		return

	if not _player_alive:
		return

	if _player.is_moving:
		return

	if _awaiting_kick:
		_handle_kick_input(event)
		get_viewport().set_input_as_handled()
		return

	if _awaiting_quaff:
		_handle_quaff_input(event)
		get_viewport().set_input_as_handled()
		return

	if _awaiting_close:
		_handle_close_input(event)
		get_viewport().set_input_as_handled()
		return

	if _awaiting_wield:
		_handle_wield_input(event)
		get_viewport().set_input_as_handled()
		return

	if _awaiting_wear:
		_handle_wear_input(event)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_W:
		if event.shift_pressed:
			_try_wear()
		else:
			_try_wield()
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_K:
		_awaiting_kick = true
		_add_message("Kick in which direction?")
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_C:
		_awaiting_close = true
		_add_message("Close which door?")
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_I:
		_open_inventory()
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_Q:
		_try_quaff()
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_R:
		_try_rest()
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
	_run_round(_do_kick_action.bind(dir))


func _handle_close_input(event: InputEvent) -> void:
	_awaiting_close = false
	if event.keycode == KEY_ESCAPE:
		_add_message("Never mind.")
		return
	var dir := _dir_from_key(event.keycode)
	if dir == Vector2i.ZERO:
		_add_message("Never mind.")
		return

	var target: Vector2i = _player.grid_pos + dir
	var tile: int = _dungeon.get_tile(target.x, target.y)
	if tile != GameData.Tile.DOOR_OPEN:
		if tile == GameData.Tile.DOOR_CLOSED or tile == GameData.Tile.DOOR_LOCKED:
			_add_message("That door is already closed.")
		else:
			_add_message("There is no open door there.")
		return
	if _monster_at.has(target):
		var m: Monster = _monster_at[target]
		_add_message("The %s is in the doorway." % GameData.MONSTERS[m.kind]["name"])
		return

	_run_round(_do_close_action.bind(dir))


func _do_close_action(dir: Vector2i) -> void:
	var target: Vector2i = _player.grid_pos + dir
	# Re-validate: a monster may have stepped into the doorway if it won initiative.
	if _dungeon.get_tile(target.x, target.y) != GameData.Tile.DOOR_OPEN:
		return
	if _monster_at.has(target):
		var m: Monster = _monster_at[target]
		_add_message("The %s blocks the doorway." % GameData.MONSTERS[m.kind]["name"])
		return
	_dungeon.set_tile(target.x, target.y, GameData.Tile.DOOR_CLOSED)
	_add_message("You close the door.")


func _try_wield() -> void:
	_wield_options.clear()
	var seen := {}
	for k in _player.inventory:
		var kind: int = k
		if GameData.is_weapon(kind) and not seen.has(kind):
			seen[kind] = true
			_wield_options.append(kind)
	if _wield_options.is_empty():
		_add_message("You have no weapons to wield.")
		return
	_add_message(_selection_prompt("Wield which weapon?", _wield_options))
	_awaiting_wield = true


func _handle_wield_input(event: InputEvent) -> void:
	_awaiting_wield = false
	if event.keycode == KEY_ESCAPE:
		_add_message("Never mind.")
		return
	var idx: int = event.keycode - KEY_A
	if idx >= 0 and idx < _wield_options.size():
		var kind: int = _wield_options[idx]
		_run_round(_do_wield_action.bind(kind))
	else:
		_add_message("Never mind.")


func _do_wield_action(kind: int) -> void:
	var iname: String = GameData.ITEMS[kind]["name"]
	if GameData.is_two_handed(kind) and _player.equipped_shield >= 0:
		_player.equipped_shield = -1
		_add_message("You sling your shield to grip the %s with both hands." % iname)
	_player.equipped_weapon = kind
	_add_message("You wield the %s." % iname)


func _try_wear() -> void:
	_wear_options.clear()
	var seen := {}
	for k in _player.inventory:
		var kind: int = k
		if (GameData.is_armor(kind) or GameData.is_shield(kind)) and not seen.has(kind):
			seen[kind] = true
			_wear_options.append(kind)
	if _wear_options.is_empty():
		_add_message("You have no armor to wear.")
		return
	_add_message(_selection_prompt("Wear which armor?", _wear_options))
	_awaiting_wear = true


func _handle_wear_input(event: InputEvent) -> void:
	_awaiting_wear = false
	if event.keycode == KEY_ESCAPE:
		_add_message("Never mind.")
		return
	var idx: int = event.keycode - KEY_A
	if idx < 0 or idx >= _wear_options.size():
		_add_message("Never mind.")
		return
	var kind: int = _wear_options[idx]
	if GameData.is_shield(kind) and _player.equipped_weapon >= 0 \
			and GameData.is_two_handed(_player.equipped_weapon):
		_add_message("You can't use a shield with a two-handed weapon.")
		return
	_run_round(_do_wear_action.bind(kind))


func _do_wear_action(kind: int) -> void:
	var iname: String = GameData.ITEMS[kind]["name"]
	if GameData.is_shield(kind):
		_player.equipped_shield = kind
		_add_message("You ready your %s." % iname)
	else:
		_player.equipped_armor = kind
		_add_message("You don the %s." % iname)


func _selection_prompt(label: String, options: Array[int]) -> String:
	var prompt := label + "  "
	for i in range(options.size()):
		var kind: int = options[i]
		prompt += "[%s] %s" % [char(97 + i), GameData.ITEMS[kind]["name"]]
		var c := _count_item(kind)
		if c > 1:
			prompt += " (%d)" % c
		prompt += "   "
	prompt += "[Esc] cancel"
	return prompt


func _try_move(dir: Vector2i) -> void:
	var target: Vector2i = _player.grid_pos + dir
	if target.x < 0 or target.y < 0 or target.x >= GameData.MAP_W or target.y >= GameData.MAP_H:
		return

	# Attacking, opening, and walking all cost a turn -> run a full round.
	if _monster_at.has(target):
		_run_round(_do_move_action.bind(dir))
		return

	var tile: int = _dungeon.get_tile(target.x, target.y)
	if tile == GameData.Tile.DOOR_LOCKED:
		_add_message("This door is locked.  Kick it open with (k).")
		return
	if tile == GameData.Tile.DOOR_CLOSED or GameData.is_passable(tile):
		_run_round(_do_move_action.bind(dir))


func _do_move_action(dir: Vector2i) -> void:
	# Re-evaluated at execution time, so it stays correct if monsters moved first.
	var target: Vector2i = _player.grid_pos + dir
	if target.x < 0 or target.y < 0 or target.x >= GameData.MAP_W or target.y >= GameData.MAP_H:
		return

	if _monster_at.has(target):
		_attack_monster(_monster_at[target])
		return

	var tile: int = _dungeon.get_tile(target.x, target.y)
	if tile == GameData.Tile.DOOR_CLOSED:
		_dungeon.set_tile(target.x, target.y, GameData.Tile.DOOR_OPEN)
		_add_message("You open the door.")
		return

	if GameData.is_passable(tile):
		_player.move_to(target)
		if _items_at.has(target):
			_pickup_item(target)
		if tile == GameData.Tile.STAIRS_DOWN:
			_add_message("There is a staircase down here.")
		elif tile == GameData.Tile.STAIRS_UP:
			_add_message("There is a staircase up here.")


func _do_kick_action(dir: Vector2i) -> void:
	var target: Vector2i = _player.grid_pos + dir
	var tile: int = _dungeon.get_tile(target.x, target.y)

	if tile == GameData.Tile.DOOR_LOCKED or tile == GameData.Tile.DOOR_CLOSED:
		if randf() < 0.5:
			_dungeon.set_tile(target.x, target.y, GameData.Tile.DOOR_OPEN)
			_add_message("WHAMM!!  The door crashes open!")
		else:
			_add_message("WHAMM!!  The door holds firm.")
	elif GameData.is_wall(tile) or tile == GameData.Tile.NOTHING:
		_add_message("Ouch!  That hurts!")
	elif tile == GameData.Tile.DOOR_OPEN:
		_add_message("You kick at the open doorway.")
	else:
		_add_message("You kick at empty space.")


func _attack_monster(m: Monster) -> void:
	var data: Dictionary = GameData.MONSTERS[m.kind]
	var mname: String = data["name"]
	var target_ac: int = data["ac"]
	var atk: int = _player.melee_attack_bonus()
	var fatigue: int = FATIGUE_PENALTY if _player.fatigued else 0
	var net := atk - fatigue
	var d20 := randi_range(1, 20)
	var total := d20 + net

	if total >= target_ac:
		var base_dmg: int = GameData.roll(int(_player.weapon_dmg_n()), int(_player.weapon_dmg_d()))
		var dmg := maxi(1, base_dmg + int(_player.damage_bonus()))
		m.hp -= dmg
		_add_message("You hit the %s!  [d20 %d %+d = %d vs AC %d]  -%d HP" %
			[mname, d20, net, total, target_ac, dmg])
		if m.hp <= 0:
			_kill_monster(m, mname, int(data["xp"]))
	else:
		_add_message("You miss the %s.  [d20 %d %+d = %d vs AC %d]" %
			[mname, d20, net, total, target_ac])


func _kill_monster(m: Monster, mname: String, xp_value: int) -> void:
	_monster_at.erase(m.grid_pos)
	_monsters.erase(m)
	m.queue_free()
	_add_message("The %s dies!  (+%d XP)" % [mname, xp_value])
	_gain_xp(xp_value)


func _gain_xp(amount: int) -> void:
	_player.xp += amount
	while _player.xp >= _player.level * 20:
		_level_up()


func _level_up() -> void:
	_player.level += 1
	_player.max_hp += _player.gain_level_hp()
	_player.hp = _player.max_hp
	_add_message("Welcome to experience level %d!" % _player.level)


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

	_last_visible = visible
	_renderer.update_visibility(visible)
	_refresh_monster_visibility()


func _regenerate() -> void:
	_dungeon.generate(GameData.MAP_W, GameData.MAP_H)
	_renderer.dungeon = _dungeon
	_renderer.visible_cells.clear()
	_renderer.explored_cells.clear()
	_awaiting_kick = false
	_awaiting_quaff = false
	_awaiting_close = false
	_turn = 1
	_player_alive = true
	_player.place_at(_dungeon.get_start_pos())
	_spawn_monsters()
	_spawn_items()
	_update_fov()
	_enter_creation()


func _toggle_reveal() -> void:
	_renderer.set_reveal_all(not _renderer.reveal_all)
	_refresh_monster_visibility()
	if _renderer.reveal_all:
		_add_message("[Debug] Revealing the whole dungeon.")
	else:
		_add_message("[Debug] Fog of war restored.")


func _spawn_monsters() -> void:
	_clear_monsters()
	for ri in range(1, _dungeon.rooms.size()):
		var room: Rect2i = _dungeon.rooms[ri]
		var n := randi_range(0, 2)
		for _k in range(n):
			var cell := _random_floor_cell(room)
			if cell.x < 0:
				continue
			var kind := randi() % GameData.MONSTERS.size()
			_add_monster(kind, cell)


func _random_floor_cell(room: Rect2i) -> Vector2i:
	for _t in range(10):
		var x := randi_range(room.position.x, room.end.x - 1)
		var y := randi_range(room.position.y, room.end.y - 1)
		var cell := Vector2i(x, y)
		if _dungeon.get_tile(x, y) == GameData.Tile.FLOOR and not _monster_at.has(cell):
			return cell
	return Vector2i(-1, -1)


func _add_monster(kind: int, cell: Vector2i) -> void:
	var m := Monster.new()
	m.setup(kind, cell)
	add_child(m)
	_monsters.append(m)
	_monster_at[cell] = m


func _clear_monsters() -> void:
	for m in _monsters:
		m.queue_free()
	_monsters.clear()
	_monster_at.clear()


func _spawn_items() -> void:
	_items_at.clear()
	for ri in range(_dungeon.rooms.size()):
		var room: Rect2i = _dungeon.rooms[ri]
		if randf() < 0.5:
			_place_item(room, _gold_item())
		if randf() < 0.35:
			_place_item(room, _potion_item())
		if randf() < 0.20:
			_place_item(room, _loot_item(_random_weapon_kind()))
		if randf() < 0.15:
			_place_item(room, _loot_item(_random_armor_kind()))
	_renderer.queue_redraw()


func _place_item(room: Rect2i, item: Dictionary) -> void:
	for _t in range(10):
		var x := randi_range(room.position.x, room.end.x - 1)
		var y := randi_range(room.position.y, room.end.y - 1)
		var cell := Vector2i(x, y)
		if _dungeon.get_tile(x, y) != GameData.Tile.FLOOR:
			continue
		if _items_at.has(cell) or _monster_at.has(cell):
			continue
		_items_at[cell] = item
		return


func _gold_item() -> Dictionary:
	return {"glyph": "$", "color": GameData.COLOR_GOLD, "gold": randi_range(2, 30)}


func _potion_item() -> Dictionary:
	var data: Dictionary = GameData.ITEMS[GameData.ItemKind.HEALING_POTION]
	return {"glyph": "!", "color": data["color"], "item": GameData.ItemKind.HEALING_POTION}


func _loot_item(kind: int) -> Dictionary:
	var data: Dictionary = GameData.ITEMS[kind]
	return {"glyph": data["glyph"], "color": data["color"], "item": kind}


func _random_weapon_kind() -> int:
	var kinds: Array[int] = []
	for kind in range(GameData.ITEMS.size()):
		if GameData.is_weapon(kind):
			kinds.append(kind)
	var pick: int = kinds[randi() % kinds.size()]
	return pick


func _random_armor_kind() -> int:
	var kinds: Array[int] = []
	for kind in range(GameData.ITEMS.size()):
		if GameData.is_armor(kind) or GameData.is_shield(kind):
			kinds.append(kind)
	var pick: int = kinds[randi() % kinds.size()]
	return pick


func _pickup_item(cell: Vector2i) -> void:
	var it: Dictionary = _items_at[cell]
	_items_at.erase(cell)
	if it.has("gold"):
		var amount: int = it["gold"]
		_player.add_gold(amount)
		_add_message("You pick up %d gold piece%s." % [amount, "" if amount == 1 else "s"])
	else:
		var kind: int = it["item"]
		_player.add_item(kind)
		_add_message("You pick up a %s." % GameData.ITEMS[kind]["name"])
	_renderer.queue_redraw()


func _refresh_monster_visibility() -> void:
	var reveal: bool = _renderer.reveal_all
	for m in _monsters:
		m.visible = reveal or _last_visible.has(m.grid_pos)


func _run_round(player_action: Callable) -> void:
	# A round is the unit of OSR combat. When combat is joined, both sides roll
	# 1d6 group initiative; the higher side takes its whole phase first.
	_turn += 1
	var monsters_first := false
	if _engaged():
		var p_init := randi_range(1, 6)
		var m_init := randi_range(1, 6)
		monsters_first = m_init > p_init
		if monsters_first:
			_add_message("Initiative: you %d, enemy %d.  The enemy strikes first!" %
				[p_init, m_init])
		else:
			_add_message("Initiative: you %d, enemy %d.  You act first." %
				[p_init, m_init])

	if monsters_first:
		_monsters_act()
		if _player_alive:
			player_action.call()
	else:
		player_action.call()
		_update_fov()
		_monsters_act()

	_update_fov()
	_update_status()


func _engaged() -> bool:
	for m in _monsters:
		if not _last_visible.has(m.grid_pos):
			continue
		var d: Vector2i = m.grid_pos - _player.grid_pos
		if absi(d.x) + absi(d.y) <= ENGAGE_RANGE:
			return true
	return false


func _monsters_act() -> void:
	for m in _monsters:
		if not _player_alive:
			return
		_monster_take_turn(m)


func _monster_take_turn(m: Monster) -> void:
	# Only monsters the player can currently see are active (they see you too).
	if not _last_visible.has(m.grid_pos):
		return
	var to_player: Vector2i = _player.grid_pos - m.grid_pos
	var dist := absi(to_player.x) + absi(to_player.y)
	if dist <= 1:
		_monster_attack(m)
		return
	var step := _choose_monster_step(m, to_player)
	if step != Vector2i.ZERO:
		var old := m.grid_pos
		m.move_to(old + step)
		_monster_at.erase(old)
		_monster_at[m.grid_pos] = m


func _choose_monster_step(m: Monster, to_player: Vector2i) -> Vector2i:
	# Greedy chase: try the longer axis first, then the other.
	var options: Array[Vector2i] = []
	if absi(to_player.x) >= absi(to_player.y):
		if to_player.x != 0:
			options.append(Vector2i(signi(to_player.x), 0))
		if to_player.y != 0:
			options.append(Vector2i(0, signi(to_player.y)))
	else:
		if to_player.y != 0:
			options.append(Vector2i(0, signi(to_player.y)))
		if to_player.x != 0:
			options.append(Vector2i(signi(to_player.x), 0))
	for step in options:
		if _monster_can_enter(m.grid_pos + step):
			return step
	return Vector2i.ZERO


func _monster_can_enter(cell: Vector2i) -> bool:
	if cell == _player.grid_pos:
		return false
	if _monster_at.has(cell):
		return false
	return GameData.is_passable(_dungeon.get_tile(cell.x, cell.y))


func _monster_attack(m: Monster) -> void:
	var data: Dictionary = GameData.MONSTERS[m.kind]
	var mname: String = data["name"]
	var atk: int = data["atk"]
	var pac: int = _player.armor_class()
	var d20 := randi_range(1, 20)
	var total := d20 + atk

	if total >= pac:
		var dmg := GameData.roll(int(data["dmg_n"]), int(data["dmg_d"]))
		_player.take_damage(dmg)
		_add_message("The %s hits you!  [d20 %d+%d=%d vs AC %d]  -%d HP" %
			[mname, d20, atk, total, pac, dmg])
		if not _player.is_alive():
			_player_dies()
	else:
		_add_message("The %s misses you.  [d20 %d+%d=%d vs AC %d]" %
			[mname, d20, atk, total, pac])


func _player_dies() -> void:
	_player_alive = false
	_add_message("You die...")
	_add_message("Press F5 to start a new game.")


func _add_message(text: String) -> void:
	_msg_log.append_text(text + "\n")


func _update_status() -> void:
	var st: int = _player.strength
	var dx: int = _player.dexterity
	var co: int = _player.constitution
	var intel: int = _player.intelligence
	var wi: int = _player.wisdom
	var cha: int = _player.charisma
	var hp: int = _player.hp
	var max_hp: int = _player.max_hp
	var ac: int = _player.armor_class()
	var lvl: int = _player.level
	var xp: int = _player.xp
	var gold: int = _player.gold
	var fatigued: bool = _player.fatigued
	_status.clear()
	_status.append_text("Adventurer the Fighter     St:%d Dx:%d Co:%d In:%d Wi:%d Ch:%d     Lawful\n" %
		[st, dx, co, intel, wi, cha])
	var line2 := "$:%d  HP:%d(%d)  Pw:0(0)  AC:%d  Exp:%d/%d  T:%d" % [
		gold, maxi(0, hp), max_hp, ac, lvl, xp, _turn]
	if fatigued:
		line2 += "  Fatigued"
	_status.append_text(line2)
