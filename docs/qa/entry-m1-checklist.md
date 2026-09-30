# M1 入口教学区 QA 清单

最终验收：`tools/verify-entry.ps1 -Render`，15/15 步通过，退出码 0。自动测试、静态环境检查、GPU渲染和用户试玩分开判定；“通过”只表示对应证据范围通过。

## 自动行为与回归

| ID | 用例 | 状态 | 证据 |
|---|---|---|---|
| A1 | 导入并启动 M1 入口，无脚本/资源错误 | 通过 | `docs/qa/entry-evidence/summary.json`、`import.log`、`entry-smoke.log` |
| A2 | 真输入完整路线：发现鸡、沿线索拾取铁盒、到出口；重复拾取不重复计数 | 通过 | `test_entry_route.log`、`test_entry.log` |
| A3 | 未拾取时出口不胜利；携带铁盒后可完成 | 通过 | `test_entry.log` |
| A4 | 不攻击、无受伤绕过田鼠完成路线；敌人追击/脱战返回边界 | 通过 | `test_entry_route.log`、`test_entry_enemy.log` |
| A5 | 一次攻击最多命中一次；独立攻击可再次命中；重复拾取受保护 | 通过 | `test_entry.log`、`test_entry_enemy.log` |
| A6 | 三格体力、攻击/无敌时序、失败状态 | 通过 | `test_entry_enemy.log`、`test_entry_progress.log` |
| A7 | 胜利、失败后重试及 R 重置状态 | 通过 | `test_entry.log`、`test_entry_input.log` |
| A8 | 暂停冻结；继续按钮不触发攻击；Tab 昼夜输入路由 | 通过 | `test_entry_input.log` |
| A9 | 故事源与阶段环境接口；玉米受风/鸡/鼠/玩家位置影响 | 通过（环境与像素证据） | `entry-environment.log`、`entry-visual-diff.log`、`docs/qa/entry-visual/summary.csv` |
| A10 | M0 攻击、角色、场景、输入、环境回归 | 通过 | summary 中全部五项 M0 检查 |

## 必须查看的图像与渲染

| ID | 检查 | 状态 | 证据/边界 |
|---|---|---|---|
| V1 | 入口、鸡和铁盒线索可辨认 | 通过（截图检查） | `game/tests/entry-entrance.png`、`entry-chicken.png`、`entry-box.png`；鸡图已隐藏早期田鼠标签。 |
| V2 | 田鼠危险/绕行与攻击反馈可读 | 部分通过 | `entry-danger.png`、`entry-complete-bypass.png` 与自动敌人用例通过；未进行人工持续试玩，整体可读性和手感仍待玩家验证。 |
| V3 | 胜利/失败/重试面板及小窗口布局 | 通过（截图检查） | `entry-complete-960.png`、`entry-failure-960.png`；同时有 1280×800胜败图。截图显示面板无明显溢出。 |
| V4 | 风摆和故事来源引起可见像素变化 | 通过（受控 GPU 对照） | 四组 before/after 图及 CSV；wind、chicken、creature、player 四项均 `passed=true`。后续真实 GPU 音频播放/释放复核无泄漏；真人主观听感未执行。 |
| V5 | 正式角色和动作回归 | 通过（自动回归） | `m0-test_character.log`，summary 中通过；不等同于人工审美评价。 |

## 用户试玩校准

| ID | 检查 | 状态 | 说明 |
|---|---|---|---|
| P1 | 未看过路线的新玩家首次完成时间约 3–5 分钟，理解线索与绕行 | 未执行 | 自动已知路线 13.78 秒仅为自动化路线数据，不作为首次游玩时长。 |
| P2 | 人工操作手感、提示可读性及声音听感 | 未执行 | 尚无真实玩家试玩/聆听记录。 |

## 证据规则

- 整套最终日志和summary保存在 `docs/qa/entry-evidence/`；渲染像素对照保存在 `docs/qa/entry-visual/`。
- 自动断言证明受测状态与输入路由；截图证明所示画面；两者均不替代首次试玩与主观听感。
