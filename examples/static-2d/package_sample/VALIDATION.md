# 小样范围验证记录

日期：2026-10-11 UTC。引擎：Godot 4.6.3.stable.official.7d41c59c4。

## 本轮实际执行

- 将打包源复制到独立验证目录，确认开始前不存在 .godot 缓存；使用独立XDG数据/配置/缓存目录。
- godot --headless --path <验证项目目录> --editor --import --quit：退出0。273项导入，日志中无ERROR、SCRIPT ERROR、WARNING。未借用工作工程的缓存。
- bash run_small_sample_tests.sh：退出0。
- 源像素只读检查通过：8个完整独立轮廓，531,507个保留像素，PNG SHA256一致。
- 原atlas检查136项、拒绝配置检查13项、候选场景检查44项：全部0失败。
- 新增打包资源检查13,011项：0失败。覆盖新英雄实际atlas、8只怪物各4类clip的所有8×8帧、纹理路径和源SHA256，启动及R重置接口之后各一遍，10个环境实例节点，原默认main的3个角色纹理。
- 通关数值轨迹：3,062 tick，8怪，24次攻击输入，0死亡，最终HP3；SHA256 098ad84d21c557642fa27be0d88224f661321ebf662733900ee288f390504a05，与封存源baseline完全相同。
- 受控伤害数值轨迹：800 tick，1次重生，最终HP3，包含run/attack/recover/idle/hurt；SHA256 4a1329f96ee5c330a000be1f3d2f7e49ad1a60fe7359a2d0601e586230023b84，与封存源baseline完全相同。
- 单独负对照目录省略 assets/mist_monster_attack_v003/E_attack_00.png 后，首次导入仍可退出0，但资源检查明确退出1（147项中112项失败）。这证明测试能检出运行时动态怪物素材缺失，而非仅凭引擎退出码或通关判断完整。
- 调整的唯一测试时序是新增打包检查对旧默认main等候完整一轮物理回调，再检查已显示纹理；原游戏代码无变更。原版本早于该回调取值，会造成3条过早检查失败；修正后的正/负对照均没有这些假失败。

## 封存与独立内容检查

383个保留源文件逐字节相同；483个省略源文件均有原大小、SHA256和理由记录。源ZIP SHA256仍为849f019a8dcfad1bc5b66562eb355cd04d42bf5f4adaa181934e534a6bd42539。

独立内容复核确认：383/483分区完整；无重复、越界路径或缓存项；所有extends/preload目标存在；256张怪物原帧及四组manifest/calibration全部与profile匹配；主角PNG/profile/import配置不变；五个GLB自包含；默认main依赖保留；原shell执行权限保留。

完整包的最高级DEFLATE无损重压实测21,399,033字节，只节省5,906字节。最终选择依赖明确的小样范围，而非改图像像素或游戏逻辑。

附 clean-import.log、positive-suite.log 和预期失败的 negative-missing-frame.log。封存来源自身的旧日志仍位于 evidence/new_pixel_hero_static_v1/，不能混称为本轮重新执行完整旧合集。

## 边界

以上都是资源、源码字节、源像素和headless逻辑验证。未运行正常图形显示验收；不声称截图、人物观感、脚锚视觉稳定、遮挡或动画通过。本角色仍是静态八向，不是RUN/攻击动画完成版。

最终ZIP封装后另作全新解压导入和测试，结果随交付说明提供；本文件记录的是封装前上述独立无缓存验证。
