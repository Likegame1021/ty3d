# 首个可运行样件独立代码审查

审查日期：2026-09-27。审查对象是当前文件，不基于 Git diff。读取了首样件规格与计划、主程序、HUD、环境脚本与 shader、启动器；未访问 `.local/`、凭据或外部 API，未修改实现文件。

## 必须修复

### P1：攻击计时截断真实 GLB 的攻击动作

- 位置：`game/scripts/player.gd:223-224`；相关位置 `player.gd:202-205`、`player.gd:234-238`、`game/scripts/attack_state.gd:10`。
- 当前 `attack_branch` 动画长度为 **1.5416666666666667 秒**，由交付 `boy.glb` 的动画 sampler 输入 accessor 上界直接读得。播放器以 `speed_scale = 1.0` 播放，但攻击状态固定持续 **0.48 秒**，之后无条件切回待机或走跑。
- 复现：在静止状态按一次 Space，观察完整挥枝动作；约 0.48 秒时切回待机，最多播放片段前约 31%，后续挥击和收招被截断。固定的 0.10–0.30 秒命中窗也没有与本段动画建立对应关系。
- 修复要求：统一攻击状态持续时间和实际动画播放时长；可按导入片段长度设定攻击状态，或明确调整片段播放速度。依据完整动作校准命中窗，并确认下一次攻击可以完整重播。应通过实际动画位置/播放状态和真实输入补充回归。

## 细节建议（不作为本轮运行阻塞）

### P3：出生点附近硬质装饰物没有碰撞

- 位置：`game/environment/cornfield.gd:156-165`；木箱布局见 `177-178`。
- `_prop()` 只实例化资源；木箱 GLB 的节点只有 mesh/name，导入配置未增加碰撞。因此 `(3.2, 0, 8.5)` 木箱等硬质道具会被角色穿过。地面、练习桩、边界已经满足当前最低碰撞验证；若将这些道具用于展示环境碰撞，应为木箱、罐子、树干等加简化静态碰撞。
- 证据为代码、GLB 节点与导入配置的静态核对；未另建穿透测试脚本。

### P3：命中截图脚本未驱动真实攻击动画

- 位置：`game/tests/render_sample.gd:31-33`。
- 脚本直接执行 `attack.begin()`、`attack.tick()`、`check_hits()`，没有经过玩家正常输入分支中的 `play_animation("attack_branch")`。该截图能证明目标命中反馈，不能证明角色挥枝动作正确。
- 最终角色验收应通过 Space/左键真实输入捕获攻击过程中画面，并覆盖后半段动作。

## 已执行的独立核对

使用已安装 Godot 4.7.2 console，以 `--headless --path G:/Game/vallage/game --script ...` 运行以下现有脚本：

| 脚本 | 结果 |
| --- | --- |
| `environment/check_environment.gd` | 退出 0；42 分块、1326 株、出生点/路线/目标地面、昼夜和暂停验证通过 |
| `tests/test_game.gd` | 退出 0；`Playable integration: 0 failures` |
| `tests/test_input.gd` | 退出 0；`Input pipeline: 0 failures`，含 E、Space、Esc、按钮恢复、R、Tab、W/D/Shift 输入 |

`tools/Start-Validation.ps1 -CheckOnly` 退出 0，正确找到本机 Godot、工程目录和已到位的角色文件。未发现启动器自身阻止本机使用的确定缺陷。

以上运行输出存在沙箱引起的 `user://logs` 无法创建以及系统证书读取失败消息；未观察到 GDScript 解析或运行错误。角色运行时成功映射 `idle`、`walk`、`run`、`attack_branch`。本次代码审查不替代角色比例、手部握枝和昼夜实际画面的最终验收。

## 整改复验（主代理，2026-09-27）

P1攻击截断已修复：按Godot实际片段1.5417秒完整播放；真实手骨采样校准命中窗0.59～0.63秒。test_character验证旧0.48秒之后仍在播放、完整收招后回待机，最终日志0 failures。

两项P3建议也已处理：木箱/陶罐/草垛/树干加入简化碰撞；render_sample通过InputEventKey Space触发完整攻击并等待命中后截图。另修复继续按钮点击泄漏成攻击，输入回归已覆盖。

最终v003非金属角色材质、4xMSAA及全部当前运行文件已通过docs/qa/logs/summary.json所列九项检查；运行文件SHA256见verified-files.json。Computer Use实际窗口按键复验因用户按Esc停止而未完成，不属于自动输入测试通过的证据范围。

用户补充验收：用户随后明确反馈“窗口按键复验 我测试过了没问题”。窗口操作据此记录为用户实测通过；该反馈与自动输入/GPU验证分开注明来源。
