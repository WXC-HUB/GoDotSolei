extends RefCounted

## 格子内道具类型；初版仅 NONE 与 MINE，后续可扩展。
enum ItemType { NONE, MINE }

signal changed
signal lost
signal won

var width: int
var height: int
var mine_count: int

var ended: bool = false
var _mines_placed: bool = false
var _cells: Array = []


func _init(w: int, h: int, mines: int) -> void:
	width = w
	height = h
	mine_count = mines
	for i in range(w * h):
		_cells.append({ "item": ItemType.NONE, "revealed": false, "flagged": false })


func idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func get_item(x: int, y: int) -> int:
	return int(_cells[idx(x, y)]["item"])


func is_revealed(x: int, y: int) -> bool:
	return bool(_cells[idx(x, y)]["revealed"])


func is_flagged(x: int, y: int) -> bool:
	return bool(_cells[idx(x, y)]["flagged"])


func adjacent_mine_count(x: int, y: int) -> int:
	var c := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if in_bounds(nx, ny) and int(_cells[idx(nx, ny)]["item"]) == ItemType.MINE:
				c += 1
	return c


func flag_count() -> int:
	var n := 0
	for c in _cells:
		if bool(c["flagged"]):
			n += 1
	return n


func _place_mines(safe_x: int, safe_y: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var excluded := {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := safe_x + dx
			var ny := safe_y + dy
			if in_bounds(nx, ny):
				excluded[idx(nx, ny)] = true
	var pool: Array[int] = []
	for i in range(_cells.size()):
		if not excluded.has(i):
			pool.append(i)
	pool.shuffle()
	var cap := mini(mine_count, pool.size())
	for j in range(cap):
		var ci: int = pool[j]
		_cells[ci]["item"] = ItemType.MINE
	_mines_placed = true


func _flood_reveal(x: int, y: int) -> void:
	var stack: Array[Vector2i] = [Vector2i(x, y)]
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		var px := p.x
		var py := p.y
		if not in_bounds(px, py):
			continue
		var i := idx(px, py)
		var c: Dictionary = _cells[i]
		if bool(c["revealed"]) or bool(c["flagged"]):
			continue
		if int(c["item"]) == ItemType.MINE:
			continue
		c["revealed"] = true
		if adjacent_mine_count(px, py) == 0:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					stack.append(Vector2i(px + dx, py + dy))


func _check_win() -> bool:
	for c in _cells:
		if int(c["item"]) != ItemType.MINE and not bool(c["revealed"]):
			return false
	return true


func reveal(x: int, y: int) -> void:
	if ended or not in_bounds(x, y):
		return
	var i := idx(x, y)
	var cell: Dictionary = _cells[i]
	if bool(cell["revealed"]) or bool(cell["flagged"]):
		return
	if not _mines_placed:
		_place_mines(x, y)
	if int(cell["item"]) == ItemType.MINE:
		for k in range(_cells.size()):
			if int(_cells[k]["item"]) == ItemType.MINE:
				_cells[k]["revealed"] = true
		ended = true
		changed.emit()
		lost.emit()
		return
	_flood_reveal(x, y)
	changed.emit()
	if _check_win():
		ended = true
		won.emit()


func toggle_flag(x: int, y: int) -> void:
	if ended or not in_bounds(x, y):
		return
	var i := idx(x, y)
	var cell: Dictionary = _cells[i]
	if bool(cell["revealed"]):
		return
	cell["flagged"] = not bool(cell["flagged"])
	changed.emit()
