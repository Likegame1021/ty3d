# 首个样件试玩

这是 Windows 本机验证样件，目标是确认角色资产流程、基本操作和玉米地表达。正式关卡的水渠、追逐、Boss 与玉米枪不在此轮范围。

## 启动

在项目根目录双击 `Start-Validation.cmd`。启动器会用本机已安装的 Godot 4.7.2，先导入资源再打开游戏。首次导入稍慢。当前交付是可运行工程，不是独立发行安装包。

用编辑器打开：在 PowerShell 执行 `./tools/Start-Validation.ps1 -Editor`。若移动了 Godot，设置环境变量 `GODOT_EXE` 为新的可执行文件路径。

## 操作

| 按键 | 功能 |
| --- | --- |
| WASD / 方向键 | 按屏幕方向移动 |
| Shift | 按住奔跑 |
| 鼠标左键 / 空格 | 挥树枝 |
| E | 靠近练习桩时交互 |
| Tab | 切换午后 / 月色 |
| R | 重置位置和命中计数 |
| Esc | 暂停 / 继续 |

建议沿中央土路走到稻草练习桩，靠近并面向它挥枝；再走进玉米边缘观察局部扰动，切换夜晚检查可读性。玉米深处的移动波纹是机制演示，尚未实现敌人 AI。

## 生产文件

- 主角参考图：`art/characters/boy/references/v001/`。
- Meshy 原始模型、绑定和动作结果：`art/characters/boy/meshy/v001/`。
- 最新 Blender 角色母版：`art/characters/boy/blender/boy-rigged-v003.blend`（修复法线与非金属材质）。
- Godot 角色交付：`game/assets/characters/boy/boy.glb`。
- 环境 Blender 母版：`art/environment/`。
- 可运行工程：`game/project.godot`。
- 分工和交接标准：`docs/first-playable-spec.md`。
- QA 记录：`docs/qa/first-playable-results.md`。

修改 Blender 母版后重新导出 GLB，再从启动器启动以重新导入。游戏逻辑与导入模型分开保存，因此重新导出角色不会覆盖操作脚本。

## 重复验证

在本机正常 PowerShell 会话执行 `./tools/verify-sample.ps1 -Render`，完成资源导入、攻击/角色/场景/输入/环境检查、启动检查和实际渲染。日志保存在 `docs/qa/logs/`，游戏截图保存在 `game/tests/`。若 Godot 安装位置不同，用 `-Godot` 传入对应控制台可执行文件。

本轮最终九项检查全部通过。键盘/鼠标功能使用 Godot 输入事件进行自动回归；Computer Use 的窗口复验曾被用户按 Esc 停止；随后用户明确反馈已自行测试窗口按键，结果没有问题，该项按用户实测通过记录。儿童握拳、长期跑动时的脚滑和玉米提示的主观可读性需要继续试玩打磨。玉米近景像素差异脚本保存在 `tools/qa/verify_corn_disturbance.gd`，本轮未执行。

