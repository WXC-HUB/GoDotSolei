extends RefCounted

## 格子内道具：空格、雷、探测器、引爆器（道具不计入邻格雷数）。
enum ItemType { NONE, MINE, DETECTOR, DETONATOR }

signal changed
signal lost
signal won

var width: int
var height: int
var mine_count: int
var detector_chance: float = 0.08
var detonator_chance: float = 0.06

var ended: bool = false
var _mines_placed: bool = false
var _cells: Array = []
## FIFO：道具动画播完后再结算；元素 { "kind": "detector"|"detonator", "from": Vector2i, "to"?: Vector2i }
var _prop_jobs: Array = []


func _init(w: int, h: int, mines: int, p_detector_chance: float = 0.08, p_detonator_chance: float = 0.06) -> void:
	width = w
	height = h
	mine_count = mines
	detector_chance = clampf(p_detector_chance, 0.0, 1.0)
	detonator_chance = clampf(p_detonator_chance, 0.0, 1.0)
	var sum := detector_chance + detonator_chance
	if sum > 1.0:
		detonator_chance = maxf(0.0, 1.0 - detector_chance)
	for i in range(w * h):
		_cells.append({ "item": ItemType.NONE, "revealed": false, "flagged": false, "spent": false })


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


func is_prop_spent(x: int, y: int) -> bool:
	return bool(_cells[idx(x, y)].get("spent", false))


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


func has_pending_prop_jobs() -> bool:
	return not _prop_jobs.is_empty()


func pop_prop_job() -> Variant:
	if _prop_jobs.is_empty():
		return null
	return _prop_jobs.pop_front()


## Game：探测器粒子抵达后调用。
func apply_detector_prop(from_x: int, from_y: int, to_x: int, to_y: int) -> void:
	if ended:
		return
	_flood_reveal(to_x, to_y)
	changed.emit()
	var fi := idx(from_x, from_y)
	var fc: Dictionary = _cells[fi]
	if int(fc["item"]) == ItemType.DETECTOR and bool(fc["revealed"]):
		fc["spent"] = true
	_try_emit_win_if_cleared()


## Game：引爆器八向粒子结束后调用。
func apply_detonator_prop(from_x: int, from_y: int) -> void:
	if ended:
		return
	_apply_detonator_burst(from_x, from_y)
	var fi := idx(from_x, from_y)
	var fc: Dictionary = _cells[fi]
	if int(fc["item"]) == ItemType.DETONATOR and bool(fc["revealed"]):
		fc["spent"] = true
	changed.emit()
	_try_emit_win_if_cleared()


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


## 非雷格互斥：先探测器概率，再引爆器概率，否则 NONE。
func _place_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dc := detector_chance
	var tc := detonator_chance
	if dc + tc > 1.0:
		tc = maxf(0.0, 1.0 - dc)
	for i in range(_cells.size()):
		var c: Dictionary = _cells[i]
		if int(c["item"]) == ItemType.MINE:
			continue
		var u := rng.randf()
		if u < dc:
			c["item"] = ItemType.DETECTOR
		elif u < dc + tc:
			c["item"] = ItemType.DETONATOR
		else:
			c["item"] = ItemType.NONE


func _enqueue_detector(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return
	var i := idx(x, y)
	var c: Dictionary = _cells[i]
	if bool(c["revealed"]) or bool(c["flagged"]):
		return
	if int(c["item"]) != ItemType.DETECTOR:
		return
	c["revealed"] = true
	var pool: Array[Vector2i] = []
	for gy in range(height):
		for gx in range(width):
			if gx == x and gy == y:
				continue
			var di := idx(gx, gy)
			var d: Dictionary = _cells[di]
			if bool(d["revealed"]) or bool(d["flagged"]):
				continue
			if int(d["item"]) == ItemType.MINE:
				continue
			pool.append(Vector2i(gx, gy))
	if pool.is_empty():
		c["spent"] = true
		return
	pool.shuffle()
	var t: Vector2i = pool[0]
	_prop_jobs.append({ "kind": "detector", "from": Vector2i(x, y), "to": t })


func _enqueue_detonator(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return
	var i := idx(x, y)
	var c: Dictionary = _cells[i]
	if bool(c["revealed"]) or bool(c["flagged"]):
		return
	if int(c["item"]) != ItemType.DETONATOR:
		return
	c["revealed"] = true
	_prop_jobs.append({ "kind": "detonator", "from": Vector2i(x, y) })


func _apply_detonator_burst(cx: int, cy: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if not in_bounds(nx, ny):
				continue
			var di := idx(nx, ny)
			var d: Dictionary = _cells[di]
			if bool(d["revealed"]):
				continue
			if int(d["item"]) == ItemType.MINE:
				d["flagged"] = true
				continue
			if bool(d["flagged"]):
				continue
			_flood_reveal(nx, ny)


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
		if int(c["item"]) == ItemType.DETECTOR:
			_enqueue_detector(px, py)
			continue
		if int(c["item"]) == ItemType.DETONATOR:
			_enqueue_detonator(px, py)
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


func _try_emit_win_if_cleared() -> void:
	if not _prop_jobs.is_empty():
		return
	if _check_win():
		ended = true
		won.emit()


func reveal(x: int, y: int) -> void:
	if ended or not in_bounds(x, y):
		return
	var i := idx(x, y)
	var cell: Dictionary = _cells[i]
	if bool(cell["revealed"]) or bool(cell["flagged"]):
		return
	if not _mines_placed:
		_place_mines(x, y)
		_place_props()
	var item: int = int(cell["item"])
	if item == ItemType.MINE:
		for k in range(_cells.size()):
			if int(_cells[k]["item"]) == ItemType.MINE:
				_cells[k]["revealed"] = true
		ended = true
		changed.emit()
		lost.emit()
		return
	if item == ItemType.DETECTOR:
		_enqueue_detector(x, y)
		changed.emit()
		_try_emit_win_if_cleared()
		return
	if item == ItemType.DETONATOR:
		_enqueue_detonator(x, y)
		changed.emit()
		_try_emit_win_if_cleared()
		return
	_flood_reveal(x, y)
	changed.emit()
	_try_emit_win_if_cleared()


func toggle_flag(x: int, y: int) -> void:
	if ended or not in_bounds(x, y):
		return
	var i := idx(x, y)
	var cell: Dictionary = _cells[i]
	if bool(cell["revealed"]):
		return
	cell["flagged"] = not bool(cell["flagged"])
	changed.emit()
