# 主程序交付报告

日期：2026-09-27。程序责任文件与正式 Meshy GLB 的程序集成已完成，已接入 TA 法线修订 v002。最初临时外形阶段记录保留在下文；最新正式角色状态见末尾补充。最终正常Windows用户上下文的统一验证和发布由主代理执行。

## 交付文件

- `game/project.godot`：Godot 4.7.2、Compatibility、1280×800、canvas_items 缩放。
- `game/main.tscn`、`game/scripts/main.gd`：环境接口接入、固定斜俯视正交跟随、输入、昼夜、交互、重置和暂停。
- `game/scripts/player.gd`：CharacterBody3D，1.2m/0.22m 胶囊，层2/掩码1；走速2.4、跑速4.6；屏幕方向移动；重力、地图限位及异常跌落恢复。
- `game/scripts/attack_state.gd`：可配置动作时长/命中时窗、每次挥动每目标仅一次、暂停冻结、重置取消。占位默认0.48s/0.10～0.30s；正式片段使用真实1.5416666s/0.59～0.63s。
- `game/scripts/practice_target.gd`：有碰撞的稻草练习桩、计数、晃动、环形反馈、稻草碎屑；重置杀掉未结束的反馈Tween。
- `game/ui/hud.gd`：中文HUD，临时/正式模型与缺动画状态、命中计数、距离提示、短消息、暂停操作提示和可点击继续按钮。
- `game/tests/`：行为回归、渲染截图脚本与证据。

所有权遵循规格：未修改环境、美术资产和凭据；仅使用环境公开的set_night与set_player_position。环境自行建立WorldEnvironment与光源，主程序不重复创建。只有环境入口不存在时才生成临时地板。

## 实际验证

先创建攻击状态的空实现与行为测试，观察4项失败：开始攻击、有效时窗命中、下一次挥动开始、下一次挥动同目标命中。实现后变为0项失败。

场景测试先观察到“可玩场景不存在”失败，随后接入可玩实现。另在重置反馈回归中发现并复现“重置后未结束环形Tween继续变化”失败，修复后通过。

最新一轮完整检查：

| 命令入口 | 结果 |
| --- | --- |
| `--headless --script res://tests/test_attack.gd` | Attack behavior: 0 failures；退出码0 |
| `--headless --script res://tests/test_game.gd` | Playable integration: 0 failures；退出码0 |
| `--headless --quit-after 120` | 主场景启动120帧；退出码0 |
| `--script res://tests/render_sample.gd` | NVIDIA RTX3080Ti/OpenGL 3.3 Compatibility真实渲染；退出码0 |

场景回归覆盖：攻击目标恰好计一次，暂停不造成新命中，暂停冻结位移与攻击计时，超距离/背对目标不能命中，重置恢复出生点和计数、取消攻击，实际输入移动，跑步速度明显快于走路，练习桩阻止穿行，脚部着地，地图边界不允许逃出，实墙阻挡交互/攻击，重置取消反馈，昼夜往返，动画根骨水平位移清除且上下和肢体动作保留。

实际图像已逐张查看：

- `game/tests/playable-day.png`
- `game/tests/playable-night.png`
- `game/tests/playable-pause.png`
- `game/tests/playable-hit.png`
- `game/tests/playable-resized.png`（960×600，HUD完整可见）

底部HUD压到约109px区域，操作说明合成一行；完整说明集中在Esc暂停界面。玉米移动扰动源在HUD明确标为验证演示。

## 正式角色接入

固定读取 `res://assets/characters/boy/boy.glb`。存在且可导入时实例化，按MeshInstance3D合并包围盒统一缩放至1.2m并贴地；自动发现AnimationPlayer，匹配idle/walk/run/attack_branch及常见别名。缺失片段在HUD列明，不静默假装动画完成。

Skeleton3D中发现RightHand、handr、Hand.R等明确右手骨骼时建立BoneAttachment3D；骨骼名写入player.bone_status用于验收。未发现时明确保存“未发现右手骨骼 · 树枝临时挂点”。正式模型的真实手部局部轴、树枝握姿、朝向及动作仍需主代理根据最终GLB实测调整。

角色动画的根骨/骨盆水平位移在运行时清除，保留Y轴运动和肢体轨迹；CharacterBody是唯一移动来源，不让Meshy动画把模型带离碰撞体。此处理有合成动画回归，正式GLB已另外执行真实骨骼与动作检查，不以合成测试替代真实GLB验收。

## 本机日志限制

本次sandbox headless日志出现Windows根证书存储不可读；GPU启动还出现Wacom配置不可读和user:// shader缓存不可写。编辑器import另报告AppData Godot配置目录不可写。这些不是游戏脚本错误，所有行为/渲染检查退出码0。建议主代理在已授权的正常Windows账户权限上下文重新执行import与最终QA，确认本机系统日志消失；没有伪称日志完全干净。

## 运行命令

PowerShell：

```powershell
$godot = 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --path 'G:/Game/vallage/game'
& $godot --headless --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/attack.log' --script res://tests/test_attack.gd
& $godot --headless --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/game.log' --script res://tests/test_game.gd
& $godot --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/render.log' --script res://tests/render_sample.gd
```

正式GLB交付后先用`--headless --editor --import`导入再运行。Windows导出、启动入口和发布由主代理负责，本轮没有生成或宣称已交付EXE。

## QA验收缺口补充（2026-09-27）

新增`game/tests/test_input.gd`，通过`Input.parse_input_event`注入物理键事件和鼠标事件，从Godot Input→Window/Viewport→未处理输入/GUI信号的真实分发路径检查，**没有直接调用游戏的输入处理方法或emit按钮pressed信号**。覆盖：远处E拒绝、近处E阅读说明、Space完整挥枝一次命中、Esc显示暂停、暂停时W/Space/R不改变位置和计数、指针点击继续按钮、R清零和回出生点、Tab昼夜往返、再次Esc暂停/恢复、W+D+Shift跑步。这是引擎输入事件验收，不冒充人工操作实体键盘证据。

Headless与真实OpenGL窗口输入测试均输出14项PASS、`Input pipeline: 0 failures`、退出码0。初次鼠标注入因headless窗口实际为64×64而GUI逻辑空间为1280×800导致测试坐标不正确；诊断得到Viewport final transform后，测试按该变换将逻辑坐标映射到物理窗口，点击正常。此问题在测试工具，不是游戏按钮实现缺陷，未因此修改产品UI。

`test_game.gd`新增一般实体墙物理验证：在中央道路生成层1的1.2×1.4×0.15m墙体，角色持续向墙跑30物理帧，实际停在墙前而不能穿过；仍保留射线阻挡检查。最新完整场景回归为0 failures、退出码0。

输入复查命令：

```powershell
& $godot --headless --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/input.log' --script res://tests/test_input.gd
& $godot --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/input-gpu.log' --script res://tests/test_input.gd
```

## 正式角色最终程序集成

TA交付v002后已重导入，并确认骨架、动作及尺寸接口不变。Godot实际发现Skeleton3D/24骨/RightHand，四个真实AnimationPlayer片段均按同名映射。实际导入attack_branch长度为**1.54166662693024s**，不是Blender源片段报告的1.5s。

原占位0.48s会截断真实动作。先新增`test_character.gd`，实际观察到6项失败（掌偏移、树枝轴向、完整时长、回摆不能早命中、0.60s有效命中、0.48s后仍在攻击），再修复并通过。程序现保留1.5416666s完整片段及收招，随后恢复idle；W与Shift输入确实分别切至真实walk/run，停止移动恢复idle。

右手实际骨轴已采样：本地+Y沿掌部/指尖方向；掌内偏移世界0.045m；树枝Cylinder沿此轴放置，真实世界长度0.7m。测试直接测量世界偏移和长度，不以骨架缩放假定替代结果。当前最终GLB经过TA归一，程序仍保留全局缩放补偿。手掌是简化开放手，没有指骨，**没有声称手指已经握紧**。

`inspect_character.gd`在真实Godot骨架上进行0.01s密集采样，数据保存`game/tests/character-hand-samples.json`。相对角色前向+Z，树枝尖在0.60s达到Z1.02546m/X-0.03421m/Y0.46416m；0.58s仍偏侧X-0.496m，0.67s已侧向收回。按实测将命中窗最终收窄至**0.59～0.63s**、攻击距离1.35m，防止后摆与收回造成提前/延迟命中。增加0.58与0.67拒绝命中回归，先看到3项失败再收窄时窗，最终通过。

另由真实事件回归发现“点击继续后自动挥枝”的产品问题：角色原先轮询Input攻击状态，GUI消费点击后全局Action状态仍在。攻击现只从Main `_unhandled_input`调用player.request_attack，GUI点击不进入攻击。先复现失败后修复；输入测试现扩到**16项PASS**，包括继续点击不攻击和GUI外左键完整一次攻击。

最终代码轮次的四套headless检查：

| 测试 | 结果 |
| --- | --- |
| `test_attack.gd` | 0 failures，退出0 |
| `test_game.gd` | 0 failures，退出0 |
| `test_input.gd` | 16项PASS，0 failures，退出0 |
| `test_character.gd` | 17项PASS，0 failures，退出0 |

截图脚本也已校正：`render_sample.gd`以真实Space输入启动游戏攻击，并等待命中，再拍实际挥击画面，不再直接设置attack.begin/tick。`render_character.gd`提供四动作的真实近距Godot预览，可检查树枝挂点。TA通知前已有近距诊断图；TA v002后完成的一轮真实输入渲染退出0。遵照主代理统一验证安排，不再重复运行截图，最终图像/正常用户日志以`tools/verify-sample.ps1 -Render`的主代理结果为准。

新增真实角色检查命令：

```powershell
& $godot --headless --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/test_character.log' --script res://tests/test_character.gd
& $godot --path 'G:/Game/vallage/game' --log-file 'G:/Game/vallage/game/tests/render-character.log' --script res://tests/render_character.gd
```
