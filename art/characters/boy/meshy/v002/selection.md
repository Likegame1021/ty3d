# M2 动作库选择

2026-09-28，使用 Meshy API 重新查询 animation-library.json；沿用主角已成功绑定的同一 rig，不重复绑骨。

| 游戏用途 | Meshy action_id / 名称 | Blender 检查与调整目标 |
|---|---|---|
| hurt | 178 / Hit Reaction | 保持轻受击，剪短恢复，保持脚底与身体尺度 |
| pick_up | 276 / Male Bend Over Pick Up | 儿童手臂触地幅度，拾取物位置与动画时点 |
| interact | 285 / Open Door | 作为伸手拨动闸门/组合道具的基础动作，裁掉不需要的行走段 |
| push | 260 / Push Forward and Stop | 缩短推行距离，配合板车让路方向 |
| vault | 428 / Unarmed Vault | 检查矮栏高度和落脚，游戏控制水平位移 |

五项按官方动作库名称初选，最终导入后通过 Blender 实际姿态采样和游戏检查决定剪裁/播放时长；不把库名称视为动作已经适合儿童比例的证明。保留原始 GLB、原 v003 母版与现有四个动作。官方接口支持同 rig 批量动作：[Meshy animation API](https://docs.meshy.ai/en/api/animation)。
