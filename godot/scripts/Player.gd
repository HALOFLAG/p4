extends CharacterBody2D

# === 走跳手感調校區 ===
# M0 階段你會花最多時間在這幾個數字上。每改一個跑一次遊戲玩 1 分鐘。
# 數值單位：像素／秒、像素／秒平方。

# 水平移動（Limbo 重量路線：放慢、給慣性）
const MAX_SPEED := 190.0          # 跑到底的速度（之前 250→180，慢一點才有重量）
const ACCEL := 2000.0             # 加速度（0.1 秒到頂速，有「啟動」感而非瞬移）
const GROUND_DECEL := 1600.0      # 地面放開方向時的減速
const AIR_DECEL := 700.0          # 空中減速明顯比地面小，營造離地後的飄

# 跳躍
const JUMP_VELOCITY := -500.0     # 起跳初速（之前 600→480，更像「人在跳」）
const JUMP_CUT_VELOCITY := -150.0 # 「短按跳」上升被截斷後的速度

# 不對稱重力：上升輕、下降重，讓跳躍上升飄逸、落地俐落
# Celeste、Mario、Hollow Knight 都這樣做
const GRAVITY_RISING := 1200.0    # 上升時的重力（比較輕）
const GRAVITY_FALLING := 2000.0   # 下降時的重力（1.7x 不對稱比，比 2.5x 自然）
const MAX_FALL_SPEED := 700.0     # 終端速度（不會掉得無限快）

# 容錯機制（這兩個讓跳躍從「準確」變「舒服」）
const COYOTE_TIME := 0.15        # 離地後 0.15 秒內仍可跳
const JUMP_BUFFER := 0.15        # 落地前 0.15 秒按跳，落地立即跳

# === 內部狀態 ===
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var spawn_position: Vector2
var dead := false  # 自爆動畫中、等待重生時為 true

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
	add_to_group("player_real")


func _physics_process(delta: float) -> void:
	if dead:
		return

	_read_inputs()
	_handle_special_actions()

	# self_destruct 可能在上一行被觸發（dead 變 true）
	if dead:
		return

	_apply_movement(delta)
	_record_frame_if_needed()

	# 把這 tick 的跳躍狀態存起來，下一 tick 用來推導 just_pressed/just_released
	input_jump_prev = input_jump


# === 預設：讀鍵盤 ===
# Clone 會覆寫成從 recording.input_frames[current_frame] 讀
func _read_inputs() -> void:
	input_left = Input.is_action_pressed("move_left")
	input_right = Input.is_action_pressed("move_right")
	input_jump = Input.is_action_pressed("jump")


# === 預設：處理玩家特定按鍵 R / X ===
# Clone 會覆寫成 pass（分身不應該觸發錄製或自爆）
func _handle_special_actions() -> void:
	if Input.is_action_just_pressed("self_destruct"):
		self_destruct()
		return
	if Input.is_action_just_pressed("record"):
		RecordingManager.start_recording(position)


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
		coyote_timer = max(coyote_timer - delta, 0.0)

	# --- 4. Jump buffer（從 input_jump 推導 just_pressed）---
	# just_pressed = 這 tick 按住 && 上 tick 沒按住
	var jump_just_pressed := input_jump and not input_jump_prev
	if jump_just_pressed:
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	# --- 5. 真正執行跳躍 ---
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# --- 6. 變高跳：跳到一半放開，把上升速度截斷 ---
	# just_released = 這 tick 沒按住 && 上 tick 按住
	var jump_just_released := input_jump_prev and not input_jump
	if jump_just_released and velocity.y < JUMP_CUT_VELOCITY:
		velocity.y = JUMP_CUT_VELOCITY

	# --- 7. 套用移動 + 處理碰撞 ---
	move_and_slide()


# === 預設：把這 tick 的輸入存進 RecordingManager ===
# Clone 會覆寫成 pass（分身的輸入是回放，不應該再被錄）
func _record_frame_if_needed() -> void:
	if RecordingManager.is_recording():
		RecordingManager.add_frame(input_left, input_right, input_jump)


func self_destruct() -> void:
	# 1. 結束當前錄製（如果有）→ 自動進入存檔清單
	# 2. 播放閃紅 + 縮成小點的小動畫
	# 3. 動畫結束 → 重生回起點
	if dead:
		return
	if RecordingManager.is_recording():
		RecordingManager.stop_recording()
	dead = true
	velocity = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color(1, 0.3, 0.3, 1), 0.05)
	tween.parallel().tween_property(visual, "scale", Vector2(0.1, 0.1), 0.25)
	tween.tween_callback(respawn)


func respawn() -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	visual.scale = Vector2.ONE
	visual.modulate = Color(0.95, 0.95, 0.95, 1)
	dead = false
