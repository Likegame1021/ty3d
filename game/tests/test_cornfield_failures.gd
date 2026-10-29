extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run_checks")
func check(value: bool,label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ",label)
func run_checks() -> void:
	var game = load("res://scripts/cornfield/game.gd").new()
	game.test_mode = true
	game.save_path = "user://qa_terminal_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	game._start_new_run(730027)
	game._choose_route(str(game.run.data.offers[0]))
	game._enter_room(str(game.dungeon.main_path[1]))
	for prop in game.gameplay.get_children():
		if prop is StaticBody3D and prop.get("prop_id") != null:
			var actual_radius := 0.0
			for child in prop.get_children():
				if child is CollisionShape3D:
					actual_radius = child.shape.radius
			check(is_equal_approx(game.world._dynamic_obstacles[prop.prop_id].radius,actual_radius),"breakable navigation radius equals its physical collider")
	game.node_complete = true
	game.next_offers = game.run.next_node_offers()
	game._show_routes()
	check(game.ui.panel_kind != "route", "N cannot open next choices inside an active optional fight")
	game.node_complete = false
	game._close_panel()
	var original_path: String = game.run._save_path
	game.run._save_path = "res://scripts"
	game._end_run("FAILED")
	check(game.run.data.status == "ACTIVE" and game.ui.panel_kind == "settlement", "failed terminal save locks gameplay pending retry")
	check(game.has_method("_save_before_quit"),"quit has a gate that preserves pending terminal outcome")
	if game.has_method("_save_before_quit"):
		check(not game._save_before_quit(),"quit is blocked while terminal save still fails")
		game.run._save_path = original_path
		check(game._save_before_quit(),"quit retries the pending terminal outcome")
		var loaded = load("res://scripts/cornfield/run_state.gd").new(original_path)
		check(loaded.load_save() and loaded.data.status == "FAILED", "closing after save failure cannot resurrect the run")
	check(game._is_shop({"node_type":"SHOP","kind":"objective","encounter":"none"}),"SHOP optional objective provides shop service rather than a false reward")
	var Run = load("res://scripts/cornfield/run_state.gd")
	var save_path := "user://qa_backup_%d.json" % Time.get_ticks_usec()
	var state = Run.new(save_path)
	check(state.new_run(99),"backup test starts a fresh checkpoint")
	var blocked := ProjectSettings.globalize_path(save_path+".bak.tmp")
	DirAccess.make_dir_absolute(blocked)
	check(not state.end_run("FAILED"),"terminal save cannot succeed if backup cannot be prepared")
	var old = Run.new(save_path)
	check(old.load_save() and old.data.status == "ACTIVE", "failed backup preparation preserves committed primary")
	DirAccess.remove_absolute(blocked)
	check(state.end_run("FAILED"),"terminal save succeeds after backup destination is restored")
	var damaged := FileAccess.open(save_path,FileAccess.WRITE)
	damaged.store_string("bad")
	damaged.close()
	var fallback = Run.new(save_path)
	check(fallback.load_save() and fallback.data.status == "FAILED", "corrupt primary cannot resurrect a successfully ended run")
	paused = false
	game.queue_free()
	await process_frame
	print("CORNFIELDS_FAILURES %d failures" % failures)
	quit(1 if failures else 0)
