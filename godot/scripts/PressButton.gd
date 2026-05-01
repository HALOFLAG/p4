extends Area2D
class_name PressButton

# 重量感應按鈕：當有 CharacterBody2D（玩家或分身）站在上面時觸發
# M4 殘骸物理化後，殘骸（StaticBody2D / RigidBody2D）也應該能觸發 — 之後修這條 filter

signal pressed_changed(is_pressed: bool)

var bodies_on := 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	# 忽略世界靜態物件（牆/地板與 Area2D 重疊也會觸發）
	if not body is CharacterBody2D:
		return
	bodies_on += 1
	if bodies_on == 1:
		pressed_changed.emit(true)
		print("[BUTTON] 按下")


func _on_body_exited(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	bodies_on -= 1
	if bodies_on == 0:
		pressed_changed.emit(false)
		print("[BUTTON] 鬆開")


func is_pressed() -> bool:
	return bodies_on > 0
