extends Control

const _STRIPE_BG := preload("res://scripts/stripe_background.gd")


func _ready() -> void:
	_STRIPE_BG.attach($Bg as ColorRect, 0.19, 22.0)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/LevelSelect.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
