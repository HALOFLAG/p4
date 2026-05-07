@tool
extends Node
class_name LogicGate

# 邏輯閘：聚合多個輸入 signal、計算 AND/OR/NOT、輸出 output_changed
# 純邏輯抽象、無視覺、無物理、無新輸入鍵 → Recording 100% 相容
#
# 輸入端適配兩種 signal 名稱：
#   PressButton.pressed_changed(is_pressed: bool)
#   Lever.state_changed(is_on: bool)
#
# 用法：在房間內加 LogicGate Node、Inspector 設 op、拖按鈕/拉桿 NodePath、
#       連 output_changed → Door.set_target（或其他 setter）
#
# AND：全部輸入 true 才輸出 true
# OR：任一輸入 true 即輸出 true
# NOT：只看 inputs[0]、輸出反向（其他輸入被忽略）

enum Op { AND, OR, NOT }

signal output_changed(value: bool)

@export var op: Op = Op.AND
@export var inputs: Array[NodePath] = []

var _input_states: Array[bool] = []
var _last_output: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Deferred 確保所有輸入節點 _ready 已跑完（同 PressCounter._setup_connections 模式）
	call_deferred("_setup_connections")


func _setup_connections() -> void:
	_input_states.clear()
	for i in range(inputs.size()):
		_input_states.append(false)
		var node := get_node_or_null(inputs[i])
		if node == null:
			push_warning("LogicGate '%s': input[%d] path '%s' not found" % [name, i, inputs[i]])
			continue
		# 連 signal（適配 PressButton 與 Lever）
		if node.has_signal("pressed_changed"):
			node.pressed_changed.connect(_on_input_changed.bind(i))
		elif node.has_signal("state_changed"):
			node.state_changed.connect(_on_input_changed.bind(i))
		else:
			push_warning("LogicGate '%s': input[%d] '%s' lacks pressed_changed / state_changed signal" % [name, i, node.name])
		# 讀取初始狀態（duck typing）
		if node.has_method("is_pressed"):
			_input_states[i] = node.is_pressed()
		elif "is_on" in node:
			_input_states[i] = node.is_on
	# 初始 emit、讓下游（如 Door）同步當前計算結果
	_last_output = _compute()
	output_changed.emit(_last_output)


func _on_input_changed(value: bool, idx: int) -> void:
	if idx < 0 or idx >= _input_states.size():
		return
	_input_states[idx] = value
	var new_output := _compute()
	# 只在輸出實際變化時 emit、避免下游重複觸發
	if new_output != _last_output:
		_last_output = new_output
		output_changed.emit(new_output)


func _compute() -> bool:
	if _input_states.is_empty():
		return false
	match op:
		Op.AND:
			for s in _input_states:
				if not s:
					return false
			return true
		Op.OR:
			for s in _input_states:
				if s:
					return true
			return false
		Op.NOT:
			# NOT 只看 inputs[0]、其他被忽略
			return not _input_states[0]
	return false
