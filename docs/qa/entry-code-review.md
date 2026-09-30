# M1 玩法代码独立审查（2026-09-28）

审查范围：`game/levels/entry.gd`、`game/scripts/entry_*.gd`、`game/ui/entry_hud.gd`、共享 `player.gd` 与 `docs/entry-milestone-spec.md`。未修改玩法实现。

**结论：未发现阻塞交付的玩法缺陷。** 鸡揭示→铁盒拾取→绕开或击退鼠怪→出口的状态门控完整；铁盒仅可计一次，出口缺物品会提示。胜利/失败会冻结危险并显示重试；暂停、继续、R 重置覆盖体力、攻击、物品、动物、敌人、环境和时间。鼠怪的攻击前摇、距离/方向、冷却、无敌时间、追击边界和脱战回归都有对应约束。小鸡不在攻击组。音频监听器在玩家身上，朝向跟随相机，空间提示不会因远距相机衰减。现有输入、敌人、进度和实体移动路线测试均为 0 failures；独立新跑 M0 `test_game.gd` 与 `test_input.gd`，均为 0 failures。

非阻塞的体验校准：物理输入自动路线用 13.78 秒直达出口且零受伤，说明可达性与绕怪路线成立；它是已知目标的优化操作，不能证明首次玩家已达到规格中的 3–5 分钟，仍须正常账户真人首次试玩。当前 HUD 早期鼠怪标签可能提前泄露目标位置，已交主程序处理展示。

环境音频另行诊断：正常 Windows 账户的 `--headless --quit-after` 同样复现一个 `AudioStreamWAV` 和一个 `AudioStreamPlaybackWAV` 退出泄漏。为两个声源加 `tree_exiting → stop + stream=null`、环境退出清理缓存后，该强制退出仍泄漏。最终修正仅在 `DisplayServer.get_name() == "headless"` 时跳过实际播放；PCM 合成、提示计时和环境接口保留。相同 `--headless --verbose --quit-after 120 res://levels/entry.tscn` 退出码 0，已无 `Leaked instance` / `ObjectDB instances`。对照用 Windows 显示驱动及 OpenGL 运行真实入口场景，1.2 秒后确认 `AUDIO_STARTED=true`，再 `queue_free` 场景并退出；`DISPLAY_DRIVER=Windows`、`AUDIO_SCENE_FREED=true`、退出码 0，且无资源泄漏警告。该对照脚本运行后已删除；不改变正常图形模式播放。

音频修正后新跑 `test_entry.gd` 与 `test_entry_input.gd`，均退出码 0、0 failures。
