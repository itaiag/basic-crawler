extends Node
# Full-screen help / commands reference. Built at runtime via load() with no
# class_name (like light_overlay.gd / combat_panel.gd), so it needs no editor
# registration pass. Owns its own overlay nodes under the UI layer: a black
# backdrop, a warm radial torch-glow, a bordered stone card, and the text label.
# The content is static -- built once in setup(), then just shown/hidden.
# No shader (GL-compatibility / web / mobile safe).

var _bg: ColorRect
var _label: RichTextLabel


func setup(ui: Node, font: Font, viewport: Vector2) -> void:
	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.position = Vector2.ZERO
	_bg.size = viewport
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.visible = false
	ui.add_child(_bg)

	var card_w := 600.0
	var card_h := 660.0
	var card_pos := Vector2((viewport.x - card_w) * 0.5, (viewport.y - card_h) * 0.5)
	var card_center := card_pos + Vector2(card_w, card_h) * 0.5

	# Warm radial torch-glow, larger than the card, centered behind it.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.72, 0.36, 0.13),
		Color(0.95, 0.72, 0.36, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256

	var glow := TextureRect.new()
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var glow_size := Vector2(card_w + 360.0, card_h + 320.0)
	glow.size = glow_size
	glow.position = card_center - glow_size * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Bordered dark-stone card.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.08, 0.92)
	sb.border_color = Color(0.55, 0.42, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)

	var card := Panel.new()
	card.position = card_pos
	card.size = Vector2(card_w, card_h)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", sb)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.position = card_pos + Vector2(28, 22)
	_label.size = Vector2(card_w - 56, card_h - 44)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("normal_font", font)
	_label.add_theme_font_override("bold_font", font)
	_label.add_theme_font_size_override("normal_font_size", 18)
	_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	_label.text = _help_text()

	# Glow and card sit behind the label.
	_bg.add_child(glow)
	_bg.add_child(card)
	_bg.add_child(_label)


func open() -> void:
	_bg.visible = true


func close() -> void:
	_bg.visible = false


func is_open() -> bool:
	return _bg.visible


# Static commands reference. Mirrors the input map in game.gd._unhandled_input;
# keep the two in sync. No single-letter [x] BBCode markers (they collide with
# the bold tag).
func _help_text() -> String:
	var t := "[center][b]COMMANDS[/b][/center]\n\n"
	t += "[b]Movement[/b]\n"
	t += "  Arrows / numpad 8 2 4 6   Move (4-way)\n"
	t += "  Numpad 7 9 1 3 / 2 arrows Move diagonally\n"
	t += "  (into a monster)          Attack\n"
	t += "  (into a closed door)      Open\n\n"
	t += "[b]Actions[/b]\n"
	t += "  k + dir                   Kick (monster or door)\n"
	t += "  c + dir                   Close a door\n"
	t += "  f                         Fire ranged weapon\n"
	t += "  q                         Quaff a potion\n"
	t += "  w                         Wield a weapon\n"
	t += "  W (Shift+w)               Wear armor or shield\n"
	t += "  R                         Rest / sleep\n\n"
	t += "[b]Interface[/b]\n"
	t += "  i                         Inventory\n"
	t += "  ? / F1                    This help\n"
	t += "  Esc                       Cancel a pending prompt\n\n"
	t += "[b]Debug[/b]\n"
	t += "  F5                        New dungeon\n"
	t += "  F6                        Reveal map\n\n"
	t += "[center]Press any key to close.[/center]"
	return t
