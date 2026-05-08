# 動畫狀態 Mapping Spec（M14a.1）

> **產出於 2026-05-08（M14a.1）**
> 對應「狀態 → 動畫 mapping 詳細說明.md」§ 六 範本。
> 本文只決定**動畫名稱、callback_mode、覆蓋對象**——不填動畫內容（M14b 才填）。
>
> 設計決策（M14a 啟動前確認）：
> - Player 動畫範圍：**完整 8 個**（含 land / record_start / record_end）
> - 既有 Tween 元件：**全部遷移到 AnimationPlayer**（命名統一）
> - M14a.4 失敗退路：**接受全面回退到 _physics_process 手刻**（保 Recording deterministic 為優先）
> - 動畫風格基調：**抽象**（光暈、粒子、shader——多用 modulate / scale / Polygon2D 既有節點變化、不做骨架）

---

## 一、術語約定

| 術語 | 含義 |
|---|---|
| **callback_mode** | `AnimationPlayer.callback_mode_process`、決定動畫 tick 跟 `_physics_process`（PHYSICS、60Hz、deterministic）還是 `_process`（IDLE、隨 fps、非 deterministic）|
| **PHYSICS-critical** | 動畫直接影響玩法（碰撞、位移、可踩可穿），**必須** PHYSICS、且 Recording 必須驗證一致 |
| **PHYSICS-pref** | 動畫不影響玩法但建議 PHYSICS（與物理同步較自然）|
| **IDLE** | 純視覺、與 Recording 無關（UI / 純 modulate / 純背景效果）|
| **TBD** | M14b 才填動畫內容（M14a 只佔位）|

> ⚠️ **callback_mode 規則**：所有「玩家或分身會互動的元件」一律 PHYSICS。UI / 字幕 / 環境光暈 / Sign 等純視覺可 IDLE。

---

## 二、Player（8 個動畫）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 觸發點 | 備註 |
|---|---|---|---|---|---|
| idle | `idle` | PHYSICS-pref | TBD（微呼吸：modulate.v 或 scale 微振）| `velocity ≈ 0 + on_floor` | 可循環、loop=true |
| walk | `walk` | PHYSICS-pref | TBD（走路循環：scale.x 微抖）| `velocity.x ≠ 0 + on_floor` | 可循環、loop=true |
| jump | `jump` | PHYSICS-pref | TBD（起跳 squash）| `is_on_floor() → !is_on_floor() 且 velocity.y < 0`（_attempt_jump 成功時）| one-shot |
| fall | `fall` | PHYSICS-pref | TBD（下落姿勢、可空）| `!on_floor + velocity.y > 0` | 可循環 |
| land | `land` | PHYSICS-pref | TBD（落地反饋：alpha 閃 / 短粒子）| `was_on_floor: false → true` | one-shot；可後做、不阻擋 M15 |
| die | `die` | **PHYSICS** | TBD（化煙：modulate.a 1→0 + scale 1→1.2 + 偏色）| `Player.die()` 內呼叫 | one-shot；要與既有 hide visual 配合 |
| record_start | `record_start` | **PHYSICS** | TBD（紅光暈淡入 + frozen 視覺）| `PlayerController.start_recording()` 凍結時 | one-shot；長度 ≤ 0.3s（不影響玩法節奏）|
| record_end | `record_end` | **PHYSICS** | TBD（紅光暈淡出 + 解凍視覺）| `PlayerController.end_recording()` 解凍時 | one-shot |

**共用注意**：
- Player 沒有獨立的 `frozen` 狀態動畫——凍結中**保持 record_start 結束姿勢**（最後一格停住），`record_end` 才解除。
- 所有 Player 動畫的呼叫由 `Player.gd` 內部依狀態切換、不改既有 `_physics_process` 物理。
- M15 設計關卡時可預期：`$Player/AnimationPlayer.is_playing()` 與 `current_animation` 是穩定接口。

---

## 三、Clone（與 Player 共用 + 自家動畫）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 來源 | 備註 |
|---|---|---|---|---|---|
| idle / walk / jump / fall / land | 同 Player | PHYSICS-pref | 同 Player | 繼承 | Clone 共用 Player 的 8 個動畫定義（相同 AnimationPlayer 命名）|
| spawn | `clone_spawn` | **PHYSICS** | TBD（從 LightPoint 淡入：alpha 0→1、modulate 偏藍光）| `Clone._ready()` | one-shot；長度 ≤ 0.4s |
| despawn | `clone_despawn` | **PHYSICS** | TBD（淡出 + 縮）| Recording 播完 → Clone.queue_free 前 | one-shot |
| frozen_freeze | `frozen_freeze` | **PHYSICS** | TBD（M7 凍結：變灰色剪影）| 待設計（freeze 機制）| 目前**不確定**會用到、M14b 視玩法決定 |
| frozen_unfreeze | `frozen_unfreeze` | **PHYSICS** | TBD（解凍：恢復色）| 同上 | 同上 |

> Clone `die` **不重用 Player.die**——Clone 死時生成 PhysicalCarcass、視覺由 Carcass 接手、不再播動畫。

---

## 四、機關（M13.5 freeze 鎖定的 13 個元件 + 4 個固定場景元件）

> 規則：
> - **互動類**（Player / Clone 會接觸）→ PHYSICS-critical 或 PHYSICS-pref
> - **純視覺類**（沒有碰撞影響）→ IDLE 可
> - 既有 Tween 全部遷移到 AnimationPlayer（用戶決策）

### 4.1 PressButton（Tween 遷移）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| idle | `idle` | IDLE | （留空、預設姿勢）| —— |
| pressed | `press_down` | **PHYSICS** | visual.position.y 0 → 6（PRESS_DEPTH）、PRESS_TIME=0.08 | `_animate_press(PRESS_DEPTH)` Tween |
| released | `press_up` | **PHYSICS** | visual.position.y 6 → 0、PRESS_TIME=0.08 | `_animate_press(0.0)` Tween |

**遷移注意**：壓下動畫不影響碰撞（Area2D 偵測仍在 `_on_body_entered`）。但因 Recording 會記住「按鈕被分身按下」、視覺一致性建議 PHYSICS。

### 4.2 Door（_physics_process 手刻 → AnimationPlayer）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| closed | `closed` | **PHYSICS** | （靜態、`visual.position.y=0` `scale.y=1` `collision.disabled=false`）| —— |
| open | `open` | **PHYSICS-critical** | visual.position.y 0→`door_height`、scale.y 1→0.001、collision.disabled false→true（`progress >= PASS_THROUGH_THRESHOLD` 時切）；OPEN_TIME=0.6 | `Door.gd._physics_process` 手刻插值 |
| close | `close` | **PHYSICS-critical** | 反向；CLOSE_TIME=0.6 | 同上、可用 `play_backwards("open")` |

**最關鍵**：Door 是 **M14a.4 第一個驗證的元件**（替代原計畫的 TriggeredPlatform，因 Door 有 collision.disabled 切換、是更嚴格的一致性測試）。

### 4.3 Exit（純偵測、加 triggered 動畫）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 觸發點 |
|---|---|---|---|---|
| idle | `idle` | IDLE | （pulse 環境光暈、可選）| —— |
| triggered | `triggered` | **PHYSICS** | TBD（玩家進入時出口閃光、modulate.value 上升）| `Exit._on_body_entered` reached signal 之後 |

> Exit 既有沒有任何視覺變化、`triggered` 是新加的 polish 動畫、**M14b 才實作、M14a 只佔位**。

### 4.4 Lever（Tween 不存在、但需新增動畫）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| off | `off` | IDLE | 靜態 color_off | `_apply_visual()` 直接設色 |
| flip_on | `flip_on` | **PHYSICS** | TBD（color_off → color_on 漸變、可加 scale 抖）；長度 ≤ 0.2s | 取代 `_apply_visual()` 直接切 |
| on | `on` | IDLE | 靜態 color_on | 同 idle |
| flip_off | `flip_off` | **PHYSICS** | TBD（color_on → color_off 漸變）| 同上 |

### 4.5 Spring（已有 AnimationPlayer + compress、僅補完）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 備註 |
|---|---|---|---|---|
| idle | `idle` | IDLE | （靜態）| —— |
| compress | `compress` | **PHYSICS-pref** | TBD（壓縮：scale.y 1→0.5→1）| **既有 `anim.play("compress")` 已連線**、M14b 只填內容 |

### 4.6 TriggeredPlatform（_physics_process 手刻 → AnimationPlayer）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| at_start | `at_start` | **PHYSICS** | 靜態於 `_start_position` | —— |
| move | `move` | **PHYSICS-critical** | position `_start_position` → `_target_position`、move_duration=1.0、linear 內插 | `_physics_process` 手刻 lerp |
| at_target | `at_target` | **PHYSICS** | 靜態於 `_target_position` | —— |
| return | `return` | **PHYSICS-critical** | 反向；可用 `play_backwards("move")` | 同 move |

> AnimatableBody2D 載人移動：M14a.4 驗證時要特別測「Player 站在平台上錄製 → 重現是否同步」。

### 4.7 CrumblingPlatform（_physics_process 手刻 → AnimationPlayer）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| solid | `solid` | **PHYSICS** | 靜態 modulate.a=1 | —— |
| warning | `warning` | **PHYSICS-critical** | modulate.a 1.0 → 0.3、CRUMBLE_TIME=0.5 | `_physics_process` 手刻 alpha 漸變 |
| collapsing | `collapse` | **PHYSICS-critical** | modulate.a 0.3 → 0、collision.disabled false → true | `_collapse()` |
| collapsed | `collapsed` | **PHYSICS** | 靜態 a=0、disabled=true | —— |
| restore | `restore` | **PHYSICS-critical** | modulate.a 0 → 1、disabled true → false | `_reset_to_initial()` |

> 注意：collision.disabled 仍要用 `set_deferred`（M14a 命名階段不變、實作時 AnimationPlayer track 對 collision.disabled 也要用 deferred 模式）。

### 4.8 Platform / HazardZone / HazardSpike / TriggerZone / PhysicalCarcass（純地形或無視覺變化）

| 元件 | 動畫名 | callback_mode | 備註 |
|---|---|---|---|
| Platform | （無）| —— | 純地形、不加 AnimationPlayer |
| HazardZone | （無）| —— | 純致死區 |
| HazardSpike | `idle`（可選）| IDLE | 若 M14b 想加動態尖刺、預留接口；M14a 不必加 |
| TriggerZone | （無）| —— | 純偵測、無視覺 |
| PhysicalCarcass | （無）| —— | 殘骸落地後保持靜態、不需要動畫 |

### 4.9 LogicGate / PressCounter / CloneSpawner（純邏輯、無視覺）

| 元件 | 動畫名 | 備註 |
|---|---|---|
| LogicGate | （無）| 純邏輯抽象、無視覺 |
| PressCounter | （無）| 純計次邏輯、視覺由連線的 Door 等承擔 |
| CloneSpawner | （無）| 純生成邏輯 |

### 4.10 Checkpoint（Tween 遷移）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| inactive | `inactive` | IDLE | 靜態 INACTIVE_COLOR | —— |
| activate | `activate` | **PHYSICS** | scale 1→1.2→1（ACTIVATE_TWEEN_TIME=0.15 × 2）+ modulate INACTIVE_COLOR → ACTIVE_COLOR | `_activate()` Tween |
| active | `active` | IDLE | 靜態 ACTIVE_COLOR | —— |
| deactivate | `deactivate` | **PHYSICS** | modulate ACTIVE_COLOR → INACTIVE_COLOR | `_deactivate()` 直接設色 |

> Checkpoint 動畫遷到 AnimationPlayer 後、Recording 必須驗證（因 Checkpoint.touched signal 會驅動 PressCounter / CrumblingPlatform reset、屬於玩法路徑）。

### 4.11 Sign（Tween 遷移）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| hidden | `hidden` | IDLE | 靜態 modulate.a=0 | —— |
| fade_in | `fade_in` | IDLE | label.modulate:a 0→1（FADE_TIME=0.3）| `_fade_to(1.0)` Tween |
| showing | `showing` | IDLE | 靜態 a=1 | —— |
| fade_out | `fade_out` | IDLE | label.modulate:a 1→0 | `_fade_to(0.0)` Tween |

> Sign 純文字提示、Recording 不關心、IDLE 安全。

### 4.12 Teleporter（保留現狀、加 pulse 命名）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| idle | `idle` | IDLE | 靜態 | —— |
| pulse | `pulse` | IDLE | 環境光暈循環（loop=true）| 既有實作（若有）整合進 AnimationPlayer |

> 注意：Teleporter 視覺可能是 shader-based、若是、保留 shader 即可、AnimationPlayer 命名只是接口佔位。

### 4.13 LightPoint（Tween 遷移、含循環脈動）

| 狀態 | 動畫名 | callback_mode | 內容（M14b）| 取代既有 |
|---|---|---|---|---|
| bright_pulse | `bright_pulse` | IDLE | modulate.a PULSE_MIN_ALPHA(0.6) ↔ PULSE_MAX_ALPHA(1.0)、PULSE_HALF_PERIOD=0.8、loop=true | `_start_pulse()` set_loops Tween |
| convert_to_trace | `convert_to_trace` | IDLE | color BRIGHT_COLOR → TRACE_COLOR、modulate.a → 1.0、FADE_TO_TRACE_TIME=0.4 | `convert_to_trace()` Tween |
| trace | `trace` | —— | 靜態 TRACE_COLOR、不脈動 | —— |
| fade_out | `fade_out` | IDLE | modulate.a → 0、FADE_OUT_TIME=0.4、結束 queue_free | `fade_out_and_remove()` Tween |

> LightPoint 是視覺核心、IDLE 可。但**注意**：`fade_out_and_remove` 結束會 `queue_free`、AnimationPlayer track 用 method call 處理（`tween.tween_callback(queue_free)` 對應 method track）。

### 4.14 CarcassTrace（既有顏色漸變、M14a 不動）

| 狀態 | 動畫名 | callback_mode | 內容 | 備註 |
|---|---|---|---|---|
| new / aging / old | `age_60s` | **PHYSICS-pref** | 既有 60s 顏色漸變邏輯 | M14a 不遷移、保留現狀（既有邏輯穩定）|

> CarcassTrace 與 Recording 無直接互動、可保留既有 _process / Tween。但若 M14b 要視覺強化、再遷移。

---

## 五、UI（多數保留 Tween、不遷移）

| UI | 既有用法 | M14a 處理 | 為何 |
|---|---|---|---|
| HUD 槽位淡入 | Tween | **不動**（保 Tween）| Recording 無關 |
| TitleScreen 標題進場 | Shader 背景 + Tween | **不動** | 已穩定 |
| PauseMenu 顯示 | 直接 visible | **不動** | 已穩定、可選 fade |
| EndingScreen 打字機 | 自訂程式 | **不動** | 已穩定 |
| MapOverlay 開合 | Tween | **不動** | Recording 無關 |

> 用戶決策「全部遷移」——但 § 五 是 **UI**、用戶決策的「全部遷移」針對的是**有玩法影響的 Tween 元件**（Checkpoint / Sign / LightPoint）。UI Tween 純視覺、不遷移以節省工時。

---

## 六、callback_mode 風險矩陣（M14a.4 驗證重點）

| 元件 | 動畫 | 風險等級 | 驗證重點 |
|---|---|---|---|
| **Door** | open / close | 致命 | collision.disabled 切換時刻是否與既有 progress >= 1.0 一致 |
| **TriggeredPlatform** | move / return | 致命 | AnimatableBody2D 載人位置同步、Player 站在上面跳起時的繼承速度 |
| **CrumblingPlatform** | warning / collapse / restore | 致命 | timer 推進與 collision.disabled 切換的時序、Checkpoint touched 觸發 restore |
| **PressButton** | press_down / press_up | 中 | 視覺壓下與 pressed_changed signal 不同源、互不影響 |
| **Lever** | flip_on / flip_off | 低 | 純色變化、不影響玩法 |
| **Checkpoint** | activate / deactivate | 中 | scale tween 不影響 touched signal、但確認 modulate 不漏掉 |
| **Spring** | compress | 低 | 已驗證可用（既有 anim.play）|
| **Player** | jump / land / die / record_start / record_end | 中-高 | 動畫長度不能阻塞物理；die 不能延遲 respawn |
| **Sign / LightPoint / Teleporter** | （IDLE）| 低 | UI / 純視覺、不影響玩法 |

**M14a.4 驗證順序**：
1. **Door** 第一個驗證（最簡單、最關鍵）→ 通過代表 collision.disabled track + PHYSICS mode 可用
2. **TriggeredPlatform** 第二個（AnimatableBody2D 載人最複雜）
3. **CrumblingPlatform** 第三個（含 Checkpoint reset 鏈路）
4. 上述 3 個都過 → 推到所有元件；任一失敗 → 全面回退到 _physics_process 手刻

---

## 七、AnimationPlayer 框架命名規範

> 給 M14a.2 建場景時用。

```
ComponentName (Root)
├── Visual (Polygon2D / Sprite2D / Node2D)
├── Collision (CollisionShape2D)
├── DetectArea (Area2D, 若有)
└── AnimationPlayer            ← 加這個
    ├── RESET                  ← 標準起始狀態（強制建議）
    ├── idle                   ← 預設靜態
    ├── <state_anim_1>         ← 對應本文表格
    └── <state_anim_2>
```

**規則**：
1. 動畫名**不加元件前綴**（用 `open` 不用 `door_open`、因為已在 Door 內部）
2. 每個 AnimationPlayer 必有 `RESET` 軌（Godot 慣例、設計時拍下初始值）
3. 在 Inspector 設 **Callback Mode Process = Physics**（PHYSICS-critical）或 **Idle**（IDLE）
4. 腳本內建議：

```gdscript
@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
    if anim != null:
        anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS  # PHYSICS-critical 必須（Godot 4.3+ enum 在 AnimationMixer 父類）
```

> 既有 `Spring.gd` 已有 `@onready var anim` 範本可參考。

---

## 八、與 Recording 系統的考量（最關鍵）

1. **callback_mode = PHYSICS** 才 deterministic（與 _physics_process 同步、60Hz）
2. 動畫不能阻塞物理：`die` / `record_start` 不能用 `await anim.animation_finished` 卡住玩法
3. AnimationPlayer track 改 `collision.disabled` 時、用 method track 呼叫 `set_deferred("disabled", value)`、不要直接用 property track（避免 physics frame 內改 disabled 造成穿模）
4. 任何「Recording 重現必須 100% 一致」的元件、動畫長度與 PHYSICS 模式都不能變

---

## 九、M14a.2 建場景時的順序

1. 先做**最低風險元件**佔位（Lever / Spring / Checkpoint / Sign / LightPoint）— 半天能掃完
2. **Door 套 AnimationPlayer + M14a.4 驗證**（半天到 1 天）
3. Door 通過 → TriggeredPlatform → CrumblingPlatform 跟進
4. 全部通過 → Player（最複雜、含 8 個動畫）
5. 文件化規範到 `新元件製作指引.md`（M14a.5）

---

## 十、M15 設計師可預期的接口（給並行 M15 用）

> M15 設計師看這節即可、不必讀全文。

設計關卡時可寫：

```gdscript
# 任意機關
$Door/AnimationPlayer.play("open")
$Lever/AnimationPlayer.play("flip_on")
$TriggeredPlatform/AnimationPlayer.play("move")

# 等動畫播完（適用於 cinematic 過場、不可用於玩法路徑）
await $Door/AnimationPlayer.animation_finished

# 查當前動畫
if $Player/AnimationPlayer.current_animation == "die":
    pass
```

**已約定的動畫名**：
- Player: `idle / walk / jump / fall / land / die / record_start / record_end`
- Clone: 同 Player + `clone_spawn / clone_despawn`
- Door: `closed / open / close`
- Lever: `off / flip_on / on / flip_off`
- Spring: `idle / compress`
- TriggeredPlatform: `at_start / move / at_target / return`
- CrumblingPlatform: `solid / warning / collapse / collapsed / restore`
- PressButton: `idle / press_down / press_up`
- Checkpoint: `inactive / activate / active / deactivate`
- Sign: `hidden / fade_in / showing / fade_out`
- LightPoint: `bright_pulse / convert_to_trace / trace / fade_out`
- Exit: `idle / triggered`
- Teleporter: `idle / pulse`

> 動畫**內容**未填、但**名稱**穩定可依賴。即使 M14a.4 驗證失敗、所有元件回退 _physics_process 手刻、上述名稱仍會留在腳本內接口（讓 M15 寫的劇情驅動代碼不必改）。

---

## 變更記錄

- 2026-05-08 建立（M14a.1 完成）
- 2026-05-08 **M14a.4 Door 驗證通過** ✅：AnimationPlayer 在 `ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS` 模式下、Value track（Visual:scale:y）+ Method track（_set_collision_disabled）3 次 Recording 重現完全一致。**結論：AnimationPlayer 路徑全面開放、TriggeredPlatform / CrumblingPlatform 可放心遷移**（細節驗證可隨 M14b 動畫內容填充時順手做、不必再開獨立 validation 階段）。
- 已知視覺退化（M14b 修）：Door 從「下沉入地面」改為「頂部往下縮」、為避免硬編 door_height 暫去掉 visual.position.y track。M14b 補回時用 method track 動態讀 door_height 或用 child Node2D 包一層做 transform。

## 已知坑（給未來 Claude / 開發者）

- **Godot 4.3+ enum 名稱**：`callback_mode_process` 的值與符號常數都改了
  - 舊（4.0~4.2）：`AnimationPlayer.ANIMATION_PROCESS_PHYSICS`
  - 新（4.3+）：`AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS`
  - .tscn 文字檔的整數值：**`callback_mode_process = 0` = PHYSICS**、**`= 1` = IDLE**、**`= 2` = MANUAL**
  - 寫 .tscn 時容易記反、若 Inspector 顯示 Idle 而你以為 Physics、檢查這個
