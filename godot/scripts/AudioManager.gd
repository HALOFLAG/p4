extends Node

# 全域音效管理（autoload）
# - SFX 預先 preload、pool 播放（避免同名 SFX 重複截斷）
# - Music / SFX audio buses 動態建立、無需編輯 default_bus_layout.tres
# - BGM 由各場景的 AudioStreamPlayer 自己負責、AudioManager 不管 BGM

const SFX_FILES := {
	"button_press": preload("res://audio/sfx/button_press.ogg"),
	"jump":         preload("res://audio/sfx/jump.ogg"),
	"die":          preload("res://audio/sfx/die.ogg"),
	"door_open":    preload("res://audio/sfx/door_open.ogg"),
	"record_start": preload("res://audio/sfx/record_start.ogg"),
	"record_end":   preload("res://audio/sfx/record_end.ogg"),
	"summon":       preload("res://audio/sfx/summon.ogg"),
	"ui_click":     preload("res://audio/sfx/ui_click.ogg"),
}

# 各 SFX 的預設音量微調（單位：dB；0 = 原始、負值變小聲、正值變大聲）
# 想統一調大/小聲：改此處數字、不需改各 hook 點
# 想單次特殊處理：呼叫時用 play_sfx("xxx", -5.0) 第二參數覆寫
const SFX_DEFAULT_DB := {
	"button_press":  -3.0,
	"jump":         -12.0,   # 跳躍很頻繁、稍微壓低避免吵
	"die":          -15.0,
	"door_open":     -9.0,
	"record_start": -15.0,
	"record_end":   -9.0,
	"summon":       -9.0,
	"ui_click":     -9.0,
}

# Pool 大小（同時可播放幾個 SFX、超過會輪替最舊的）
const POOL_SIZE := 8

# 房間距離衰減：以「玩家當前房間」為基準、source 在幾個房間遠就降多少音量
# 房間距 0/1/2/3 → 振幅 100/70/40/10%（每隔一房 -30%）；>=4 房不播
# 房間排列以 1280px（一個房間寬）為單位、距離換算成房間數
# 適用：按鈕、門、分身跳/死等「源頭可能不在當前畫面」的音效（透過 play_sfx_at）
const ROOM_WIDTH := 1280.0
const ROOM_DISTANCE_AMPLITUDE := [1.0, 0.7, 0.4, 0.1]

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx := 0


func _ready() -> void:
	# 即使遊戲暫停也要能跑（暫停期間的儀式音效仍要發出）
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 確保 Music / SFX bus 存在
	_ensure_bus("Music")
	_ensure_bus("SFX")

	# 建 SFX pool
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_pool.append(p)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


# 播放命名 SFX；找不到名字時靜默（不爆 error）
# volume_db_override：傳數字會**覆蓋** SFX_DEFAULT_DB 的預設、傳 INF 表示用預設
# 一般情況直接呼叫 play_sfx("jump") 即可、它會自動套 SFX_DEFAULT_DB["jump"]
func play_sfx(sfx_name: String, volume_db_override: float = INF) -> void:
	if not SFX_FILES.has(sfx_name):
		push_warning("[Audio] SFX 名稱不存在: %s" % sfx_name)
		return
	var vol: float = volume_db_override
	if vol == INF:
		vol = SFX_DEFAULT_DB.get(sfx_name, 0.0)
	var p := _sfx_pool[_next_sfx]
	_next_sfx = (_next_sfx + 1) % POOL_SIZE
	p.stream = SFX_FILES[sfx_name]
	p.volume_db = vol
	p.play()


# 帶世界座標的 SFX 播放：自動依「source 所在房間」與「玩家當前房間」的距離衰減
# 同房 = 全音量；隔 1/2/3 房 = 70/40/10%；>=4 房不播
# 適用：按鈕、門、分身的跳/死等可能在別房觸發的音效
# 不適用：玩家本體（永遠在當前房）、UI 與錄製音效（介面層、與位置無關）
func play_sfx_at(sfx_name: String, world_pos: Vector2, volume_db_override: float = INF) -> void:
	var amp := _distance_amplitude(world_pos)
	if amp <= 0.0:
		return  # 超過 3 房：不播、也不佔 pool slot
	if not SFX_FILES.has(sfx_name):
		push_warning("[Audio] SFX 名稱不存在: %s" % sfx_name)
		return
	var base_vol: float = volume_db_override
	if base_vol == INF:
		base_vol = SFX_DEFAULT_DB.get(sfx_name, 0.0)
	var p := _sfx_pool[_next_sfx]
	_next_sfx = (_next_sfx + 1) % POOL_SIZE
	p.stream = SFX_FILES[sfx_name]
	p.volume_db = base_vol + linear_to_db(amp)
	p.play()


# 計算 world_pos 與當前房間的「房間距」、查表回傳音量振幅
# 找不到當前房間（剛開場、玩家還沒進任何房）→ 1.0 全音量（安全預設）
func _distance_amplitude(world_pos: Vector2) -> float:
	var cur: Node = RoomManager.current_room
	if cur == null:
		return 1.0
	var src: Node = _find_room_at(world_pos)
	if src == null or src == cur:
		return 1.0
	var dist: float = src.camera_target.global_position.distance_to(cur.camera_target.global_position)
	var rooms_away: int = int(round(dist / ROOM_WIDTH))
	if rooms_away <= 0:
		rooms_away = 1  # 不同房間至少算 1（防 camera_target 排版過近時誤判同房）
	if rooms_away >= ROOM_DISTANCE_AMPLITUDE.size():
		return 0.0
	return ROOM_DISTANCE_AMPLITUDE[rooms_away]


# 用 "room" group + Room.contains() 找包含 world_pos 的房間
func _find_room_at(world_pos: Vector2) -> Node:
	for room in get_tree().get_nodes_in_group("room"):
		if room.has_method("contains") and room.contains(world_pos):
			return room
	return null
