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
