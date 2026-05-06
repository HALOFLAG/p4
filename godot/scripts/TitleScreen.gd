extends Control

# 餘響 / Lingering Echo — 開始介面
# 對應 Claude Design: Lingering Echo Title Screen.html
#
# 視覺：放射漸層背景 + 月白/微藍粒子飄動、標題列水平置中（餘響 — Lingering Echo）、
#       三按鈕垂直置中、設定面板半透明覆蓋。
#
# 動畫：
#   進場序列：0.3s → 標題淡入（1.5s）→ 1.6s → 三按鈕從下淡入（依序 0/0.12/0.24s）
#   標題呼吸：modulate.a 在 0.95-1.0 間 5s 週期循環
#   按鈕 hover：bg/border/字色 0.15s tween + 漣漪粒子
#   按鈕 press：金色字 + 金色邊
# Audio buses（Music、SFX）在 _ready 時動態建立、無需編輯 project.godot 的 audio layout

const WORLD_SCENE := "res://scenes/World.tscn"
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.7

# === 設計色票（對應 HTML）===
const COLOR_BG_DARK := Color(0.051, 0.063, 0.098, 1.0)         # #0D1019
const COLOR_BG_MID := Color(0.102, 0.129, 0.22, 0.6)           # #1A2138 @ 60%（hover bg）
const COLOR_TEXT_PRIMARY := Color(0.957, 0.945, 0.91, 1.0)     # #F4F1E8 月白
const COLOR_TEXT_SECONDARY := Color(0.541, 0.576, 0.659, 1.0)  # #8A93A8 灰藍
const COLOR_TEXT_DIM := Color(0.290, 0.314, 0.376, 1.0)        # disabled
const COLOR_ACCENT := Color(0.929, 0.624, 0.008, 1.0)          # #ED9F02 金黃

# === 進場時序（秒）===
const TITLE_DELAY := 0.3
const TITLE_FADE_DUR := 1.5
const BUTTONS_START := 1.6
const BUTTON_FADE_DUR := 0.6
const BUTTON_STAGGER := 0.12

# === 呼吸動畫 ===
const BREATHE_PERIOD := 5.0
const BREATHE_MIN := 0.95
const BREATHE_MAX := 1.0

@onready var main_panel: Control = $MainPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var title_row: HBoxContainer = $MainPanel/TitleRow
@onready var buttons_box: VBoxContainer = $MainPanel/Buttons
@onready var start_button: Button = $MainPanel/Buttons/StartButton
@onready var settings_button: Button = $MainPanel/Buttons/SettingsButton
@onready var quit_button: Button = $MainPanel/Buttons/QuitButton

@onready var music_slider: HSlider = $SettingsPanel/Frame/Margin/VBox/MusicRow/MusicSlider
@onready var music_value_label: Label = $SettingsPanel/Frame/Margin/VBox/MusicRow/MusicHeader/MusicValue
@onready var sfx_slider: HSlider = $SettingsPanel/Frame/Margin/VBox/SFXRow/SFXSlider
@onready var sfx_value_label: Label = $SettingsPanel/Frame/Margin/VBox/SFXRow/SFXHeader/SFXValue
@onready var back_button: Button = $SettingsPanel/Frame/Margin/VBox/BackButton
@onready var close_button: Button = $SettingsPanel/Frame/Margin/VBox/Header/CloseButton

@onready var bgm_player: AudioStreamPlayer = $BGMPlayer

var _breathe_time := 0.0
var _entrance_done := false
var _menu_buttons: Array[Button] = []


func _ready() -> void:
	# Music / SFX bus 由 AudioManager autoload._ready 已建好、不需重複建
	# bgm_player.bus 由 .tscn 設定為 "Music"
	if bgm_player.stream != null and "loop" in bgm_player.stream:
		bgm_player.stream.loop = true

	_menu_buttons = [start_button, settings_button, quit_button]
	for btn in _menu_buttons:
		_apply_menu_button_style(btn)
		_wire_hover_animations(btn)

	_apply_back_button_style(back_button)
	_apply_close_button_style(close_button)

	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)
	close_button.pressed.connect(_on_back_pressed)

	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.value = DEFAULT_MUSIC_VOLUME
	sfx_slider.value = DEFAULT_SFX_VOLUME
	# .tscn 的 slider 預設已是 0.7、上面 set 同值 → value_changed 不會觸發 → bus 停在 0 dB
	# 強制呼叫一次套用、確保 bus 真的被設到預設
	AudioManager.set_bus_volume_linear("Music", DEFAULT_MUSIC_VOLUME)
	AudioManager.set_bus_volume_linear("SFX", DEFAULT_SFX_VOLUME)

	main_panel.visible = true
	settings_panel.visible = false

	_play_entrance()


func _process(delta: float) -> void:
	# 標題呼吸：進場 fade-in 完成後接手控制 modulate.a，週期 5s sin 振盪 0.95-1.0
	if not _entrance_done:
		return
	_breathe_time += delta
	var phase := fmod(_breathe_time, BREATHE_PERIOD) / BREATHE_PERIOD
	var k := 0.5 + 0.5 * sin(phase * TAU)
	title_row.modulate.a = lerp(BREATHE_MIN, BREATHE_MAX, k)


# === 進場 ===

func _play_entrance() -> void:
	# 標題：1.5s ease 淡入。完成後 _entrance_done=true 接管 modulate.a 給呼吸動畫
	title_row.modulate.a = 0.0
	var tw_title := create_tween()
	tw_title.set_trans(Tween.TRANS_SINE)
	tw_title.set_ease(Tween.EASE_IN_OUT)
	tw_title.tween_interval(TITLE_DELAY)
	tw_title.tween_property(title_row, "modulate:a", 1.0, TITLE_FADE_DUR)
	tw_title.tween_callback(func(): _entrance_done = true)

	# 按鈕：依序淡入（VBoxContainer 自動排版，position 不可靠，只 tween alpha）
	for i in _menu_buttons.size():
		var btn: Button = _menu_buttons[i]
		btn.modulate.a = 0.0
		var delay := BUTTONS_START + BUTTON_STAGGER * i
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.tween_interval(delay)
		tw.tween_property(btn, "modulate:a", 1.0, BUTTON_FADE_DUR)


# === 按鈕樣式 ===

func _apply_menu_button_style(btn: Button) -> void:
	# Normal：完全透明、灰藍字
	btn.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)

	btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	btn.add_theme_stylebox_override("hover", _make_btn_style(COLOR_BG_MID, COLOR_ACCENT))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(COLOR_BG_DARK, COLOR_ACCENT))
	btn.add_theme_stylebox_override("focus", _make_btn_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))


func _apply_back_button_style(btn: Button) -> void:
	# 設定面板的「返回」：灰藍邊框 → hover 時變金色邊 + 月白字
	btn.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0, 0, 0, 0), COLOR_TEXT_SECONDARY))
	btn.add_theme_stylebox_override("hover", _make_btn_style(Color(0, 0, 0, 0), COLOR_ACCENT))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(Color(0, 0, 0, 0), COLOR_ACCENT))
	btn.add_theme_stylebox_override("focus", _make_btn_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))


func _apply_close_button_style(btn: Button) -> void:
	# 設定面板右上角的「✕」：灰藍 → hover 月白
	btn.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)


func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


# === 按鈕 hover 漣漪 ===

func _wire_hover_animations(btn: Button) -> void:
	btn.mouse_entered.connect(_on_btn_hover_enter.bind(btn))


func _on_btn_hover_enter(btn: Button) -> void:
	_spawn_ripple(btn)


func _spawn_ripple(btn: Button) -> void:
	# 漣漪：滑鼠位置生成一個小金色圓、scale 20 倍、0.5s 內淡出
	# 用 Panel + StyleBoxFlat（圓角等於寬度的一半 → 圓形）
	var local_mouse := btn.get_local_mouse_position()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_ACCENT
	sb.bg_color.a = 0.4
	sb.corner_radius_top_left = 32
	sb.corner_radius_top_right = 32
	sb.corner_radius_bottom_left = 32
	sb.corner_radius_bottom_right = 32

	var ripple := Panel.new()
	ripple.add_theme_stylebox_override("panel", sb)
	ripple.size = Vector2(6, 6)
	ripple.pivot_offset = Vector2(3, 3)
	ripple.position = local_mouse - Vector2(3, 3)
	ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ripple)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ripple, "scale", Vector2(20, 20), 0.5)
	tw.tween_property(ripple, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(ripple.queue_free)


# === 主選單 ===

func _on_start_pressed() -> void:
	AudioManager.play_sfx("ui_click")
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
	AudioManager.set_bus_volume_linear("Music", value)
	music_value_label.text = "%d%%" % int(value * 100)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_bus_volume_linear("SFX", value)
	sfx_value_label.text = "%d%%" % int(value * 100)
