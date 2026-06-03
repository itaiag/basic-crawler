class_name MonsterAI extends RefCounted

# Pure monster pathfinding: greedy chase / mirror flee / passability test.
# Stateless -- the caller passes the dungeon, occupancy map, and player cell, so
# nothing here touches game state. game.gd keeps the turn-driving and attacks.


# Greedy chase: step diagonally toward the player when possible, else fall back to
# the longer orthogonal axis first, then the other.
static func chase_step(from: Vector2i, to_player: Vector2i, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> Vector2i:
	for step in _ranked_steps(to_player, false):
		if can_enter(from, step, dungeon, occupancy, player_pos):
			return step
	return Vector2i.ZERO


# Mirror of the chase: step directly away from the player when possible.
static func flee_step(from: Vector2i, to_player: Vector2i, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> Vector2i:
	for step in _ranked_steps(to_player, true):
		if can_enter(from, step, dungeon, occupancy, player_pos):
			return step
	return Vector2i.ZERO


# Preferred steps toward (or, when fleeing, away from) the player: diagonal first,
# then the two orthogonals in longer-axis-first order.
static func _ranked_steps(to_player: Vector2i, flee: bool) -> Array[Vector2i]:
	var away := -1 if flee else 1
	var sx := signi(to_player.x) * away
	var sy := signi(to_player.y) * away
	var opts: Array[Vector2i] = []
	if sx != 0 and sy != 0:
		opts.append(Vector2i(sx, sy))
	if absi(to_player.x) >= absi(to_player.y):
		if sx != 0:
			opts.append(Vector2i(sx, 0))
		if sy != 0:
			opts.append(Vector2i(0, sy))
	else:
		if sy != 0:
			opts.append(Vector2i(0, sy))
		if sx != 0:
			opts.append(Vector2i(sx, 0))
	return opts


static func can_enter(from: Vector2i, dir: Vector2i, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> bool:
	var cell := from + dir
	if cell == player_pos:
		return false
	if occupancy.has(cell):
		return false
	if not GameData.is_passable(dungeon.get_tile(cell.x, cell.y)):
		return false
	if dir.x != 0 and dir.y != 0 and not GameData.diagonal_clear(dungeon, from, dir):
		return false
	return true
