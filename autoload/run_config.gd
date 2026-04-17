extends Node

## 与 themes/app_theme.tres 一致：打包字体，Web/CI 无系统中文轮廓时仍正常显示。
const BUNDLED_UI_FONT := "res://fonts/ALIBABAPUHUITI-3-105-HEAVY.TTF"

## 关卡在 LevelCatalog 中的下标，由选关页写入、游戏页读取。
var selected_level_index: int = 0


func _ready() -> void:
	if ResourceLoader.exists(BUNDLED_UI_FONT):
		var f: Variant = load(BUNDLED_UI_FONT)
		if f is Font:
			ThemeDB.fallback_font = f
			return
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"PingFang SC",
		"Noto Sans CJK SC",
		"Noto Sans SC",
		"Source Han Sans SC",
		"Segoe UI",
		"sans-serif",
	])
	sf.font_weight = 500
	ThemeDB.fallback_font = sf
