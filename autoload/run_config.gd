extends Node

const _UI_FONT := "res://fonts/NotoSansSC-Regular.otf"

## 关卡在 LevelCatalog 中的下标，由选关页写入、游戏页读取。
var selected_level_index: int = 0


func _ready() -> void:
	# 全局回退字体：覆盖 Web/无系统中文轮廓的环境，以及代码里动态创建的控件。
	if ResourceLoader.exists(_UI_FONT):
		var f: Variant = load(_UI_FONT)
		if f is Font:
			ThemeDB.fallback_font = f
