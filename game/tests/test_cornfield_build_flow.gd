extends SceneTree
const Game = preload("res://scripts/cornfield/game.gd")
const Dungeon = preload("res://scripts/cornfield/dungeon.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		if failures.size()<15:
			printerr("FAIL: ",label)
func _run() -> void:
	for seed_value in range(1000):
		for floor_number in range(1,4):
			var node: String = ["ANVIL","LEVEL","REWARD","ELITE","EVENT","SHOP"][seed_value%6]
			var dungeon := Dungeon.generate(seed_value,floor_number,node)
			var heaps := 0
			for definition in dungeon.rooms.values():
				if definition.get("has_toolheap",false):
					heaps+=1
					check(definition.encounter=="none" and definition.kind=="objective","heap at preexisting safe service")
			check(heaps==(1 if floor_number<=2 else 0),"guaranteed one heap before Boss")
	if failures.size()>0:
		_finish()
		return
	var game := Game.new()
	game.test_mode = true
	game.save_path = "user://qa_build_flow_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	check(game._start_new_run(730027),"run starts")
	check(game._choose_route(str(game.run.data.offers[0])),"route selected")
	game._enter_room(str(game.dungeon.objective))
	await physics_frame
	check(game._is_service(game.dungeon.rooms[game.current_room]),"heap room interactive")
	game._show_service()
	check(game.ui.panel_kind=="toolheap" and paused,"single-candidate heap opens and pauses")
	var unchanged: Dictionary = game.run.data.duplicate(true)
	game._close_panel()
	check(game.run.data==unchanged,"close applies no upgrade")
	game._show_service()
	game._on_toolheap_action("accept")
	var after: Dictionary = game.run.data.duplicate(true)
	game._on_toolheap_action("accept")
	check(game.run.data==after,"repeated callback cannot grant twice")
	check(game.run.current_toolheap().resolved,"heap resolved")
	var entry: String = game.dungeon.entry
	game._enter_room(entry)
	game._enter_room(str(game.dungeon.objective))
	check(game.run.current_toolheap().resolved,"room revisit preserves heap resolution")
	game.run.data.global_builds.clear_heal = 2
	game.player.hp = 50
	game.room_states[game.current_room].cleared = false
	game._room_cleared()
	check(game.player.hp==50,"safe service entry does not count as clearing enemies")
	game._enter_room(str(game.dungeon.main_path[1]))
	if is_instance_valid(game.director):
		game.director.shutdown()
		game.director._complete=true
	game._room_cleared()
	check(game.player.hp==56,"combat clear recovery granted once")
	game._room_cleared()
	check(game.player.hp==56,"repeated clear never duplicates recovery")
	game.player.request_attack()
	game._show_pause()
	check(game.player.attack.remaining==0,"pause clears buffered melee")
	game._close_panel()
	check(game.player.attack.remaining==0,"close does not release old attack")
	game.player.request_attack()
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.player.attack.remaining==0,"focus loss clears melee")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not paused,"focus regain returns control")
	# Rejecting a destination checkpoint must leave its one-shot panel usable.
	game._enter_room(str(game.dungeon.exit))
	if is_instance_valid(game.director):
		game.director.shutdown()
		game.director._complete = true
	game.room_states[game.current_room].cleared = true
	game.node_complete = true
	game.next_offers = game.run.next_node_offers()
	game._show_routes()
	var generation: int = game.ui._display_generation
	var original_path: String = game.run._save_path
	game.run._save_path = "res://scripts"
	game.ui._dispatch_selection(str(game.next_offers[0]),generation,game._choose_route)
	check(game.ui.panel_kind=="route" and not game.ui._display_submitted,"failed checkpoint refreshes one-shot route controls")
	game.run._save_path = original_path
	game._close_panel()
	var effects: Dictionary = game.run.build_effects("stick")
	check(is_equal_approx(game.player.attack_reach,1.35*float(effects.reach_multiplier)),"build reach assigned from baseline once")
	for index in 30:
		game._sync_stats()
	check(is_equal_approx(game.player.attack_reach,1.35*float(effects.reach_multiplier)),"per-frame sync never compounds reach")
	paused = false
	game.queue_free()
	await process_frame
	_finish()
func _finish() -> void:
	print("CORNFIELDS_BUILD_FLOW %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
