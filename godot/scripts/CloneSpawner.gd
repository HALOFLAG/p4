extends Node

# 通用的分身召喚器：監聽 1-5 數字鍵，從 RecordingManager 取對應槽位的錄製召喚分身。
# 加為任何需要召喚分身的場景的子節點。召喚出來的分身會被加到 spawner 的父節點（場景根）。
# M5 起改為 1-5 槽位制（取代 M2 的 1-9 無上限）

const CLONE_SCENE := preload("res://scenes/Clone.tscn")

# physical_keycode → 槽位索引（0-based，對應 RecordingManager.slots[i]）
const SPAWN_KEYS := {
	KEY_1: 0,
	KEY_2: 1,
	KEY_3: 2,
	KEY_4: 3,
	KEY_5: 4,
}

# 召喚 CD：避免誤觸與連拍刷屏（M2.5 決策，原型階段可調整）
const SUMMON_CD := 0.3
var summon_cd_remaining := 0.0


func _process(delta: float) -> void:
	if summon_cd_remaining > 0.0:
		summon_cd_remaining = maxf(summon_cd_remaining - delta, 0.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = SPAWN_KEYS.get(event.physical_keycode, -1)
		if idx >= 0:
			spawn_clone(idx)


func spawn_clone(slot_index: int) -> void:
	# CD 期間靜默吞掉（不印 log，避免連拍刷屏）
	if summon_cd_remaining > 0.0:
		return
	# 錄製中不能召喚（沿用既有規則）
	if PlayerController.is_recording():
		return
	var rec: Recording = RecordingManager.get_recording(slot_index)
	if rec == null:
		# 槽位空——是常見情況（早期玩家還沒錄滿），印 log 給除錯用
		print("[SPAWN] 槽位 %d 為空" % (slot_index + 1))
		return
	var clone: Clone = CLONE_SCENE.instantiate()
	clone.position = rec.spawn_position
	clone.recording = rec
	# 加到 spawner 的父節點（通常是場景根），與其他場景物件同層
	get_parent().add_child(clone)
	summon_cd_remaining = SUMMON_CD
	print("[SPAWN] 召喚 ", rec.label, " @ ", rec.spawn_position, " — ", rec.input_frames.size(), " frames")
