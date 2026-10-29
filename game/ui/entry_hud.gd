extends "res://ui/hud.gd"

signal retry_requested

var objective_label: Label
var health_label: Label
var timer_label: Label
var menu_title: Label
var menu_body: Label
var resume_button: Button
var retry_button: Button
var damage_overlay: ColorRect
var damage_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	var top := PanelContainer.new()
	root.add_child(top)
	top.position = Vector2(24, 22)
	top.custom_minimum_size = Vector2(420, 0)
	top.add_theme_stylebox_override("panel", panel_style(Color(0.11, 0.18, 0.14, 0.91)))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	top.add_child(column)
	column.add_child(label("风过玉米地", 28, Color("fff0c3")))
	column.add_child(label("入口冒险  /  找回弹珠铁盒", 14, Color("bacaad")))
	objective_label = label("", 19, Color("f6dc9c"))
	column.add_child(objective_label)
	health_label = label("", 21, Color("e9bc68"))
	column.add_child(health_label)
	timer_label = label("", 13, Color("bacaad"))
	column.add_child(timer_label)
	var bottom := PanelContainer.new()
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -100
	bottom.offset_bottom = -20
	bottom.add_theme_stylebox_override("panel", panel_style(Color(0.11, 0.18, 0.14, 0.92)))
	var bottom_column := VBoxContainer.new()
	bottom_column.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_column)
	context_label = label("", 18, Color("fff0c3"))
	bottom_column.add_child(context_label)
	bottom_column.add_child(label("WASD / 方向键 跑动   ·   松开即停   ·   左键 / Space 挥枝   ·   E 拾取 / 出口   ·   Tab 日夜   ·   R 重试   ·   Esc 暂停", 14, Color("c2ceb9")))
	message_label = label("", 21, Color("fff0c3"))
	root.add_child(message_label)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	message_label.offset_left = -490
	message_label.offset_right = 490
	message_label.offset_top = -193
	message_label.offset_bottom = -111
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_shadow_color", Color("1a281d"))
	message_label.add_theme_constant_override("shadow_offset_x", 2)
	message_label.add_theme_constant_override("shadow_offset_y", 2)
	damage_overlay = ColorRect.new()
	root.add_child(damage_overlay)
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.color = Color(0.8, 0.25, 0.13, 0.0)
	pause_overlay = ColorRect.new()
	root.add_child(pause_overlay)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.035, 0.07, 0.055, 0.78)
	var center := CenterContainer.new()
	pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", panel_style(Color("283d30")))
	var menu := VBoxContainer.new()
	panel.add_child(menu)
	menu.add_theme_constant_override("separation", 14)
	menu_title = label("", 32, Color("fff0c3"))
	menu.add_child(menu_title)
	menu_body = label("", 18, Color("d2d8c6"))
	menu.add_child(menu_body)
	resume_button = Button.new()
	resume_button.name = "Resume"
	resume_button.text = "继续冒险  ·  Esc"
	resume_button.custom_minimum_size.y = 46
	resume_button.pressed.connect(func(): resume_requested.emit())
	menu.add_child(resume_button)
	retry_button = Button.new()
	retry_button.name = "Retry"
	retry_button.text = "从入口重新开始  ·  R"
	retry_button.custom_minimum_size.y = 46
	retry_button.pressed.connect(func(): retry_requested.emit())
	menu.add_child(retry_button)
	make_nonblocking(root)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	resume_button.mouse_filter = Control.MOUSE_FILTER_STOP
	retry_button.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	message_label.visible = false

func update_entry(progress: RefCounted, context: String, night: bool) -> void:
	var objectives := ["① 看看左侧玉米里的动静", "② 沿侧边小路找到铁盒", "③ 带着铁盒去北边出口", "铁盒已带出玉米地"]
	objective_label.text = "这次体力用完了" if progress.outcome == "lost" else objectives[progress.stage]
	health_label.text = "体力  " + "● ".repeat(progress.health) + "○ ".repeat(3 - progress.health)
	timer_label.text = ("月色" if night else "午后") + "  ·  " + time_text(progress.elapsed) + ("  ·  已拿到铁盒" if progress.item_collected else "  ·  铁盒还在田里")
	context_label.text = context

func time_text(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func show_menu(kind: String, progress: RefCounted) -> void:
	pause_overlay.visible = true
	resume_button.visible = kind == "pause"
	if kind == "won":
		menu_title.text = "找回来了！"
		menu_body.text = "弹珠铁盒平安带出了玉米地。\n用时 %s  ·  剩余体力 %d / 3\n%s" % [time_text(progress.elapsed), progress.health, "你用树枝击退了田鼠，平安把铁盒带回来了。" if progress.enemy_repelled else "你绕开了田鼠，把铁盒带回来了。"]
	elif kind == "lost":
		menu_title.text = "先回田边歇歇"
		menu_body.text = "这次体力用完了，回入口重新试一遍吧。\n田鼠停下前摇时，往侧面走，或用树枝打断。\n也可以跑开绕过去，从入口再试一次。"
	else:
		menu_title.text = "歇一会儿"
		menu_body.text = "已暂停。角色、动物和关卡时间都已停下。\n小鸡是无害的，靠近看看；E 拾起弹珠铁盒。\n田鼠可绕行，前摇时侧移或挥树枝；带盒去北边出口。"

func hide_menu() -> void:
	pause_overlay.visible = false

func show_damage() -> void:
	damage_time = 0.32

func reset_feedback() -> void:
	message_time = 0.0
	message_label.visible = false
	damage_time = 0.0
	damage_overlay.color.a = 0.0
	hide_menu()

func _process(delta: float) -> void:
	super._process(delta)
	if not get_tree().paused:
		damage_time = maxf(0.0, damage_time - delta)
	damage_overlay.color.a = damage_time / 0.32 * 0.18
