extends "res://ui/hud.gd"

signal retry_requested
signal weather_requested(value: String)

const CORN_CHARGE_SECONDS := 0.55
const CornReticle = preload("res://ui/corn_reticle.gd")

var objective_label: Label
var health_label: Label
var detail_label: Label
var boss_panel: PanelContainer
var boss_meter: ProgressBar
var boss_health_label: Label
var charge_meter: ProgressBar
var charge_label: Label
var menu_title: Label
var menu_body: Label
var resume_button: Button
var retry_button: Button
var weather_row: HBoxContainer
var damage_overlay: ColorRect
var damage_time := 0.0
var menu_panel: PanelContainer
var weapon_panel: PanelContainer
var corn_reticle: Control
var bottom_panel: PanelContainer
var controls_label: Label
var title_label: Label
var _corn_equipped := false
var _corn_lab := false
var _aim_requested := false
var _charge_fill: StyleBoxFlat

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 17
	root.theme = theme
	var top := PanelContainer.new()
	root.add_child(top)
	top.position = Vector2(20, 18)
	top.custom_minimum_size = Vector2(385, 0)
	top.add_theme_stylebox_override("panel", panel_style(Color(0.10, 0.17, 0.13, 0.88)))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	top.add_child(column)
	title_label = label("风过玉米地", 26, Color("fff0c3"))
	column.add_child(title_label)
	objective_label = label("", 18, Color("f5db9b"))
	column.add_child(objective_label)
	health_label = label("", 20, Color("efc176"))
	column.add_child(health_label)
	detail_label = label("", 14, Color("c6d1bb"))
	column.add_child(detail_label)
	boss_panel = PanelContainer.new()
	root.add_child(boss_panel)
	boss_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	boss_panel.offset_left = -286
	boss_panel.offset_right = -20
	boss_panel.offset_top = 18
	boss_panel.offset_bottom = 150
	boss_panel.add_theme_stylebox_override("panel", panel_style(Color(0.17, 0.12, 0.10, 0.9)))
	var boss_column := VBoxContainer.new()
	boss_column.add_theme_constant_override("separation", 4)
	boss_panel.add_child(boss_column)
	boss_health_label = label("荒田稻草人  12 / 12", 17, Color("f5d39b"))
	boss_column.add_child(boss_health_label)
	boss_meter = ProgressBar.new()
	boss_meter.max_value = 12
	boss_meter.show_percentage = false
	boss_meter.custom_minimum_size.y = 16
	boss_meter.add_theme_stylebox_override("fill", meter_style(Color("d88b59")))
	boss_meter.add_theme_stylebox_override("background", meter_style(Color("45352c")))
	boss_column.add_child(boss_meter)
	weapon_panel = PanelContainer.new()
	root.add_child(weapon_panel)
	weapon_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_panel.offset_left = -304
	weapon_panel.offset_right = -20
	weapon_panel.offset_top = -182
	weapon_panel.offset_bottom = -17
	weapon_panel.add_theme_stylebox_override("panel", panel_style(Color(0.10, 0.17, 0.13, 0.94)))
	var weapon_column := VBoxContainer.new()
	weapon_column.add_theme_constant_override("separation", 5)
	weapon_panel.add_child(weapon_column)
	weapon_column.add_child(label("玉米枪", 23, Color("f5d071")))
	weapon_column.add_child(label("左键按住连射\n右键蓄力散射", 15, Color("e0e4c9")))
	charge_label = label("", 14, Color("f4dd9e"))
	weapon_column.add_child(charge_label)
	charge_meter = ProgressBar.new()
	charge_meter.max_value = 100
	charge_meter.show_percentage = false
	charge_meter.custom_minimum_size.y = 10
	_charge_fill = meter_style(Color("e2c366"))
	charge_meter.add_theme_stylebox_override("fill", _charge_fill)
	charge_meter.add_theme_stylebox_override("background", meter_style(Color("453e2d")))
	weapon_column.add_child(charge_meter)
	var bottom := PanelContainer.new()
	bottom_panel = bottom
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_top = -119
	bottom.offset_bottom = -17
	bottom.add_theme_stylebox_override("panel", panel_style(Color(0.10, 0.17, 0.13, 0.90)))
	var bottom_column := VBoxContainer.new()
	bottom_column.add_theme_constant_override("separation", 3)
	bottom.add_child(bottom_column)
	context_label = label("", 17, Color("fff0c3"))
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom_column.add_child(context_label)
	controls_label = label("WASD 移动 · Shift 跑 · E 交互/翻栏 · F 投石\n空格/左键 挥枝 · Q 切换 · Tab 日夜 · F6 天气 · Esc 暂停", 12, Color("c4ceb9"))
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom_column.add_child(controls_label)
	message_label = label("", 20, Color("fff0c3"))
	root.add_child(message_label)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	message_label.offset_left = 20
	message_label.offset_right = -20
	message_label.offset_top = -211
	message_label.offset_bottom = -137
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_shadow_color", Color("142219"))
	message_label.add_theme_constant_override("shadow_offset_x", 2)
	message_label.add_theme_constant_override("shadow_offset_y", 2)
	corn_reticle = CornReticle.new()
	root.add_child(corn_reticle)
	corn_reticle.visible = false
	damage_overlay = ColorRect.new()
	root.add_child(damage_overlay)
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.color = Color(0.8, 0.24, 0.12, 0)
	pause_overlay = ColorRect.new()
	root.add_child(pause_overlay)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.03, 0.07, 0.05, 0.79)
	var center := CenterContainer.new()
	pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_panel = PanelContainer.new()
	center.add_child(menu_panel)
	menu_panel.custom_minimum_size = Vector2(520, 0)
	menu_panel.add_theme_stylebox_override("panel", panel_style(Color("293e32")))
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 11)
	menu_panel.add_child(menu)
	menu_title = label("", 30, Color("fff0c3"))
	menu.add_child(menu_title)
	menu_body = label("", 17, Color("d6dfce"))
	menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(menu_body)
	weather_row = HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 10)
	menu.add_child(weather_row)
	for pair in [["晴", "sunny"], ["雨", "rain"], ["雪", "snow"]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size = Vector2(90, 38)
		var value: String = pair[1]
		button.pressed.connect(func(): weather_requested.emit(value))
		weather_row.add_child(button)
	resume_button = Button.new()
	resume_button.name = "Resume"
	resume_button.text = "继续冒险  ·  Esc"
	resume_button.custom_minimum_size.y = 44
	resume_button.pressed.connect(func(): resume_requested.emit())
	menu.add_child(resume_button)
	retry_button = Button.new()
	retry_button.name = "Retry"
	retry_button.text = "从入口重新开始  ·  R"
	retry_button.custom_minimum_size.y = 44
	retry_button.pressed.connect(func(): retry_requested.emit())
	menu.add_child(retry_button)
	make_nonblocking(root)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	for button in weather_row.get_children():
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	resume_button.mouse_filter = Control.MOUSE_FILTER_STOP
	retry_button.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	message_label.visible = false
	boss_panel.visible = false
	weapon_panel.visible = false
	charge_meter.visible = false
	charge_label.visible = false

func meter_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	return style

func update_full(progress: RefCounted, context: String, weather: String, night: bool, gun_equipped: bool, charge_seconds: float = -1.0) -> void:
	var objective := ""
	if progress.outcome == "lost":
		objective = "回入口再试一次"
	elif progress.outcome == "won":
		objective = "荒田恢复平静"
	elif not progress.chicken_seen:
		objective = "① 看看入口玉米里的动静"
	elif not progress.tin_taken:
		objective = "① 找回弹珠铁盒"
	elif not progress.canal_open:
		objective = "② 清理水口，再打开闸门"
	elif not progress.launcher_taken:
		objective = "③ 穿过高密玉米 · 农具区找发射器"
	elif not progress.boss_active:
		objective = "④ 前往北边的荒田"
	elif not progress.corn_gun and progress.corn_spilled:
		objective = "⑤ 趁它停住，组合玉米枪"
	else:
		objective = "⑤ 击退荒田稻草人"
	objective_label.text = "试枪场 · 移动瞄准，试试连射与蓄力" if _corn_lab else objective
	health_label.text = "体力  " + "● ".repeat(progress.health) + "○ ".repeat(progress.max_health - progress.health)
	var weather_name: String = {"sunny":"晴", "rain":"雨", "snow":"雪"}.get(weather, weather)
	var weapon := "玉米枪" if progress.corn_gun and gun_equipped else "树枝"
	detail_label.text = ("夜" if night else "昼") + " · " + weather_name + " · " + weapon + " · %02d:%02d" % [int(progress.elapsed) / 60, int(progress.elapsed) % 60]
	context_label.text = "试试边走边射 · 右键蓄满后松开，近处散射" if _corn_lab and context.is_empty() else context
	boss_panel.visible = progress.boss_active
	boss_meter.visible = progress.boss_active
	boss_meter.value = progress.boss_hp
	boss_health_label.text = "荒田稻草人  %d / %d" % [progress.boss_hp, progress.max_boss_hp]
	_corn_equipped = progress.corn_gun and gun_equipped
	weapon_panel.visible = _corn_equipped
	bottom_panel.offset_right = -322 if _corn_equipped else -20
	message_label.offset_right = -322 if _corn_equipped else -20
	controls_label.text = "WASD 移动 · Shift 跑 · E 交互/翻栏 · F 投石\nQ 切换 · Tab 日夜 · F6 天气 · Esc 暂停" if _corn_equipped else "WASD 移动 · Shift 跑 · E 交互/翻栏 · F 投石\n空格/左键 挥枝 · Q 切换 · Tab 日夜 · F6 天气 · Esc 暂停"
	if not _corn_equipped:
		_aim_requested = false
		corn_reticle.visible = false
		corn_reticle.reset_feedback()
	var show_charge: bool = _corn_equipped and charge_seconds >= 0
	charge_meter.visible = show_charge
	charge_label.visible = show_charge
	if show_charge:
		charge_meter.value = clampf(charge_seconds / CORN_CHARGE_SECONDS, 0, 1) * 100
		var ready: bool = charge_seconds >= CORN_CHARGE_SECONDS
		charge_label.text = "散射就绪 · 松开右键" if ready else "蓄力中 · 按住右键"
		_charge_fill.bg_color = Color("c9e294") if ready else Color("e2c366")
		charge_label.add_theme_color_override("font_color", Color("d7e9a3") if ready else Color("f4dd9e"))

func update_corn_aim(screen_position: Vector2, visible_aim: bool, charge_ratio: float) -> void:
	_aim_requested = visible_aim
	corn_reticle.update_aim(screen_position, charge_ratio)
	corn_reticle.visible = visible_aim and _corn_equipped and not pause_overlay.visible

func show_corn_hit(charged: bool = false) -> void:
	if _corn_equipped and not pause_overlay.visible:
		corn_reticle.show_hit(charged)

func set_corn_lab(enabled: bool) -> void:
	_corn_lab = enabled
	title_label.text = "田边试枪场" if enabled else "风过玉米地"

func show_menu(kind: String, progress: RefCounted) -> void:
	pause_overlay.visible = true
	corn_reticle.visible = false
	resume_button.visible = kind == "pause"
	weather_row.visible = kind == "pause"
	if kind == "won":
		menu_title.text = "风又吹过玉米地"
		menu_body.text = "找回铁盒，疏通水渠，也让荒田恢复了平静。\n用时 %02d:%02d  ·  剩余体力 %d / %d\n想再走一遍，可以按 R。" % [int(progress.elapsed) / 60, int(progress.elapsed) % 60, progress.health, progress.max_health]
	elif kind == "lost":
		menu_title.text = "先回田边歇歇"
		menu_body.text = "这次体力用完了。留意田鼠和稻草人的预警，再试一次。\n按 R 或点击下方按钮重新出发。"
	else:
		menu_title.text = "歇一会儿"
		menu_body.text = "冒险已暂停。可以在这里预览晴、雨、雪。\nTab 切换日夜；F6 也能在路上切换天气。"

func hide_menu() -> void:
	pause_overlay.visible = false
	corn_reticle.visible = _aim_requested and _corn_equipped

func set_paused(value: bool) -> void:
	pause_overlay.visible = value
	corn_reticle.visible = not value and _aim_requested and _corn_equipped

func show_damage() -> void:
	damage_time = 0.32

func reset_feedback() -> void:
	message_time = 0.0
	message_label.visible = false
	damage_time = 0.0
	damage_overlay.color.a = 0
	_aim_requested = false
	corn_reticle.reset_feedback()
	hide_menu()

func _process(delta: float) -> void:
	super._process(delta)
	if not get_tree().paused:
		damage_time = maxf(0.0, damage_time - delta)
	damage_overlay.color.a = damage_time / 0.32 * 0.18
