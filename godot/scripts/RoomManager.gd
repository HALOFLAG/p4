extends Node

# 房間制鏡頭管理器（autoload）
# 對應 M10：Q1 一房一鏡頭
#
# 流程：
#   1. Room.tscn 透過 Bounds Area2D 偵測玩家進出 → 通知 RoomManager
#   2. RoomManager 在「玩家進入新房間」時 tween 當前 active Camera2D 到該房間 CameraTarget
#
# Camera2D 透過 Viewport.get_camera_2d() 自動取得，無須註冊
# 多房同時觸發時取「最後進入的」當 current_room（玩家在門口邊緣 race 的處理）
# Room 型別用 Node 而非 Room class——避免 autoload 載入順序與 class_name 註冊的循環

const TRANSITION_TIME := 0.4

var current_room: Node = null
var _player_rooms: Array = []  # 玩家當前所在的所有 room（疊加）
var _transition_tween: Tween = null


# 透過 Viewport 取當前 active Camera2D（無須在場景中手動註冊）
func _get_camera() -> Camera2D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_2d()


# Room.gd 偵測到玩家進入時呼叫
func player_entered_room(room: Node) -> void:
	if not room in _player_rooms:
		_player_rooms.append(room)
	_switch_to(room)


# Room.gd 偵測到玩家離開時呼叫
func player_exited_room(room: Node) -> void:
	_player_rooms.erase(room)
	# 若玩家還在其他 room 內、且離開的是 current → 切到剩下最後一個
	if not _player_rooms.is_empty() and current_room == room:
		_switch_to(_player_rooms[-1])


func _switch_to(room: Node) -> void:
	if room == current_room:
		return
	current_room = room
	var cam := _get_camera()
	if cam == null:
		return
	# 中斷上一個 tween 避免疊加
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	var target: Vector2 = room.camera_target.global_position
	_transition_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(cam, "global_position", target, TRANSITION_TIME)
