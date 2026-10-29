extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func fixture() -> Node3D:
	var game:=Game.new();game.test_mode=true;game.save_path="user://travel_guard_%d.json"%Time.get_ticks_usec()
	root.add_child(game);await process_frame
	game._start_new_run(5);game._choose_route(str(game.run.data.offers[0]))
	game._enter_room("optional_0");game._enter_room("entry")
	return game
func dispose(game:Node3D) -> void:
	paused=false;game.queue_free();await process_frame
func _run() -> void:
	var game:=await fixture()
	check(game.has_method("_can_travel_action"),"travel has one authoritative policy")
	check(game.has_method("_can_service_action"),"service callbacks share alive/focus/transaction policy")
	if game.has_method("_can_travel_action"):
		check(game._can_travel_action("revisit","optional_0"),"known clear room is revisitable")
		check(not game._can_travel_action("revisit","fight_1"),"unknown uncleared room cannot be fast traveled")
		check(not game._can_travel_action("unexpected"),"unknown travel action fails closed")
		for blocker in ["hp","focus","transition","terminal","phase","status","pause"]:
			game.player.hp=100;game.focused=true;game.room_change_pending=false;game.pending_terminal="";game.phase="floor";game.run.data.status="ACTIVE";game.ui.panel_kind="";game.ui.opened=false
			match blocker:
				"hp":game.player.hp=0
				"focus":game.focused=false
				"transition":game.room_change_pending=true
				"terminal":game.pending_terminal="FAILED"
				"phase":game.phase="settlement"
				"status":game.run.data.status="FAILED"
				"pause":game.ui.panel_kind="pause";game.ui.opened=true
			check(not game._can_travel_action("revisit","optional_0"),"authoritative revisit rejection "+blocker)
			check(not game._travel_to("optional_0") and game.current_room=="entry","callback cannot bypass revisit guard "+blocker)
	await dispose(game)
	# A request was legal, but its deferred commit became stale/adversarial.
	for blocker in ["hp","focus","service","pause","room_change","new_run","none"]:
		game=await fixture()
		var source:String=game.current_room
		var side:String=game.dungeon.rooms[source].doors.keys()[0]
		var target:String=game.dungeon.rooms[source].doors[side]
		game.player.position=game.world.get_door_position(side)+Game.INWARD[side]*.5
		game.gameplay_time=2;game.last_door_time=0
		game._check_doors()
		check(game.room_change_pending,"normal door request schedules once "+blocker)
		match blocker:
			"hp":game.player.hp=0
			"focus":game.focused=false;game._refresh_pause()
			"service":game._panel("Fixture service","",[],"service")
			"pause":game._show_pause()
			"room_change":game._enter_room("optional_0")
			"new_run":
				game._update_hud()
				game._start_new_run(12)
				game._update_hud()
				check(not game.ui.minimap.visible,"new initial route hides the previous room minimap")
		await process_frame
		var expected:String=target if blocker=="none" else "optional_0" if blocker=="room_change" else "" if blocker=="new_run" else source
		check(game.current_room==expected,"door commit revalidates current context "+blocker)
		check(not game.room_change_pending,"rejected/finished ticket cannot leave a stuck pending flag "+blocker)
		await dispose(game)
	# Ticket identity is one-use and cannot interfere with a later request.
	game=await fixture()
	game.set_process(false);game.player.set_physics_process(false)
	var side:String=game.dungeon.rooms.entry.doors.keys()[0]
	var destination:String=game.dungeon.rooms.entry.doors[side]
	game.player.position=game.world.get_door_position(side)+Game.INWARD[side]*.5
	game.gameplay_time=2;game.last_door_time=0
	game._check_doors()
	if game.has_method("_commit_door_transition"):
		var ticket:int=game.get("_door_ticket")
		check(not game._commit_door_transition(ticket-1) and game.room_change_pending,"wrong ticket cannot cancel current request")
		check(game._commit_door_transition(ticket) and game.current_room==destination,"exact ticket commits once")
		check(not game._commit_door_transition(ticket),"same ticket cannot commit twice")
		game._enter_room("entry");game.player.set_physics_process(false)
		game.player.position=game.world.get_door_position(side)+Game.INWARD[side]*.5
		game.gameplay_time=4;game.last_door_time=0;game._check_doors()
		var newer:int=game.get("_door_ticket")
		check(newer>ticket and not game._commit_door_transition(ticket) and game.room_change_pending,"stale callback preserves a newer ticket")
		game.player.position=game.world.definition.entry_position
		check(not game._commit_door_transition(newer) and not game.room_change_pending,"commit rechecks actual door proximity")
		for mutation in ["run_id","floor","link","epoch"]:
			game.player.position=game.world.get_door_position(side)+Game.INWARD[side]*.5
			game._check_doors();ticket=game.get("_door_ticket")
			var old_run:String=game.run.data.run_id;var old_floor:int=game.run.data.floor;var old_link:String=game.dungeon.rooms.entry.doors[side]
			match mutation:
				"run_id":game.run.data.run_id="different-run"
				"floor":game.run.data.floor=2
				"link":game.dungeon.rooms.entry.doors[side]="missing-room"
				"epoch":game.set("_room_epoch",int(game.get("_room_epoch"))+1)
			check(not game._commit_door_transition(ticket) and game.current_room=="entry" and not game.room_change_pending,"commit rejects changed "+mutation)
			game.run.data.run_id=old_run;game.run.data.floor=old_floor;game.dungeon.rooms.entry.doors[side]=old_link
	else:check(false,"one-use deferred door commit exists")
	await dispose(game)
	# Route and map callbacks preserve the intended modal-specific truth table.
	game=await fixture();game.set_process(false)
	game.node_complete=true;game.next_offers=game.run.next_node_offers()
	for panel in ["service","toolheap","pause","settlement","confirm","tutorial","welcome"]:
		game.ui.opened=true;game.ui.panel_kind=panel;paused=true
		var floor_before:int=game.run.data.floor
		game._show_routes()
		check(game.ui.panel_kind==panel and not game._choose_route(str(game.next_offers[0])) and game.run.data.floor==floor_before,"route rejects unrelated modal "+panel)
	game._close_panel();game._show_map()
	check(game._travel_to("optional_0") and game.current_room=="optional_0" and not paused,"valid paused map callback travels and closes UI")
	game._show_routes()
	check(game.ui.panel_kind=="route" and paused and game._choose_route(str(game.next_offers[0])) and int(game.run.data.floor)==2,"valid paused route callback advances once")
	await dispose(game)
	# Every economic callback must reject state changes after a modal was built.
	game=await fixture();game._enter_room("optional_0")
	var base_data:Dictionary=game.run.data.duplicate(true)
	var base_state:Dictionary=game.room_states[game.current_room].duplicate(true)
	for action in ["buy","sell","resolve","accept","reroll","skip"]:
		for blocker in ["hp","focus","transition","terminal","pause","stale_panel"]:
			game.run.data=base_data.duplicate(true);game.room_states[game.current_room]=base_state.duplicate(true)
			game.pending_terminal="";game.room_change_pending=false;game.focused=true;game.phase="floor"
			game.dungeon.rooms[game.current_room].node_type="SHOP"
			game.player.hp=50;game.run.data.coins=25;game.run.data.loot["田间拾物"]=3
			if action in ["buy","sell","resolve"]:game.run.act_on_toolheap("skip")
			game.ui.panel_kind="toolheap" if action in ["accept","reroll","skip"] else "service";game.ui.opened=true;paused=true
			match blocker:
				"hp":game.player.hp=0
				"focus":game.focused=false
				"transition":game.room_change_pending=true
				"terminal":game.pending_terminal="FAILED"
				"pause":game.ui.panel_kind="pause"
				"stale_panel":game.ui.panel_kind="route"
			var before:Dictionary={"hp":game.player.hp,"coins":game.run.data.coins,"dice":game.run.data.dice,"loot":game.run.data.loot.duplicate(true),"ranks":game.run._rank_payload(),"heap":game.run.current_toolheap().duplicate(true),"resolved":game.room_states[game.current_room].resolved}
			match action:
				"buy":game._buy_heal()
				"sell":game._sell_loot()
				"resolve":game._resolve_service("skip")
				_:game._on_toolheap_action(action)
			var after:Dictionary={"hp":game.player.hp,"coins":game.run.data.coins,"dice":game.run.data.dice,"loot":game.run.data.loot.duplicate(true),"ranks":game.run._rank_payload(),"heap":game.run.current_toolheap().duplicate(true),"resolved":game.room_states[game.current_room].resolved}
			check(before==after,"economic callback rejects %s after %s"%[action,blocker])
	await dispose(game)
	game=await fixture();game._enter_room("optional_0")
	game.dungeon.rooms[game.current_room].node_type="SHOP"
	game.player.hp=50;game.run.data.coins=25
	game.run.act_on_toolheap("skip")
	game._panel("Fixture shop","",[],"service")
	game._buy_heal()
	check(game.player.hp==85 and game.run.data.coins==15,"legitimate service modal pause still permits buying")
	await dispose(game)
	print("CORNFIELDS_TRAVEL_GUARDS %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
