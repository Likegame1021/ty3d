# 首个样件：环境与技术美术实施报告

日期：2026-09-27。范围：关卡搭建、环境模块、玉米风摆与扰动、日夜；没有修改角色资产或主程序文件，没有调用 Meshy / ImageGen。

## 实际交付

- `tools/build_environment.py`：Blender 5.2.2 后台生成器，随机种子固定，支持重新生成。
- `art/environment/`：corn、fence、rocks、crate、haystack、jar、grass、tree 共8份 `.blend` 母版；`game/assets/environment/` 对应8份GLB。
- 玉米叶片是有中脊、弯曲、收尖和厚度的几何叶片；秆、玉米穗、顶部雄穗是几何体；没有透明叶片图片。
- 围栏使用圆柱木桩与横杆；木箱为分块板条；石块为不规则低面体；陶罐有开口；草垛带零散秸秆；树为分叉树干与簇状冠层。
- `game/environment/cornfield.gd` 自建环境：公开 `set_night(bool)` 和 `set_player_position(Vector3)`，无需修改接口即可实例化。

来源：本轮原创程序几何与自定义材质；色调和体块参考项目 `docs/references/henan_countryside_forever_summer.png`，没有将图片贴到模型上。程序生成属于环境模块生产，不能用来代替主角的 Meshy 生成/绑定验收。

## 地图与运行行为

核心范围约28×32米。出生(0,0,8)、目标(0,0,-5)及中心土路留空；目标由主程序创建。地面及外围隐形防越界碰撞在层1，面向玩家层2。玉米和大多数装饰没有逐株碰撞、骨架或刚体。

42个约4米地块，共1326株玉米，每块共享同一3材质表面网格；MultiMesh减少节点和提交成本，裁剪是地块级，不能逐株裁剪。每块自定义AABB留出风摆/接近扰动余量。不将玉米地当实心遮挡体，不启用自动遮挡体烘焙。

`corn.gdshader` 使用每实例随机相位/颜色、顶端权重风摆、玩家近处推开及一个独立移动隐藏源扰动。世界空间扰动转换回实例局部坐标，随机转向后仍向远离玩家方向弯曲。隐藏源在左侧玉米区循环移动，没有新增敌人AI或练习目标。

时间使用 `_process` 驱动的 `animation_time` uniform，未使用 shader 内置 TIME。场景继承暂停模式时，风摆与隐藏源同时停止。土路使用程序材质；白天暖阳、夜晚低强度蓝色补光及少量玉米自发光用于保持可读。

## 验证与证据

- Blender后台实际完成8份GLB导出和母版保存，记录见 `art/environment/build-log.txt`。已避开5.2不支持的旧导出参数。原脚本还带未使用的顶点色属性，导出器提示不导出；游戏使用材质表面颜色，不依赖该属性。
- Godot4.7.2 headless导入完成，记录见 `art/environment/godot-import-log.txt`。
- `check_environment.gd` 实际输出 `ENVIRONMENT_CHECK_OK plots=42 corn=1326 ground=spawn,target,route night=toggle`。检查42分块、1326株、出生/目标/路中地面Y=0、日夜uniform切换与暂停期间时间冻结。记录见 `art/environment/headless-log.txt`。
- 非headless GPU渲染：NVIDIA RTX3080Ti，OpenGL3.3，Compatibility；两份PNG实际生成并已查看，没有脚本或shader编译错误。记录见 `art/environment/gpu-log.txt`。
- 最新环境独立渲染证据：`game/environment/preview_day.png`、`preview_night.png`。这两张不含主角/HUD；完整游戏证据由主程序/QA保存。
- 主程序反馈其跟随镜头下昼夜可读、中央路可走，移动、跑步、攻击与地图边界回归通过；此为跨岗位反馈，不冒称本报告独立执行了程序玩法测试。

## 复现

```powershell
& 'D:/blender.exe' --background --factory-startup --python 'G:/Game/vallage/tools/build_environment.py'
& 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'G:/Game/vallage/game' --editor --import --quit
& 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'G:/Game/vallage/game' --script res://environment/check_environment.gd --quit-after 20
& 'C:/Users/21078/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --path 'G:/Game/vallage/game' --script res://environment/capture_environment.gd --rendering-method gl_compatibility --resolution 1280x800 --quit-after 60
```

## 限制

沙箱运行日志有Godot用户目录/缓存写入、系统证书读取和系统Wacom配置访问限制，GPU仍正常渲染。没有读取该配置或凭据；没有把这些启动级错误隐瞒为“日志完全无错误”。母版保存另有Blender自带笔刷资源相对路径警告，不影响本次网格GLB。

未做最低配置性能承诺或正式帧时间预算；密度、阴影和相机仍需最终整合评估。此处为小样件环境，尚无完整村庄、水渠或Boss关卡。

## 后续小修订（2026-09-27）

- 视觉PlaneMesh扩为100×100米，避免跟随镜头边缘出现蓝色虚空；地面碰撞仍30×34米，外围防越界及核心28×32米可行走范围不变。
- crate用约0.74米盒碰撞；jar、haystack及tree分别用简化柱碰撞。各自随实例缩放，层1/遮罩2。玉米、草与石块仍不逐株添加物理体。
- 环境headless回归重新通过；额外对木箱、陶罐、草垛和树干位置从上方射线，确认命中SimplePropCollision并具有合理高度，中央路径/目标/出生地面仍Y=0。
