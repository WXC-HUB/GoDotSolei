extends Button

const BoardModel := preload("res://scripts/game/board_model.gd")

signal reveal_requested(gx: int, gy: int)
signal flag_requested(gx: int, gy: int)

var grid_x: int = 0
var grid_y: int = 0


func setup(gx: int, gy: int) -> void:
	grid_x = gx
	grid_y = gy


func _ready() -> void:
	custom_minimum_size = Vector2(28, 28)
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	reveal_requested.emit(grid_x, grid_y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		flag_requested.emit(grid_x, grid_y)
		accept_event()


func update_from_model(m: BoardModel) -> void:
	disabled = m.ended
	if m.is_flagged(grid_x, grid_y) and not m.is_revealed(grid_x, grid_y):
		text = "F"
		modulate = Color(0.9, 0.3, 0.3)
		return
	if not m.is_revealed(grid_x, grid_y):
		text = ""
		modulate = Color.WHITE
		return
	if m.get_item(grid_x, grid_y) == BoardModel.ItemType.MINE:
		text = "*"
		modulate = Color(1, 0.2, 0.2)
		return
	var n := m.adjacent_mine_count(grid_x, grid_y)
	text = str(n) if n > 0 else ""
	modulate = Color(0.15, 0.35, 0.85) if n > 0 else Color(0.75, 0.75, 0.78)
