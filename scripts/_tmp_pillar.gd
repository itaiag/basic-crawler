extends SceneTree

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _fail: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	var pillar_total := 0
	var rooms_with := 0
	var rooms_total := 0
	for _iter in range(40):
		var dg := DungeonGenerator.new()
		dg.generate(GameData.MAP_W, GameData.MAP_H)
		rooms_total += dg.rooms.size()
		for ri in range(dg.rooms.size()):
			var room: Rect2i = dg.rooms[ri]
			var has := false
			for y in range(room.position.y, room.end.y):
				for x in range(room.position.x, room.end.x):
					if dg.get_tile(x, y) == GameData.Tile.PILLAR:
						has = true
			if has:
				rooms_with += 1
			if not _room_ok(dg, room):
				_fail.append("room disconnected by pillars")
		for y in range(GameData.MAP_H):
			for x in range(GameData.MAP_W):
				if dg.get_tile(x, y) != GameData.Tile.PILLAR:
					continue
				pillar_total += 1
				var cell := Vector2i(x, y)
				var inside := false
				for r in dg.rooms:
					if r.has_point(cell):
						inside = true
						break
				if not inside:
					_fail.append("pillar outside any room at %s" % cell)
				for d in DIRS:
					var nb: Vector2i = cell + d
					if GameData.is_door(dg.get_tile(nb.x, nb.y)):
						_fail.append("pillar adjacent to door at %s" % cell)

	if GameData.is_passable(GameData.Tile.PILLAR):
		_fail.append("pillar is passable")
	if GameData.is_transparent(GameData.Tile.PILLAR):
		_fail.append("pillar is transparent (would not block FOV)")
	if pillar_total == 0:
		_fail.append("no pillars generated across 40 dungeons")

	# Live game: monsters / items / player must never sit on a pillar.
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(game)
	await process_frame
	var pp: Vector2i = game._player.grid_pos
	if game._dungeon.get_tile(pp.x, pp.y) == GameData.Tile.PILLAR:
		_fail.append("player started on a pillar")
	for k in game._monster_at.keys():
		var c: Vector2i = k
		if game._dungeon.get_tile(c.x, c.y) == GameData.Tile.PILLAR:
			_fail.append("monster on a pillar at %s" % c)
	for k in game._items_at.keys():
		var c: Vector2i = k
		if game._dungeon.get_tile(c.x, c.y) == GameData.Tile.PILLAR:
			_fail.append("item on a pillar at %s" % c)
	game.free()

	print("pillars across 40 maps: %d ; rooms with pillars: %d / %d" %
		[pillar_total, rooms_with, rooms_total])
	_finish()


func _room_ok(dg: DungeonGenerator, room: Rect2i) -> bool:
	var cells: Array[Vector2i] = []
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if dg.get_tile(x, y) == GameData.Tile.FLOOR:
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return true
	var seen := {}
	var q: Array[Vector2i] = [cells[0]]
	seen[cells[0]] = true
	while not q.is_empty():
		var cur: Vector2i = q.pop_back()
		for d in DIRS:
			var nb: Vector2i = cur + d
			if seen.has(nb):
				continue
			if dg.get_tile(nb.x, nb.y) == GameData.Tile.FLOOR:
				seen[nb] = true
				q.append(nb)
	for cell in cells:
		if not seen.has(cell):
			return false
	return true


func _finish() -> void:
	if _fail.is_empty():
		print("PILLAR TEST PASSED")
		quit(0)
	else:
		for f in _fail:
			printerr("PILLAR TEST FAILURE: " + f)
		print("PILLAR TEST FAILED")
		quit(1)
