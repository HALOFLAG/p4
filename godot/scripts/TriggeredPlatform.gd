@tool
extends AnimatableBody2D
class_name TriggeredPlatform

# 觸發式平台：被 signal 驅動移動的平台（按鈕 / 拉桿 / 邏輯閘輸出）
# AnimatableBody2D 讓踩在上面的 CharacterBody2D（Player / Clone）自動跟著走
# 移動由 _physics_process 線性內插（與 _physics_process 同步、deterministic 100%）
# M14a.4 完成 AnimationPlayer 一致性驗證後可考慮換 AnimationPlayer
#
# 設計用途：
#   movement = Vector2(0, -200) → 沉降式（往上升降）
#   movement = Vector2(200, 0)  → 直線水平移動
#
# 連線：在房間 .tscn 內 connect button.pressed_changed → platform.set_target

@export var movement: Vector2 = Vector2(0, -200):  # 從 start position 偏移到 target
	set(value):
		movement = value
@export var move_duration: float = 1.0  # 移動時間（秒）
@export var size: Vector2 = Vector2(200, 30):
	set(value):
		size = value
		_apply_size()
@export var color: Color = Color(0.55, 0.45, 0.3, 1.0):
	set(value):
		color = value
		_apply_color()

var _start_position: Vector2
var _target_position: Vector2
var _progress: float = 0.0          # 0 = at start, 1 = at target
var _moving_to_target: bool = false  # true = 向 target 動、false = 向 start 動


func _ready() -> void:
	_apply_size()
	_apply_color()
	if Engine.is_editor_hint():
		return
	_start_position = position
	_target_position = position + movement
	add_to_group("triggered_platform")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var target_progress: float = 1.0 if _moving_to_target else 0.0
	if _progress == target_progress:
		return  # 已到位、不必更新
	# 推進 progress
	var step: float = delta / move_duration
	if _moving_to_target:
		_progress = minf(_progress + step, 1.0)
	else:
		_progress = maxf(_progress - step, 0.0)
	# 等速移動（linear、無 ease）：避免中段速度峰值給玩家過大繼承速度
	# 副作用：起停會「全速啟動 / 突然停止」、無柔順感、但符合可預期物理
	position = _start_position.lerp(_target_position, _progress)


# 由按鈕 (pressed_changed) / 拉桿 (state_changed) / 邏輯閘 (output_changed) signal 呼叫
# active=true：移到 target；active=false：回 start
func set_target(active: bool) -> void:
	_moving_to_target = active


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
