extends Node2D
class_name CarcassTrace

# 物理殘骸轉化後的視覺痕跡——無 collision、永久存在、新→舊兩階段
# NEW（剛轉化）：alpha 0.5，視覺仍可辨識
# OLD（formation 60s 後）：alpha 0.2，5s 內淡化過渡，之後不再變化

const NEW_ALPHA := 0.5
const OLD_ALPHA := 0.2
const NEW_TO_OLD_DELAY := 60.0  # 形成多少秒後開始轉舊
const NEW_TO_OLD_FADE := 5.0    # 轉舊的淡化時間
# 鄰近去重複半徑：新 trace 形成時若 < 此距離已有 trace，新 trace 自我銷毀
# 避免同位置 alpha 疊加（兩個 0.5 → 視覺 0.75，破壞 NEW/OLD 兩階段視覺）
# 48 = 1.5 倍 player 寬度，兩 trace 中心距離 < 48 即視為「同一處」，讓視覺邊緣留 ~16px 間隙
const DEDUP_RADIUS := 48.0

# 由 PhysicalCarcass.convert_to_trace() 設定（沿用原殘骸的形成時間）
var formation_time_msec: int = 0

@onready var visual: Polygon2D = $Visual

var _has_aged := false


func _ready() -> void:
	add_to_group("carcass_trace")
	# 初始 alpha = NEW
	visual.modulate.a = NEW_ALPHA
	# 鄰近去重複：保留先到的、丟掉後到的（避免 alpha 疊加）
	for existing in get_tree().get_nodes_in_group("carcass_trace"):
		if existing == self or not is_instance_valid(existing):
			continue
		if global_position.distance_to(existing.global_position) < DEDUP_RADIUS:
			queue_free()
			return


func _process(_delta: float) -> void:
	if _has_aged:
		return
	var elapsed: float = (Time.get_ticks_msec() - formation_time_msec) / 1000.0
	if elapsed >= NEW_TO_OLD_DELAY:
		_has_aged = true
		var tween := create_tween()
		tween.tween_property(visual, "modulate:a", OLD_ALPHA, NEW_TO_OLD_FADE)
