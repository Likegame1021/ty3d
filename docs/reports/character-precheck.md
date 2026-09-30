# 主角绑定前结构预检 v001

日期：2026-09-27。检查来源：`art/characters/boy/meshy/v001/model.glb`。使用Blender5.2.2后台实际导入、统计与渲染；没有修改该原始GLB、没有重拓扑、没有回传Meshy、没有写正式游戏角色路径。

## 建议

**静态结构可进入自动绑定验证，建议沿用原Meshy任务并设height_meters=1.2。此次没有发现必须先修整/回传的明显障碍。** 这只代表静态预检通过，不代表肩膀、肘膝、脚滑或握持动作已验收。

## 实测结构

| 项目 | 结果 |
| --- | --- |
| 网格 / 材质 | 1个 Mesh_0、1个 Material_0，没有骨架 |
| 顶点 / 三角面 | 导入网格31752顶点、20600三角面；glTF拆UV/法线顶点增加顶点数 |
| 贴图 | 3张打包2048×2048图片，含normal，预览材质正常 |
| Blender包围尺寸 | X1.51105、Y0.54598、Z1.90021米 |
| 对象变换 | 位置0、旋转0、缩放1 |
| 原点 / 脚底 | 原点位于身体中部；脚底约Z=-0.95185，并非脚底原点 |
| 朝向 | Blender正面-Y，符合常规GLB角色+Z前方转换；前向预览已查看 |
| 原始连通统计 | 5833个拆顶点连通片，不应解释为5833个漂浮物 |
| 临时焊接分析 | 只在未保存的临时BMesh中按0.00001米合并重合坐标：10087顶点、1个连通体、无独立漂浮几何体；原网格未焊接 |
| 孤立顶点 | 0 |

当前1.90021米原始尺寸不是目标儿童身高；绑定设置1.2米后还需检查实际输出高度、脚底偏移和动画位移。不要为了改原点或高度单独破坏已绑定网格/骨架变换。

## 目视结果与边界

已查看实际生成的全身偏正面三分之四预览：T-Pose双臂与身体明显分离，腋下不是封死状态；双腿分离，脚部完整；没有看到严重悬空物、大面积穿插或缺肢。头发、围巾、包体与背带轮廓完整。

手指属于简化较扁的掌部，不能以本预览证明抓树枝能自然握紧；需要实际右手骨骼和握持动画。包与背带靠近主体，临时焊接分析为整体连通，自动权重可能把局部拉扯到胯腿；肩袖也需要举臂和极限姿态复验。这些列为绑定后检查点，目前不据此强制重拓扑。

这次没有进行变形测试或生成骨架，因此没有声称关节拓扑/蒙皮权重已经合格。若绑定后出现肩膀塌陷、手指无法满足握持或背包跟腿拉扯，再决定局部权重修复或返回绑定前结构修整。

## 交付与复现

- 未绑定母版：`art/characters/boy/blender/boy-unrigged-v001.blend`，保存原导入变换及材质，渲染用灯光与摄像机未写回母版。
- 实际渲染预览：`art/characters/boy/blender/boy-unrigged-v001-preview.png`，1100×1100，EEVEE，中性背景。
- 原始统计：同目录`precheck-data.json`；临时焊接分析：`welded-analysis.json`；后台日志：`precheck-log.txt`。
- 工具：`tools/characters/inspect_unrigged.py`；另有只读母版/临时内存分析工具`check_components.py`。

```powershell
& 'D:/blender.exe' --background --factory-startup --python 'G:/Game/vallage/tools/characters/inspect_unrigged.py'
& 'D:/blender.exe' --background --factory-startup --python 'G:/Game/vallage/tools/characters/check_components.py'
```

Blender导入、母版保存、渲染和统计均实际完成。日志存在Blender自带笔刷资源相对路径警告以及退出清理提示，不影响已保存角色母版与PNG；没有把这些警告写成“完全无警告”。
