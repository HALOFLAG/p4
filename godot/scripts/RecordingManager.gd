extends Node

# 5 槽位錄製管理器（autoload）
# 對應實作用規格書 S6
#
# 槽位規則：
#   - 固定 5 個槽位（slots[0] ~ slots[4]）
#   - 結束錄製時優先填空槽（從 0 找到 4）
#   - 全滿則 FIFO 覆蓋「最舊」的槽位（依 created_at_msec），emit slot_will_overwrite
#   - 重錄會更新該槽位的 created_at_msec（變最新）
#
# 信號用途：
#   slot_will_overwrite：FIFO/重錄前發出，讓 PlayerController 把舊光點轉痕跡
#   slot_assigned：錄製完成、放入槽位後發出，PlayerController 生成新光點
#   slot_cleared：主動刪除（Q 鍵）後發出，PlayerController 淡出光點

const SLOT_COUNT := 5

# 5 個槽位（null 表示空）
var slots: Array[Recording] = []

# 正在進行的錄製（null 表示沒在錄）
var current: Recording = null

signal slot_assigned(slot_index: int, recording: Recording)
signal slot_will_overwrite(slot_index: int, old_recording: Recording)
signal slot_cleared(slot_index: int)


func _ready() -> void:
	# 初始化 5 個空槽位
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = null


func is_recording() -> bool:
	return current != null


func start_recording(spawn_pos: Vector2) -> void:
	if current != null:
		print("[REC] 已在錄製中，忽略")
		return
	current = Recording.new()
	current.spawn_position = spawn_pos
	print("[REC] 開始錄製 @ ", spawn_pos)


func add_frame(left: bool, right: bool, jump: bool) -> void:
	if current == null:
		return
	current.input_frames.append({"left": left, "right": right, "jump": jump})


func stop_recording() -> Recording:
	"""完成錄製、放入槽位（必要時 FIFO）、回傳該 Recording。
	無錄製進行中則回傳 null。"""
	if current == null:
		return null

	# 找空槽位；全滿則 FIFO 覆蓋最舊那個
	var slot_index := _find_empty_slot()
	if slot_index == -1:
		slot_index = _find_oldest_slot()
		# 通知 PlayerController 等：舊光點要轉痕跡
		slot_will_overwrite.emit(slot_index, slots[slot_index])

	current.slot_index = slot_index
	current.label = "存檔 %d" % (slot_index + 1)
	current.created_at_msec = Time.get_ticks_msec()
	var saved := current
	slots[slot_index] = saved
	current = null

	slot_assigned.emit(slot_index, saved)
	print("[REC] 結束錄製：%s — %d frames (%.2fs)" % [
		saved.label, saved.input_frames.size(), saved.duration_seconds()
	])
	return saved


func get_recording(slot_index: int) -> Recording:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return null
	return slots[slot_index]


func delete_slot(slot_index: int) -> bool:
	"""主動刪除槽位內容（M6 Q 鍵會用）。回傳是否真的有刪到東西。"""
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	if slots[slot_index] == null:
		return false
	slots[slot_index] = null
	slot_cleared.emit(slot_index)
	print("[REC] 槽位 %d 已刪除" % (slot_index + 1))
	return true


func replace_slot(slot_index: int, recording: Recording) -> void:
	"""重錄某個槽位（M6 站光點上 R 會用）
	注意：**不** emit slot_will_overwrite——重錄是「精確覆蓋同一槽位」，
	光點要保持原位、不轉痕跡（與 FIFO 行為不同）"""
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	recording.slot_index = slot_index
	recording.label = "存檔 %d" % (slot_index + 1)
	recording.created_at_msec = Time.get_ticks_msec()
	slots[slot_index] = recording
	slot_assigned.emit(slot_index, recording)
	print("[REC] 槽位 %d 已重錄" % (slot_index + 1))


func stop_recording_to_slot(target_slot: int) -> Recording:
	"""完成錄製、放入指定槽位（用 replace_slot），用於 re-record 流程。
	無錄製進行中或槽位無效則回傳 null。"""
	if current == null:
		return null
	if target_slot < 0 or target_slot >= SLOT_COUNT:
		return null
	var saved := current
	current = null
	replace_slot(target_slot, saved)
	return saved


func clear_all() -> void:
	for i in range(SLOT_COUNT):
		slots[i] = null
	current = null
	print("[REC] 已清空所有槽位")


# M9：丟棄正在進行的錄製（不存槽位、不發信號）
# A3 路徑下「錄製太短不存」與本體死亡中斷錄製都會用
func discard_recording() -> void:
	if current == null:
		return
	current = null
	print("[REC] 錄製已丟棄")


func _find_empty_slot() -> int:
	for i in range(SLOT_COUNT):
		if slots[i] == null:
			return i
	return -1


func _find_oldest_slot() -> int:
	# 假設呼叫時所有槽位都非空（FIFO 路徑才會用到）
	return get_oldest_slot_index()


# HUD 用：取得最舊／最新的槽位 index（無填滿則回 -1）
func get_oldest_slot_index() -> int:
	var oldest_idx := -1
	var oldest_msec: int = 0
	for i in range(SLOT_COUNT):
		var s: Recording = slots[i]
		if s == null:
			continue
		if oldest_idx == -1 or s.created_at_msec < oldest_msec:
			oldest_msec = s.created_at_msec
			oldest_idx = i
	return oldest_idx


func get_newest_slot_index() -> int:
	var newest_idx := -1
	var newest_msec: int = 0
	for i in range(SLOT_COUNT):
		var s: Recording = slots[i]
		if s == null:
			continue
		if newest_idx == -1 or s.created_at_msec > newest_msec:
			newest_msec = s.created_at_msec
			newest_idx = i
	return newest_idx


func filled_count() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n
