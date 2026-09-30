# 玉米枪验收记录

日期：2026-09-28。项目：`G:\Game\vallage`。运行环境：Windows、Godot 4.7.2、Compatibility、NVIDIA GeForce RTX 3080 Ti。

最终结果：**35 / 35 项检查通过**，包括原场景自动通关、M0/M1 回归、GPU 渲染与验证期间源文件未变化检查。最终日志无脚本错误、FAIL 或 ObjectDB 泄漏。自动输入流程实际到达胜利状态；该流程的约 56 秒机器操作用时不作为真人游玩时长。

## 本次交付

- 原完整场景的玉米枪升级为鼠标瞄准、按住左键连射、右键蓄力散射，可边移动边射击。
- 玉米枪专用模型、双臂持枪姿态、后坐、苞叶摆动、枪口闪光、玉米粒拖尾、命中碎粒、伤害数字、准星和蓄力反馈。
- 射击、散射、命中及蓄力声音；独立的开火声道避免群体命中抢占枪声。
- `Start-Corn-Gun.cmd` 直接进入试枪场：三个木靶、4/6/8 只田鼠的三波挑战、36 体力稻草人。
- 保留原关卡的解锁流程和树枝近战。新试枪场不要求重走解锁路线。

## 验证方法

统一命令：

```powershell
& .\tools\verify-full.ps1 -Render -EvidenceDirectory 'G:\Game\vallage\docs\qa\corn-evidence\final-suite'
```

结果来源为该命令生成的 [summary.json](corn-evidence/final-suite/summary.json) 和 [参与验证的文件哈希](corn-evidence/final-suite/verified-files.json)。验证器把脚本错误、FAIL、非零退出及 ObjectDB 资源泄漏都视为失败。

新增专项测试覆盖：

| 范围 | 证据 |
| --- | --- |
| 普通弹射线、侧方不误伤、实体墙阻挡、近距离斜向靶心、首次右键瞄准 | [瞄准日志](corn-evidence/final-suite/test_full_corn_aim.log) |
| 按住连射、松开停止、短蓄力与长蓄力、多目标只结算一次、切枪/暂停/失焦/胜负取消输入、菜单点击不穿透 | [真实输入事件日志](corn-evidence/final-suite/test_full_corn_input.log) |
| 群体命中保留枪声、声道上限、暂停恢复、重试与退出清理 | [WASAPI 音频日志](corn-evidence/final-suite/test_full_corn_audio.log) |
| 准星、蓄力、命中提示、菜单遮罩与界面边界 | [HUD 日志](corn-evidence/final-suite/test_full_corn_hud.log) |
| 木靶受击、移动敌人、出生距离、Boss、重开清理 | [试枪场日志](corn-evidence/final-suite/test_full_corn_lab.log) |
| 特效数量上限、暂停与清理 | [特效生命周期日志](corn-evidence/final-suite/check_corn_fx.log) |
| idle/walk/run 持枪时的握点、非手臂骨骼和交互动作保持 | [持枪姿态日志](corn-evidence/final-suite/check_corn_hold.log) |

还执行原完整场景的角色动作、战斗、进度、边界、武器、输入与自动通关，以及 M0/M1 回归。实际音频测试指定 WASAPI；无声 Dummy 后端保留资源与声道检查，但不创建无用的音频播放实例。

## 实机画面

截图来自当前游戏的 GPU 渲染，未做美术合成。查看了 1280×800 与 960×600 的界面、白天射击、雨夜蓄力和持枪近景。

- [散射与清怪实机图](corn-evidence/corn-combat.png)
- [七粒散射、枪口闪光与命中数字](corn-evidence/corn-scatter.png)
- [命中与弹道](corn-evidence/corn-hit.png)
- [蓄力准星与提示](corn-evidence/corn-charge.png)
- [雨夜](corn-evidence/corn-rain-night.png)
- [960×600 界面](corn-evidence/corn-960.png)
- [持枪近景](corn-evidence/corn-grip.png)

## 修正记录与边界

先复现、再修正了普通弹过宽误伤、木靶靶心与瞄准平面不一致、首次右键没有更新瞄准、敌人贴身出生、群体命中抢占枪声和退出音频资源清理问题。原自动通关测试仍按旧版朝向射击，已改为发送真实鼠标移动事件并瞄准 Boss，没有降低伤害或胜利断言。

射击参数目前用于试玩调校，未经过多人盲测或长期难度平衡。声音已验证实际后端播放与生命周期，未做人工听感打分。失焦取消由 Godot 通知测试覆盖，未声称进行人工 Alt-Tab 测试。

本次未制作肉鸽地图选路、局内材料、改装或升级树。武器和特效为程序化资产，人物沿用项目既有模型；稻草人与小怪仍为项目已有外形。
