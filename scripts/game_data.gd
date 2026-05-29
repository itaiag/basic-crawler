class_name GameData

enum Tile {
	NOTHING,
	WALL_H,
	WALL_V,
	FLOOR,
	CORRIDOR,
	DOOR_CLOSED,
	DOOR_LOCKED,
	DOOR_OPEN,
	STAIRS_DOWN,
	STAIRS_UP,
}

const CELL := Vector2i(16, 24)
const MAP_W := 80
const MAP_H := 21
const FONT_SIZE := 20
const FOV_RADIUS := 8

const COLOR_WALL := Color(0.80, 0.50, 0.20)
const COLOR_FLOOR := Color(0.42, 0.42, 0.42)
const COLOR_CORRIDOR := Color(0.62, 0.62, 0.62)
const COLOR_DOOR := Color(0.95, 0.78, 0.25)
const COLOR_STAIRS := Color.WHITE

enum MonsterKind { SNAKE, RAT, SPIDER, GOBLIN }

# Stats follow easy-leaning Basic Fantasy values. Index matches MonsterKind.
# Damage is dmg_n d dmg_d (monsters have no damage bonus). morale is the Basic
# Fantasy 2d6 score: on a morale check, a 2d6 roll *over* this value breaks the
# monster and it flees (lower = more skittish).
const MONSTERS := [
	{"name": "snake", "glyph": "S", "color": Color(0.35, 0.80, 0.35),
		"hp": 4, "ac": 13, "atk": 1, "dmg_n": 1, "dmg_d": 4, "xp": 8, "morale": 7},
	{"name": "rat", "glyph": "R", "color": Color(0.62, 0.45, 0.30),
		"hp": 3, "ac": 12, "atk": 0, "dmg_n": 1, "dmg_d": 3, "xp": 4, "morale": 5},
	{"name": "spider", "glyph": "s", "color": Color(0.85, 0.85, 0.92),
		"hp": 5, "ac": 13, "atk": 1, "dmg_n": 1, "dmg_d": 4, "xp": 10, "morale": 7},
	{"name": "goblin", "glyph": "G", "color": Color(0.60, 0.72, 0.25),
		"hp": 6, "ac": 13, "atk": 1, "dmg_n": 1, "dmg_d": 6, "xp": 12, "morale": 8},
]

const COLOR_GOLD := Color(0.95, 0.85, 0.20)
const COLOR_WEAPON := Color(0.70, 0.80, 0.85)
const COLOR_ARMOR := Color(0.72, 0.60, 0.40)

enum ItemKind {
	HEALING_POTION,
	HAND_AXE, BATTLE_AXE, GREAT_AXE,
	DAGGER, SHORTSWORD, LONGSWORD, TWO_HANDED_SWORD,
	WARHAMMER, MACE, MAUL,
	CLUB, QUARTERSTAFF, POLE_ARM, SPEAR,
	LEATHER_ARMOR, CHAIN_MAIL, PLATE_MAIL,
	SHIELD,
}

# Indexed by ItemKind; the row order must match the enum above.
const ITEMS := [
	{"name": "healing potion", "glyph": "!", "color": Color(0.50, 0.85, 0.95),
		"category": "potion", "heal_n": 1, "heal_d": 8, "heal_bonus": 2},
	{"name": "hand axe", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 6},
	{"name": "battle axe", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 8},
	{"name": "great axe", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 10, "two_handed": true},
	{"name": "dagger", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 4},
	{"name": "shortsword", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 6},
	{"name": "longsword", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 8},
	{"name": "two-handed sword", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 10, "two_handed": true},
	{"name": "warhammer", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 6},
	{"name": "mace", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 8},
	{"name": "maul", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 10, "two_handed": true},
	{"name": "club", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 4},
	{"name": "quarterstaff", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 6, "two_handed": true},
	{"name": "pole arm", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 10, "two_handed": true},
	{"name": "spear", "glyph": ")", "color": COLOR_WEAPON, "category": "weapon", "dmg_n": 1, "dmg_d": 6},
	{"name": "leather armor", "glyph": "[", "color": COLOR_ARMOR, "category": "armor", "ac": 13},
	{"name": "chain mail", "glyph": "[", "color": COLOR_ARMOR, "category": "armor", "ac": 15},
	{"name": "plate mail", "glyph": "[", "color": COLOR_ARMOR, "category": "armor", "ac": 17},
	{"name": "shield", "glyph": "[", "color": COLOR_ARMOR, "category": "shield"},
]

static func is_potion(kind: int) -> bool:
	return ITEMS[kind].get("category", "") == "potion"

static func is_weapon(kind: int) -> bool:
	return ITEMS[kind].get("category", "") == "weapon"

static func is_armor(kind: int) -> bool:
	return ITEMS[kind].get("category", "") == "armor"

static func is_shield(kind: int) -> bool:
	return ITEMS[kind].get("category", "") == "shield"

static func is_two_handed(kind: int) -> bool:
	return ITEMS[kind].get("two_handed", false)

static func get_tile_char(tile: int) -> String:
	match tile:
		Tile.WALL_H: return "-"
		Tile.WALL_V: return "|"
		Tile.FLOOR: return "."
		Tile.CORRIDOR: return "#"
		Tile.DOOR_CLOSED: return "+"
		Tile.DOOR_LOCKED: return "+"
		Tile.DOOR_OPEN: return "|"
		Tile.STAIRS_DOWN: return ">"
		Tile.STAIRS_UP: return "<"
	return " "

static func get_tile_color(tile: int) -> Color:
	match tile:
		Tile.WALL_H, Tile.WALL_V: return COLOR_WALL
		Tile.FLOOR: return COLOR_FLOOR
		Tile.CORRIDOR: return COLOR_CORRIDOR
		Tile.DOOR_CLOSED, Tile.DOOR_LOCKED, Tile.DOOR_OPEN: return COLOR_DOOR
		Tile.STAIRS_DOWN, Tile.STAIRS_UP: return COLOR_STAIRS
	return Color.BLACK

static func is_passable(tile: int) -> bool:
	return tile in [Tile.FLOOR, Tile.CORRIDOR, Tile.DOOR_OPEN,
		Tile.STAIRS_DOWN, Tile.STAIRS_UP]

static func is_transparent(tile: int) -> bool:
	return tile in [Tile.FLOOR, Tile.CORRIDOR, Tile.DOOR_OPEN,
		Tile.STAIRS_DOWN, Tile.STAIRS_UP]

static func is_wall(tile: int) -> bool:
	return tile == Tile.WALL_H or tile == Tile.WALL_V

static func is_door(tile: int) -> bool:
	return tile in [Tile.DOOR_CLOSED, Tile.DOOR_LOCKED, Tile.DOOR_OPEN]

static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * CELL.x, grid_pos.y * CELL.y)

static func roll(n: int, sides: int) -> int:
	var total := 0
	for _i in range(n):
		total += randi_range(1, sides)
	return total

# 4d6 drop-lowest gives a slightly heroic, not-too-difficult character.
static func roll_ability() -> int:
	var dice := [randi_range(1, 6), randi_range(1, 6), randi_range(1, 6), randi_range(1, 6)]
	dice.sort()
	return int(dice[1]) + int(dice[2]) + int(dice[3])

# Basic Fantasy ability score modifier table.
static func ability_mod(score: int) -> int:
	if score <= 3:
		return -3
	elif score <= 5:
		return -2
	elif score <= 8:
		return -1
	elif score <= 12:
		return 0
	elif score <= 15:
		return 1
	elif score <= 17:
		return 2
	return 3
