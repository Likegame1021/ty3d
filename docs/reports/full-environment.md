# M2 五区环境与天气交付

交付文件：`game/environment/full_field.gd`、`weather.gd`、`full_soil.gdshader`、`full_corn.gdshader`、`full_water.gdshader`、`full_wetland.gdshader`、`weather_precip.gdshader`、`full_cart_snow.gdshader`；独立检查 `full_field_check.gd` 与 GPU 采图 `full_capture.gd`。未修改 M0/M1 环境与角色资产。

场景 56×96 米，入口、贯通水渠、高密玉米、农具棚和 Boss 空地有独立地标。复用既有玉米/围栏/树/石头/草垛/木箱/陶罐/草 GLB；玉米 3625 株按 162 个约 5 米地块 MultiMesh 渲染，主路和侧路留空。Boss 中心半径 8 米无静态稻草人。土路使用连续多尺度噪声，棚屋旧板屋顶在玩家入棚时只隐藏屋顶视觉，露出内部道具和主角。五处小暖灯辅助夜间认路。

公开接口：`set_player_position(Vector3)`、`set_night(bool)`、`set_weather(String)`、`set_progress(Dictionary)`、`set_actor_sources(Array[Vector3])`、`reset_field()`。`set_progress` 支持既定六键 `canal_open/cart_moved/launcher_taken/boss_active/corn_spilled/boss_defeated`，另支持清堵阶段的 `mouth_cleared`。清堵后堵石隐藏、湿地显现；开闸后门的碰撞和视觉移除、水流及涟漪增强、局部玉米倒伏。板车随状态移走，棚两侧和后墙、板车有简化实体碰撞；南口保持可通，主程序另负责状态横栏。actor_sources 的前四槽分别为鸡、巡游怪、Boss、首只召唤怪；玉米摇摆强度/范围分级，源无效时传 `(1000,0,1000)`。重试复位门、板车、储存物、天气晴天、日光、音效和时钟。

雨雪采用跟随玩家的局部 26×26 米 MultiMesh：雨 340 条、雪 175 片；雨天地面暗湿与连续水洼涟漪，雪天地面/屋顶积雪且保留主路灰蓝区分。时钟由 `_process` 推进，暂停时场景与天气均停止。环境声使用程序 PCM 的低音量雨雪循环与既有鸡声/沙沙声 WAV；仅在有图形显示驱动时播放，headless 保留状态与时钟而不启动音频。

三件 M2 新资产现来自 Meshy 原始 GLB 经 Blender 整理：棚屋、板车、树木；原始树缺冠，树干保留而树冠由 Blender 修补，详见 `docs/reports/meshy-static-assets.md`。棚屋及板车保留 2K 基色纹理；棚屋屋顶可单独隐藏并在雪天轻覆雪，板车朝上木面有受控积雪覆盖。M2 旧程序化外观保留为导入失败时的回退，原有碰撞及交互坐标未改。

验证：Godot 4.7.2 headless 运行 `res://environment/full_field_check.gd` 退出码 0，输出 `FULL_ENVIRONMENT_OK`；检查 162 地块/3625 株、三件 GLB 存在和新外观实际装载、清堵与开闸的即时材质/碰撞、恢复关闸、天气与积雪材质、暂停、板车移动后棚中心通道、侧后墙碰撞与屋顶遮挡。Windows OpenGL 3.3 Compatibility 运行 `res://environment/full_capture.gd` 输出 `FULL_ENV_GPU_CAPTURE_OK`，生成 `game/tests/full-env-*.png` 共 20 张，已目视五区、清堵/开闸、晴雨雪昼夜、棚内遮挡及四处夜间灯光。独立 GUI 音频对照确认 `DISPLAY_DRIVER=Windows`、`RAIN_AUDIO_STARTED=true`、`CHICKEN_AUDIO_STARTED=true`、场景释放 true、退出码 0，未见泄漏；临时检查脚本已删除。环境单独截图不代表主程序 HUD、Boss 交互或真人游玩节奏已验收。
