extends Node

# 統一管控本體、RecordingProxy、儀式時序、光點生命週期、光點互動的 autoload
# 對應實作用規格書 S1（含 M5 加入的光點追蹤、M6 加入的光點互動）

signal recording_started
signal recording_ended
# M6：玩家在亮光點上 / 離開所有亮光點
signal player_on_lightpoint(lp)
signal player_off_lightpoint
# 玩家進入 / 離開傳送門範圍（HUD 用來顯示「按 R 傳送」提示）
signal player_on_teleporter(tp)
signal player_off_teleporter
# 錄製期間分身擦過本體（中心距離由「未重疊」變「重疊」時 emit 一次）
# 參數：兩者中點的世界座標，給粒子等視覺效果用
signal proxy_brushed_body(world_position: Vector2)

# 分身與本體中心距離小於此值視為重疊
const OVERLAP_THRESHOLD := 40.0

enum State { NORMAL, RECORDING }
var state: State = State.NORMAL
# 用 Node 而非 Player 型別——避免 Player.gd 的 class_name 與本檔案的循環依賴
var current_player: Node = null
var current_proxy: Node = null

# 槽位 → LightPoint 對應（M5 加入）
var _slot_lightpoints: Dictionary = {}

# M6：玩家當前所在的 LightPoints（可能多個重疊）+ 最近的亮光點
var _lps_with_player: Array = []
var _current_bright_lp = null

# 玩家當前所在的 Teleporters（可能多個重疊）+ 最後進入的視為當前
var _teleporters_with_player: Array = []
var _current_teleporter: Teleporter = null

# M6：本次錄製的目標槽位（-1 = 新錄製、>=0 = 重錄該槽位）
var _target_slot: int = -1

# 分身-本體重疊偵測狀態（每幀刷新，跨 false→true 邊緣 emit proxy_brushed_body）
var _proxy_overlapping_body := false

# 場景根的快取（生成 LightPoint 用）
var _scene_root: Node = null

# M9：本體死亡的 zone 追蹤
# 玩家當前所在的 zone 列表（可重疊）；最後加入的視為「當前 zone」
var _current_zones: Array = []
# M10：錄製啟動時所在的房間，proxy 離開該房間即自動結束錄製
var _recording_start_room: Node = null
# 黑屏覆蓋層（重生流程）
var _death_canvas: CanvasLayer
var _death_rect: ColorRect
const DEATH_FADE_TIME := 0.3
# A3：錄製最短時長（< 此 frame 數則 proxy 死亡時不存槽位）
const MIN_RECORDING_FRAMES := 30  # 0.5s @ 60Hz
# 錄製時長上限：到此自動 end_recording（保住玩家成果，不丟棄）
const MAX_RECORDING_FRAMES := 1800  # 30s @ 60Hz（C1 後縮短：強迫每段為單一原子任務）

const RECORDING_PROXY_SCENE := preload("res://scenes/RecordingProxy.tscn")
const LIGHT_POINT_SCENE := preload("res://scenes/LightPoint.tscn")
const MAP_OVERLAY := preload("res://scenes/MapOverlay.tscn")

# 玩家手動取消 / A3 太短 / 本體死亡中斷時、proxy 與本體淡入淡出時長
# 比正常結束儀式（~0.7s）短、與 letterbox 收回（0.3s）大致同步
const ABORT_FADE_TIME := 0.25


func _ready() -> void:
	RecordingManager.slot_will_overwrite.connect(_on_slot_will_overwrite)
	RecordingManager.slot_assigned.connect(_on_slot_assigned)
	RecordingManager.slot_cleared.connect(_on_slot_cleared)
	# M9：黑屏 CanvasLayer + ColorRect（覆蓋整個畫面用）
	_death_canvas = CanvasLayer.new()
	_death_canvas.layer = 200  # 蓋在 RitualPlayer 紅框（layer 100）之上
	add_child(_death_canvas)
	_death_rect = ColorRect.new()
	_death_rect.color = Color(0, 0, 0, 0)
	_death_rect.anchor_right = 1.0
	_death_rect.anchor_bottom = 1.0
	_death_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_canvas.add_child(_death_rect)


# === M9：Player / TriggerZone 註冊 API ===

# Player._ready 呼叫，連 died signal
func register_player(p) -> void:
	if not p.died.is_connected(_on_player_died):
		p.died.connect(_on_player_died)


# TriggerZone._ready 呼叫，連 player_entered/exited signal
func register_zone(zone) -> void:
	zone.player_entered.connect(_on_zone_entered)
	zone.player_exited.connect(_on_zone_exited)


func _on_zone_entered(zone) -> void:
	if not zone in _current_zones:
		_current_zones.append(zone)


func _on_zone_exited(zone) -> void:
	_current_zones.erase(zone)


# 取最後進入的 zone 當作「當前」zone（重置範圍）
func get_current_zone():
	if _current_zones.is_empty():
		return null
	return _current_zones[-1]


# 每幀偵測分身-本體重疊（僅錄製中且 proxy 已被儀式啟用後）
func _physics_process(_delta: float) -> void:
	if state != State.RECORDING:
		_proxy_overlapping_body = false
		return
	if current_player == null or current_proxy == null:
		return
	# 儀式期間 proxy.set_physics_process=false，跳過避免在分裂淡入時誤觸
	if not current_proxy.is_physics_processing():
		return

	# 錄製時長上限：自動結束（保住玩家成果、走完整 end_recording 儀式）
	if RecordingManager.current != null and \
			RecordingManager.current.input_frames.size() >= MAX_RECORDING_FRAMES:
		print("[CTRL] 達到錄製時長上限 %.1fs，自動結束" % (MAX_RECORDING_FRAMES / 60.0))
		end_recording()
		return

	# Proxy 離開錄製起始房間 → 自動結束（當作完成錄製，走標準 end_recording）
	if _recording_start_room != null and is_instance_valid(_recording_start_room):
		if not _recording_start_room.contains(current_proxy.global_position):
			print("[CTRL] Proxy 離開錄製起始房間，自動結束")
			end_recording()
			return

	var dist: float = current_player.position.distance_to(current_proxy.position)
	var now_overlap := dist < OVERLAP_THRESHOLD
	if now_overlap and not _proxy_overlapping_body:
		var midpoint: Vector2 = (current_player.global_position + current_proxy.global_position) * 0.5
		proxy_brushed_body.emit(midpoint)
	_proxy_overlapping_body = now_overlap


func is_recording() -> bool:
	return state == State.RECORDING


func get_active_player() -> Node:
	if state == State.RECORDING:
		return current_proxy
	return current_player


# 取得玩家本體（用 group 查詢，比 current_player 更穩定）
func _get_player_real() -> Node:
	var nodes = get_tree().get_nodes_in_group("player_real")
	if nodes.is_empty():
		return null
	return nodes[0]


# M6：取得玩家當前所在的亮光點（多個重疊則取最近的）
func get_current_bright_lp():
	return _current_bright_lp


# M6：取得當前錄製的目標槽位（-1 = 新錄製）
func get_target_slot() -> int:
	return _target_slot


# === 錄製生命週期 ===

# 由 Player._handle_special_actions 呼叫
# target_slot >= 0 表示重錄該槽位（站在亮光點上按 R 觸發）
# target_slot == -1 表示新錄製
func start_recording(player, target_slot: int = -1) -> void:
	if state != State.NORMAL:
		return
	state = State.RECORDING
	current_player = player
	_scene_root = player.get_parent()
	_target_slot = target_slot
	# M10：記下錄製啟動時所在房間，proxy 離開即自動結束
	_recording_start_room = RoomManager.current_room

	# 提前 emit recording_started：讓 BGM ducking 等訂閱者**先**降音量、
	# 之後再發 record_start SFX 與儀式音、避免被 BGM 蓋掉
	recording_started.emit()

	# 1. 凍結本體 + 所有 active Clone（M7）
	player.freeze()
	_freeze_all_clones()

	# 2. 決定 proxy 起始位置
	#    新錄製：proxy 在本體位置
	#    重錄：proxy 在 LP 中心（snap）
	# C1 後 proxy 不再側位移、新錄/重錄共用同一儀式
	var proxy: Node2D = RECORDING_PROXY_SCENE.instantiate()
	if target_slot >= 0:
		var lp = _slot_lightpoints.get(target_slot)
		if lp != null and is_instance_valid(lp):
			proxy.position = lp.position
		else:
			# Fallback：找不到 LP（不該發生）→ 退回新錄製行為
			proxy.position = player.position
			_target_slot = -1
			print("[CTRL] 警告：找不到槽位 %d 的光點，退回新錄製" % target_slot)
	else:
		proxy.position = player.position

	_scene_root.add_child(proxy)
	current_proxy = proxy

	# C1：proxy 與 body 起始同位置 → 預設 overlap 為 true
	# 否則 ritual 結束第一個 physics frame 會 false→true 邊緣誤觸發 brush 粒子+tint
	# 玩家須真的「走出 40px 再回來」才會 emit brush（這才是擦過的本意）
	_proxy_overlapping_body = true

	# 3. 通知 RecordingManager（spawn_pos 用 proxy 位置，儀式內可能再更新）
	RecordingManager.start_recording(proxy.position)

	# 4. 播放儀式（C1：雙影分裂回合、無位移）
	AudioManager.play_sfx("record_start")
	RitualPlayer.play_recording_start_ritual(player, proxy)

	# 開始錄製 → 5 槽全滿時最舊 LP 顯示 OLD 警告
	_update_lp_fifo_warnings()

	if target_slot >= 0:
		print("[CTRL] Re-recording slot %d @ %s" % [target_slot + 1, proxy.position])
	else:
		print("[CTRL] Recording started @ ", player.position)


# 由 RecordingProxy._handle_special_actions 呼叫
func end_recording() -> void:
	if state != State.RECORDING:
		return
	state = State.NORMAL
	AudioManager.play_sfx("record_end")

	# 依 _target_slot 決定走 FIFO 流程還是 replace_slot 流程
	var rec: Recording
	if _target_slot >= 0:
		rec = RecordingManager.stop_recording_to_slot(_target_slot)
	else:
		rec = RecordingManager.stop_recording()
	_target_slot = -1
	if rec != null:
		GameStats.recording_completed_count += 1

	if current_proxy:
		current_proxy.set_physics_process(false)

	var p := current_player
	var pr := current_proxy
	current_player = null
	current_proxy = null

	if p and pr:
		await RitualPlayer.play_recording_end_ritual(p, pr)

	if pr:
		pr.queue_free()
	if p:
		p.unfreeze()
	# M7：解凍所有 active Clone
	_unfreeze_all_clones()
	_recording_start_room = null

	# 錄製結束 → 清掉所有 OLD 警告
	_update_lp_fifo_warnings()

	print("[CTRL] Recording ended (rec saved: ", rec != null, ")")
	recording_ended.emit()


# === M7：批次凍結／解凍所有 active Clone ===
# 用 "clone" group 找；is_instance_valid 防止上一幀剛 queue_free 的殘骸
func _freeze_all_clones() -> void:
	for c in get_tree().get_nodes_in_group("clone"):
		if is_instance_valid(c):
			c.freeze()


func _unfreeze_all_clones() -> void:
	for c in get_tree().get_nodes_in_group("clone"):
		if is_instance_valid(c):
			c.unfreeze()


# === M9：本體死亡重置流程 ===
# Player.die() 觸發 → 黑屏 0.3s → 清分身 + zone 殘骸轉痕跡 → 重生 → 黑屏淡出
func _on_player_died() -> void:
	# 防御：錄製中本體無法移動、理論上不會死亡，但若 race 發生先 abort 錄製
	if state == State.RECORDING:
		_abort_recording()

	await _run_fade_transition(DEATH_FADE_TIME, func():
		# 1. 清所有 active Clone
		for c in get_tree().get_nodes_in_group("clone"):
			if is_instance_valid(c):
				c.queue_free()

		# 2. 當前 zone 內物理殘骸 → 痕跡（跨 zone 不變）
		var zone = get_current_zone()
		if zone != null:
			CarcassManager.reset_zone(zone)
		else:
			print("[CTRL] Player 死亡時未在任何 zone 內，跳過 reset_zone")

		# 3. 重生本體
		var p = _get_player_real()
		if p != null and p.has_method("respawn"):
			p.respawn()
	, DEATH_FADE_TIME)

	print("[CTRL] 本體重生完成")


# 黑屏轉場 helper：fade-in → 跑 mid_action → fade-out
# 死亡與傳送共用、各自設不同 fade 時長
# mid_action 在全黑時執行（玩家看不到位置變化）
func _run_fade_transition(fade_in_time: float, mid_action: Callable, fade_out_time: float) -> void:
	var t1 := create_tween()
	t1.tween_property(_death_rect, "color:a", 1.0, fade_in_time)
	await t1.finished

	mid_action.call()

	var t2 := create_tween()
	t2.tween_property(_death_rect, "color:a", 0.0, fade_out_time)
	await t2.finished


# === Teleporter 互動（玩家進出範圍偵測 + 觸發傳送）===

# Teleporter._ready 時呼叫，連 zone 信號
func register_teleporter(tp: Teleporter) -> void:
	tp.player_entered_zone.connect(_on_teleporter_entered)
	tp.player_exited_zone.connect(_on_teleporter_exited)


func _on_teleporter_entered(tp: Teleporter) -> void:
	if not _teleporters_with_player.has(tp):
		_teleporters_with_player.append(tp)
	_update_current_teleporter()


func _on_teleporter_exited(tp: Teleporter) -> void:
	_teleporters_with_player.erase(tp)
	_update_current_teleporter()


# 取最後進入的 teleporter 當作「當前」、與 zone / lp 同邏輯
func _update_current_teleporter() -> void:
	var new_tp: Teleporter = null
	if not _teleporters_with_player.is_empty():
		new_tp = _teleporters_with_player[-1]
	if new_tp != _current_teleporter:
		_current_teleporter = new_tp
		if new_tp != null:
			player_on_teleporter.emit(new_tp)
		else:
			player_off_teleporter.emit()


# Player.gd R 鍵優先序判定用
func get_current_teleporter() -> Teleporter:
	return _current_teleporter


# 由 Player._handle_special_actions 呼叫；錄製中禁用
# 流程：開地圖（選擇模式、source = 玩家所在 tp）→ await 玩家點選目標 → fade + 瞬移
# 玩家按 ESC 取消會 emit null、本函式直接 return（不傳送）
#
# 重要：fade 期間必須 freeze 玩家、否則：
#   1. record action 同時綁 LMB（見 project.godot）
#   2. 玩家點地圖目標的 LMB 等於按了 record
#   3. MapOverlay._close 解除 pause 後、Player._physics_process 同幀又會看到 record just_pressed
#   4. Player 又呼叫 activate_teleporter、開出第二張地圖
# Player.freeze() 把 is_frozen 設 true、_physics_process 早退、不處理 special actions
func activate_teleporter(player: Node2D, source_tp: Teleporter) -> void:
	if state == State.RECORDING:
		return
	if source_tp == null or not is_instance_valid(source_tp):
		return
	var overlay = MAP_OVERLAY.instantiate()
	add_child(overlay)
	overlay.enter_selection_mode(source_tp)
	# await signal 第一個參數；ESC/Tab 取消時 emit null
	var dest_tp = await overlay.destination_selected
	if dest_tp == null or not is_instance_valid(dest_tp):
		return
	# 凍結玩家、避免 LMB-as-record 在 unpause 後同幀又觸發 R 邏輯
	player.freeze()
	var dest: Vector2 = dest_tp.global_position
	await _run_fade_transition(0.15, func():
		player.position = dest
		player.velocity = Vector2.ZERO
	, 0.15)
	player.unfreeze()
	print("[CTRL] 傳送至 %s（從 %s 到 %s）" % [dest, source_tp.name, dest_tp.name])


# === M9 / S15：A3 — RecordingProxy 撞 hazard ===
# 由 Hazard 在偵測到 RecordingProxy 進入時呼叫，傳入死亡位置
# 流程依錄製時長分流：
#   < 0.5s（30 frames）：丟棄錄製、不留殘骸
#   >= 0.5s：存槽位、生殘骸、跑結束儀式
func handle_recording_proxy_death(death_position: Vector2) -> void:
	if state != State.RECORDING:
		return

	var frames := 0
	if RecordingManager.current != null:
		frames = RecordingManager.current.input_frames.size()

	if frames < MIN_RECORDING_FRAMES:
		print("[CTRL] A3：錄製太短（%d frames < %d），丟棄" % [frames, MIN_RECORDING_FRAMES])
		_abort_recording()
		return

	# 正常存槽位 + 生殘骸
	state = State.NORMAL
	var rec: Recording
	if _target_slot >= 0:
		rec = RecordingManager.stop_recording_to_slot(_target_slot)
	else:
		rec = RecordingManager.stop_recording()
	_target_slot = -1
	if rec != null:
		GameStats.recording_completed_count += 1

	if current_proxy:
		current_proxy.set_physics_process(false)

	var p := current_player
	var pr := current_proxy
	current_player = null
	current_proxy = null

	# 殘骸生在死亡位置（rec.slot_index 在 stop_recording 已指派）
	if rec != null and rec.slot_index >= 0 and _scene_root != null:
		CarcassManager.register_death(rec.slot_index, death_position, _scene_root)

	if p and pr:
		await RitualPlayer.play_recording_end_ritual(p, pr)

	if pr:
		pr.queue_free()
	if p:
		p.unfreeze()
	_unfreeze_all_clones()

	# 錄製結束 → 清掉所有 OLD 警告
	_update_lp_fifo_warnings()

	print("[CTRL] A3：proxy 死亡、錄製存到槽位 %d、殘骸生成 @ %s" % [
		(rec.slot_index + 1) if rec else -1, death_position
	])
	recording_ended.emit()


# 由 RecordingProxy 在玩家錄製中按 RMB/E 時呼叫
# 公開包裝、保留 _abort_recording 為內部用（A3 太短 / 死亡路徑各有自己語意）
func cancel_recording_by_user() -> void:
	if state != State.RECORDING:
		return
	print("[CTRL] 玩家手動取消錄製")
	_abort_recording()


# 中斷錄製、丟棄資料（A3 太短時 / 本體在錄製中死亡時 / 玩家手動取消用）
# 不跑完整結束儀式（沒亮起 / 散粒子）、但 proxy 與本體用 ABORT_FADE_TIME 淡入淡出避免瞬切突兀
# 與 letterbox 收回（0.3s）大致同步、體感平順
func _abort_recording() -> void:
	if state != State.RECORDING:
		return
	state = State.NORMAL
	RecordingManager.discard_recording()
	_target_slot = -1

	var p := current_player
	var pr := current_proxy
	current_player = null
	current_proxy = null

	# Proxy：停物理（不再回應輸入或繼續運動）+ 淡出 0.25s 後 queue_free
	# tween 綁在 pr 自己、若意外被外部 free 也會自動 kill、不會 tween 已釋放物件
	if pr and is_instance_valid(pr):
		pr.set_physics_process(false)
		var pr_tween := pr.create_tween()
		pr_tween.tween_property(pr, "modulate:a", 0.0, ABORT_FADE_TIME)
		pr_tween.tween_callback(pr.queue_free)
	# 本體：modulate 從凍結中的 0.2 alpha 平滑淡回正常白；同時立刻 unfreeze
	# 玩家在淡入過程中已可操作（取消的「快速恢復控制」手感）
	if p and is_instance_valid(p):
		var p_tween := p.create_tween()
		p_tween.tween_property(p, "modulate", Color(1, 1, 1, 1), ABORT_FADE_TIME)
		p.unfreeze()
	# 單獨收掉 RitualPlayer 的紅框（既有 0.3s）
	RitualPlayer.fade_out_recording_frame()
	_unfreeze_all_clones()
	_recording_start_room = null

	# 錄製中斷 → 清掉所有 OLD 警告
	_update_lp_fifo_warnings()

	recording_ended.emit()


# M6：站在亮光點上按 Q 時呼叫，刪除該槽位
func delete_slot(slot_index: int) -> void:
	if state != State.NORMAL:
		return
	if not _slot_lightpoints.has(slot_index):
		return
	RecordingManager.delete_slot(slot_index)


# === LightPoint 生命週期管理 ===

# 槽位被 FIFO 覆蓋前：把舊光點轉痕跡
# 注意：replace_slot（重錄）不會 emit 此信號，所以重錄時 LP 不轉痕跡
func _on_slot_will_overwrite(slot_index: int, _old_recording) -> void:
	var old_lp = _slot_lightpoints.get(slot_index)
	if old_lp != null and is_instance_valid(old_lp):
		old_lp.convert_to_trace()
	_slot_lightpoints.erase(slot_index)
	_update_current_lp()


# 槽位被指派新錄製：在錄製起點生成新光點
# 重錄情況下 LP 已存在於該槽位，本函式略過（LP 視覺保持不動）
func _on_slot_assigned(slot_index: int, recording) -> void:
	if _slot_lightpoints.has(slot_index):
		# 重錄：LP 已存在、保持原位、不重生
		print("[CTRL] 槽位 %d 重錄完成（LP 留在原位）" % (slot_index + 1))
		_update_lp_fifo_warnings()
		return
	if _scene_root == null or not is_instance_valid(_scene_root):
		print("[CTRL] _scene_root 無效，無法生成光點")
		return
	var lp = LIGHT_POINT_SCENE.instantiate()
	lp.position = recording.spawn_position
	lp.set_slot(slot_index)
	_scene_root.add_child(lp)
	_slot_lightpoints[slot_index] = lp
	# 連接 LP 的 body_entered/exited 以追蹤玩家進出
	lp.body_entered.connect(_on_lp_body_entered.bind(lp))
	lp.body_exited.connect(_on_lp_body_exited.bind(lp))
	print("[CTRL] 槽位 %d 光點生成 @ %s" % [slot_index + 1, recording.spawn_position])
	# 槽位狀態變動 → 重新計算 FIFO OLD 警告（保險、即使錄製中信號也能正確）
	_update_lp_fifo_warnings()


# 槽位被主動刪除（M6 Q 鍵）：光點淡出消失
func _on_slot_cleared(slot_index: int) -> void:
	var lp = _slot_lightpoints.get(slot_index)
	if lp != null and is_instance_valid(lp):
		lp.fade_out_and_remove()
		# 立即從玩家重疊列表移除，避免 context hint 殘留 0.4 秒
		_lps_with_player.erase(lp)
	_slot_lightpoints.erase(slot_index)
	_update_current_lp()
	# 槽位刪除後可能不再滿、清掉 OLD
	_update_lp_fifo_warnings()


# 計算當前哪些 LP 該顯示 OLD（FIFO 即將替換警告）
# 條件：state == RECORDING + 新錄製（非重錄）+ 5 槽全滿 → 最舊 LP 顯示 OLD
# 與 HUD 既有的 ⚠ FIFO 警告判定條件一致（HUD.gd _process 內 fifo_warning_slot 邏輯）
func _update_lp_fifo_warnings() -> void:
	var should_warn: bool = (
		state == State.RECORDING
		and _target_slot == -1
		and RecordingManager.filled_count() == RecordingManager.SLOT_COUNT
	)
	var oldest: int = RecordingManager.get_oldest_slot_index() if should_warn else -1
	for slot_idx in _slot_lightpoints:
		var lp = _slot_lightpoints[slot_idx]
		if is_instance_valid(lp) and lp.has_method("set_fifo_warning"):
			lp.set_fifo_warning(slot_idx == oldest)


# === LightPoint 玩家進出偵測（M6）===

func _on_lp_body_entered(body: Node, lp: Node) -> void:
	if body.is_in_group("player_real"):
		if not _lps_with_player.has(lp):
			_lps_with_player.append(lp)
		_update_current_lp()


func _on_lp_body_exited(body: Node, lp: Node) -> void:
	if body.is_in_group("player_real"):
		_lps_with_player.erase(lp)
		_update_current_lp()


# 重新評估當前所在的亮光點，發出對應信號
func _update_current_lp() -> void:
	var new_lp = _find_closest_bright_lp()
	if new_lp != _current_bright_lp:
		_current_bright_lp = new_lp
		if new_lp != null:
			player_on_lightpoint.emit(new_lp)
		else:
			player_off_lightpoint.emit()


func _find_closest_bright_lp():
	var player = _get_player_real()
	if player == null or _lps_with_player.is_empty():
		return null
	var closest = null
	var closest_dist_sq := INF
	for lp in _lps_with_player:
		if not is_instance_valid(lp):
			continue
		# 過濾掉痕跡光點（state != BRIGHT）
		if "state" in lp and lp.state != 0:  # 0 = BRIGHT enum
			continue
		var dist_sq: float = player.position.distance_squared_to(lp.position)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			closest = lp
	return closest
