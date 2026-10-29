extends SceneTree

var failures := 0
var actions: Array[String] = []
var closes := 0

func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run_checks")

func sample_info(dice: int = 2) -> Dictionary:
	return {"id":"arc","name":"扫开一片","description":"加宽树枝横扫的有效范围。","current_rank":1,"next_rank":2,"max_rank":2,"change_text":"横扫角度：+12° → +24°","scope":"weapon","weapon_id":"stick","dice":dice,"layer":1,"total_layers":1}

func _action(action: String) -> void:
	actions.append(action)

func _close() -> void:
	closes += 1

func button(panel: Node, action: String) -> Button:
	for candidate in panel.find_children("*","Button",true,false):
		if candidate.get_meta("toolheap_action","") == action:
			return candidate
	return null

func run_checks() -> void:
	root.size = Vector2i(1280,800)
	var ui = load("res://scripts/cornfield/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	check(ui.has_method("show_toolheap"),"UI exposes single-candidate toolheap without owning game state")
	if not ui.has_method("show_toolheap"):
		ui.queue_free()
		await process_frame
		quit(1)
		return
	ui.show_toolheap(sample_info(0),_action,_close)
	await process_frame
	var panel = ui.overlay.get_child(0)
	check(ui.panel_kind == "toolheap" and ui.opened,"toolheap uses normal modal lifecycle")
	check(button(panel,"reroll").disabled,"zero dice disables reroll")
	check(panel.get_node("Card/Rank").text.contains("1") and panel.get_node("Card/Rank").text.contains("2"),"candidate shows current and next rank")
	check(panel.get_node("Card/Effect").text == "横扫角度：+12° → +24°","candidate shows precise authoritative numeric effect")
	button(panel,"reroll").pressed.emit()
	check(actions.is_empty(),"programmatic press cannot bypass disabled reroll")
	button(panel,"accept").pressed.emit()
	button(panel,"accept").pressed.emit()
	button(panel,"skip").pressed.emit()
	check(actions == ["accept"],"one rendered state invokes at most one action")
	check(panel.find_children("*","Button",true,false).all(func(b):return b.disabled),"submitted display disables every button before callback")
	ui.show_toolheap(sample_info(),_action,_close)
	await process_frame
	panel = ui.overlay.get_child(0)
	button(panel,"close").pressed.emit()
	button(panel,"close").pressed.emit()
	button(panel,"accept").pressed.emit()
	check(closes==1 and actions==["accept"],"cancel closes once and never grants candidate")
	ui.show_toolheap(sample_info(),func(action):
		actions.append(action)
		ui.show_toolheap(sample_info(1),_action,_close),_close)
	panel = ui.overlay.get_child(0)
	var stale_button := button(panel,"reroll")
	stale_button.pressed.emit()
	stale_button.pressed.emit()
	check(actions==["accept","reroll"],"reentrant refresh rejects second callback from stale display")
	await process_frame
	panel = ui.overlay.get_child(0)
	check(not button(panel,"reroll").disabled,"new display has an independent interaction guard")
	button(panel,"skip").pressed.emit()
	check(actions.back()=="skip","skip is a distinct callback")
	ui.show_toolheap({"dice":2,"resolved":false},_action,_close)
	panel = ui.overlay.get_child(0)
	check(button(panel,"accept").disabled and button(panel,"reroll").disabled and not button(panel,"skip").disabled,"empty pool offers safe skip without false candidate")

	ui.show_toolheap(sample_info(),_action,_close)
	panel = ui.overlay.get_child(0)
	var abandoned_button := button(panel,"accept")
	ui.close_panel()
	abandoned_button.pressed.emit()
	check(actions.size()==3,"removed display cannot apply an action after programmatic cancel")
	var maximum := sample_info()
	maximum.current_rank = 2
	maximum.next_rank = 2
	ui.show_toolheap(maximum,_action,_close)
	panel = ui.overlay.get_child(0)
	check(button(panel,"accept").disabled,"full-rank candidate cannot be accepted")
	var incomplete := sample_info()
	incomplete.change_text = ""
	ui.show_toolheap(incomplete,_action,_close)
	panel = ui.overlay.get_child(0)
	check(button(panel,"accept").disabled,"candidate without precise effect cannot be accepted")
	ui.close_panel()
	check(not ui.opened and not ui.overlay.visible,"programmatic close restores modal state")
	check(actions.size()==3,"programmatic close does not apply any action")
	ui.queue_free()
	await process_frame
	print("Cornfield toolheap UI: %d failures" % failures)
	quit(1 if failures else 0)
