extends Control
## Presentation only. A fresh configure/display allows exactly one callback.
## The owner commits or rejects the action and supplies the next authoritative state.
const INK := Color("423d2c")
const PAPER := Color("f3e6c8")
const OLIVE := Color("667348")
const CLAY := Color("a75739")
var info: Dictionary = {}
var _on_action: Callable
var _on_close: Callable
var _submitted := false
var submission_guard: Callable
var _buttons: Dictionary = {}

func configure(value: Dictionary, on_action: Callable, on_close: Callable) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	info = value.duplicate(true)
	_on_action = on_action
	_on_close = on_close
	_submitted = false
	_buttons.clear()
	size = Vector2(640,400)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var card := Control.new()
	card.name = "Card"
	card.position = Vector2(87,49)
	card.size = Vector2(466,302)
	add_child(card)
	_label(card,"Title","田间工具堆",Vector2(22,16),Vector2(330,24),19)
	var layer := int(info.get("layer",1))
	var total := maxi(1,int(info.get("total_layers",1)))
	_label(card,"Layer","第 %d / %d 层 · 本层只取一件" % [layer,total],Vector2(23,45),Vector2(320,17),10,Color("766a4f"))
	_add_button(card,"close","×",Vector2(411,15),Vector2(32,29),false)
	var candidate := str(info.get("candidate_id",info.get("id","")))
	var resolved := bool(info.get("resolved",false))
	var has_candidate := not candidate.is_empty() and not resolved
	var title := str(info.get("title",info.get("name","暂无可用强化"))) if has_candidate else ("这堆工具已挑选过" if resolved else "已经没有适用的强化")
	_label(card,"Candidate",title,Vector2(86,76),Vector2(350,27),18)
	var current := int(info.get("current_rank",0))
	var next := int(info.get("next_rank",mini(current+1,2)))
	var maximum := int(info.get("max_rank",2))
	var rank := "当前 %d 级  →  %d 级 / %d" % [current,next,maximum] if has_candidate else "可安心离开，继续沿田埂探索"
	_label(card,"Rank",rank,Vector2(87,106),Vector2(350,18),11,OLIVE)
	var effect := str(info.get("change_text",""))
	if effect.is_empty() and info.has("effect_before") and info.has("effect_after"):
		effect = "%s → %s" % [info.effect_before,info.effect_after]
	if effect.is_empty():
		effect = "暂无效果说明，不能领取" if has_candidate else "跳过不消耗骰子"
	_label(card,"Effect",effect,Vector2(23,143),Vector2(420,25),15,INK)
	var scope := str(info.get("scope","weapon"))
	var weapon := str(info.get("weapon_label","树枝剑" if info.get("weapon_id","stick")=="stick" else "玉米枪"))
	var description := str(info.get("description",""))
	var applies := "本局通用" if scope=="global" else "适用："+weapon
	var detail := _label(card,"Description",applies+" · "+description if has_candidate else "关闭面板也不会领取或消耗任何东西。",Vector2(23,177),Vector2(420,34),11,Color("746b52"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dice := maxi(0,int(info.get("dice",0)))
	_label(card,"Dice","骰子 %d 枚" % dice,Vector2(24,218),Vector2(145,20),12,OLIVE)
	_label(card,"Cost","重掷消耗 1 枚 · 跳过不消耗",Vector2(191,220),Vector2(255,18),10,Color("766a4f"))
	var has_effect: bool = not str(info.get("change_text","")).strip_edges().is_empty() or (not str(info.get("effect_before","")).strip_edges().is_empty() and not str(info.get("effect_after","")).strip_edges().is_empty())
	_add_button(card,"accept","收下强化",Vector2(23,249),Vector2(143,32),not has_candidate or not has_effect or current>=maximum or next<=current)
	_add_button(card,"reroll","重掷 · 1 骰子",Vector2(176,249),Vector2(137,32),not has_candidate or dice<1 or not bool(info.get("can_reroll",true)))
	_add_button(card,"skip","跳过这一层",Vector2(323,249),Vector2(120,32),resolved)
	# Start at the non-mutating exit, so a buffered confirm cannot accept a build.
	_buttons.close.grab_focus()
	queue_redraw()

func _label(parent: Control, node_name: String, value: String, at: Vector2, extent: Vector2, font_size: int, color: Color=INK) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.position = at
	label.size = extent
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _add_button(parent: Control, action: String, title: String, at: Vector2, extent: Vector2, disabled: bool) -> void:
	var button := Button.new()
	button.name = action.capitalize()
	button.text = title
	button.position = at
	button.size = extent
	button.disabled = disabled
	button.add_theme_font_size_override("font_size",11 if action!="close" else 19)
	button.set_meta("toolheap_action",action)
	if action=="close":
		button.set_meta("close_panel",true)
	button.pressed.connect(_submit.bind(action))
	parent.add_child(button)
	_buttons[action] = button

func _submit(action: String) -> void:
	if (submission_guard.is_valid() and not bool(submission_guard.call())) or _submitted or not _buttons.has(action) or _buttons[action].disabled:
		return
	_submitted = true
	for button in _buttons.values():
		button.disabled = true
	if action=="close":
		if _on_close.is_valid():
			_on_close.call()
	elif _on_action.is_valid():
		_on_action.call(action)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.12,0.15,0.10,0.60))
	var at := Vector2(87,49)
	draw_rect(Rect2(at+Vector2(3,5),Vector2(466,302)),Color(0.10,0.11,0.07,0.32))
	draw_rect(Rect2(at,Vector2(466,302)),PAPER)
	draw_rect(Rect2(at,Vector2(466,302)),INK,false,2)
	draw_rect(Rect2(at+Vector2(7,7),Vector2(452,288)),Color("c6b58c"),false,1)
	draw_line(at+Vector2(22,67),at+Vector2(443,67),Color("c6b58c"),1)
	draw_rect(Rect2(at+Vector2(18,135),Vector2(430,37)),Color("e6d7b3"))
	for corner in [Vector2(11,11),Vector2(455,11),Vector2(11,291),Vector2(455,291)]:
		draw_circle(at+corner,1.5,Color("9c7a48"))
	# Original hand-made branch and sickle mark, not an imported interface asset.
	var center := at+Vector2(49,99)
	draw_circle(center,25,Color("dbcfaa"))
	draw_line(center+Vector2(-14,18),center+Vector2(12,-17),Color("846444"),5)
	draw_line(center+Vector2(-13,17),center+Vector2(12,-16),Color("b2925d"),2)
	draw_line(center+Vector2(3,-3),center+Vector2(-5,-13),Color("846444"),3)
	draw_arc(center+Vector2(3,-5),15,-1.7,0.95,16,OLIVE,4)
	draw_line(center+Vector2(-16,9),center+Vector2(9,15),CLAY,3)
