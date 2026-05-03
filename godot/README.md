# M0 — 走跳手感原型

對應實作計畫 [`v2-md-md-crystalline-turing.md`](../../../../Users/halof/.claude/plans/v2-md-md-crystalline-turing.md) 的 M0 階段。

## 怎麼開

1. 開啟 Godot：`F:\CCTEST\TOOL\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64.exe`
2. 在啟動畫面點 **Import**
3. 選擇 `f:/CCTEST/haloflag ai trpg/P4/godot/project.godot`
4. 點 **Import & Edit**
5. 編輯器開啟後，按右上角 ▶（Play）或 F5

第一次按 Play 時，Godot 會問「要設哪個場景為主場景？」
→ 選 `scenes/Main.tscn`（其實 `project.godot` 已經設好，應該不會問，但保險起見）

## 操作

| 按鍵 | 動作 |
|---|---|
| A / ← | 向左走 |
| D / → | 向右走 |
| Space / W / ↑ | 跳 |
| **LMB / R** | **記下動作**（按一次開始、再按結束；最長 30 秒） |
| **RMB / E** | **重現過去**（同時召喚所有段的「過去的你」） |
| **Q** | 站在光點上：抹去該段過去 |
| LMB / R（站在光點上） | 重做該段過去 |

> 完整實作計畫見 [`../實作計畫.md`](../實作計畫.md)

## 你應該感覺到的東西

跑一次 5 分鐘，依序試：

1. **走路** — 加速與減速感是否舒服？瞬間到滿速會「太靈」、太慢會「太黏」。
2. **跳躍高度可控** — 短按一下跳一點點，按住跳得高。這就是 variable jump height。
3. **Coyote time** — 走出平台邊緣的瞬間（離地）按跳，應該還跳得起來。沒有 coyote time 會很挫折。
4. **Jump buffer** — 還在空中下墜時提早按跳，落地的瞬間應該自動跳起來。沒有 buffer 會感覺「跳鍵失靈」。
5. **空中控制** — 跳到一半左右切換方向，反應應該流暢但有一點重量感。

## 怎麼調手感

打開 [`scripts/Player.gd`](scripts/Player.gd)，最上面那一塊「走跳手感調校區」的所有 `const` 都可以改。

**新手調校建議順序：**

1. 先調 `MAX_SPEED` — 跑起來覺得舒服的速度
2. 再調 `JUMP_VELOCITY`（負值，越負跳越高）+ `GRAVITY`，讓跳躍弧線好看
3. 然後調 `ACCEL` 與 `GROUND_DECEL` — 加速感
4. 最後調 `COYOTE_TIME` 與 `JUMP_BUFFER` — 通常 0.08~0.12 之間最舒服

**改完不用重啟編輯器，按 Stop 再 Play 即可。**

## 驗收標準

對應計畫 M0 的目標：

- [ ] 自己玩 5 分鐘不會煩躁
- [ ] 跳躍高度可控（短按小跳 / 長按大跳）
- [ ] 從平台邊緣跑出去剛好按跳，跳得起來
- [ ] 空中按跳，落地立刻跳

四項都覺得舒服 → 進入 M1（錄製系統）。
任何一項彆扭 → 回去調參數，不要硬往下做。

## 場景配置

`Main.tscn` 是這樣：

```
       ┌─ HighPlatform (高)
       │
       ├─ MidPlatform (中)
       │
       ├─ LowPlatform (低)
       │
玩家───┴───────────────  ← 地板
```

設計用意：你可以從低平台跳到中平台、中平台跳到高平台，測試不同跳躍距離與高度的手感。

## 如果跑不起來

- **「無法載入場景」**：檢查專案是不是真的 import 進去了（編輯器左下「FileSystem」面板要看得到 `scenes/`、`scripts/`）
- **角色穿過地板**：通常是 `_physics_process` 寫成 `_process`，檢查 [`Player.gd`](scripts/Player.gd) 第 31 行
- **角色完全不動**：檢查專案設定的「Input Map」有沒有 `move_left`、`move_right`、`jump`、`reset` 這四個 action（`project.godot` 裡已經寫好了，正常會自動載入）
- 任何錯誤把 Output 面板的紅字截圖／貼給我
