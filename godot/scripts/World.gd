extends Node2D

# World 主場景根節點（M10）
# Room 2: 拉桿 → 門 + 觸發式平台（M13 測試：連線在 demo_room2.tscn 內）
# Room 3: clone 按鈕→門
# Room 4: 雙按鈕 AND-gate → 門（M13：邏輯由 demo_room4.tscn 內的 LogicGate Node 處理）
# Room 6: PressCounter（50 次按鈕、跨房計算、碰旗幟重置）→ 門 → Exit
#         Counter 與 Door 連接由 PressCounter inspector 處理，World.gd 只接 Exit

const ENDING_SCENE := preload("res://scenes/EndingScreen.tscn")

# 錄製期間 BGM ducking：壓低 BGM 強化儀式感、不動 Music bus（保留使用者音量設定）
const BGM_NORMAL_DB := 0.0
const BGM_DUCK_DB := -10.0
const BGM_DUCK_TIME := 0.05      # 進場：近瞬切，按 R 立刻降，不蓋過 record_start SFX
const BGM_RECOVER_TIME := 0.4    # 出場：較緩，BGM 跟著結束儀式柔和回升

# 地圖介面 BGM 衰減：開啟地圖時 BGM 持續播放但壓到 50% 音量（≈ -6 dB）
const BGM_MAP_DUCK_DB := -6.02   # 20 * log10(0.5)，linear 50% 振幅
const BGM_MAP_FADE_TIME := 0.2

@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
var _bgm_duck_tween: Tween = null
@onready var room3_button: PressButton = $demo_room3/Button
@onready var room3_door: Door = $demo_room3/Door
@onready var room6_exit: Exit = $demo_room6/Exit


func _ready() -> void:
	# 強制 BGM loop（mp3 預設不 loop）
	if bgm_player.stream != null and "loop" in bgm_player.stream:
		bgm_player.stream.loop = true
	bgm_player.volume_db = BGM_NORMAL_DB
	# BGM 跨 pause 持續播放（地圖開啟 / PauseMenu 開啟時都不會中斷音樂）
	bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS

	# 錄製啟動 / 結束時 duck BGM
	PlayerController.recording_started.connect(_on_recording_started)
	PlayerController.recording_ended.connect(_on_recording_ended)
	# 地圖開啟 / 關閉時 duck BGM 至 50%
	PlayerController.map_opened.connect(_on_map_opened)
	PlayerController.map_closed.connect(_on_map_closed)

	# Room 2 連線：M13 測試起改由 demo_room2.tscn 內的 [connection] 處理
	room3_button.pressed_changed.connect(room3_door.set_target)
	# Room 4 AND-gate 連線：M13 起改由 demo_room4.tscn 內的 LogicGate Node 處理
	room6_exit.reached.connect(_on_exit_reached)


func _on_recording_started() -> void:
	_tween_bgm_db(BGM_DUCK_DB, BGM_DUCK_TIME)


func _on_recording_ended() -> void:
	_tween_bgm_db(BGM_NORMAL_DB, BGM_RECOVER_TIME)


func _on_map_opened() -> void:
	_tween_bgm_db(BGM_MAP_DUCK_DB, BGM_MAP_FADE_TIME)


func _on_map_closed() -> void:
	_tween_bgm_db(BGM_NORMAL_DB, BGM_MAP_FADE_TIME)


# Tween bgm_player.volume_db 不動 Music bus，使用者音量設定保留
# Tween 綁在 bgm_player 上（process_mode = ALWAYS）、地圖開啟時 World 雖然 pause、tween 仍會跑
func _tween_bgm_db(target_db: float, fade_time: float) -> void:
	if _bgm_duck_tween != null and _bgm_duck_tween.is_valid():
		_bgm_duck_tween.kill()
	_bgm_duck_tween = bgm_player.create_tween()
	_bgm_duck_tween.tween_property(bgm_player, "volume_db", target_db, fade_time)


func _on_exit_reached() -> void:
	print("[WORLD] 通關 → 開啟結局畫面")
	var ending := ENDING_SCENE.instantiate()
	add_child(ending)
