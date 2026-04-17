extends Control

const LevelCatalog := preload("res://scripts/level_catalog.gd")
const BoardModel := preload("res://scripts/game/board_model.gd")
const SweeperCell := preload("res://scripts/cell.gd")
const CELL_SCENE := preload("res://scenes/Cell.tscn")
const LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const GAME_SCENE := "res://scenes/Game.tscn"

const DEFAULT_DETECTOR_CHANCE := 0.08
const DEFAULT_DETONATOR_CHANCE := 0.06
const PROP_JOB_GAP_SEC := 0.12
const FLIGHT_DURATION_SEC := 0.32

@onready var _grid: GridContainer = $Margin/Card/Inner/VBox/Scroll/BoardGrid
@onready var _status: Label = $Margin/Card/Inner/VBox/Toolbar/Status
@onready var _mine_label: Label = $Margin/Card/Inner/VBox/MineLabel
@onready var _retry: Button = $Margin/Card/Inner/VBox/Toolbar/BtnRetry
@onready var _fx_layer: CanvasLayer = $FxLayer
@onready var _blocking_banner: PanelContainer = $FxLayer/BlockingBanner
@onready var _blocking_label: Label = $FxLayer/BlockingBanner/Label
@onready var _flight_dot: ColorRect = $FxLayer/FlightDot

var _model: BoardModel
var _cell_nodes: Array = []

var _prop_blocking: bool = false
var _drain_running: bool = false
var _banner_tween: Tween


func _ready() -> void:
	var levels := LevelCatalog.get_levels()
	var idx: int = clampi(RunConfig.selected_level_index, 0, maxi(levels.size() - 1, 0))
	if levels.is_empty():
		_status.text = "无关卡数据"
		return
	var def: Dictionary = levels[idx]
	var w: int = int(def.get("width", 9))
	var h: int = int(def.get("height", 9))
	var mines: int = int(def.get("mines", 10))
	var det_chance: float = float(def.get("detector_chance", DEFAULT_DETECTOR_CHANCE))
	var deto_chance: float = float(def.get("detonator_chance", DEFAULT_DETONATOR_CHANCE))
	_model = BoardModel.new(w, h, mines, det_chance, deto_chance)
	_model.changed.connect(_on_model_changed)
	_model.lost.connect(_on_lost)
	_model.won.connect(_on_won)
	_grid.columns = w
	for y in range(h):
		for x in range(w):
			var cell := CELL_SCENE.instantiate() as SweeperCell
			cell.setup(x, y)
			cell.reveal_requested.connect(_on_reveal)
			cell.flag_requested.connect(_on_flag)
			_grid.add_child(cell)
			_cell_nodes.append(cell)
	const CELL_PX := 30
	const GRID_GAP := 3
	_grid.custom_minimum_size = Vector2(
		w * CELL_PX + maxi(w - 1, 0) * GRID_GAP,
		h * CELL_PX + maxi(h - 1, 0) * GRID_GAP
	)
	_blocking_banner.visible = false
	_flight_dot.visible = false
	_retry.disabled = true
	_status.text = "左键翻开，右键标记"
	_refresh_mine_label()
	_on_model_changed()


func _on_reveal(x: int, y: int) -> void:
	if _model == null or _prop_blocking:
		return
	_model.reveal(x, y)
	_on_model_changed()
	if _model.has_pending_prop_jobs():
		_run_drain_async()


func _on_flag(x: int, y: int) -> void:
	if _model == null or _prop_blocking:
		return
	_model.toggle_flag(x, y)


func _run_drain_async() -> void:
	if _drain_running:
		return
	if _model == null or not _model.has_pending_prop_jobs():
		return
	_drain_running = true
	_prop_blocking = true
	_set_board_input_blocked(true)
	_show_blocking_banner()
	while _model.has_pending_prop_jobs() and not _model.ended:
		var job: Variant = _model.pop_prop_job()
		if job == null:
			break
		var d: Dictionary = job
		var kind: String = String(d.get("kind", "detector"))
		if kind == "detonator":
			var from_d: Vector2i = d["from"]
			await _play_detonator_ring_flights(from_d)
			if _model == null or _model.ended:
				break
			_model.apply_detonator_prop(from_d.x, from_d.y)
			_on_model_changed()
		else:
			var from_v: Vector2i = d["from"]
			var to_v: Vector2i = d["to"]
			await _play_detector_flight(from_v, to_v)
			if _model == null or _model.ended:
				break
			_model.apply_detector_prop(from_v.x, from_v.y, to_v.x, to_v.y)
			_on_model_changed()
		if _model == null or _model.ended:
			break
		await get_tree().create_timer(PROP_JOB_GAP_SEC).timeout
	_hide_blocking_banner()
	_set_board_input_blocked(false)
	_prop_blocking = false
	_drain_running = false
	if _model != null:
		_on_model_changed()


func _play_detector_flight(from_g: Vector2i, to_g: Vector2i) -> void:
	if _model == null or _model.ended:
		return
	var from_p := _cell_center_global(from_g)
	var to_p := _cell_center_global(to_g)
	var half := _flight_dot.size * 0.5
	_flight_dot.visible = true
	_flight_dot.global_position = from_p - half
	var tw := create_tween()
	tw.tween_property(_flight_dot, "global_position", to_p - half, FLIGHT_DURATION_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_flight_dot.visible = false


func _play_detonator_ring_flights(center: Vector2i) -> void:
	if _model == null or _model.ended:
		return
	var targets: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := center.x + dx
			var ny := center.y + dy
			if not _model.in_bounds(nx, ny):
				continue
			if not _model.is_revealed(nx, ny):
				targets.append(Vector2i(nx, ny))
	if targets.is_empty():
		return
	var from_c := _cell_center_global(center)
	var dots: Array[ColorRect] = []
	for t in targets:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = Color(1, 0.55, 0.15, 0.92)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_layer.add_child(dot)
		dot.global_position = from_c - dot.custom_minimum_size * 0.5
		dots.append(dot)
	var tw := create_tween()
	tw.set_parallel(true)
	for i in range(targets.size()):
		var to_p := _cell_center_global(targets[i])
		var ddot: ColorRect = dots[i]
		tw.tween_property(ddot, "global_position", to_p - ddot.custom_minimum_size * 0.5, FLIGHT_DURATION_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	for ddot in dots:
		ddot.queue_free()


func _cell_center_global(g: Vector2i) -> Vector2:
	var ix := g.y * _model.width + g.x
	return (_cell_nodes[ix] as Control).get_global_rect().get_center()


func _set_board_input_blocked(on: bool) -> void:
	for c in _cell_nodes:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP


func _show_blocking_banner() -> void:
	_blocking_banner.visible = true
	_blocking_label.modulate = Color(1, 1, 1, 1)
	_kill_banner_tween()
	_banner_tween = create_tween().set_loops()
	_banner_tween.tween_property(_blocking_label, "modulate:a", 0.4, 0.38)
	_banner_tween.tween_property(_blocking_label, "modulate:a", 1.0, 0.38)


func _hide_blocking_banner() -> void:
	_kill_banner_tween()
	_blocking_banner.visible = false
	_blocking_label.modulate = Color(1, 1, 1, 1)


func _kill_banner_tween() -> void:
	if _banner_tween != null and is_instance_valid(_banner_tween):
		_banner_tween.kill()
	_banner_tween = null


func _on_model_changed() -> void:
	if _model == null:
		return
	for c in _cell_nodes:
		(c as SweeperCell).update_from_model(_model)
	_refresh_mine_label()


func _refresh_mine_label() -> void:
	if _model == null:
		return
	var left: int = _model.mine_count - _model.flag_count()
	_mine_label.text = "剩余标记/雷: %d" % left


func _on_lost() -> void:
	_status.text = "踩到雷，本局结束"
	_retry.disabled = false


func _on_won() -> void:
	_status.text = "通关！"
	_retry.disabled = false


func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_level_select_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT)
