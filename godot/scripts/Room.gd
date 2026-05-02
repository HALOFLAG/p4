extends Node2D
class_name Room

# 一個「房間」= 視覺單位（鏡頭一個房間鎖一個）+ 邏輯容器
# 對應 M10：Q1 房間制鏡頭
#
# 用法：把這個場景拖到 World.tscn、加自己的內容（牆、按鈕、checkpoint、sign 等）
# Bounds 覆蓋整個房間範圍，玩家進出時通知 RoomManager 切換鏡頭

@onready var bounds: Area2D = $Bounds
@onready var camera_target: Marker2D = $CameraTarget
@onready var _bounds_shape: CollisionShape2D = $Bounds/CollisionShape2D


# 給 PlayerController 用：判斷世界座標點是否在本房間範圍內
# （proxy 跨房時自動結束錄製需要這個 API）
func contains(world_pos: Vector2) -> bool:
	if _bounds_shape == null or _bounds_shape.shape == null:
		return false
	var rect := _bounds_shape.shape as RectangleShape2D
	if rect == null:
		return false
	var local := bounds.to_local(world_pos)
	return absf(local.x) <= rect.size.x * 0.5 and absf(local.y) <= rect.size.y * 0.5


func _ready() -> void:
	add_to_group("room")
	bounds.body_entered.connect(_on_body_entered)
	bounds.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		RoomManager.player_entered_room(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		RoomManager.player_exited_room(self)
