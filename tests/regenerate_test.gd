extends SceneTree
# Headless logic check: regenerating the dungeon clears all encounter/combat-panel
# state, so no stale initiative or turn events leak into the new level. Drives the
# real game scene like smoke_test.gd.
#
# Run:
#   Godot --headless --path <project> --script res://tests/regenerate_test.gd
# Pass: exit 0 + "REGENERATE TEST PASSED".

const GAME_SCENE := "res://scenes/game.tscn"

var _game: Node
var _failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	_game = load(GAME_SCENE).instantiate()
	get_root().add_child(_game)
	await process_frame

	if _game._player == null or _game._dungeon == null:
		_fail("scene did not initialise (player or dungeon is null)")
		_finish()
		return

	_game._begin_play()
	_game._clear_monsters()

	# Force an active encounter with some panel content.
	_game._begin_encounter()
	_game._combat_panel.begin_turn()
	_game._combat_panel.push_attack("You -> rat", true, true, 15, "d20 15 = 15 vs AC 12 -> HIT", "1d6 3 = 3", "rat 1/4")

	if not _game._encounter_active:
		_fail("precondition failed: encounter not active after _begin_encounter")
	if not _game._combat_panel._encounter_active:
		_fail("precondition failed: panel encounter not active")
	if _game._combat_panel._turn_events.is_empty():
		_fail("precondition failed: panel has no turn events to clear")

	_game._regenerate()

	# Game-side encounter state cleared.
	if _game._encounter_active:
		_fail("_encounter_active should be false after regenerate")
	if _game._player_initiative_roll != 0:
		_fail("player initiative roll should reset to 0 (got %d)" % _game._player_initiative_roll)
	if _game._monster_initiative_roll != 0:
		_fail("monster initiative roll should reset to 0 (got %d)" % _game._monster_initiative_roll)

	# Panel state cleared and hidden.
	var p: Node = _game._combat_panel
	if p._encounter_active:
		_fail("panel _encounter_active should be false after regenerate")
	if p._combat_turn != 0:
		_fail("panel _combat_turn should reset to 0 (got %d)" % p._combat_turn)
	if not p._turn_events.is_empty():
		_fail("panel _turn_events should be cleared after regenerate")
	if p._bg != null and p._bg.visible:
		_fail("panel card should be hidden after regenerate")

	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	var ok := _failures.is_empty()
	if _game != null:
		_game.free()
	if ok:
		print("REGENERATE TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("REGENERATE TEST FAILURE: " + f)
		print("REGENERATE TEST FAILED (%d failure(s))" % _failures.size())
		quit(1)
