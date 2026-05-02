extends Node2D

# World 主場景根節點（M10）
# Room 2: 單按鈕→門
# Room 3: clone 按鈕→門
# Room 4: 雙按鈕（左上 + 右上）→ 門（AND 邏輯，需兩個分身同時按住）

@onready var room2_button: PressButton = $Room2/Button
@onready var room2_door: Door = $Room2/Door2
@onready var room3_button: PressButton = $Room3/Button
@onready var room3_door: Door = $Room3/Door
@onready var room4_button_left: PressButton = $Room4/ButtonLeft
@onready var room4_button_right: PressButton = $Room4/ButtonRight
@onready var room4_door: Door = $Room4/Door
@onready var room4_exit: Exit = $Room4/Exit

var _r4_left_pressed := false
var _r4_right_pressed := false


func _ready() -> void:
	room2_button.pressed_changed.connect(room2_door.set_target)
	room3_button.pressed_changed.connect(room3_door.set_target)
	room4_button_left.pressed_changed.connect(_on_r4_left_changed)
	room4_button_right.pressed_changed.connect(_on_r4_right_changed)
	room4_exit.reached.connect(_on_exit_reached)


# Room 4 AND-gate：兩個按鈕都按住才開門
func _on_r4_left_changed(p: bool) -> void:
	_r4_left_pressed = p
	_update_r4_door()


func _on_r4_right_changed(p: bool) -> void:
	_r4_right_pressed = p
	_update_r4_door()


func _update_r4_door() -> void:
	room4_door.set_target(_r4_left_pressed and _r4_right_pressed)


func _on_exit_reached() -> void:
	print("[WORLD] 教學通關！")
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.5, 0.2)
	tw.tween_property(flash, "color:a", 0.0, 1.2)
