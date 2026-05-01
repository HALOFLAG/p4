extends Area2D
class_name Exit

# 出口偵測：只有「真正的玩家」進入才算通關，分身路過不觸發
# 用 group "player_real" 區分：Player._ready 會 add_to_group，Clone 因為不呼叫 super._ready 自動不會在這 group

signal reached

var triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if triggered:
		return
	if body.is_in_group("player_real"):
		triggered = true
		reached.emit()
		print("[EXIT] 玩家到達出口")
