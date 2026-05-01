extends StaticBody2D
class_name Door

# 漸進升降的門：被連結的按鈕按住時慢慢升起，鬆開時慢慢落下
# 視覺用 Polygon2D scale.y 縮減（門從天花板向下「縮回去」）
# 碰撞用 disable 切換（避免縮放 CollisionShape 在 Godot 物理引擎裡的詭異行為）

const OPEN_TIME := 2.0   # 完全開啟需要 2 秒
const CLOSE_TIME := 2.0  # 完全關閉需要 2 秒
const PASS_THROUGH_THRESHOLD := 0.95  # 開到這個比例以上才允許穿過

var open_progress := 0.0  # 0 = 完全關閉、1 = 完全開啟
var should_open := false

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $Collision


# 由按鈕的 pressed_changed signal 呼叫
func set_target(open: bool) -> void:
	should_open = open


func _physics_process(delta: float) -> void:
	var rate := (1.0 / OPEN_TIME) if should_open else -(1.0 / CLOSE_TIME)
	open_progress = clamp(open_progress + rate * delta, 0.0, 1.0)

	# 視覺縮減：scale.y 從 1（完整門）到接近 0（縮回天花板）
	# 留 0.001 避免完全為 0 造成 polygon degenerate
	# 用 maxf（型別 float 版）而非 max，後者回傳 Variant 在嚴格模式會警告
	var s := maxf(1.0 - open_progress, 0.001)
	visual.scale.y = s

	# 碰撞切換：開到 95% 以上才放行（不縮放 CollisionShape，只 toggle disabled）
	collision.disabled = open_progress >= PASS_THROUGH_THRESHOLD
