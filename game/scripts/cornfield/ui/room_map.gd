extends Control

const INK := Color("3d5140")
const OCHRE := Color("b38958")
var info: Dictionary = {}
var locations: Dictionary = {}
var room_extents: Dictionary = {}
var revealed: Dictionary = {}
var on_select: Callable
var _submitted := false
var submission_guard: Callable

class RoomNode extends Button:
	var room: Dictionary = {}
	var current := false

	func _draw() -> void:
		var known: bool = room.get("visited", false)
		var completion: bool = room.get("completion",false)
		var labelled := size.y >= 42
		var area := Rect2(4,3,size.x-8,size.y-(19 if labelled else 6))
		var world_size: Vector2 = room.get("size",Vector2(1120,736))
		var proportions := Vector2(clampf(world_size.x/1280.0,0.7,1.0),clampf(world_size.y/800.0,0.7,1.0))
		var extent := area.size * proportions
		var origin := area.get_center()-extent*0.5
		var points := PackedVector2Array()
		var outline: Array = room.get("outline",[Vector2(0.07,0),Vector2(0.77,0),Vector2(0.77,0.13),Vector2(1,0.13),Vector2(1,0.86),Vector2(0.86,0.86),Vector2(0.86,1),Vector2(0.1,1),Vector2(0.1,0.84),Vector2(0,0.84),Vector2(0,0.2),Vector2(0.07,0.2)])
		for point in outline:
			points.append(origin+point*extent)
		var paper := Color("e0c798") if known else Color("e7d7b7")
		if current:
			paper = Color("d0d4a0")
		if completion:
			paper = Color("e7aaa0") if known else Color("e4b9a6")
		draw_colored_polygon(points, paper)
		var contour := points.duplicate()
		contour.append(points[0])
		draw_polyline(contour, Color("ad493d") if completion else (Color("53634b") if known else Color("bba37e")), 2.0)
		if known:
			for gate in room.get("gates",[]):
				var gate_at: Vector2 = origin+Vector2(gate.get("pos",Vector2.ZERO)).clamp(Vector2.ZERO,Vector2.ONE)*extent
				var vertical: bool = str(gate.get("side","")) in ["east","west"]
				var half := Vector2(0,3) if vertical else Vector2(3,0)
				draw_line(gate_at-half,gate_at+half,Color("f3e3b9"),5)
				draw_line(gate_at-half,gate_at+half,Color("768a50") if gate.get("open",false) else Color("8c6744"),3)
				if not gate.get("open",false):
					draw_line(gate_at-Vector2(1.5,1.5),gate_at+Vector2(1.5,1.5),Color("faeac1"),1.5)
		if current or has_focus() or (is_hovered() and not disabled):
			draw_rect(Rect2(origin,extent).grow(2), Color("fff4bd") if current else Color("b78936"), false, 2)
		if not known and not completion:
			draw_string(get_theme_font("font"),Vector2(0,area.get_center().y+6),"?",HORIZONTAL_ALIGNMENT_CENTER,size.x,18 if labelled else 13,Color("aa9874"))
		elif labelled:
			var symbol_scale := minf(0.85,minf(extent.x/36.0,extent.y/34.0))
			draw_set_transform(area.get_center()-Vector2(44,31)*symbol_scale,0,Vector2.ONE*symbol_scale)
			_draw_symbol(str(room.get("kind", room.get("id", "fight"))))
			draw_set_transform(Vector2.ZERO)
		var title: String = str(room.get("title", "田埂")) if known else ("红色通关房" if completion else "未探索")
		if labelled or known:
			var font_size := 9 if size.x >= 48 else 8
			var available_characters := maxi(2,int(size.x/font_size))
			if title.length()>available_characters:
				title = title.left(available_characters-1)+"…"
			draw_string(get_theme_font("font"),Vector2(0,size.y-3 if labelled else size.y*0.5+3),title,HORIZONTAL_ALIGNMENT_CENTER,size.x,font_size,Color("43513f") if known else Color("9b8e70"))
		if known and room.get("has_toolheap",false) and not room.get("toolheap_resolved",false):
			var tool_at := origin+Vector2(5,6)
			draw_circle(tool_at,5,Color("f1d789"))
			draw_line(tool_at+Vector2(-2,3),tool_at+Vector2(2,-3),Color("705734"),2)
			draw_line(tool_at+Vector2(-1,-2),tool_at+Vector2(3,-1),Color("705734"),2)
		if current:
			draw_circle(origin+Vector2(extent.x-3,3),3,Color("f9f5d5"))
			draw_circle(origin+Vector2(extent.x-3,3),1.5,Color("4e7b45"))

	func _draw_symbol(kind: String) -> void:
		var ink := Color("5e6343")
		var at := Vector2(44,31)
		if kind.to_lower() in ["start", "shelter"]:
			draw_colored_polygon(PackedVector2Array([at+Vector2(-14,-2),at+Vector2(0,-13),at+Vector2(14,-2)]), Color("887044"))
			draw_rect(Rect2(at+Vector2(-10,-1),Vector2(20,14)), Color("bc9a61"))
			draw_rect(Rect2(at+Vector2(-3,4),Vector2(6,9)), ink)
		elif kind.to_lower() == "shop":
			draw_rect(Rect2(at+Vector2(-13,-3),Vector2(26,16)),Color("b78c53"))
			draw_colored_polygon(PackedVector2Array([at+Vector2(-17,-3),at+Vector2(-11,-14),at+Vector2(11,-14),at+Vector2(17,-3)]),Color("e4c27e"))
			draw_line(at+Vector2(-13,-3),at+Vector2(13,-3),ink,2)
			for x in [-7,0,7]:
				draw_rect(Rect2(at+Vector2(x-2,0),Vector2(4,7)),Color("6d8651"))
		elif kind.to_lower() in ["exit", "gate", "boss", "completion"]:
			draw_line(at+Vector2(-8,13),at+Vector2(-8,-14),ink,3)
			draw_colored_polygon(PackedVector2Array([at+Vector2(-6,-14),at+Vector2(14,-10),at+Vector2(-6,-3)]),Color("b64739"))
		elif kind.to_lower() in ["optional", "tree", "event"]:
			draw_rect(Rect2(at+Vector2(-2,0),Vector2(5,14)), Color("8b6e48"))
			for p in [Vector2(-7,-3),Vector2(7,-3),Vector2(0,-10)]:
				draw_circle(at+p,8,Color("7c8952"))
		elif kind.to_lower() in ["reward", "objective", "anvil", "level"]:
			draw_rect(Rect2(at+Vector2(-11,-7),Vector2(22,19)), Color("ad8c4f"))
			draw_rect(Rect2(at+Vector2(-11,-7),Vector2(22,19)), ink,false,2)
			draw_line(at+Vector2(-10,0),at+Vector2(10,0),ink,2)
			draw_rect(Rect2(at+Vector2(-2,-2),Vector2(4,6)),Color("e6c475"))
		else:
			draw_circle(at,9,Color("879151"))
			draw_line(at+Vector2(0,-8),at+Vector2(0,8),ink,2)
			for side in [-1,1]:
				for y in [-6,0,6]:
					draw_line(at+Vector2(side*7,y),at+Vector2(side*14,y-3),ink,2)

func configure(value: Dictionary, select: Callable, close: Callable) -> void:
	_submitted = false
	info = value.duplicate(true)
	# Service rooms are outside this node, never standalone map destinations.
	info.rooms = info.get("rooms",[]).filter(func(room): return room.get("id","") != "start")
	on_select = select
	size = Vector2(640,360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var explored: Dictionary = {}
	for room in info.get("rooms", []):
		if room.get("visited", false) or room.id == info.get("current", ""):
			explored[room.id] = true
	revealed = explored.duplicate()
	for link in info.get("links", []):
		if explored.has(link[0]):
			revealed[link[1]] = true
		if explored.has(link[1]):
			revealed[link[0]] = true
	# Never hand hidden outlines, proportions, symbols, or deep branches to cards.
	var visible_rooms: Array = []
	for room in info.rooms:
		if not revealed.has(room.id):
			continue
		if explored.has(room.id):
			room.visited = true
			visible_rooms.append(room)
		else:
			visible_rooms.append({"id":room.id,"grid":room.get("grid",Vector2i.ZERO),"visited":false,"completion":room.get("completion",false)})
	info.rooms = visible_rooms
	info.links = info.get("links",[]).filter(func(link): return revealed.has(link[0]) and revealed.has(link[1]) and (explored.has(link[0]) or explored.has(link[1])))
	_layout_rooms()
	var first: Button
	for room in info.get("rooms", []):
		if not revealed.has(room.id):
			continue
		var button := RoomNode.new()
		button.room = room
		button.current = room.id == info.get("current", "")
		button.position = locations[room.id] - room_extents[room.id]*0.5
		button.size = room_extents[room.id]
		button.set_meta("room_id", room.id)
		button.tooltip_text = str(room.get("title", "")) if room.get("visited", false) else "未探索的田埂"
		if room.get("visited",false) and not str(room.get("service_title","")).is_empty():
			button.tooltip_text += "\n"+str(room.service_title)+(" · 已处理" if room.get("service_resolved",false) and not room.get("service_repeatable",false) else " · 可互动")
			button.tooltip_text += "\n"+str(room.get("service_description",""))
		if room.get("visited",false) and room.get("has_toolheap",false):
			button.tooltip_text += " · 工具堆已用" if room.get("toolheap_resolved",false) else " · 工具堆可挑选"
		button.disabled = not _can_travel(room)
		button.focus_mode = Control.FOCUS_ALL
		for state in ["normal","hover","pressed","disabled","focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_request_travel.bind(room))
		button.focus_entered.connect(button.queue_redraw)
		button.focus_exited.connect(button.queue_redraw)
		button.mouse_entered.connect(button.queue_redraw)
		button.mouse_exited.connect(button.queue_redraw)
		add_child(button)
		if first == null and not button.disabled:
			first = button
	var close_button := Button.new()
	close_button.text = "收起地图  " + str(info.get("close_label",""))
	close_button.position = Vector2(452,307)
	close_button.size = Vector2(158,25)
	close_button.add_theme_font_size_override("font_size",10)
	close_button.set_meta("close_panel", true)
	close_button.pressed.connect(_dispatch.bind(close))
	add_child(close_button)
	if first != null:
		first.grab_focus()
	else:
		close_button.grab_focus()
	queue_redraw()

func _layout_rooms() -> void:
	locations.clear()
	room_extents.clear()
	var grid_positions: Dictionary = {}
	var defaults := {"fight_a":Vector2i(0,0),"fight_b":Vector2i(1,0),"objective":Vector2i(2,0),"exit":Vector2i(3,0),"optional":Vector2i(1,1)}
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for room in info.get("rooms", []):
		if not revealed.has(room.id):
			continue
		var at := Vector2(room.get("grid",defaults.get(room.id,Vector2i(grid_positions.size(),0))))
		grid_positions[room.id] = at
		minimum = minimum.min(at)
		maximum = maximum.max(at)
	if grid_positions.is_empty():
		return
	var graph_area := Rect2(40,88,558,208)
	var cells := maximum-minimum+Vector2.ONE
	var step := Vector2(minf(94,graph_area.size.x/cells.x),minf(67,graph_area.size.y/cells.y))
	var origin := graph_area.get_center()-(minimum+maximum)*step*0.5
	for id in grid_positions:
		locations[id] = origin + grid_positions[id]*step
		room_extents[id] = step*Vector2(0.84,0.82)

func _can_travel(room: Dictionary) -> bool:
	return not info.get("combat_locked",false) and room.get("visited",false) and room.get("cleared",false) and room.get("can_travel",false) and room.id != info.get("current", "")

func _request_travel(room: Dictionary) -> void:
	if _can_travel(room):
		_dispatch(on_select.bind(str(room.id)))

func _draw() -> void:
	draw_rect(Rect2(0,-20,640,400),Color(0.10,0.16,0.13,0.56))
	var paper := PackedVector2Array([Vector2(16,16),Vector2(135,16),Vector2(138,19),Vector2(259,16),Vector2(403,16),Vector2(407,19),Vector2(621,16),Vector2(624,340),Vector2(502,340),Vector2(499,337),Vector2(321,341),Vector2(181,338),Vector2(18,341)])
	draw_colored_polygon(paper,Color("ecd7ad"))
	var edge := paper.duplicate()
	edge.append(paper[0])
	draw_polyline(edge,INK,3)
	draw_rect(Rect2(24,25,592,307),Color("c5a576"),false,1)
	draw_string(get_theme_font("font"),Vector2(37,52),"田埂地图",HORIZONTAL_ALIGNMENT_LEFT,-1,19,INK)
	var subtitle := "第 %s 层 · %s" % [info.get("floor",1),info.get("node_title","这一节点走过的路")]
	draw_string(get_theme_font("font"),Vector2(39,70),subtitle,HORIZONTAL_ALIGNMENT_LEFT,450,10,Color("8c7855"))
	for link in info.get("links", []):
		if "start" in link or not locations.has(link[0]) or not locations.has(link[1]):
			continue
		var a: Vector2 = locations[link[0]]
		var b: Vector2 = locations[link[1]]
		draw_line(a,b,OCHRE,3)
		draw_line(a+Vector2(0,2),b+Vector2(0,2),Color("f6e4c3"),1)
	var caption := "点击已探索且清空的房间，即可前往。"
	if info.get("combat_locked", false):
		caption = "先清空当前房间，再沿田埂前往别处。"
	draw_string(get_theme_font("font"),Vector2(38,323),caption,HORIZONTAL_ALIGNMENT_LEFT,400,10,INK)
	draw_circle(Vector2(335,47),5,Color("f1d789"))
	draw_line(Vector2(333,50),Vector2(337,44),Color("705734"),2)
	draw_line(Vector2(334,45),Vector2(338,46),Color("705734"),2)
	draw_string(get_theme_font("font"),Vector2(345,51),"工具可取",HORIZONTAL_ALIGNMENT_LEFT,-1,9,INK)
	draw_circle(Vector2(535,47),3,Color("6d874a"))
	draw_string(get_theme_font("font"),Vector2(544,51),"当前位置",HORIZONTAL_ALIGNMENT_LEFT,-1,9,INK)
	draw_rect(Rect2(423,43,7,7),Color("b64739"))
	draw_string(get_theme_font("font"),Vector2(435,51),"红色通关房",HORIZONTAL_ALIGNMENT_LEFT,-1,9,INK)

func _dispatch(callback: Callable) -> void:
	if (submission_guard.is_valid() and not bool(submission_guard.call())) or _submitted:
		return
	_submitted = true
	for button in find_children("*","Button",true,false):
		button.disabled = true
	if callback.is_valid():
		callback.call()
