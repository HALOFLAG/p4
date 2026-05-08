「狀態 → 動畫 mapping」詳細說明
一、這個東西本質是什麼
先想清楚有哪些狀態值得用動畫表達、再給每個狀態取一個動畫名字、最後才填動畫內容。

像蓋房子：先畫圖（mapping）→ 鋪電線（AnimationPlayer 框架）→ 裝燈（M14b 才填）。

M14a.1 是畫圖階段——只決定「有哪幾盞燈、各自叫什麼名字」。

二、為什麼要先做這個、不直接做動畫
3 個理由：

1. 避免「隨手寫、寫到一半發現重複」
不先列、會出現：

Door 內部叫 open
Lever 翻轉動畫叫 lever_on（不一致命名）
TriggeredPlatform 的移動叫 move_platform（更不一致）
事後重命名痛苦、自動化測試也對不上。

2. 提供 M15 設計關卡時的可預期接口
M15 設計師（其實也是你）擺機關時、知道「Lever 一定有 flip_on/flip_off」、就可以在事件驅動劇情用：


# M15 某關卡的房間 .gd
func _on_lever_state_changed(is_on):
    if is_on:
        $Lever.anim.play("flip_on")  # 事先約定的名字
        await $Lever.anim.animation_finished
        $Door.anim.play("open")
不必等 M14b 真的填內容。

3. 集中 Recording 一致性風險
所有狀態 mapping 完才開始套 AnimationPlayer、第一個套用就驗證 Recording 一致性。

若不過、馬上知道「全部都要回退」、不會做了一半才發現。

三、要 mapping 的對象分 3 類
類別 A：角色（Player / Clone / RecordingProxy）
玩家自己、最複雜、狀態最多。

類別 B：機關（9 個元件 + 既有 Checkpoint/Sign/Teleporter/LightPoint）
被觸發後有視覺反應、狀態通常 1-3 個。

類別 C：UI（HUD / PauseMenu / EndingScreen / MapOverlay / TitleScreen）
介面動畫（淡入淡出、按鈕 hover、過場）。

很多既有用 Tween 做、不需移到 AnimationPlayer——可選擇性 mapping。

四、各對象的具體狀態盤點
4.1 Player（最複雜）
狀態	觸發條件	動畫名稱（暫定）	預計內容（M14b 填）
idle	velocity ≈ 0 + on_floor	idle	站立微呼吸
walk	velocity.x ≠ 0 + on_floor	walk	走路循環
jump	跳起、velocity.y < 0	jump	起跳姿勢
fall	空中、velocity.y > 0	fall	下落姿勢
land	剛落地（was_on_floor false → true）	land	落地 squash
die	撞 Hazard / 掉 DeathBand	die	化煙消失
record_start	按 R 啟動錄製	record_start	紅光暈淡入
record_end	按 R 結束錄製	record_end	紅光暈淡出
frozen	錄製中本體凍結	frozen	半透明淡化
Player 可能不必每個狀態都做動畫——MVP 只做 idle/walk/jump/fall/die 也夠。但 mapping 階段先列全部、決定要不要做留到 M14b。

4.2 Clone（與 Player 共用、加自己的）
狀態	動畫	來源
idle / walk / jump / fall	同 Player	繼承（共用）
spawn	從 LightPoint 淡入時	clone_spawn
despawn	播完 recording 後淡出	clone_despawn
frozen（M7 凍結）	變灰色剪影	frozen_freeze / frozen_unfreeze
4.3 機關（9 個元件 + 4 個固定場景元件）
元件	狀態	動畫名
PressButton	idle / pressed / released	press_down, press_up
Door	closed / opening / open / closing	open, close
Exit	idle / triggered	triggered
Lever	off / flip_on / on / flip_off	flip_on, flip_off
Spring	idle / compress	compress
TriggeredPlatform	at_start / moving / at_target	move, return
CrumblingPlatform	solid / warning / collapsing / collapsed / restoring	warning, collapse, restore
Platform	（無動畫、純地形）	—
HazardZone	（無動畫、純致死區）	—
HazardSpike	idle	idle（如要做動態尖刺）
Checkpoint	inactive / activate / active	activate、deactivate（M10 既有 Tween）
Sign	hidden / showing	fade_in, fade_out（M10 既有 Tween）
Teleporter	idle / pulse	pulse 環境光暈循環
LightPoint	bright_pulse / convert_to_trace / fade_out	對應 LightPoint.gd 既有 Tween 邏輯
PhysicalCarcass	idle	（無動畫）
CarcassTrace	new / aging / old	age_60s 顏色漸變（既有邏輯）
4.4 UI（多數可保留 Tween、不必動）
UI	既有用法	M14a 處理
HUD 槽位淡入	Tween	不動（保 Tween）
Sign 文字淡入	Tween	不動
Door 開合	_physics_process 手刻	改 AnimationPlayer（M14a.4 驗證 Recording）
Checkpoint activate	Tween	不動（已穩定）
TitleScreen 標題進場	Shader 背景 + Tween	不動
PauseMenu 顯示	直接 visible	可選用 fade
EndingScreen 打字機效果	自訂程式	不動
規則：既有 Tween 已穩定的不動。新元件 + Door / TriggeredPlatform / CrumblingPlatform 改 AnimationPlayer。

五、決策原則：哪些狀態值得做動畫
不是所有狀態都需要動畫。3 個篩選問題：

篩 1：玩家會不會察覺？
「按鈕被按下的瞬間」→ 玩家會看 → 值得動畫
「PhysicalCarcass 形成」→ 玩家會看 → 值得動畫
「TriggerZone 內部 reset 觸發」→ 玩家看不見 → 不必動畫
篩 2：靜態 vs 動態？
靜態物件（Platform 純地板）→ 永遠不必動畫
動態物件（Door / Lever / Spring）→ 必要動畫
篩 3：餘響的詩意基調是否需要它？
錄製儀式（紅光暈、儀式感）→ 強烈需要、加分
跳起來時的灰塵粒子 → 不一定需要、加了好但可省
結論
MVP 級別（M14a 必做）：機關狀態變化（Door / Lever / Spring 等）、角色基本動作（Idle / Walk / Jump / Fall / Die）

Polish 級別（M14b 補）：跳躍尾跡、儀式光暈、UI 過場、命中回饋

六、Mapping 文件長什麼樣
M14a.1 產出物：1 份「mapping spec」、可放進 新元件製作指引.md 或單獨建文件。

範本：


# 動畫狀態 Mapping Spec

## Player
| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 備註 |
|---|---|---|---|---|
| idle | `idle` | PHYSICS | TBD | 站立微呼吸 |
| walk | `walk` | PHYSICS | TBD | 走路循環 |
| jump | `jump` | PHYSICS | TBD | 起跳 squash |
| ... | ... | ... | ... | ... |

## Door
| 狀態 | 動畫名 | callback_mode | 內容 | 備註 |
|---|---|---|---|---|
| open | `open` | **PHYSICS**（critical）| visual.position.y 0→200 + scale.y 1→0.001 + collision.disabled = true | 取代 _physics_process 手刻、必驗 Recording |
| close | `close` | PHYSICS | 反向 | play_backwards("open") 也 OK |
關鍵欄位：

callback_mode 必須是 PHYSICS 才 Recording-safe（M14a.4 驗證）
內容 欄位 M14a 留 TBD、M14b 才填
七、與 Recording 系統的考量（最關鍵）
動畫的 callback_mode 一定要是 PHYSICS
Godot AnimationPlayer 預設 callback_mode_process = ANIMATION_PROCESS_IDLE——隨 fps 變化、非 deterministic。

要改成 ANIMATION_PROCESS_PHYSICS（與 _physics_process 同步、60Hz 固定）：

Inspector 設 Callback Mode Process = Physics
或腳本 anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS（Godot 4.3+ enum 在 AnimationMixer 父類）
Mapping 階段就要標清楚每個動畫的 callback mode
在 mapping spec 內、明確標：

PHYSICS（Recording-critical，所有玩家/機關互動）
IDLE（純 UI、純視覺、不影響玩法）
M14a.4 第一個動畫驗證的重要性
選 1 個 high-risk 元件（推薦 TriggeredPlatform 因為它 Recording-critical 又有 AnimationPlayer 路徑需求）：

把 _physics_process lerp 改成 AnimationPlayer 的 move/return 動畫
callback_mode 設 PHYSICS
跑「錄製含平台移動 → 重現 3 次比對」
3 次都一致 → AnimationPlayer 在 PHYSICS mode 是 Recording-safe、可全面套用
不一致 → 致命、回退 _physics_process 手刻、所有元件都不換
萬一不一致、退路是什麼？
保留所有元件用 _physics_process 手刻動畫
沒有 AnimationPlayer 的視覺優勢、但 Recording 仍 deterministic
M14b 改用粒子 / shader 等其他方式 polish 視覺
→ 並非「沒 AnimationPlayer 就完蛋」、只是「polish 路徑不同」。

八、典型工作流程（M14a.1 怎麼做）
第 1-2 小時：列所有對象 + 狀態（用 工具與機關清單.md 39 個對象做底）
第 3 小時：給每個狀態取動畫名、確認命名一致（如 Door 用 open 不用 door_open、因為已在 Door 內部）
第 4 小時：標每個動畫的 callback_mode（PHYSICS / IDLE）
第 5-6 小時：寫進 spec 文件、commit
1 天內完成。

九、做 mapping 時你要思考的設計問題
幾個會冒出來的決定點：

Q1：Player 動畫要做幾個？
5 個（idle/walk/jump/fall/die）= MVP
8 個（+ land / record_start / record_end）= 完整
12 個（+ frozen / hurt / 跳兩段）= 過度
建議：先列 8 個、M14b 才決定填哪幾個。

Q2：靜態元件要不要 AnimationPlayer 占位？
例如 Platform（純地板）— 完全不需要。

但若 M14b 想加「地板有微妙呼吸效果」、現在不加 AnimationPlayer、之後要加就要改場景。

建議：靜態元件不加 AnimationPlayer、保留簡潔。需要時再補不晚。

Q3：UI 動畫要不要遷移到 AnimationPlayer？
例如 Sign 淡入既有 Tween。

建議：不遷移——Tween 在 UI / 純視覺場景已穩定、改 AnimationPlayer 是「為改而改」。

Q4：相同動畫多元件共用嗎？
例如 Door 與 TimedDoor（雖然 freeze 不會做）都有 open 動畫。

建議：用繼承——子類沿用父類動畫、不複製。

十、給你思考的問題清單
開始 M14a.1 前、先思考這幾題：

MVP vs 完整：Player 動畫做 5 個還是 8 個？（影響 M14b 美術投入）
既有 Tween 動嗎：Checkpoint activate / Sign fade / LightPoint pulse 已穩定、要不要保留？我傾向保留
AnimationPlayer 失敗的退路：若 Recording 一致性失敗、所有元件回 _physics_process 手刻、可接受嗎？
動畫風格定錨：餘響的「靜謐 / 詩意」基調、動畫該偏寫實（squash & stretch）還是抽象（光暈、粒子）？
這 4 題的答案會影響 mapping spec 的決策——可在實際開始 M14a 時思考。

結論
M14a.1「狀態 → 動畫 mapping」=

盤點所有對象的狀態
給每個狀態取一致的動畫名
標清 callback_mode（PHYSICS / IDLE）
寫進 spec、不填動畫內容