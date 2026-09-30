# 首个可运行样件 QA 结果

验收日期：2026-09-27。测试对象为集成 v003 角色 GLB 与 4×MSAA 的当前 `game/`。Godot 4.7.2 stable，Compatibility 渲染，GPU 为 RTX 3080 Ti。`docs/qa/logs/summary.json` 汇总的9项最终验证全部退出码0、errors 0。

## 自动检查

| ID | 结果 | 证据与边界 |
|---|---|---|
| A1 | 通过 | `docs/qa/logs/import.log`：Godot 完成项目扫描与资源重新导入，退出码0。 |
| A2 | 通过 | `smoke.log` 主场景运行检查、各脚本/集成测试无解析或运行时错误；summary 中9项均为 PASS/errors 0。 |
| A3 | 通过 | `character.log` 检出正式 boy GLB 与 idle/walk/run/attack_branch 四片段；正式文件经 Godot 导入。角色身高1.2m、24骨骼，右手骨 `RightHand`。 |

## 实看与操作检查

| ID | 结果 | 证据与边界 |
|---|---|---|
| V1 | 通过 | 已查看 `game/tests/playable-day.png` 等实际 GPU 渲染图。正式角色、玉米地、练习桩、HUD 均可见；v003 材质修订后的角色轮廓与场景能辨认。 |
| V2 | 部分通过 | `input.log` 与 `integration.log` 通过移动、跑步、练习桩碰撞、地图边界和固定摄像机集成检查。持续实际操控跑步的主观手感尚未验收，步速脚滑仍需试玩；不把模拟输入结果当成人工体验结论。 |
| V3 | 通过 | `character.log` 验证真实攻击片段完整播放至收招、测得前挥接触窗可命中、回摆/恢复时不命中且一次挥击只计一次；`playable-hit.png` 可见挥击、反馈与计数01。 |
| V4 | 通过 | `input.log`：E 超距离无效，进入交互范围后显示练习说明。用户另反馈真实窗口按键复验正常。 |
| V5 | 通过 | `input.log` 验证 Esc 暂停、暂停屏蔽输入、继续按钮点击路由、R 清除计数并回到出生点；暂停截图可见面板。用户反馈真实窗口按键与继续操作复验正常。 |
| V6 | 通过 | `input.log` 验证 Tab 昼夜往返；白天/夜晚 GPU 截图显示角色、路面和作物可辨认。用户反馈真实窗口按键复验正常。 |
| V7 | 部分通过 | 环境测试确认42块、1326株、地面与日夜参数正确；静帧可见玉米地。`tools/qa/verify_corn_disturbance.gd` 已准备，但因停止桌面操作未运行，风摆/玩家靠近造成的像素变化与玩法可读性未验收。 |
| V8 | 通过 | `character.log` 验证正式 GLB 的四动作映射、RightHand 树枝挂点、0.7m枝长、Walk/Run切换和松开输入回 Idle；已查看四张角色 GPU 近景截图。开放手掌未做儿童握拳，步行/跑步脚滑和持续手感仍可后续打磨。 |
| V9 | 通过 | v003 GLB 替换后重新导入并通过 `character`、`integration` 与 `render` 检查；正式模型仍从稳定路径加载，挂点、动画与玩法层保持有效。 |
| V10 | 通过 | `summary.json` 九项均 PASS、errors 0；最终运行日志无未处理脚本错误。用户另反馈真实窗口按键复验正常。 |

## 截图与限制

- 全场景截图：`game/tests/playable-day.png`、`playable-night.png`、`playable-hit.png`、`playable-pause.png`、`playable-resized.png`。
- 角色近景截图：`game/tests/character-idle.png`、`character-walk.png`、`character-run.png`、`character-attack_branch.png`。
- 960×600 与1280×800截图的 HUD 均在画面内，没有明显裁切或溢出；缩小窗口时文字变小但仍可见。
- 当前交付是技术验证样件。角色开放手掌、儿童握枝姿势和持续跑步的脚滑/步速手感可继续打磨；玉米动态差异测量与主观可读性仍未验收。

## 玉米动态验证脚本

`tools/qa/verify_corn_disturbance.gd` 对准一块玉米地，计划输出 `docs/qa/corn-wind-t0.png`、`corn-wind-t08.png` 和 `corn-player-push.png`，并统计植被区域像素差异。本轮没有运行该脚本，不存在像素差异通过结论。
