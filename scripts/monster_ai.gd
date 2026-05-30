class_name MonsterAI extends RefCounted

# Pure monster pathfinding: greedy chase / mirror flee / passability test.
# Stateless -- the caller passes the dungeon, occupancy map, and player cell, so
# nothing here touches game state. game.gd keeps the turn-driving and attacks.


# Greedy chase: try the longer axis first, then the other.
static func chase_step(from: Vector2i, to_player: Vector2i, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	if absi(to_player.x) >= absi(to_player.y):
		if to_player.x != 0:
			options.append(Vector2i(signi(to_player.x), 0))
		if to_player.y != 0:
			options.append(Vector2i(0, signi(to_player.y)))
	else:
		if to_player.y != 0:
			options.append(Vector2i(0, signi(to_player.y)))
		if to_player.x != 0:
			options.append(Vector2i(signi(to_player.x), 0))
	for step in options:
		if can_enter(from + step, dungeon, occupancy, player_pos):
			return step
	return Vector2i.ZERO


# Mirror of the chase: step directly away from the player when possible.
static func flee_step(from: Vector2i, to_player: Vector2i, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	if absi(to_player.x) >= absi(to_player.y):
		if to_player.x != 0:
			options.append(Vector2i(-signi(to_player.x), 0))
		if to_player.y != 0:
			options.append(Vector2i(0, -signi(to_player.y)))
	else:
		if to_player.y != 0:
			options.append(Vector2i(0, -signi(to_player.y)))
		if to_player.x != 0:
			options.append(Vector2i(-signi(to_player.x), 0))
	for step in options:
		if can_enter(from + step, dungeon, occupancy, player_pos):
			return step
	return Vector2i.ZERO


static func can_enter(cell: Vector2i, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> bool:
	if cell == player_pos:
		return false
	if occupancy.has(cell):
		return false
	return GameData.is_passable(dungeon.get_tile(cell.x, cell.y))
