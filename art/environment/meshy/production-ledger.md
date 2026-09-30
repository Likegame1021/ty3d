# M2 Meshy 实际生产记录

2026-09-28。此前主角生成+绑骨+四动画已消耗47积分。本次按用户新指示追加三件静态模型与五段库动画，提交前余额1258，提交后余额1153，本批实际消耗105积分。余额原始响应见本目录 `balance-before-m2.json` 与 `balance-after-m2.json`。

| 任务 | ID | 实际消耗 | 原始交付 |
|---|---|---:|---|
| 农具棚单图3D | 01a0e53e-4acf-757a-bca3-c9f72bdf4cc5 | 30 | tool-shed/v001/model.glb |
| 板车单图3D | 01a0e53f-8252-7557-89a6-c5b13fba8585 | 30 | farm-cart/v001/model.glb |
| 树木单图3D | 01a0e53f-927a-72c5-8791-81e9ae74c797 | 30 | locust-tree/v001/model.glb |
| 原主角骨架新增5动画 | 01a0e53f-a5c2-75e1-8f12-e71aaa8ea25f | 15 | art/characters/boy/meshy/v002/animations/animations.glb |

模型均使用风格修订后style-v002独立参考、Meshy7.1 standard、2K材质、triangle remesh，目标面数棚12000/车6000/树8000；实际面数以Blender导出检查为准。没有重复绑骨，没有购买套餐。请求和任务完整响应存放在各版本目录；访问密钥只在本机DPAPI凭据中，不进入运行游戏。

生成成功后技术美术验收确认：树木返回缩略图严重缺冠，GLB 几何也确实缺叶，非 alpha/剔面误显。M2 样件现使用 Meshy 树干 + Blender 补充的圆润橄榄绿叶冠；原始源文件不变，修订母版与导出件见 `docs/reports/meshy-static-assets.md`。这是一件混合来源修补资产，不把有缺陷的 Meshy 原生成记为完整美术成功。棚屋与板车也经 Blender 整理并在 Godot 实机晴雨雪验收；最终树冠仍需正式美术细化。

官方接口：[单图生成3D](https://docs.meshy.ai/en/api/image-to-3d)、[动作库与动画](https://docs.meshy.ai/en/api/animation)。最终采用哪些资产、修了什么，以 `docs/reports/` 的交付记录与实机画面为准。
