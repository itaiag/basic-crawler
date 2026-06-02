extends SceneTree
# Headless logic check: DungeonPopulator never places a monster or item on a pillar,
# stairs, door, or an already-occupied cell, and placements never collide with each
# other. Pure -- no scene; generates many dungeons and inspects the returned data.
#
# Run:
#   Godot --headless --path <project> --script res://tests/populator_test.gd
# Pass: exit 0 + "POPULATOR TEST PASSED".

var _failures: Array[String] = []


func _init() -> void:
	for run in range(40):
		seed(70000 + run)
		_check_one_dungeon(run)
		if not _failures.is_empty():
			break
	_finish()


func _check_one_dungeon(run: int) -> void:
	var d := DungeonGenerator.new()
	d.generate(GameData.MAP_W, GameData.MAP_H)

	# Seed some occupancy on real floor cells so the avoidance path is exercised.
	var occupancy: Dictionary = {}
	for ri in range(d.rooms.size()):
		var room: Rect2i = d.rooms[ri]
		var c := Vector2i(room.position.x, room.position.y)
		if d.get_tile(c.x, c.y) == GameData.Tile.FLOOR:
			occupancy[c] = true

	var monsters: Array[Dictionary] = DungeonPopulator.roll_monsters(d, occupancy)
	var monster_cells: Dictionary = {}
	for m in monsters:
		var cell: Vector2i = m["cell"]
		_assert_clean(d, cell, occupancy, "monster", run)
		if monster_cells.has(cell):
			_fail("run %d: two monsters share cell %s" % [run, cell])
		monster_cells[cell] = true

	# Items roll after monsters: pass monsters as occupancy so items avoid them.
	var item_occ: Dictionary = occupancy.duplicate()
	item_occ.merge(monster_cells)
	var items: Dictionary = DungeonPopulator.roll_items(d, item_occ)
	for cell in items.keys():
		var c: Vector2i = cell
		_assert_clean(d, c, occupancy, "item", run)
		if monster_cells.has(c):
			_fail("run %d: item placed on a monster at %s" % [run, c])


# A placement cell must be plain FLOOR (which excludes pillar/stairs/door/wall/void)
# and must not sit on a pre-seeded occupant.
func _assert_clean(d: DungeonGenerator, cell: Vector2i, occupancy: Dictionary, what: String, run: int) -> void:
	var tile: int = d.get_tile(cell.x, cell.y)
	if tile != GameData.Tile.FLOOR:
		_fail("run %d: %s placed on non-floor tile %d at %s" % [run, what, tile, cell])
	if GameData.is_pillar(tile):
		_fail("run %d: %s placed on a pillar at %s" % [run, what, cell])
	if GameData.is_door(tile):
		_fail("run %d: %s placed on a door at %s" % [run, what, cell])
	if tile == GameData.Tile.STAIRS_DOWN or tile == GameData.Tile.STAIRS_UP:
		_fail("run %d: %s placed on stairs at %s" % [run, what, cell])
	if occupancy.has(cell):
		_fail("run %d: %s placed on an occupied cell at %s" % [run, what, cell])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("POPULATOR TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("POPULATOR TEST FAILURE: " + f)
		print("POPULATOR TEST FAILED (%d failure(s))" % _failures.size())
		quit(1)
