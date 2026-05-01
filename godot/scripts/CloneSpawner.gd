extends Node

# 通用的分身召喚器：監聽 1-9 數字鍵，從 RecordingManager 取對應存檔召喚分身。
# 加為任何需要召喚分身的場景的子節點。召喚出來的分身會被加到 spawner 的父節點（場景根）。

const CLONE_SCENE := preload("res://scenes/Clone.tscn")

# physical_keycode → 存檔索引（0-based）
const SPAWN_KEYS := {
	KEY_1: 0,
	KEY_2: 1,
	KEY_3: 2,
	KEY_4: 3,
	KEY_5: 4,
	KEY_6: 5,
	KEY_7: 6,
	KEY_8: 7,
	KEY_9: 8,
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


func spawn_clone(index: int) -> void:
	# CD 期間靜默吞掉（不印 log，避免連拍刷屏）
	if summon_cd_remaining > 0.0:
		return
	var recordings := RecordingManager.recordings
	if index >= recordings.size():
		# 索引錯誤是真正需要知道的，仍印 log
		print("[SPAWN] 沒有存檔 ", index + 1, "（目前 ", recordings.size(), " 筆）")
		return
	var rec: Recording = recordings[index]
	var clone: Clone = CLONE_SCENE.instantiate()
	clone.position = rec.spawn_position
	clone.recording = rec
	# 加到 spawner 的父節點（通常是場景根），與其他場景物件同層
	get_parent().add_child(clone)
	summon_cd_remaining = SUMMON_CD
	print("[SPAWN] 召喚 ", rec.label, " @ ", rec.spawn_position, " — ", rec.input_frames.size(), " frames")
