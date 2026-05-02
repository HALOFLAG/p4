extends Area2D
class_name Sign

# 接近淡入文字（M10）
# 玩家走近 → label fade in；走開 → fade out
# Inspector 設 text 屬性即可，不必每個 sign 新建場景

@export var text: String = "":
	set(value):
		text = value
		if label != null:
			label.text = value

const FADE_TIME := 0.3

@onready var label: Label = $Label

var _fade_tween: Tween = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	label.text = text
	label.modulate.a = 0.0


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player_real"):
		return
	_fade_to(1.0)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player_real"):
		return
	_fade_to(0.0)


func _fade_to(target_alpha: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(label, "modulate:a", target_alpha, FADE_TIME)
