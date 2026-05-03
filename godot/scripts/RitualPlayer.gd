extends Node

# 視覺儀式播放器（autoload）
# M10 版：完整 0.9s 進入 / 1.0s 結束 + letterbox 黑邊（cinematic）+ 左右薄紅邊
# 對應實作用規格書 S4

# === 時間常數 ===
const PAUSE_TIME := 0.3              # Phase 1: 暫停 + letterbox slide-in
const FADE_TIME := 0.3               # 結束儀式 / abort 收 letterbox 用
const BODY_FROZEN_ALPHA := 0.2       # 0.5 → 0.2：proxy 與 body 同位後 proxy 更突出
const BODY_NORMAL_COLOR := Color(1, 1, 1, 1.0)

# === C1 雙影分裂回合（取代 50px 側位移）===
# 按 R 後從 proxy 位置朝 ±X 展開兩道殘影、再收回中央合併成 proxy
# proxy 與 body 始終在同位置，玩家不被搬動，但保留「分裂 → 統合」的視覺事件
const SPLIT_GHOST_OFFSET := 28.0     # 兩道殘影朝兩側展開距離
const SPLIT_EXPAND_TIME := 0.2       # Phase 2a：展開時長
const SPLIT_MERGE_TIME := 0.2        # Phase 2b：收回 + proxy 顯形 + body 淡退
const SPLIT_GHOST_PEAK_ALPHA := 0.55 # 殘影最亮 α

# === Letterbox 黑邊 ===
const LETTERBOX_HEIGHT := 40.0       # 上下黑邊各 40px（細邊 cinematic）

# === 進入儀式分裂粒子 ===
const PARTICLE_AMOUNT := 80
const PARTICLE_LIFETIME := 0.8

# === 結束儀式：分身散成光點向上飄 ===
const END_DRIFT_PARTICLE_AMOUNT := 30
const END_DRIFT_LIFETIME := 0.7

# === 分身擦過本體的小粒子 ===
const BRUSH_PARTICLE_AMOUNT := 14
const BRUSH_PARTICLE_LIFETIME := 0.4

# === 分身擦過本體的本體 tint flash ===
# alpha 必須高於 BODY_FROZEN_ALPHA 才看得到 flash（0.6 > 0.2）
const BRUSH_TINT_COLOR := Color(0.6, 0.85, 1.0, 0.6)
const BRUSH_TINT_TIME := 0.3

var _canvas_layer: CanvasLayer
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _brush_tint_tween: Tween = null


func _ready() -> void:
	# 即使世界暫停也要能跑（為了 await 暫停期間的 timer 與 tween）
	process_mode = Node.PROCESS_MODE_ALWAYS

	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100  # 蓋在 HUD 之上
	add_child(_canvas_layer)

	# 上黑邊：滿寬、黏在頂部
	# offset_top = -LETTERBOX_HEIGHT 表示位於螢幕頂之上（隱藏狀態）
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color(0, 0, 0, 1)
	_letterbox_top.anchor_left = 0
	_letterbox_top.anchor_right = 1
	_letterbox_top.anchor_top = 0
	_letterbox_top.anchor_bottom = 0
	_letterbox_top.offset_left = 0
	_letterbox_top.offset_right = 0
	_letterbox_top.offset_top = -LETTERBOX_HEIGHT
	_letterbox_top.offset_bottom = 0
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_letterbox_top)

	# 下黑邊：滿寬、黏在底部
	# offset_bottom = +LETTERBOX_HEIGHT 表示位於螢幕底之下（隱藏狀態）
	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.color = Color(0, 0, 0, 1)
	_letterbox_bottom.anchor_left = 0
	_letterbox_bottom.anchor_right = 1
	_letterbox_bottom.anchor_top = 1
	_letterbox_bottom.anchor_bottom = 1
	_letterbox_bottom.offset_left = 0
	_letterbox_bottom.offset_right = 0
	_letterbox_bottom.offset_top = 0
	_letterbox_bottom.offset_bottom = LETTERBOX_HEIGHT
	_letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_letterbox_bottom)

	# 訂閱「分身擦過本體」事件——在重疊點散射小粒子 + 本體 tint flash
	PlayerController.proxy_brushed_body.connect(_on_proxy_brushed_body)


# === Brush effects (穿過本體) ===

func _on_proxy_brushed_body(world_position: Vector2) -> void:
	_spawn_brush_particles(world_position)
	var body = PlayerController.current_player
	if body != null and is_instance_valid(body):
		_play_body_tint_flash(body)


func _play_body_tint_flash(body) -> void:
	if _brush_tint_tween != null and _brush_tint_tween.is_valid():
		_brush_tint_tween.kill()
	var frozen_white := Color(1, 1, 1, BODY_FROZEN_ALPHA)
	_brush_tint_tween = create_tween()
	_brush_tint_tween.tween_property(body, "modulate", BRUSH_TINT_COLOR, BRUSH_TINT_TIME * 0.3)
	_brush_tint_tween.tween_property(body, "modulate", frozen_white, BRUSH_TINT_TIME * 0.7)


# === 進入錄製儀式 ~0.7s（C1 雙影分裂回合）===
# 時間軸：
#   0.0-0.3s  Phase 1：暫停世界、粒子爆散、letterbox slide-in
#   0.3s      解除暫停
#   0.3-0.5s  Phase 2a：兩道殘影從 proxy 位置朝 ±X 展開、α 0 → 0.55
#   0.5-0.7s  Phase 2b：殘影收回中央 + 淡出；proxy α 0 → 1.0；body α 1.0 → 0.2
#   0.7s      proxy 與 body 同位重合、玩家恢復對 proxy 控制
#
# 取消原 50px 側位移：proxy 全程停在原位、玩家不會感覺被搬動。
# 新錄製 / 重錄共用同一儀式（原 animate_split 參數移除）。
func play_recording_start_ritual(body, proxy) -> void:
	proxy.modulate.a = 0.0
	proxy.set_physics_process(false)

	# 粒子於 proxy 位置爆散（既有特效保留）
	_spawn_split_particles(proxy.global_position)

	# Phase 1：暫停 + letterbox slide-in
	get_tree().paused = true
	var phase1 := create_tween().set_parallel()
	phase1.tween_property(_letterbox_top, "offset_top", 0.0, PAUSE_TIME)
	phase1.tween_property(_letterbox_top, "offset_bottom", LETTERBOX_HEIGHT, PAUSE_TIME)
	phase1.tween_property(_letterbox_bottom, "offset_top", -LETTERBOX_HEIGHT, PAUSE_TIME)
	phase1.tween_property(_letterbox_bottom, "offset_bottom", 0.0, PAUSE_TIME)
	await get_tree().create_timer(PAUSE_TIME, true).timeout
	get_tree().paused = false

	# 預備兩道殘影（Polygon2D 視覺複製、無物理）
	var center_pos: Vector2 = proxy.global_position
	var visual := proxy.get_node("Visual") as Polygon2D
	var parent_node: Node = proxy.get_parent()
	var ghost_left := _spawn_ghost(parent_node, center_pos, visual)
	var ghost_right := _spawn_ghost(parent_node, center_pos, visual)

	# Phase 2a：殘影展開到 ±SPLIT_GHOST_OFFSET、α 0 → SPLIT_GHOST_PEAK_ALPHA
	var phase2a := create_tween().set_parallel()
	phase2a.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	phase2a.tween_property(ghost_left, "global_position:x", center_pos.x - SPLIT_GHOST_OFFSET, SPLIT_EXPAND_TIME)
	phase2a.tween_property(ghost_right, "global_position:x", center_pos.x + SPLIT_GHOST_OFFSET, SPLIT_EXPAND_TIME)
	phase2a.tween_property(ghost_left, "modulate:a", SPLIT_GHOST_PEAK_ALPHA, SPLIT_EXPAND_TIME)
	phase2a.tween_property(ghost_right, "modulate:a", SPLIT_GHOST_PEAK_ALPHA, SPLIT_EXPAND_TIME)
	await phase2a.finished

	# Phase 2b：殘影收回中央 + 淡出；同時 proxy 顯形、body 淡退
	var phase2b := create_tween().set_parallel()
	phase2b.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	phase2b.tween_property(ghost_left, "global_position:x", center_pos.x, SPLIT_MERGE_TIME)
	phase2b.tween_property(ghost_right, "global_position:x", center_pos.x, SPLIT_MERGE_TIME)
	phase2b.tween_property(ghost_left, "modulate:a", 0.0, SPLIT_MERGE_TIME)
	phase2b.tween_property(ghost_right, "modulate:a", 0.0, SPLIT_MERGE_TIME)
	phase2b.tween_property(proxy, "modulate:a", 1.0, SPLIT_MERGE_TIME)
	phase2b.tween_property(body, "modulate", Color(1, 1, 1, BODY_FROZEN_ALPHA), SPLIT_MERGE_TIME)
	await phase2b.finished

	# 清理殘影
	if is_instance_valid(ghost_left):
		ghost_left.queue_free()
	if is_instance_valid(ghost_right):
		ghost_right.queue_free()

	# 更新 spawn_position 為 proxy 位置（無位移、即按 R 那一格）
	if RecordingManager.current:
		RecordingManager.current.spawn_position = proxy.position

	# 玩家可控
	proxy.set_physics_process(true)


# 雙影輔助：以 source Polygon2D 為模板生成一個視覺殘影、附加到 parent
# z_index = -1 讓殘影排在 proxy 之下，proxy 淡入時自然蓋過
func _spawn_ghost(parent: Node, world_pos: Vector2, source: Polygon2D) -> Polygon2D:
	var ghost := Polygon2D.new()
	ghost.polygon = source.polygon
	ghost.color = source.color
	ghost.modulate = Color(1, 1, 1, 0.0)
	ghost.z_index = -1
	parent.add_child(ghost)
	ghost.global_position = world_pos
	return ghost


# === 結束錄製儀式 ~0.7s ===
# 時間軸：
#   0.0-0.3s  分身輪廓亮一下（modulate 微亮）
#   0.3-0.7s  分身散粒子 + 分身淡出 + 本體淡回 + letterbox slide-out（依 set_delay 並行）
func play_recording_end_ritual(body, proxy) -> void:
	# brush tint tween 還在跑會跟結束 tween 同時寫 modulate 造成閃爍——先收掉
	if _brush_tint_tween != null and _brush_tint_tween.is_valid():
		_brush_tint_tween.kill()

	# Phase A (0.0-0.3s)：分身亮一下
	var bright := Color(1.4, 1.4, 1.6, 1.0)  # modulate >1 變亮
	var phaseA := create_tween()
	phaseA.tween_property(proxy, "modulate", bright, 0.15)
	phaseA.tween_property(proxy, "modulate", Color(1, 1, 1, 1), 0.15)
	await phaseA.finished

	# Phase B (0.3-0.7s, 平行並行):
	#   分身散粒子 + 分身淡出
	#   本體淡回正常
	#   letterbox slide-out 從 0.5 開始
	_spawn_end_drift_particles(proxy.global_position)
	var phaseB := create_tween().set_parallel()
	phaseB.tween_property(proxy, "modulate:a", 0.0, 0.4)
	phaseB.tween_property(body, "modulate", BODY_NORMAL_COLOR, 0.3).set_delay(0.1)
	# letterbox slide-out（Phase B 內 0.2s 後啟動，跑 FADE_TIME）
	phaseB.tween_property(_letterbox_top, "offset_top", -LETTERBOX_HEIGHT, FADE_TIME).set_delay(0.2)
	phaseB.tween_property(_letterbox_top, "offset_bottom", 0.0, FADE_TIME).set_delay(0.2)
	phaseB.tween_property(_letterbox_bottom, "offset_top", 0.0, FADE_TIME).set_delay(0.2)
	phaseB.tween_property(_letterbox_bottom, "offset_bottom", LETTERBOX_HEIGHT, FADE_TIME).set_delay(0.2)
	await phaseB.finished


# A3 短錄製 abort 用：不跑完整結束儀式，但要把 letterbox 收掉
func fade_out_recording_frame() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_letterbox_top, "offset_top", -LETTERBOX_HEIGHT, FADE_TIME)
	tween.tween_property(_letterbox_top, "offset_bottom", 0.0, FADE_TIME)
	tween.tween_property(_letterbox_bottom, "offset_top", 0.0, FADE_TIME)
	tween.tween_property(_letterbox_bottom, "offset_bottom", LETTERBOX_HEIGHT, FADE_TIME)


# 在指定位置生成「分裂瞬間」的散逸粒子（不變，從 M4 沿用）
func _spawn_split_particles(world_position: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.position = world_position
	particles.amount = PARTICLE_AMOUNT
	particles.lifetime = PARTICLE_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	particles.spread = 180.0
	particles.direction = Vector2(0, -1)
	particles.initial_velocity_min = 50.0
	particles.initial_velocity_max = 110.0
	particles.gravity = Vector2(0, 80)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.process_mode = Node.PROCESS_MODE_ALWAYS

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.6, 0.85, 1.0, 1.0))
	gradient.set_color(1, Color(0.6, 0.85, 1.0, 0.0))
	particles.color_ramp = gradient

	var scene_root: Node = get_tree().current_scene
	if scene_root:
		scene_root.add_child(particles)
	else:
		add_child(particles)
	particles.emitting = true

	var cleanup_timer := get_tree().create_timer(PARTICLE_LIFETIME + 0.5, true)
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


# M10：結束儀式分身散成光點向上飄
func _spawn_end_drift_particles(world_position: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.position = world_position
	particles.amount = END_DRIFT_PARTICLE_AMOUNT
	particles.lifetime = END_DRIFT_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 0.4   # 較鬆散、不爆裂
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	particles.spread = 30.0          # 略向上方錐形
	particles.direction = Vector2(0, -1)
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 70.0
	particles.gravity = Vector2(0, -20)  # 向上飄（負重力）
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	particles.process_mode = Node.PROCESS_MODE_ALWAYS

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.7, 0.9, 1.0, 0.9))
	gradient.set_color(1, Color(0.7, 0.9, 1.0, 0.0))
	particles.color_ramp = gradient

	var scene_root: Node = get_tree().current_scene
	if scene_root:
		scene_root.add_child(particles)
	else:
		add_child(particles)
	particles.emitting = true

	var cleanup_timer := get_tree().create_timer(END_DRIFT_LIFETIME + 0.5, true)
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


func _spawn_brush_particles(world_position: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.position = world_position
	particles.amount = BRUSH_PARTICLE_AMOUNT
	particles.lifetime = BRUSH_PARTICLE_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	particles.spread = 180.0
	particles.direction = Vector2(0, -1)
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 70.0
	particles.gravity = Vector2(0, 60)
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.5
	particles.process_mode = Node.PROCESS_MODE_ALWAYS

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.6, 0.85, 1.0, 1.0))
	gradient.set_color(1, Color(0.6, 0.85, 1.0, 0.0))
	particles.color_ramp = gradient

	var scene_root: Node = get_tree().current_scene
	if scene_root:
		scene_root.add_child(particles)
	else:
		add_child(particles)
	particles.emitting = true

	var cleanup_timer := get_tree().create_timer(BRUSH_PARTICLE_LIFETIME + 0.5, true)
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)
