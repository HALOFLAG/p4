@tool
extends Area2D
class_name Lever

# 拉桿（跨壓觸發版）：玩家或分身路過 → toggle 狀態
# 與按鈕互補：按鈕需持續站著、拉桿瞬間 toggle 然後保持狀態（latch）
# 含 0.5s 冷卻避免抖動（玩家連續走過時不會反覆切換）
#
# 設計約定：分身死亡時拉桿狀態不回退（與 PressCounter 達標 latch 一致）

signal state_changed(is_on: bool)

const COOLDOWN_TIME := 0.5  # 拉一次後 0.5 秒不可再切

@export var initial_state: bool = false:
	set(value):
		initial_state = value
		# 編輯器：即時預覽；Runtime：_ready 已用 initial_state 初始化、setter 不重置
		if Engine.is_editor_hint():
			is_on = value
			_apply_visual()

@export var color_on: Color = Color(0.3, 0.85, 0.3, 1.0):
	set(value):
		color_on = value
		_apply_visual()

@export var color_off: Color = Color(0.5, 0.5, 0.55, 1.0):
	set(value):
		color_off = value
		_apply_visual()

@export var size: Vector2 = Vector2(40, 60):
	set(value):
		size = value
		_apply_size()

var is_on: bool = false
var _cooldown_timer: float = 0.0


func _ready() -> void:
	is_on = initial_state
	_apply_size()
	_apply_visual()
	if Engine.is_editor_hint():
		return
	add_to_group("lever")
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)


func _on_body_entered(body: Node2D) -> void:
	# 只接受角色（玩家/分身）；殘骸不觸發拉桿
	if not (body is CharacterBody2D):
		return
	if _cooldown_timer > 0.0:
		return  # 冷卻中、忽略
	_toggle()


func _toggle() -> void:
	is_on = not is_on
	_cooldown_timer = COOLDOWN_TIME
	state_changed.emit(is_on)
	_apply_visual()
	AudioManager.play_sfx_at("lever_toggle", global_position)
	print("[LEVER] %s toggle → %s" % [name, "ON" if is_on else "OFF"])


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


func _apply_visual() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	if v != null:
		v.color = color_on if is_on else color_off
