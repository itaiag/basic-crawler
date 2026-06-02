extends Node2D
# Transient cosmetic projectile: a short streak that flies from the shooter to the
# impact cell, then frees itself. No class_name -- spawned at runtime via load(),
# like light_overlay.gd / combat_panel.gd, so it needs no editor registration pass.
#
# The node is rotated toward its travel direction and draws a head dot at the local
# origin with a tail trailing along -x; a position tween slides the origin (head)
# from start to impact, so the streak reads as a fast-moving missile. Faked with a
# line + circle (no texture / no shader) to stay GL-compatibility / web / mobile safe.

const TAIL := 13.0   # streak length trailing the head, in pixels
const HEAD_R := 2.5

var _color := Color.WHITE


func launch(from: Vector2, to: Vector2, color: Color, duration: float) -> void:
	_color = color
	position = from
	rotation = (to - from).angle()
	queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "position", to, duration).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(queue_free)


func _draw() -> void:
	draw_line(Vector2(-TAIL, 0.0), Vector2.ZERO, Color(_color.r, _color.g, _color.b, 0.85), 2.0)
	draw_circle(Vector2.ZERO, HEAD_R, _color)
