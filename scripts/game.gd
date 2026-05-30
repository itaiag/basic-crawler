extends Node2D

const TOP_PANEL_H := 72
const BOTTOM_PANEL_H := 60
const RIGHT_PANEL_W := 340
const ENGAGE_RANGE := 5
const MORALE_SIGHT_RANGE := 6

# Subtle battle zoom. In Godot 4 a larger Camera2D.zoom means more zoomed-in,
# so combat nudges the view slightly closer. Keep it gentle ("felt, not noticed").
const CAMERA_ZOOM_NORMAL := Vector2(1.0, 1.0)
const CAMERA_ZOOM_COMBAT := Vector2(1.12, 1.12)
const CAMERA_ZOOM_DURATION := 0.25

# Rest/sleep tuning. A rest is *abstracted* as SLEEP_TURNS danger rolls -- one
# per advanced turn -- NOT 15 fully simulated monster turns. Nothing actually
# moves while you sleep; each turn only rolls against an interruption chance.
# Per-turn chances are picked for cumulative risk across a whole rest:
#   safe (closed room): 1 - (1 - 0.01)^15  ~= 14%
#   open / unsafe:      1 - (1 - 0.15)^15  ~= 91%
const SLEEP_TURNS := 15
const REST_INTERRUPT_SAFE := 0.01
const REST_INTERRUPT_OPEN := 0.15
const FATIGUE_PENALTY := 2
const KICK_ATK_PENALTY := 2  # Basic Fantasy: kicks rolled at -2 attack

var _dungeon := DungeonGenerator.new()
var _turn := 1
var _combat_zoom_active := false
var _camera_zoom_tween: Tween
var _awaiting_kick := false

# Encounter-based group initiative (Basic Fantasy / OSR): rolled once when an
# encounter begins and kept for its whole duration -- never rerolled per round.
var _encounter_active := false
var _player_has_initiative := true
var _player_initiative_roll := 0
var _monster_initiative_roll := 0

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
var _combat_panel: Node  # combat_panel.gd, built at runtime under UI

@onready var _renderer: Node2D = $DungeonRenderer
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Player/Camera
var _light: Node2D  # torchlight overlay (scripts/light_overlay.gd), built at runtime
@onready var _msg_log: RichTextLabel = $UI/MessageLog
@onready var _status: RichTextLabel = $UI/StatusBar


func _ready() -> void:
	_dungeon.generate(GameData.MAP_W, GameData.MAP_H)
	_renderer.dungeon = _dungeon
	_renderer.items = _items_at

	_setup_camera()
	_setup_light()
	_setup_vignette()
	_setup_ui()
	_setup_overlays()
	_setup_side_panel()
	_setup_combat_panel()

	var start := _dungeon.get_start_pos()
	_player.grid_pos = start
	_player.position = GameData.grid_to_world(start)

	_spawn_monsters()
	_spawn_items()
	_update_fov()
	_enter_creation()


func _setup_camera() -> void:
	_camera.zoom = CAMERA_ZOOM_NORMAL
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
	msg_style.bg_color = Color(0.05, 0.05, 0.07)
	msg_style.content_margin_left = 10
	msg_style.content_margin_top = 4
	msg_style.content_margin_right = 10
	msg_style.border_color = Color(0.20, 0.20, 0.26)
	msg_style.border_width_bottom = 1
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
	status_style.bg_color = Color(0.05, 0.05, 0.07)
	status_style.content_margin_left = 10
	status_style.content_margin_top = 4
	status_style.content_margin_right = 10
	status_style.border_color = Color(0.20, 0.20, 0.26)
	status_style.border_width_top = 1
	_status.add_theme_stylebox_override("normal", status_style)
	_status.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_status.add_theme_font_override("normal_font", font)
	_status.add_theme_font_size_override("normal_font_size", 16)


# Torchlight overlay node: a world-space child that darkens visible cells by
# distance from the player. High z_index so it draws above the dungeon renderer
# and the runtime-spawned monsters/player tokens.
func _setup_light() -> void:
	_light = Node2D.new()
	_light.set_script(load("res://scripts/light_overlay.gd"))
	_light.z_index = 10
	add_child(_light)


# Screen-space radial vignette: a soft dark frame at the edges, drawn behind the
# text labels. No shader -- a radial GradientTexture2D stretched full-screen, which
# is GL-compatibility / web / mobile safe.
func _setup_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.5)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256

	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(rect)
	$UI.move_child(rect, 0)  # behind the message log / status bar / panels


func _setup_overlays() -> void:
	_create_bg = _new_overlay()
	_create_label = _create_bg.get_child(0) as RichTextLabel
	_setup_create_decor()


# Frames the character-creation text: a soft warm torch-glow and a bordered
# stone card behind the label, so the menu shares the dungeon's lit mood
# instead of floating on flat black. No shader -- radial GradientTexture2D +
# StyleBoxFlat, GL-compatibility / web / mobile safe.
func _setup_create_decor() -> void:
	var vp := get_viewport().get_visible_rect().size

	var card_w := 540.0
	var card_h := 300.0
	var card_pos := Vector2((vp.x - card_w) * 0.5, vp.y * 0.06)
	var card_center := card_pos + Vector2(card_w, card_h) * 0.5

	# Warm radial torch-glow, larger than the card, centered behind it.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.72, 0.36, 0.13),
		Color(0.95, 0.72, 0.36, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256

	var glow := TextureRect.new()
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var glow_size := Vector2(card_w + 360.0, card_h + 320.0)
	glow.size = glow_size
	glow.position = card_center - glow_size * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Bordered dark-stone card.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.08, 0.92)
	sb.border_color = Color(0.55, 0.42, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)

	var card := Panel.new()
	card.position = card_pos
	card.size = Vector2(card_w, card_h)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", sb)

	# Insert behind the label (child 0); label must draw on top.
	_create_bg.add_child(glow)
	_create_bg.add_child(card)
	_create_bg.move_child(glow, 0)
	_create_bg.move_child(card, 1)


# A right-docked panel beside the dungeon (between the message and status bars).
# Holds the inventory for now; meant to host other content (lore, etc.) later.
func _setup_side_panel() -> void:
	var font := preload("res://resources/mono_font.tres")
	var vp := get_viewport().get_visible_rect().size
	var panel_h := vp.y - TOP_PANEL_H - BOTTOM_PANEL_H

	_inv_bg = ColorRect.new()
	_inv_bg.color = Color(0.04, 0.04, 0.04)
	_inv_bg.position = Vector2(vp.x - RIGHT_PANEL_W, TOP_PANEL_H)
	_inv_bg.size = Vector2(RIGHT_PANEL_W, panel_h)
	_inv_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_bg.visible = false
	$UI.add_child(_inv_bg)

	_inv_label = RichTextLabel.new()
	_inv_label.bbcode_enabled = true
	_inv_label.scroll_active = false
	_inv_label.position = Vector2.ZERO
	_inv_label.size = Vector2(RIGHT_PANEL_W, panel_h)
	_inv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.04)
	style.border_color = Color(0.32, 0.32, 0.32)
	style.border_width_left = 1
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 10
	_inv_label.add_theme_stylebox_override("normal", style)
	_inv_label.add_theme_font_override("normal_font", font)
	_inv_label.add_theme_font_override("bold_font", font)
	_inv_label.add_theme_font_size_override("normal_font_size", 16)
	_inv_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_inv_bg.add_child(_inv_label)


# The combat card is its own node (combat_panel.gd) under the UI layer; game.gd
# feeds it the fight's screen-space area via the _combat_area_screen closure.
func _setup_combat_panel() -> void:
	var font := preload("res://resources/mono_font.tres")
	var vp := get_viewport().get_visible_rect().size
	_combat_panel = load("res://scripts/combat_panel.gd").new()
	add_child(_combat_panel)
	_combat_panel.setup($UI, font, vp, TOP_PANEL_H, BOTTOM_PANEL_H, _combat_area_screen)


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
	_add_message("Commands: arrows move, k kick, c close door, i inventory, q quaff, w wield, W wear, R rest.")
	_add_message("[Debug] F5: new dungeon   F6: reveal map")
	_update_status()
	_update_combat_camera_zoom()


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

	var t := "\n\n\n\n[center][font_size=30][b][color=#e0b25a]Create Your Character[/color][/b][/font_size]\n\n"
	t += "[color=#b8b0a0]Human Fighter,  [/color][color=#cfc6dc]Lawful[/color]\n\n"
	t += "%s    %s    %s\n" % [
		_stat_cell("St", st), _stat_cell("Dx", dx), _stat_cell("Co", co)]
	t += "%s    %s    %s\n\n" % [
		_stat_cell("In", intel), _stat_cell("Wi", wi), _stat_cell("Ch", cha)]
	t += "[color=#d06a5a]HP %d[/color]        [color=#6a9fd0]AC %d[/color]\n\n\n" % [hp, ac]
	t += "[color=#e0b25a][ R ][/color] Reroll          [color=#e0b25a][ Enter ][/color] Begin[/center]"
	_create_label.text = t


# Format one ability score as "Lbl NN (+/-M)" with the value tinted by its modifier.
func _stat_cell(label: String, value: int) -> String:
	var m: int = GameData.ability_mod(value)
	var col := "#888888"
	if m > 0:
		col = "#7ec850"
	elif m < 0:
		col = "#d06a5a"
	return "[color=#9a9286]%s[/color] [color=%s]%2d (%+d)[/color]" % [label, col, value, m]


func _open_inventory() -> void:
	_inventory_open = true
	_update_inv_label()
	_inv_bg.visible = true


func _update_inv_label() -> void:
	var t := "[font_size=22][b]Inventory[/b][/font_size]\n\n"
	t += "Gold: %d\n" % int(_player.gold)

	# Bucket distinct kinds by category, preserving inventory order.
	var weapons: Array[int] = []
	var armor: Array[int] = []
	var potions: Array[int] = []
	var other: Array[int] = []
	var seen := {}
	for k in _player.inventory:
		var kind: int = k
		if seen.has(kind):
			continue
		seen[kind] = true
		if GameData.is_weapon(kind):
			weapons.append(kind)
		elif GameData.is_armor(kind) or GameData.is_shield(kind):
			armor.append(kind)
		elif GameData.is_potion(kind):
			potions.append(kind)
		else:
			other.append(kind)

	t += _inv_section("Weapons", weapons)
	t += _inv_section("Armor", armor)
	t += _inv_section("Potions", potions)
	t += _inv_section("Other", other)

	if weapons.is_empty() and armor.is_empty() and potions.is_empty() and other.is_empty():
		t += "\n(carrying nothing)\n"

	t += "\n[color=#888888]i to close[/color]"
	_inv_label.text = t


func _inv_section(title: String, kinds: Array[int]) -> String:
	if kinds.is_empty():
		return ""
	var s := "\n[b]%s[/b]\n" % title
	for kind in kinds:
		s += _inv_item_line(kind)
	return s


func _inv_item_line(kind: int) -> String:
	var data: Dictionary = GameData.ITEMS[kind]
	var line := "  " + str(data["name"])
	var count := _count_item(kind)
	if count > 1:
		line += " x%d" % count
	var marker := _equip_marker(kind)
	if marker != "":
		line += " [color=#c8a850]%s[/color]" % marker
	line += "\n"
	if GameData.is_weapon(kind):
		var hit: int = _player.melee_attack_bonus()
		var db: int = _player.damage_bonus()
		var dmg := "%dd%d" % [int(data["dmg_n"]), int(data["dmg_d"])]
		if db != 0:
			dmg += "%+d" % db
		line += "      [color=#999999]%+d to hit, %s dmg[/color]\n" % [hit, dmg]
	elif GameData.is_armor(kind):
		line += "      [color=#999999]AC %d[/color]\n" % int(data["ac"])
	elif GameData.is_shield(kind):
		line += "      [color=#999999]+1 AC[/color]\n"
	return line


func _equip_marker(kind: int) -> String:
	if kind == _player.equipped_weapon:
		return "(wielded)"
	if kind == _player.equipped_armor:
		return "(worn)"
	if kind == _player.equipped_shield:
		return "(shield)"
	return ""


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
		prompt += "%s) %s" % [char(97 + i), GameData.ITEMS[kind]["name"]]
		var c := _count_item(kind)
		if c > 1:
			prompt += " (%d)" % c
		prompt += "   "
	prompt += "Esc to cancel"
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
	# Abstracted rest: advance the clock and roll for danger each turn instead of
	# running real monster turns. The first failed roll wakes the player.
	var interrupted := false
	for _i in range(SLEEP_TURNS):
		_turn += 1
		if randf() < chance:
			interrupted = true
			break

	if interrupted:
		var was_fatigued: bool = _player.fatigued
		_player.fatigued = true
		var mname := _spawn_wandering_near_player()
		if mname != "":
			_add_message("A %s wanders in and wakes you!" % mname)
		else:
			_add_message("Something disturbs your sleep.")
		# Spell out what fatigue does the first time it sets in; don't repeat it.
		if not was_fatigued:
			_add_message("You are groggy from lost sleep: -%d to hit until you sleep soundly." % FATIGUE_PENALTY)
	else:
		var amount := maxi(1, GameData.roll(1, 8) + int(_player.con_mod()))
		_player.heal(amount)
		_player.fatigued = false
		_add_message("You sleep%s and recover %d HP." % ["" if safe else " uneasily", amount])

	_update_fov()
	_update_status()
	_update_combat_camera_zoom()


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


func _spawn_wandering_near_player() -> String:
	var cell := DungeonPopulator.wandering_cell_near(_player.grid_pos, 2, 5, _dungeon, _monster_at, _player.grid_pos)
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
		_add_message("You put on the %s." % iname)


func _selection_prompt(label: String, options: Array[int]) -> String:
	var prompt := label + "  "
	for i in range(options.size()):
		var kind: int = options[i]
		prompt += "%s) %s" % [char(97 + i), GameData.ITEMS[kind]["name"]]
		var c := _count_item(kind)
		if c > 1:
			prompt += " (%d)" % c
		prompt += "   "
	prompt += "Esc to cancel"
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
	if tile == GameData.Tile.PILLAR:
		# Like a wall bump: no turn consumed, but a hint that it's a real obstacle.
		_add_message("A stone pillar blocks the way.")
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

	if _monster_at.has(target):
		_kick_monster(_monster_at[target])
		return

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


func _kick_monster(m: Monster) -> void:
	var data: Dictionary = GameData.MONSTERS[m.kind]
	var mname: String = data["name"]
	var target_ac: int = data["ac"]

	# BF brawling rule: soft-armored kicker vs metal-armored target -> kick rebounds.
	var player_soft_armor: bool = _player.equipped_armor < 0 or \
		_player.equipped_armor == GameData.ItemKind.LEATHER_ARMOR
	if player_soft_armor and data.get("metal_armor", false):
		var dmg := GameData.roll(1, 4)
		_add_message("You hurt your foot kicking the armored %s!  (%d damage to you)" % [mname, dmg])
		_player.hp -= dmg
		_update_status()
		if not _player.is_alive():
			_player_dies()
		return

	var base_atk: int = _player.melee_attack_bonus()
	var fatigue: int = FATIGUE_PENALTY if _player.fatigued else 0
	var d20 := randi_range(1, 20)
	var total := d20 + base_atk - KICK_ATK_PENALTY - fatigue

	var calc := "d20 %d %s -2" % [d20, TextFmt.signed(base_atk)]
	if fatigue > 0:
		calc += " %s" % TextFmt.signed(-fatigue)
	calc += " = %d vs AC %d" % [total, target_ac]

	var hit := total >= target_ac
	if not hit:
		_add_message("You miss the %s." % mname)
		_combat_panel.push_attack(
			"You kick at %s" % TextFmt.cap(mname), false, true, d20, calc, "", "")
		return

	var dmg: int = GameData.roll(1, 4)
	var dline := "kick 1d4 = %d" % dmg
	m.hp -= dmg
	_add_message("You kick the %s for %d damage." % [mname, dmg])
	var hp_short := "slain" if m.hp <= 0 else "%d/%d" % [m.hp, m.max_hp]
	_combat_panel.push_attack(
		"You kick %s" % TextFmt.cap(mname), true, true, d20, calc, dline, hp_short)
	if m.hp <= 0:
		_kill_monster(m, mname, int(data["xp"]))
	else:
		_check_half_hp_morale(m)


func _attack_monster(m: Monster) -> void:
	var data: Dictionary = GameData.MONSTERS[m.kind]
	var mname: String = data["name"]
	var target_ac: int = data["ac"]
	var atk: int = _player.melee_attack_bonus()
	var fatigue: int = FATIGUE_PENALTY if _player.fatigued else 0
	var d20 := randi_range(1, 20)
	var total := d20 + atk - fatigue

	var calc := "d20 %d %s" % [d20, TextFmt.signed(atk)]
	if fatigue > 0:
		calc += " %s" % TextFmt.signed(-fatigue)  # show the fatigue penalty as its own term
	calc += " = %d vs AC %d" % [total, target_ac]
	var hit := total >= target_ac
	if not hit:
		_add_message("You miss the %s." % mname)
		_combat_panel.push_attack(
			"You swing at %s" % TextFmt.cap(mname), false, true, d20, calc, "", "")
		return

	var dn := int(_player.weapon_dmg_n())
	var dd := int(_player.weapon_dmg_d())
	var base_dmg := GameData.roll(dn, dd)
	var dbonus := int(_player.damage_bonus())
	var raw := base_dmg + dbonus
	var dmg := maxi(1, raw)
	var dline := "%s %dd%d %d %s = %d" % [_player_weapon_name(), dn, dd, base_dmg, TextFmt.signed(dbonus), raw]
	if dmg != raw:
		dline += " (min 1)"

	m.hp -= dmg
	_add_message("You hit the %s for %d damage." % [mname, dmg])
	var hp_short := "slain" if m.hp <= 0 else "%d/%d" % [m.hp, m.max_hp]
	_combat_panel.push_attack(
		"You strike %s" % TextFmt.cap(mname), true, true, d20, calc, dline, hp_short)
	if m.hp <= 0:
		_kill_monster(m, mname, int(data["xp"]))
	else:
		_check_half_hp_morale(m)


func _kill_monster(m: Monster, mname: String, xp_value: int) -> void:
	var dead_pos: Vector2i = m.grid_pos
	_monster_at.erase(m.grid_pos)
	_monsters.erase(m)
	m.queue_free()
	_add_message("%s dies!  (+%d XP)" % [TextFmt.cap(mname), xp_value])
	_gain_xp(xp_value)
	_check_ally_death_morale(dead_pos)


func _check_half_hp_morale(m: Monster) -> void:
	# First time a monster is brought to half HP or less, it tests its nerve.
	if m.morale_checked or m.fleeing:
		return
	if m.hp * 2 <= m.max_hp:
		m.morale_checked = true
		_morale_check(m)


func _check_ally_death_morale(dead_pos: Vector2i) -> void:
	# Living monsters near enough to witness a comrade fall test morale too.
	for m in _monsters:
		if m.fleeing:
			continue
		if not _last_visible.has(m.grid_pos):
			continue
		var d: Vector2i = m.grid_pos - dead_pos
		if absi(d.x) + absi(d.y) <= MORALE_SIGHT_RANGE:
			_morale_check(m)


func _morale_check(m: Monster) -> void:
	# Basic Fantasy 2d6 morale: a roll over the score breaks the monster -> flee.
	var data: Dictionary = GameData.MONSTERS[m.kind]
	var nm: String = data["name"]
	var morale: int = data["morale"]
	var roll := randi_range(1, 6) + randi_range(1, 6)
	var held := roll <= morale
	var verdict := "[color=#9bd06b]HOLDS[/color]" if held else "[color=#d09040]FLEES[/color]"
	_add_message("%s morale: 2d6 %d vs %d -> %s" %
		[TextFmt.cap(nm), roll, morale, verdict])
	_combat_panel.push_morale(TextFmt.cap(nm), held, roll, morale)
	if not held:
		m.fleeing = true


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
	_light.enabled = not _renderer.reveal_all
	_light.set_light(_player.grid_pos, visible)
	_refresh_monster_visibility()


func _regenerate() -> void:
	_dungeon.generate(GameData.MAP_W, GameData.MAP_H)
	_renderer.dungeon = _dungeon
	_renderer.visible_cells.clear()
	_renderer.explored_cells.clear()
	_awaiting_kick = false
	_awaiting_quaff = false
	_awaiting_close = false
	_awaiting_wield = false
	_awaiting_wear = false
	_reset_combat_zoom()
	_end_encounter()  # no stale initiative carried into the new dungeon
	_turn = 1
	_player_alive = true
	_player.place_at(_dungeon.get_start_pos())
	_spawn_monsters()
	_spawn_items()
	_update_fov()
	_enter_creation()


func _toggle_reveal() -> void:
	_renderer.set_reveal_all(not _renderer.reveal_all)
	_light.enabled = not _renderer.reveal_all
	_light.queue_redraw()
	_refresh_monster_visibility()
	if _renderer.reveal_all:
		_add_message("[Debug] Revealing the whole dungeon.")
	else:
		_add_message("[Debug] Fog of war restored.")


func _spawn_monsters() -> void:
	_clear_monsters()
	for spawn in DungeonPopulator.roll_monsters(_dungeon, _monster_at):
		var kind: int = spawn["kind"]
		var cell: Vector2i = spawn["cell"]
		_add_monster(kind, cell)


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
	# The renderer holds _items_at by reference (set once in _ready), so refill the
	# existing dict in place rather than rebinding it.
	_items_at.clear()
	_items_at.merge(DungeonPopulator.roll_items(_dungeon, _monster_at), true)
	_renderer.queue_redraw()


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
	# A round is the unit of OSR combat. Group initiative is rolled ONCE when the
	# encounter begins (here, on the not-engaged -> engaged transition) and the
	# winning side keeps the first phase for the whole encounter -- no rerolls.
	_turn += 1
	if _engaged() and not _encounter_active:
		_begin_encounter()
	if _encounter_active:
		_begin_combat_turn()  # new round: bump Turn N, clear last round's events
	var monsters_first := _encounter_active and not _player_has_initiative

	if monsters_first:
		# Monsters resolve first; the player's chosen action is re-derived at call
		# time (see _do_*_action), so it adapts if the board changed underfoot.
		_monsters_act()
		if _player_alive:
			player_action.call()
	else:
		player_action.call()
		_update_fov()
		_monsters_act()

	_update_fov()
	_update_status()
	_update_combat_camera_zoom()


# Start of encounter: roll 1d6 per side, higher acts first, ties go to the
# player. Logged compactly once (top log + combat panel), never per round.
func _begin_encounter() -> void:
	_encounter_active = true
	_player_initiative_roll = randi_range(1, 6)
	_monster_initiative_roll = randi_range(1, 6)
	_player_has_initiative = _player_initiative_roll >= _monster_initiative_roll
	var who := "You win initiative." if _player_has_initiative else "Monsters win initiative."
	# Initiative lives in the panel's fixed header (built from the stored rolls),
	# not as a scrolling event. The top log keeps one compact narrative line.
	_add_message("Encounter begins.  %s" % who)
	_combat_panel.begin_encounter(_player_initiative_roll, _monster_initiative_roll, _player_has_initiative)


# End of encounter: reset state so the next engagement rolls fresh initiative.
func _end_encounter() -> void:
	_encounter_active = false
	_player_has_initiative = true
	_player_initiative_roll = 0
	_monster_initiative_roll = 0
	_combat_panel.end_encounter()


func _engaged() -> bool:
	for m in _monsters:
		if not _last_visible.has(m.grid_pos):
			continue
		var d: Vector2i = m.grid_pos - _player.grid_pos
		if absi(d.x) + absi(d.y) <= ENGAGE_RANGE:
			return true
	return false


# Combat = the same engagement test used for initiative. Re-evaluated after each
# turn; the zoom only animates when the state actually flips.
func _update_combat_camera_zoom() -> void:
	var should_zoom: bool = _player.hp > 0 and _engaged()
	# Combat over (disengaged or player dead) -> close out the encounter so a
	# later fight rolls new initiative. Same condition that drops the zoom.
	if _encounter_active and not should_zoom:
		_end_encounter()
	_set_combat_zoom(should_zoom)


func _set_combat_zoom(active: bool) -> void:
	if _combat_zoom_active == active:
		return
	_combat_zoom_active = active
	if active:
		# Show the card; if no blow has landed yet this engagement, prime it.
		_combat_panel.show_card()
	else:
		# Leaving combat: clear the panel so the next fight starts fresh.
		_combat_panel.hide_card()
	if _camera_zoom_tween:
		_camera_zoom_tween.kill()
	var target_zoom := CAMERA_ZOOM_COMBAT if active else CAMERA_ZOOM_NORMAL
	_camera_zoom_tween = create_tween()
	_camera_zoom_tween.set_trans(Tween.TRANS_SINE)
	_camera_zoom_tween.set_ease(Tween.EASE_OUT)
	_camera_zoom_tween.tween_property(_camera, "zoom", target_zoom, CAMERA_ZOOM_DURATION)


func _reset_combat_zoom() -> void:
	if _camera_zoom_tween:
		_camera_zoom_tween.kill()
	_combat_zoom_active = false
	_camera.zoom = CAMERA_ZOOM_NORMAL
	_combat_panel.hide_card()


# --- Combat panel (structured encounter card) -----------------------------
# The card itself lives in combat_panel.gd; game.gd just drives it.

func _begin_combat_turn() -> void:
	_combat_panel.begin_turn()


# Screen-space bounding box of the active fight: the player plus any engaged,
# currently-visible monsters, padded by a cell. Uses logical grid positions
# (stable mid-tween) projected through the live camera transform.
func _combat_area_screen() -> Rect2:
	var xf := get_viewport().get_canvas_transform()
	var area := Rect2(xf * GameData.grid_to_world(_player.grid_pos), Vector2.ZERO)
	for m in _monsters:
		if not _last_visible.has(m.grid_pos):
			continue
		var d: Vector2i = m.grid_pos - _player.grid_pos
		if absi(d.x) + absi(d.y) <= ENGAGE_RANGE:
			area = area.expand(xf * GameData.grid_to_world(m.grid_pos))
	return area.grow(float(GameData.CELL.x))


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

	if m.fleeing:
		var flee := MonsterAI.flee_step(m.grid_pos, to_player, _dungeon, _monster_at, _player.grid_pos)
		if flee != Vector2i.ZERO:
			_move_monster(m, flee)
		elif dist <= 1:
			# Cornered with nowhere to run -> it turns and fights.
			_monster_attack(m)
		return

	if dist <= 1:
		_monster_attack(m)
		return
	var step := MonsterAI.chase_step(m.grid_pos, to_player, _dungeon, _monster_at, _player.grid_pos)
	if step != Vector2i.ZERO:
		_move_monster(m, step)


func _move_monster(m: Monster, step: Vector2i) -> void:
	var old: Vector2i = m.grid_pos
	m.move_to(old + step)
	_monster_at.erase(old)
	_monster_at[m.grid_pos] = m


func _monster_attack(m: Monster) -> void:
	var data: Dictionary = GameData.MONSTERS[m.kind]
	var mname: String = data["name"]
	var atk: int = data["atk"]
	var pac: int = _player.armor_class()
	var d20 := randi_range(1, 20)
	var total := d20 + atk
	var hit := total >= pac
	var calc := "d20 %d %s = %d vs AC %d" % [d20, TextFmt.signed(atk), total, pac]
	if not hit:
		_add_message("The %s misses you." % mname)
		_combat_panel.push_attack(
			"%s swings at you" % TextFmt.cap(mname), false, false, d20, calc, "", "")
		return

	var dn := int(data["dmg_n"])
	var dd := int(data["dmg_d"])
	var dmg := GameData.roll(dn, dd)
	_player.take_damage(dmg)
	_add_message("The %s hits you for %d damage." % [mname, dmg])
	var dline := "%dd%d %d" % [dn, dd, dmg]
	var hp_short := "%d/%d" % [maxi(0, _player.hp), _player.max_hp]
	_combat_panel.push_attack(
		"%s strikes you" % TextFmt.cap(mname), true, false, d20, calc, dline, hp_short)
	if not _player.is_alive():
		_player_dies()


func _player_dies() -> void:
	_player_alive = false
	_add_message("You die...")
	_add_message("Press F5 to start a new game.")
	_update_combat_camera_zoom()


func _add_message(text: String) -> void:
	_msg_log.append_text(text + "\n")


func _player_weapon_name() -> String:
	if _player.equipped_weapon >= 0:
		var n: String = GameData.ITEMS[_player.equipped_weapon]["name"]
		return n
	return "fists"


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
	# Colour the values that matter at a glance; HP shifts green->amber->red.
	var hp_ratio := float(maxi(0, hp)) / float(maxi(1, max_hp))
	var hp_col := "#6cc06c"
	if hp_ratio <= 0.33:
		hp_col = "#d05a5a"
	elif hp_ratio <= 0.66:
		hp_col = "#d0c060"
	var line2 := "$:[color=#d8b020]%d[/color]  HP:[color=%s]%d[/color](%d)  Pw:0(0)  AC:[color=#7fb0c8]%d[/color]  Exp:[color=#b08fd0]%d/%d[/color]  T:%d" % [
		gold, hp_col, maxi(0, hp), max_hp, ac, lvl, xp, _turn]
	if fatigued:
		line2 += "  [color=#d08040]Fatigued(-%d to hit)[/color]" % FATIGUE_PENALTY
	_status.append_text(line2)
