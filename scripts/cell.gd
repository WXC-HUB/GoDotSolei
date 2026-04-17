extends Button

const BoardModel := preload("res://scripts/game/board_model.gd")

signal reveal_requested(gx: int, gy: int)
signal flag_requested(gx: int, gy: int)

## 经典扫雷数字配色（1–8）
const NUMBER_COLORS: Array[Color] = [
	Color(), ## 占位 0
	Color(0.22, 0.45, 0.92),
	Color(0.18, 0.62, 0.32),
	Color(0.88, 0.28, 0.28),
	Color(0.28, 0.28, 0.75),
	Color(0.62, 0.22, 0.22),
	Color(0.2, 0.68, 0.72),
	Color(0.15, 0.15, 0.18),
	Color(0.45, 0.45, 0.5),
]

var grid_x: int = 0
var grid_y: int = 0

var _style_covered: StyleBoxFlat
var _style_covered_hover: StyleBoxFlat
var _style_open: StyleBoxFlat
var _style_open_dim: StyleBoxFlat
var _style_flag: StyleBoxFlat
var _style_mine: StyleBoxFlat


func setup(gx: int, gy: int) -> void:
	grid_x = gx
	grid_y = gy


func _ready() -> void:
	## flat=true 时引擎常不绘制 normal 的 StyleBox，格子会像消失一样不可见。
	flat = false
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(30, 30)
	add_theme_font_size_override("font_size", 15)
	_build_styles()
	_apply_covered_look()
	pressed.connect(_on_pressed)


func _sb(bg: Color, border: Color, radius: int = 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(radius)
	return s


func _build_styles() -> void:
	_style_covered = _sb(Color(0.4, 0.44, 0.55), Color(0.55, 0.6, 0.72))
	_style_covered_hover = _sb(Color(0.48, 0.52, 0.64), Color(0.62, 0.66, 0.78))
	_style_open = _sb(Color(0.24, 0.26, 0.33), Color(0.38, 0.42, 0.52))
	_style_open_dim = _sb(Color(0.2, 0.22, 0.28), Color(0.32, 0.36, 0.44))
	_style_flag = _sb(Color(0.42, 0.36, 0.28), Color(0.78, 0.62, 0.35))
	_style_mine = _sb(Color(0.52, 0.22, 0.26), Color(0.78, 0.35, 0.38))


func _set_tile_style(base: StyleBoxFlat) -> void:
	add_theme_stylebox_override("normal", base)
	add_theme_stylebox_override("hover", base)
	add_theme_stylebox_override("pressed", base)
	add_theme_stylebox_override("disabled", base)


func _apply_covered_look() -> void:
	add_theme_stylebox_override("normal", _style_covered)
	add_theme_stylebox_override("hover", _style_covered_hover)
	add_theme_stylebox_override("pressed", _style_covered_hover)
	add_theme_stylebox_override("disabled", _style_covered)


func _on_pressed() -> void:
	reveal_requested.emit(grid_x, grid_y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		flag_requested.emit(grid_x, grid_y)
		accept_event()


func update_from_model(m: BoardModel) -> void:
	disabled = m.ended
	remove_theme_color_override("font_color")
	remove_theme_color_override("font_hover_color")
	remove_theme_color_override("font_pressed_color")
	if m.is_flagged(grid_x, grid_y) and not m.is_revealed(grid_x, grid_y):
		text = "F"
		add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
		_set_tile_style(_style_flag)
		return
	if not m.is_revealed(grid_x, grid_y):
		text = ""
		_apply_covered_look()
		add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
		return
	if m.get_item(grid_x, grid_y) == BoardModel.ItemType.MINE:
		text = "●"
		add_theme_color_override("font_color", Color(1, 0.85, 0.85))
		_set_tile_style(_style_mine)
		return
	var n: int = m.adjacent_mine_count(grid_x, grid_y)
	text = str(n) if n > 0 else ""
	var open_style: StyleBoxFlat = _style_open_dim if n == 0 else _style_open
	_set_tile_style(open_style)
	if n > 0 and n < NUMBER_COLORS.size():
		var c: Color = NUMBER_COLORS[n]
		add_theme_color_override("font_color", c)
		add_theme_color_override("font_hover_color", c)
		add_theme_color_override("font_pressed_color", c)
	else:
		add_theme_color_override("font_color", Color(0.5, 0.52, 0.58))
