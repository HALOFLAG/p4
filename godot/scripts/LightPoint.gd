extends Area2D
class_name LightPoint

# 光點：錄製結束後在錄製起點生成
# 兩種狀態：
#   BRIGHT：活躍槽位的光點（脈動發光，可重錄/刪除——M6 加入互動）
#   TRACE：被覆蓋的舊光點（純視覺、暗灰、不脈動、永久存在）
# 對應實作用規格書 S5

enum State { BRIGHT, TRACE }

const BRIGHT_COLOR := Color(0.6, 0.85, 1.0, 1.0)  # 與儀式粒子同色，視覺連結
const TRACE_COLOR := Color(0.5, 0.5, 0.55, 0.25)  # 暗灰、低 alpha
const PULSE_MIN_ALPHA := 0.6
const PULSE_MAX_ALPHA := 1.0
const PULSE_HALF_PERIOD := 0.8  # 從 min 到 max 的時間（一次完整脈動 = 1.6 秒）
const FADE_TO_TRACE_TIME := 0.4
const FADE_OUT_TIME := 0.4

var state: State = State.BRIGHT
var slot_index: int = -1

@onready var visual: Polygon2D = $Visual

var _pulse_tween: Tween


func _ready() -> void:
	visual.color = BRIGHT_COLOR
	visual.modulate.a = PULSE_MAX_ALPHA
	_start_pulse()


func set_slot(index: int) -> void:
	slot_index = index


func _start_pulse() -> void:
	# 循環脈動 modulate.a 在 min 與 max 之間擺盪
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(visual, "modulate:a", PULSE_MIN_ALPHA, PULSE_HALF_PERIOD)
	_pulse_tween.tween_property(visual, "modulate:a", PULSE_MAX_ALPHA, PULSE_HALF_PERIOD)


func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null


# FIFO / 重錄時呼叫：變成痕跡光點（永久存在但不可互動）
func convert_to_trace() -> void:
	if state == State.TRACE:
		return
	state = State.TRACE
	slot_index = -1
	_stop_pulse()

	# 緩慢淡化成痕跡視覺：color 變灰、modulate.a 重置為 1（不再脈動）
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "color", TRACE_COLOR, FADE_TO_TRACE_TIME)
	tween.tween_property(visual, "modulate:a", 1.0, FADE_TO_TRACE_TIME)


# 主動刪除（M6 的 Q 鍵）：完全淡出消失，不變痕跡
func fade_out_and_remove() -> void:
	_stop_pulse()
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, FADE_OUT_TIME)
	tween.tween_callback(queue_free)
