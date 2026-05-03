extends Node

# 通用的分身召喚器：監聽 summon_all action（LMB / E）、同時召喚所有填滿槽位的分身
# 加為任何需要召喚分身的場景的子節點。召喚出來的分身會被加到 spawner 的父節點（場景根）。
#
# 演進：
#   M2  鍵 1-9 無上限召喚（個別槽位）
#   M5  鍵 1-5 槽位制（個別召喚對應槽位）
#   C1  統一召喚：單一觸發（LMB / E）同時召出所有填滿槽位的分身
#       理由：玩家偏好「一分身一事完整完成」、不會頻繁切換槽位、
#             且「過去同時迴響」更貼合「餘響」主題

const CLONE_SCENE := preload("res://scenes/Clone.tscn")

# 召喚 CD：避免誤觸與連按刷屏（M2.5 決策、原型階段可調）
# C1 後：CD 共享於整批召喚（按一次 = 一批）；0.3 → 0.5 強化儀式感、防雙擊
const SUMMON_CD := 0.5
var summon_cd_remaining := 0.0


func _process(delta: float) -> void:
	if summon_cd_remaining > 0.0:
		summon_cd_remaining = maxf(summon_cd_remaining - delta, 0.0)


# 用 _unhandled_input 讓 PauseMenu / 其他 UI 可優先消費事件
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("summon_all"):
		summon_all()


# 同時召喚所有填滿槽位的分身
# 設計決策：
# - 0 個分身被召喚時不消耗 CD、不播 SFX（避免空按浪費）
# - clone_summon_count 仍按單個分身累計（保持現有統計含義）
# - 錄製中保護：與既有規則一致
func summon_all() -> void:
	if summon_cd_remaining > 0.0:
		return
	if PlayerController.is_recording():
		return

	var spawned := 0
	for i in range(RecordingManager.SLOT_COUNT):
		var rec: Recording = RecordingManager.get_recording(i)
		if rec == null:
			continue
		var clone: Clone = CLONE_SCENE.instantiate()
		clone.position = rec.spawn_position
		clone.recording = rec
		# 加到 spawner 的父節點（通常是場景根）、與其他場景物件同層
		get_parent().add_child(clone)
		GameStats.clone_summon_count += 1
		spawned += 1

	if spawned > 0:
		summon_cd_remaining = SUMMON_CD
		AudioManager.play_sfx("summon")
		print("[SPAWN] 召喚 %d 個分身" % spawned)
	else:
		print("[SPAWN] 無可召喚的分身（所有槽位皆空）")
