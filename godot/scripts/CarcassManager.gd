extends Node

# 槽位制物理殘骸管理器（autoload）
# 對應實作用規格書 S10
#
# 規則：每個錄製槽位最多 1 個物理殘骸（地圖上同時存活的物理殘骸 ≤ 5）
#
# 三個進入點：
#   register_death(slot_index, position, parent)
#     由 Hazard 在 Clone 死亡時呼叫
#     若該槽位已有殘骸 → 舊轉痕跡、新生成
#   clear_slot_carcass(slot_index)
#     RecordingManager.slot_will_overwrite / slot_cleared 觸發
#     舊殘骸轉痕跡
#   reset_zone(zone)
#     M9 補：本體死亡時呼叫，zone 內殘骸轉痕跡

const PHYSICAL_CARCASS_SCENE := preload("res://scenes/PhysicalCarcass.tscn")

# slot_index → PhysicalCarcass 實例（最多 5 個 entry，對應 5 槽位）
var _slot_carcasses: Dictionary = {}


func _ready() -> void:
	# 與 RecordingManager 協作：槽位被覆蓋/刪除時連帶處理對應殘骸
	# slot_will_overwrite：FIFO 覆蓋——舊殘骸轉痕跡
	# slot_cleared：Q 刪除——舊殘骸轉痕跡
	# slot_assigned：重錄完成——也視為「該槽位重新開始」，舊殘骸轉痕跡
	#   （重錄後玩家對槽位的認知是新的，舊死亡留下的殘骸應該降級為痕跡）
	RecordingManager.slot_will_overwrite.connect(_on_slot_will_overwrite)
	RecordingManager.slot_cleared.connect(_on_slot_cleared)
	RecordingManager.slot_assigned.connect(_on_slot_assigned)


# Clone 撞 hazard 死亡 → Hazard 呼叫
func register_death(slot_index: int, world_position: Vector2, parent: Node) -> void:
	if slot_index < 0:
		return
	# 同槽位已有殘骸 → 舊轉痕跡（保留 60s 倒數的延續）
	_convert_slot_to_trace(slot_index)

	var carcass: PhysicalCarcass = PHYSICAL_CARCASS_SCENE.instantiate()
	carcass.global_position = world_position
	carcass.setup(slot_index)
	parent.add_child(carcass)
	_slot_carcasses[slot_index] = carcass
	GameStats.carcass_spawn_count += 1
	print("[CARCASS] 槽位 %d 殘骸生成 @ %s" % [slot_index + 1, world_position])


# 主動刪除某槽位殘骸（轉痕跡）
func clear_slot_carcass(slot_index: int) -> void:
	_convert_slot_to_trace(slot_index)


# M9：本體死亡時呼叫，把指定 zone 內的物理殘骸全部轉痕跡
# 跨 zone 的殘骸不變
func reset_zone(zone) -> void:
	if zone == null:
		return
	var to_clear: Array = []
	for slot_idx in _slot_carcasses.keys():
		var c = _slot_carcasses[slot_idx]
		if not is_instance_valid(c):
			continue
		if zone.contains(c.global_position):
			to_clear.append(slot_idx)
	for slot_idx in to_clear:
		_convert_slot_to_trace(slot_idx)
	print("[CARCASS] reset_zone：%d 個殘骸轉痕跡" % to_clear.size())


# 內部：把指定槽位的殘骸換成痕跡（如果有的話）
func _convert_slot_to_trace(slot_index: int) -> void:
	var c = _slot_carcasses.get(slot_index)
	if c != null and is_instance_valid(c):
		c.convert_to_trace()
	_slot_carcasses.erase(slot_index)


# === RecordingManager 信號 handlers ===

func _on_slot_will_overwrite(slot_index: int, _old_recording) -> void:
	_convert_slot_to_trace(slot_index)


func _on_slot_cleared(slot_index: int) -> void:
	_convert_slot_to_trace(slot_index)


func _on_slot_assigned(slot_index: int, _recording) -> void:
	# 重錄完成：把該槽位的舊殘骸降級
	# 新錄製（slot 第一次填）：_slot_carcasses 沒這 entry，erase 是 no-op
	_convert_slot_to_trace(slot_index)
