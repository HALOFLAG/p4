extends Node
class_name PressCounter

# 計次型機關：N 顆 PressButton 的「壓下」事件累計計數，達 target_count 時 emit signal
# 可直接連結 Door（達標後 set_target(true)）
# Room 6：支援 track_all_buttons（吃所有房間的按鈕）+ reset_on_checkpoint（碰旗幟歸零）
# 達標 latch：之後再壓不變化、Door 不會關回（除非被 reset 重置回 0）

signal target_reached
signal count_changed(current: int, target: int)

@export var target_count: int = 5
@export var button_paths: Array[NodePath] = []
@export var door_path: NodePath
@export var label_path: NodePath  # 可選：顯示 "3 / 50" 的 Label
# Room 6：吃所有 "press_button" group 的按鈕（跨房）
@export var track_all_buttons: bool = false
# Room 6：玩家碰任一 "checkpoint" group 旗幟時 reset 計數
@export var reset_on_checkpoint: bool = false

var current_count := 0
var _reached := false


func _ready() -> void:
	# 用 deferred 確保所有 PressButton / Checkpoint 的 _ready 都先跑完、group 都已填好
	target_reached.connect(_open_door)
	call_deferred("_setup_connections")


func _setup_connections() -> void:
	var connected: Dictionary = {}

	# 1. 明確指定的 button_paths
	for path in button_paths:
		var btn := get_node_or_null(path)
		if btn != null and btn.has_signal("pressed_changed") and not connected.has(btn):
			btn.pressed_changed.connect(_on_button_pressed_changed)
			connected[btn] = true

	# 2. 跨房：掃 group "press_button"
	if track_all_buttons:
		for btn in get_tree().get_nodes_in_group("press_button"):
			if not connected.has(btn) and btn.has_signal("pressed_changed"):
				btn.pressed_changed.connect(_on_button_pressed_changed)
				connected[btn] = true

	# 3. Reset on checkpoint：掃 group "checkpoint"
	if reset_on_checkpoint:
		for cp in get_tree().get_nodes_in_group("checkpoint"):
			if cp.has_signal("touched"):
				cp.touched.connect(reset)

	_emit_count()
	print("[COUNTER] 連接 %d 顆按鈕、目標 %d" % [connected.size(), target_count])


func _on_button_pressed_changed(is_pressed: bool) -> void:
	# 只計「壓下」、不計「鬆開」；達標後 latch 不再變
	if not is_pressed or _reached:
		return
	current_count += 1
	_emit_count()
	if current_count >= target_count:
		_reached = true
		target_reached.emit()
		print("[COUNTER] 達標 %d / %d" % [current_count, target_count])


# 給 Checkpoint touched / 外部呼叫用：歸零並重新打開 door 為關
func reset() -> void:
	if current_count == 0 and not _reached:
		return
	current_count = 0
	if _reached:
		_reached = false
		# 達標後若 latch 已開門，重置時把門關回
		var door := get_node_or_null(door_path)
		if door != null and door.has_method("set_target"):
			door.set_target(false)
	_emit_count()
	print("[COUNTER] 已重置")


func _emit_count() -> void:
	count_changed.emit(min(current_count, target_count), target_count)
	var label := get_node_or_null(label_path) as Label
	if label != null:
		label.text = "%d / %d" % [min(current_count, target_count), target_count]


func _open_door() -> void:
	var door := get_node_or_null(door_path)
	if door != null and door.has_method("set_target"):
		door.set_target(true)
