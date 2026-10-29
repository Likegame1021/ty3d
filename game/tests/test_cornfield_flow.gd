extends SceneTree
const Game = preload("res://scripts/cornfield/game.gd")
const Run = preload("res://scripts/cornfield/run_state.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	game = Game.new()
	game.test_mode = true
	game.save_path = "user://qa_flow_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	check(game.phase == "village" and game.village != null,"3D departure clearing loads")
	check(game.player.weapon_id == "stick", "preparation preserves target branch default")
	check(game.player.get_script().get_base_script().resource_path == "res://scripts/player.gd", "chapter extends original target player")
	check(is_equal_approx(game.camera.size,15.0), "target calibrated camera size is unchanged")
	check(game._start_new_run(730027),"new run checkpoint persists")
	check(paused and game.ui.panel_kind=="route","first choices freeze gameplay")
	var elapsed: float = game.run.data.elapsed
	game._process(2)
	check(game.run.data.elapsed>=elapsed+2,"route time counts while scene is paused")
	game._show_pause()
	elapsed = game.run.data.elapsed
	game._process(2)
	check(game.run.data.elapsed==elapsed,"pause time excluded")
	game._close_panel() # Real input resumes before opening the route; pause is not a travel permission.
	game._show_routes()
	var selected := str(game.run.data.offers[0])
	check(game._choose_route(selected),"selection enters node")
	await physics_frame
	await physics_frame
	check(game.current_room==game.dungeon.entry,"starts at node entry")
	check(game.run.data.weapon=="stick" and game.player.weapon_id=="stick","new run binds branch once")
	var loaded := Run.new(game.save_path)
	check(loaded.load_save() and loaded.data.selected==selected and loaded.data.weapon=="stick","route marker and branch binding survive restore")
	game._show_routes()
	check(game.ui.panel_kind!="route","N cannot unlock next node early")
	var entry: String = game.dungeon.entry
	game._enter_room(str(game.dungeon.main_path[1]))
	await physics_frame
	await physics_frame
	check(game._hostile_room(),"required elite room is a combat room")
	check(not game._travel_to(entry),"M cannot bypass an unfinished fight")
	await _complete_current()
	check(game.room_states[game.current_room].cleared,"combat completion unlocks doors")
	var coins: int = game.run.data.coins
	check(game._travel_to(entry),"safe visited-room fast travel succeeds")
	check(game._travel_to(str(game.dungeon.main_path[1])),"revisit cleared elite succeeds")
	check(not game._hostile_room() and int(game.run.data.coins)==coins,"revisit does not respawn enemies or grant rewards")
	game._show_map()
	check(game.ui.panel_kind=="map" and paused,"M opens actual room graph and freezes combat")
	game._close_panel()
	for floor_number in range(1,4):
		check(int(game.run.data.floor)==floor_number,"expected node number")
		for id in game.dungeon.main_path:
			if not game.room_states[id].cleared:
				game._enter_room(str(id))
				await physics_frame
				await physics_frame
				await _complete_current()
		if game.phase == "floor":
			game._enter_room(str(game.dungeon.exit))
			if game._is_service(game.dungeon.rooms[game.current_room]):
				game._show_service()
				game._resolve_service("skip")
		await process_frame
		if floor_number<3:
			check(game.node_complete,"red room unlocks node without immediate transfer")
			check(int(game.run.data.floor)==floor_number,"player remains on cleared node")
			game._show_routes()
			check(game.ui.panel_kind=="route","N can show next choices after red room")
			check(game._history(floor_number+1).size()==floor_number,"earlier route history remains visible")
			game._close_panel()
			check(game.phase=="floor" and game.node_complete,"closing N allows continued exploration")
			check(game._choose_route(str(game.next_offers[0])),"select next node transaction succeeds")
			await physics_frame
			await physics_frame
			check(game.run.data.route_history.size()==floor_number,"old route retained read-only")
		else:
			check(game.run.data.selected=="BOSS","last node fixed boss")
			check(game.phase=="settlement","boss completion reaches settlement")
			loaded = Run.new(game.save_path)
			check(loaded.load_save() and loaded.data.status=="VICTORY_PENDING_SETTLEMENT","terminal save survives crash before settlement")
	game._settle()
	check(game.phase=="village" and game.run.data.status=="COMPLETE","settlement returns to village")
	check(game.run.data.meta==10,"victory permanent reward exactly once")
	loaded = Run.new(game.save_path)
	loaded.load_save()
	loaded.settle()
	check(loaded.data.meta==10,"reloaded settlement does not duplicate reward")
	# Explicit free shop branch: consumption must never be required by red room.
	var shop_seed := 1
	while true:
		game._start_new_run(shop_seed)
		if game.run.data.offers.has("SHOP"):
			break
		shop_seed += 1
	game._choose_route("SHOP")
	game._enter_room(str(game.dungeon.exit))
	await physics_frame
	game.run.data.coins = 0
	game._show_service()
	game._resolve_service("skip")
	check(game.node_complete and game.run.data.coins==0,"red shop exits without buying or money")
	game._end_run("FORFEIT")
	loaded = Run.new(game.save_path)
	check(loaded.load_save() and loaded.data.status=="FORFEIT","forfeit durable and cannot continue")
	game._settle()
	# End-to-end failure of selection commit must preserve current scene/state.
	game._start_new_run(45)
	var original_path: String = game.run._save_path
	game.run._save_path = "res://scripts" # existing directory; cannot become a save file.
	check(not game._choose_route(str(game.run.data.offers[0])),"selection reports persistence failure")
	check(game.run.data.selected=="" and game.current_room=="","failed selection does not teleport")
	game.run._save_path = original_path
	# An older 3D corn run must not silently change weapon when continued.
	check(game.run.new_run(813,"corn"),"legacy corn checkpoint prepared")
	game.run = Run.new(game.save_path)
	check(game.run.load_save() and game.run.data.weapon=="corn","legacy corn binding is loaded from disk")
	game._continue_run()
	check(game._choose_route(str(game.run.data.offers[0])),"legacy corn first route commits")
	check(game.player.weapon_id=="corn" and game.run.data.weapon=="corn","Continue preserves saved corn binding")
	game._show_village()
	check(game.player.weapon_id=="stick" and game.run.data.weapon=="corn","village previews branch without modifying active corn save")
	game._continue_run()
	check(game.player.weapon_id=="corn","returning to existing run restores its fixed weapon")
	game._end_run("FORFEIT")
	game._settle()
	check(game._start_new_run(814),"new run after corn settlement commits")
	check(game._choose_route(str(game.run.data.offers[0])),"new branch route commits")
	check(game.player.weapon_id=="stick" and game.run.data.weapon=="stick","subsequent run defaults back to branch")
	paused = false
	game.queue_free()
	await process_frame
	var unknown_path := "user://qa_unknown_%d.json" % Time.get_ticks_usec()
	var original := "{\"version\":999,\"marker\":\"keep-original-progress\"}"
	var source := FileAccess.open(unknown_path,FileAccess.WRITE)
	source.store_string(original)
	source.close()
	var recovered := Game.new()
	recovered.test_mode = true
	recovered.save_path = unknown_path
	root.add_child(recovered)
	await process_frame
	check(not recovered.save_recovery_blocked and recovered.recovered_save_paths.size()==1,"unreadable save archived before enabling new run")
	var recovery_path: String = recovered.recovered_save_paths[0]
	check(recovered._start_new_run(1024),"new run allowed after verified recovery copy")
	check(FileAccess.get_file_as_string(recovery_path)==original,"unknown original survives main and rolling backup replacement")
	paused = false
	recovered.queue_free()
	await process_frame
	print("CORNFIELDS_FLOW %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _complete_current() -> void:
	if not is_instance_valid(game.director) or game.director.is_complete():
		return
	var director: Node3D = game.director
	director.set_physics_process(false)
	game.player.controls_enabled = false
	director.request_exit_check()
	var loops := 0
	while not director.is_complete() and loops<160:
		director._physics_process(0.25)
		for enemy in director.enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.dead:
				enemy.receive_hit(100000,Vector3.RIGHT)
		loops += 1
		await physics_frame
	check(director.is_complete(),"required budgets drain and actual defeat callbacks clear "+game.current_room)
	var metrics:Dictionary=director.metrics()
	if director._domain_active:
		# Finite legal-domain search may temporarily defer a whole formation.
		# This append-only diagnostic records history, including recovered waits;
		# viability is established by actual bounded full birth/defeat below.
		var groups_drained:=true
		for segment:Dictionary in director.segments:
			groups_drained=groups_drained and int(segment.spawned)==int(segment.budget) and int(segment.reserved)==0
			for group:Dictionary in segment.groups:
				groups_drained=groups_drained and int(group.spawned)==int(group.count) and int(group.reserved)==0
		var expected_elites:=1 if bool(director.definition.get("elite",false)) and not director._boss_room else 0
		check(metrics.content_error.is_empty() and groups_drained and int(metrics.spawned)==int(metrics.planned) and int(metrics.defeated)==int(metrics.planned) and int(metrics.reserved)==0 and int(metrics.elite_spawned)==expected_elites,"finite-domain flow drains every exact owed group, actor and elite within existing bound")
		check(int(metrics.reward_paid)==int(metrics.reward_budget) and game.world.doors_open,"finite-domain flow pays exact fixed reward and opens actual doors after full drain")
		print("FLOW_DOMAIN_DRAIN ",JSON.stringify({"room":game.current_room,"floor":game.run.data.floor,"loops":loops,"limit":160,"stepped_seconds":loops*.25,"planned":metrics.planned,"spawned":metrics.spawned,"defeated":metrics.defeated,"elite_spawned":metrics.elite_spawned,"reward_paid":metrics.reward_paid,"reward_budget":metrics.reward_budget,"historical_deferred_segments":metrics.spawn_failure_segments}))
	else:
		check(metrics.spawn_failure_segments.is_empty(),"native room has viable wave spawns")
	game.player.controls_enabled = true
