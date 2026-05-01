extends Node

# 全域單例（autoload）：管理所有錄製存檔
# 在 project.godot 設成 autoload 後，任何地方都可以直接用 `RecordingManager.xxx` 存取

# 已完成的存檔清單（in-memory，原型階段不存磁碟）
var recordings: Array[Recording] = []

# 正在進行的錄製（null 表示沒在錄）
var current: Recording = null


func is_recording() -> bool:
	return current != null


func start_recording(spawn_pos: Vector2) -> void:
	# 如果已經在錄就忽略（避免重複按 R 把舊的洗掉）
	if current != null:
		print("[REC] 已在錄製中，忽略")
		return
	current = Recording.new()
	current.spawn_position = spawn_pos
	print("[REC] 開始錄製 @ ", spawn_pos)


func add_frame(left: bool, right: bool, jump: bool) -> void:
	# 每個 physics tick 由 Player 呼叫一次
	if current == null:
		return
	current.input_frames.append({"left": left, "right": right, "jump": jump})


func stop_recording() -> Recording:
	# 結束錄製、加進清單、回傳剛存的那一筆
	if current == null:
		return null
	current.label = "存檔 %d" % (recordings.size() + 1)
	var r := current
	recordings.append(r)
	current = null
	print("[REC] 結束錄製：", r.label, " — ", r.input_frames.size(), " frames (", "%.2f" % r.duration_seconds(), "s)")
	return r


func clear_all() -> void:
	# 偵錯用：清空所有存檔
	recordings.clear()
	current = null
	print("[REC] 已清空所有存檔")
