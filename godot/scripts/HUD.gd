extends CanvasLayer

# HUD：顯示錄製狀態、存檔清單、操作提示
# CanvasLayer 讓內容停留在螢幕座標、不跟著相機/世界移動

@onready var red_tint: ColorRect = $RedTint
@onready var rec_label: Label = $InfoBox/RecLabel
@onready var saves_label: Label = $InfoBox/SavesLabel


func _process(_delta: float) -> void:
	# 錄製狀態：紅色覆蓋層 + 計時文字
	if RecordingManager.is_recording():
		red_tint.visible = true
		var n := RecordingManager.current.input_frames.size()
		rec_label.text = "● RECORDING  %.2fs  (%d frames)" % [n / 60.0, n]
		rec_label.modulate = Color(1, 0.4, 0.4)
	else:
		red_tint.visible = false
		rec_label.text = ""

	# 存檔清單（編號顯示，方便對應 1-9 召喚鍵）
	var count := RecordingManager.recordings.size()
	if count == 0:
		saves_label.text = "Saves: 0  (按 R 開始錄製)"
	else:
		var parts: Array[String] = []
		for i in range(count):
			var r: Recording = RecordingManager.recordings[i]
			parts.append("[%d] %s (%.1fs)" % [i + 1, r.label, r.duration_seconds()])
		saves_label.text = "Saves: %d  —  %s" % [count, "  ".join(parts)]
