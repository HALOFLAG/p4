extends CanvasLayer

# 時間觸發的 hint 系統（呼應設計文件「用時間而非次數判斷玩家卡住」）
# 規則：
#   1. 進場 35 秒未通關 → 角落淡入「按 R 開始錄製」
#   2. 在按鈕上停留 5 秒 → 角落淡入「按 X 自爆」（離開按鈕重新計時）
#   3. 通關後兩個提示淡出消失（這是「第一個」也是「唯一」會出現提示的場景）

const SCENE_STUCK_TIME := 35.0
const ON_BUTTON_STUCK_TIME := 5.0

@onready var hint_record: Label = $HintRecord
@onready var hint_destruct: Label = $HintDestruct
@onready var button: PressButton = $"../Button"
@onready var exit: Exit = $"../Exit"

var time_in_scene := 0.0
var time_on_button := 0.0
var hint_record_started := false   # 已啟動淡入動畫的 flag，避免每 tick 重複建 tween
var hint_destruct_started := false
var solved := false


func _ready() -> void:
	hint_record.modulate.a = 0.0
	hint_destruct.modulate.a = 0.0
	exit.reached.connect(_on_solved)


func _process(delta: float) -> void:
	if solved:
		return

	time_in_scene += delta
	# 在按鈕上連續累積、離開時重置為 0（避免「總共在按鈕上 5 秒」這種不直覺的累積）
	if button.is_pressed():
		time_on_button += delta
	else:
		time_on_button = 0.0

	if not hint_record_started and time_in_scene >= SCENE_STUCK_TIME:
		hint_record_started = true
		_fade_in(hint_record)
	if not hint_destruct_started and time_on_button >= ON_BUTTON_STUCK_TIME:
		hint_destruct_started = true
		_fade_in(hint_destruct)


func _fade_in(label: Label) -> void:
	create_tween().tween_property(label, "modulate:a", 1.0, 1.5)


func _on_solved() -> void:
	solved = true
	var tw := create_tween()
	tw.parallel().tween_property(hint_record, "modulate:a", 0.0, 0.8)
	tw.parallel().tween_property(hint_destruct, "modulate:a", 0.0, 0.8)
