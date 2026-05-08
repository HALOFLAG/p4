extends CanvasLayer

# 簡易地圖 UI：兩種開啟模式
#   ① Tab（瀏覽模式）  ：顯示房間 + 玩家 + 傳送門位置、ESC/Tab 關閉
#   ② R 在傳送門上（選擇模式）：同上 + 滑鼠 hover 高亮 + 點擊傳送門 → emit destination_selected
# PlayerController 用 await destination_selected 等玩家選完、再做 fade + 瞬移
# MVP 不畫房間內牆/平台、不做 fog of war、不做 keyboard 選擇

signal destination_selected(dest_teleporter)  # 玩家點選的目標、null 表示取消

const VIEWPORT_SIZE := Vector2(1280, 720)  # 螢幕大小（與 project.godot 對齊）
const MAP_PADDING := 80.0
const ROOM_RECT_PADDING := 4.0             # 房間色塊間視覺分隔
const PLAYER_MARKER_SIZE := Vector2(18, 24)
const TELEPORTER_MARKER_SIZE := Vector2(14, 22)
const TELEPORTER_HIT_PADDING := Vector2(6, 6)  # 點擊判定額外擴大、好按
const MARKER_BORDER_WIDTH := 2.0
const LP_MARKER_RADIUS := 8.0
const LP_LABEL_FONT_SIZE := 12

const COLOR_BG := Color(0.04, 0.05, 0.08, 0.95)
const COLOR_PLAYER := Color(1, 0.55, 0.7)
const COLOR_TELEPORTER := Color(0.6, 0.85, 1.0)
const COLOR_TELEPORTER_UNDISCOVERED := Color(0.35, 0.38, 0.45)  # 未啟用——灰、不可點
const COLOR_MARKER_BORDER := Color(1, 1, 1)
const COLOR_MARKER_BORDER_DIM := Color(0.55, 0.6, 0.7)   # 未啟用傳送門邊框
const COLOR_TELEPORTER_HOVER := Color(1, 0.85, 0.3)   # 金色——hover 中
const COLOR_TELEPORTER_SOURCE := Color(0.5, 1.0, 0.5) # 綠色——目前所在傳送門
const COLOR_LIGHTPOINT := Color(0.6, 0.85, 1.0)       # 與 LightPoint BRIGHT_COLOR 一致
const COLOR_HINT := Color(0.7, 0.75, 0.85)

# 投影參數（_ready 算一次、_draw 用）
var _world_min: Vector2
var _scale: float
var _map_offset: Vector2

# 選擇模式狀態
var _selection_mode := false
var _source_teleporter = null  # Teleporter 或 null
var _hovered_teleporter = null
var _selection_emitted := false  # 防 _exit_tree 在已 emit 後又補 emit 一次

@onready var canvas: Control = $Canvas
@onready var title_label: Label = $Canvas/TitleLabel
@onready var hint_label: Label = $Canvas/HintLabel
@onready var label_label: Label = $Canvas/HoverLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_compute_projection()
	get_tree().paused = true
	# 通知 PlayerController：World 收到後會 duck BGM 到 50%、保持音樂持續播放
	PlayerController.notify_map_opened()
	canvas.draw.connect(_draw_canvas)
	label_label.visible = false
	canvas.queue_redraw()


# 由 PlayerController.activate_teleporter 在 instantiate 後呼叫
# 切到「點目標」模式、UI 文字變化、滑鼠 hover/click 啟用
func enter_selection_mode(source_tp) -> void:
	_selection_mode = true
	_source_teleporter = source_tp
	if title_label != null:
		title_label.text = "選擇傳送目標"
	if hint_label != null:
		hint_label.text = "點選目標傳送門 / ESC 取消"


func _compute_projection() -> void:
	var rooms := get_tree().get_nodes_in_group("room")
	if rooms.is_empty():
		_world_min = Vector2.ZERO
		_scale = 1.0
		_map_offset = Vector2(MAP_PADDING, MAP_PADDING)
		return

	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for room in rooms:
		if not room.has_method("get_world_rect"):
			continue
		var r: Rect2 = room.get_world_rect()
		min_pt.x = minf(min_pt.x, r.position.x)
		min_pt.y = minf(min_pt.y, r.position.y)
		max_pt.x = maxf(max_pt.x, r.position.x + r.size.x)
		max_pt.y = maxf(max_pt.y, r.position.y + r.size.y)

	_world_min = min_pt
	var world_size: Vector2 = max_pt - min_pt
	var avail: Vector2 = VIEWPORT_SIZE - Vector2(MAP_PADDING, MAP_PADDING) * 2.0
	_scale = minf(avail.x / world_size.x, avail.y / world_size.y)
	var scaled: Vector2 = world_size * _scale
	_map_offset = Vector2(MAP_PADDING, MAP_PADDING) + (avail - scaled) * 0.5


func _world_to_map(world_pos: Vector2) -> Vector2:
	return (world_pos - _world_min) * _scale + _map_offset


func _process(_delta: float) -> void:
	# 玩家位置每幀刷新；選擇模式下 hover 偵測也每幀更新
	if _selection_mode:
		var mouse: Vector2 = canvas.get_local_mouse_position()
		var new_hover = _hit_test_teleporter(mouse)
		if new_hover != _hovered_teleporter:
			_hovered_teleporter = new_hover
			_update_hover_label()
	canvas.queue_redraw()


# 用比 Marker 大一點的 rect 做 hit test、提升點擊容易度
# 注意：仍會回傳未啟用 / source 傳送門、由呼叫端決定是否要 hover label / 點擊
# 這樣 hover 未啟用時可顯「未啟用」提示、教育玩家「要走過去才能用」
func _hit_test_teleporter(screen_pos: Vector2):
	for tp in get_tree().get_nodes_in_group("teleporter"):
		if not is_instance_valid(tp):
			continue
		var center: Vector2 = _world_to_map(tp.global_position)
		var hit_size: Vector2 = TELEPORTER_MARKER_SIZE + TELEPORTER_HIT_PADDING * 2.0
		var rect := Rect2(center - hit_size * 0.5, hit_size)
		if rect.has_point(screen_pos):
			return tp
	return null


func _update_hover_label() -> void:
	if _hovered_teleporter == null:
		label_label.visible = false
		return
	var name_str: String = _hovered_teleporter.name
	if _hovered_teleporter.has_method("get_label"):
		name_str = _hovered_teleporter.get_label()
	if _hovered_teleporter == _source_teleporter:
		label_label.text = "%s（目前位置）" % name_str
	elif not _is_tp_discovered(_hovered_teleporter):
		# 未啟用：提示玩家「先走過去」（混合方案 / 篝火模式）
		label_label.text = "%s（未啟用 — 親身抵達後解鎖）" % name_str
	else:
		label_label.text = name_str
	# 跟隨滑鼠右下、不擋到 hover marker
	var mouse: Vector2 = canvas.get_local_mouse_position()
	label_label.position = mouse + Vector2(16, 8)
	label_label.visible = true


# 統一查詢、避免散落多處（GameStats 是來源真相、Teleporter.is_discovered 為便利包裝）
func _is_tp_discovered(tp) -> bool:
	if tp == null or not is_instance_valid(tp):
		return false
	return GameStats.is_teleporter_discovered(tp)


func _draw_canvas() -> void:
	# 背景
	canvas.draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), COLOR_BG, true)

	# 房間色塊
	for room in get_tree().get_nodes_in_group("room"):
		if not room.has_method("get_world_rect"):
			continue
		var r: Rect2 = room.get_world_rect()
		var top_left := _world_to_map(r.position)
		var size: Vector2 = r.size * _scale
		var inner := Rect2(
			top_left + Vector2(ROOM_RECT_PADDING, ROOM_RECT_PADDING),
			size - Vector2(ROOM_RECT_PADDING, ROOM_RECT_PADDING) * 2.0
		)
		var color: Color = room.area_color if "area_color" in room else Color(0.4, 0.3, 0.7)
		canvas.draw_rect(inner, color, true)

	# 光點標記（只畫 BRIGHT 的活躍光點、TRACE 不畫）
	# state enum：0 = BRIGHT、1 = TRACE
	var font: Font = canvas.get_theme_default_font()
	for lp in get_tree().get_nodes_in_group("light_point"):
		if not is_instance_valid(lp):
			continue
		if "state" in lp and lp.state != 0:
			continue
		var lp_pos: Vector2 = _world_to_map(lp.global_position)
		canvas.draw_circle(lp_pos, LP_MARKER_RADIUS, COLOR_LIGHTPOINT)
		canvas.draw_arc(lp_pos, LP_MARKER_RADIUS, 0, TAU, 24, COLOR_MARKER_BORDER, 1.5)
		# 編號標於圓上方
		if "slot_index" in lp and lp.slot_index >= 0:
			var num_str: String = str(lp.slot_index + 1)
			var size: Vector2 = font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, LP_LABEL_FONT_SIZE)
			var text_pos: Vector2 = Vector2(lp_pos.x - size.x * 0.5, lp_pos.y - LP_MARKER_RADIUS - 3)
			canvas.draw_string(font, text_pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, LP_LABEL_FONT_SIZE, Color.WHITE)

	# 傳送門標記
	# 顏色優先序：source(綠) > hover(金、僅已啟用會亮金) > 已啟用(青藍) > 未啟用(灰)
	# 未啟用 hover 仍顯 label（教育玩家「要走過去」）、但點擊由 _input 過濾掉
	for tp in get_tree().get_nodes_in_group("teleporter"):
		if not is_instance_valid(tp):
			continue
		var center: Vector2 = _world_to_map(tp.global_position)
		var rect := Rect2(center - TELEPORTER_MARKER_SIZE * 0.5, TELEPORTER_MARKER_SIZE)
		var discovered: bool = _is_tp_discovered(tp)
		var fill: Color = COLOR_TELEPORTER if discovered else COLOR_TELEPORTER_UNDISCOVERED
		var border: Color = COLOR_MARKER_BORDER if discovered else COLOR_MARKER_BORDER_DIM
		var border_w: float = MARKER_BORDER_WIDTH
		if tp == _source_teleporter:
			fill = COLOR_TELEPORTER_SOURCE
			border = COLOR_TELEPORTER_SOURCE
			border_w = MARKER_BORDER_WIDTH * 1.5
		elif _selection_mode and tp == _hovered_teleporter and discovered:
			# hover 金色僅給「可點選」對象（已啟用且非 source）
			fill = COLOR_TELEPORTER_HOVER
			border = COLOR_TELEPORTER_HOVER
			border_w = MARKER_BORDER_WIDTH * 1.5
		canvas.draw_rect(rect, fill, true)
		canvas.draw_rect(rect, border, false, border_w)

	# 玩家標記
	var players := get_tree().get_nodes_in_group("player_real")
	if not players.is_empty():
		var p: Node2D = players[0]
		var center: Vector2 = _world_to_map(p.global_position)
		var rect := Rect2(center - PLAYER_MARKER_SIZE * 0.5, PLAYER_MARKER_SIZE)
		canvas.draw_rect(rect, COLOR_PLAYER, true)
		canvas.draw_rect(rect, COLOR_MARKER_BORDER, false, MARKER_BORDER_WIDTH)


func _input(event: InputEvent) -> void:
	# ESC / Tab → 取消（emit null）
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("toggle_map") or event.keycode == KEY_ESCAPE:
			_close(null)
			get_viewport().set_input_as_handled()
			return

	# 選擇模式下：滑鼠左鍵點擊 = 選目標
	if _selection_mode and event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var clicked = _hit_test_teleporter(event.position)
			# 過濾：source / 空白點擊 / 未啟用 都忽略（不關閉地圖、玩家可繼續挑）
			if clicked != null \
					and clicked != _source_teleporter \
					and _is_tp_discovered(clicked):
				_close(clicked)
				get_viewport().set_input_as_handled()


# 關閉 + emit destination_selected
# dest = null（取消）或 Teleporter（選定目標）
func _close(dest) -> void:
	if _selection_emitted:
		return
	_selection_emitted = true
	get_tree().paused = false
	PlayerController.notify_map_closed()
	destination_selected.emit(dest)
	queue_free()


# Tab 模式被父節點 free 時也要 emit、避免上游 await 卡住（保險用）
func _exit_tree() -> void:
	if _selection_mode and not _selection_emitted:
		_selection_emitted = true
		destination_selected.emit(null)
