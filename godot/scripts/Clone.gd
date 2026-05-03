extends "res://scripts/Player.gd"
class_name Clone

# Clone 是 Player 的子類別：
#   * 共用：所有物理（走、跳、重力、coyote、jump buffer、變高跳、碰撞）
#   * 不同：
#       1. 輸入來源從鍵盤改為 Recording 資料（覆寫 _read_inputs）
#       2. 不處理 R/X 按鍵（覆寫 _handle_special_actions 為 pass）
#       3. 不錄製自己的輸入（覆寫 _record_frame_if_needed 為 pass）
#       4. 播完所有 frame 後淡出消失

# M7：凍結時的視覺常數
const FROZEN_MODULATE := Color(0.4, 0.5, 0.7, 0.5)  # 暗藍灰 + 半透明，讀感「冰凍剪影」
const NORMAL_MODULATE := Color(1, 1, 1, 1)
const FREEZE_FADE_TIME := 0.3

# 分身跳躍音效音量（dB）：比玩家本體 SFX_DEFAULT_DB["jump"] 再低 6 dB ≈ -50% 振幅
# 多個分身可能同時跳、避免疊聲過吵
const JUMP_SFX_DB := -18.0

var recording: Recording = null
var current_frame := 0
var finished := false
var _freeze_tween: Tween = null


func _ready() -> void:
	# 不呼叫 super._ready()——Clone 不需要重生機制
	# 但仍要初始化 spawn_position 以免 inherit 的變數遺留 null
	spawn_position = position
	# 視覺差異化：藍色半透明，與玩家（白色）區分
	visual.color = Color(0.4, 0.7, 1.0, 0.7)
	# M7：加入 "clone" group，讓 PlayerController 能 batch 凍結/解凍
	add_to_group("clone")
	# M8：依自己的 slot 計算 mask——看 World + 其他 slot 殘骸，排除自己 slot 的殘骸 layer
	# 同 slot 連續死亡的後續分身會穿過自己的舊殘骸
	if recording != null:
		var own_layer := PhysicalCarcass.slot_to_layer(recording.slot_index)
		collision_mask = 1 + PhysicalCarcass.ALL_CARCASS_LAYERS - own_layer


# === 覆寫：從 recording 讀輸入而非鍵盤 ===
func _read_inputs() -> void:
	if recording == null:
		input_left = false
		input_right = false
		input_jump = false
		return
	if current_frame < recording.input_frames.size():
		var f: Dictionary = recording.input_frames[current_frame]
		input_left = f["left"]
		input_right = f["right"]
		input_jump = f["jump"]
		current_frame += 1
	else:
		# Recording 已播完，所有輸入歸零（讓物理自然衰減直到 finish 觸發）
		input_left = false
		input_right = false
		input_jump = false


# === 覆寫：分身不處理 R/X ===
func _handle_special_actions() -> void:
	pass


# === 覆寫：分身不錄製自己的輸入 ===
func _record_frame_if_needed() -> void:
	pass


# === 覆寫：分身跳躍音效低 6 dB + 房間距離衰減 ===
# 基礎音量比玩家本體再低 6 dB（避免一堆分身同時跳很吵）
# 再透過 play_sfx_at 依「分身所在房間」與「玩家當前房間」距離衰減
# 隔房分身的跳躍會被壓得更小聲、超過 3 房直接不播
func _play_jump_sfx() -> void:
	AudioManager.play_sfx_at("jump", global_position, JUMP_SFX_DB)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Recording 播完後淡出消失
	if not finished and recording != null and current_frame >= recording.input_frames.size():
		finish()


func finish() -> void:
	finished = true
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


# === M8：被 Hazard 殺死 ===
# Hazard 偵測到 Clone 進入時呼叫——立刻關閉 collision 與 tick、queue_free
# 殘骸由 Hazard 那一側呼叫 CarcassManager.register_death 生成（避免 Clone 反向耦合）
func die() -> void:
	if finished:
		return
	finished = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if _freeze_tween != null and _freeze_tween.is_valid():
		_freeze_tween.kill()
	# 分身死亡套距離衰減（別房死亡的分身不應該與本體死亡同等響度）
	AudioManager.play_sfx_at("die", global_position)
	queue_free()


# === M7：覆寫 Player 的 freeze/unfreeze ===
# 與 Player 不同：不動 collision_layer（保持被按鈕偵測）、不動 collision_mask
# Player._physics_process 開頭的 `if is_frozen: return` 會自動停止 tick
# 視覺淡化為灰色剪影、0.3s 內淡入淡出
func freeze() -> void:
	if is_frozen or finished:
		return
	is_frozen = true
	velocity = Vector2.ZERO
	if _freeze_tween != null and _freeze_tween.is_valid():
		_freeze_tween.kill()
	_freeze_tween = create_tween()
	_freeze_tween.tween_property(visual, "modulate", FROZEN_MODULATE, FREEZE_FADE_TIME)


func unfreeze() -> void:
	if not is_frozen or finished:
		return
	is_frozen = false
	if _freeze_tween != null and _freeze_tween.is_valid():
		_freeze_tween.kill()
	_freeze_tween = create_tween()
	_freeze_tween.tween_property(visual, "modulate", NORMAL_MODULATE, FREEZE_FADE_TIME)
