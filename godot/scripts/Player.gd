extends CharacterBody2D
class_name Player

# === M9：死亡與重生 signal ===
# 由 Hazard.gd 在偵測到本體進入時呼叫 die()
# PlayerController 訂閱本 signal 跑黑屏 + 清分身 + reset_zone + respawn 流程
signal died

# === 走跳手感調校區 ===
# M0 階段你會花最多時間在這幾個數字上。每改一個跑一次遊戲玩 1 分鐘。
# 數值單位：像素／秒、像素／秒平方。

# 水平移動（Limbo 重量路線：放慢、給慣性）
const MAX_SPEED := 190.0          # 跑到底的速度（慢一點才有重量）
const ACCEL := 2000.0             # 加速度（0.1 秒到頂速，有「啟動」感而非瞬移）
const GROUND_DECEL := 1600.0      # 地面放開方向時的減速
const AIR_DECEL := 700.0          # 空中減速明顯比地面小，營造離地後的飄

# 跳躍
const JUMP_VELOCITY := -500.0     # 起跳初速
const JUMP_CUT_VELOCITY := -150.0 # 「短按跳」上升被截斷後的速度

# 不對稱重力：上升輕、下降重，讓跳躍上升飄逸、落地俐落
# Celeste、Mario、Hollow Knight 都這樣做
const GRAVITY_RISING := 1200.0    # 上升時的重力（比較輕）
const GRAVITY_FALLING := 2000.0   # 下降時的重力（1.7x 不對稱比，比 2.5x 自然）
const MAX_FALL_SPEED := 700.0     # 終端速度（不會掉得無限快）

# 容錯機制（這兩個讓跳躍從「準確」變「舒服」）
const COYOTE_TIME := 0.15        # 離地後 0.15 秒內仍可跳
const JUMP_BUFFER := 0.15        # 落地前 0.15 秒按跳，落地立即跳

# 移動平台繼承速度上限（M13）
# 玩家踩到 AnimatableBody2D（如 TriggeredPlatform）跳起時、CharacterBody2D 預設繼承
# 平台速度（platform_on_leave = ADD_VELOCITY）。若平台速度 >> MAX_SPEED 會「暴衝」感。
# 這個上限只在「剛離地」那 1 frame clamp velocity.x、避免過度繼承；空中物理照常
# 比 MAX_SPEED(190) 略高、保留「平台給點推力」的物理感、但不暴衝
const MAX_INHERIT_SPEED := 220.0

# === 內部狀態 ===
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var spawn_position: Vector2

# 面向方向：1 = 右、-1 = 左。每次水平移動時更新；停下後保留最後方向
# 給錄製儀式用——分身從本體的面向側淡入
var facing_dir: int = 1

# === 凍結機制 ===
# 錄製期間 PlayerController.start_recording 會呼叫 freeze()
# 結束錄製時 PlayerController.end_recording 會呼叫 unfreeze()
var is_frozen := false
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0

# === M9：死亡狀態 ===
# 由 Hazard 偵測到本體後呼叫 die()，emit died 給 PlayerController 處理黑屏 + 重生
# is_dead 防止 die() 被連續觸發
var is_dead := false

# === 輸入狀態（每個 tick 由 _read_inputs() 填入）===
# 抽出這層，是為了讓 Clone 子類可以覆寫成「從 Recording 資料讀」而非鍵盤
var input_left := false
var input_right := false
var input_jump := false
var input_jump_prev := false  # 上一 tick 的跳躍按住狀態，用來推導 just_pressed/just_released

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	spawn_position = position
	# 加入 "player_real" group：讓 Exit 等只認玩家本人的東西能用 group 過濾
	# Clone 不呼叫 super._ready()，所以 Clone 不會在這個 group 裡 — 自然分流
	# RecordingProxy 也不呼叫 super._ready()，同樣不在 group 裡
	add_to_group("player_real")
	# M9：向 PlayerController 註冊，讓它接 died signal
	PlayerController.register_player(self)


func _physics_process(delta: float) -> void:
	# 凍結期間（錄製中本體 / 之後 M7 凍結的 Clone）：完全不動、不讀輸入
	if is_frozen:
		return

	_read_inputs()
	_handle_special_actions()

	# _handle_special_actions 可能呼叫 PlayerController.start_recording 進而 freeze 自己
	if is_frozen:
		return

	_apply_movement(delta)
	_record_frame_if_needed()

	# 把這 tick 的跳躍狀態存起來，下一 tick 用來推導 just_pressed/just_released
	input_jump_prev = input_jump


# === 預設：讀鍵盤 ===
# Clone 會覆寫成從 recording.input_frames[current_frame] 讀
# RecordingProxy 沿用本預設（讀鍵盤）
func _read_inputs() -> void:
	input_left = Input.is_action_pressed("move_left")
	input_right = Input.is_action_pressed("move_right")
	input_jump = Input.is_action_pressed("jump")


# === 預設：處理本體特定按鍵 ===
# R 鍵優先序：① 在傳送門範圍 → 傳送（最高）② 站亮光點上 → 重錄該槽位 ③ 預設 → 新錄製
# Q 鍵：站亮光點上才有效（刪除該槽位）
# Clone 覆寫成 pass（分身不應該觸發錄製）
# RecordingProxy 覆寫成「R = 結束錄製」
func _handle_special_actions() -> void:
	if Input.is_action_just_pressed("record"):
		# ① 傳送門最優先
		var tp = PlayerController.get_current_teleporter()
		if tp != null:
			PlayerController.activate_teleporter(self, tp)
			return
		# ② 站亮光點上 → 重錄該槽位
		var lp = PlayerController.get_current_bright_lp()
		if lp != null:
			PlayerController.start_recording(self, lp.slot_index)
		else:
			# ③ 標準新錄製（FIFO）
			# 限制：新錄製只能在地面起手——避免空中凍結懸浮、解凍墜落、儀式感斷裂
			if not is_on_floor():
				return
			PlayerController.start_recording(self)
	elif Input.is_action_just_pressed("delete_slot"):
		# 站亮光點上才有效
		var lp = PlayerController.get_current_bright_lp()
		if lp != null:
			PlayerController.delete_slot(lp.slot_index)


# === 共用的物理移動邏輯 ===
# Player 與 Clone 都用同一份，只是 input_left/right/jump 來源不同
func _apply_movement(delta: float) -> void:
	# --- 1. 水平移動 ---
	# 從 input 狀態算方向（取代 Input.get_axis，因為 Clone 不能用 Input）
	var dir := 0.0
	if input_left:
		dir -= 1.0
	if input_right:
		dir += 1.0

	if dir != 0.0:
		# 更新面向方向（給錄製儀式的分身偏移用）
		facing_dir = 1 if dir > 0.0 else -1
		velocity.x = move_toward(velocity.x, dir * MAX_SPEED, ACCEL * delta)
	else:
		var d := GROUND_DECEL if is_on_floor() else AIR_DECEL
		velocity.x = move_toward(velocity.x, 0.0, d * delta)

	# --- 2. 重力（不對稱：上升用輕的、下降用重的）---
	if not is_on_floor():
		var g := GRAVITY_RISING if velocity.y < 0.0 else GRAVITY_FALLING
		velocity.y += g * delta
		if velocity.y > MAX_FALL_SPEED:
			velocity.y = MAX_FALL_SPEED

	# --- 3. Coyote time ---
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	# --- 4. Jump buffer（從 input_jump 推導 just_pressed）---
	# just_pressed = 這 tick 按住 && 上 tick 沒按住
	var jump_just_pressed := input_jump and not input_jump_prev
	if jump_just_pressed:
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	# --- 5. 真正執行跳躍 ---
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		_play_jump_sfx()

	# --- 6. 變高跳：跳到一半放開，把上升速度截斷 ---
	# just_released = 這 tick 沒按住 && 上 tick 按住
	var jump_just_released := input_jump_prev and not input_jump
	if jump_just_released and velocity.y < JUMP_CUT_VELOCITY:
		velocity.y = JUMP_CUT_VELOCITY

	# --- 7. 套用移動 + 處理碰撞 ---
	var was_on_floor := is_on_floor()
	move_and_slide()

	# --- 8. 平台繼承速度 clamp（M13）---
	# 偵測「剛離地」（跳起 / 走出平台邊緣）那一幀
	# 把繼承自移動平台的水平速度 clamp 到 MAX_INHERIT_SPEED
	# 之後空中受重力、AIR_DECEL、玩家方向鍵等正常物理影響
	if was_on_floor and not is_on_floor():
		velocity.x = clampf(velocity.x, -MAX_INHERIT_SPEED, MAX_INHERIT_SPEED)


# === 預設：把這 tick 的輸入存進 RecordingManager ===
# Clone 會覆寫成 pass（分身的輸入是回放，不應該再被錄）
# RecordingProxy 沿用本預設（會錄自己的輸入）
func _record_frame_if_needed() -> void:
	if RecordingManager.is_recording():
		RecordingManager.add_frame(input_left, input_right, input_jump)


# === 預設：跳躍音效用全域預設音量 ===
# Clone 會覆寫成低 6 dB（≈ -50% 振幅、避免一堆分身同時跳很吵）
func _play_jump_sfx() -> void:
	AudioManager.play_sfx("jump")


# === 外部驅動的速度修改（給彈簧 / 推力機關用） ===
# 由 Spring 等機關 body_entered 時呼叫
# 重置 coyote/buffer 避免「彈起後立刻又能跳」造成不可預期行為
# Clone 透過繼承自動有此方法
func apply_bounce(vy: float) -> void:
	velocity.y = vy
	coyote_timer = 0.0
	jump_buffer_timer = 0.0


# === 凍結機制（M4 新增） ===
# 由 PlayerController.start_recording 呼叫
# 凍結期間：不執行 _physics_process、無物理碰撞、velocity 歸零
func freeze() -> void:
	if is_frozen:
		return
	is_frozen = true
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO


# 由 PlayerController.end_recording 呼叫
func unfreeze() -> void:
	if not is_frozen:
		return
	is_frozen = false
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask


# === M9：死亡與重生 ===

# M10：由 Checkpoint 在玩家碰到時呼叫，更新重生位置
func set_spawn(pos: Vector2) -> void:
	spawn_position = pos


# 由 Hazard.gd 在偵測到 Player（本體）進入時呼叫
# 立刻發 died signal、鎖物理（避免在黑屏期間繼續移動）；重生由 PlayerController 流程驅動
func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	is_frozen = true  # 借用 freeze 的 _physics_process 早退
	GameStats.death_count += 1
	AudioManager.play_sfx("die")
	died.emit()


# 由 PlayerController 在黑屏到底、準備淡出前呼叫
# 重置 position 與物理狀態到 spawn_position（由 Checkpoint.set_spawn 動態更新）
func respawn() -> void:
	is_dead = false
	is_frozen = false
	position = spawn_position
	velocity = Vector2.ZERO
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	input_jump_prev = false
	modulate = Color(1, 1, 1, 1)
