# M2 三件 Meshy 静态资产验收卡

2026-09-28。风格目标为 `docs/references/henan_countryside_forever_summer.png` 与 `art/environment/references/style-v002/` 下的三张单件图：温暖乡村木色、自然橄榄绿和清楚的大轮廓。原始下载均未改写；本轮未请求新的 Meshy 任务。工作流为 Blender 5.2.2 后台导入、修尺寸/原点/材质并保存 `.blend` 母版，导出独立 GLB，Godot 4.7.2 Compatibility 导入。处理脚本为 `tools/environment/process_meshy_static.py`。

| 资产 | 原始模型 / 任务 ID | Blender 母版与正式 GLB | 尺寸、面数、材质 |
|---|---|---|---|
| 农具棚 | `art/environment/meshy/tool-shed/v001/model.glb` / `01a0e53e-4acf-757a-bca3-c9f72bdf4cc5` | `art/environment/meshy/shed-v001.blend` / `game/assets/environment/meshy/shed.glb` | 6.1×5.5×3.4 m；10603 三角面；1 个保留 2K 基色贴图的材质。单独 `RoofVisual`，其 8132 原面片被分离为屋顶组。 |
| 板车 | `art/environment/meshy/farm-cart/v001/model.glb` / `01a0e53f-8252-7557-89a6-c5b13fba8585` | `art/environment/meshy/cart-v001.blend` / `game/assets/environment/meshy/cart.glb` | 平面约 1.32×2.4 m，高 0.75 m；5281 三角面；1 个保留 2K 基色贴图的材质；轮底归零、长轴朝原有道路。 |
| 槐树 | `art/environment/meshy/locust-tree/v001/model.glb` / `01a0e53f-927a-72c5-8791-81e9ae74c797` | `art/environment/meshy/tree-v001.blend` / `game/assets/environment/meshy/tree.glb` | 4.8×3.6×5.0 m；5191 三角面；原树干 1 个 2K 基色材质，加 5 个 256² 橄榄绿叶纹材质。 |

三件原始模型的脚底/接地归零。GLB JSON 复核：所有材质有基色贴图，`metallicFactor=0`、`roughnessFactor≈0.78`；原 Meshy 的金属粗糙度贴图连线已解除，避免木材呈现金属感，法线贴图保留。`.blend` 同目录 JSON 清单记录原/终尺寸、三角面、贴图分辨率。没有为这些静态资产添加骨架或动画。

槐树原始预览近乎无叶，检查 GLB 后确认只有约 2167 三角面，材质没有会误隐藏树冠的 alpha 或剔面设置，故属于生成几何缺冠。最终资产是 **Meshy 树干 + Blender 补树冠**，不能视为 Meshy 单独完整生成。修补部分用 18 个圆润低面簇共 1728 多边形，并以深浅橄榄绿 256² 叶纹减轻纯色球感。固定俯视实机中轮廓已完整，但树冠仍有可见簇状拼接，与棚屋细致的原始纹理精度并不完全一致；正式美术阶段需继续精修叶片轮廓与纹理，不将样件质量冒称最终美术验收。

Godot `full_field.gd` 仅在 M2 实例化三件新 GLB；M0/M1 未改。棚屋保留原静态侧/后墙碰撞、南口通道和发射器坐标，玩家进入时只隐藏新资产的屋顶组；雪天屋顶轻覆雪。板车保留原 `CartBodyCollision`，随 `cart_moved` 同步移动，雪天 shader 仅淡化朝上的木面。树木沿原 M2 树位少量复用，约 5.2 千三角面每株；没有复制为成千植株，玉米仍由原分地块 MultiMesh 承担密度。

验收证据：`game/environment/full_field_check.gd` headless 输出 `FULL_ENVIRONMENT_OK`、退出码 0，确认新 GLB 加载、屋顶可隐藏、车与棚碰撞/通道、晴雨雪切换和积雪材质复位。`game/environment/full_capture.gd` 在 Windows OpenGL 3.3 Compatibility 输出 `FULL_ENV_GPU_CAPTURE_OK`、退出码 0，20 张图包括 `game/tests/full-env-farm.png`、`full-env-farm-inside.png`、`full-env-farm-rain.png`、`full-env-farm-snow.png`；已目视三件新资产、棚内遮挡、雨雪状态。`docs/qa/art-review.html` 可并排比较原参考和实机。此次验收仅针对资产/环境接口，不代替完整玩法回归。
