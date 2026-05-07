@tool
extends StaticBody2D
class_name CrumblingPlatform

# 崩落平台：玩家或分身踩上 → CRUMBLE_TIME 秒後消失
# 採 (c) checkpoint reset 語意：碰旗幟（含死亡 respawn 落點）時恢復原狀
# 與 PressCounter.reset_on_checkpoint 同模式：deferred 連 Checkpoint.touched signal
#
# Recording 一致性：
#   _physics_process 推進 timer（deterministic）
#   Clone 重現時平台仍會崩、下一次 checkpoint 觸發 reset
#   多次重現之間：每次重現開始前 reset 應已完成（透過 checkpoint）

signal crumbled
signal restored

const CRUMBLE_TIME := 0.5  # 踩上後多久消失

@export var size: Vector2 = Vector2(200, 30):
	set(value):
		size = value
		_apply_size()
@export var color: Color = Color(0.5, 0.4, 0.3, 1.0):
	set(value):
		color = value
		_apply_color()

var _is_crumbling: bool = false
var _is_collapsed: bool = false
var _crumble_timer: float = 0.0


func _ready() -> void:
	_apply_size()
	_apply_color()
	if Engine.is_editor_hint():
		return
	add_to_group("crumbling_platform")
	# StaticBody2D 沒有 body_entered；改用子節點 DetectArea (Area2D) 偵測
	# 這個 Area2D 在 .tscn 內以同尺寸 collision 配置
	var area := get_node_or_null("DetectArea") as Area2D
	if area != null:
		area.body_entered.connect(_on_body_entered)
	# 連 Checkpoint reset（deferred 確保 Checkpoint._ready 已加入 group）
	call_deferred("_setup_checkpoint_connections")


func _setup_checkpoint_connections() -> void:
	for cp in get_tree().get_nodes_in_group("checkpoint"):
		if cp.has_signal("touched"):
			cp.touched.connect(_reset_to_initial)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_crumbling:
		return
	_crumble_timer = maxf(_crumble_timer - delta, 0.0)
	# 視覺警告：alpha 隨倒數淡化（1.0 → 0.3）
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual != null:
		visual.modulate.a = 0.3 + 0.7 * (_crumble_timer / CRUMBLE_TIME)
	if _crumble_timer <= 0.0:
		_collapse()


func _on_body_entered(body: Node2D) -> void:
	if _is_crumbling or _is_collapsed:
		return
	if not (body is CharacterBody2D):
		return  # 殘骸不觸發
	_start_crumbling()


func _start_crumbling() -> void:
	_is_crumbling = true
	_crumble_timer = CRUMBLE_TIME
	AudioManager.play_sfx_at("crumble_warning", global_position)
	print("[CRUMBLE] %s 倒數 %.1fs" % [name, CRUMBLE_TIME])


func _collapse() -> void:
	_is_crumbling = false
	_is_collapsed = true
	var collision := get_node_or_null("Collision") as CollisionShape2D
	var visual := get_node_or_null("Visual") as Polygon2D
	# 用 set_deferred 避免在 physics frame 中改 disabled 導致狀態不同步
	if collision != null:
		collision.set_deferred("disabled", true)
	if visual != null:
		visual.modulate.a = 0.0
	AudioManager.play_sfx_at("crumble_collapse", global_position)
	crumbled.emit()
	print("[CRUMBLE] %s 崩塌" % name)


func _reset_to_initial() -> void:
	if not _is_crumbling and not _is_collapsed:
		return  # 已是初始狀態、不必動
	_is_crumbling = false
	_is_collapsed = false
	_crumble_timer = 0.0
	var collision := get_node_or_null("Collision") as CollisionShape2D
	var visual := get_node_or_null("Visual") as Polygon2D
	# 用 set_deferred：被 Checkpoint.touched signal 呼叫時、處於 physics frame 內、
	# 直接改 disabled 物理引擎可能還未 rebuild、玩家會穿過「視覺看起來實心」的平台。
	# set_deferred 保證下一 idle frame 才套用、broadphase 會正確更新
	if collision != null:
		collision.set_deferred("disabled", false)
	if visual != null:
		visual.modulate.a = 1.0
	restored.emit()
	print("[CRUMBLE] %s 恢復" % name)


func _apply_size() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	var c := get_node_or_null("Collision") as CollisionShape2D
	var area_c := get_node_or_null("DetectArea/CollisionShape2D") as CollisionShape2D
	if v == null or c == null:
		return
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	v.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy)
	])
	# 主 collision（StaticBody2D 用、給玩家踩）
	if c.shape is RectangleShape2D:
		(c.shape as RectangleShape2D).size = size
	else:
		var rect := RectangleShape2D.new()
		rect.size = size
		c.shape = rect
	# DetectArea collision（Area2D 用、給 body_entered 觸發；略大一點包含上方）
	if area_c != null:
		var area_size := Vector2(size.x, size.y + 10)  # 上方多 10px、踩上更易觸發
		if area_c.shape is RectangleShape2D:
			(area_c.shape as RectangleShape2D).size = area_size
		else:
			var rect := RectangleShape2D.new()
			rect.size = area_size
			area_c.shape = rect


func _apply_color() -> void:
	var v := get_node_or_null("Visual") as Polygon2D
	if v != null:
		v.color = color
