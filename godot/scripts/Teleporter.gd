extends Area2D
class_name Teleporter

# 互動式傳送門：玩家在範圍內按 R → 開啟地圖選目標 → 傳送
# 主要用途：死路盡頭快捷回岔路口（地圖規劃 §9.3）
# 任何**已啟用**的 Teleporter 都可被選為目標——啟用 = 玩家本體曾親身抵達一次
# 不傳送 Clone — body_entered 只認 player_real
# 錄製中由 PlayerController 端 block
#
# 「混合方案」（M14a 順手做、依備忘1 § 五）：
#   首次進入範圍 → GameStats 記錄為 discovered → 後續可作遠傳目標
#   未啟用的傳送門在地圖上顯灰、不可點選
#   單次 session 記憶（GameStats reset 才清）

signal player_entered_zone(teleporter: Teleporter)
signal player_exited_zone(teleporter: Teleporter)

# 可選：在地圖上 hover 時顯示的名稱（空字串則用節點名）
@export var display_name: String = ""

# 未啟用視覺：modulate 較暗、提示玩家「還沒走到過」
const MODULATE_UNDISCOVERED := Color(0.55, 0.55, 0.65, 1.0)
const MODULATE_DISCOVERED := Color(1.0, 1.0, 1.0, 1.0)
const ACTIVATE_FADE_TIME := 0.4


func _ready() -> void:
	add_to_group("teleporter")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 自動向 PlayerController 註冊、讓它接收 zone 信號（不用每個 Teleporter 手連）
	PlayerController.register_teleporter(self)
	# 依當前 GameStats 狀態套初始視覺（同 session 重新進房時保持已啟用樣貌）
	_apply_discovery_visual(GameStats.is_teleporter_discovered(self), false)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		player_entered_zone.emit(self)
		# 首次抵達 → 啟用、播淡入動畫；已啟用則 mark_ 內部 dedupe 不重發 signal
		var was_new: bool = not GameStats.is_teleporter_discovered(self)
		GameStats.mark_teleporter_discovered(self)
		if was_new:
			_apply_discovery_visual(true, true)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player_real"):
		player_exited_zone.emit(self)


# 給 MapOverlay hover 顯示用
func get_label() -> String:
	if display_name != "":
		return display_name
	return name


# 給 MapOverlay 篩選遠傳目標用（GameStats 是 session 來源真相、本函式為便利包裝）
func is_discovered() -> bool:
	return GameStats.is_teleporter_discovered(self)


# 套用 discovered/undiscovered 視覺；animate=true 走 0.4s 淡入（首次抵達瞬間用）
func _apply_discovery_visual(discovered: bool, animate: bool) -> void:
	var visual := get_node_or_null("Visual")
	if visual == null:
		return
	var target: Color = MODULATE_DISCOVERED if discovered else MODULATE_UNDISCOVERED
	if animate:
		var tween := create_tween()
		tween.tween_property(visual, "modulate", target, ACTIVATE_FADE_TIME)
	else:
		visual.modulate = target
