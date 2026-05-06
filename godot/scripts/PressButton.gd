@tool
extends Area2D
class_name PressButton

# 重量感應按鈕：當有 CharacterBody2D（玩家/分身）或物理殘骸站在上面時觸發
# M8：殘骸（StaticBody2D 在 "physical_carcass" group）也算重量
# 元件化：@tool + @export width / color，Inspector 內即時調整尺寸與顏色

signal pressed_changed(is_pressed: bool)

# 視覺壓下動畫
const PRESS_DEPTH := 6.0    # 被壓下時 visual 下沉像素
const PRESS_TIME := 0.08    # 壓下/回升 tween 時間

# 預設按鈕寬度 60 / 高度 30；視覺高度為 20（碰撞略大方便觸發）
@export var width: float = 60.0:
	set(value):
		width = value
		_apply_dimensions()

@export var color: Color = Color(0.85, 0.6, 0.2, 1.0):
	set(value):
		color = value
		var v := get_node_or_null("Visual") as Polygon2D
		if v != null:
			v.color = color

@onready var visual: Polygon2D = $Visual

var bodies_on := 0
var _press_tween: Tween = null


func _ready() -> void:
	_apply_dimensions()
	if Engine.is_editor_hint():
		return
	# M8：mask 統一覆蓋——Player(1) + Clone(2) + 所有殘骸 layer (124) = 127
	# 蓋掉 .tscn 的 3，避免每個按鈕場景手動更新
	collision_mask = 3 + PhysicalCarcass.ALL_CARCASS_LAYERS
	# Room 6：給 PressCounter 用 group 掃所有按鈕
	add_to_group("press_button")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _apply_dimensions() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	var c := get_node_or_null("Collision") as CollisionShape2D
	if v == null or c == null:
		return
	var hx: float = width * 0.5
	# 視覺 width × 20（高 20）
	v.polygon = PackedVector2Array([
		Vector2(-hx, -10), Vector2(hx, -10),
		Vector2(hx, 10), Vector2(-hx, 10)
	])
	# 碰撞 width × 30（略高方便觸發）
	if c.shape is RectangleShape2D:
		(c.shape as RectangleShape2D).size = Vector2(width, 30)
	else:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(width, 30)
		c.shape = rect


# 接受角色（玩家/分身）+ 物理殘骸；過濾掉地板/牆等世界靜態
func _accepts_body(body: Node2D) -> bool:
	return body is CharacterBody2D or body.is_in_group("physical_carcass")


func _on_body_entered(body: Node2D) -> void:
	if not _accepts_body(body):
		return
	bodies_on += 1
	if bodies_on == 1:
		pressed_changed.emit(true)
		_animate_press(PRESS_DEPTH)
		GameStats.button_press_count += 1
		AudioManager.play_sfx_at("button_press", global_position)
		print("[BUTTON] 按下")


func _on_body_exited(body: Node2D) -> void:
	if not _accepts_body(body):
		return
	bodies_on -= 1
	if bodies_on == 0:
		pressed_changed.emit(false)
		_animate_press(0.0)
		print("[BUTTON] 鬆開")


func is_pressed() -> bool:
	return bodies_on > 0


# Visual 下沉/回升動畫（kill 重觸發時前一個 tween，避免疊加）
func _animate_press(target_y: float) -> void:
	if visual == null:
		return
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(visual, "position:y", target_y, PRESS_TIME)
