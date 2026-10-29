# 风过玉米地 · ty3d

本次保存的是**已恢复的原地图 R48 检查点**，另附**独立 2D 静态八向主角小样**。两者没有合并；不是新完成版，也不包含未能恢复的后续原地图候选。

## 首次克隆后：离线恢复两件大素材

**必须先完成此步，再让 Godot 导入原地图。** 仓库为传输大小限制将两件大 GLB 无损拆成分块；不是删除素材，也不是替代模型。需要 Python **3.8+**（仅标准库，无联网或额外依赖），以及支持硬链接的本地文件系统（例如 NTFS、ext4、APFS；不要在 FAT/exFAT 盘直接运行）。在仓库根目录执行一次：

```bash
python3 restore_assets.py
```

Windows 若命令名不同，可用 `py -3 restore_assets.py`。脚本校验所有分块和最终 SHA-256 后原子恢复以下文件；保留分块，已存在且正确的文件不重写，存在不同内容时停止而不覆盖：

- `game/assets/characters/boy/normal_grip/v4/boy-closed-diagonal-surface-v4.glb`（16,088,172 字节）
- `game/assets/sprint_20261002/insects/giant_corn_borer.glb`（12,474,940 字节）

看到 `Assets ready` 后再按下面步骤启动。不要把 `.part` 文件直接交给 Godot。该步骤恢复的 GLB 与已验证完整源码逐字节一致，未修改游戏逻辑。要重跑恢复器安全测试：`python3 -m unittest discover -s packaging_tests -v`。

## 原地图：主要入口

用 Godot 打开 `game/project.godot`，等待首次导入完成后按 **F5**。默认入口已选为 `scenes/modular/modular_slice.tscn`。

```bash
godot --headless --path game --editor --import --quit
godot --path game
```

WASD 移动，鼠标左键挥棍，Esc 暂停。该版本仅保存地图布局；重开回入口，HP、金币和击杀不持久化。

## 独立 2D 静态主角小样

单独打开 `examples/static-2d/project.godot`，再打开 `scenes/corn_route_new_pixel_hero_static_v1.tscn`，按 **F6**。

```bash
godot --headless --path examples/static-2d --editor --import --quit
godot --path examples/static-2d res://scenes/corn_route_new_pixel_hero_static_v1.tscn
```

WASD/方向键移动，空格或鼠标左键攻击，R 重置。五房间、八怪物；主角每方向只有一张静态图，**没有完成 RUN/攻击/受伤动画**。小样默认 F5 仍是旧试作入口，不是新静态主角。部分未使用旧候选脚本仅作为历史源码保留，不能据此认为其他候选都可独立运行。

## 恢复和验证边界

- 原地图精确恢复链：R26 九分卷 → R37 的 606 文件 → R48 的 618 文件 → 玉米早出场/接触补丁的 622 文件；每个原始源文件 SHA-256 均匹配封存清单。13 个输入 ZIP 的 SHA-256 和 CRC 全部通过。
- 公开包装仅调整主地图入口、净化历史工作路径及对应元数据哈希，并补充说明；没有改动游戏脚本、场景或图片像素。详见 [恢复说明](RECOVERY_NOTES.md)。
- 本次使用 **Godot 4.6.3** 检查。原地图和小样均完成空缓存 headless 导入；原地图默认入口启动 120 帧后正常退出且无错误。
- 公开版 2D 小样通过：136 项八向 atlas、13 项异常配置拒绝、44 项场景检查、13,011 项资源检查，以及原 PNG 的 8 个独立轮廓/531,507 像素核验。800 tick 伤害轨迹和 3,062 tick 八怪通关轨迹与封存基线逐位一致（24 次攻击、0 死亡、最终 HP 3）。以上是 headless 逻辑/资源验证，不是正常图形画面验收。
- 原地图历史记录使用 Godot 4.7.2；本次未重新完成全图战斗、帧率、正常图形画面和全部历史测试验收。部分旧测试依赖未随恢复包保留的外部基线，不能声称整个历史测试集通过。
- `art/`、`tools/`、`docs/` 和旧 `Start-*.cmd` 保留原仓库历史资料。旧验证/渲染脚本可能引用当前不存在的辅助脚本，**不要用它们代替以上启动方式**。
- `.godot` 是可再生缓存，不随源码保存。引擎程序不包含在仓库中。

素材保留既有来源与适用条款；本次恢复没有为整个工程新增 MIT、CC0 等通用授权，也不表示所有素材均可任意再分发。
