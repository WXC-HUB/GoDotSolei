extends Control

const LevelCatalog := preload("res://scripts/level_catalog.gd")
const BoardModel := preload("res://scripts/game/board_model.gd")
const SweeperCell := preload("res://scripts/cell.gd")
const CELL_SCENE := preload("res://scenes/Cell.tscn")
const LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const GAME_SCENE := "res://scenes/Game.tscn"
const _STRIPE_BG := preload("res://scripts/stripe_background.gd")

const DEFAULT_DETECTOR_CHANCE := 0.08
const DEFAULT_DETONATOR_CHANCE := 0.06
const DEFAULT_REVIVE_CARD_CHANCE := 0.05
const PROP_JOB_GAP_SEC := 0.07
const FLIGHT_DURATION_SEC := 0.26
## 单次翻开 batch 格时的指数底数；batch 越大本次得分爆炸越快。
const OPEN_SCORE_EXP_BASE := 1.78
const MAX_SCORE_PER_POP := 2_000_000_000
const MAX_TOTAL_SCORE := 9_999_999_999
## 烟花粒子 tier：0 轻、1 中、2 重（数量与速度）
const FW_TIER_LIGHT := 0
const FW_TIER_MED := 1
const FW_TIER_HEAVY := 2

@onready var _margin: MarginContainer = $Margin
@onready var _card: PanelContainer = $Margin/Card
@onready var _grid: GridContainer = $Margin/Card/Inner/VBox/Scroll/BoardGrid
@onready var _status: Label = $Margin/Card/Inner/VBox/Toolbar/Status
@onready var _mine_label: Label = $Margin/Card/Inner/VBox/MineLabel
@onready var _score_value: Label = $Margin/Card/Inner/VBox/ScoreRow/ScoreValue
@onready var _combo_strip: Label = $Margin/Card/Inner/VBox/ScoreRow/ComboStrip
@onready var _retry: Button = $Margin/Card/Inner/VBox/Toolbar/BtnRetry
@onready var _fx_layer: CanvasLayer = $FxLayer
@onready var _blocking_banner: PanelContainer = $FxLayer/BlockingBanner
@onready var _blocking_label: Label = $FxLayer/BlockingBanner/Label
@onready var _flight_dot: ColorRect = $FxLayer/FlightDot
@onready var _combo_splash: Label = $FxLayer/ComboSplash
@onready var _life_splash: Label = $FxLayer/LifeSplash
@onready var _bg: ColorRect = $Bg

var _model: BoardModel
var _cell_nodes: Array = []

var _prop_blocking: bool = false
var _drain_running: bool = false
var _banner_tween: Tween
var _combo_splash_tween: Tween
var _life_splash_tween: Tween
var _score_pulse_tween: Tween

var _score: int = 0
var _combo: int = 0
var _particles_host: Node2D
var _fw_spark_tex: Texture2D


func _ready() -> void:
	_STRIPE_BG.attach(_bg, 0.27, 17.0)
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
	var revive_chance: float = float(def.get("revive_card_chance", DEFAULT_REVIVE_CARD_CHANCE))
	_model = BoardModel.new(w, h, mines, det_chance, deto_chance, revive_chance)
	_model.changed.connect(_on_model_changed)
	_model.lost.connect(_on_lost)
	_model.won.connect(_schedule_on_won)
	_model.life_spent.connect(_on_life_spent)
	_model.life_gained.connect(_on_life_gained)
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
	_particles_host = Node2D.new()
	_particles_host.name = "ParticlesHost"
	_fx_layer.add_child(_particles_host)
	_blocking_banner.visible = false
	_flight_dot.visible = false
	_retry.disabled = true
	_status.text = "左键翻开，右键标记"
	_score = 0
	_combo = 0
	_refresh_score_row()
	call_deferred("_setup_fx_pivots")
	_refresh_mine_label()
	_on_model_changed()


func _setup_fx_pivots() -> void:
	_card.pivot_offset = _card.size * 0.5
	_grid.pivot_offset = _grid.size * 0.5
	if _score_value != null:
		_score_value.pivot_offset = _score_value.size * 0.5
	_combo_splash.pivot_offset = _combo_splash.custom_minimum_size * 0.5
	if _life_splash != null:
		_life_splash.pivot_offset = _life_splash.custom_minimum_size * 0.5


func _on_reveal(x: int, y: int) -> void:
	if _model == null or _prop_blocking:
		return
	var batch: int = _model.reveal(x, y)
	_on_model_changed()
	if batch > 0:
		_combo += 1
		var gain: int = _compute_score_gain(batch)
		_score = mini(_score + gain, MAX_TOTAL_SCORE)
		_refresh_score_row()
		_pulse_score_value()
		_play_combo_splash(batch, gain)
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
			await _impact_heavy()
		else:
			var from_v: Vector2i = d["from"]
			var to_v: Vector2i = d["to"]
			await _play_detector_flight(from_v, to_v)
			if _model == null or _model.ended:
				break
			_model.apply_detector_prop(from_v.x, from_v.y, to_v.x, to_v.y)
			_on_model_changed()
			await _impact_medium()
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
	_flight_dot.custom_minimum_size = Vector2(14, 14)
	_flight_dot.color = Color(0.45, 0.95, 1.0, 0.98)
	var half := _flight_dot.custom_minimum_size * 0.5
	_flight_dot.visible = true
	_flight_dot.scale = Vector2(0.35, 0.35)
	_flight_dot.global_position = from_p - half
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_flight_dot, "global_position", to_p - half, FLIGHT_DURATION_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flight_dot, "scale", Vector2(1.45, 1.45), FLIGHT_DURATION_SEC * 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	_flight_dot.visible = false
	_flight_dot.scale = Vector2.ONE
	_burst_fireworks(to_p, FW_TIER_LIGHT, 0.12)


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
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = Color(1, 0.62, 0.08, 1.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_layer.add_child(dot)
		dot.scale = Vector2(0.15, 0.15)
		dot.global_position = from_c - dot.custom_minimum_size * 0.5
		dots.append(dot)
	var tw := create_tween()
	tw.set_parallel(true)
	for i in range(targets.size()):
		var to_p := _cell_center_global(targets[i])
		var ddot: ColorRect = dots[i]
		var half_d := ddot.custom_minimum_size * 0.5
		tw.tween_property(ddot, "global_position", to_p - half_d, FLIGHT_DURATION_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(ddot, "scale", Vector2(1.35, 1.35), FLIGHT_DURATION_SEC * 0.65).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	for ddot in dots:
		ddot.queue_free()
	_burst_fireworks(from_c, FW_TIER_HEAVY, randf() * 0.15)
	for ti in mini(targets.size(), 6):
		var gi: Vector2i = targets[wrapi(ti * 3 + 1, 0, targets.size())]
		_burst_fireworks(_cell_center_global(gi), FW_TIER_LIGHT, randf_range(-0.2, 0.2))


func _cell_center_global(g: Vector2i) -> Vector2:
	var ix := g.y * _model.width + g.x
	return (_cell_nodes[ix] as Control).get_global_rect().get_center()


func _set_board_input_blocked(on: bool) -> void:
	for c in _cell_nodes:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP


func _show_blocking_banner() -> void:
	_blocking_banner.visible = true
	_blocking_label.modulate = Color(1, 0.94, 0.72, 1)
	_kill_banner_tween()
	_banner_tween = create_tween().set_loops()
	_banner_tween.tween_property(_blocking_label, "modulate:a", 0.08, 0.18)
	_banner_tween.tween_property(_blocking_label, "modulate:a", 1.0, 0.18)


func _hide_blocking_banner() -> void:
	_kill_banner_tween()
	_blocking_banner.visible = false
	_blocking_label.modulate = Color(1, 1, 1, 1)


func _kill_banner_tween() -> void:
	if _banner_tween != null and is_instance_valid(_banner_tween):
		_banner_tween.kill()
	_banner_tween = null


func _shake_margin(strength: float, duration: float) -> void:
	var p0 := _margin.position
	var tw := create_tween()
	var steps := 14
	for s in range(steps):
		var t := float(s) / float(max(steps - 1, 1))
		var damp := 1.0 - t * 0.92
		var ox := (randf() * 2.0 - 1.0) * strength * damp
		var oy := (randf() * 2.0 - 1.0) * strength * damp
		tw.tween_property(_margin, "position", p0 + Vector2(ox, oy), duration / float(steps)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_margin, "position", p0, duration / float(steps) * 0.75).set_trans(Tween.TRANS_QUAD)
	await tw.finished


func _pulse_card_scale(peak: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_card, "scale", Vector2(peak, peak), dur * 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2.ONE, dur * 0.58).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tw.finished


func _pulse_grid_flash() -> void:
	var tw := create_tween()
	tw.tween_property(_grid, "modulate", Color(1.28, 1.3, 1.15, 1.0), 0.05)
	tw.tween_property(_grid, "modulate", Color.WHITE, 0.12).set_trans(Tween.TRANS_QUAD)
	await tw.finished


func _screen_flash_warm(alpha_peak: float, dur: float) -> void:
	var flash := ColorRect.new()
	var vr := get_viewport().get_visible_rect()
	flash.position = vr.position
	flash.size = vr.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1.0, 0.48, 0.1, 0.0)
	_fx_layer.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", alpha_peak, dur * 0.22)
	tw.tween_property(flash, "color:a", 0.0, dur * 0.78).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	flash.queue_free()
	_burst_fireworks(get_viewport().get_visible_rect().get_center(), FW_TIER_MED, randf() * 0.25)


func _impact_medium() -> void:
	_burst_fireworks(_grid_screen_center(), FW_TIER_MED, randf_range(-0.08, 0.08))
	_burst_fireworks(_grid_screen_center() + Vector2(randf_range(-28, 28), randf_range(-18, 18)), FW_TIER_LIGHT, randf_range(0.15, 0.35))
	await _shake_margin(7.0, 0.16)
	await _pulse_card_scale(1.018, 0.14)
	await _pulse_grid_flash()


func _impact_heavy() -> void:
	var gc := _grid_screen_center()
	_burst_fireworks(gc, FW_TIER_HEAVY, randf() * 0.2)
	_burst_fireworks(gc + Vector2(randf_range(-52, 52), randf_range(-36, 36)), FW_TIER_MED, randf_range(-0.35, 0.35))
	call_deferred("_burst_fireworks", gc + Vector2(randf_range(-24, 24), randf_range(-80, -20)), FW_TIER_LIGHT, randf() * 0.1)
	await _shake_margin(13.0, 0.24)
	await _pulse_card_scale(1.045, 0.18)
	await _screen_flash_warm(0.32, 0.16)
	await _pulse_grid_flash()


func _grid_screen_center() -> Vector2:
	return _grid.get_global_rect().get_center()


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
	_mine_label.text = "剩余标记/雷: %d  ·  生命 ×%d" % [left, _model.lives]


func _on_life_spent(x: int, y: int) -> void:
	if _model == null:
		return
	var cell_p: Vector2 = _cell_center_global(Vector2i(x, y))
	_burst_fireworks(cell_p, FW_TIER_HEAVY, 0.02)
	_burst_fireworks(cell_p + Vector2(randf_range(-70, 70), randf_range(-40, 40)), FW_TIER_MED, 0.18)
	_play_life_block_splash(_model.lives)
	_status.text = "替你挡雷！剩余生命 ×%d" % _model.lives


func _on_life_gained(_x: int, _y: int) -> void:
	if _model == null:
		return
	_burst_fireworks(_cell_center_global(Vector2i(_x, _y)), FW_TIER_LIGHT, 0.32)


func _refresh_score_row() -> void:
	if _score_value != null:
		_score_value.text = _format_big_int(_score)
	if _combo_strip != null:
		_combo_strip.text = "连击 ×%d" % _combo


func _format_big_int(v: int) -> String:
	if v >= 1_000_000_000:
		return "%.2fB" % (float(v) / 1_000_000_000.0)
	if v >= 1_000_000:
		return "%.2fM" % (float(v) / 1_000_000.0)
	if v >= 10_000:
		return "%.1f万" % (float(v) / 10000.0)
	return str(v)


func _compute_score_gain(batch: int) -> int:
	if batch < 1:
		return 0
	var mul: int = maxi(_combo, 1)
	var raw: float = pow(OPEN_SCORE_EXP_BASE, float(batch)) * float(mul)
	if raw != raw or raw > float(MAX_SCORE_PER_POP):
		return MAX_SCORE_PER_POP
	return clampi(int(round(raw)), 1, MAX_SCORE_PER_POP)


func _play_life_block_splash(lives_remaining: int) -> void:
	if _life_splash == null:
		return
	if _life_splash_tween != null and is_instance_valid(_life_splash_tween):
		_life_splash_tween.kill()
	if _combo_splash_tween != null and is_instance_valid(_combo_splash_tween):
		_combo_splash_tween.kill()
		_combo_splash.visible = false
	_life_splash.visible = true
	var pulse: float = clampf(1.0 - float(lives_remaining) * 0.18, 0.0, 1.0)
	_life_splash.modulate = Color(0.55, 0.98, 1.0, 1.0).lerp(Color(1.0, 0.55, 0.35, 1.0), pulse)
	var fs: int = clampi(48 + (4 - clampi(lives_remaining, 0, 4)) * 10, 46, 96)
	_life_splash.add_theme_font_size_override("font_size", fs)
	_life_splash.text = "替你挡雷\n生命 ×%d" % lives_remaining
	_life_splash.pivot_offset = _life_splash.custom_minimum_size * 0.5
	_life_splash.scale = Vector2(0.32, 0.32)
	_life_splash.rotation_degrees = -4.0
	var splash_c: Vector2 = _life_splash.get_global_rect().get_center()
	_burst_fireworks(splash_c + Vector2(0, 20), FW_TIER_MED, randf_range(0.1, 0.28))
	_burst_fireworks(splash_c + Vector2(randf_range(-90, 90), randf_range(-30, 30)), FW_TIER_LIGHT, randf() * 0.35)
	var tw := create_tween()
	_life_splash_tween = tw
	tw.set_parallel(true)
	tw.tween_property(_life_splash, "scale", Vector2(1.38, 1.38), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_life_splash, "rotation_degrees", 0.0, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_property(_life_splash, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.42)
	tw.tween_property(_life_splash, "modulate:a", 0.0, 0.32)
	tw.tween_callback(func() -> void:
		_life_splash.visible = false
		_life_splash.modulate = Color(0.55, 0.98, 1.0, 1.0)
		_life_splash.rotation_degrees = 0.0
	)


func _play_combo_splash(batch: int, gain: int) -> void:
	if _combo_splash == null:
		return
	if _life_splash_tween != null and is_instance_valid(_life_splash_tween):
		_life_splash_tween.kill()
		_life_splash.visible = false
	if _combo_splash_tween != null and is_instance_valid(_combo_splash_tween):
		_combo_splash_tween.kill()
	_combo_splash.visible = true
	var heat: float = clampf((float(batch) - 1.0) / 28.0, 0.0, 1.0)
	_combo_splash.modulate = Color(1.0, 0.98, 0.45, 1.0).lerp(Color(1.0, 0.28, 0.22, 1.0), heat)
	var fs: int = clampi(38 + _combo * 2 + batch * 5, 38, 128)
	_combo_splash.add_theme_font_size_override("font_size", fs)
	_combo_splash.text = "×%d  +%s" % [_combo, _format_big_int(gain)]
	_combo_splash.pivot_offset = _combo_splash.custom_minimum_size * 0.5
	_combo_splash.scale = Vector2(0.45, 0.45)
	var splash_center: Vector2 = _combo_splash.get_global_rect().get_center()
	var fw_tier: int = clampi(FW_TIER_LIGHT + batch / 5 + _combo / 8, FW_TIER_LIGHT, FW_TIER_HEAVY)
	_burst_fireworks(splash_center, fw_tier, randf_range(-0.3, 0.3))
	if batch >= 6 or _combo >= 5:
		_burst_fireworks(splash_center + Vector2(randf_range(-60, 60), randf_range(-28, 28)), clampi(fw_tier - 1, FW_TIER_LIGHT, FW_TIER_HEAVY), randf() * 0.4)
	var tw := create_tween()
	_combo_splash_tween = tw
	tw.tween_property(_combo_splash, "scale", Vector2(1.35, 1.35), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_combo_splash, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(_combo_splash, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func() -> void:
		_combo_splash.visible = false
		_combo_splash.modulate = Color(1, 0.88, 0.35, 1)
	)


func _pulse_score_value() -> void:
	if _score_value == null:
		return
	if _score_pulse_tween != null and is_instance_valid(_score_pulse_tween):
		_score_pulse_tween.kill()
	var tw := create_tween()
	_score_pulse_tween = tw
	tw.tween_property(_score_value, "scale", Vector2(1.22, 1.22), 0.07)
	tw.tween_property(_score_value, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_ELASTIC)


func _on_lost() -> void:
	_combo = 0
	_refresh_score_row()
	if _life_splash_tween != null and is_instance_valid(_life_splash_tween):
		_life_splash_tween.kill()
		_life_splash_tween = null
	if _combo_splash_tween != null and is_instance_valid(_combo_splash_tween):
		_combo_splash_tween.kill()
		_combo_splash_tween = null
	if _life_splash != null:
		_life_splash.visible = false
	if _combo_splash != null:
		_combo_splash.visible = false
	_status.text = "踩到雷，本局结束 · 得分 %s" % _format_big_int(_score)
	_retry.disabled = false


func _schedule_on_won() -> void:
	call_deferred("_on_won")


func _on_won() -> void:
	_status.text = "通关！得分 %s · 连击 ×%d" % [_format_big_int(_score), _combo]
	_retry.disabled = false
	if _particles_host != null:
		var vr := get_viewport().get_visible_rect()
		_burst_fireworks(vr.get_center() + Vector2(0, -90), FW_TIER_HEAVY, randf_range(-0.15, 0.15))
		_burst_fireworks(_grid_screen_center(), FW_TIER_MED, randf_range(0.2, 0.45))


func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_level_select_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT)


func _ensure_fw_spark_tex() -> Texture2D:
	if _fw_spark_tex != null:
		return _fw_spark_tex
	var im := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		for x in range(8):
			var d: float = Vector2(float(x) - 3.5, float(y) - 3.5).length()
			var a: float = clampf(1.0 - d / 3.8, 0.0, 1.0)
			im.set_pixel(x, y, Color(1, 1, 1, a))
	_fw_spark_tex = ImageTexture.create_from_image(im)
	return _fw_spark_tex


func _make_firework_cpu(tier: int, hue_warp: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.z_index = 4
	p.texture = _ensure_fw_spark_tex()
	var t: int = clampi(tier, FW_TIER_LIGHT, FW_TIER_HEAVY)
	var amounts: Array = [56, 104, 168]
	var vmaxs: Array = [300.0, 420.0, 580.0]
	p.amount = int(amounts[t])
	p.lifetime = 0.58 + float(t) * 0.1
	p.one_shot = true
	p.explosiveness = 0.94
	p.randomness = 0.26
	p.lifetime_randomness = 0.48
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.spread = 180.0
	p.direction = Vector2(0, -1)
	var vm: float = float(vmaxs[t])
	p.initial_velocity_min = vm * 0.32
	p.initial_velocity_max = vm
	p.angular_velocity_min = -320.0
	p.angular_velocity_max = 320.0
	p.gravity = Vector2(0, 720)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.48 + float(t) * 0.14
	p.hue_variation_min = -0.5 + hue_warp
	p.hue_variation_max = 0.5 + hue_warp
	p.damping_min = 18.0
	p.damping_max = 72.0
	var g := Gradient.new()
	g.add_point(0.0, Color(1, 1, 1, 1))
	g.add_point(0.22, Color(1, 0.45, 0.85, 1))
	g.add_point(0.45, Color(0.45, 0.95, 1.0, 1))
	g.add_point(0.68, Color(0.65, 1.0, 0.55, 1))
	g.add_point(1.0, Color(1, 0.82, 0.35, 0.0))
	p.color_ramp = g
	p.emitting = false
	return p


func _burst_fireworks(screen_pos: Vector2, tier: int, hue_warp: float) -> void:
	if _particles_host == null:
		return
	var p := _make_firework_cpu(tier, hue_warp)
	_particles_host.add_child(p)
	p.position = screen_pos
	p.restart()
	p.emitting = true
	var wait_sec: float = p.lifetime + 0.55
	get_tree().create_timer(wait_sec).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)
