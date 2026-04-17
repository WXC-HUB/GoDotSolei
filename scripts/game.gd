extends Control

const LevelCatalog := preload("res://scripts/level_catalog.gd")
const BoardModel := preload("res://scripts/game/board_model.gd")
const SweeperCell := preload("res://scripts/cell.gd")
const CELL_SCENE := preload("res://scenes/Cell.tscn")
const LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const GAME_SCENE := "res://scenes/Game.tscn"

@onready var _grid: GridContainer = $Margin/VBox/Scroll/BoardGrid
@onready var _status: Label = $Margin/VBox/Toolbar/Status
@onready var _mine_label: Label = $Margin/VBox/MineLabel
@onready var _retry: Button = $Margin/VBox/Toolbar/BtnRetry

var _model: BoardModel
var _cell_nodes: Array = []


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
	_model = BoardModel.new(w, h, mines)
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
	_retry.disabled = true
	_status.text = "左键翻开，右键标记"
	_refresh_mine_label()
	_on_model_changed()


func _on_reveal(x: int, y: int) -> void:
	if _model == null:
		return
	_model.reveal(x, y)


func _on_flag(x: int, y: int) -> void:
	if _model == null:
		return
	_model.toggle_flag(x, y)


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
