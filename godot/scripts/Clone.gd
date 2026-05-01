extends "res://scripts/Player.gd"
class_name Clone

# Clone 是 Player 的子類別：
#   * 共用：所有物理（走、跳、重力、coyote、jump buffer、變高跳、碰撞）
#   * 不同：
#       1. 輸入來源從鍵盤改為 Recording 資料（覆寫 _read_inputs）
#       2. 不處理 R/X 按鍵（覆寫 _handle_special_actions 為 pass）
#       3. 不錄製自己的輸入（覆寫 _record_frame_if_needed 為 pass）
#       4. 播完所有 frame 後淡出消失

var recording: Recording = null
var current_frame := 0
var finished := false


func _ready() -> void:
	# 不呼叫 super._ready()——Clone 不需要重生機制
	# 但仍要初始化 spawn_position 以免 inherit 的變數遺留 null
	spawn_position = position
	# 視覺差異化：藍色半透明，與玩家（白色）區分
	visual.color = Color(0.4, 0.7, 1.0, 0.7)


# === 覆寫：從 recording 讀輸入而非鍵盤 ===
func _read_inputs() -> void:
	if recording == null:
		input_left = false
		input_right = false
		input_jump = false
		return
	if current_frame < recording.input_frames.size():
		var f: Dictionary = recording.input_frames[current_frame]
		input_left = f["left"]
		input_right = f["right"]
		input_jump = f["jump"]
		current_frame += 1
	else:
		# Recording 已播完，所有輸入歸零（讓物理自然衰減直到 finish 觸發）
		input_left = false
		input_right = false
		input_jump = false


# === 覆寫：分身不處理 R/X ===
func _handle_special_actions() -> void:
	pass


# === 覆寫：分身不錄製自己的輸入 ===
func _record_frame_if_needed() -> void:
	pass


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Recording 播完後淡出消失
	if not finished and recording != null and current_frame >= recording.input_frames.size():
		finish()


func finish() -> void:
	finished = true
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
