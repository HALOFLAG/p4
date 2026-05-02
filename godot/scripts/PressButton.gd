extends Area2D
class_name PressButton

# 重量感應按鈕：當有 CharacterBody2D（玩家/分身）或物理殘骸站在上面時觸發
# M8：殘骸（StaticBody2D 在 "physical_carcass" group）也算重量

signal pressed_changed(is_pressed: bool)

var bodies_on := 0


func _ready() -> void:
	# M8：mask 統一覆蓋——Player(1) + Clone(2) + 所有殘骸 layer (124) = 127
	# 蓋掉 .tscn 的 3，避免每個按鈕場景手動更新
	collision_mask = 3 + PhysicalCarcass.ALL_CARCASS_LAYERS
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# 接受角色（玩家/分身）+ 物理殘骸；過濾掉地板/牆等世界靜態
func _accepts_body(body: Node2D) -> bool:
	return body is CharacterBody2D or body.is_in_group("physical_carcass")


func _on_body_entered(body: Node2D) -> void:
	if not _accepts_body(body):
		return
	bodies_on += 1
	if bodies_on == 1:
		pressed_changed.emit(true)
		print("[BUTTON] 按下")


func _on_body_exited(body: Node2D) -> void:
	if not _accepts_body(body):
		return
	bodies_on -= 1
	if bodies_on == 0:
		pressed_changed.emit(false)
		print("[BUTTON] 鬆開")


func is_pressed() -> bool:
	return bodies_on > 0
