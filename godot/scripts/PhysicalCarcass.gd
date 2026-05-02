extends StaticBody2D
class_name PhysicalCarcass

# 分身被機關殺死後留下的物理屍體
# - StaticBody2D 在「該 slot 的專屬 layer」（layer 3-7），同 slot 的 clone 用 mask 排除
# - 在 "physical_carcass" group（保留給未來查詢用）
# - convert_to_trace() 把自己換成視覺痕跡（無 collision）

const TRACE_SCENE := preload("res://scenes/CarcassTrace.tscn")

# 5 個 slot 殘骸 layer 聯集（layer 3+4+5+6+7 = 4+8+16+32+64 = 124）
# Player/Proxy/PressButton 全部用、Clone 從中扣掉自己 slot 的 layer
const ALL_CARCASS_LAYERS := 124

# slot index → 該 slot 殘骸專屬的 collision_layer 位元值
# slot 0 → layer 3 (4), slot 1 → layer 4 (8), …, slot 4 → layer 7 (64)
static func slot_to_layer(p_slot_index: int) -> int:
	return 1 << (p_slot_index + 2)


var slot_index: int = -1
var formation_time_msec: int = 0


func _ready() -> void:
	add_to_group("physical_carcass")
	formation_time_msec = Time.get_ticks_msec()


func setup(p_slot_index: int) -> void:
	slot_index = p_slot_index
	collision_layer = slot_to_layer(p_slot_index)


# 由 CarcassManager 在「該槽位殘骸被新殘骸覆蓋 / 槽位被刪 / zone 重置」時呼叫
# 換成痕跡（保留 formation_time 讓 trace 沿用同一個 60s 倒數）
func convert_to_trace() -> Node:
	var trace = TRACE_SCENE.instantiate()
	trace.position = position
	trace.formation_time_msec = formation_time_msec
	get_parent().add_child(trace)
	queue_free()
	return trace
