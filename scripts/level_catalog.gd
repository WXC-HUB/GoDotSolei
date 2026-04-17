static func get_levels() -> Array:
	var path := "res://data/levels.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法读取关卡数据: " + path)
		return []
	var text := f.get_as_text()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_ARRAY:
		push_error("levels.json 格式应为数组")
		return []
	return data
