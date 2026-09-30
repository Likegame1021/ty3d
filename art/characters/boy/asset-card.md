# 主角 v001 生产记录

制作日期：2026-09-27。目标：首个 Windows 可运行样件，1.2m 儿童角色，固定斜俯视镜头。最终美术精修不等同于本轮技术链路验证。

## 输入与可追溯文件

- 原始设定：`docs/design-baseline-v1.md`。
- 原始角色板：`docs/references/a_large_character_design_reference_sheet_for_a_lit.png`。
- 生产图：`references/v001/front.png`、`left.png`、`back.png`、`right.png`。
- `references/v001/prompts.json` 保存图像提示词；右侧图经历一次补丁修正，草稿未参与建模。
- 模型请求记录：`meshy/v001/generation-request.json`。四视图、Meshy 7.1、20K目标三角面、2K贴图、T-Pose。

## Meshy 实际任务

| 阶段 | 任务 ID | 状态 | 实际积分 |
| --- | --- | --- | ---: |
| 多图生成 | 01a0e332-7d77-7247-8b4d-91ac16b6abca | SUCCEEDED，原始与重拓扑 GLB 已下载 | 30 |
| 绑定 | 01a0e33c-8671-74eb-8a74-4f9e81d64a6c | SUCCEEDED，绑定体和基础走跑已下载 | 5 |
| 四动画合并 | 01a0e342-fa73-75a3-a45b-48830eaa5be1 | SUCCEEDED，合并 GLB 已下载 | 12 |

合计 **47 Meshy API 积分**。余额从1305到1258，已通过余额接口复核。这不含出图服务消耗。

选择动画：Idle（0）、Casual Walk inplace（613）、Run 2（14）、Right-hand Sword Slash（219）。本轮用同一绑定体批量输出四动作，便于统一片段管理；绑定任务附带走跑保留为候选版本。

## 预检结果

静态模型：20600三角面、1网格、1材质、3张2K贴图。原始约1.9m，绑定请求设置1.2m。未进行额外重拓扑或改UV；原生成任务直接用于绑定。

绑定结果：24骨骼，Hips根骨，RightHand右手，无独立手指骨。精确握拳不在自动绑定能力内，首版按手部挂点持枝验证。Blender整理仅导出角色网格与骨架，排除导入时附带的骨架显示物。动画需去除水平根位移、保留垂直髋运动。

最终母版为 `blender/boy-rigged-v003.blend`，正式交付 `game/assets/characters/boy/boy.glb`。v002修复重复顶点造成的分裂法线，v003关闭错误金属度与自发光，骨骼与动画关键帧保持不变。Godot实际动画为idle、walk、run、attack_branch；攻击按导入后1.5417秒完整播放，命中窗0.59～0.63秒。具体动作/挂点验收见 `docs/reports/character-rigging.md` 和 `docs/qa/first-playable-results.md`。

## 已知精修项

AI模型未逐像素复现参考图的包带、补丁和手指；后续正式角色需继续统一衣物细节、检查背包随跑动的变形，并制作适合儿童持枝的手型。当前用于技术与操作验证，不视为最终人物美术定稿。

API key 不在本卡、请求参数或游戏资源中；本机加密凭据位于工程资源目录外。
