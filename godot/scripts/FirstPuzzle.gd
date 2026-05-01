extends Node2D

# 第一個必經教學謎題的場景根節點
# 負責：把按鈕連到門、偵測通關、播一個簡單的勝利淡白

@onready var button: PressButton = $Button
@onready var door: Door = $Door
@onready var exit: Exit = $Exit


func _ready() -> void:
	button.pressed_changed.connect(door.set_target)
	exit.reached.connect(_on_exit_reached)


func _on_exit_reached() -> void:
	print("[PUZZLE] 第一謎題通關！")
	# 簡單的螢幕淡白（原型階段的「儀式感」最小版本）
	var canvas := CanvasLayer.new()
	canvas.layer = 100  # 蓋在 HUD 之上
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
