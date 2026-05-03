extends StaticBody2D
class_name Door

# 漸進升降的門：被連結的按鈕按住時慢慢開啟，鬆開時慢慢關回
# 視覺：top 向下沉、bottom 不動（門從上方往下縮減直到消失，像沉入地面）
# 碰撞用 disable 切換（避免縮放 CollisionShape 在 Godot 物理引擎裡的詭異行為）

const OPEN_TIME := 0.6   # 完全開啟需要 0.6 秒（縮短：原 2.0 → 0.6 配合嚴格實體）
const CLOSE_TIME := 0.6  # 完全關閉需要 0.6 秒
const PASS_THROUGH_THRESHOLD := 1.0  # 嚴格實體：必須完全沉入地面才允許穿過、消除穿模

# 可調門高（每個 Door 實例 inspector 設定）。需與 Polygon2D 高度、Collision shape size.y 一致
@export var door_height: float = 200.0

var open_progress := 0.0  # 0 = 完全關閉、1 = 完全開啟
var should_open := false

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $Collision


# 由按鈕的 pressed_changed signal 呼叫
func set_target(open: bool) -> void:
	# 播 SFX 只在「關 → 開」轉換、避免 AND-gate 多次連發
	if open and not should_open:
		AudioManager.play_sfx_at("door_open", global_position)
	should_open = open


func _physics_process(delta: float) -> void:
	var rate := (1.0 / OPEN_TIME) if should_open else -(1.0 / CLOSE_TIME)
	open_progress = clamp(open_progress + rate * delta, 0.0, 1.0)

	# 從上方往下縮減：visual.position.y 下沉、scale.y 縮小
	# 起始：position.y=0, scale.y=1 → polygon 顯示 [0, door_height]
	# 結束：position.y=door_height, scale.y≈0 → polygon 崩塌在 bottom
	# 視覺結果：top 從 y=0 沉到 y=door_height 與 bottom 重合，整扇門「沉入地面」
	visual.position.y = open_progress * door_height
	visual.scale.y = maxf(1.0 - open_progress, 0.001)

	# 碰撞切換：必須完全開啟（100%）才放行，視覺與碰撞 1:1 對齊、無穿模
	# 不縮放 CollisionShape、只 toggle disabled
	collision.disabled = open_progress >= PASS_THROUGH_THRESHOLD
