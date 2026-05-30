extends Node2D

signal finished_moving

var grid_pos := Vector2i.ZERO
var is_moving := false

var strength := 10
var dexterity := 10
var constitution := 10
var intelligence := 10
var wisdom := 10
var charisma := 10

var hp := 8
var max_hp := 8
var xp := 0
var level := 1
var gold := 0
var inventory: Array = []
var fatigued := false

const HIT_DIE := 8
const BASE_AC := 11
const SHIELD_AC := 1
const UNARMED_DMG_N := 1
const UNARMED_DMG_D := 2

var equipped_weapon := -1
var equipped_armor := -1
var equipped_shield := -1

const MOVE_DURATION := 0.1

var _font: Font
var _tween: Tween


func _ready() -> void:
	_font = preload("res://resources/mono_font.tres")


func _draw() -> void:
	var cw := float(GameData.CELL.x)
	var ch := float(GameData.CELL.y)
	var center := Vector2(cw * 0.5, ch * 0.5)
	# Soft warm torch halo: a few concentric circles with falling alpha fake a
	# smooth radial glow without a texture (GL-compat / web safe).
	var warm := Color(1.0, 0.82, 0.5)
	draw_circle(center, 26.0, Color(warm, 0.05))
	draw_circle(center, 19.0, Color(warm, 0.06))
	draw_circle(center, 13.0, Color(warm, 0.08))
	draw_circle(center, 9.0, Color(warm, 0.10))
	# Grounding shadow peeking out below the token.
	draw_circle(center + Vector2(0, 4.0), 6.0, Color(0, 0, 0, 0.30))
	draw_circle(center, 7.5, GameData.COLOR_TOKEN_BG)
	var fs := GameData.FONT_SIZE
	var baseline := (ch - (_font.get_ascent(fs) + _font.get_descent(fs))) * 0.5 + _font.get_ascent(fs)
	draw_string(_font, Vector2(0, baseline), "@", HORIZONTAL_ALIGNMENT_CENTER,
		cw, fs, Color.WHITE)


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


func take_damage(amount: int) -> void:
	hp -= amount


func is_alive() -> bool:
	return hp > 0


func roll_new_character() -> void:
	strength = GameData.roll_ability()
	dexterity = GameData.roll_ability()
	constitution = GameData.roll_ability()
	intelligence = GameData.roll_ability()
	wisdom = GameData.roll_ability()
	charisma = GameData.roll_ability()
	level = 1
	xp = 0
	gold = 0
	inventory = [
		GameData.ItemKind.LONGSWORD,
		GameData.ItemKind.LEATHER_ARMOR,
		GameData.ItemKind.SHIELD,
	]
	equipped_weapon = GameData.ItemKind.LONGSWORD
	equipped_armor = GameData.ItemKind.LEATHER_ARMOR
	equipped_shield = GameData.ItemKind.SHIELD
	fatigued = false
	max_hp = maxi(1, HIT_DIE + con_mod())
	hp = max_hp


func str_mod() -> int:
	return GameData.ability_mod(strength)


func dex_mod() -> int:
	return GameData.ability_mod(dexterity)


func con_mod() -> int:
	return GameData.ability_mod(constitution)


func wis_mod() -> int:
	return GameData.ability_mod(wisdom)


func armor_class() -> int:
	var base := BASE_AC
	if equipped_armor >= 0:
		base = int(GameData.ITEMS[equipped_armor]["ac"])
	var shield := SHIELD_AC if equipped_shield >= 0 else 0
	return base + shield + dex_mod()


func weapon_dmg_n() -> int:
	if equipped_weapon >= 0:
		return int(GameData.ITEMS[equipped_weapon]["dmg_n"])
	return UNARMED_DMG_N


func weapon_dmg_d() -> int:
	if equipped_weapon >= 0:
		return int(GameData.ITEMS[equipped_weapon]["dmg_d"])
	return UNARMED_DMG_D


func melee_attack_bonus() -> int:
	# Fighter base attack roughly equals level, plus Strength.
	return level + str_mod()


func damage_bonus() -> int:
	return str_mod()


func gain_level_hp() -> int:
	return maxi(1, GameData.roll(1, HIT_DIE) + con_mod())


func add_gold(amount: int) -> void:
	gold += amount


func add_item(kind: int) -> void:
	inventory.append(kind)


func remove_item(kind: int) -> void:
	inventory.erase(kind)


func has_item(kind: int) -> bool:
	return inventory.has(kind)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
