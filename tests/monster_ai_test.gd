extends SceneTree
# Headless logic check: MonsterAI chase/flee never steps into a pillar, wall, or
# occupied/player cell. Pure -- no scene; builds synthetic grids plus a fuzz sweep
# over a real generated dungeon. (See CLAUDE.md "Throwaway logic checks", but this
# one is kept in tests/ as a regression guard for monster_ai.gd.)
#
# Run:
#   Godot --headless --path <project> --script res://tests/monster_ai_test.gd
# Pass: exit 0 + "MONSTER AI TEST PASSED".

var _failures: Array[String] = []


func _init() -> void:
	_test_targeted()
	_test_fuzz()
	_finish()


# Build a w*h grid filled with `fill`, then poke individual cells.
func _grid(w: int, h: int, fill: int) -> DungeonGenerator:
	var d := DungeonGenerator.new()
	var t := []
	for _y in range(h):
		var row := []
		row.resize(w)
		row.fill(fill)
		t.append(row)
	d.tiles = t
	return d


# Monster at (2,2), player two cells along +x so chase wants to step to (3,2) and
# flee (mirrored) also lands there from the opposite side. Each blocker must veto it.
func _test_targeted() -> void:
	var occ_empty: Dictionary = {}

	# Positive control: open floor -> chase steps toward the player.
	var open := _grid(5, 5, GameData.Tile.FLOOR)
	var step := MonsterAI.chase_step(Vector2i(2, 2), Vector2i(4, 2) - Vector2i(2, 2), open, occ_empty, Vector2i(4, 2))
	if step != Vector2i(1, 0):
		_fail("chase into open floor should step (1,0), got %s" % step)

	# Each blocker on the only sensible step cell (3,2) must force ZERO (no y option
	# exists because the player is on the same row).
	for blocker in [GameData.Tile.PILLAR, GameData.Tile.WALL_H, GameData.Tile.WALL_V]:
		var d := _grid(5, 5, GameData.Tile.FLOOR)
		d.set_tile(3, 2, blocker)
		var s := MonsterAI.chase_step(Vector2i(2, 2), Vector2i(2, 0), d, occ_empty, Vector2i(4, 2))
		if s != Vector2i.ZERO:
			_fail("chase must not enter tile %d at (3,2); got step %s" % [blocker, s])
		if MonsterAI.can_enter(Vector2i(3, 2), d, occ_empty, Vector2i(4, 2)):
			_fail("can_enter should reject tile %d at (3,2)" % blocker)

	# Occupied cell blocks the step.
	var docc := _grid(5, 5, GameData.Tile.FLOOR)
	var occ: Dictionary = {Vector2i(3, 2): true}
	var so := MonsterAI.chase_step(Vector2i(2, 2), Vector2i(2, 0), docc, occ, Vector2i(4, 2))
	if so != Vector2i.ZERO:
		_fail("chase must not enter an occupied cell; got %s" % so)

	# Player cell is never entered.
	if MonsterAI.can_enter(Vector2i(4, 2), open, occ_empty, Vector2i(4, 2)):
		_fail("can_enter should reject the player's own cell")

	# Flee mirror: player on the -x side, monster steps away to (3,2). Pillar vetoes.
	var dflee := _grid(5, 5, GameData.Tile.FLOOR)
	dflee.set_tile(3, 2, GameData.Tile.PILLAR)
	var fs := MonsterAI.flee_step(Vector2i(2, 2), Vector2i(0, 2) - Vector2i(2, 2), dflee, occ_empty, Vector2i(0, 2))
	if fs != Vector2i.ZERO:
		_fail("flee must not enter a pillar; got %s" % fs)


# Sweep many random monster/player/occupancy combos on a real dungeon: whatever step
# chase/flee returns, its destination must satisfy every entry constraint.
func _test_fuzz() -> void:
	seed(20260530)
	var d := DungeonGenerator.new()
	d.generate(GameData.MAP_W, GameData.MAP_H)

	var floors: Array[Vector2i] = []
	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			if d.get_tile(x, y) == GameData.Tile.FLOOR:
				floors.append(Vector2i(x, y))
	if floors.size() < 4:
		_fail("generated dungeon had too few floor cells to fuzz (%d)" % floors.size())
		return

	for _i in range(3000):
		var from: Vector2i = floors[randi() % floors.size()]
		var player: Vector2i = floors[randi() % floors.size()]
		var occ: Dictionary = {}
		for _o in range(randi_range(0, 3)):
			occ[floors[randi() % floors.size()]] = true
		var to_player := player - from
		for step in [MonsterAI.chase_step(from, to_player, d, occ, player),
				MonsterAI.flee_step(from, to_player, d, occ, player)]:
			if step == Vector2i.ZERO:
				continue
			var dest: Vector2i = from + step
			if not GameData.is_passable(d.get_tile(dest.x, dest.y)):
				_fail("step into non-passable cell %s (tile %d)" % [dest, d.get_tile(dest.x, dest.y)])
				return
			if occ.has(dest):
				_fail("step into occupied cell %s" % dest)
				return
			if dest == player:
				_fail("step into player cell %s" % dest)
				return


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("MONSTER AI TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("MONSTER AI TEST FAILURE: " + f)
		print("MONSTER AI TEST FAILED (%d failure(s))" % _failures.size())
		quit(1)
