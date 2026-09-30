# M2 完整玉米地 QA 清单

规格：`docs/full-scene-spec.md`。本表核对功能原型与证据范围；状态只代表表中列出的测试/截图，不代表真人试玩或正式美术验收。

状态值：未执行、待最终复验、部分通过、通过、失败、阻塞。

## 自动流程与状态边界

| ID | 验收点 | 通过条件 | 状态 | 证据 |
|---|---|---|---|---|
| A1 | 导入、启动与日志 | 默认完整场景导入并启动，退出码为 0，无脚本/资源错误或泄漏。 | 通过 | 最终 `summary.json`：import、full-smoke、源码一致性均 PASS；对应日志在 `docs/qa/full-evidence/` |
| A2 | 五区完整路线 | 实际输入事件驱动角色从入口按顺序走到Boss并获胜；测试脚本不直接传送玩家或修改血量/进度。 | 通过（自动输入） | 最终同版 `docs/qa/full-evidence/full-input-playthrough.log`：56.135秒、2心、胜利，0 failures；游戏翻栏交互本身以坐标越栏并播放动画实现 |
| A3 | 水渠关卡边界 | 闭闸时西岸、东岸和桥口实体碰撞阻止绕行；开闸后玩家能实体通过。 | 通过 | 最终 `docs/qa/full-evidence/full-canal-barrier.log`；定点修正复验 `final_z=14.2999`，保留 `<17.0` 通路阈值，0 failures，另记于 `docs/qa/full-canal-barrier-qa.log` |
| A4 | 乱序与重复交互 | 不可跳过必需前置、重复领取或重复结算。 | 通过（状态/场景测试） | `test_full_progress.log`、`test_full_playable.log`、`test_full_input.log`；不等同于人工穷举所有输入次序 |
| A5 | 玉米怪追逐与绕行 | 实体追逐、石头引怪、实体矮栏翻越、脱战返回均有测试覆盖；无需攻击巡游怪即可通过高密区。 | 通过（自动测试） | `test_full_combat.log`、`test_full_route.log`、真实输入路线日志及区域截图；Boss战仍需攻击 |
| A6 | 板车与发射器前置 | 木板、板车和棚内发射器按顺序取得；实体障碍阻挡未完成路线。 | 通过 | `test_full_route.log`、独立真实输入路线日志、`full-env-farm.png`/`full-env-farm-inside.png` |
| A7 | Boss攻击模式 | 扫击、钻地移动预警/冲出、召唤小怪及近战命中窗口工作。 | 通过（自动状态/战斗测试） | `test_full_combat.log`、`full-boss-burrow.png`、`full-input-playthrough-v004-final.log`；未以真人躲避体验代替机制断言 |
| A8 | 半血玉米枪组合 | 半血散落、现场E组合、可见武器、普通射击和蓄力多目标散射命中。 | 通过（自动输入/战斗测试） | `test_full_weapon.log`、`test_full_character_actions.log`、真实输入Boss路线日志；枪和散射见 `full-corn-gun.png`、`full-corn-scatter.png` |
| A9 | 胜败、重试、暂停 | 胜败结束、危险冻结、暂停及UI输入路由、R/按钮重试重置。 | 通过（自动输入测试） | `test_full_playable.log`、`test_full_input.log`、960胜败截图；不表示手工逐按钮体验 |
| A10 | M0/M1 回归 | 旧入口保持可测，核心自动回归无失败。 | 通过 | 最终 `summary.json` 的5项M1、4项M0回归及日志 |

## 天气和场景视觉（真实 GPU）

| ID | 验收点 | 通过条件 | 状态 | 证据 |
|---|---|---|---|---|
| V1 | 五区地标与路线 | 入口、水渠、高密区、农具区、圆形Boss场可区分，路线连续。 | 通过（截图检查） | `game/tests/full-env-{entrance,canal,dense,farm,boss}.png`、`docs/qa/art-review.html` |
| V2 | 天气×昼夜矩阵 | sunny/rain/snow 六种天气与日夜组合实际渲染；Tab/F6独立、暂停天气可选。 | 通过（GPU截图+输入测试） | `full-env-{sunny,rain,snow}-{day,night}.png`、`test_full_input.log` |
| V3 | 雨雪地表反馈 | 雨丝/湿地、雪花/积雪及照明变化可见；状态重置与暂停受自动测试。 | 通过（截图和自动状态） | `full-env-farm-rain.png`、`full-env-farm-snow.png`、六态截图、`full_field_check.log`、`test_full_input.log` |
| V4 | HUD遮挡与可读性 | 关键界面在检查分辨率内未裁切，雨雪下仍可读。 | 部分通过 | `test_full_hud.log`、`full-victory-960.png`、`full-failure-960.png`；截图有限，不是多显示器/真人可读性测试 |
| V5 | 天气性能/渲染器兼容 | Compatibility 渲染器真实GPU生成六态；短采样和退出检查无错误。 | 部分通过 | 最终 `summary.json`、GPU截图及 `full-weather-evidence.json`；每态仅入口约45帧采样，`mean_wall_frame_ms`不代表全关卡帧率或性能承诺 |
| V6 | 五区互动视觉反馈 | 水渠状态、倒伏/扰动玉米、移动板车、Boss散落及枪状态有可检查画面。 | 通过（截图检查） | `full-env-canal-cleared.png`、`full-env-canal-open.png`、`full-dense-pursuit.png`、`full-cart-moved.png`、`full-corn-spilled.png`、`full-corn-gun.png` |

## 真人试玩校准（不可由自动测试替代）

| ID | 验收点 | 通过条件 | 状态 | 证据 |
|---|---|---|---|---|
| P1 | 首次完整路线时长 | 未看过路线者自然完成五区，验证20–30分钟节奏。 | 未执行 | 自动路线约56.51秒，是熟悉路线的测试输入，不能代表首次体验 |
| P2 | 线索/天气/战斗理解 | 玩家理解线索、水渠、可绕行敌人、Boss预警与武器组合。 | 未执行 | 尚无观察记录或玩家反馈 |
| P3 | 音频与长期体验 | 实际设备试听并评估音量、提示辨识度及长时间舒适度。 | 未执行 | 无主观试听/长时间体验记录 |

## 判定说明

- 最终统一正常用户验证结束后，以 `docs/qa/full-evidence/summary.json` 的完整步骤结果作为导入、脚本、回归、图像捕获和源码一致性结论；运行中状态不可视为最终通过。
- 独立水渠测试首轮失败是QA行走帧数不足：未按跑步，仅走100帧，未走到原断言阈值。修正仅将开桥行走增至180帧并记录实际终点；`<17.0` 实体通路断言保持不变。修正后的定点复验 0 failures。旧失败不得与最终修正结果混写。
- 自动输入路线、状态夹具、GPU截图和像素/天气采样不能代替真人首次游玩。M2 是可运行技术样件，不是完整的20–30分钟体验验收。
- Meshy棚屋、板车和树干已落地，树冠由Blender补建；玉米、地面、小道具与敌人仍偏程序化原型。画面方向温暖卡通且与style-v002大体协调，但材质层次和地表/植被完成度低于参考；详见 `docs/qa/art-review.html` 和 `docs/reports/meshy-static-assets.md`。
