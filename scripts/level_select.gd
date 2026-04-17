extends Control

const LevelCatalog := preload("res://scripts/level_catalog.gd")

const MAIN_SCENE := "res://scenes/MainMenu.tscn"
const GAME_SCENE := "res://scenes/Game.tscn"

@onready var _list: VBoxContainer = $Center/VBox/List


func _ready() -> void:
	var levels := LevelCatalog.get_levels()
	for i in range(levels.size()):
		var row: Dictionary = levels[i]
		var w: int = int(row.get("width", 0))
		var h: int = int(row.get("height", 0))
		var m: int = int(row.get("mines", 0))
		var title: String = str(row.get("title", "关卡"))
		var btn := Button.new()
		btn.text = "%s  %d×%d  雷:%d" % [title, w, h, m]
		var idx := i
		btn.pressed.connect(func() -> void:
			RunConfig.selected_level_index = idx
			get_tree().change_scene_to_file(GAME_SCENE)
		)
		_list.add_child(btn)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
