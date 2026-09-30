# 正式角色整理与交接 v001

2026-09-27。输入为本轮Meshy四动画合并GLB，原始下载未改；未访问凭据或调用API。

## 实际交付

- `game/assets/characters/boy/boy.glb`：唯一正式角色交付，1个蒙皮网格、1个材质、24个骨骼、4动画。
- `art/characters/boy/blender/boy-rigged-v001.blend`：可编辑母版，保留独立NLA片段，默认静止姿势，无预览灯光/摄像机。
- `tools/characters/prepare_boy.py`：可重现整理脚本；验证数据和后台日志位于母版同目录。

静止包围高度1.20000032米，脚底Z约-0.00000027米。Blender前方-Y，GLB/Godot前方+Z。Meshy厘米级数据与Armature对象0.01缩放共同规范为米级网格、骨架数据及scale1；所有动作平移通道同时缩放，避免100倍位移。只导出角色网格与骨架，排除Blender glTF导入器骨骼显示用Icosphere。

四动画独立NLA导出，GLB JSON已核实名字：

| 名称 | 时长 | 建议运行设置 |
| --- | --- | --- |
| idle | 4.000000秒 | 循环 |
| walk | 4.1999998秒 | 循环 |
| run | 0.73333335秒 | 循环 |
| attack_branch | 1.500000秒 | 单次；程序按动作调命中窗口 |

骨架对象名BoyRig；顶层骨Hips；右手骨RightHand。其余骨：LeftUpLeg、LeftLeg、LeftFoot、LeftToeBase、RightUpLeg、RightLeg、RightFoot、RightToeBase、Spine02、Spine01、Spine、LeftShoulder、LeftArm、LeftForeArm、LeftHand、RightShoulder、RightArm、RightForeArm、neck、Head、head_end、headfront。没有独立手指骨。

右手骨本地+Y沿腕到掌/指尖方向；树枝可由主程序以此作为初始纵向基准，在掌内约0.045米位置试挂，但应以Godot实际手骨basis、视角和挥击帧复验。骨附件会随动画，不能只按静止T-Pose世界坐标固定。

## 动作与变形检查

Hips在骨架空间中的水平位置固定到静止骨位置，垂直髋部起伏保留；先采样，再完整移除原根位置通道的整数及小数帧关键帧，避免残留小数帧恢复水平漂移。五个进度采样的根水平差为浮点误差量级，数据见`rigged-validation.json`。

每动画0/25/50/75/100%检查实际变形网格包围范围，没有尺度爆炸。BlenderEEVEE实际渲染并查看待机、跑步、右手挥击：`pose-idle.png`、`pose-run.png`、`pose-attack_branch.png`。手臂和背包在这些帧没有看到大范围断裂或严重飞散；这不是全帧无穿插保证。

已知样件局限：手为简化开放掌，挥击动作来源为右手剑斩，未专门制作儿童紧握树枝手形；围巾/包带局部及衣袖变形、近距法线/平面感仍可进一步打磨。待机/步行脚底可出现厘米量级偏移，跑步存在合理腾空阶段；静止脚底0不能证明动画全时脚接地。主程序仍需在游戏里检查步速与脚滑、动作切换、手部树枝及攻击命中时机。

Godot4.7.2 headless实际导入了正式GLB；日志见`godot-import-log.txt`。没有把目录/编辑器配置沙箱写入警告说成完全无错误，原始素材/绑定/动画费用由主代理任务记录核实。

## 法线修订 v002（2026-09-27）

主代理发现v001变形预览面部/手臂/裤腿有明显三角亮斑，因此进行了单次针对性诊断与修复。

原Meshy动画GLB实际导入31941顶点，但只有10087个位置；v001交付再导入31953顶点，同样10087个位置。两者都有custom split normals，重合顶点的蒙皮权重逐组完全一致（最大差0）。只打开所有面的smooth标志无法连通已拆开的顶点，原分裂法线与sharp边仍会参与变形后的着色。

修复对v001母版用0.000001米阈值焊接同位置顶点，保留UV逐角数据与一致蒙皮权重；清除custom split normals、解除遗留sharp边，重算外向法线并平滑。没有重生成、重减面或改角色轮廓。编辑网格顶点变10087，三角面仍20600，UV角数据长度不变。glTF导出仍会按UV需要拆顶点，这是格式行为，不是修复失败。

同一挥击帧、同一灯光和镜头实际EEVEE对比：`normals-before.png`与`normals-after.png`。已查看：手臂、裤腿等的大块三角亮斑明显消失，面部连续性改善；残余高光/贴图纹理仍存在，不声称完全没有自动权重或贴图局限。

修订母版为`boy-rigged-v002.blend`，正式`game/assets/characters/boy/boy.glb`已替换为v002并通知主程序重导入。

独立比较验证：24骨名称/层级/静止矩阵完全相等；四动画每条曲线的所有关键帧值和插值类型完全相等；四动作各6进度共24个实际变形采样的世界位置集合在0.00001米精度完全一致。因此本修订改善来自法线/邻接连续性，而不是修改骨骼、动作或人物造型。验证数据`normal-repair-verification.json`，源诊断`normal-diagnosis.json`；工具`diagnose_normals.py`、`repair_normals.py`、`export_normal_revision.py`，日志在母版目录。

Godot已实际重新导入v002，原骨名、四动画名/长度、1.2米尺寸及根运动处理不变。完整游戏截图由主程序/QA重拍。v001母版和原始Meshy文件保留用于对照与回退。
