@tool
extends StaticBody2D
class_name Floor

# 可重用地板元件：用於房間底部的長條地面、Inspector 內調整 size、color
# 用法：拖 Floor.tscn 進關卡 → 調整 size 跨距 → 完成
# 預設 1280×40 對應一個房間寬度的整段地面、純地形無動畫需求


@export var size: Vector2 = Vector2(1280, 40):
	set(value):
		size = value
		_apply_size()

@export var color: Color = Color(0.35, 0.3, 0.28, 1.0):
	set(value):
		color = value
		_apply_color()


func _ready() -> void:
	_apply_size()
	_apply_color()


func _apply_size() -> void:
	var visual := get_node_or_null("Visual") as Polygon2D
	var collision := get_node_or_null("Collision") as CollisionShape2D
	if visual == null or collision == null:
		return
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy)
	])
	if collision.shape is RectangleShape2D:
		(collision.shape as RectangleShape2D).size = size
	else:
		var rect := RectangleShape2D.new()
		rect.size = size
		collision.shape = rect


func _apply_color() -> void:
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual != null:
		visual.color = color
