# M1入口教学区：主程序交接

日期：2026-09-28。程序责任文件已实现并完成自身验证。最终正常用户账户下统一import、实际渲染与发布由主代理负责；关卡环境和声音由技术美术负责。

## 玩家流程

新增`game/levels/entry.tscn`及`entry.gd`：正式GLB主角从(0,0,12)出发，靠近(-3.8,0,7)移动的小鸡后自动识别它无害；左侧小路通往(-5.5,0,1)铁盒，E只能拾取一次；北路田鼠(-1.8,0,-6)可绕开或以树枝两次独立挥击击退；持盒在(0,0,-13)附近按E完成。空手出口明确说明缺盒，未观察小鸡时铁盒不能绕过教学步骤直接拾取。小鸡没有攻击组、受伤或奖励刷取接口。

田鼠是简模，有可见橙色警戒环及“要扑了”字幕，靠近后0.72秒前摇，再进行一次短扑击，之后有1.10秒喘息。短追逐限4.5秒、出生方向界限与家周围5.3m区域；玩家可跑开脱战，鼠怪返回巡逻。受树枝攻击后眩晕、位移击退，两次不同挥击使其退走；没有血腥，不要求击退才能通关。体力三格，受伤后1.25秒无敌防连续扣格。三次分隔伤害触发失败，完成或失败冻结危险和游戏时间。

Esc暂停及继续、R重试和暂停/胜负按钮重试均将任务、小鸡、铁盒、田鼠、血量、动作、时间、昼夜、环境源与临时界面反馈复原。胜负界面清除之前的即时消息和受伤闪屏，按钮点击不漏进攻击。M1仅把共享主角出生点和攻击目标组做参数化、玩家碰撞掩码设层1|4；M0默认出生点/组/层不变，`main.tscn`仍作为独立技术验证。M1正交镜头size13.5；中文HUD仅呈现目标、体力、时间、操作与当前情境，不显示资产技术状态。

## 环境与声音接口

实际载入`res://environment/entry_field.gd`，每帧传入角色位置；真实鸡/鼠坐标及鼠是否仍活跃传给`set_story_sources`，阶段变化用`set_story_stage`，重试用`reset_story`，昼夜用`set_night`。没有在程序侧复制玉米地、光照或出口模型。AudioListener3D放在玩家身上Y0.7m，朝向随固定相机，避免Camera高空斜俯视导致TA的12m空间提示音听不到。没有把所有声音放大成全场可听。TA提供的声音为程序合成WAV，音频设备不可用时玩法判定仍独立成立。

## 测试与证据

关键逻辑先观察失败再实现：任务阶段/一次拾取/受伤无敌/完成冻结13项失败；鼠怪追逐/前摇/脱战/击退8项失败。结果界面的旧提示和闪屏清理又观察到2项失败后修复。最新以下八个行为脚本逐一退出码0且`0 failures`：

- M0：`test_attack.gd`、`test_game.gd`、`test_input.gd`、`test_character.gd`。
- M1：`test_entry_progress.gd`、`test_entry_enemy.gd`、`test_entry.gd`、`test_entry_input.gd`。

M1集成检查涵盖真实环境API及玩家四动作载入、鸡自动发现和无害性、E拾取与重复阻断、缺盒出口、完整无战斗胜利、敌人单挥单次命中及两次击退、受伤无敌与三格失败、胜负/暂停冻结、R和按钮重试，包含失败重试后敌人的眩晕/位移/可见状态清理。输入测试使用Godot `Input.parse_input_event`经过Viewport/GUI/未处理输入路径，实际检查暂停时E不能拾取、Esc、Tab、R、胜负/暂停按钮及按钮点击不误触挥枝。它是引擎注入，不冒充用户实体键盘试玩。

`test_entry_route.gd`另在真实入口环境中只用Input移动角色碰撞体，不传送玩家：出生→鸡→铁盒→回中央路→东侧绕鼠→出口。`entry-route-evidence.json`记录七个实到点，鼠状态包括`patrol/chase/return`，结局`won`、体力3/3、鼠被攻击0次，**实际游戏计时13.78秒**，检查退出码0。这是机器人知道目标的优化路径，不能宣称首次玩家已达到3～5分钟；目标时长留给真实首次试玩校准，不靠强制等待凑时长。

`render_entry.gd`在真实OpenGL Compatibility下保存入口、小鸡、铁盒、田鼠前摇、无战斗完成、胜利重试、失败、失败重试、960×600、夜间图，共输出`ENTRY_GPU_CAPTURE_OK`并退出0。图在`game/tests/entry-*.png`；已目视入口、侧路铁盒、警戒环、结果界面、缩放和夜间。渲染脚本中的角色位置设置只为快速获取各场景证据，真实全路线可达性由上述物理移动测试单独证明。

## 最后定点收尾

小鸡阶段的远处田鼠字幕已隐藏，田鼠形体和环境声仍在真实位置。进入田鼠遭遇阶段后字幕出现；若田鼠在追逐、前摇、扑击或眩晕中近身，也会显示危险信息。`test_entry.gd`先观察到新断言2项失败，修复后退出码0、`Entry playable: 0 failures`。最新`entry-chicken.png`已目视确认没有提前显示田鼠标签。

渲染脚本新增`entry-complete-960.png`与`entry-failure-960.png`，在实际胜负状态下按960×600窗口捕获并检查菜单矩形未越界。最新脚本退出码0并输出两张`CAPTURE`及`ENTRY_GPU_CAPTURE_OK`；已目视确认两张结果菜单标题、说明和重试按钮完整、不裁切。此后玩法代码冻结，等待主代理在正常用户账户下运行最终整套验证。

## 已知边界

- 用户亲自首次游玩的3～5分钟体验时长未验证；优化自动路线仅13.78秒，地图与目标引导是否让首次玩家探索足够时间需实玩判断。
- 鸡和鼠为清楚区分无害/危险的程序简模；本阶段未生成Meshy动物资产。
- 本机sandbox中Godot日志曾报告Windows根证书不可读。技术美术已修复音频退出清理：其独立检查显示`--headless --verbose --quit-after 120`退出0且无WAV/PlaybackWAV/ObjectDB泄漏，GUI播放并`queue_free`后也无泄漏；正式正常账户日志以主代理统一验证为准。

## 复现

```powershell
$godot = 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --path 'G:/Game/vallage/game' 'res://levels/entry.tscn'
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_entry_progress.gd
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_entry_enemy.gd
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_entry.gd
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_entry_input.gd
& $godot --headless --path 'G:/Game/vallage/game' --script res://tests/test_entry_route.gd
& $godot --path 'G:/Game/vallage/game' --script res://tests/render_entry.gd
```
