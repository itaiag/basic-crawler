class_name DungeonPopulator extends RefCounted

# Pure dungeon population: decides *what* goes *where*, returning plain data.
# It never creates nodes -- game.gd owns Monster instances and the live _items_at
# dict. The caller passes the dungeon and current occupancy so nothing here reads
# game state.


# Roll monster placements: 0-2 per room (skipping the start room, index 0).
# Returns [{ "kind": int, "cell": Vector2i }, ...]. A local copy of the occupancy
# is grown as cells are chosen so two monsters never land on the same tile.
static func roll_monsters(dungeon, occupancy: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var taken: Dictionary = occupancy.duplicate()
	for ri in range(1, dungeon.rooms.size()):
		var room: Rect2i = dungeon.rooms[ri]
		var n := randi_range(0, 2)
		for _k in range(n):
			var cell := random_floor_cell(dungeon, room, taken)
			if cell.x < 0:
				continue
			var kind := randi() % GameData.MONSTERS.size()
			result.append({"kind": kind, "cell": cell})
			taken[cell] = true
	return result


# Roll item placements across every room. Returns Vector2i -> item dict. Monsters
# are expected to be spawned already (passed via occupancy) so items avoid them.
static func roll_items(dungeon, occupancy: Dictionary) -> Dictionary:
	var items: Dictionary = {}
	for ri in range(dungeon.rooms.size()):
		var room: Rect2i = dungeon.rooms[ri]
		if randf() < 0.5:
			_place_item(dungeon, room, gold_item(), items, occupancy)
		if randf() < 0.35:
			_place_item(dungeon, room, potion_item(), items, occupancy)
		if randf() < 0.20:
			_place_item(dungeon, room, loot_item(random_weapon_kind()), items, occupancy)
		if randf() < 0.15:
			_place_item(dungeon, room, loot_item(random_armor_kind()), items, occupancy)
	return items


# A cell 2-5 (min_r..max_r) tiles from center for a wandering spawn; -1,-1 on fail.
static func wandering_cell_near(center: Vector2i, min_r: int, max_r: int, dungeon, occupancy: Dictionary, player_pos: Vector2i) -> Vector2i:
	for _t in range(30):
		var dx := randi_range(-max_r, max_r)
		var dy := randi_range(-max_r, max_r)
		var dist := absi(dx) + absi(dy)
		if dist < min_r or dist > max_r:
			continue
		var cell := center + Vector2i(dx, dy)
		if cell == player_pos or occupancy.has(cell):
			continue
		if not GameData.is_passable(dungeon.get_tile(cell.x, cell.y)):
			continue
		return cell
	return Vector2i(-1, -1)


static func random_floor_cell(dungeon, room: Rect2i, occupancy: Dictionary) -> Vector2i:
	for _t in range(10):
		var x := randi_range(room.position.x, room.end.x - 1)
		var y := randi_range(room.position.y, room.end.y - 1)
		var cell := Vector2i(x, y)
		if dungeon.get_tile(x, y) == GameData.Tile.FLOOR and not occupancy.has(cell):
			return cell
	return Vector2i(-1, -1)


static func _place_item(dungeon, room: Rect2i, item: Dictionary, items: Dictionary, occupancy: Dictionary) -> void:
	for _t in range(10):
		var x := randi_range(room.position.x, room.end.x - 1)
		var y := randi_range(room.position.y, room.end.y - 1)
		var cell := Vector2i(x, y)
		if dungeon.get_tile(x, y) != GameData.Tile.FLOOR:
			continue
		if items.has(cell) or occupancy.has(cell):
			continue
		items[cell] = item
		return


static func gold_item() -> Dictionary:
	return {"glyph": "$", "color": GameData.COLOR_GOLD, "gold": randi_range(2, 30)}


static func potion_item() -> Dictionary:
	var data: Dictionary = GameData.ITEMS[GameData.ItemKind.HEALING_POTION]
	return {"glyph": "!", "color": data["color"], "item": GameData.ItemKind.HEALING_POTION}


static func loot_item(kind: int) -> Dictionary:
	var data: Dictionary = GameData.ITEMS[kind]
	return {"glyph": data["glyph"], "color": data["color"], "item": kind}


static func random_weapon_kind() -> int:
	var kinds: Array[int] = []
	for kind in range(GameData.ITEMS.size()):
		if GameData.is_weapon(kind):
			kinds.append(kind)
	var pick: int = kinds[randi() % kinds.size()]
	return pick


static func random_armor_kind() -> int:
	var kinds: Array[int] = []
	for kind in range(GameData.ITEMS.size()):
		if GameData.is_armor(kind) or GameData.is_shield(kind):
			kinds.append(kind)
	var pick: int = kinds[randi() % kinds.size()]
	return pick
