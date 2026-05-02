extends CanvasLayer

# HUD：顯示錄製狀態、5 槽位內容、上下文提示
# CanvasLayer 讓內容停留在螢幕座標、不跟著相機/世界移動
# M6：訂閱 PlayerController 的 player_on/off_lightpoint 顯示上下文提示

# 錄製計時器顏色預警門檻（PlayerController.MAX_RECORDING_FRAMES = 2700 = 45s）
const WARNING_DURATION := 30.0   # 黃色警示
const CRITICAL_DURATION := 40.0  # 紅色臨界

# HelpLabel idle 顯示：玩家 N 秒未移動才淡入
const HELP_IDLE_THRESHOLD := 30.0
const HELP_FADE_TIME := 0.5

@onready var rec_label: Label = $InfoBox/RecLabel
@onready var saves_label: Label = $InfoBox/SavesLabel
@onready var context_hint: Label = $ContextHint
@onready var help_label: Label = $HelpLabel
@onready var pause_button: Button = $PauseButton

const PAUSE_MENU := preload("res://scenes/PauseMenu.tscn")

var _idle_time := 0.0
var _help_visible := false
var _help_fade_tween: Tween = null


func _ready() -> void:
	context_hint.visible = false
	context_hint.text = ""
	# HelpLabel 起始隱藏，超過 idle 閾值才淡入
	help_label.modulate.a = 0.0

	# 訂閱 PlayerController 的光點互動信號
	PlayerController.player_on_lightpoint.connect(_on_player_on_lightpoint)
	PlayerController.player_off_lightpoint.connect(_on_player_off_lightpoint)

	# 暫停按鈕（暫停期間仍可點）
	pause_button.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_button.pressed.connect(_on_pause_pressed)


func _on_pause_pressed() -> void:
	if get_tree().paused:
		return
	AudioManager.play_sfx("ui_click")
	var menu := PAUSE_MENU.instantiate()
	add_child(menu)


func _process(delta: float) -> void:
	_update_help_idle(delta)
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
		# 三段顏色預警：< 30s 白、30-40s 黃、>= 40s 鮮紅
		if seconds >= CRITICAL_DURATION:
			rec_label.modulate = Color(1, 0.15, 0.15)
		elif seconds >= WARNING_DURATION:
			rec_label.modulate = Color(1, 0.85, 0.3)
		else:
			rec_label.modulate = Color(1, 1, 1)
	else:
		rec_label.text = ""

	# 5 槽位顯示
	# 重錄期間在目標槽位加標記、新錄製要 FIFO 時在「最舊」槽位加警告
	# OLD / NEW 標示：填滿 >= 2 槽時，依 created_at_msec 找最舊與最新各標一個
	var filled: int = RecordingManager.filled_count()
	var oldest_idx: int = RecordingManager.get_oldest_slot_index()
	var newest_idx: int = RecordingManager.get_newest_slot_index()
	var fifo_warning_slot := -1
	if RecordingManager.is_recording() and PlayerController.get_target_slot() == -1:
		# 新錄製：若全滿則最舊槽位將被 FIFO 覆蓋
		if filled == RecordingManager.SLOT_COUNT:
			fifo_warning_slot = oldest_idx

	# 只有 2 個以上才標 OLD/NEW（1 個時兩者重合，沒意義）
	var show_age_tags := filled >= 2

	var parts: Array[String] = []
	for i in range(RecordingManager.SLOT_COUNT):
		var r: Recording = RecordingManager.slots[i]
		# 縱向排列：⚠ 列佔 2 字元，其餘列補 2 空白讓 [N] 對齊
		var prefix := "  "
		if i == fifo_warning_slot:
			prefix = "⚠ "
		var suffix := ""
		if show_age_tags and r != null:
			if i == oldest_idx:
				suffix = " OLD"
			elif i == newest_idx:
				suffix = " NEW"
		if r != null:
			parts.append("%s[%d] %s (%.1fs)%s" % [prefix, i + 1, r.label, r.duration_seconds(), suffix])
		else:
			parts.append("%s[%d] —" % [prefix, i + 1])
	saves_label.text = "Slots: %d/%d\n%s" % [
		filled, RecordingManager.SLOT_COUNT, "\n".join(parts)
	]


func _on_player_on_lightpoint(lp) -> void:
	var slot_index: int = lp.slot_index
	context_hint.text = "站在槽位 [%d] 的光點上 — R 重錄 / Q 刪除" % (slot_index + 1)
	context_hint.visible = true


func _on_player_off_lightpoint() -> void:
	context_hint.visible = false
	context_hint.text = ""


# === HelpLabel idle 顯示 ===
# 玩家連續 30 秒沒按方向 / 跳躍 → 淡入提示文字
# 任一移動鍵按下 → 立即淡出
func _update_help_idle(delta: float) -> void:
	var any_movement := (
		Input.is_action_pressed("move_left")
		or Input.is_action_pressed("move_right")
		or Input.is_action_pressed("jump")
	)
	if any_movement:
		_idle_time = 0.0
		if _help_visible:
			_help_visible = false
			_fade_help_to(0.0)
	else:
		_idle_time += delta
		if _idle_time >= HELP_IDLE_THRESHOLD and not _help_visible:
			_help_visible = true
			_fade_help_to(1.0)


func _fade_help_to(target_alpha: float) -> void:
	if _help_fade_tween != null and _help_fade_tween.is_valid():
		_help_fade_tween.kill()
	_help_fade_tween = create_tween()
	_help_fade_tween.tween_property(help_label, "modulate:a", target_alpha, HELP_FADE_TIME)
