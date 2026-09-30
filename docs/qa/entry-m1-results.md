# M1 入口教学区 QA 结果

记录日期：2026-09-28。最终正常 Windows 用户验收由 `tools/verify-entry.ps1 -Render` 执行：15/15 步通过、退出码 0，summary 中各步 `errors: 0`。`normal-user-audio-quit.log` 是修复前 06:54 的 Dummy/headless 强退历史；后续 TA 记录确认相同 headless 命令已无泄漏，Windows GUI/OpenGL 实际播放后释放场景也退出码 0 且无泄漏，详见 [entry-code-review.md](entry-code-review.md)。该结果支持技术验收通过；不代表真实新手试玩或主观音频评价完成。

## 自动验收与渲染证据

| 项目 | 结果 | 证据与范围 |
|---|---|---|
| 导入、启动及脚本/资源错误 | 通过 | `docs/qa/entry-evidence/summary.json`、`import.log`、`entry-smoke.log`；无错误，全部退出码 0。 |
| M1 行为、路线、输入、敌人和进度 | 通过 | `test_entry.log`、`test_entry_route.log`、`test_entry_input.log`、`test_entry_enemy.log`、`test_entry_progress.log`。真输入事件路线覆盖发现鸡、拾取、田鼠追击后返回、无攻击无受伤到出口；自动路线 13.78 秒。重复拾取/命中、绕行、胜败重试、暂停/继续点击不攻击、R 与 Tab 均有自动断言。 |
| M0 回归 | 通过 | summary 中 `m0-test_attack`、`m0-test_character`、`m0-test_game`、`m0-test_input`、`m0-environment` 全部通过。 |
| 场景环境与 GPU 捕获 | 通过 | `entry-environment.log` 与 `entry-render.log`；RTX 3080 Ti / OpenGL Compatibility，成功生成渲染截图。 |
| 局部玉米视觉扰动 | 通过（像素证据） | `entry-visual-diff.log` 与 `docs/qa/entry-visual/summary.csv`：wind 287288/202290、chicken 4394/2584、creature 1209/587、player 35477/23494（总差异像素/绿色玉米变化像素），四项 passed=true。四组前后对照图在 `docs/qa/entry-visual/`。这证明受控渲染状态改变了可见像素，不能单独证明玩家实玩时容易读懂线索。 |
| UI 与关键画面 | 通过（所查截图） | `game/tests/entry-chicken.png` 已不显示早期田鼠标签；`entry-complete-960.png`、`entry-failure-960.png` 的 960×600 胜败面板可见且无明显溢出。其他入口、铁盒、危险、夜间及 1280×800结果图见 `game/tests/entry-*.png`。 |
| 音频运行/退出 | 通过（技术释放） | `normal-user-audio-quit.log` 是修复前的 06:54 历史记录；后续 headless 和 Windows GUI/OpenGL 音频播放/释放复核无泄漏，详见 `docs/qa/entry-code-review.md`。主观听感与提示清晰度仍未做真人聆听评价。 |

## 尚未完成的用户验证

- **3–5 分钟首次路线目标：未执行。** 自动已知路线为 13.78 秒，不代表首次游玩耗时；需要未看过路线的玩家实际试玩并记录卡点。
- **人工可读性、操作手感和整体声音听感：未执行。** GPU 像素差异和自动输入断言不能代替实际试玩与聆听。

因此，本次结论是：M1 技术样件及自动/渲染验收通过，M0 回归通过；真实新手体验校准仍待进行。
