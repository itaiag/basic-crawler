extends Node2D
## World-space torchlight overlay. Draws a per-cell darkening pass over the
## currently-visible cells so light pools around the player and falls off into
## shadow, instead of the binary full-bright / dim look. Kept as a separate cheap
## node (it only iterates `visible_cells`, a few hundred rects) so the heavy
## full-map tile pass in dungeon_renderer.gd is untouched. No class_name: not
## referenced by type, only via node path.

# Darkening alpha at the light centre (0.0 = untouched) and at the radius edge.
const SHADE_MIN := 0.0
const SHADE_MAX := 0.5

var light_pos := Vector2i.ZERO
var visible_cells: Dictionary = {}
var radius := float(GameData.FOV_RADIUS)
var enabled := true
var flicker := 1.0  # multiplier on the shade; breathes via _process

# Flicker: two summed sines give a living-flame wobble of about +/-7% around 1.0.
# Redraws are throttled well below the frame rate so the per-frame cost stays
# tiny (only this overlay redraws; the heavy tile pass is untouched).
const REDRAW_INTERVAL := 1.0 / 15.0
var _t := 0.0
var _redraw_accum := 0.0


func _process(delta: float) -> void:
	if not enabled or visible_cells.is_empty():
		return
	_t += delta
	flicker = 1.0 + 0.05 * sin(_t * 6.3) + 0.025 * sin(_t * 13.7)
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


func set_light(pos: Vector2i, cells: Dictionary) -> void:
	light_pos = pos
	visible_cells = cells
	queue_redraw()


func _draw() -> void:
	if not enabled or visible_cells.is_empty():
		return
	var cx := float(GameData.CELL.x)
	var cy := float(GameData.CELL.y)
	var inv_r := 1.0 / maxf(radius, 1.0)
	for pos in visible_cells:
		var d := Vector2(pos - light_pos).length() * inv_r
		var shade: float = lerpf(SHADE_MIN, SHADE_MAX, clampf(d, 0.0, 1.0)) * flicker
		if shade <= 0.0:
			continue
		draw_rect(Rect2(pos.x * cx, pos.y * cy, cx, cy), Color(0, 0, 0, shade))
