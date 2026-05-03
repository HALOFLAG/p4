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


# 結局 UI 用：把秒數格成 "MM:SS"
func format_time() -> String:
	var t := int(play_time_seconds)
	@warning_ignore("integer_division")
	var m := t / 60
	var s := t % 60
	return "%d:%02d" % [m, s]
