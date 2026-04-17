extends Node

## 可选：将授权字体放到 res://fonts/ 后在此填写路径，会设为 ThemeDB.fallback_font（优先于内置 SystemFont 回退）。
const OPTIONAL_BUNDLED_UI_FONT := ""

## 关卡在 LevelCatalog 中的下标，由选关页写入、游戏页读取。
var selected_level_index: int = 0


func _ready() -> void:
	# 全局回退：Web/动态控件在无主题字体时仍能解析中文；若仓库内自带 TTF 则优先用文件（便于与 CI 一致）。
	if OPTIONAL_BUNDLED_UI_FONT != "" and ResourceLoader.exists(OPTIONAL_BUNDLED_UI_FONT):
		var f: Variant = load(OPTIONAL_BUNDLED_UI_FONT)
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
