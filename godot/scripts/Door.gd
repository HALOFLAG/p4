@tool
extends StaticBody2D
class_name Door

# 漸進升降的門：被連結的按鈕按住時開啟、鬆開時關回
# M14a.4：改用 AnimationPlayer 驅動 visual.scale.y + collision.disabled
# - callback_mode = PHYSICS、保 Recording deterministic
# - 動畫內容定義於 Door.tscn 的 "open" / "close" sub_resource
# - collision.disabled 切換透過 method track 呼叫 _set_collision_disabled、用 set_deferred 避免 physics frame 中改 disabled
# 已知視覺退化（M14a.4 階段）：原本「門下沉入地面」改為「純縮放在頂部」、M14b 補回 position.y 動畫（需依 door_height 參數化）
# 元件化：@tool + @export width / door_height / door_color、Inspector 內可調

const OPEN_TIME := 0.6   # 與 Door.tscn "open" / "close" 動畫 length 一致

# 可調門高（每個 Door 實例 inspector 設定）。需與 Polygon2D 高度、Collision shape size.y 一致
@export var door_height: float = 200.0:
	set(value):
		door_height = value
		_apply_dimensions()

@export var width: float = 60.0:
	set(value):
		width = value
		_apply_dimensions()

@export var door_color: Color = Color(0.6, 0.3, 0.3, 1.0):
	set(value):
		door_color = value
		var v := get_node_or_null("Visual") as Polygon2D
		if v != null:
			v.color = door_color

var should_open := false

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $Collision
@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_apply_dimensions()
	if Engine.is_editor_hint():
		return
	# M14a.4：AnimationPlayer 必須走 PHYSICS callback、保 Recording deterministic
	# Godot 4.3+ enum 已搬到父類 AnimationMixer、舊的 AnimationPlayer.ANIMATION_PROCESS_PHYSICS 不可用
	if anim != null:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS


# 視覺與碰撞依 width / door_height 重新生成
# Polygon: 從 (x=-w/2, y=0) 到 (x=w/2, y=h) — 門「頂部」對齊節點原點
# Collision: position (0, h/2)，shape size (w, h) — 門「中心」對齊
# 門關閉時 visual.position.y=0、scale.y=1；開啟時 position.y→h、scale.y→0（沉入地面）
func _apply_dimensions() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	var c := get_node_or_null("Collision") as CollisionShape2D
	if v == null or c == null:
		return
	var hx: float = width * 0.5
	v.polygon = PackedVector2Array([
		Vector2(-hx, 0), Vector2(hx, 0),
		Vector2(hx, door_height), Vector2(-hx, door_height)
	])
	c.position = Vector2(0, door_height * 0.5)
	if c.shape is RectangleShape2D:
		(c.shape as RectangleShape2D).size = Vector2(width, door_height)
	else:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(width, door_height)
		c.shape = rect


# 由按鈕的 pressed_changed signal 呼叫
# M14a.4：用 anim.play() 取代 _physics_process 手刻、collision.disabled 由動畫 method track 切換
# 反轉處理：若動畫進行中切方向、用 seek 從鏡像位置繼續、保視覺連續
func set_target(open: bool) -> void:
	if open == should_open:
		return  # 狀態未變、不重觸發
	# 播 SFX 只在「關 → 開」轉換、避免 AND-gate 多次連發
	if open:
		AudioManager.play_sfx_at("door_open", global_position)
	should_open = open
	if anim == null:
		return
	# 捕捉前一動畫的位置（用於鏡像反轉）
	var prev_pos := anim.current_animation_position if anim.is_playing() else 0.0
	if open:
		anim.play("open")
	else:
		anim.play("close")
	# 鏡像反轉：從上一動畫進度的鏡像位置繼續播放、避免視覺跳變
	if prev_pos > 0 and prev_pos < OPEN_TIME:
		anim.seek(OPEN_TIME - prev_pos, true)


# 由 Door.tscn 內 AnimationPlayer 的 method track 呼叫
# 用 set_deferred 避免在 physics frame 中改 disabled（broadphase 同步問題）
# "open" 動畫於 t=0.6 呼叫 _set_collision_disabled(true)、"close" 動畫於 t=0.0 呼叫 _set_collision_disabled(false)
func _set_collision_disabled(value: bool) -> void:
	if collision != null:
		collision.set_deferred("disabled", value)
