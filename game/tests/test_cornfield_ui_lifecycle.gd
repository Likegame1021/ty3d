extends SceneTree
## Integrated UI router/lifecycle assertions; the game remains the state owner.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, description: String) -> void:
	checks+=1
	print("PASS: " if ok else "FAIL: ",description)
	if not ok: failures+=1

func send_action(game: Node, action: String) -> void:
	var event := InputEventAction.new()
	event.action=action
	event.pressed=true
	game._unhandled_input(event)

func find_action(ui: Node, action: String) -> Button:
	for button in ui.overlay.find_children("*","Button",true,false):
		if button.get_meta("toolheap_action","")==action: return button
	return null

func run_checks() -> void:
	var game = load("res://scripts/cornfield/game.gd").new()
	game.test_mode=true
	game.save_path="user://qa_ui_lifecycle_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	check(game._start_new_run(730027),"isolated UI fixture starts a valid run")
	check(game._choose_route(str(game.run.data.offers[0])),"isolated UI fixture chooses route")
	game._close_panel()
	send_action(game,"map")
	check(game.ui.panel_kind=="map" and paused,"map action opens map and pauses combat")
	send_action(game,"map")
	check(not game.ui.opened and not paused,"same map action closes without stale modal state")
	game._enter_room(str(game.dungeon.objective))
	await process_frame
	game.player.request_attack()
	game._show_service()
	check(game.ui.panel_kind=="toolheap" and paused and game.player.attack.remaining==0,"toolheap cancels buffered swing before showing controls")
	var snapshot: Dictionary=game.run.data.duplicate(true)
	var stale: Button=find_action(game.ui,"accept")
	send_action(game,"pause")
	stale.pressed.emit()
	check(not game.ui.opened and game.run.data==snapshot,"Escape cancel plus stale click cannot claim candidate")
	game._show_service()
	check(game.ui.panel_kind=="toolheap" and not find_action(game.ui,"accept").disabled,"cancelled candidate can be reopened normally")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(paused and game.ui.panel_kind=="toolheap" and game.player.attack.remaining==0,"focus loss retains modal and clears combat input")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(paused and game.ui.panel_kind=="toolheap" and game.run.data==snapshot,"focus regain preserves pending candidate without applying it")
	find_action(game.ui,"close").pressed.emit()
	check(not game.ui.opened and not paused and game.run.data==snapshot,"close button restores play without spending or granting")
	game.node_complete=true
	game.next_offers=game.run.next_node_offers()
	send_action(game,"node_map")
	check(game.ui.panel_kind=="route" and paused,"route action opens choices after red-room completion")
	send_action(game,"node_map")
	check(not game.ui.opened and not paused,"same route action closes without selecting")
	game._show_service()
	stale=find_action(game.ui,"accept")
	game._end_run("FAILED")
	check(game.ui.panel_kind=="settlement" and paused,"terminal outcome replaces toolheap with settlement")
	var ended: Dictionary=game.run.data.duplicate(true)
	stale.pressed.emit()
	check(game.run.data==ended,"removed toolheap cannot apply after death or settlement")
	send_action(game,"pause")
	check(game.ui.panel_kind=="settlement" and paused,"Escape cannot accidentally dismiss terminal settlement")
	game._settle()
	check(game.phase=="village" and not paused and not game.ui.opened,"settlement returns to a clean playable village")
	paused=false
	game.queue_free()
	await process_frame
	print("Cornfield UI lifecycle: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
