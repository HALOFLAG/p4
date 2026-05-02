extends Control

# 開始介面：標題 + 開始 / 設定 / 離開 三按鈕 + Music/SFX 音量設定
# 之後加 BGM 檔案：在 BGMPlayer 節點 inspector 設 stream 屬性即可
# Audio buses（Music、SFX）在 _ready 時動態建立、無需編輯 project.godot 的 audio layout

const WORLD_SCENE := "res://scenes/World.tscn"
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.7

@onready var main_panel: Control = $MainPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var start_button: Button = $MainPanel/VBox/StartButton
@onready var settings_button: Button = $MainPanel/VBox/SettingsButton
@onready var quit_button: Button = $MainPanel/VBox/QuitButton

@onready var music_slider: HSlider = $SettingsPanel/Frame/Margin/VBox/MusicRow/MusicSlider
@onready var music_value_label: Label = $SettingsPanel/Frame/Margin/VBox/MusicRow/MusicValue
@onready var sfx_slider: HSlider = $SettingsPanel/Frame/Margin/VBox/SFXRow/SFXSlider
@onready var sfx_value_label: Label = $SettingsPanel/Frame/Margin/VBox/SFXRow/SFXValue
@onready var back_button: Button = $SettingsPanel/Frame/Margin/VBox/BackButton

@onready var bgm_player: AudioStreamPlayer = $BGMPlayer


func _ready() -> void:
	# 確保 Music / SFX 音訊匯流排存在（AudioManager 也會做、這是 fallback）
	_ensure_bus("Music")
	_ensure_bus("SFX")

	# BGM player 路由到 Music bus、強制 loop（mp3 預設不 loop）
	bgm_player.bus = "Music"
	if bgm_player.stream != null and "loop" in bgm_player.stream:
		bgm_player.stream.loop = true

	# 連接按鈕（含 UI click 音）
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# 音量 slider
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.value = DEFAULT_MUSIC_VOLUME
	sfx_slider.value = DEFAULT_SFX_VOLUME

	# 初始顯示主選單、隱藏設定
	main_panel.visible = true
	settings_panel.visible = false


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


# === 主選單 ===

func _on_start_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	# 進世界前重置所有狀態
	GameStats.reset()
	RecordingManager.clear_all()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_settings_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	main_panel.visible = false
	settings_panel.visible = true


func _on_quit_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().quit()


# === 設定面板 ===

func _on_back_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	settings_panel.visible = false
	main_panel.visible = true


func _on_music_changed(value: float) -> void:
	_apply_volume("Music", value)
	music_value_label.text = "%d%%" % int(value * 100)


func _on_sfx_changed(value: float) -> void:
	_apply_volume("SFX", value)
	sfx_value_label.text = "%d%%" % int(value * 100)


func _apply_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# 0 → 靜音、否則用 linear→db 映射
	if linear < 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
