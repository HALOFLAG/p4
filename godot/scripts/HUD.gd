extends CanvasLayer

# HUD：顯示錄製狀態、5 槽位內容、上下文提示
# CanvasLayer 讓內容停留在螢幕座標、不跟著相機/世界移動
# M6：訂閱 PlayerController 的 player_on/off_lightpoint 顯示上下文提示

# 錄製計時器顏色預警門檻（PlayerController.MAX_RECORDING_FRAMES = 2700 = 45s）
const WARNING_DURATION := 30.0   # 黃色警示
const CRITICAL_DURATION := 40.0  # 紅色臨界

@onready var rec_label: Label = $InfoBox/RecLabel
@onready var saves_label: Label = $InfoBox/SavesLabel
@onready var context_hint: Label = $ContextHint


func _ready() -> void:
	context_hint.visible = false
	context_hint.text = ""

	# 訂閱 PlayerController 的光點互動信號
	PlayerController.player_on_lightpoint.connect(_on_player_on_lightpoint)
	PlayerController.player_off_lightpoint.connect(_on_player_off_lightpoint)


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
