class_name DungeonGenerator

const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tiles := []
var rooms: Array[Rect2i] = []

var _width := 0
var _height := 0


func generate(width: int, height: int, max_rooms: int = 8) -> void:
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
		var rw := randi_range(5, 11)
		var rh := randi_range(3, 6)
		var rx := randi_range(2, width - rw - 2)
		var ry := randi_range(2, height - rh - 2)
		var room := Rect2i(rx, ry, rw, rh)

		var valid := true
		for existing in rooms:
			# grow(3) keeps at least one empty cell between any two wall rings,
			# which prevents adjacent walls rendering as a comb of connectors.
			if room.grow(3).intersects(existing):
				valid = false
				break
		if valid:
			_carve_room(room)
			rooms.append(room)

	# Surround every room with a clean wall ring before any corridors are dug.
	for room in rooms:
		_build_walls(room)

	# Connect rooms with a minimum spanning tree (nearest-neighbour) so corridors
	# stay short and there are no redundant parallel runs across the map.
	_connect_mst()
	# Add some mess on top of the guaranteed-connected backbone.
	_add_extra_connections()
	_add_dead_ends()

	if rooms.size() >= 1:
		var first: Rect2i = rooms[0]
		var up_pos: Vector2i = first.position + first.size / 2
		tiles[up_pos.y][up_pos.x] = GameData.Tile.STAIRS_UP
	if rooms.size() >= 2:
		var last: Rect2i = rooms.back()
		var down_pos: Vector2i = last.position + last.size / 2
		tiles[down_pos.y][down_pos.x] = GameData.Tile.STAIRS_DOWN

	# Pillars last: candidates must be FLOOR, which naturally excludes the stairs
	# cells (and therefore the player start) placed just above.
	_add_pillars()


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


func _room_center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


func _connect_mst() -> void:
	if rooms.size() < 2:
		return
	var connected: Array[int] = [0]
	var remaining: Array[int] = []
	for i in range(1, rooms.size()):
		remaining.append(i)

	while not remaining.is_empty():
		var best_c := -1
		var best_r := -1
		var best_d := INF
		for ci in connected:
			var c_idx: int = ci
			var ca: Vector2i = _room_center(rooms[c_idx])
			for ri in remaining:
				var r_idx: int = ri
				var cb: Vector2i = _room_center(rooms[r_idx])
				var dx := float(ca.x - cb.x)
				var dy := float(ca.y - cb.y)
				var d := dx * dx + dy * dy
				if d < best_d:
					best_d = d
					best_c = c_idx
					best_r = r_idx
		if best_r == -1:
			break
		var ra: Rect2i = rooms[best_c]
		var rb: Rect2i = rooms[best_r]
		_connect(ra, rb)
		connected.append(best_r)
		remaining.erase(best_r)


func _add_extra_connections() -> void:
	# A couple of redundant links create loops and corridors that cross.
	if rooms.size() < 3:
		return
	var extra := randi_range(1, 3)
	var tries := 0
	while extra > 0 and tries < 40:
		tries += 1
		var i := randi() % rooms.size()
		var j := randi() % rooms.size()
		if i == j:
			continue
		var ra: Rect2i = rooms[i]
		var rb: Rect2i = rooms[j]
		_connect(ra, rb)
		extra -= 1


func _add_dead_ends() -> void:
	var cells := _collect_corridor_cells()
	if cells.is_empty():
		return
	var count := randi_range(3, 6)
	for _k in range(count):
		var start: Vector2i = cells[randi() % cells.size()]
		_carve_dead_end(start)


func _carve_dead_end(start: Vector2i) -> void:
	# Wander through the void from an existing corridor; stop at a dead end and
	# never breach a room (only carve empty space, pass through other corridors).
	var pos := start
	var length := randi_range(3, 9)
	var dir: Vector2i = DIRS4[randi() % DIRS4.size()]
	for _s in range(length):
		if randf() < 0.35:
			dir = DIRS4[randi() % DIRS4.size()]
		var nxt: Vector2i = pos + dir
		if nxt.x < 1 or nxt.y < 1 or nxt.x >= _width - 1 or nxt.y >= _height - 1:
			break
		var t: int = get_tile(nxt.x, nxt.y)
		if t == GameData.Tile.NOTHING:
			set_tile(nxt.x, nxt.y, GameData.Tile.CORRIDOR)
			pos = nxt
		elif t == GameData.Tile.CORRIDOR:
			pos = nxt
		else:
			break


func _collect_corridor_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(_height):
		for x in range(_width):
			if get_tile(x, y) == GameData.Tile.CORRIDOR:
				cells.append(Vector2i(x, y))
	return cells


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
		var dirs := DIRS4.duplicate()
		dirs.shuffle()
		for d in dirs:
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


# --- Pillars -------------------------------------------------------------------
# Sparse, symmetric stone columns inside larger rooms. Real blocking features:
# not passable, not transparent (see GameData), placed only on FLOOR cells.

func _add_pillars() -> void:
	for room in rooms:
		_maybe_add_pillars(room)


func _maybe_add_pillars(room: Rect2i) -> void:
	# room is the FLOOR-only interior rect. Only medium/large rooms qualify.
	if room.size.x < 5 or room.size.y < 5:
		return
	if randf() > 0.30:  # ~30% of qualifying rooms get pillars (sparse overall)
		return
	var candidates := _pillar_candidates(room)
	# Bail on the whole (symmetric) set if any spot is unusable -- keeps it tidy.
	for c in candidates:
		if not _pillar_cell_ok(c):
			return
	if not _room_connected_without(room, candidates):
		return
	for c in candidates:
		set_tile(c.x, c.y, GameData.Tile.PILLAR)


func _pillar_candidates(room: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pos := room.position
	var iw := room.size.x
	var ih := room.size.y
	var cx := pos.x + iw / 2
	var cy := pos.y + ih / 2
	var big := iw >= 7 and ih >= 5
	var choice := randi() % (3 if big else 2)
	if big and choice == 2:
		# 4 inset corners (leaves the centre and edges open).
		out.append(Vector2i(pos.x + 1, pos.y + 1))
		out.append(Vector2i(pos.x + iw - 2, pos.y + 1))
		out.append(Vector2i(pos.x + 1, pos.y + ih - 2))
		out.append(Vector2i(pos.x + iw - 2, pos.y + ih - 2))
	elif choice == 1:
		# 2 symmetric pillars along the longer axis.
		if iw >= ih:
			out.append(Vector2i(pos.x + 1, cy))
			out.append(Vector2i(pos.x + iw - 2, cy))
		else:
			out.append(Vector2i(cx, pos.y + 1))
			out.append(Vector2i(cx, pos.y + ih - 2))
	else:
		# Single central pillar.
		out.append(Vector2i(cx, cy))
	return out


func _pillar_cell_ok(c: Vector2i) -> bool:
	# Must be plain floor (so never on stairs / start), and not hugging a door.
	if get_tile(c.x, c.y) != GameData.Tile.FLOOR:
		return false
	for d in DIRS4:
		var dir: Vector2i = d
		var nb: Vector2i = c + dir
		if GameData.is_door(get_tile(nb.x, nb.y)):
			return false
	return true


func _room_connected_without(room: Rect2i, pillars: Array[Vector2i]) -> bool:
	# Flood-fill the room's floor with the pillars removed; every floor cell must
	# stay reachable so a room is never split or sealed off from its doors.
	var blocked := {}
	for p in pillars:
		blocked[p] = true
	var cells: Array[Vector2i] = []
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			if get_tile(x, y) == GameData.Tile.FLOOR and not blocked.has(cell):
				cells.append(cell)
	if cells.is_empty():
		return false
	var seen := {}
	var q: Array[Vector2i] = [cells[0]]
	seen[cells[0]] = true
	while not q.is_empty():
		var cur: Vector2i = q.pop_back()
		for d in DIRS4:
			var dir: Vector2i = d
			var nb: Vector2i = cur + dir
			if seen.has(nb) or blocked.has(nb):
				continue
			if get_tile(nb.x, nb.y) == GameData.Tile.FLOOR:
				seen[nb] = true
				q.append(nb)
	for cell in cells:
		if not seen.has(cell):
			return false
	return true
