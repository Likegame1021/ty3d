# M2完整场景主程序交接

日期：2026-09-28。主程序文件为 `game/levels/full.tscn`、`full.gd`、`game/scripts/full_*`、`game/ui/full_hud.gd`、`game/tests/test_full*`、`render_full.gd`。共享 `player.gd` 增加可配置世界边界和可选情境动作，默认边界仍是 M0/M1 的 `x=-13.5～13.5, z=-15.5～15.5`。完整关卡独立设置为 `x=-27.5～27.5, z=-47.5～47.5`，不覆盖旧场景。

## 可玩流程

正式主角 GLB 与四个原有动作沿用 M0/M1。出生 `(0,0.05,40)`，小鸡 `(-3.5,36)` 稳定触发无害发现，铁盒 `(-5,31)` 仅能拾取一次；水口 `(0,22)` 清堵后才可在 `(5,20)` 开闸。环境层的西岸、桥口、东岸碰撞共同封住未开闸的水渠。高密区的田鼠在 5m 左右开始短追逐，有 0.72s 前摇/扑击/收招/脱战返回；F 石子可把它引向落点，矮栏 `(-5,3)` 有实体碰撞，靠近按 E 可翻过。农具区必须先取 `(12,-9)` 木板、在 `(16,-13)` 垫轮移车，才可越过棚口实体横栏，在 `(17,-18)` 拿旧发射器。旧发射器在半血前不提供远程火力；拿到它才开放 Boss 入口。

Boss `(0,-34)` 有横扫（举杆与环形预警）、钻入外围玉米（本体隐藏、土丘实际移动、环境扰动源随实际坐标移动、目标地面预警后冲出）及召唤 2～3 只小田鼠三种循环技能。每个技能有前摇和收招，近战树枝在收招窗口造成一次伤害。召唤物也有可见扑击前摇。Boss 血量 12，半血时储粮架散落玉米，Boss 停顿 7 秒，玩家到 `(5,-33)` 按 E 将旧发射器组合为玉米枪；未拾枪前 Boss 至多降到 1 血，避免提前击败后的软锁。Q 切换树枝/枪，手上简模枪和树枝同步显隐。普通枪弹射程 9m、伤害 1；按住右键至少 0.8s 后松开，5 束可见弹道在 5.5m 锥形内对各目标至多结算一次，Boss 伤害 3。击败 Boss 进入胜利画面；五格体力用完显示失败。暂停、胜负、R 或按钮重试均复原任务、敌人、枪、天气、日夜、体力和临时反馈。

固定正交镜头跟随主角，玩家身上 Y≈0.7 的 AudioListener3D 与镜头同方向，环境 3D 鸡声/沙沙声不由高空镜头衰减。天气 `sunny/rain/snow` 通过 F6 轮换或暂停菜单按钮选择，Tab 独立切换日夜，重试恢复晴天白昼。玩法将 `mouth_cleared` 及规格六键同步给 `full_field.set_progress`；`set_actor_sources` 前三槽固定为鸡、巡游怪、Boss，无效槽送 `(1000,0,1000)`，后续槽为小怪。环境、天气、光照、渠水、地标和实体岸边屏障由 TA 模块负责。

## 主角追加动作

从同一 Meshy rig 的 `animations.glb` 取 `Hit_Reaction`、`Male_Bend_Over_Pick_Up`、`open_door`、`Push_Forward_and_Stop`、`Unarmed_Vault`，经 `tools/characters/extend_actions.py` 合并到 v003 正式主角母版，保存 `boy-rigged-v004.blend` 并重新导出 `game/assets/characters/boy/boy.glb`。五个规范片段名为 `hurt`（0.82s）、`pick_up`（1.60s）、`interact`（1.30s）、`push`（1.45s）、`vault`（0.87s）；`idle/walk/run/attack_branch` 的曲线和实际导入长度不改。合并脚本逐项对比 24 骨、网格、材质及旧四动作 SHA256，导出九个片段；校验在 `art/characters/boy/blender/actions-v004-verification.json`。

源拾取长 7.2s，前 3.6s 已完整覆盖弯腰、低手取物、基本起身，后半是冗余展示动作；将此前段裁剪并重定时至 1.6s，而不是整段四倍速。其余片段按游戏交互节奏重定时；新五动作中和水平根位移，推车/翻栏降低垂直髋位移，实际位移仍由 CharacterBody 控制。最低右手位置经 61 点姿态采样在拾取片段约 40.7% 处，预览 `pose-pick_up-v004.png` 用该帧，其余预览为 `pose-{hurt,interact,push,vault}-v004.png`。推车与翻栏是可用动作原型，手部没有手指骨，手与道具接触尚未做到逐帧精准校准。

成功拾取铁盒、木板、旧发射器、组合玉米枪时播放 `pick_up`；清水口和开闸播放 `interact`；移板车播放 `push`；翻栏播放 `vault`；受伤播放 `hurt`。短动作保持到片段结束才恢复待机/移动，攻击不能打断拾取等交互。体力受伤照常立即结算；若受伤恰在已发出的挥枝期间，先完成原有 0.59～0.63s 命中窗，再播放受伤反应，避免攻击被同帧伤害吞掉。受伤反应期间玩家可主动挥枝恢复战斗。暂停冻结剩余时间和待播受伤；失败及重试清空当前和待播动作。M0/M1 若缺新增片段仍自动只用原四动作。

## 输入

WASD/方向键移动，Shift 跑；E 交互/翻栏；F 投石引怪；空格/左键挥枝（持枪时普通射击）；半血组合后 Q 切换武器，右键按住蓄力、松开散射；Tab 昼夜，F6 天气，Esc 暂停/继续，R 重试。右键释放在 `_input` 处理，避免 GUI 吞掉释放事件导致蓄力卡住；暂停取消蓄力，UI 按钮点击不会穿透为攻击。

## 测试与证据

关键状态判定先观察到失败再实现，包括乱序/重复领取、独立关卡边界、Boss 三技能、钻地实际位移/隐藏形体、未拾枪封顶、枪模/锥形多目标、HUD 血量/蓄力、物理板车棚口与输入重试。v004 追加动作先看到交互事件 5 项失败，再接入播放；真实输入路线暴露同帧受伤吞挥枝后，新增排队反应测试先失败再修复。最终九个 M2 测试逐项 `exit 0`、`0 failures`：`test_full_progress.gd`、`test_full_player_bounds.gd`、`test_full_combat.gd`、`test_full_playable.gd`、`test_full_weapon.gd`、`test_full_hud.gd`、`test_full_route.gd`、`test_full_input.gd`、`test_full_character_actions.gd`。同时七项 M0/M1 回归（`test_attack`、`test_game`、`test_input`、`test_entry_progress`、`test_entry_enemy`、`test_entry`、`test_entry_input`）均 `exit 0`、`0 failures`，v004 日志位于 `game/tests/*-v004.log` 与 `full-character-actions-queue-green.log`。

`test_full_route.gd` 通过 `CharacterBody3D.move_and_collide` 分段移动玩家实体，从出生到鸡、铁盒、水渠、高密区、农具区、Boss 入口。它额外把玩家放到西岸/东岸闭闸探测点，分别确认西岸、东岸和桥口三处碰撞挡路，然后从桥口开闸继续实体行走。还确认矮栏中心必须翻越、板车/横栏未移时挡棚口、移后可进入、取发射器后可跨 Boss 入口。路线测试直接调用 E 对应的 `interact`，真实按键派发另由 `test_full_input.gd` 使用 `Input.parse_input_event` 检查 F6/Tab/E/Q/右键蓄力/暂停/按钮/R；这不是人工实体键盘试玩。`test_full_playable.gd` 为快速覆盖完整 Boss 胜利及失败重试而设置阶段位置，不能单独当物理可达性证据。

独立 QA 的 `tools/qa/full-input-playthrough.gd` 在 v004 后再次运行：通过真实输入事件和玩家实体移动走全程，结局 `won`、Boss 0 血、已组合玉米枪、剩 2 心、56.51s、0 failures，证据在 `game/tests/full-input-playthrough-v004-final.log`。它是熟悉路线的自动输入，不代表首次玩家用时或人工手柄验收。

`render_full.gd` 在 OpenGL Compatibility 实际 GPU 下输出 `FULL_GPU_CAPTURE_OK`、退出码 0，图在 `game/tests/full-*.png`：入口、闭/开水渠、高密区追逐、板车移位、Boss、钻地移动土丘/落点预警、半血玉米散落、枪模与散射、960×600 胜败画面。已目视菜单文字/按钮没有裁切。根另独立执行三天气×日夜 6 张画面截图与帧耗时；不把程序快速布景截图当真实通关输入录像。

## 已知边界

- M2 自动化证明机制与物理路线，尚未有真实首次玩家 20～30 分钟节奏验收；自动测试和快速截图时长不能当试玩时长。
- 田鼠、稻草人、木板和玉米枪是程序原型；主角五个追加动作已接入正式 v004 GLB，但物件与手掌接触尚未逐帧校准，翻栏时位置由玩法直接过栏，动作和实体位移还未做严格同步。静态场景 Meshy 棚、板车、树由 TA 和根另行集成。
- 本机 sandbox Godot 启动偶见 `user://logs` 和 Windows 根证书读取警告；M2 行为测试与 GPU 捕获均按退出码和脚本错误检查通过。正式正常用户账户验收由根任务统一执行。

## 复现

```powershell
$godot = 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --path 'G:/Game/vallage/game' 'res://levels/full.tscn'
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_full_playable.gd
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_full_route.gd
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_full_input.gd
& $godot --path 'G:/Game/vallage/game' --script res://tests/render_full.gd
```
