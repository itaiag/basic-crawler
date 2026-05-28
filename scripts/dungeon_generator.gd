class_name DungeonGenerator

const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tiles := []
var rooms: Array[Rect2i] = []

var _width := 0
var _height := 0


func generate(width: int, height: int, max_rooms: int = 15) -> void:
	tiles.clear()
	rooms.clear()
	_width = width
	_height = height

	for y in range(height):
		var row := []
		row.resize(width)
		row.fill(GameData.Tile.NOTHING)
		tiles.append(row)

	# Place non-overlapping room floors, well spaced so void lanes exist between them.
	for _i in range(max_rooms * 6):
		if rooms.size() >= max_rooms:
			break
		var rw := randi_range(6, 12)
		var rh := randi_range(4, 7)
		var rx := randi_range(2, width - rw - 2)
		var ry := randi_range(2, height - rh - 2)
		var room := Rect2i(rx, ry, rw, rh)

		var valid := true
		for existing in rooms:
			if room.grow(2).intersects(existing):
				valid = false
				break
		if valid:
			_carve_room(room)
			rooms.append(room)

	# Surround every room with a clean wall ring before any corridors are dug.
	for room in rooms:
		_build_walls(room)

	# Connect rooms in sequence with corridors routed entirely through the void.
	for i in range(1, rooms.size()):
		var prev: Rect2i = rooms[i - 1]
		var cur: Rect2i = rooms[i]
		_connect(prev, cur)

	if rooms.size() >= 1:
		var first: Rect2i = rooms[0]
		var up_pos: Vector2i = first.position + first.size / 2
		tiles[up_pos.y][up_pos.x] = GameData.Tile.STAIRS_UP
	if rooms.size() >= 2:
		var last: Rect2i = rooms.back()
		var down_pos: Vector2i = last.position + last.size / 2
		tiles[down_pos.y][down_pos.x] = GameData.Tile.STAIRS_DOWN


func get_tile(x: int, y: int) -> int:
	if tiles.is_empty() or x < 0 or y < 0 or y >= tiles.size() or x >= tiles[0].size():
		return GameData.Tile.NOTHING
	return tiles[y][x]


func set_tile(x: int, y: int, value: int) -> void:
	if x >= 0 and y >= 0 and y < tiles.size() and x < tiles[0].size():
		tiles[y][x] = value


func get_start_pos() -> Vector2i:
	if rooms.is_empty():
		return Vector2i(GameData.MAP_W / 2, GameData.MAP_H / 2)
	var first: Rect2i = rooms[0]
	return first.position + first.size / 2


func room_index_at(pos: Vector2i) -> int:
	for i in range(rooms.size()):
		var r: Rect2i = rooms[i]
		if r.has_point(pos):
			return i
	return -1


func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			tiles[y][x] = GameData.Tile.FLOOR


func _build_walls(floor_rect: Rect2i) -> void:
	var ring := floor_rect.grow(1)
	for x in range(ring.position.x, ring.end.x):
		_put_wall(x, ring.position.y, GameData.Tile.WALL_H)
		_put_wall(x, ring.end.y - 1, GameData.Tile.WALL_H)
	for y in range(ring.position.y, ring.end.y):
		_put_wall(ring.position.x, y, GameData.Tile.WALL_V)
		_put_wall(ring.end.x - 1, y, GameData.Tile.WALL_V)


func _put_wall(x: int, y: int, tile: int) -> void:
	# Corners stay as the WALL_H placed first; never overwrite floors or shared walls.
	if get_tile(x, y) == GameData.Tile.NOTHING:
		set_tile(x, y, tile)


func _connect(a: Rect2i, b: Rect2i) -> void:
	var a_exits := _room_exits(a)
	var b_exits := _room_exits(b)
	if a_exits.is_empty() or b_exits.is_empty():
		return

	var b_map := {}
	for e in b_exits:
		var entry: Array = e
		b_map[entry[0]] = entry[1]

	var came_from := {}
	var src_door := {}
	var frontier: Array[Vector2i] = []
	for e in a_exits:
		var entry: Array = e
		var exit: Vector2i = entry[0]
		if not came_from.has(exit):
			came_from[exit] = exit
			src_door[exit] = entry[1]
			frontier.append(exit)

	var found := Vector2i.ZERO
	var found_ok := false
	var head := 0
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		if b_map.has(cur):
			found = cur
			found_ok = true
			break
		for d in DIRS4:
			var step: Vector2i = d
			var nxt: Vector2i = cur + step
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= _width or nxt.y >= _height:
				continue
			if came_from.has(nxt):
				continue
			var t: int = get_tile(nxt.x, nxt.y)
			if t == GameData.Tile.NOTHING or t == GameData.Tile.CORRIDOR:
				came_from[nxt] = cur
				src_door[nxt] = src_door[cur]
				frontier.append(nxt)

	if not found_ok:
		return

	var node: Vector2i = found
	while true:
		if get_tile(node.x, node.y) == GameData.Tile.NOTHING:
			set_tile(node.x, node.y, GameData.Tile.CORRIDOR)
		var prev: Vector2i = came_from[node]
		if prev == node:
			break
		node = prev

	var a_door: Vector2i = src_door[found]
	var b_door: Vector2i = b_map[found]
	set_tile(a_door.x, a_door.y, _random_door())
	set_tile(b_door.x, b_door.y, _random_door())


func _room_exits(floor_rect: Rect2i) -> Array:
	var ring := floor_rect.grow(1)
	var result: Array = []
	for x in range(ring.position.x, ring.end.x):
		_try_exit(Vector2i(x, ring.position.y), Vector2i(0, -1), result)
		_try_exit(Vector2i(x, ring.end.y - 1), Vector2i(0, 1), result)
	for y in range(ring.position.y, ring.end.y):
		_try_exit(Vector2i(ring.position.x, y), Vector2i(-1, 0), result)
		_try_exit(Vector2i(ring.end.x - 1, y), Vector2i(1, 0), result)
	return result


func _try_exit(wall_cell: Vector2i, normal: Vector2i, result: Array) -> void:
	var wall: int = get_tile(wall_cell.x, wall_cell.y)
	if wall != GameData.Tile.WALL_H and wall != GameData.Tile.WALL_V:
		return
	var inside: Vector2i = wall_cell - normal
	var outside: Vector2i = wall_cell + normal
	if get_tile(inside.x, inside.y) != GameData.Tile.FLOOR:
		return
	if get_tile(outside.x, outside.y) != GameData.Tile.NOTHING:
		return
	result.append([outside, wall_cell])


func _random_door() -> int:
	var r := randf()
	if r < 0.30:
		return GameData.Tile.DOOR_LOCKED
	elif r < 0.75:
		return GameData.Tile.DOOR_CLOSED
	return GameData.Tile.DOOR_OPEN
