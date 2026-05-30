extends Node

# Floating dark-fantasy encounter card, shown only while engaged. A *structured*
# panel (not a chronological log): a pinned initiative header that never scrolls,
# then the current round's events. Detailed roll breakdowns live here; the top log
# stays narrative. Owns its own ColorRect + RichTextLabel under the UI layer.
#
# No class_name -- built at runtime and referenced by a node var (like
# light_overlay.gd), so it needs no editor registration pass.

const PANEL_W := 340
const PANEL_H := 308
const MARGIN := 12
# If a round has more events than fit, keep the most recent few (in order) so the
# initiative header is never pushed off the top.
const TURN_EVENT_LIMIT := 4

var _bg: ColorRect
var _label: RichTextLabel
var _top_h := 0
var _bottom_h := 0
# Game-provided closure returning the fight's screen-space Rect2 (it needs the live
# camera transform + monster positions, which stay in game.gd).
var _area_provider: Callable

var _encounter_active := false
var _player_has_initiative := true
var _player_initiative_roll := 0
var _monster_initiative_roll := 0
var _combat_turn := 0                   # current round within the active encounter
var _turn_events: Array[String] = []    # this round's event blocks, in order acted
var _corner := -1  # 0=TL 1=TR 2=BL 3=BR; -1 = unplaced (snap on next show)
var _pos_tween: Tween


func setup(ui: CanvasLayer, font: Font, viewport: Vector2, top_h: int, bottom_h: int, area_provider: Callable) -> void:
	_top_h = top_h
	_bottom_h = bottom_h
	_area_provider = area_provider

	_bg = ColorRect.new()
	# Slightly translucent so the player can tell map content sits behind it when
	# overlap is unavoidable; the text itself stays fully opaque and readable.
	_bg.color = Color(0.10, 0.06, 0.06, 0.88)
	_bg.position = Vector2(
		viewport.x - PANEL_W - MARGIN,
		viewport.y - bottom_h - PANEL_H - MARGIN)
	_bg.size = Vector2(PANEL_W, PANEL_H)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.visible = false
	ui.add_child(_bg)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.position = Vector2.ZERO
	_label.size = Vector2(PANEL_W, PANEL_H)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.06, 0.06, 0.88)
	style.border_color = Color(0.46, 0.22, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	_label.add_theme_stylebox_override("normal", style)
	_label.add_theme_font_override("normal_font", font)
	_label.add_theme_font_override("bold_font", font)
	_label.add_theme_font_size_override("normal_font_size", 14)
	_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_bg.add_child(_label)


# --- encounter lifecycle ---------------------------------------------------

# Start of encounter: store the initiative result for the pinned header.
func begin_encounter(player_roll: int, monster_roll: int, player_has_init: bool) -> void:
	_encounter_active = true
	_player_initiative_roll = player_roll
	_monster_initiative_roll = monster_roll
	_player_has_initiative = player_has_init
	_combat_turn = 0
	_turn_events.clear()


# End of encounter: reset logical state (the card is hidden separately).
func end_encounter() -> void:
	_encounter_active = false
	_player_has_initiative = true
	_player_initiative_roll = 0
	_monster_initiative_roll = 0
	_combat_turn = 0
	_turn_events.clear()


# New round: bump Turn N, clear last round's events.
func begin_turn() -> void:
	_combat_turn += 1
	_turn_events.clear()
	_render()


func push_attack(header: String, hit: bool, friendly: bool, d20: int, attack_line: String, damage_line: String, hp_short: String) -> void:
	_turn_events.append(_attack_block(header, hit, friendly, _nat_note(d20), attack_line, damage_line, hp_short))
	_render()


func push_morale(name: String, held: bool, roll: int, morale: int) -> void:
	_turn_events.append(_morale_block(name, held, roll, morale))
	_render()


func show_card() -> void:
	_render()


func hide_card() -> void:
	if _bg == null:
		return
	_bg.visible = false
	_turn_events.clear()
	_label.text = ""
	_corner = -1  # next engagement snaps to its chosen corner
	if _pos_tween:
		_pos_tween.kill()


# --- rendering -------------------------------------------------------------
# Split into a fixed top header (encounter + initiative) and a Current-Turn
# section replaced each round. Events append to the current turn in the order acted.

func _render() -> void:
	if _encounter_active:
		_label.text = "%s\n\n%s" % [_header(), _turn_section()]
	else:
		# Engaged but no encounter rolled yet (the rare mid-move trigger gap).
		_label.text = "[font_size=16][b]In combat[/b][/font_size]\n\n[color=#8a8a8a]Steel is drawn...[/color]"
	_bg.visible = true
	_update_placement()


# A thin graphical rule under a section heading (box-drawing line).
func _rule() -> String:
	return "[color=#6a4f4f]%s[/color]" % "─".repeat(22)


# Fixed header: the encounter's initiative result, rebuilt from stored rolls so
# attack events never push it down.
func _header() -> String:
	var win_col := "#9bbf6b" if _player_has_initiative else "#d09a6a"
	var who := "You win initiative." if _player_has_initiative else "Monsters win initiative."
	var t := "[font_size=16][b]Encounter[/b][/font_size]\n"
	t += _rule() + "\n"
	t += "[color=%s]%s[/color]\n" % [win_col, who]
	t += "[color=#9a9a9a]You: %d   Monsters: %d[/color]" % [
		_player_initiative_roll, _monster_initiative_roll]
	return t


# Current round only. Older rounds live in the top log. If the round overflows,
# the most recent events are shown.
func _turn_section() -> String:
	var t := "[font_size=16][b]Turn %d[/b][/font_size]\n" % _combat_turn
	t += _rule()
	if _turn_events.is_empty():
		t += "\n[color=#7a7a7a]...[/color]"
		return t
	var start := maxi(0, _turn_events.size() - TURN_EVENT_LIMIT)
	for i in range(start, _turn_events.size()):
		t += "\n\n" + _turn_events[i]
	return t


# --- placement -------------------------------------------------------------
# Pick the corner farthest from the current fight; only repositions when the
# chosen corner changes, so it never jitters. First placement snaps; later glide.

func _update_placement() -> void:
	if not _bg.visible:
		return
	var area: Rect2 = _area_provider.call()
	var vp := _bg.get_viewport_rect().size
	var corner := _pick_corner(area, vp)
	if corner == _corner:
		return
	var first := _corner == -1
	_corner = corner
	var target := _corner_pos(corner, vp)
	if _pos_tween:
		_pos_tween.kill()
	if first:
		_bg.position = target
	else:
		_pos_tween = create_tween()
		_pos_tween.set_trans(Tween.TRANS_SINE)
		_pos_tween.set_ease(Tween.EASE_OUT)
		_pos_tween.tween_property(_bg, "position", target, 0.18)


# Screen-space top-left for a candidate corner. All four sit strictly between the
# top message log and the bottom status bar so the panel never covers them.
func _corner_pos(corner: int, vp: Vector2) -> Vector2:
	var top := float(_top_h + MARGIN)
	var bottom := vp.y - _bottom_h - PANEL_H - MARGIN
	var left := float(MARGIN)
	var right := vp.x - PANEL_W - MARGIN
	match corner:
		0: return Vector2(left, top)      # top-left
		1: return Vector2(right, top)     # top-right
		2: return Vector2(left, bottom)   # bottom-left
		_: return Vector2(right, bottom)  # bottom-right


# Score each candidate: a non-overlapping corner always beats an overlapping one;
# ties (and the all-overlap case) break toward the greatest distance from the
# combat-area center. Pure given (area, vp) so it can be unit-checked.
func _pick_corner(area: Rect2, vp: Vector2) -> int:
	var center := area.position + area.size * 0.5
	var panel_size := Vector2(PANEL_W, PANEL_H)
	var best := 3
	var best_score := -1.0
	for corner in range(4):
		var pos := _corner_pos(corner, vp)
		var rect := Rect2(pos, panel_size)
		var dist := (pos + panel_size * 0.5).distance_to(center)
		var score := dist + (0.0 if rect.intersects(area) else 100000.0)
		if score > best_score:
			best_score = score
			best = corner
	return best


# --- event cards -----------------------------------------------------------

# One attack entry: a bold "who -> who" header with a HIT/MISS badge (and the
# target's remaining HP / NAT note), then labelled Attack and Damage lines.
# `friendly` tints the player's hits green / an enemy's hits red; misses go grey.
func _attack_block(header: String, hit: bool, friendly: bool, nat: String, attack_line: String, damage_line: String, hp_short: String) -> String:
	var result := "HIT" if hit else "MISS"
	var col := "#707070"
	if hit:
		col = "#74c274" if friendly else "#d97a7a"
	# Pad the name so the HIT/MISS badge lines up, with a guaranteed gap so they
	# never run together when the name fills the column (e.g. "...you" + "MISS").
	var t := "[b]%s[/b]  [color=%s][b]%s[/b][/color]" % [header.rpad(18), col, result]
	if hp_short != "":
		t += "  [color=#b0b0b0](%s)[/color]" % hp_short
	if nat != "":
		t += "  %s" % nat
	t += "\n[color=#8f8f8f]Attack:[/color] %s" % attack_line
	if hit and damage_line != "":
		t += "\n[color=#caa05a]Damage:[/color] %s" % damage_line
	return t


# Morale card: a 2d6 nerve test surfaced like an attack so the player sees *why* a
# monster turned and ran (it otherwise only hit the log).
func _morale_block(name: String, held: bool, roll: int, morale: int) -> String:
	var result := "HOLDS" if held else "FLEES"
	var col := "#9bd06b" if held else "#d09040"
	var t := "[b]%s[/b]  [color=%s][b]%s[/b][/color]" % [("%s morale" % name).rpad(18), col, result]
	t += "\n[color=#8f8f8f]Check:[/color] 2d6 %d vs %d" % [roll, morale]
	return t


# A natural 20 / natural 1 is surfaced for flavour only -- no crit mechanics yet.
func _nat_note(d20: int) -> String:
	if d20 == 20:
		return "[color=#e8d27a][b]NAT 20![/b][/color]"
	if d20 == 1:
		return "[color=#c06a6a][b]NAT 1[/b][/color]"
	return ""
