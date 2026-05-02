extends CanvasLayer

# 結局畫面（Exit 觸發）：白框黑底、統計數值與結語用打字機效果出現
# 按 R = 完整重置（GameStats + RecordingManager + 場景重載）
# 按 ESC = 退出遊戲

@onready var v_btn: Label = $Frame/Margin/VBox/StatsGrid/V_Btn
@onready var v_summon: Label = $Frame/Margin/VBox/StatsGrid/V_Summon
@onready var v_recorded: Label = $Frame/Margin/VBox/StatsGrid/V_Recorded
@onready var v_carcass: Label = $Frame/Margin/VBox/StatsGrid/V_Carcass
@onready var v_death: Label = $Frame/Margin/VBox/StatsGrid/V_Death
@onready var v_time: Label = $Frame/Margin/VBox/StatsGrid/V_Time
@onready var variant_label: Label = $Frame/Margin/VBox/VariantLabel
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer


func _ready() -> void:
	# 暫停世界、但本 CanvasLayer 仍能跑 typewriter tween
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	# Variant Label 起始空白、由 typewriter 填入
	variant_label.text = ""

	# 切換 BGM：停掉 World 的 title.mp3、播自己的 world.mp3（與 TitleScreen 同首）
	# 強制 mp3 loop（mp3 預設不 loop）
	if bgm_player.stream != null and "loop" in bgm_player.stream:
		bgm_player.stream.loop = true
	var parent_node := get_parent()
	if parent_node != null:
		var world_bgm := parent_node.get_node_or_null("BGMPlayer") as AudioStreamPlayer
		if world_bgm != null:
			world_bgm.stop()
	# 數值欄起始空（避免 .tscn 預設文字搶先）
	v_btn.text = ""
	v_summon.text = ""
	v_recorded.text = ""
	v_carcass.text = ""
	v_death.text = ""
	v_time.text = ""
	_animate_reveal()


func _animate_reveal() -> void:
	await get_tree().create_timer(0.3, true).timeout
	var pairs := [
		[v_btn, "%d 次" % GameStats.button_press_count],
		[v_summon, "%d 次" % GameStats.clone_summon_count],
		[v_recorded, "%d 次" % GameStats.recording_completed_count],
		[v_carcass, "%d 個" % GameStats.carcass_spawn_count],
		[v_death, "%d 次" % GameStats.death_count],
		[v_time, GameStats.format_time()],
	]
	for pair in pairs:
		_typewriter(pair[0], pair[1], 30.0)
		await get_tree().create_timer(0.18, true).timeout

	# 統計都跑完之後停一拍、再上結語
	await get_tree().create_timer(0.6, true).timeout
	_typewriter(variant_label, _build_variant_text(), 22.0)


# 打字機效果：text 設好、visible_characters 從 0 tween 到 length
func _typewriter(label: Label, full_text: String, chars_per_sec: float) -> void:
	label.text = full_text
	label.visible_characters = 0
	var duration: float = float(full_text.length()) / chars_per_sec
	var tween := create_tween()
	tween.tween_property(label, "visible_characters", full_text.length(), duration)


# 詩意風變體對白——依玩家統計組合多句、組成段落
func _build_variant_text() -> String:
	var lines: Array[String] = []
	# 死亡
	if GameStats.death_count == 0:
		lines.append("你穿越所有時空，沒有一個自己留下。")
	elif GameStats.death_count >= 10:
		lines.append("你經歷無數失敗。每一次跌倒的你，鋪成下一個你的路。")
	# 殘骸
	if GameStats.carcass_spawn_count >= 3:
		lines.append("你以 %d 個自己的骨血，為當下鋪了一條路。" % GameStats.carcass_spawn_count)
	# 召喚
	if GameStats.clone_summon_count >= 20:
		lines.append("你頻繁地呼喚過去。過去回應了你。")
	elif GameStats.clone_summon_count <= 5:
		lines.append("你獨自走完了大部分。但分身，並非沒有意義。")
	# 時長
	if GameStats.play_time_seconds < 300:
		lines.append("你穿過時空，宛如一道閃電。")
	elif GameStats.play_time_seconds > 1800:
		lines.append("你慢慢走、每一步都帶著時間的重量。")
	# 後備
	if lines.is_empty():
		lines.append("過去與當下、在你身上交織成圈。")
	return "\n".join(lines)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.keycode == KEY_R:
		_full_restart()


# 完整重置：所有 autoload 狀態 + 回到開始介面
func _full_restart() -> void:
	GameStats.reset()
	RecordingManager.clear_all()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
