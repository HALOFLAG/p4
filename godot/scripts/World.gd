extends Node2D

# World 主場景根節點（M10）
# Room 2: 單按鈕→門
# Room 3: clone 按鈕→門
# Room 4: 雙按鈕 AND-gate → 門
# Room 6: PressCounter（50 次按鈕、跨房計算、碰旗幟重置）→ 門 → Exit
#         Counter 與 Door 連接由 PressCounter inspector 處理，World.gd 只接 Exit

const ENDING_SCENE := preload("res://scenes/EndingScreen.tscn")

# 錄製期間 BGM ducking：壓低 BGM 強化儀式感、不動 Music bus（保留使用者音量設定）
const BGM_NORMAL_DB := 0.0
const BGM_DUCK_DB := -10.0
const BGM_DUCK_TIME := 0.05      # 進場：近瞬切，按 R 立刻降，不蓋過 record_start SFX
const BGM_RECOVER_TIME := 0.4    # 出場：較緩，BGM 跟著結束儀式柔和回升

@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
var _bgm_duck_tween: Tween = null
@onready var room2_button: PressButton = $Room2/Button
@onready var room2_door: Door = $Room2/Door2
@onready var room3_button: PressButton = $Room3/Button
@onready var room3_door: Door = $Room3/Door
@onready var room4_button_left: PressButton = $Room4/ButtonLeft
@onready var room4_button_right: PressButton = $Room4/ButtonRight
@onready var room4_door: Door = $Room4/Door
@onready var room6_exit: Exit = $Room6/Exit

var _r4_left_pressed := false
var _r4_right_pressed := false


func _ready() -> void:
	# 強制 BGM loop（mp3 預設不 loop）
	if bgm_player.stream != null and "loop" in bgm_player.stream:
		bgm_player.stream.loop = true
	bgm_player.volume_db = BGM_NORMAL_DB

	# 錄製啟動 / 結束時 duck BGM
	PlayerController.recording_started.connect(_on_recording_started)
	PlayerController.recording_ended.connect(_on_recording_ended)

	room2_button.pressed_changed.connect(room2_door.set_target)
	room3_button.pressed_changed.connect(room3_door.set_target)
	room4_button_left.pressed_changed.connect(_on_r4_left_changed)
	room4_button_right.pressed_changed.connect(_on_r4_right_changed)
	room6_exit.reached.connect(_on_exit_reached)


# Room 4 AND-gate：兩個按鈕都按住才開門
func _on_r4_left_changed(p: bool) -> void:
	_r4_left_pressed = p
	_update_r4_door()


func _on_r4_right_changed(p: bool) -> void:
	_r4_right_pressed = p
	_update_r4_door()


func _update_r4_door() -> void:
	room4_door.set_target(_r4_left_pressed and _r4_right_pressed)


func _on_recording_started() -> void:
	_tween_bgm_db(BGM_DUCK_DB, BGM_DUCK_TIME)


func _on_recording_ended() -> void:
	_tween_bgm_db(BGM_NORMAL_DB, BGM_RECOVER_TIME)


# Tween bgm_player.volume_db 不動 Music bus，使用者音量設定保留
func _tween_bgm_db(target_db: float, fade_time: float) -> void:
	if _bgm_duck_tween != null and _bgm_duck_tween.is_valid():
		_bgm_duck_tween.kill()
	_bgm_duck_tween = create_tween()
	_bgm_duck_tween.tween_property(bgm_player, "volume_db", target_db, fade_time)


func _on_exit_reached() -> void:
	print("[WORLD] 通關 → 開啟結局畫面")
	var ending := ENDING_SCENE.instantiate()
	add_child(ending)
