extends Area2D
class_name Teleporter

# 互動式傳送門：玩家在範圍內按 R → 開啟地圖選目標 → 傳送
# 主要用途：死路盡頭快捷回岔路口（地圖規劃 §9.3）
# 任何一個 Teleporter 都可被選為目標——目的地由地圖 UI 上玩家點選決定
# 不傳送 Clone — body_entered 只認 player_real
# 錄製中由 PlayerController 端 block

signal player_entered_zone(teleporter: Teleporter)
signal player_exited_zone(teleporter: Teleporter)

# 可選：在地圖上 hover 時顯示的名稱（空字串則用節點名）
@export var display_name: String = ""


func _ready() -> void:
	add_to_group("teleporter")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 自動向 PlayerController 註冊、讓它接收 zone 信號（不用每個 Teleporter 手連）
	PlayerController.register_teleporter(self)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		player_entered_zone.emit(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		player_exited_zone.emit(self)


# 給 MapOverlay hover 顯示用
func get_label() -> String:
	if display_name != "":
		return display_name
	return name
