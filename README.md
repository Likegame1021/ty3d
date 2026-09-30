# 河南农村童年冒险

当前项目设计基线：用户提供的《河南农村童年冒险》统一设计档案 v1，归档于 2026-09-27。

## 在新电脑上运行

克隆仓库后，使用 Godot 4.7.2 打开 `game/project.godot`；首次打开会自动导入资源。也可以将环境变量 `GODOT_EXE` 指向本机 Godot 可执行文件，再运行下方的 `.cmd` 启动入口。

游戏所需模型、贴图和声音均包含在仓库中，运行游戏不需要 Meshy API 密钥。Godot 缓存、本机凭据、临时日志、Blender 自动备份和含临时签名下载链接的 Meshy 响应不纳入版本控制；美术源文件、请求参数及制作记录保留。

## 玉米枪专项试玩

双击 **`Start-Corn-Gun.cmd`**，直接进入田边试枪场：鼠标瞄准，按住左键连射，右键蓄力后松开散射。按 F 切换木靶、三波清怪和稻草人挑战，R 回木靶。

玉米枪已包含双手握持、后坐、枪口闪光、玉米粒弹道、命中碎粒与数字、蓄力提示和声音。原完整关卡中的玉米枪也使用这套射击与反馈。

- [玉米枪操作与制作范围](docs/play-corn-gun.md)
- [玉米枪验证记录](docs/qa/corn-gun-results.md)

## 当前试玩：完整玉米地首版（M2）

双击 **`Start-Full-Scene.cmd`**：从入口出发，经过水渠、高密玉米区与农具棚，挑战荒田稻草人，在战斗中组合玉米枪。F6 切换晴/雨/雪，Tab 切换昼夜。

- [完整场景操作与路线说明](docs/play-full.md)
- [晴雨雪实机画面对照](docs/qa/full-scene-gallery.html)
- [原参考、Meshy资产与实机美术对照](docs/qa/art-review.html)
- [完整场景规格](docs/full-scene-spec.md)与[执行计划](docs/full-scene-plan.md)
- [QA 结果与验证边界](docs/qa/full-scene-results.md)

这是完整五区玩法和场景的首版。农具棚、板车、树干已接入真实 Meshy 模型（缺失树冠由 Blender 补建）；主角新增五段 Meshy 库动作。仍含程序化道具与敌人外形，整体美术尚未达到概念图完成度；正式美术精修、真人首次游玩时长和难度校准见验收记录。

## 入口的小冒险（M1保留）

双击 `Start-Adventure.cmd`：发现小鸡、找回弹珠铁盒、绕开或击退田鼠、带着铁盒到出口。见[入口试玩说明](docs/play-entry.md)和[制作规格](docs/entry-milestone-spec.md)。

## 首个验证样件（M0保留）

Windows 本机启动入口：双击 `Start-Validation.cmd`。工程位于 `game/`，使用本机 Godot 4.7.2；首次启动会导入资源。

- [试玩说明与操作](docs/play-validation.md)
- [团队职责与样件范围](docs/first-playable-spec.md)
- [执行计划](docs/first-playable-plan.md)
- [QA 实测记录](docs/qa/first-playable-results.md)

## 设计与制作资料

- [统一设计档案 v1](docs/design-baseline-v1.md)：美术方向、主角、动画、玉米地关卡、资产与制作流程。
- [参考图索引](docs/reference-index.md)：10 张原始附件的用途、对应关系与使用边界。
- `docs/references/`：原始参考图的项目内副本。
- [Meshy API 本地接入](docs/meshy-api.md)：本机加密凭据的使用方法与余额验证命令。
- [资产制作流程 v1.1](docs/asset-pipeline-v1.1.md)：Windows 优先的出图 → Meshy → Blender → Godot 工序、动画与验收规范。
- [美术风格检查基线](docs/art-style-check.md)：参考图、生成模型和实际俯视场景的统一检查要求。
- [M2真实Meshy任务与积分记录](art/environment/meshy/production-ledger.md)：本轮三件静态模型及五段库动作的可追溯交付。
- [资产需求与验收卡模板](docs/templates/asset-card.md)：记录参考图、生成任务、母版、交付件与验收结果。

最新文字设定优先于参考图中的旧设定。完整设计档案描述长期目标；本轮实际交付范围与验证结果以上方样件文档为准。

## 新对话接续用语

> 请先阅读本项目的 `docs/design-baseline-v1.md`、`docs/reference-index.md` 与 `docs/asset-pipeline-v1.1.md`，将其作为《河南农村童年冒险》的设计与制作上下文。按需查看 `docs/references/` 中的参考图。目标为 Windows 电脑优先。保留已确定方向，区分暂定内容与待补素材，不把参考图中未确认的元素直接加入正式范围。然后继续处理我本次提出的具体任务。
