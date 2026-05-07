@tool
extends Area2D
class_name Spring

# 彈簧：玩家或分身落上時強制向上彈起
# 用戶定位「**移動手段、非謎題核心**」——不參與 signal 連線、固定彈速、純環境設施
# Recording 100% 相容：彈簧改 velocity.y、後續仍走 _physics_process pipeline

@export var bounce_velocity: float = -800.0  # 負 = 向上
@export var size: Vector2 = Vector2(60, 20):
	set(value):
		size = value
		_apply_size()
@export var color: Color = Color(0.3, 0.7, 1.0, 1.0):
	set(value):
		color = value
		_apply_color()

@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")


func _ready() -> void:
	_apply_size()
	_apply_color()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


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


func _apply_color() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	if v != null:
		v.color = color


func _on_body_entered(body: Node2D) -> void:
	# 只對有 apply_bounce 的物體有效（Player 與 Clone 透過繼承）；殘骸無此 method 不彈
	if not body.has_method("apply_bounce"):
		return
	body.apply_bounce(bounce_velocity)
	AudioManager.play_sfx_at("spring_bounce", global_position)
	if anim != null:
		anim.play("compress")
