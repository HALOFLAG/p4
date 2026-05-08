# Light Layer 命名規範（M14a.3）

> **產出於 2026-05-08（M14a.3）**
> 對應 [`M14a + M15 階段詳細說明.md`](M14a%20+%20M15%20階段詳細說明.md) § M14a 第 3 點「Light slot / layer 系統」。
>
> **本文只定 layer 名、bit、用途**——M14a 階段「鋪電線、不裝燈」、不調 Color / energy / range 等實際數值（M14b 才調）。

---

## 一、背景

### 1.1 為什麼分層

[`光暗系統設計分析.md`](光暗系統設計分析.md) 規劃了三個整合層次（L1 純美術 → L2 暗室機制 → L3 機關語言）。**L2 暗室機制需要「能單獨關掉某類光源」**——例如「進入暗室時關掉 ambient（環境光）但保留 mechanism（按鈕指示燈）」。

如果光照不分層、未來實作暗室時就要逐個物件改 `light.enabled = false`、難以維護且容易遺漏。**先在 M14a.3 把 layer 框架定好、未來只動 layer 不動物件**。

### 1.2 M14a 階段定位

| 項目 | M14a.3（現在）| M14b（之後）|
|---|---|---|
| Layer 名稱 / bit 編號 / 用途 | ✓ 定下來 | 不再變動 |
| 元件屬於哪個 layer | ✓ 定下來 | 不再變動 |
| Light2D 節點實際加上去 | ✗（只留接口） | ✓ M14b 才加 |
| Color / energy / range 數值 | ✗（不調） | ✓ M14b 才調 |
| 暗室機制（關 ambient） | ✗（留 hook） | ✓ L2 階段才實作 |

**核心原則**：**鋪電線、不裝燈**。這份文件就是「電線配置圖」、未來 M14b / L2 / L3 來「裝燈」時照表操課。

### 1.3 與既有資產相容

- 既有 LightPoint 用 Polygon2D + Tween 模擬光暈、**M14a 不動**（保留現狀）。M14b 若要強化、再加 PointLight2D 進 `ritual` layer。
- CanvasModulate 目前**沒設**（場景全亮）、屬於 `ambient` layer 的未來實作項。
- Player / Clone 目前**沒有 Light2D**、屬於 `character` layer 的未來實作項。

---

## 二、四個 Layer 定義

### 2.1 速覽表

| Layer | bit | light_mask | canvas_layer | 用途 | 強度基調 | 色相基調 |
|---|---|---|---|---|---|---|
| `ambient` | 1 | `1` (0b0001) | -1（背景）| 環境光 / CanvasModulate | 弱（壓低整場）| 冷藍 / 冷紫（餘響靜謐感）|
| `mechanism` | 2 | `2` (0b0010) | 0（預設） | 機關指示燈 | 中（夠明顯）| 暖白 / 黃綠（依機關 active 色）|
| `character` | 3 | `4` (0b0100) | 0（預設）| 角色光暈 | 弱-中（醒目但不刺眼）| 玩家偏白 / Clone 偏藍 |
| `ritual` | 4 | `8` (0b1000) | 1（前景偏上） | 儀式 / LightPoint | 中-強（敘事焦點）| 紅光（錄製中）/ 暖橘（光點）|

> **bit 編號 = 1, 2, 4, 8 是設計原則決定**（power of 2、可位元組合）。Godot 的 `Light2D.range_item_cull_mask` 與 `LightOccluder2D.occluder_light_mask` 就是用 bitmask 表示「這顆光照亮哪些 layer / 這個 occluder 擋住哪些 layer」。

### 2.2 `ambient` — 環境光（Layer 1）

| 項目 | 值 |
|---|---|
| **bit / mask** | `1`（0b0001）|
| **canvas_layer** | -1（CanvasModulate 不需 CanvasLayer、由 Room 直接持有；本欄位僅標示「在 Z-order 概念上屬於底層」）|
| **強度基調** | 弱（壓暗整場、保留可視性、最低 ≥ 0.10 避免全黑）|
| **色相基調** | 冷藍 / 冷紫（如 `Color(0.3, 0.3, 0.4)`、餘響「靜謐 / 詩意」基調）|

**用途**：
- 全場染色、營造區域氛圍（過去 / 現在 / 終局 用不同色）
- 暗室機制的主要操作對象（L2 階段：「關掉 ambient」= 把 CanvasModulate 設成深暗 `Color(0.15, 0.15, 0.2)`）
- 與 [Room.area_color](../godot/scripts/Room.gd) 整合（每 Room 自帶 `area_color`、未來餵給 CanvasModulate）

**屬於本 layer 的元件**：
| 元件 | 節點 | 備註 |
|---|---|---|
| Room | `CanvasModulate`（每 Room 一個）| M14b 加；用 `area_color` 餵色 |
| ColorRect 全螢幕罩（暗室用）| `ColorRect`（覆蓋整螢幕）| L2 才實作；不算光源、但屬「環境視覺」 |

**Light2D 設定**（未來 M14b 加 PointLight2D 進 ambient 時參考）：
- `range_item_cull_mask = 1`
- 其餘 layer 的 PointLight2D 把 mask 留**不含 1** 的值、避免被 CanvasModulate 反算

> CanvasModulate 不是 Light2D、沒有 light_mask；但語意上它是 ambient layer 的代表元件。

### 2.3 `mechanism` — 機關光（Layer 2）

| 項目 | 值 |
|---|---|
| **bit / mask** | `2`（0b0010）|
| **canvas_layer** | 0（預設、與機關本體同層）|
| **強度基調** | 中（夠醒目讓玩家分辨「啟用 / 待機」、不刺眼）|
| **色相基調** | 機關 idle = 冷灰 / 偏暗；機關 active = 暖白 / 黃綠（沿用元件既有 `color_on` / `color_off`）|

**用途**：
- 機關狀態的視覺反饋（按鈕被踩亮起、Lever 翻過去亮起、Spring 觸發瞬間閃光）
- 暗室時**保持發光**（L2 設計原則：機關必須在暗室中可見、否則玩家盲解謎）

**屬於本 layer 的元件**（依 [動畫狀態 Mapping Spec.md](動畫狀態%20Mapping%20Spec.md) § 4）：
| 元件 | 預計光照狀態 | 對應動畫 | 備註 |
|---|---|---|---|
| PressButton | 踩下時亮 | `press_down` / `press_up` | 配合 visual.modulate |
| Lever | `on` 狀態亮 | `flip_on` / `flip_off` | 顏色已有 `color_on` / `color_off` |
| Spring | 壓縮瞬間閃 | `compress` | one-shot 短暫亮 |
| Door | open 狀態邊緣微光（指示「現在可通過」）| `open` | 可選、M14b 評估 |
| TriggeredPlatform | 移動中發光（警示「正在動」）| `move` / `return` | 可選 |
| CrumblingPlatform | warning 階段閃紅 | `warning` | 與既有 modulate.a 漸變並行 |
| Checkpoint | active 狀態亮 | `active` | 既有 ACTIVE_COLOR 已強調、加 PointLight2D 強化 |
| Exit | triggered 時閃 | `triggered` | 通關慶祝 |

**Light2D 設定**（未來 M14b 加時）：
- `PointLight2D.range_item_cull_mask = 2`
- 半徑建議 80-150 px（機關尺寸）
- energy 0.5-1.0（不蓋過 ritual）

### 2.4 `character` — 角色光（Layer 3）

| 項目 | 值 |
|---|---|
| **bit / mask** | `4`（0b0100）|
| **canvas_layer** | 0（預設）|
| **強度基調** | 弱-中（角色定位指引、暗室裡的「最小可視範圍」）|
| **色相基調** | Player = 暖白 / 微金；Clone = 偏藍 / 偏紫（區分過去）|

**用途**：
- 玩家在暗室裡的自帶可視範圍（依 [光暗系統設計分析.md](光暗系統設計分析.md) § 七：玩家身上自帶弱光、≥3 公尺）
- 分身與玩家的視覺區分（Clone 偏冷色、強化「過去」感）
- Clone spawn / despawn 的光暈淡入淡出（與 `clone_spawn` / `clone_despawn` 動畫聯動）

**屬於本 layer 的元件**：
| 元件 | 預計光照狀態 | 對應動畫 | 備註 |
|---|---|---|---|
| Player | 持續發光（暖白）| `idle` / `walk` 等所有狀態 | 死亡時隨 `die` 淡出 |
| Clone | 持續發光（偏藍）| 同 Player + `clone_spawn` / `clone_despawn` | spawn / despawn 時 alpha 漸變 |

**Light2D 設定**（未來 M14b 加時）：
- `PointLight2D.range_item_cull_mask = 4`
- 半徑：Player 200 px、Clone 300 px（依分析文件 § 4.4 起點值）
- energy 0.7-1.0
- 色相：Player `Color(1.0, 0.95, 0.85)`、Clone `Color(0.7, 0.85, 1.0)`（暫定、M14b 調）

### 2.5 `ritual` — 儀式光（Layer 4）

| 項目 | 值 |
|---|---|
| **bit / mask** | `8`（0b1000）|
| **canvas_layer** | 1（前景偏上、確保儀式光不被機關遮擋）|
| **強度基調** | 中-強（敘事焦點、玩家視覺引導）|
| **色相基調** | 錄製中 = 紅光 / 偏粉；LightPoint BRIGHT = 暖橘；TRACE = 偏冷灰 |

**用途**：
- 錄製生命週期的視覺標記（red ritual aura）
- LightPoint 的 BRIGHT / TRACE 視覺
- Teleporter 的脈動光暈（敘事提示「這是傳送門」）

**屬於本 layer 的元件**（依 mapping spec § 4.13、§ 4.12、Player record_start/record_end）：
| 元件 | 預計光照狀態 | 對應動畫 | 備註 |
|---|---|---|---|
| LightPoint | BRIGHT 脈動 / TRACE 靜態 / fade_out | `bright_pulse` / `convert_to_trace` / `trace` / `fade_out` | M14b 加 PointLight2D、原 Tween 保留 |
| Player（錄製中）| 紅光暈 | `record_start` / `record_end` | 凍結期間維持、解凍淡出 |
| Teleporter | 持續脈動 | `pulse` | 既有 shader 整合 |

**Light2D 設定**（未來 M14b 加時）：
- `PointLight2D.range_item_cull_mask = 8`
- LightPoint 半徑 250 px（依分析文件 § 4.4）
- 錄製紅光 energy 1.0、Teleporter 0.6（敘事不蓋過玩法）

---

## 三、與 Godot Light2D 系統的對應

### 3.1 三件套：CanvasModulate + Light2D + Occluder

依 [`Godot 工具與技巧分析.md`](../docs_tool/Godot%20工具與技巧分析.md) § 3.2 / § 3.3：

```
Room (Node2D)
├── CanvasModulate（ambient layer 載體、用 area_color 餵色）
├── Walls / Platforms
│   └── LightOccluder2D + OccluderPolygon2D（擋光、依 occluder_light_mask 決定擋哪幾 layer）
├── PressButton
│   └── PointLight2D（mechanism layer、range_item_cull_mask = 2）
├── Player（外層 Scene）
│   └── PointLight2D（character layer、range_item_cull_mask = 4）
└── LightPoint
    └── PointLight2D（ritual layer、range_item_cull_mask = 8）
```

### 3.2 light_mask 設定原則

| 屬性 | 在哪個節點 | 怎麼設 |
|---|---|---|
| `range_item_cull_mask` | `Light2D`（PointLight2D / DirectionalLight2D） | 設成本 layer 的 bit 值（1 / 2 / 4 / 8） |
| `light_mask` | 被照亮的 `CanvasItem`（Polygon2D / Sprite2D） | 通常設 `1`（接受 ambient 染色）；若不想被某 layer 照亮、把對應 bit 移除 |
| `occluder_light_mask` | `LightOccluder2D` | 設成「要擋住哪幾 layer 的光」、通常 `1 \| 2 \| 4 \| 8 = 15`（全擋） |

> 若有「我希望這顆光照亮所有東西」就把 `range_item_cull_mask` 設成 `15`（0b1111）；但**這不是本規範的預設**——本規範要求每 layer 的光只照亮自己 layer。

### 3.3 canvas_layer 的選擇

> **canvas_layer 只在「需要 UI 與遊戲世界分離」時用**——對 Light2D 本身意義不大。本欄位主要用來指示「Z-order 概念上該屬於哪層」、實作時通常用節點順序而非 CanvasLayer。

實務建議：
- `ambient`（CanvasModulate）：直接掛 Room 根、不必 CanvasLayer
- `mechanism` / `character`：與機關 / 角色本體同層、不必 CanvasLayer
- `ritual`：若需要「儀式光在所有東西之上」、可考慮獨立 CanvasLayer（Layer 1）；M14a 階段不必先做。

---

## 四、暗室機制接口（v1.0 不做、留 Hook）

> **本節是 L2 暗室機制的接口設計**——M14a.3 不實作、只描述未來怎麼 hook。

### 4.1 設計目標

未來進入暗室時、能用**一行程式碼**控制某 layer 的開關：

```gdscript
# 進入暗室：關掉環境光、保留機關 / 角色 / 儀式
LightController.set_layer_enabled("ambient", false)

# 離開暗室：恢復環境光
LightController.set_layer_enabled("ambient", true)
```

### 4.2 兩種實作方向（建議方向、不實作）

#### 方向 A：Autoload `LightController`（建議優先）

新增 Autoload `LightController.gd`、提供 API：

```gdscript
# scripts/LightController.gd（M14b / L2 才實作）
extends Node

const LAYER_BITS := {
    "ambient": 1,
    "mechanism": 2,
    "character": 4,
    "ritual": 8,
}

func set_layer_enabled(layer_name: String, enabled: bool) -> void:
    # 遍歷場景樹、找所有 Light2D、依 range_item_cull_mask 判斷是否屬於本 layer
    # enabled=false 時 .enabled = false（或調 energy = 0）
    pass

func set_layer_energy(layer_name: String, energy: float) -> void:
    # 漸變改 energy（暗室淡入淡出用）
    pass
```

**優點**：
- 全域可呼叫、不必抓 Room 引用
- 與既有 Autoload 風格一致（AudioManager / RecordingService）

**缺點**：
- 遍歷整場景樹找 Light2D 的成本（小型專案無感、注意 cache）

#### 方向 B：Group `light_<layer_name>`

每個 Light2D 加進對應 group：

```gdscript
# 在每個 PointLight2D 的 _ready
add_to_group("light_ambient")  # 或 mechanism / character / ritual
```

進暗室時：

```gdscript
get_tree().call_group("light_ambient", "set_enabled", false)
```

**優點**：
- 不必 Autoload、更輕量
- 可直接用 Godot group 機制

**缺點**：
- 每個 Light2D 都要記得加 group（人為失誤風險）
- 沒有「漸變改 energy」這類進階功能

### 4.3 建議

**先走方向 A（Autoload LightController）**：

1. 與 P4 既有 Autoload 風格一致（AudioManager / RecordingService / RoomManager）
2. 未來可擴展：除了 enabled 還可做漸變、color tint、temporary override（如閃光彈效果）
3. M14b / L2 階段才實作骨架；M14a.3 階段**只在本文件留接口設計、不寫 .gd**

> **TBD**（給用戶決定）：是否現在加 LightController Autoload **空骨架**（只有 LAYER_BITS const、沒有實作）、還是完全等 M14b？空骨架的好處是 M15 設計關卡時可寫 `LightController.LAYER_BITS["mechanism"]`。

---

## 五、新增元件時的 SOP

> 給「未來新增機關 / 場景元件」時的決策流程。並進 [`新元件製作指引.md`](../docs_tool/新元件製作指引.md)。

### 5.1 決策流程

```
新元件需要發光嗎？
├── 否 → 不加 PointLight2D、不必管 layer
└── 是
    ├── 是「環境染色 / 全場氛圍」 → ambient（layer 1）
    ├── 是「機關狀態反饋（按鈕、Lever、平台）」 → mechanism（layer 2）
    ├── 是「角色（玩家 / 分身）自帶」 → character（layer 3）
    └── 是「敘事 / 儀式 / 光點 / 傳送門」 → ritual（layer 4）
```

### 5.2 加 PointLight2D 的標準流程

```
NewComponent (Root)
├── Visual (Polygon2D)
├── Collision (CollisionShape2D)
├── AnimationPlayer
└── PointLight2D                     ← 新增
    ├── range_item_cull_mask = <對應 bit>
    ├── enabled = true
    ├── energy = <依 layer 強度基調>
    ├── color = <依 layer 色相基調>
    └── texture = <Godot 預設 light gradient、不必畫>
```

**M14a.3 階段**：**不必加 PointLight2D**——只記住「這個元件屬於哪個 layer」。等 M14b 加時、再依本文 § 二填上 mask / energy / color。

### 5.3 預設值參考表（給 M14b 用）

| Layer | range_item_cull_mask | energy | 色相起點 | 半徑（px）|
|---|---|---|---|---|
| ambient | 1 | 0.3-0.5 | `Color(0.3, 0.3, 0.4)` | N/A（CanvasModulate 不適用） |
| mechanism | 2 | 0.5-1.0 | `Color(0.9, 0.9, 0.7)` | 80-150 |
| character | 4 | 0.7-1.0 | Player 暖白 / Clone 冷藍 | 200-300 |
| ritual | 8 | 0.8-1.5 | 暖橘 / 紅光 | 200-300 |

---

## 六、與 Recording 系統的相容性備註

依 [動畫狀態 Mapping Spec.md](動畫狀態%20Mapping%20Spec.md) § 八：

| 確認項 | 結論 |
|---|---|
| Light2D 影響 deterministic 嗎？ | **否**——Light2D 純視覺渲染、不參與物理 |
| PointLight2D 動畫（modulate / energy 漸變）callback_mode 要 PHYSICS 嗎？ | **不必**——可 IDLE。光不影響玩法、不必跟物理 frame 同步 |
| LightPoint 既有 Tween 要遷 AnimationPlayer 嗎？ | M14a 不遷（既有穩定）。M14b 評估時可遷、但 callback_mode 維持 IDLE |
| 暗室機制（關 ambient）會破 deterministic 嗎？ | **否**——只改視覺、Recording 重現時光照狀態可能不同但軌跡一致 |
| 遊戲存檔需要記錄光照狀態嗎？ | **否**（v1.0）——光照狀態由 Room / Area 決定、不必序列化 |

**核心原則**：**光屬於視覺層、不屬於玩法層**。錄一段 → 重現時即使光照不同（如玩家錄完進入暗室）、軌跡仍一致。

---

## 七、變更記錄

- 2026-05-08 建立（M14a.3 完成）
- 待補：M14b 階段實作後、回填「實際使用的 energy / color / 半徑數值」
- 待補：L2 暗室機制實作後、回填「LightController 實際 API 與用法範例」
