@tool
extends StaticBody2D
class_name Platform

# 可重用平台元件：Inspector 內調整 size、color，編輯器即時同步 Polygon 與 Collision
# 用法：拖 Platform.tscn 進關卡 → 設定 size & color → 完成
# 高度只支援矩形；如需異形（5 邊以上、有缺口）請保留 inline StaticBody2D


@export var size: Vector2 = Vector2(200, 30):
	set(value):
		size = value
		_apply_size()

@export var color: Color = Color(0.45, 0.45, 0.5, 1.0):
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
