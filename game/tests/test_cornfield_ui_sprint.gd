extends SceneTree
var failures := 0
var selections: Array[String] = []
var closes := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures+=1

func bind_key(action: String, key: int) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action,event)

func all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result += node.text+"\n"
	for child in node.get_children(): result+=all_text(child)
	return result

func select(id: String) -> void:
	selections.append(id)

func close() -> void:
	closes+=1

func run_checks() -> void:
	root.size=Vector2i(1280,800)
	for entry in [["move_up",KEY_I],["move_left",KEY_J],["move_down",KEY_K],["move_right",KEY_L],["attack",KEY_X],["interact",KEY_F],["map",KEY_TAB],["node_map",KEY_R],["pause",KEY_ESCAPE]]:
		bind_key(entry[0],entry[1])
	var ui = load("res://scripts/cornfield/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	check(ui.has_method("input_label") and ui.has_method("refresh_controls_hint"),"UI derives controls from live InputMap")
	check(ui.has_method("show_tutorial"),"UI exposes three compact onboarding steps")
	check(ui.has_method("update_status"),"HUD accepts distinct health weapon wallet and progress data")
	if failures:
		ui.queue_free()
		await process_frame
		quit(1)
		return
	check(ui.input_label("interact")=="F" and ui.input_label("map")=="Tab","remapped physical key labels are authoritative")
	check(ui.input_label("nonexistent")=="未绑定","missing action is explicit rather than fictional key")
	bind_key("test_modified",KEY_E)
	var modified: InputEventKey = InputMap.action_get_events("test_modified")[0]
	InputMap.action_erase_events("test_modified")
	modified.ctrl_pressed = true
	InputMap.action_add_event("test_modified",modified)
	check(ui.input_label("test_modified")=="Ctrl+E","modified input labels preserve required modifiers")
	if not InputMap.has_action("test_pad"): InputMap.add_action("test_pad")
	var pad := InputEventJoypadButton.new()
	pad.button_index=JOY_BUTTON_A
	InputMap.action_add_event("test_pad",pad)
	check(ui.input_label("test_pad")!="未绑定","joypad mappings are not falsely reported as unbound")
	ui.refresh_controls_hint("stick")
	check(ui.controls_hint.contains("I") and ui.controls_hint.contains("X") and ui.controls_hint.contains("F") and ui.controls_hint.contains("Tab") and ui.controls_hint.contains("R"),"controls hint reflects remapped movement attack interact and maps")
	check(not ui.controls_hint.contains("Shift") and not ui.controls_hint.contains("冲刺"),"controls never invent walk or dash")
	ui.update_status({"hp":70,"max_hp":100,"title":"玉米地 2 / 3 · 双口水渠","weapon_label":"树枝剑","build_summary":"扫角 Ⅱ · 长度 Ⅰ","coins":24,"dice":2})
	check(ui.health.position.y+ui.health.size.y<=ui.health_text.position.y,"health bar never overlaps its numeric label")
	check(ui.health.value==70 and ui.health.max_value==100 and ui.health.position.x<ui.heading.position.x,"health takes leftmost primary HUD position")
	check(ui.wallet.text.contains("24") and ui.wallet.text.contains("2"),"money and dice are always readable together")
	check(ui.build_summary.mouse_filter==Control.MOUSE_FILTER_PASS and not ui.build_summary.tooltip_text.is_empty(),"long build summary has reachable hover details")
	check(ui.stats.text.contains("树枝剑") and ui.build_summary.text.contains("扫角"),"weapon and builds occupy their own HUD row")
	for step in 3:
		ui.show_tutorial(step,func():pass,close)
		await process_frame
		var copy := all_text(ui.overlay)
		if step==0:
			check(not copy.contains("鼠标指向") and copy.contains("朝向目标"),"tutorial does not falsely describe directional melee as mouse-aimed")
		check(copy.contains("%d / 3" % (step+1)),"tutorial step %d is numbered" % (step+1))
		check(not copy.contains("Shift") and not copy.contains("冲刺"),"tutorial step %d uses actual action vocabulary" % (step+1))
	ui.update_minimap({"visible":true,"gates":[{"pos":Vector2(1,0.5),"open":false}],"combat_locked":true})
	check(ui.minimap.info.get("gate_status","")=="清场后开门","minimap names combat-locked doors")
	ui.update_minimap({"visible":true,"gates":[{"pos":Vector2(1,0.5),"open":true}]})
	check(ui.minimap.info.get("gate_status","")=="通路已开放","minimap names traversable doors")
	ui.update_minimap({"visible":true,"gates":[],"next_unlocked":true})
	check(ui.minimap.info.get("gate_status","")=="下一节点可选","minimap names node-unlocked state separately")
	ui.show_route_choices({"floor":2,"previous_complete":true,"offers":[{"id":"REWARD","title":"收获","description":"额外补给","room_count":5}],"history":[]},select,close)
	var route = ui.overlay.get_child(0)
	check(all_text(route).contains("离开当前节点"),"route choice explains irreversible departure before selecting")
	check(all_text(route).contains("R") and not all_text(route).contains("关闭 N"),"route close hints use remapped route action")
	var choice: Button
	for b in route.find_children("*","Button",true,false):
		if b.has_meta("offer_id"): choice=b
	choice.pressed.emit()
	choice.pressed.emit()
	check(selections==["REWARD"],"route double activation dispatches only once")
	ui.show_room_map({"current":"a","rooms":[{"id":"a","grid":Vector2i.ZERO,"visited":true,"cleared":true},{"id":"b","title":"回访","grid":Vector2i.RIGHT,"visited":true,"cleared":true,"can_travel":true,"has_toolheap":true,"toolheap_resolved":false}],"links":[["a","b"]]},select,close)
	var map = ui.overlay.get_child(0)
	check(all_text(map).contains("Tab"),"room map close hint uses remapped map action")
	for b in map.find_children("*","Button",true,false):
		if b.get_meta("room_id","")=="b":
			check(b.tooltip_text.contains("工具堆可挑选"),"known available toolheap is identified in room-map tooltip")
			b.pressed.emit()
			b.pressed.emit()
	check(selections==["REWARD","b"],"map travel double activation dispatches only once")
	ui.show_panel("测试","安全恢复",[{"text":"一次","action":func():closes+=1}],"service")
	var option: Button = ui.overlay.find_children("*","Button",true,false)[0]
	option.pressed.emit()
	option.pressed.emit()
	check(closes==1,"legacy service actions also reject repeated click")
	ui.close_panel()
	root.size=Vector2i(2560,1600)
	root.content_scale_size=Vector2i(2560,1600)
	await process_frame
	check(ui.scale==Vector2(4,4),"double logical canvas retains layout and input scale")
	ui.queue_free()
	await process_frame
	print("Cornfield sprint UI: %d failures" % failures)
	quit(1 if failures else 0)
