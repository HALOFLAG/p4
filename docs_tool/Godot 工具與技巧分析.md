# Godot 工具與技巧分析（餘響專案視角）

> 針對 2D 解謎平台類遊戲常用的 Godot 4 功能與技巧，分析每一項的：
> - 🎯 **運作目標**：解決什麼問題
> - ⚙️ **運作方式**：在 Godot 內的具體機制
> - 📊 **與目前的差距**：餘響專案現況 vs 完整導入後
> - 💰 **導入成本與時機**：學習成本、合適切入點
>
> **閱讀順序建議**：先看 §〇 已用盤點，再依需要跳讀 §一~§八。

---

## 〇、目前已用的工具盤點

| 工具 | 用途 | 使用狀態 |
|---|---|---|
| **CharacterBody2D** | Player / Clone | ✓ 完整 |
| **Area2D** | Hazard / Button / Exit / Sign / Checkpoint / Teleporter / TriggerZone | ✓ 完整 |
| **StaticBody2D** | 地板 / 牆 / 平台 / Door / PhysicalCarcass | ✓ 完整 |
| **Autoload (Singleton)** | PlayerController / AudioManager / GameStats / RoomManager / CarcassManager | ✓ 5 個 |
| **AudioStreamPlayer + AudioBus** | Master / Music / SFX 三軌混音、距離衰減 | ✓ 完整 |
| **Tween** | 門開合、按鈕壓下、checkpoint、HUD 淡入 | ✓ 大量使用 |
| **`@tool` script** | components/ 下 5 個元件（PressButton/Door/Exit/Platform/HazardZone）即時預覽 | ✓ 剛做完 |
| **Scene Inheritance** | demo_room1~6 繼承 Room.tscn | ✓ 剛做完 |
| **Signal** | 各物件互通 | ✓ 大量使用 |
| **Custom Resource (.tres)** | Recording.gd 用 `extends Resource` | △ 僅一處 |
| **Shader** | TitleScreen 背景動態效果 | △ 僅一處 |
| **平台跳躍手感技巧** | Coyote Time + Jump Buffer + Variable Jump + 不對稱重力 | ✓ 完整 |

> 你比一般初學者起點高很多。Recording 已經懂 Resource 概念，跳躍手感在 Player.gd:30-31 + 158-182 完整實作。下方分析會反映這些事實。

---

## 一、強相關、優先補的 4 個

### 1.1 Custom Resource (.tres) — 資料驅動

#### 🎯 運作目標
把「會變動的數值/設定」從程式碼**抽出來變成可在 Inspector 編輯的資料卡**。改數值不用碰 .gd / .tscn、可批次管理、可序列化（存讀檔、分享）。

#### ⚙️ 運作方式
1. 建一個 GDScript 檔，`extends Resource` + `class_name`
2. 用 `@export` 暴露想編輯的欄位
3. FileSystem 右鍵 → New Resource → 選你的 class
4. 在 Inspector 內填值、存成 `.tres`
5. 其他腳本用 `@export var data: MyResource` 引用，或 `load("res://data/foo.tres")`

```gdscript
class_name LeverConfig extends Resource

@export var initial_state: bool = false
@export var sfx_on: AudioStream
@export var sfx_off: AudioStream
@export var visual_color_on: Color = Color.GREEN
@export var visual_color_off: Color = Color.GRAY
```

存成 `data/lever_default.tres`、`data/lever_red.tres`，掛到不同拉桿實例 inspector 上。

#### 📊 與目前的差距
- **已用**：[Recording.gd](../godot/scripts/Recording.gd) 已是 Resource——能用，但只當「記憶體資料容器」，沒實際存成 .tres
- **未用**：
  - 機關參數寫死在 const（如 [Door.gd](../godot/scripts/Door.gd) 的 `OPEN_TIME = 0.6`）
  - Player 的 `MAX_SPEED`、`JUMP_VELOCITY` 等手感數值是 const，不同關卡無法 override
  - 關卡 metadata（房名、提示文字、area_color）混在 .tscn 內、無法批次讀取做關卡選單

**完整導入後**：每個機關有 `MechConfig.tres`、每個房間有 `RoomMeta.tres`、Player 手感分 `WalkConfig.tres`（潛行模式可換另一個）。

#### 💰 導入成本/時機
- **成本**：低。學一次概念 30 分鐘
- **時機**：下次新增第 2 個拉桿/彈簧時，順手抽 Config.tres
- **建議**：第一個切入點是 `Recording.gd` 加「實際存成 .tres 到 user://」，玩家就能分享通關錄影

---

### 1.2 AnimationPlayer — 取代手刻動畫

#### 🎯 運作目標
**在編輯器內 timeline 拖曲線**做動畫，取代 `_physics_process` 手刻插值或 Tween 鏈。能動任何屬性（位置、顏色、scale、collision_disabled），還能在 keyframe 上發 signal、播 sfx、呼叫 method。

#### ⚙️ 運作方式
1. 加 `AnimationPlayer` 節點
2. 在編輯器底部「Animation」面板新增動畫（如 `door_open`）
3. 設長度（如 0.6 秒）、加 keyframe 改屬性
4. 程式碼呼叫 `$AnimationPlayer.play("door_open")`
5. 訂閱 `animation_finished` signal 銜接後續邏輯

對 Door 的具體例子：
```gdscript
# 取代 Door.gd 現在的 _physics_process 手刻
func set_target(open: bool) -> void:
    if open:
        $AnimationPlayer.play("door_open")
    else:
        $AnimationPlayer.play_backwards("door_open")
```

時間軸內：
- 0.0s：visual.position.y = 0、scale.y = 1、collision.disabled = false
- 0.6s：visual.position.y = door_height、scale.y = 0.001、collision.disabled = true
- 0.5s 處可插一個 method call → `play_sfx("door_open_complete")`

#### 📊 與目前的差距
- **目前**：[Door.gd:_physics_process](../godot/scripts/Door.gd) 手刻 0.6s 插值；[Checkpoint.gd:_activate](../godot/scripts/Checkpoint.gd) 用 Tween 鏈；Sign 用 Tween；按鈕壓下用 Tween；`PauseMenu`、`HUD` 也都靠 Tween
- **問題**：動畫散在多個 .gd 內、改參數要回去看程式碼、不能視覺化預覽
- **導入後**：所有動畫集中在每個物件的 AnimationPlayer 內，編輯器拖一拖就改、無痛預覽

#### 💰 導入成本/時機
- **成本**：學一次 30~60 分鐘（最關鍵的一次性投資）
- **時機**：下次需要做 Player 動畫（idle/run/jump 序列）時順便學
- **第一個練習**：把 [Door.gd](../godot/scripts/Door.gd) 的 `_physics_process` 動畫換成 AnimationPlayer

#### ⚠️ 與既有系統的相容
Door 的 `should_open` 邏輯與「達到 100% 才能穿過」門檻是錄製/重現的關鍵——換成 AnimationPlayer 時要確保動畫 60fps deterministic（AnimationPlayer 預設用 delta 動，可能跨幀數有 floating-point 差異，與 Recording 系統一致性需驗證）。

---

### 1.3 State Machine — 玩家行為管理

#### 🎯 運作目標
把「角色在不同狀態下行為不同」這件事**結構化**，避免 if-else 樹爆炸。每個狀態獨立 enter/update/exit。

#### ⚙️ 運作方式（簡單版）
最低成本：用 enum + match。

```gdscript
enum State { NORMAL, FROZEN, RECORDING_RITUAL, DEAD }
var state: State = State.NORMAL

func _physics_process(delta):
    match state:
        State.NORMAL: _update_normal(delta)
        State.FROZEN: pass
        State.RECORDING_RITUAL: _update_ritual(delta)
        State.DEAD: pass

func _change_state(new: State):
    _exit_state(state)
    state = new
    _enter_state(new)
```

進階版：每個 state 是一個獨立 `Node`，有自己的 enter/update/exit，主 StateMachine 節點派送呼叫。可用 Godot 4 的 AnimationTree 內建的 StateMachine，也可手刻。

#### 📊 與目前的差距
- **目前**：[Player.gd](../godot/scripts/Player.gd) 用 4 個 boolean flag 管狀態：
  - `is_frozen`（錄製中本體 + 凍結中分身）
  - `is_dead`（死亡）
  - 隱式的「正常」（兩者皆否）
  - 子類 Clone / RecordingProxy 用繼承覆寫行為
- **不算糟**——目前複雜度還在可控範圍。但若再加：「教學模式」、「過場控制」、「特殊機關鎖控」，flag 數會爆增。
- **導入後**：清楚的 4~6 個 state、每個 state 行為集中、加新 state 不污染舊邏輯。

#### 💰 導入成本/時機
- **成本**：中。簡單版 1 小時、進階版 3~5 小時
- **時機**：當你發現 `is_X and not is_Y and is_Z` 這種多 flag 組合判斷出現第 3 次以上
- **建議**：暫不用做。你目前 Player.gd 還算清楚，先加新機關，等 flag 真的爆了再重構。

---

### 1.4 平台跳躍手感技巧 — 已完整實作 ✓

#### 🎯 運作目標
讓「準確的物理模擬」變成「玩家覺得舒服」。三大技巧解決三類惱人狀況。

#### ⚙️ 運作方式 + 📊 餘響現況

| 技巧 | 解決的問題 | 餘響實作位置 | 狀態 |
|---|---|---|---|
| **Coyote Time** | 走出邊緣瞬間按跳沒反應 | [Player.gd:30, 157-161](../godot/scripts/Player.gd) `COYOTE_TIME = 0.15` | ✓ |
| **Jump Buffer** | 落地前 0.05s 按了跳結果沒跳到 | [Player.gd:31, 163-169](../godot/scripts/Player.gd) `JUMP_BUFFER = 0.15` | ✓ |
| **Variable Jump Height** | 不論按多久跳一樣高 | [Player.gd:21, 178-182](../godot/scripts/Player.gd) `JUMP_CUT_VELOCITY` | ✓ |
| **不對稱重力** | 上升像氣球、下降像鉛塊（業界標準） | [Player.gd:25-26, 151-155](../godot/scripts/Player.gd) `GRAVITY_RISING / FALLING` | ✓ |
| **加速度而非瞬移** | 啟動有「重量」感 | [Player.gd:14-17, 142-148](../godot/scripts/Player.gd) `ACCEL` | ✓ |

#### 💰 導入成本
**0**——你已全部實作，且調校過（看註解可知是讀過 Celeste/Mario/Hollow Knight 文章後做的）。

#### 可繼續優化的方向
- **Wall slide / Wall jump**：蹬牆跳。但你 Tier C 標明「衝突核心移動手感」、不建議
- **Dash / Air dash**：衝刺。同上，會打掉錄製假設
- **Apex hangtime**：跳到頂點短暫減重力（讓玩家有更多時間調整方向）。低成本可試

---

## 二、TileMap（地形系統）

> ⚠️ **2026-05-08 M15.1 決策**：選 (c) 不引入 TileMap、改強化現有元件化策略。
> 原本 § 二 寫「建議混合策略」、是基於泛用論證；M15.1 盤點後發現瓶頸不在 TileMap 缺席、而是 Platform.tscn 元件未被充分使用、故改向。詳見 § 2.1。

#### 🎯 運作目標
用「畫圖」方式擺地形，取代手刻 StaticBody2D。

#### ⚙️ 運作方式
TileSet（圖塊資料庫，.tres）+ TileMapLayer（畫布節點）。Godot 4.3+ 推薦 TileMapLayer。

#### 📊 與目前的差距
- 目前：每塊地板/牆/平台 = 手刻 StaticBody2D + Polygon2D + CollisionShape2D（3 節點）
- 導入後：每格地板 = TileMap 內 1 byte 資料；改美術同步全世界

#### 💰 導入成本/時機
- 成本：第一次 1~2 小時（配 TileSet + collision）；之後新房間極快
- 時機：M15.1 已決定**本 v1.0 不引入**；若 v2.0 自製關卡編輯器或購買 tile sprite 美術、再評估

---

### 2.1 M15.1 評估與決策（2026-05-08）

#### 背景
M15 階段需 lock 後續 6~10 關的地形實作策略。3 週工期、單人、無美術 sprite（全 Polygon2D 色塊）、元件化已成熟。前 2 天做評估、第 2 天結束 lock。

#### 盤點現況

| 觀察 | 細節 |
|---|---|
| Platform.tscn 元件成熟度 | `@tool` + `size`/`color` 即時預覽、矩形完全可控 |
| 既有 demo room 元件使用率 | **低**——demo_room1 的 P1~P6、demo_room4 的 L1~L3/R1~R3 全是 inline StaticBody2D + Polygon2D + CollisionShape2D（3 節點/塊）、未使用 Platform.tscn |
| 異形需求 | demo_room1 的 P2 為帶缺口五邊形、demo_room4 的 L4Btn/R4Btn 為加寬按鈕台 |
| 重複地形密度 | 中等。每房間 6~12 個小平台、規格高度雷同（197×30、240×30、wall 600×40）|
| 視覺風格 | 純 Polygon2D 色塊、無紋理、無 sprite |

#### 三選項權衡

| 維度 | (a) 全 TileMap | (b) 混合策略 | (c) 強化元件、不引入 TileMap |
|---|---|---|---|
| 學習成本 | 高（TileSet/TileMapLayer/物理層 1.5~2h）| 中（同 a 但只用核心功能）| 0（已會）|
| 6~10 關工時 | 配 TileSet 後刷地形快、但前置投資吃掉前 2 關 | 互動物件保留元件、地形快、平衡 | 沿用元件 + 補 Wall.tscn/Floor.tscn 即可 |
| 與 Recording deterministic 相容 | TileMap 物理是 StaticBody2D 同源、deterministic OK | 同 a | 完全一致（已驗證）|
| 與既有元件整合 | TileMap 不能放互動物件、得分層 | 設計成本中（協調 z-index、collision layer）| 0 摩擦 |
| 異形地形 | TileMap 處理不來、仍需 inline | 異形 inline 處理 | 異形 inline 處理（同現狀）|
| 視覺風格一致性 | 需先做 TileSet 圖塊、不然 TileMap 反而醜 | 同 a | 完全一致（沿用 Polygon2D 色塊）|
| 未來 M14b polish 風險 | 低（TileMap 換貼圖簡單）| 低 | 中（每塊地形自繪、polish 時要換 sprite 比較煩）|

#### 推薦：選項 (c)

**核心理由**：盤點顯示「地形配置慢」不是 TileMap 缺席造成、是 **Platform.tscn 元件沒被用起來**。demo_room1 的 P1~P6 改用 Platform.tscn 後、節點數從 18 降到 6、地形碎片化問題就大半消失。

**為何不選 (a)/(b)**：
- 視覺仍是色塊階段、TileSet 沒美術可放、用 TileMap 等於「為了 TileMap 而 TileMap」
- 3 週工期、學新工具的投資回收期 > 剩餘關卡數、邊際效益不足
- 互動物件（按鈕、門、傳送門）已是 `.tscn` 元件、TileMap 不能直接整合、(b) 反而讓地形與機關對齊變麻煩

#### 後續 8 關實作模板

1. **地形元件擴充清單**（M15.1 收尾、預估 30 分鐘）：
   - `Floor.tscn`（@tool、size/color、預設 1280×40）
   - `Wall.tscn`（@tool、size/color、預設 40×600）
   - `Platform.tscn`（已存在、保持不變）
   - 異形地形仍 inline（每關 1~2 個、用於設計重點）

2. **每關地形配置 SOP**：
   - Step 1：拖 Room.tscn（繼承）→ 設 area_color
   - Step 2：拖 Floor.tscn / Wall.tscn 處理外框（4 個節點搞定）
   - Step 3：拖 Platform.tscn × N 處理重複小平台（每塊 1 個節點）
   - Step 4：異形地形 inline StaticBody2D（不超過 2 個/關）
   - Step 5：拖互動元件（PressButton/Door/Exit/Teleporter…）
   - Step 6：連 signal、設 LogicGate

3. **產能預估**：每關地形配置 < 20 分鐘、滿足 3 週做完 6~10 關。

#### Escape Hatch（重新評估條件）

若 M15.2 大綱出現以下任一條件、回頭重評選項 (a)/(b)：
- 單關地形重複塊數 > 30（目前最高 ~12）
- 確定 M14b 會購買/委託 tile sprite 美術資源
- 加入「自製關卡編輯器」需求（TileMap 在編輯器內畫圖體驗遠勝拖元件）

#### 與既有系統相容性備註

- **Recording 一致性**：選 (c) 完全沿用 StaticBody2D、與現有 `_physics_process` 60Hz tick 一致、無風險
- **z-index / collision layer**：地形元件已固定為 layer 1、與機關元件 layer 配置不衝突
- **未來換 sprite**：Polygon2D 換 Sprite2D 是節點層級替換、不影響 collision、與 (a) 換 TileSet 紋理同等簡單

---

## 三、視覺強化類

### 3.1 GPUParticles2D — 粒子效果

#### 🎯 運作目標
廉價地產生視覺事件：灰塵、火花、煙霧、儀式光暈、跳躍尾跡、傳送門光點。

#### ⚙️ 運作方式
1. 加 `GPUParticles2D` 節點
2. 設 `process_material`（ParticleProcessMaterial 或自訂 ShaderMaterial）
3. 設 amount、lifetime、emission shape
4. `emitting = true` 開始 / `restart()` 重發

#### 📊 與目前的差距
- **目前**：錄製儀式可能用了一些（需要看實作；PlayerController 648 行有不少儀式相關）。Polygon2D + Tween 模擬粒子可能存在
- **導入後**：
  - 跳躍/落地揚塵
  - 機關按下時火花
  - 死亡爆裂碎片
  - 傳送門持續光點
  - 分身淡入時的儀式星塵（如果現在沒有的話）

#### 💰 導入成本/時機
- **成本**：低（基本用法）；中（自訂 shader 進階特效）
- **時機**：M11 美術 polish 階段；或新增動作機關（彈簧）時順便加跳躍尾跡

---

### 3.2 Light2D + Occluder — 動態光源

#### 🎯 運作目標
做明暗對比、聚光燈、提示引導、夜晚場景。Occluder 讓 Light2D 被牆擋住產生陰影。

#### ⚙️ 運作方式
1. 加 `PointLight2D`（點光源）或 `DirectionalLight2D`
2. 設 texture（光形）、energy（亮度）、color、range
3. 牆/地板加 `LightOccluder2D` + `OccluderPolygon2D`，光會被擋住
4. 全場景加 `CanvasModulate`（壓暗環境，光才看得出來）

#### 📊 與目前的差距
- **目前**：場景全亮（CanvasModulate 沒設）、LightPoint 只是 Polygon2D 不是真光源
- **導入後**：
  - 「過去自己」生成的 LightPoint 真的發光、照亮周圍
  - 死路盡頭加一道光引導玩家方向
  - 房間整體偏暗，按鈕/門/出口透過自身光點突出
  - 餘響的「儀式」基調與微光美學天作之合

#### 💰 導入成本/時機
- **成本**：中（光源 + occluder + canvas modulate 三件套，第一次要學）
- **時機**：M11 美術 polish；或當你要做「夜晚 / 室內」 area 時

---

### 3.3 CanvasModulate — 全螢幕染色

#### 🎯 運作目標
全場套一層色（暗色、暖色、警報紅）。簡單但效果強。

#### ⚙️ 運作方式
場景內加 `CanvasModulate` 節點，設 color。整個 canvas（除了 UI）都套這個顏色。

#### 📊 與目前的差距
- **目前**：無
- **導入後**：
  - 進入「終局」area 整體調暗
  - 死亡瞬間瞬切紅色再淡出
  - 不同 area 用不同色調（已有 `area_color` 在 [Room.gd](../godot/scripts/Room.gd:12)，可順勢套到 CanvasModulate）

#### 💰 導入成本/時機
- **成本**：超低（5 分鐘）
- **時機**：M11 polish 順手加

---

### 3.4 Shader — 自訂視覺效果

#### 🎯 運作目標
GPU 上做任何視覺：水波紋、輪廓、波紋、粒狀、glitch、過場。

#### ⚙️ 運作方式
1. 寫 `.gdshader`（GLSL-like 語法）
2. 包成 ShaderMaterial（.tres）
3. 套到節點的 material 屬性

#### 📊 與目前的差距
- **目前**：[TitleScreen.tscn:6-35](../godot/scenes/TitleScreen.tscn) 已有背景 shader（你已會用）
- **未用於**：
  - 玩家輪廓（跳躍時加 outline 強化角色）
  - 分身（"過去的你"）半透明 + 漣漪 shader
  - 過場黑屏改成自訂 dissolve shader
  - 死亡 chromatic aberration 一瞬

#### 💰 導入成本/時機
- **成本**：高（GLSL 學一個新語言）；但**抄現成**很容易（GodotShaders.com 一堆免費資源）
- **時機**：等遊戲玩法完成、開始 polish 視覺時

---

### 3.5 Parallax2D — 視差背景

#### 🎯 運作目標
多層背景以不同速度移動，產生深度感。

#### ⚙️ 運作方式
Godot 4.3+ 用 `Parallax2D` 節點（取代舊的 ParallaxLayer/ParallaxBackground）。每層設 `scroll_scale`（0.5 = 半速移動 = 看起來在遠方）。

#### 📊 與目前的差距
- **目前**：背景單一深灰
- **導入後**：遠方山脈/雲/光暈以 0.2 倍速移動、近景細節 1 倍速、玩家走動有立體感

#### 💰 導入成本/時機
- **成本**：低（節點配一配）
- **時機**：M11 polish；或當你決定要做「室外」主題時

---

### 3.6 Camera2D Shake — 鏡頭晃動

#### 🎯 運作目標
重擊回饋（落地、爆炸、boss 攻擊）。常見只要 5~10 行程式碼。

#### ⚙️ 運作方式
```gdscript
func shake(intensity: float, duration: float) -> void:
    var t := 0.0
    while t < duration:
        offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
        await get_tree().process_frame
        t += get_process_delta_time()
    offset = Vector2.ZERO
```

#### 📊 與目前的差距
- **目前**：無
- **導入後**：分身死亡時微震、玩家落地超高距離時震、儀式爆裂時震

#### 💰 導入成本/時機
- **成本**：超低（10 分鐘）
- **時機**：隨時

---

## 四、物理擴充類

### 4.1 RigidBody2D — 物理模擬物件

#### 🎯 運作目標
讓物件遵守物理定律：可推、可壓、可彈、會受重力影響。

#### ⚙️ 運作方式
- StaticBody2D：不動（牆、地板）
- CharacterBody2D：腳本控制（玩家、分身）
- **RigidBody2D**：物理引擎控制（箱子、滾石、爆炸碎片）

#### 📊 與目前的差距
- **目前**：[PhysicalCarcass](../godot/scripts/PhysicalCarcass.gd) 是 StaticBody2D（殘骸不動，按鈕仍能踩）
- **可導入場景**：
  - 推箱子謎題（過去自己推 → 卡位 → 現在自己跳上去）
  - 重物壓住計時門
  - 爆炸碎片
- **疑慮**：與錄製/重現是否 deterministic？RigidBody2D 物理計算每幀有微浮點差異，多次重現可能軌跡不一致

#### 💰 導入成本/時機
- **成本**：中（須處理 deterministic 問題）
- **時機**：先別用。直到你想做「推物」謎題時，再評估是否值得處理重現一致性問題

---

### 4.2 One-way Platform — 單向平台

#### 🎯 運作目標
從下方可穿透、從上方踩得住。經典平台跳躍機關。

#### ⚙️ 運作方式
StaticBody2D 的 inspector 內 `Platform / One Way Collision = true`，搭配 `One Way Collision Margin`。

#### 📊 與目前的差距
- **目前**：所有平台都是兩面實體
- **導入後**：垂直跳躍謎題大量增加（從低處跳到高層、再從更高層 fallthrough 回低層）

#### 💰 導入成本/時機
- **成本**：超低（每塊平台改一個 toggle）
- **時機**：下次設計垂直謎題時

---

### 4.3 Slope Handling — 斜面行走

#### 🎯 運作目標
讓 Player 在斜面上正常走路（不滑、不卡頭）。

#### ⚙️ 運作方式
CharacterBody2D 的 inspector：
- `Floor Snap Length`：地面吸附（避免下斜坡浮空）
- `Floor Max Angle`：最大可走斜度
- `floor_constant_speed = true`：上下斜走一樣快

#### 📊 與目前的差距
- **目前**：全水平地形，沒斜坡
- **導入後**：可以做斜面平台、滑坡、Y 字路口

#### 💰 導入成本/時機
- **成本**：低（調 inspector + 少量 fine-tune）
- **時機**：當你決定要破水平單調時

---

## 五、系統與資料類

### 5.1 ConfigFile — 設定檔

#### 🎯 運作目標
存讀玩家設定（音量、解析度、控制鍵），跨平台。

#### ⚙️ 運作方式
```gdscript
var config := ConfigFile.new()
config.set_value("audio", "music_volume", 0.8)
config.save("user://settings.cfg")

# 讀
config.load("user://settings.cfg")
var v = config.get_value("audio", "music_volume", 1.0)
```

#### 📊 與目前的差距
- **目前**：[PauseMenu.gd](../godot/scripts/PauseMenu.gd) 內音量設定在記憶體、關掉就還原
- **導入後**：玩家設好音量後、下次開遊戲還在

#### 💰 導入成本/時機
- **成本**：低（30 分鐘）
- **時機**：M11 之後 polish

---

### 5.2 FileAccess + JSON — 存讀檔

#### 🎯 運作目標
存讀任意資料（玩家進度、自訂關卡、錄製分享）。

#### ⚙️ 運作方式
```gdscript
var data := {"checkpoint": "demo_room4", "deaths": 12, "time": 234.5}
var file := FileAccess.open("user://save.json", FileAccess.WRITE)
file.store_string(JSON.stringify(data))
```

#### 📊 與目前的差距
- **目前**：無存檔。每次重開從頭玩
- **導入後**：
  - 進度存讀
  - 通關時間排行（[GameStats.gd](../godot/scripts/GameStats.gd) 已收集數據，缺存讀層）
  - 玩家自製關卡載入

#### 💰 導入成本/時機
- **成本**：低（1 小時做基本存讀）
- **時機**：M11 之後

---

### 5.3 Translation (i18n) — 多語言

#### 🎯 運作目標
所有顯示字串可切換語言（中/英/日）。

#### ⚙️ 運作方式
1. 字串改用 `tr("KEY")` 或 `text = tr("ROOM2_SIGN")`
2. 建 `.csv` 對照表（KEY, zh_TW, en, ja）
3. 設 `TranslationServer.set_locale("en")` 切換

#### 📊 與目前的差距
- **目前**：所有字串硬編碼為繁體中文（Sign.text、HUD label、PauseMenu...）
- **導入後**：可發行英文版

#### 💰 導入成本/時機
- **成本**：中（一次性把字串抽出來、建 csv）
- **時機**：考慮上架 Steam 時再做。**現在不必做**

---

### 5.4 Theme — UI 全域樣式

#### 🎯 運作目標
所有 UI（Button、Label、Panel）統一字型、顏色、間距，改一處全部同步。

#### ⚙️ 運作方式
1. 建 `default.theme` 資源
2. 設各類 Control 節點的樣式
3. 在根節點 set theme，自動繼承到所有子 Control

#### 📊 與目前的差距
- **目前**：HUD、PauseMenu、TitleScreen 各自設 `theme_override_*` 屬性
- **導入後**：全 UI 一致風格、改字型一次到位

#### 💰 導入成本/時機
- **成本**：中（學 Theme 編輯器 + 設樣式 = 2 小時）
- **時機**：UI 多到 4+ 場景時

---

### 5.5 InputMap — 輸入綁定

#### 🎯 運作目標
把實體按鍵抽象成「動作」，方便重新綁定、支援手把。

#### ⚙️ 運作方式
1. Project Settings → Input Map 加動作（如 `move_left`、`record`、`delete_slot`）
2. 程式碼用 `Input.is_action_pressed("move_left")`
3. 手把用同一動作觸發、自動跨鍵盤/手把

#### 📊 與目前的差距
- **已用**：[Player.gd:97](../godot/scripts/Player.gd#L97) 等已用 `Input.is_action_pressed("move_left")` ✓
- **未用**：玩家可重綁鍵、手把支援

#### 💰 導入成本/時機
- **成本**：低（重綁 UI 1 小時、手把 inspector 設定 30 分鐘）
- **時機**：上架前

---

### 5.6 Object Pooling — 物件池

#### 🎯 運作目標
重複用同個物件而非頻繁 instance/free，避免卡頓。

#### ⚙️ 運作方式
```gdscript
var pool: Array[Bullet] = []

func get_bullet() -> Bullet:
    if pool.is_empty():
        return Bullet.new()
    return pool.pop_back()

func return_bullet(b: Bullet) -> void:
    b.visible = false
    pool.append(b)
```

#### 📊 與目前的差距
- **目前**：Clone / RecordingProxy 每次召喚都 instantiate、結束都 free
- **問題**：餘響每場景最多 5 個 Clone，頻率不高，**目前無痛**
- **未來必要**：做到「100 個分身同時演」會卡

#### 💰 導入成本/時機
- **成本**：低（30 分鐘）
- **時機**：當你發現分身召喚有可感知延遲。**現在無需**

---

## 六、除錯與編輯器擴充

### 6.1 `_draw()` Debug Lines

#### 🎯 運作目標
在運行時畫出隱形資料：碰撞框、判定區、軌跡、AI 視野。

#### ⚙️ 運作方式
```gdscript
func _draw() -> void:
    draw_line(Vector2.ZERO, velocity, Color.RED, 2.0)
    draw_circle(target_pos, 10, Color.GREEN)

func _physics_process(_d):
    queue_redraw()  # 強制重畫
```

#### 📊 與目前的差距
- **目前**：靠 print 除錯
- **導入後**：
  - 分身錄製範圍可視化
  - 房間 Bounds 即時繪製
  - 按鈕→門連線視覺化（哪個按鈕觸發哪個門）

#### 💰 導入成本/時機
- **成本**：超低（10 分鐘）
- **時機**：除錯具體 bug 時臨時加

---

### 6.2 EditorPlugin / Inspector Plugin

#### 🎯 運作目標
擴充 Godot 編輯器：自訂工具列按鈕、dock、屬性編輯器、場景檢視。

#### ⚙️ 運作方式
1. `addons/my_plugin/plugin.gd` extends EditorPlugin
2. enable from Project Settings → Plugins
3. 加 dock、自訂 Inspector、自訂 import...

#### 📊 與目前的差距
- **目前**：無外掛
- **可做**：
  - **元件庫 dock**：列出 components/ 下所有元件、點一下放到場景中央
  - **連線預覽**：在編輯器內可視化 PressButton → Door 的 signal 綁定
  - **關卡測試器**：場景內加按鈕「從這個房間開始遊戲」

#### 💰 導入成本/時機
- **成本**：中~高（複雜外掛 5+ 小時）
- **時機**：**最後手段**。除非場景化 + scene inheritance + 元件化都做完還覺得慢，否則別碰

---

## 七、解謎平台類設計概念

### 7.1 Determinism（決定性）

#### 🎯 運作目標
每次重現完全一致：相同輸入 → 相同結果。**這是餘響的核心**。

#### ⚙️ 運作方式
- `_physics_process` 用固定 60Hz（Godot 預設）
- 物理計算只在 `_physics_process` 內做
- 隨機數用固定 seed
- 避免 RigidBody2D（浮點不穩）

#### 📊 與目前的差距
- **目前**：核心已實作。Recording 系統依賴此假設
- **風險點**：
  - 將來若加 RigidBody2D 機關（推箱）、需驗證重現一致性
  - 若改用 AnimationPlayer 取代 _physics_process 動畫，需驗證動畫也是 60Hz tick-driven

#### 💰 維護成本
持續注意。每次加新機關都要問「這在錄製/重現時行為一致嗎？」

---

### 7.2 Snapshot / Restore — 狀態快照

#### 🎯 運作目標
存取某瞬間的世界狀態，可回到那一刻。Undo、checkpoint、replay 都靠這個。

#### ⚙️ 運作方式
- 每個會變動的物件實作 `serialize() / deserialize()`
- 主控節點掃描所有物件、收集 snapshot 為 Dictionary
- 還原時逐個 deserialize

#### 📊 與目前的差距
- **目前**：[Checkpoint](../godot/scripts/Checkpoint.gd) 只存玩家位置；其他狀態（按鈕、門、PressCounter 計數）在死亡重生時靠 zone reset 重置而非快照
- **完整導入**：
  - 真正的存檔（記錄門/計數器當前狀態，不只 Player 位置）
  - 「Z 鍵回到 3 秒前」的時光倒流玩法（不一定要做）

#### 💰 導入成本/時機
- **成本**：高（每個物件加 serialize/deserialize）
- **時機**：上架前做存檔功能、或新增「時光倒流」玩法時

---

### 7.3 Undo / Redo

#### 🎯 運作目標
玩家可回退操作（《Baba Is You》、《Patrick's Parabox》核心）。

#### ⚙️ 運作方式
維護 history stack，每次「動作」（步、按按鈕）push 一個 snapshot，按 Z pop。

#### 📊 與目前的差距
- **目前**：餘響的「錄製/重現」是替代方案——你不重來世界、你召喚過去自己
- **要不要做 undo**：與餘響的設計哲學衝突。**不建議**

---

### 7.4 Solution Validation — 解法驗證

#### 🎯 運作目標
自動驗證關卡可解（給關卡編輯器用）。

#### ⚙️ 運作方式
跑模擬：用 BFS/A* 探索玩家動作空間，看能否到達 Exit。

#### 📊 與目前的差距
- **目前**：手動測試
- **導入時機**：當你做出「玩家自製關卡」功能、需要過濾無解作品時

#### 💰 導入成本
高（4+ 小時設計，且不一定 100% 有效）

---

### 7.5 Hint System — 提示系統

#### 🎯 運作目標
玩家卡關時提供漸進提示（視覺 highlight、文字、影片示範）。

#### ⚙️ 運作方式
- 計時偵測玩家在房間停留多久沒解
- 達閾值後 fade in 提示 UI
- 多級提示：first hint vague、second hint specific

#### 📊 與目前的差距
- **目前**：[Sign.tscn](../godot/scenes/Sign.tscn) 是固定提示（被動接近觸發）
- **導入後**：動態提示（卡 60 秒後出現），但要小心干擾「自己想出解法」的成就感

#### 💰 導入成本/時機
- **成本**：低
- **時機**：playtest 後發現某些謎題卡關率高再加

---

### 7.6 Replay Sharing — 通關錄影分享

#### 🎯 運作目標
玩家把自己通關的錄製存成檔案、分享給朋友。

#### ⚙️ 運作方式
- Recording.gd 已是 Resource，可 ResourceSaver.save 存成 .tres
- 上傳到雲端 / 用 base64 編碼分享 string

#### 📊 與目前的差距
- **目前**：Recording 只在記憶體
- **導入後**：玩家通關後可分享 5 段錄製組成的「解法」、其他人載入後直接看演

#### 💰 導入成本/時機
- **成本**：中（序列化 + UI）
- **時機**：上架後社群功能

---

## 八、優先順序總表

依 **「對餘響當前痛點 × 學習成本 × 通用性」** 排序：

### Tier S — 強推現在做

| # | 項目 | 為何 | 成本 |
|---|---|---|---|
| 1 | **AnimationPlayer** | 機關動畫散落各處、預覽不直觀 | 30~60 min |
| 2 | **Custom Resource 擴展** | 機關參數化、通往關卡編輯器 | 30 min（單個機關） |
| 3 | **CanvasModulate + area_color** | 房間視覺區隔、5 分鐘大幅 polish | 10 min |
| 4 | **Camera Shake** | 死亡 / 落地反饋、超便宜 | 10 min |

### Tier A — 中期補（M11 polish 階段）

| # | 項目 | 為何 |
|---|---|---|
| 5 | Light2D + Occluder | 餘響的「儀式」基調與微光美學契合 |
| 6 | Parallax2D | 簡單擴增景深 |
| 7 | GPUParticles2D | 跳躍/落地/儀式回饋 |
| 8 | One-way Platform | 解鎖垂直謎題設計 |
| 9 | ConfigFile | 設定持久化 |
| 10 | TileMap（混合策略） | 新增多房間時 |

### Tier B — 看需要

| # | 項目 | 何時 |
|---|---|---|
| 11 | State Machine（正式） | Player.gd 的 flag 數爆增時 |
| 12 | Theme | UI 場景超過 4 個時 |
| 13 | Slope Handling | 想加斜面地形時 |
| 14 | Replay Sharing | 上架後社群功能 |
| 15 | Translation | 上 Steam 時 |
| 16 | Hint System | playtest 後若發現卡關 |

### Tier C — 暫不需要

| # | 項目 | 原因 |
|---|---|---|
| - | RigidBody2D | 與 deterministic 重現衝突 |
| - | Undo/Redo | 與餘響「錄製」哲學衝突 |
| - | Solution Validation | 沒有玩家自製關卡需求 |
| - | Shader 進階 | 已會用、視 polish 時程 |
| - | Object Pooling | 分身數量低、無痛 |
| - | EditorPlugin | 80% 需求用 @tool + scene component 已解 |

---

## 九、後續行動建議

### 短期（一週內）
1. **加 CanvasModulate 用 area_color**（10 分鐘）— 立刻看到房間視覺差異
2. **加 Camera Shake**（10 分鐘）— 死亡/落地反饋
3. **學 AnimationPlayer**（學一次 60 分鐘，之後永遠受用）

### 中期（M11 polish）
4. 用 AnimationPlayer 重做 Door 開合（驗證 deterministic）
5. 加 Light2D 重做 LightPoint 視覺
6. 加 GPUParticles2D 跳躍尾跡 / 儀式星塵

### 長期（上架前）
7. ConfigFile + FileAccess 存讀檔
8. Theme 統一 UI
9. 視需求加 Translation、Replay Sharing

---

## 附錄：相關設計文件

- 機關層分析：[平台機關工具箱.md](../平台機關工具箱.md)
- 關卡層提案：[謎題提案.md](../謎題提案.md)
- 元件化重構（已完成）：[godot/scenes/components/](../godot/scenes/components/)
- 房間繼承場景（已完成）：[godot/scenes/rooms/](../godot/scenes/rooms/)
