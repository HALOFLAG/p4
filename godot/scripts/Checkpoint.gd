extends Area2D
class_name Checkpoint

# 旗幟造型重生點（M10）
# 玩家碰到 → 設成本體新的 spawn_position、其他 checkpoint 失活、自己 activate（金黃 + 短暫放大）
# 死亡時 Player.respawn() 會回到最後 active 旗幟的位置

const ACTIVE_COLOR := Color(1, 0.85, 0.3, 1)      # 金黃，已啟用
const INACTIVE_COLOR := Color(0.45, 0.55, 0.7, 0.7)  # 暗藍灰，未啟用
const ACTIVATE_TWEEN_TIME := 0.15

@onready var visual: Node2D = $Visual

var is_active := false


func _ready() -> void:
	add_to_group("checkpoint")
	body_entered.connect(_on_body_entered)
	visual.modulate = INACTIVE_COLOR


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player_real"):
		return
	if is_active:
		return  # 已是當前重生點，不重複觸發
	# 設玩家 spawn
	if body.has_method("set_spawn"):
		body.set_spawn(global_position)
	# 失活其他所有 checkpoint
	for c in get_tree().get_nodes_in_group("checkpoint"):
		if c != self and c.is_active:
			c._deactivate()
	_activate()


func _activate() -> void:
	is_active = true
	visual.modulate = ACTIVE_COLOR
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector2(1.2, 1.2), ACTIVATE_TWEEN_TIME)
	tween.tween_property(visual, "scale", Vector2(1, 1), ACTIVATE_TWEEN_TIME)


func _deactivate() -> void:
	is_active = false
	visual.modulate = INACTIVE_COLOR
