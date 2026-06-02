extends SceneTree
# Headless logic check for combat_panel.gd: across begin_encounter / begin_turn /
# push_attack, the stored initiative stays fixed (rebuilt header, never re-rolled)
# and each turn's events stay isolated to that turn. The panel is built at runtime
# (no class_name) so we load() it like game.gd does.
#
# Run:
#   Godot --headless --path <project> --script res://tests/combat_panel_test.gd
# Pass: exit 0 + "COMBAT PANEL TEST PASSED".

var _failures: Array[String] = []
var _panel: Node
var _ui: CanvasLayer


func _init() -> void:
	_run()


func _run() -> void:
	_ui = CanvasLayer.new()
	get_root().add_child(_ui)
	_panel = load("res://scripts/combat_panel.gd").new()
	get_root().add_child(_panel)
	await process_frame

	var font: Font = load("res://resources/mono_font.tres")
	# area_provider is only used for corner placement; a fixed rect is fine here.
	var area := func() -> Rect2: return Rect2(0, 0, 10, 10)
	_panel.setup(_ui, font, Vector2(1280, 720), 40, 40, area)

	# Initiative recorded once.
	_panel.begin_encounter(5, 3, true)
	_expect(_panel._encounter_active, "encounter should be active after begin_encounter")
	_expect_eq(_panel._player_initiative_roll, 5, "player initiative roll")
	_expect_eq(_panel._monster_initiative_roll, 3, "monster initiative roll")
	_expect(_panel._player_has_initiative, "player should hold initiative")
	_expect_eq(_panel._combat_turn, 0, "combat turn before first begin_turn")
	_expect(_panel._turn_events.is_empty(), "no events before any turn")

	# Turn 1 with two attack events.
	_panel.begin_turn()
	_expect_eq(_panel._combat_turn, 1, "combat turn after first begin_turn")
	_panel.push_attack("You -> snake", true, true, 14, "d20 14 = 14 vs AC 12 -> HIT", "1d6 4 = 4", "snake 3/7")
	_panel.push_attack("snake -> you", false, false, 7, "d20 7 = 7 vs AC 13 -> MISS", "", "")
	_expect_eq(_panel._turn_events.size(), 2, "turn 1 should hold two events")

	# Initiative is untouched by turns/attacks.
	_expect_eq(_panel._player_initiative_roll, 5, "player initiative unchanged after turn 1")
	_expect_eq(_panel._monster_initiative_roll, 3, "monster initiative unchanged after turn 1")
	_expect(_panel._label.text.contains("You: 5") and _panel._label.text.contains("Monsters: 3"),
		"header should display the stored initiative rolls")

	# Turn 2 starts clean: previous turn's events are cleared, initiative still fixed.
	_panel.begin_turn()
	_expect_eq(_panel._combat_turn, 2, "combat turn after second begin_turn")
	_expect(_panel._turn_events.is_empty(), "turn 2 should start with no events")
	_panel.push_attack("You -> snake", true, true, 20, "d20 20 = 20 vs AC 12 -> HIT", "1d6 5 = 5", "snake 0/7")
	_expect_eq(_panel._turn_events.size(), 1, "turn 2 should hold one event")
	_expect_eq(_panel._player_initiative_roll, 5, "player initiative unchanged after turn 2")
	_expect_eq(_panel._monster_initiative_roll, 3, "monster initiative unchanged after turn 2")

	# end_encounter resets the logical state.
	_panel.end_encounter()
	_expect(not _panel._encounter_active, "encounter inactive after end_encounter")
	_expect_eq(_panel._combat_turn, 0, "combat turn reset after end_encounter")
	_expect(_panel._turn_events.is_empty(), "events cleared after end_encounter")

	_finish()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _expect_eq(got, want, msg: String) -> void:
	if got != want:
		_failures.append("%s: expected %s, got %s" % [msg, want, got])


func _finish() -> void:
	var ok := _failures.is_empty()
	if _panel != null:
		_panel.free()
	if _ui != null:
		_ui.free()
	if ok:
		print("COMBAT PANEL TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("COMBAT PANEL TEST FAILURE: " + f)
		print("COMBAT PANEL TEST FAILED (%d failure(s))" % _failures.size())
		quit(1)
