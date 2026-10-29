extends SceneTree
const Game = preload("res://scripts/cornfield/game.gd")
const World = preload("res://scripts/cornfield/room_world.gd")
const Dungeon = preload("res://scripts/cornfield/dungeon.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func fixture() -> Dictionary:
	# Deliberately unordered IDs and links: names and insertion order are not route intent.
	return {"entry":"start","exit":"finish","main_path":["start","middle","finish"],"rooms":{
		"leaf":{"title":"SECRET REWARD","doors":{"west":"branch"}},
		"finish":{"doors":{"west":"middle"}},
		"branch":{"title":"SECRET SERVICE","doors":{"west":"middle","east":"leaf"}},
		"middle":{"doors":{"west":"start","east":"finish","north":"branch"}},
		"start":{"doors":{"east":"middle"}}},"links":[["leaf","branch"],["middle","finish"],["branch","middle"],["start","middle"]]}
func _run() -> void:
	var game := Game.new()
	game.test_mode = true
	game.save_path = "user://qa_exit_signs_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	game._start_new_run(5)
	game._choose_route(str(game.run.data.offers[0]))
	for side: String in game.world.definition.doors:
		var target: String = game.world.definition.doors[side]
		var expected := "主路前进" if target == game.dungeon.main_path[1] else "支路探索"
		check(game.world._door_labels[side].text.contains(expected), "entry actual door identifies "+expected)
	check(game.world.has_method("exit_labels_for"), "pure graph classifier is available")
	if game.world.has_method("exit_labels_for"):
		var graph := fixture()
		var before := graph.duplicate(true)
		var labels: Dictionary = game.world.call("exit_labels_for",graph,"middle")
		check(labels=={"west":"原路返回","east":"主路前进","north":"支路探索"}, "main room labels follow actual graph order")
		labels = game.world.call("exit_labels_for",graph,"branch")
		check(labels=={"west":"返回主路","east":"支路探索"}, "first optional room distinguishes main return from deeper exploration")
		labels = game.world.call("exit_labels_for",graph,"leaf")
		check(labels=={"west":"原路返回"}, "two-deep optional return never falsely promises immediate main route")
		check(graph==before, "classification never mutates authoritative graph or hidden titles")
		var cyclic := graph.duplicate(true)
		cyclic.links.append(["leaf","finish"])
		cyclic.rooms.leaf.doors.north = "finish"
		cyclic.rooms.finish.doors.south = "leaf"
		check(game.world.call("exit_labels_for",cyclic,"middle").is_empty(), "cycle falls back rather than inventing route intent")
		var malformed := graph.duplicate(true)
		malformed.main_path = ["start","branch","middle","finish"]
		check(game.world.call("exit_labels_for",malformed,"middle").is_empty(), "disconnected main ordering falls back")
		malformed = graph.duplicate(true)
		malformed.rooms.middle.doors.north = "finish"
		check(game.world.call("exit_labels_for",malformed,"middle").is_empty(), "contradictory door graph falls back")
		malformed = graph.duplicate(true)
		malformed.main_path = ["start","middle","middle","finish"]
		check(game.world.call("exit_labels_for",malformed,"middle").is_empty(), "duplicate main nodes fall back")
		var source: String = game.current_room
		for side: String in game.world._door_labels:
			var label: Label3D = game.world._door_labels[side]
			var text_open: String = label.text
			game.world.set_route_unlocked(true)
			check(label.text==text_open, "node unlock preserves real within-node direction")
			game.world.set_doors_open(false)
			check(label.text.contains("清场后开启") and not label.text.contains("主路"), "sealed door wins even after node unlock")
			check(game.world._door_bodies[side].collision_layer==1, "sealed door collision unchanged")
			game.world.set_doors_open(true)
			check(label.text==text_open and game.world._door_bodies[side].collision_layer==0, "opening restores direction without changing guard contract")
		check(game.current_room==source and game.next_offers.is_empty(), "presentation setters do not travel or select node")
		for revision in [2,3]:
			for seed_value in 80:
				for floor_number in [1,2,3]:
					var generated := Dungeon.generate(seed_value,floor_number,"ANVIL",revision)
					for id: String in generated.rooms:
						var actual: Dictionary = game.world.call("exit_labels_for",generated,id)
						check(actual.size()==generated.rooms[id].doors.size(),"generated valid tree labels all doors")
	paused = false
	game.queue_free()
	await process_frame
	print("CORNFIELDS_EXIT_SIGNS %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
