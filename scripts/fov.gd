class_name FOV
## Recursive shadowcasting FOV (RogueBasin algorithm).
## Processes 8 octants with directional multipliers.

static func compute(origin: Vector2i, radius: int, is_opaque: Callable) -> Dictionary:
	var visible := {}
	visible[origin] = true

	var xx := [1, 0, 0, -1, -1, 0, 0, 1]
	var xy := [0, 1, -1, 0, 0, -1, 1, 0]
	var yx := [0, 1, 1, 0, 0, -1, -1, 0]
	var yy := [1, 0, 0, 1, -1, 0, 0, -1]

	for oct in 8:
		_cast(origin, radius, 1, 1.0, 0.0,
			xx[oct], xy[oct], yx[oct], yy[oct], is_opaque, visible)

	return visible


static func _cast(origin: Vector2i, radius: int, row: int,
		start: float, end: float,
		xx: int, xy: int, yx: int, yy: int,
		is_opaque: Callable, visible: Dictionary) -> void:
	if start < end:
		return

	var r2 := radius * radius
	var new_start := start

	for j in range(row, radius + 1):
		var blocked := false

		for dx in range(-j, 1):
			var dy := -j
			var map_x := origin.x + dx * xx + dy * xy
			var map_y := origin.y + dx * yx + dy * yy
			var pos := Vector2i(map_x, map_y)

			var l_slope := (float(dx) - 0.5) / (float(dy) + 0.5)
			var r_slope := (float(dx) + 0.5) / (float(dy) - 0.5)

			if start < r_slope:
				continue
			if end > l_slope:
				break

			if dx * dx + dy * dy <= r2:
				visible[pos] = true

			if blocked:
				if is_opaque.call(pos):
					new_start = r_slope
				else:
					blocked = false
					start = new_start
			elif is_opaque.call(pos):
				blocked = true
				_cast(origin, radius, j + 1, start, l_slope,
					xx, xy, yx, yy, is_opaque, visible)
				new_start = r_slope

		if blocked:
			break
