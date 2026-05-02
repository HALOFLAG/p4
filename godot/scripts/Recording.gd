class_name Recording
extends Resource

# 一筆錄製 = 在哪裡開始 + 每個 tick 按了什麼
# 用 Resource 是為了未來能存到磁碟（雖然 M1 暫時只放記憶體）

@export var spawn_position: Vector2 = Vector2.ZERO
@export var input_frames: Array[Dictionary] = []  # [{left: bool, right: bool, jump: bool}, ...]
@export var label: String = ""
@export var slot_index: int = -1  # 0-4 對應 5 槽位；-1 表示尚未指派
# 寫入槽位時的時戳（Time.get_ticks_msec()），FIFO 用來找最舊的槽位
# 重錄會更新此時戳——重錄等於「我又確認它是新的」
@export var created_at_msec: int = 0

func duration_seconds() -> float:
	return float(input_frames.size()) / 60.0
