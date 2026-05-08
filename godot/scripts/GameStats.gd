extends Node

# 全域玩家行為累計（autoload）
# 結局 UI 從這裡讀數字、依組合給變體對白
# 沉默累計、不顯示在 HUD（避免玩家為刷數字而玩）

var button_press_count := 0          # 按鈕被踩下次數（含玩家、分身、殘骸）
var death_count := 0                 # 本體死亡次數
var clone_summon_count := 0          # 召喚分身次數
var recording_completed_count := 0   # 完成錄製次數（含 A3 自然存槽，不含太短被丟）
var carcass_spawn_count := 0         # 物理殘骸生成次數
var play_time_seconds := 0.0         # 遊戲時長（秒）

# === 傳送門「混合方案」啟用狀態（M14a 順手做）===
# 玩家親身抵達過的傳送門 ID 集合 → 之後可從地圖內遠傳到此處
# 依據：備忘1 § 五 + M14a + M15 階段詳細說明.md § M14a 第 5 點
# 範圍：單次遊戲 session 記憶、不寫存檔（M16 才做存檔）；reset() 會清空
# Key 用 NodePath（場景樹絕對路徑、跨房間穩定）；Value=true 僅代表存在
var discovered_teleporters: Dictionary = {}
signal teleporter_discovered(tp)

# === 玩家設定（不在 reset() 內、跨重玩保留）===
# 預設顯示 HUD 操作提示；玩家可在暫停選單關閉
var show_help_label: bool = true
signal show_help_label_changed(visible: bool)


func set_show_help_label(visible: bool) -> void:
	if show_help_label == visible:
		return
	show_help_label = visible
	show_help_label_changed.emit(visible)


func _process(delta: float) -> void:
	play_time_seconds += delta


# 重玩時呼叫（EndingScreen 按 R 觸發）
func reset() -> void:
	button_press_count = 0
	death_count = 0
	clone_summon_count = 0
	recording_completed_count = 0
	carcass_spawn_count = 0
	play_time_seconds = 0.0
	discovered_teleporters.clear()


# === 傳送門「混合方案」helper（M14a）===
# 用 NodePath 當 key、避免 Teleporter 同房間實例化多次時 ID 撞名
# 玩家本體進入 Teleporter Area2D → Teleporter._on_body_entered 呼叫此函式
func mark_teleporter_discovered(tp: Node) -> void:
	if tp == null or not is_instance_valid(tp):
		return
	var key := String(tp.get_path())
	if discovered_teleporters.has(key):
		return
	discovered_teleporters[key] = true
	teleporter_discovered.emit(tp)


# MapOverlay 用：判斷該傳送門是否可作為遠傳目標
func is_teleporter_discovered(tp: Node) -> bool:
	if tp == null or not is_instance_valid(tp):
		return false
	return discovered_teleporters.has(String(tp.get_path()))


# 結局 UI 用：把秒數格成 "MM:SS"
func format_time() -> String:
	var t := int(play_time_seconds)
	@warning_ignore("integer_division")
	var m := t / 60
	var s := t % 60
	return "%d:%02d" % [m, s]
