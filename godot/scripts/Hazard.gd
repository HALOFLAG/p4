extends Area2D
class_name Hazard

# 殺死分身 / 本體 / RecordingProxy 的機關
# - mask = 3（layer 1 World/Player + layer 2 Clone）
# - body_entered 依進來的物件分流：
#     Clone → die() + CarcassManager.register_death
#     Player（本體）→ M9 處理：Player.died signal + zone reset
#     RecordingProxy → M9 處理：A3（強制結束錄製儀式）
#     物理殘骸 / 世界靜態 → 忽略

# 子類化以後加新類型：HazardSpike, HazardProjectile, HazardLaser


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# 殘骸不會觸發此函式（殘骸在 layer 3-7、本 Hazard mask=3 不偵測），不需要型別過濾

	# Clone 死亡（M8 完整實作）
	if body is Clone:
		var clone := body as Clone
		var sidx: int = clone.recording.slot_index if clone.recording else -1
		clone.die()
		if sidx >= 0:
			CarcassManager.register_death(sidx, clone.global_position, get_parent())
		return

	# RecordingProxy 死亡（M9 / S15 A3）
	if body is RecordingProxy:
		PlayerController.handle_recording_proxy_death(body.global_position)
		return

	# Player 本體死亡（M9 / S13 重置）
	if body is Player:
		body.die()
		return
