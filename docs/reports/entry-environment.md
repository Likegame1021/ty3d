# M1 入口教学区：环境 / 技术美术 / 提示音实施

2026-09-27。按`docs/entry-milestone-spec.md`实现，无新Meshy/ImageGen费用，未使用Computer Use。此报告不将独立环境检查冒充完整任务玩法或用户试玩。

## 交付与接口

`game/environment/entry_field.gd`继承已有cornfield；`set_night(bool)`、`set_player_position(Vector3)`沿用基类，新增`set_story_sources(chicken_position,creature_position,creature_active)`、`set_story_stage(0..3)`、`reset_story()`。不生成玩家、小鸡、鼠怪、铁盒或完成判定，均由入口程序管理。

入口独立材质为`entry_corn.gdshader`、`entry_soil.gdshader`。环境实际42地块、1301株，较M0移除25株用于侧路和发现口袋，复用原8份乡村模块GLB与原灯光/碰撞。

中央道路仍通出生(0,0,12)和出口(0,0,-13)；侧路从(-1.8,9.2)经鸡(-3.8,7)、铁盒(-5.5,1)回到(-1.7,-2.7)。侧路是稍浅的踩踏土色和有限清场，盒周围约0.78米口袋，不是发光物品定位点；稠密玉米仍保留遮挡。入口与分岔有旧木牌，出口(0,0,-13.7)有可通行木门架；stage2仅低强度暖色布标，不新增胜利判断。

角色附近约1米范围的玉米局部压低并推开，提高1.2米主角可辨性，不使用全田透明。实际小鸡位置驱动低幅轻颤（基准约0.09），鼠怪位置驱动较强波纹（基准约0.32），怪物禁用时强度0。M1 `_process`不调用M0的自动扰动演示，因此不会产生与当前生物无关的巡游波纹。所有动画时间由程序驱动，继承暂停模式。

## 声音

自有GDScript程序合成短鸡声/沙沙声，22.05kHz单声道16位PCM；播放用AudioStreamPlayer3D，不加载外部版权音频。`entry_chirp.wav`和`entry_rustle.wav`是独立检查导出的试听样本，产品运行时直接生成AudioStreamWAV，不依赖这两份WAV导入。

鸡提示较轻，约-15dB；鸡的轻沙沙约-23dB；鼠沙沙约-13dB。源节点跟实际生物世界位置移动，最大距离12米；仅在玩家附近触发，stage3停止声音。reset清源位置、时钟、调度和当前播放。声音为辅助，静音仍能凭晃动和通达侧路探索。

固定高位相机不宜用作唯一空间音频听点：已与主程序确认由其AudioListener3D跟随玩家位置并使用相机basis；本环境不创建重复监听器。独立无角色渲染检查未评价人耳听感，正式空间声需要集成监听器后实听。

## 验证证据

- `entry_check.gd`先验证缺失入口而失败，实施后实际通过。最终输出：`ENTRY_ENVIRONMENT_OK plots=42 corn=1301 route_samples=117 actual_sources=pause,reset,disabled audio=generated`。
- 117个路线胶囊采样（半径0.22m/高1.2m）没有碰撞阻挡，每处地面Y=0；CPU记录中没有玉米茎位于清场侧路内。
- 实际源传入位置与shader参数一致，改变位置后参数跟随；禁用怪物后强度0；暂停时风时间冻结；stage3停止声音/生物扰动；reset清源、stage和计时。声音PCM实际生成并保存样本。
- headless的Dummy渲染器返回MultiMesh实例getter零矩阵，不能可靠反查本次布局；共享cornfield仅添加`source_transforms/source_colors`轻量CPU metadata，使用同一数据建立渲染与验证。随机数、M0布局/着色/默认接口保持不变。已通知主程序。
- M0环境回归实际通过：42地块/1326株、地面/日夜/暂停检查，记录`art/environment/entry/m0-headless-log.txt`。
- RTX3080Ti、OpenGL3.3、Compatibility实际渲染三张PNG并查看：`entry_preview_day.png`、`entry_preview_night.png`、`entry_preview_sidepath.png`。侧路在日夜下可辨，镜头边缘不出现蓝色虚空；没有角色/HUD，不冒称完整游戏画面。记录`art/environment/entry/gpu-log.txt`，输出`ENTRY_GPU_CAPTURE_OK corn=1301`。

共享cornfield此次只增加CPU元数据；M0默认自动扰动、主角模型/动画均未修改。没有新增音频总线、改工程配置、重复生物或派子代理。

## 复现与限制

```powershell
& 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'G:/Game/vallage/game' --script res://environment/entry_check.gd --quit-after 20
& 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --path 'G:/Game/vallage/game' --script res://environment/entry_capture.gd --rendering-method gl_compatibility --resolution 1280x800 --quit-after 90
```

沙箱仍有user://日志/缓存写入、系统证书/Wacom配置访问限制；已如实保留记录，未读取配置内容或凭据。实际截图成功，未见环境脚本或shader编译错误。尚未进行用户真实3～5分钟试玩、整合HUD/危险/完成画面或音频听感验收，这些由集成和QA继续执行。
