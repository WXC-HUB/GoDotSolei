extends Control

const LevelCatalog := preload("res://scripts/level_catalog.gd")
const _STRIPE_BG := preload("res://scripts/stripe_background.gd")

const MAIN_SCENE := "res://scenes/MainMenu.tscn"
const GAME_SCENE := "res://scenes/Game.tscn"

@onready var _list: VBoxContainer = $Center/Card/VBox/List


func _ready() -> void:
	_STRIPE_BG.attach($Bg as ColorRect, 0.23, 20.0)
	var levels := LevelCatalog.get_levels()
	for i in range(levels.size()):
		var row: Dictionary = levels[i]
		var w: int = int(row.get("width", 0))
		var h: int = int(row.get("height", 0))
		var m: int = int(row.get("mines", 0))
		var title: String = str(row.get("title", "关卡"))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(400, 48)
		btn.text = "%s  %d×%d  雷:%d" % [title, w, h, m]
		var idx := i
		btn.pressed.connect(func() -> void:
			RunConfig.selected_level_index = idx
			get_tree().change_scene_to_file(GAME_SCENE)
		)
		_list.add_child(btn)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
