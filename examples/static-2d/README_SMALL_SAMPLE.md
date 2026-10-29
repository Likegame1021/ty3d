> **公开恢复版说明（2026-10-29）：** 以下为历史小样说明。当前公开版仅净化素材来源元数据的历史绝对路径、同步校验哈希并省略历史执行日志；像素、场景和游戏脚本未改。完整包/历史验收数字不是本次重跑结果，当前入口与验证范围以仓库根 README.md 为准。

# 新2D静态八向主角：独立小样包

本包从封存的 corn-route-new-2d-static-hero-v1-20261010-0231.zip 按依赖复制而来，只用于该新主角场景的独立运行和复核。不是完整历史候选合集。未改任何保留的游戏脚本、场景、project.godot、PNG像素或配置文件；原ZIP、旧正式工程和默认入口均未改。

## 开始运行

1. 解压到一个全新的目录，不要覆盖其他工程，也不要复制旧 .godot 缓存。
2. 使用 Godot 4.6.3 打开里面的 project.godot，等待首次资源导入完成。
3. 打开 scenes/corn_route_new_pixel_hero_static_v1.tscn 并按 F6。状态标识应为 NEW 2D HERO · EIGHT AUTHORED STATIC VIEWS；RESOURCE UNAVAILABLE 表示失败。

默认 main.tscn 及其旧素材依赖仍原样保留，F5会运行旧默认入口。要看本次新主角，必须使用上述新场景/F6。

Linux终端（已安装Godot 4.6.3，并在解压后的hd2d-trial目录）：

    godot --headless --path . --editor --import --quit
    godot --path . res://scenes/corn_route_new_pixel_hero_static_v1.tscn

也可使用 bash run_new_pixel_hero_static_v1.sh。若解压工具没有保留执行权限，直接使用上面的Godot命令。

WASD或方向键移动，空格/鼠标左键攻击，R重置。新主角每方向仍仅1帧；移动、攻击、受伤使用静态方向图，受伤保留红色提示。没有新增RUN或攻击动画。怪物的原四类动画资源全部保留。

## 本包为何更小

- 完整源包866项；其中383项逐字节保留，483项仅在这个小样包中省略。
- 省略了不被此新场景或默认main使用的旧主角烘焙素材、单正面候选素材，以及对应的其他候选入口、配置、完整合集测试和文档。
- 保留新主角原PNG和其真实 .import 设置；保留全部256张怪物帧、四组manifest/calibration、五个内嵌素材的环境GLB，以及默认main的旧角色贴图。
- 全部原运行时代码保留，包含继承和预加载链；部分未使用的旧候选脚本仍在，但其入口和资源未作为独立候选交付。
- package_sample/source-file-manifest.json 逐项列出来源、大小、SHA256和省略理由；package_sample/OMITTED_FILES.md 是易读省略清单。
- 本包不含可再生 .godot 缓存或引擎程序。完整源包本就没有该缓存；最高级DEFLATE重压只节省5,906字节，仍为21,399,033字节，因此使用明确裁定依赖的小样范围。

## 核验与证据范围

本包的命令以本README为准。README_NEW_PIXEL_HERO_STATIC_V1.md 和 evidence/new_pixel_hero_static_v1/ 原样保留，记录的是封存完整源包的既有证据；其中“837项原封存文件”“完整回归”及旧运行器命令不代表本小样仍含完整合集。

本小样测试入口为 bash run_small_sample_tests.sh，需要Godot 4.6.3以及已装Pillow、NumPy、SciPy的Python3。它运行原136项atlas、13项拒绝、44项候选场景检查，新增独立资源检查，并将新场景的通关/伤害数值轨迹与封存源证据比较。不会运行已省略的旧场景来重写baseline。轨迹测试会写同目录的 integrated JSON证据；baseline不改。

只验证保留源文件的字节一致性，可运行 python3 package_sample/verify_source_files.py；无需第三方Python库。

新主角PNG SHA256：3daffa7b35471ee21ee3750e71600fc0f03e2a75eda2c82c7051de27bf64058a

新主角profile SHA256：4071c18e749601f8b225ce43ed808a8e0ffad2ab8505c448e557366fe68c30c3

本轮具体检查结果见 package_sample/VALIDATION.md。headless导入、资源和逻辑检查不等于正常图形显示验收；像素密度、脚锚视觉稳定、边缘和前后遮挡仍需正常图形环境检查。没有声称人物动画已完成。
