extends CanvasLayer

# HUD：顯示錄製狀態（rec_label）、光點/傳送門上的 context hint、idle 操作提示
# CanvasLayer 讓內容停留在螢幕座標、不跟著相機/世界移動
# 槽位資訊已退出 HUD——LP 編號 / OLD 直接顯示在世界、跨房間查詢用 Tab 地圖

# 錄製計時器顏色預警門檻（PlayerController.MAX_RECORDING_FRAMES = 1800 = 30s）
const WARNING_DURATION := 20.0   # 黃色警示
const CRITICAL_DURATION := 25.0  # 紅色臨界

# HelpLabel 顯示/隱藏 fade 時長（PauseMenu 切換時使用）
const HELP_FADE_TIME := 0.3

@onready var rec_label: Label = $InfoBox/RecLabel
@onready var context_hint: Label = $ContextHint
@onready var help_label: Label = $HelpLabel

const PAUSE_MENU := preload("res://scenes/PauseMenu.tscn")
const MAP_OVERLAY := preload("res://scenes/MapOverlay.tscn")

var _help_fade_tween: Tween = null


func _ready() -> void:
	context_hint.visible = false
	context_hint.text = ""
	# HelpLabel 預設依 GameStats 設定顯示（true = 顯示、false = 隱藏）
	help_label.modulate.a = 1.0 if GameStats.show_help_label else 0.0

	# 訂閱 PlayerController 的光點 / 傳送門互動信號
	PlayerController.player_on_lightpoint.connect(_on_player_on_lightpoint)
	PlayerController.player_off_lightpoint.connect(_on_player_off_lightpoint)
	PlayerController.player_on_teleporter.connect(_on_player_on_teleporter)
	PlayerController.player_off_teleporter.connect(_on_player_off_teleporter)
	# PauseMenu 切換操作提示時 fade in/out
	GameStats.show_help_label_changed.connect(_on_help_label_toggled)


# 鍵盤輸入：ESC 開暫停選單、Tab 開地圖
# 兩個都檢查 paused / 錄製狀態避免疊加（PauseMenu / MapOverlay 自己處理 ESC 關閉）
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_map"):
		_open_map()
		get_viewport().set_input_as_handled()


func _open_pause_menu() -> void:
	if get_tree().paused:
		return
	AudioManager.play_sfx("ui_click")
	var menu := PAUSE_MENU.instantiate()
	add_child(menu)


func _open_map() -> void:
	if get_tree().paused:
		return
	if PlayerController.is_recording():
		return
	var overlay := MAP_OVERLAY.instantiate()
	add_child(overlay)


func _process(_delta: float) -> void:
	# 錄製狀態：計時文字 + 顏色預警（每幀更新）
	if RecordingManager.is_recording():
		var n := RecordingManager.current.input_frames.size()
		var seconds: float = n / 60.0
		var prefix := "● RECORDING"
		# M6 重錄時標示目標槽位
		var target := PlayerController.get_target_slot()
		if target >= 0:
			prefix = "● RE-RECORDING [%d]" % (target + 1)
		rec_label.text = "%s  %.2fs  (%d frames)" % [prefix, seconds, n]
		# 三段顏色預警：< 20s 白、20-25s 黃、>= 25s 鮮紅
		if seconds >= CRITICAL_DURATION:
			rec_label.modulate = Color(1, 0.15, 0.15)
		elif seconds >= WARNING_DURATION:
			rec_label.modulate = Color(1, 0.85, 0.3)
		else:
			rec_label.modulate = Color(1, 1, 1)
	else:
		rec_label.text = ""


# 提示優先序：傳送門 > 光點（玩家在傳送門前的明確意圖是離開、優先顯示傳送）
# _hint_owner 記錄當前 hint 由誰擁有；只有同源才能蓋掉自己的 hint
var _hint_owner: String = ""


func _on_player_on_lightpoint(lp) -> void:
	# 已有傳送門提示就讓位、避免 context_hint 閃爍
	if _hint_owner == "teleporter":
		return
	var slot_index: int = lp.slot_index
	context_hint.text = "第 %d 段過去的起點 — LMB/R 重做 / Q 抹去" % (slot_index + 1)
	context_hint.visible = true
	_hint_owner = "lightpoint"


func _on_player_off_lightpoint() -> void:
	if _hint_owner != "lightpoint":
		return
	context_hint.visible = false
	context_hint.text = ""
	_hint_owner = ""


func _on_player_on_teleporter(_tp) -> void:
	context_hint.text = "按 R 選擇傳送目標"
	context_hint.visible = true
	_hint_owner = "teleporter"


func _on_player_off_teleporter() -> void:
	if _hint_owner != "teleporter":
		return
	context_hint.visible = false
	context_hint.text = ""
	_hint_owner = ""


# === HelpLabel 顯示切換 ===
# 預設顯示（GameStats.show_help_label = true）；玩家可在暫停選單關閉
func _on_help_label_toggled(is_visible: bool) -> void:
	if _help_fade_tween != null and _help_fade_tween.is_valid():
		_help_fade_tween.kill()
	_help_fade_tween = create_tween()
	_help_fade_tween.tween_property(help_label, "modulate:a", 1.0 if is_visible else 0.0, HELP_FADE_TIME)
