extends Control

const INK := Color("294d42")
const PAPER := Color("f5f0da")
const OCHRE := Color("b78f47")

var _floor := 1
var _previous_complete := false
var _centers: Array[float] = []
var _has_history := false
var _submitted := false
var submission_guard: Callable


class RoomChoice extends Button:
	var room_kind := "EVENT"
	var preview_rooms: Dictionary = {}
	var preview_links: Array = []
	var history_status := ""
	const OUTLINE := Color("294d42")
	const GOLD := Color("c39c4d")
	const CLAY := Color("b66d48")

	func _ready() -> void:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var active := not disabled and (has_focus() or is_hovered())
		if history_status == "selected":
			draw_rect(Rect2(Vector2.ZERO,size),Color("eee3bd"))
			draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),GOLD,false,1)
		draw_rect(Rect2(5,25,136,64),_palette(Color("eee1b8") if active else Color("e6dfc1")))
		draw_rect(Rect2(5,25,136,64),_palette(GOLD if active or history_status == "selected" else Color("b8b28b")),false,1)
		# A route offer communicates its type, not unexplored room geometry.
		_draw_symbol(Vector2(73,61))
		draw_set_transform(Vector2(73,13),0,Vector2.ONE*0.42)
		_draw_symbol(Vector2.ZERO)
		draw_set_transform(Vector2.ZERO)

	func _palette(color: Color) -> Color:
		if history_status != "declined":
			return color
		var grey := color.get_luminance()
		return Color(grey,grey,grey).lerp(Color("e3e0d1"),0.35)

	func _draw_symbol(center: Vector2) -> void:
		match room_kind:
			"BOSS":
				for index in range(5):
					var point := center+Vector2((index-2)*8,abs(index-2)*3)
					draw_circle(point,10,_palette(OUTLINE))
					draw_circle(point+Vector2(0,-2),7,_palette(CLAY))
					draw_line(point+Vector2(-4,5),point+Vector2(-7,13),_palette(OUTLINE),3)
					draw_line(point+Vector2(4,5),point+Vector2(7,13),_palette(OUTLINE),3)
				draw_circle(center+Vector2(-20,-1),2,_palette(GOLD))
				draw_line(center+Vector2(-22,-9),center+Vector2(-28,-19),_palette(GOLD),3)
				draw_line(center+Vector2(-15,-10),center+Vector2(-14,-21),_palette(GOLD),3)
			"SHOP":
				draw_rect(Rect2(center+Vector2(-17,-4),Vector2(34,25)),_palette(OUTLINE))
				draw_rect(Rect2(center+Vector2(-14,-1),Vector2(28,18)),_palette(GOLD))
				draw_colored_polygon(PackedVector2Array([center+Vector2(-23,-5),center+Vector2(-15,-18),center+Vector2(15,-18),center+Vector2(23,-5)]),_palette(CLAY))
				draw_rect(Rect2(center+Vector2(-4,3),Vector2(8,14)),_palette(OUTLINE))
			"ANVIL":
				var anvil := PackedVector2Array([
					center + Vector2(-22, -5), center + Vector2(20, -5),
					center + Vector2(10, 4), center + Vector2(5, 4),
					center + Vector2(5, 10), center + Vector2(16, 15),
					center + Vector2(-15, 15), center + Vector2(-5, 10),
					center + Vector2(-5, 4), center + Vector2(-14, 4)
				])
				draw_colored_polygon(anvil, _palette(OUTLINE))
				draw_line(center + Vector2(4, -21), center + Vector2(-4, -9), _palette(CLAY), 4)
				draw_rect(Rect2(center + Vector2(-2, -23), Vector2(15, 7)), _palette(GOLD))
			"LEVEL":
				draw_rect(Rect2(center + Vector2(-22, 9), Vector2(13, 8)), _palette(OUTLINE))
				draw_rect(Rect2(center + Vector2(-8, 3), Vector2(13, 14)), _palette(OUTLINE))
				draw_rect(Rect2(center + Vector2(6, -3), Vector2(13, 20)), _palette(OUTLINE))
				draw_line(center + Vector2(-6, -3), center + Vector2(-6, -21), _palette(GOLD), 4)
				draw_polyline(PackedVector2Array([center + Vector2(-13, -14), center + Vector2(-6, -21), center + Vector2(1, -14)]), _palette(GOLD), 3)
			"REWARD":
				draw_rect(Rect2(center + Vector2(-20, -12), Vector2(40, 29)), _palette(OUTLINE))
				draw_rect(Rect2(center + Vector2(-17, -9), Vector2(34, 23)), _palette(GOLD))
				draw_line(center + Vector2(-17, 0), center + Vector2(17, 0), _palette(OUTLINE), 3)
				draw_rect(Rect2(center + Vector2(-4, -4), Vector2(8, 11)), _palette(Color("f8ebbc")))
				draw_line(center + Vector2(-10, -19), center + Vector2(-10, -15), _palette(GOLD), 2)
				draw_line(center + Vector2(10, -20), center + Vector2(10, -15), _palette(GOLD), 2)
			"ELITE":
				for side in [-1, 1]:
					for offset in [-8, 1, 10]:
						draw_polyline(PackedVector2Array([center + Vector2(side * 9, offset), center + Vector2(side * 20, offset - 4), center + Vector2(side * 24, offset + 2)]), _palette(OUTLINE), 3)
				draw_circle(center + Vector2(0, 1), 15, _palette(OUTLINE))
				draw_circle(center + Vector2(0, 2), 11, _palette(CLAY))
				draw_line(center + Vector2(0, -8), center + Vector2(0, 12), _palette(GOLD), 2)
				draw_circle(center + Vector2(0, -14), 7, _palette(OUTLINE))
				draw_polyline(PackedVector2Array([center + Vector2(-7, -25), center + Vector2(-5, -19), center + Vector2(5, -19), center + Vector2(7, -25)]), _palette(GOLD), 3)
			_:
				draw_rect(Rect2(center + Vector2(-17, -20), Vector2(34, 38)), _palette(OUTLINE))
				draw_rect(Rect2(center + Vector2(-14, -17), Vector2(28, 32)), _palette(Color("faf0cf")))
				draw_line(center + Vector2(-20, -19), center + Vector2(20, -19), _palette(GOLD), 4)
				draw_line(center + Vector2(-20, 18), center + Vector2(20, 18), _palette(GOLD), 4)
				draw_string(get_theme_default_font(), center + Vector2(-7, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, _palette(CLAY))


func configure(info: Dictionary, on_select: Callable, on_close: Callable) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_submitted = false
	_floor = int(info.get("floor", 1))
	_previous_complete = bool(info.get("previous_complete", false))
	var history: Array = info.get("history", [])
	_has_history = not history.is_empty()
	_centers.clear()
	_label("前方的田埂", Vector2(58, 34), Vector2(360, 28), 20)
	_label("第 %d 节点 · 选定后离开当前节点，请先拾取补给" % _floor if _previous_complete else "第 %d 节点 · 选择一片田地，立即开始探索" % _floor, Vector2(60, 64), Vector2(455, 20), 11, Color("737453"))
	var close := Button.new()
	close.text = "关闭 " + str(info.get("close_label",""))
	close.position = Vector2(480, 36)
	close.size = Vector2(111, 24)
	close.add_theme_font_size_override("font_size", 11)
	close.set_meta("close_panel", true)
	close.pressed.connect(_dispatch.bind(on_close))
	add_child(close)
	var offers: Array = info.get("offers", [])
	var choice_buttons: Array[Button] = []
	if _has_history:
		choice_buttons = _create_history(history,offers,on_select)
	else:
		for index in range(mini(offers.size(), 3)):
			var center_x := 320.0 + (float(index)-(mini(offers.size(),3)-1)*.5)*175.0
			_centers.append(center_x)
			choice_buttons.append(_create_choice(offers[index],Vector2(center_x-73,88),self,on_select))
	for index in range(choice_buttons.size()):
		var choice := choice_buttons[index]
		choice.focus_neighbor_left = choice.get_path_to(choice_buttons[posmod(index - 1, choice_buttons.size())])
		choice.focus_neighbor_right = choice.get_path_to(choice_buttons[(index + 1) % choice_buttons.size()])
		choice.focus_neighbor_top = choice.get_path_to(close)
		choice.focus_neighbor_bottom = choice.get_path_to(close)
	if not choice_buttons.is_empty():
		choice_buttons[0].grab_focus()
	if not _has_history:
		var current := _label("红色房间已通过 · 可继续探索" if _previous_complete else "从这里出发", Vector2(215, 298), Vector2(210, 18), 10, Color("687254"))
		current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help := _label("%s / %s 选择    %s 确认    %s 关闭" % [info.get("left_label","←"),info.get("right_label","→"),info.get("confirm_label","确认键"),info.get("close_label","")], Vector2(150, 321), Vector2(340, 16), 10, Color("818066"))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_redraw()


func _create_choice(offer: Dictionary, location: Vector2, parent: Control, on_select: Callable, history_floor: int = 0, selected_id: String = "") -> RoomChoice:
	var choice := RoomChoice.new()
	choice.room_kind = str(offer.get("id", "EVENT"))
	choice.position = location
	choice.size = Vector2(146,162)
	choice.tooltip_text = str(offer.get("title", "")) + "：" + str(offer.get("description", ""))
	if history_floor > 0:
		choice.name = "History_%d_%s" % [history_floor,choice.room_kind]
		choice.history_status = "selected" if choice.room_kind == selected_id else "declined"
		choice.disabled = true
		choice.focus_mode = Control.FOCUS_NONE
		choice.set_meta("historical_offer_id",choice.room_kind)
		choice.set_meta("history_floor",history_floor)
	else:
		choice.name = "Offer_" + choice.room_kind
		choice.focus_mode = Control.FOCUS_ALL
		choice.set_meta("offer_id",choice.room_kind)
		choice.pressed.connect(_dispatch.bind(on_select.bind(choice.room_kind)))
	for state in ["normal", "hover", "pressed", "disabled"]:
		choice.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = Color("c39c4d")
	focus_style.set_border_width_all(1)
	focus_style.set_corner_radius_all(3)
	choice.add_theme_stylebox_override("focus",focus_style)
	parent.add_child(choice)
	var title_color := Color("92938a") if choice.history_status == "declined" else INK
	var title := _label(str(offer.get("title", "未知田埂")),Vector2(8,90),Vector2(130,20),13,title_color,choice)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var description := _label(str(offer.get("description", "")),Vector2(8,111),Vector2(130,33),10,Color("93948b") if choice.history_status == "declined" else Color("667058"),choice)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	# _label initially measures unwrapped text; reset bounds after enabling wrap.
	description.clip_text = true
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.size = Vector2(130,33)
	var room_count := int(offer.get("room_count",maxi(1,choice.preview_rooms.size())))
	var hint := "%s 个房间 · 点击即进入" % room_count
	if history_floor > 0:
		hint = "%s 个房间 · %s" % [room_count,"已走过" if choice.history_status == "selected" else "放弃"]
	var entry_hint := _label(hint,Vector2(3,146),Vector2(140,15),9,Color("92938a") if choice.history_status == "declined" else Color("916d37"),choice)
	entry_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return choice


func _create_history(history: Array, offers: Array, on_select: Callable) -> Array[Button]:
	var summary_parts: PackedStringArray = []
	for entry in history:
		var selected_title := "历史未记录"
		for offer in entry.get("offers",[]):
			if str(offer.get("id","")) == str(entry.get("selected","")):
				selected_title = str(offer.get("title","已走过"))
				break
		summary_parts.append("第%d层 %s" % [int(entry.get("floor",1)),selected_title])
	var summary := _label("已走过：" + " → ".join(summary_parts),Vector2(60,88),Vector2(345,18),10,Color("7e6d45"))
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.tooltip_text = summary.text
	summary.mouse_filter = Control.MOUSE_FILTER_PASS
	_label("↑ 向上滚动回看 · 历史不可选",Vector2(414,88),Vector2(172,18),10,Color("737453"))
	var scroll := ScrollContainer.new()
	scroll.name = "RouteHistoryScroll"
	scroll.position = Vector2(58,111)
	scroll.size = Vector2(526,204)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_NONE
	add_child(scroll)
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",10)
	scroll.add_child(rows)
	for entry in history:
		var floor_number := int(entry.get("floor",1))
		var row := Control.new()
		row.name = "HistoryFloor_%d" % floor_number
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var historical_offers: Array = entry.get("offers",[])
		var unavailable := bool(entry.get("unavailable",false)) or historical_offers.is_empty()
		row.custom_minimum_size = Vector2(510,46 if unavailable else 188)
		rows.add_child(row)
		if unavailable:
			_label("第%d层 历史未记录" % floor_number,Vector2(14,4),Vector2(476,18),11,Color("92938a"),row)
			_label("本层路线无法回看",Vector2(14,23),Vector2(476,16),9,Color("92938a"),row)
			continue
		_label("第 %d 层 · 已走过的田埂" % floor_number,Vector2(14,0),Vector2(476,20),11,Color("7e6d45"),row)
		for index in range(mini(historical_offers.size(),3)):
			_create_choice(historical_offers[index],Vector2(14+index*175,24),row,Callable(),floor_number,str(entry.get("selected","")))
	var current_row := Control.new()
	current_row.name = "CurrentFloor"
	current_row.custom_minimum_size = Vector2(510,204)
	current_row.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_child(current_row)
	_label("第 3 层 · 前往巨型玉米螟巢" if _floor == 3 else "第 %d 层 · 选择下一片田地" % _floor,Vector2(14,0),Vector2(476,20),11,INK,current_row)
	var choices: Array[Button] = []
	for index in range(mini(offers.size(),3)):
		var slot_x := 14.0 + (float(index)+(3-mini(offers.size(),3))*.5)*175.0
		choices.append(_create_choice(offers[index],Vector2(slot_x,24),current_row,on_select))
	_scroll_to_current.call_deferred(scroll,current_row)
	return choices


func _scroll_to_current(scroll: ScrollContainer, current_row: Control) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(scroll) or not is_instance_valid(current_row):
		return
	if scroll.is_inside_tree() and current_row.is_inside_tree():
		scroll.ensure_control_visible(current_row)


func _label(value: String, location: Vector2, extent: Vector2, font_size: int, color: Color = INK, parent: Control = self) -> Label:
	var label := Label.new()
	label.text = value
	label.position = location
	label.size = extent
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _draw() -> void:
	draw_rect(Rect2(0, -20, 640, 400), Color(0.14, 0.23, 0.18, 0.48))
	draw_rect(Rect2(34, 25, 580, 320), Color(0.10, 0.19, 0.13, 0.20))
	draw_rect(Rect2(30, 20, 580, 320), PAPER)
	draw_rect(Rect2(30, 20, 580, 320), INK, false, 2)
	draw_rect(Rect2(37, 27, 566, 306), Color("c9bd91"), false, 1)
	draw_line(Vector2(58, 85), Vector2(582, 85), Color("d2c7a2"), 1)
	for corner in [Vector2(40, 30), Vector2(600, 30), Vector2(40, 330), Vector2(600, 330)]:
		draw_circle(corner, 2, OCHRE)
	if _has_history:
		return
	for center_x in _centers:
		var bend := Vector2(center_x, 260)
		draw_dashed_line(Vector2(320, 270), bend, OCHRE, 2.0, 5.0)
		draw_dashed_line(bend, Vector2(center_x, 254), OCHRE, 2.0, 4.0)
		draw_circle(Vector2(center_x, 254), 2, INK)
	draw_rect(Rect2(302, 270, 36, 23), Color("d6c891"))
	draw_rect(Rect2(302, 270, 36, 23), INK, false, 2)
	draw_colored_polygon(PackedVector2Array([Vector2(320, 274), Vector2(326, 281), Vector2(320, 288), Vector2(314, 281)]), INK)
	draw_circle(Vector2(320, 281), 2, Color("f2e9ba"))


func _dispatch(callback: Callable) -> void:
	if (submission_guard.is_valid() and not bool(submission_guard.call())) or _submitted:
		return
	_submitted = true
	for button in find_children("*","Button",true,false):
		button.disabled = true
	if callback.is_valid():
		callback.call()
