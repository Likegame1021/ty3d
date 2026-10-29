extends CanvasLayer

const RoomMap = preload("res://scripts/cornfield/ui/room_map.gd")
const RouteChoices = preload("res://scripts/cornfield/ui/route_choices.gd")
const ToolheapPanel = preload("res://scripts/cornfield/ui/toolheap_panel.gd")

var input_guard: Callable
var overlay: Control
var heading: Label
var stats: Label
var hint: Label
var notice: Label
var health: ProgressBar
var health_text: Label
var wallet: Label
var build_summary: Label
var _display_generation := 0
var _display_submitted := false
var notice_time := 0.0
var controls_hint := "移动 · 松开即停 · 攻击 · 互动 · 地图 · 路线"
var opened := false
var panel_kind := ""
var _settlement_notice: Label
var base: Control
var theme_value: Theme
var minimap: Control
var boss_panel: Control
var boss_health: ProgressBar
var boss_name: Label
var _spawn_occluders: Array[Control] = []

class MiniMap extends Control:
	var info: Dictionary = {}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.13,0.24,0.19,0.78))
		draw_rect(Rect2(Vector2(1,1),size-Vector2(2,2)),Color("b4ab74"),false,1)
		draw_string(get_theme_font("font"),Vector2(5,13),str(info.get("title","田埂")),HORIZONTAL_ALIGNMENT_CENTER,88,9,Color("f4ebcb"))
		var area := Rect2(12,25,74,47)
		var points := PackedVector2Array()
		for point in info.get("outline", []):
			points.append(area.position + Vector2(point).clamp(Vector2.ZERO,Vector2.ONE) * area.size)
		if points.size() > 2:
			draw_colored_polygon(points,Color("344b3b"))
			points.append(points[0])
			draw_polyline(points,Color("ed8370") if info.get("completion",false) else Color("f2ead2"),2)
		for gate in info.get("gates", []):
			var normalized: Vector2 = Vector2(gate.get("pos",Vector2.ZERO)).clamp(Vector2.ZERO,Vector2.ONE)
			var at := area.position + normalized * area.size
			var vertical: bool = gate.get("side","") in ["west","east"] or (not gate.has("side") and (normalized.x < 0.05 or normalized.x > 0.95))
			var extent := Vector2(0,5) if vertical else Vector2(5,0)
			draw_line(at-extent,at+extent,Color("192f22"),6)
			draw_line(at-extent,at+extent,Color("76e64e") if gate.get("open",false) else Color("58b948"),4)
			if not gate.get("open",false):
				draw_line(at-Vector2(2,2),at+Vector2(2,2),Color("f2de9c"),2)
				draw_line(at+Vector2(-2,2),at+Vector2(2,-2),Color("f2de9c"),2)
			else:
				draw_circle(at,2,Color("fff3c5"))
		for contact in info.get("contacts",[]):
			var at := area.position+Vector2(contact.pos).clamp(Vector2.ZERO,Vector2.ONE)*area.size
			var extent := 3 if contact.get("boss",false) else 2
			draw_rect(Rect2(at-Vector2.ONE,Vector2.ONE*extent),Color("f3ca63") if contact.get("elite",false) else Color("e77961"))
		var state := str(info.get("gate_status",""))
		var state_at := Vector2(8,86)
		if info.get("next_unlocked",false):
			draw_colored_polygon(PackedVector2Array([state_at+Vector2(-1,-5),state_at+Vector2(3,-1),state_at+Vector2(-1,3),state_at+Vector2(-5,-1)]),Color("e4bf70"))
		elif state=="清场后开门":
			draw_line(state_at-Vector2(3,4),state_at+Vector2(3,2),Color("eadbaf"),2)
			draw_line(state_at+Vector2(-3,2),state_at+Vector2(3,-4),Color("eadbaf"),2)
		else:
			draw_circle(state_at-Vector2(0,1),3,Color("9cba6b"),false,1.5)
		draw_string(get_theme_font("font"),Vector2(16,89),state,HORIZONTAL_ALIGNMENT_LEFT,80,9,Color("f4ebcb"))
		var player_at := area.position + Vector2(info.get("player",Vector2(0.5,0.5))).clamp(Vector2.ZERO,Vector2.ONE) * area.size
		draw_circle(player_at,3,Color("263c31"))
		draw_circle(player_at,2,Color("f0c85b"))
		draw_circle(player_at,0.8,Color("fff5d0"))

func _ready() -> void:
	layer = 20
	theme_value = Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme_value.default_font = font
	theme_value.default_font_size = 12
	for type in ["Label","Button"]:
		theme_value.set_color("font_color",type,Color("423d2c"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e8d9b7")
		style.border_color = Color("b8a77d")
		if state == "hover":
			style.bg_color = Color("f4e8c9")
			style.border_color = Color("97773e")
		if state == "pressed":
			style.bg_color = Color("d2c397")
			style.border_color = Color("7f743e")
		if state == "disabled":
			style.bg_color = Color("e0d9c5")
			style.border_color = Color("c8bea5")
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		style.set_content_margin_all(5)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("8b783d")
			style.set_border_width_all(2)
		theme_value.set_stylebox(state,"Button",style)
	for state in ["font_hover_color","font_pressed_color","font_focus_color"]:
		theme_value.set_color(state,"Button",Color("423d2c"))
	theme_value.set_color("font_disabled_color","Button",Color("a09882"))
	base = Control.new()
	base.size = Vector2(640,400)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.theme = theme_value
	add_child(base)
	var top := Panel.new()
	top.position = Vector2.ZERO
	top.size = Vector2(640,52)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.94,0.89,0.75,0.96)
	top_style.border_color = Color("9e8a61")
	top_style.border_width_bottom = 2
	top_style.shadow_color = Color(0.16,0.14,0.08,0.20)
	top_style.shadow_size = 3
	top.add_theme_stylebox_override("panel",top_style)
	base.add_child(top)
	_spawn_occluders.append(top)
	for at in [Vector2(178,9),Vector2(478,9)]:
		var divider := ColorRect.new()
		divider.position = at
		divider.size = Vector2(1,32)
		divider.color = Color("c9b891")
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		base.add_child(divider)
	health = ProgressBar.new()
	health.add_theme_font_size_override("font_size",1)
	health.position = Vector2(16,11)
	health.size = Vector2(148,14)
	health.show_percentage = false
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_track := StyleBoxFlat.new()
	health_track.bg_color = Color("c7bca0")
	health_track.set_border_width_all(1)
	health_track.border_color = Color("766e4c")
	health_track.set_corner_radius_all(2)
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color("7b8f50")
	health_fill.border_color = Color("a2b16c")
	health_fill.border_width_top = 2
	health_fill.set_corner_radius_all(2)
	health.add_theme_stylebox_override("background",health_track)
	health.add_theme_stylebox_override("fill",health_fill)
	base.add_child(health)
	health.set_deferred("size",Vector2(148,14))
	health_text = make_label("体力",Vector2(16,29),10)
	health_text.size = Vector2(148,16)
	heading = make_label("田埂上的暑假",Vector2(191,6),13)
	heading.size = Vector2(277,22)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats = make_label("树枝剑",Vector2(191,30),10)
	stats.size = Vector2(91,16)
	stats.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	build_summary = make_label("尚未强化",Vector2(288,30),10)
	build_summary.size = Vector2(181,16)
	build_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	build_summary.add_theme_color_override("font_color",Color("6c714e"))
	wallet = make_label("零花钱 0 · 骰子 2",Vector2(490,9),10)
	wallet.size = Vector2(140,19)
	var wallet_caption := make_label("备好工具，再往深处走",Vector2(490,31),9)
	wallet_caption.add_theme_color_override("font_color",Color("837455"))
	var bottom := Panel.new()
	bottom.position = Vector2(10,359)
	bottom.size = Vector2(620,34)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.94,0.89,0.75,0.30)
	bottom_style.border_color = Color(0.58,0.49,0.33,0.25)
	bottom_style.set_border_width_all(1)
	bottom_style.set_corner_radius_all(2)
	bottom.add_theme_stylebox_override("panel",bottom_style)
	base.add_child(bottom)
	_spawn_occluders.append(bottom)
	hint = make_label("",Vector2(19,362),11)
	hint.size = Vector2(602,17)
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice = make_label("",Vector2(19,380),9)
	notice.size = Vector2(602,13)
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice.add_theme_color_override("font_color",Color("756a4f"))
	# Keep the complete original spawn-occlusion rectangle while allowing
	# distant attack lines through the panel; outline only these two labels.
	for label: Label in [hint,notice]:
		label.add_theme_color_override("font_color",Color("fff1cd"))
		label.add_theme_color_override("font_outline_color",Color("302819"))
		label.add_theme_constant_override("outline_size",2)
	minimap = MiniMap.new()
	minimap.position = Vector2(532,61)
	minimap.size = Vector2(98,96)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.visible = false
	base.add_child(minimap)
	_spawn_occluders.append(minimap)
	boss_panel = Control.new()
	boss_panel.position = Vector2(168,59)
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(boss_panel)
	boss_name = Label.new()
	boss_name.size = Vector2(304,16)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_font_size_override("font_size",11)
	boss_name.add_theme_color_override("font_color",Color("fff1cd"))
	boss_name.add_theme_color_override("font_outline_color",Color("413426"))
	boss_name.add_theme_constant_override("outline_size",3)
	boss_panel.add_child(boss_name)
	_spawn_occluders.append(boss_name)
	boss_health = ProgressBar.new()
	boss_health.add_theme_font_size_override("font_size",1)
	boss_health.position = Vector2(0,18)
	boss_health.size = Vector2(304,7)
	boss_health.show_percentage = false
	var boss_track := StyleBoxFlat.new()
	boss_track.bg_color = Color("443e2c")
	boss_track.border_color = Color("ecd799")
	boss_track.set_border_width_all(1)
	var boss_fill := StyleBoxFlat.new()
	boss_fill.bg_color = Color("b7503e")
	boss_health.add_theme_stylebox_override("background",boss_track)
	boss_health.add_theme_stylebox_override("fill",boss_fill)
	boss_panel.add_child(boss_health)
	_spawn_occluders.append(boss_health)
	boss_health.set_deferred("size",Vector2(304,7))
	boss_panel.hide()
	overlay = Control.new()
	overlay.size = Vector2(640,400)
	overlay.visible = false
	base.add_child(overlay)
	_spawn_occluders.append(overlay)
	refresh_controls_hint("stick")
	_fit_canvas()
	get_viewport().size_changed.connect(_fit_canvas)

# CanvasLayer's native transform scales both drawing and GUI input together.
func _fit_canvas() -> void:
	var extent := get_viewport().get_visible_rect().size
	var ratio := minf(extent.x/640.0,extent.y/400.0)
	theme_value.default_font.oversampling = maxf(1.0,ratio)
	scale = Vector2.ONE*ratio
	offset = (extent-Vector2(640,400)*ratio)*0.5

func spawn_occlusion_rects() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for control: Control in _spawn_occluders:
		if not is_instance_valid(control) or not control.is_visible_in_tree(): continue
		# Include CanvasLayer scaling/offset; Control.get_global_rect alone is
		# in the logical640x400 canvas and does not match Camera3D projection.
		var rect: Rect2=control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)
		if rect.has_area(): result.append(rect)
	return result

func make_label(value: String, p: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = p
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(label)
	return label

func _process(delta: float) -> void:
	notice_time -= delta
	if notice_time <= 0:
		notice.text = "%s 地图 · %s 路线 · %s 暂停" % [input_label("map"),input_label("node_map"),input_label("pause")]

func toast(value: String) -> void:
	notice.text = value
	notice_time = 5.0
	if panel_kind == "settlement" and is_instance_valid(_settlement_notice):
		_settlement_notice.text = value
		_settlement_notice.visible = true

func update_minimap(info: Dictionary) -> void:
	minimap.visible = info.get("visible",false)
	if minimap.visible:
		minimap.info = info.duplicate(true)
		minimap.info.gate_status = gate_status_label(info)
		minimap.queue_redraw()

func show_room_map(info: Dictionary, on_select: Callable, on_close: Callable) -> void:
	close_panel()
	opened = true
	panel_kind = "map"
	overlay.visible = true
	var map_view := RoomMap.new()
	overlay.add_child(map_view)
	map_view.submission_guard = _can_submit_display.bind(_display_generation)
	var display_info := info.duplicate(true)
	display_info.close_label = "%s / %s" % [input_label("map"),input_label("pause")]
	map_view.configure(display_info,_dispatch_selection.bind(_display_generation,on_select),_dispatch_display_callback.bind(_display_generation,on_close))
	map_view.position.y = 20

func show_route_choices(info: Dictionary, on_select: Callable, on_close: Callable) -> void:
	close_panel()
	opened = true
	panel_kind = "route"
	overlay.visible = true
	var route_view := RouteChoices.new()
	overlay.add_child(route_view)
	route_view.submission_guard = _can_submit_display.bind(_display_generation)
	var display_info := info.duplicate(true)
	display_info.close_label = "%s / %s" % [input_label("node_map"),input_label("pause")]
	display_info.confirm_label = input_label("ui_accept")
	display_info.left_label = input_label("ui_left")
	display_info.right_label = input_label("ui_right")
	route_view.configure(display_info,_dispatch_selection.bind(_display_generation,on_select),_dispatch_display_callback.bind(_display_generation,on_close))
	route_view.position.y = 20

func show_toolheap(info: Dictionary, on_action: Callable, on_close: Callable) -> void:
	close_panel()
	opened = true
	panel_kind = "toolheap"
	overlay.visible = true
	var toolheap := ToolheapPanel.new()
	overlay.add_child(toolheap)
	toolheap.submission_guard = _can_submit_display.bind(_display_generation)
	toolheap.configure(info,_dispatch_selection.bind(_display_generation,on_action),_dispatch_display_callback.bind(_display_generation,on_close))

func show_panel(title: String, body: String, choices: Array, kind: String = "service") -> void:
	close_panel()
	opened = true
	panel_kind = kind
	overlay.visible = true
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.14, 0.23, 0.18, 1.0 if kind == "settlement" else 0.48)
	overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(119, 20 if choices.size()>5 else 47)
	panel.size = Vector2(402, 0)
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color("f5f1df")
	box_style.border_color = Color("a9af8c")
	box_style.set_border_width_all(1)
	box_style.set_corner_radius_all(3)
	box_style.set_content_margin_all(14)
	box_style.shadow_color = Color(0.10, 0.19, 0.13, 0.26)
	box_style.shadow_size = 5
	box_style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", box_style)
	overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4 if choices.size()>5 else 7)
	panel.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.add_theme_color_override("font_color", Color("284d40"))
	column.add_child(title_label)
	var description := Label.new()
	description.text = body
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 366
	description.add_theme_font_size_override("font_size", 11)
	description.add_theme_color_override("font_color", Color("667058"))
	column.add_child(description)
	for option in choices:
		var button := Button.new()
		button.text = option.text
		button.custom_minimum_size.y = 27
		button.add_theme_font_size_override("font_size", 11)
		button.disabled = option.get("disabled", false)
		button.pressed.connect(_dispatch_panel_action.bind(_display_generation,button,option.action))
		column.add_child(button)
		if column.get_child_count() == 3 and not button.disabled:
			button.grab_focus()
	if kind == "settlement":
		_settlement_notice = Label.new()
		_settlement_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_settlement_notice.custom_minimum_size.x = 366
		_settlement_notice.add_theme_font_size_override("font_size", 11)
		_settlement_notice.add_theme_color_override("font_color", Color("9b3f33"))
		_settlement_notice.visible = false
		column.add_child(_settlement_notice)

func close_panel() -> void:
	_display_generation += 1
	_display_submitted = false
	_settlement_notice = null
	if overlay == null:
		return
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = false
	opened = false
	panel_kind = ""

func update_boss(info: Dictionary) -> void:
	if boss_panel == null:
		return
	boss_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	boss_health.max_value = float(info.max_hp)
	boss_health.value = float(info.hp)
	boss_name.text = str(info.title)

func _dispatch_panel_action(generation: int, button: Button, action: Callable) -> void:
	if not _can_submit_display(generation) or button.disabled:
		return
	_display_submitted = true
	for control in overlay.find_children("*","Button",true,false):
		control.disabled = true
	if action.is_valid():
		action.call()

func input_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "未绑定"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if code != 0:
				return _modifier_prefix(event)+("Esc" if code==KEY_ESCAPE else OS.get_keycode_string(code))
		elif event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT: return _modifier_prefix(event)+"左键"
				MOUSE_BUTTON_RIGHT: return _modifier_prefix(event)+"右键"
				MOUSE_BUTTON_MIDDLE: return _modifier_prefix(event)+"中键"
				_: return _modifier_prefix(event)+"鼠标 %d" % event.button_index
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return event.as_text()
	return "未绑定"

func refresh_controls_hint(weapon_id: String) -> void:
	var movement := "/".join([input_label("move_up"),input_label("move_left"),input_label("move_down"),input_label("move_right")])
	var attack_label := "%s %s" % [input_label("attack"),"挥砍" if weapon_id == "stick" else "连射"]
	if weapon_id == "corn":
		attack_label += " · %s 蓄力" % input_label("charge_shot")
	controls_hint = "%s 跑动 · 松开即停 · %s · %s 互动 · %s 地图 · %s 路线 · %s 暂停" % [movement,attack_label,input_label("interact"),input_label("map"),input_label("node_map"),input_label("pause")]

func update_status(info: Dictionary) -> void:
	health.max_value = float(info.get("max_hp",100))
	health.value = float(info.get("hp",health.max_value))
	health_text.text = "体力 %d / %d" % [int(health.value),int(health.max_value)]
	heading.text = str(info.get("title","田埂上的暑假"))
	stats.text = str(info.get("weapon_label","树枝剑"))
	build_summary.text = str(info.get("build_summary","尚未强化"))
	wallet.text = "零花钱 %d · 骰子 %d" % [int(info.get("coins",0)),int(info.get("dice",0))]
	heading.tooltip_text = heading.text
	stats.tooltip_text = stats.text
	build_summary.tooltip_text = build_summary.text
	for label in [heading,stats,build_summary]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS

func show_tutorial(step: int, on_next: Callable, on_close: Callable) -> void:
	var index := clampi(step,0,2)
	var titles := ["沿田埂跑起来","路边的东西可以用","看清来路，再选前路"]
	var movement := "/".join([input_label("move_up"),input_label("move_left"),input_label("move_down"),input_label("move_right")])
	var bodies := [
		"%s 跑动，松开即停。\n朝向目标，%s 攻击。" % [movement,input_label("attack")],
		"靠近设施，按 %s 互动。\n工具堆每层只看一件，可以收下、跳过或用骰子重掷。" % input_label("interact"),
		"%s 查看本节点地图，已清房间可以回访。\n通过红房后，%s 选下一节点；选定才会离开当前节点。" % [input_label("map"),input_label("node_map")]]
	var choices := [{"text":"下一步" if index<2 else "出发吧","action":on_next},{"text":"知道了，关闭提示","action":on_close}]
	show_panel("%d / 3  ·  %s" % [index+1,titles[index]],bodies[index],choices,"tutorial")

func _dispatch_selection(value: String, generation: int, callback: Callable) -> void:
	_dispatch_display_callback(generation,callback.bind(value))

func _can_submit_display(generation: int) -> bool:
	return generation==_display_generation and not _display_submitted and (not input_guard.is_valid() or bool(input_guard.call()))

func _dispatch_display_callback(generation: int, callback: Callable) -> void:
	if not _can_submit_display(generation):
		return
	_display_submitted = true
	for control in overlay.find_children("*","Button",true,false):
		control.disabled = true
	if callback.is_valid():
		callback.call()

func gate_status_label(info: Dictionary) -> String:
	if info.get("next_unlocked",false):
		return "下一节点可选"
	if info.get("combat_locked",false):
		return "清场后开门"
	for gate in info.get("gates",[]):
		if not gate.get("open",false):
			return "清场后开门"
	return "通路已开放"

func _modifier_prefix(event: InputEventWithModifiers) -> String:
	var names: PackedStringArray = []
	if event.ctrl_pressed or (event.command_or_control_autoremap and not OS.has_feature("macos")):
		names.append("Ctrl")
	if event.alt_pressed:
		names.append("Alt")
	if event.shift_pressed:
		names.append("Shift")
	if event.meta_pressed or (event.command_or_control_autoremap and OS.has_feature("macos")):
		names.append("Meta")
	return "+".join(names)+"+" if not names.is_empty() else ""
