extends CanvasLayer

# 遊戲中暫停選單：HUD 右上角的暫停按鈕觸發
# 暫停世界、提供 Music/SFX 音量調整 + 繼續遊戲 + 回主選單

@onready var music_slider: HSlider = $Frame/Margin/VBox/MusicRow/MusicSlider
@onready var music_value: Label = $Frame/Margin/VBox/MusicRow/MusicValue
@onready var sfx_slider: HSlider = $Frame/Margin/VBox/SFXRow/SFXSlider
@onready var sfx_value: Label = $Frame/Margin/VBox/SFXRow/SFXValue
@onready var resume_btn: Button = $Frame/Margin/VBox/ResumeButton
@onready var main_menu_btn: Button = $Frame/Margin/VBox/MainMenuButton


func _ready() -> void:
	# 暫停期間仍能跑（slider tween / button 點擊）
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Slider 從現有 bus volume 讀進來（玩家在 TitleScreen 調過的會延續）
	music_slider.value = _read_bus_linear("Music")
	sfx_slider.value = _read_bus_linear("SFX")
	music_value.text = "%d%%" % int(music_slider.value * 100)
	sfx_value.text = "%d%%" % int(sfx_slider.value * 100)

	# 連接信號
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	resume_btn.pressed.connect(_on_resume)
	main_menu_btn.pressed.connect(_on_main_menu)

	# 暫停世界
	get_tree().paused = true


func _read_bus_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.7
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clamp(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _on_music_changed(v: float) -> void:
	_apply_volume("Music", v)
	music_value.text = "%d%%" % int(v * 100)


func _on_sfx_changed(v: float) -> void:
	_apply_volume("SFX", v)
	sfx_value.text = "%d%%" % int(v * 100)


func _apply_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if linear < 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _on_resume() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().paused = false
	queue_free()


func _on_main_menu() -> void:
	AudioManager.play_sfx("ui_click")
	GameStats.reset()
	RecordingManager.clear_all()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
