extends SceneTree
# Headless gameplay smoke test (not part of the shipped game).
#
# Instantiates the real game scene and drives a single move and a single attack
# through the actual turn/combat code, then reports whether the run completed
# without failing an assertion. It is a guard against runtime errors in code
# paths that a plain `--quit-after` boot never executes (movement, combat).
#
# Run:
#   Godot --headless --path <project> --script res://tests/smoke_test.gd
# Pass criteria: process exit code 0, the line "SMOKE TEST PASSED" in output,
# and no "SCRIPT ERROR" lines.

const GAME_SCENE := "res://scenes/game.tscn"

var _game: Node
var _failures: Array[String] = []


func _init() -> void:
	# Run as a coroutine: the scene's nodes only finish _ready after the main
	# loop processes a frame, so we add the scene, yield, then drive it.
	_run()


func _run() -> void:
	_game = load(GAME_SCENE).instantiate()
	get_root().add_child(_game)
	await process_frame

	if _game._player == null or _game._dungeon == null:
		_fail("scene did not initialise (player or dungeon is null)")
		_finish()
		return

	# Leave the character-creation screen so play actions behave normally.
	_game._begin_play()
	# Deterministic setup: drop the randomly spawned monsters.
	_game._clear_monsters()

	_test_move()
	_test_attack()
	_finish()


func _test_move() -> void:
	var p: Vector2i = _game._player.grid_pos
	var dir := _passable_dir(p)
	if dir == Vector2i.ZERO:
		_fail("no passable neighbour to move into from the start cell")
		return
	_game._try_move(dir)
	var after: Vector2i = _game._player.grid_pos
	if after != p + dir:
		_fail("player did not move (was %s, now %s, expected %s)" % [p, after, p + dir])


func _test_attack() -> void:
	var p: Vector2i = _game._player.grid_pos
	var dir := _passable_dir(p)
	if dir == Vector2i.ZERO:
		_fail("no passable neighbour to place the target monster")
		return
	var cell: Vector2i = p + dir
	_game._add_monster(GameData.MonsterKind.SNAKE, cell)
	_game._update_fov()
	# Bumping into the monster routes through _do_move_action -> _attack_monster.
	_game._try_move(dir)
	var log_text: String = _game._msg_log.get_parsed_text()
	if not log_text.to_lower().contains("snake"):
		_fail("attack produced no combat message in the log")
	if not _game._player_alive:
		_fail("player unexpectedly died during the smoke test")


# First orthogonal direction whose neighbour is walkable and unoccupied.
func _passable_dir(from: Vector2i) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var c: Vector2i = from + d
		if c == _game._player.grid_pos or _game._monster_at.has(c):
			continue
		if GameData.is_passable(_game._dungeon.get_tile(c.x, c.y)):
			return d
	return Vector2i.ZERO


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	var ok := _failures.is_empty()
	# Free the scene so we don't trip end-of-run "resources still in use" errors.
	if _game != null:
		_game.free()
	if ok:
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("SMOKE TEST FAILURE: " + f)
		print("SMOKE TEST FAILED (%d failure(s))" % _failures.size())
		quit(1)
