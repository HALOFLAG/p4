extends Player
class_name RecordingProxy

# 錄製期間玩家可控的分身
# 共用 Player 的所有走跳邏輯，但：
#   1. 不在 player_real group（Exit 等不會誤判它）
#   2. collision_mask 排除 layer 2（穿透其他凍結分身）— A1 規則
#   3. 處理 R 鍵結束錄製（與本體的 R 起錄共用，PlayerController 依 state 分流）
#   4. 視覺色為淡藍灰、100% 透明度（與一般 Clone 同色但飽和清楚）
# 對應實作用規格書 S3


func _ready() -> void:
	# 不呼叫 super._ready()——避免加入 player_real group
	spawn_position = position
	# 視覺：淡藍灰、活躍狀態（飽和清楚）
	visual.color = Color(0.4, 0.7, 1.0, 1.0)
	# Collision：偵測 World（layer 1）+ 所有殘骸 layer（3-7），不偵測 Clone（layer 2）— A1 規則
	# M8：proxy 走得上所有 slot 的殘骸，但仍穿透其他凍結 Clone
	collision_mask = 1 + PhysicalCarcass.ALL_CARCASS_LAYERS


# 覆寫：錄製中的特殊鍵
#   R / LMB（record action）= 結束錄製、存槽
#   RMB / E（summon_all action）= 取消錄製、丟棄
# summon_all 在錄製中本來就被 CloneSpawner 擋下、是 no-op、重新詮釋為「取消」零衝突
func _handle_special_actions() -> void:
	if Input.is_action_just_pressed("record"):
		PlayerController.end_recording()
	elif Input.is_action_just_pressed("summon_all"):
		PlayerController.cancel_recording_by_user()
