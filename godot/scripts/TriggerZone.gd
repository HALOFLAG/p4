extends Area2D
class_name TriggerZone

# 謎題區域邊界——本體死亡時用 zone 範圍決定哪些殘骸轉痕跡
# 對應實作用規格書 S12
#
# 用法：每個謎題場景手動放 1 個 TriggerZone 包圍核心區域
# 玩家可同時在多個 zone 內（重疊 zone）；PlayerController 取「最後進入的」當作重置範圍

signal player_entered(zone)
signal player_exited(zone)

@onready var _shape_node: CollisionShape2D = $Collision


func _ready() -> void:
	add_to_group("trigger_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 自動向 PlayerController 註冊，讓它接收進出信號
	PlayerController.register_zone(self)


func _on_body_entered(body: Node2D) -> void:
	# 只認本體（player_real group）；Clone / RecordingProxy 沒在這 group 內
	if body.is_in_group("player_real"):
		player_entered.emit(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		player_exited.emit(self)


# 給 CarcassManager.reset_zone 用：判斷世界座標點是否在本 zone 範圍內
func contains(world_pos: Vector2) -> bool:
	if _shape_node == null or _shape_node.shape == null:
		return false
	var rect := _shape_node.shape as RectangleShape2D
	if rect == null:
		return false
	var local := to_local(world_pos)
	return absf(local.x) <= rect.size.x * 0.5 and absf(local.y) <= rect.size.y * 0.5
