@tool
extends Hazard
class_name HazardZone

# 矩形致死區：可在 Inspector 調整 size，編輯器內即時更新
# 用於 death band（掉落致死）、岩漿、酸液等大面積危險區
# 視覺有半透明色塊；要隱形（如世界邊界 death band）可把 visual color alpha 設 0


@export var size: Vector2 = Vector2(200, 40):
	set(value):
		size = value
		_apply_size()

@export var visual_color: Color = Color(0.85, 0.2, 0.25, 0.3):
	set(value):
		visual_color = value
		var v := get_node_or_null("Visual") as Polygon2D
		if v != null:
			v.color = visual_color


func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	# Hazard.gd 會接 body_entered；不在 editor 跑
	super._ready()


func _apply_size() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	var c := get_node_or_null("Collision") as CollisionShape2D
	if v == null or c == null:
		return
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	v.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy)
	])
	if c.shape is RectangleShape2D:
		(c.shape as RectangleShape2D).size = size
	else:
		var rect := RectangleShape2D.new()
		rect.size = size
		c.shape = rect
