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
	"button_press":  0.0,
	"jump":         -12.0,   # 跳躍很頻繁、稍微壓低避免吵
	"die":          -15.0,
	"door_open":     3.0,
	"record_start": -15.0,
	"record_end":   -9.0,
	"summon":       -9.0,
	"ui_click":     -9.0,
}

# Pool 大小（同時可播放幾個 SFX、超過會輪替最舊的）
const POOL_SIZE := 8

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
