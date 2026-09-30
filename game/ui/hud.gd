extends CanvasLayer

signal resume_requested

var status_label: Label
var tally_label: Label
var context_label: Label
var message_label: Label
var asset_label: Label
var pause_overlay: ColorRect
var message_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	var top := PanelContainer.new()
	root.add_child(top)
	top.position = Vector2(26, 22)
	top.custom_minimum_size = Vector2(380, 0)
	top.add_theme_stylebox_override("panel", panel_style(Color(0.12, 0.18, 0.15, 0.90)))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	top.add_child(column)
	column.add_child(label("风过玉米地", 30, Color("fff0c3")))
	column.add_child(label("河南乡野  /  首个可运行样件", 14, Color("c3c9ad")))
	column.add_child(label("玉米移动波纹：扰动验证演示", 13, Color("c3c9ad")))
	status_label = label("", 17, Color("e5e6cc"))
	column.add_child(status_label)
	tally_label = label("", 20, Color("f4ce74"))
	column.add_child(tally_label)
	var bottom := PanelContainer.new()
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 26
	bottom.offset_right = -26
	bottom.offset_top = -109
	bottom.offset_bottom = -22
	bottom.add_theme_stylebox_override("panel", panel_style(Color(0.12, 0.18, 0.15, 0.92)))
	var bottom_column := VBoxContainer.new()
	bottom_column.add_theme_constant_override("separation", 5)
	bottom.add_child(bottom_column)
	context_label = label("沿中央小路，向前找到稻草练习桩。", 19, Color("fff0c3"))
	bottom_column.add_child(context_label)
	bottom_column.add_child(label("WASD / 方向键 移动   ·   Shift 跑步   ·   左键 / Space 挥枝   ·   E 交互   ·   Tab 日夜   ·   R 重置   ·   Esc 帮助", 15, Color("d2d8c6")))
	asset_label = label("", 13, Color("aebfae"))
	bottom_column.add_child(asset_label)
	message_label = label("", 23, Color("fff0c3"))
	root.add_child(message_label)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -320
	message_label.offset_right = 320
	message_label.offset_top = 38
	message_label.offset_bottom = 100
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.12, 0.09, 0.9))
	message_label.add_theme_constant_override("shadow_offset_x", 2)
	message_label.add_theme_constant_override("shadow_offset_y", 2)
	message_label.visible = false
	pause_overlay = ColorRect.new()
	root.add_child(pause_overlay)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.04, 0.08, 0.06, 0.75)
	var center := CenterContainer.new()
	pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pause_panel := PanelContainer.new()
	center.add_child(pause_panel)
	pause_panel.custom_minimum_size = Vector2(580, 0)
	pause_panel.add_theme_stylebox_override("panel", panel_style(Color("263d30")))
	var pause_column := VBoxContainer.new()
	pause_column.add_theme_constant_override("separation", 15)
	pause_panel.add_child(pause_column)
	pause_column.add_child(label("歇一会儿", 34, Color("fff0c3")))
	pause_column.add_child(label("已暂停。玉米、角色和攻击一起停下。", 18, Color("d2d8c6")))
	pause_column.add_child(label("WASD / 方向键移动，Shift 跑步。\n靠近练习桩，面向它按左键或 Space 挥枝。\n按 E 阅读练习说明；Tab 切换昼夜；R 重新开始。", 18, Color("d2d8c6")))
	var button := Button.new()
	button.text = "继续走走  ·  Esc"
	button.custom_minimum_size.y = 46
	button.pressed.connect(func(): resume_requested.emit())
	pause_column.add_child(button)
	pause_overlay.visible = false
	make_nonblocking(root)
	# The pause controls remain interactive while the gameplay HUD ignores clicks.
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_filter = Control.MOUSE_FILTER_STOP

func make_nonblocking(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		make_nonblocking(child)

func label(text: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result

func panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.73, 0.77, 0.54, 0.32)
	return style

func update_display(player: Node3D, night: bool, hits: int, nearby: bool) -> void:
	status_label.text = ("月色" if night else "午后") + "   ·   " + player.state + "   ·   固定斜俯视"
	tally_label.text = "练习命中  %02d" % hits
	context_label.text = "[ E ] 与练习桩交互  ·  面向稻草人，挥动树枝" if nearby else "沿中央小路，向前找到稻草练习桩。"
	asset_label.text = player.model_status

func show_message(text: String, seconds: float = 2.8) -> void:
	message_label.text = text
	message_label.visible = true
	message_time = seconds

func _process(delta: float) -> void:
	if not get_tree().paused and message_time > 0:
		message_time -= delta
		message_label.visible = message_time > 0

func set_paused(value: bool) -> void:
	pause_overlay.visible = value
