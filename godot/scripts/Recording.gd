class_name Recording
extends Resource

# 一筆錄製 = 在哪裡開始 + 每個 tick 按了什麼
# 用 Resource 是為了未來能存到磁碟（雖然 M1 暫時只放記憶體）

@export var spawn_position: Vector2 = Vector2.ZERO
@export var input_frames: Array[Dictionary] = []  # [{left: bool, right: bool, jump: bool}, ...]
@export var label: String = ""

func duration_seconds() -> float:
	return float(input_frames.size()) / 60.0
