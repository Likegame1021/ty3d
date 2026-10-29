extends SceneTree
## Service values and safe placements are tested without running Game or mutating rewards.
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const World = preload("res://scripts/cornfield/room_world.gd")
const REQUIRED_KEYS := ["title","short_description","service_kind","coins","heal","meta","loot","cost","sell_price","allowed_actions","repeatable"]
var checks := 0
var failures: Array[String] = []
var anchor_rows: Array = []
var Services: Script

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/cornfield/service_catalog.gd"),"service directory exists")
	var probe := World.new()
	check(probe.has_method("resolve_service_anchor"),"RoomWorld provides safe service anchor")
	probe.free()
	if not failures.is_empty():
		_finish()
		return
	Services = load("res://scripts/cornfield/service_catalog.gd")
	_test_services()
	if "--detour-only" in OS.get_cmdline_user_args():
		_test_detour_path_length()
	else:
		await _test_anchors()
	_finish()

func _test_services() -> void:
	var expected := {
		"ANVIL":{"coins":8,"heal":0,"meta":0,"loot":0,"cost":0,"sell_price":0,"service_kind":"supply","allowed_actions":["ANVIL","skip"],"repeatable":false},
		"LEVEL":{"coins":0,"heal":30,"meta":2,"loot":0,"cost":0,"sell_price":0,"service_kind":"rest","allowed_actions":["LEVEL","skip"],"repeatable":false},
		"REWARD":{"coins":18,"heal":0,"meta":0,"loot":3,"cost":0,"sell_price":0,"service_kind":"loot","allowed_actions":["REWARD","skip"],"repeatable":false},
		"ELITE":{"coins":18,"heal":0,"meta":0,"loot":3,"cost":0,"sell_price":0,"service_kind":"loot","allowed_actions":["ELITE","skip"],"repeatable":false},
		"EVENT":{"coins":0,"heal":40,"meta":0,"loot":0,"cost":8,"sell_price":0,"service_kind":"event","allowed_actions":["watermelon","skip"],"repeatable":false},
		"SHOP":{"coins":0,"heal":35,"meta":0,"loot":0,"cost":10,"sell_price":3,"service_kind":"shop","allowed_actions":["buy_heal","sell_loot","skip"],"repeatable":true}}
	for node: String in expected:
		var descriptor: Dictionary = Services.describe(node)
		for key: String in REQUIRED_KEYS:
			check(descriptor.has(key),node+" descriptor has "+key)
		for key: String in expected[node]:
			check(descriptor.get(key) == expected[node][key],node+" truthful "+key)
		var room := {"node_type":node,"kind":"objective","encounter":"none"}
		check(Services.for_room(room) == descriptor,node+" objective consumes same catalog")
		check(Services.for_room({"node_type":node,"kind":"combat","encounter":"swarm"}).is_empty(),node+" combat is not a service")
		check(Services.for_room({"node_type":node,"kind":"event","encounter":"none"}) == Services.describe("EVENT"),node+" optional event takes precedence")
		check(Services.for_room({"node_type":node,"kind":"combat","encounter":"event"}) == Services.describe("EVENT"),node+" explicit event encounter takes precedence")
		check(Services.for_room({"node_type":node,"kind":"objective","encounter":"boss"}).is_empty(),node+" actual boss does not become a service")
	check(not str(Services.describe("ANVIL").short_description).contains("强化"),"ANVIL description does not promise an extra exclusive upgrade")
	check(Services.describe("unknown").is_empty() and Services.describe("").is_empty(),"unknown macro IDs return empty")
	check(Services.for_room({}).is_empty(),"missing room node cannot invent reward")
	check(Services.for_room({"node_type":"unknown","kind":"objective","encounter":"service"}).is_empty(),"unknown service IDs cannot issue rewards")
	check(Services.for_room({"node_type":"SHOP","kind":"exit","encounter":"shop"}) == Services.describe("SHOP"),"authored shop exit is explicitly a shop")
	for unrelated_role: String in ["reward","rest","service","exit","entry","combat"]:
		check(Services.for_room({"node_type":"SHOP","kind":unrelated_role,"encounter":"none"}).is_empty(),"SHOP "+unrelated_role+" without explicit shop role is not a shop")
	check(Services.for_room({"node_type":"SHOP","kind":"combat","encounter":"service"}).is_empty(),"generic service encounter does not silently become a SHOP")
	check(Services.for_room({"node_type":"SHOP","kind":"event","encounter":"shop"}) == Services.describe("EVENT"),"SHOP event role overrides even shop encounter")
	var boss: Dictionary = Services.describe("BOSS")
	for key: String in REQUIRED_KEYS:
		check(boss.has(key),"BOSS descriptor has "+key)
	check(boss.coins == 0 and boss.loot == 0 and boss.allowed_actions.is_empty(),"macro Boss card has no invented primary reward/action")
	var boss_side: Dictionary = Services.for_room({"id":"optional_0","node_type":"BOSS","kind":"objective","encounter":"none"})
	check(boss_side.get("coins") == 18 and boss_side.get("loot") == 3 and boss_side.get("allowed_actions") == ["BOSS","skip"],"BOSS optional_0 retains established supply")
	check(Services.for_room({"node_type":"BOSS","kind":"exit","encounter":"boss"}).is_empty(),"actual Boss combat room has no service")
	check(Services.for_room({"node_type":"BOSS","kind":"event","encounter":"none"}) == Services.describe("EVENT"),"BOSS optional event is watermelon")
	var original := {"node_type":"SHOP","kind":"event","encounter":"none"}
	var snapshot := original.duplicate(true)
	Services.for_room(original)
	check(original == snapshot,"service lookup does not mutate room definition")
	var edited: Dictionary = Services.describe("SHOP")
	edited.allowed_actions.clear()
	edited.coins = 999
	check(Services.describe("SHOP").allowed_actions == ["buy_heal","sell_loot","skip"] and Services.describe("SHOP").coins == 0,"callers cannot mutate future descriptors")

func _test_anchors() -> void:
	for index in range(Catalog.TEMPLATE_COUNT):
		for side: String in ["north","east","south","west"]:
			var definition := Catalog.make_template(index)
			definition.doors = {"north":"n","east":"e","south":"s","west":"w"}
			definition.arrival_side = side
			definition.entry_position = Catalog.door_position(side,definition.size)+Catalog.door_inward(side)*4.0
			definition.main_route = PackedVector3Array([definition.entry_position,Vector3(definition.size.x*.5,0,definition.size.y*.5),Catalog.door_position(Catalog.opposite_side(side),definition.size)+Catalog.door_inward(Catalog.opposite_side(side))*6.0])
			var world := World.new()
			root.add_child(world)
			world.build(definition)
			_register_game_props(world)
			var before := world.definition.duplicate(true)
			var anchor: Dictionary = world.resolve_service_anchor()
			var label := "%s/%s" % [definition.template_id,side]
			check(anchor.get("ok",false),label+" has a service anchor")
			if anchor.get("ok",false):
				_validate_anchor(world,anchor,label,true)
				for repeat in range(3):
					check(world.resolve_service_anchor() == anchor,label+" repeated resolution stays deterministic")
				world.set_doors_open(true)
				check(world.resolve_service_anchor() == anchor,label+" opening doors does not move service")
				world.set_doors_open(false)
				await physics_frame
				await physics_frame
				check(world.resolve_service_anchor() == anchor,label+" native navigation synchronization does not move service")
				for revisit_side: String in definition.doors:
					var revisit := world.get_door_position(revisit_side)+Catalog.door_inward(revisit_side)*4.0
					check(not world.path_to(revisit,anchor.position).is_empty(),label+" alternative "+revisit_side+" revisit reaches the same service")
				world.register_dynamic_obstacle("candidate_blocker",anchor.position,.35)
				var moved: Dictionary = world.resolve_service_anchor()
				check(moved.get("ok",false),label+" can replace a dynamically blocked candidate")
				if moved.get("ok",false):
					_validate_anchor(world,moved,label+" blocked",true)
					check(moved.position.distance_to(anchor.position)>=.95-0.0001,label+" replacement clears circular dynamic prop")
				world.remove_dynamic_obstacle("candidate_blocker")
				check(world.resolve_service_anchor() == anchor,label+" removing blocker restores original fixed anchor")
				anchor_rows.append({"template":str(definition.template_id),"canonical_entrance":side,"position":[anchor.position.x,anchor.position.y,anchor.position.z],"path_length":anchor.path_length,"short_path":anchor.short_path,"dynamic_blocked_position":[moved.position.x,moved.position.y,moved.position.z] if moved.get("ok",false) else [],"dynamic_blocked_path_length":moved.get("path_length",-1.0),"placement_radius":.6,"door_exclusion":5.0})
			check(world.definition == before,label+" helper does not alter existing anchors/geometry/nav definition")
			world.queue_free()
			await process_frame
		print("ANCHOR_TEMPLATE: ",index," complete")
	_test_detour_path_length()
	await _test_fallback()
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--anchor-json="):
			output = arg.trim_prefix("--anchor-json=")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		check(file != null,"anchor coordinate evidence is writable")
		if file != null:
			file.store_string(JSON.stringify(anchor_rows,"\t"))

func _register_game_props(world: Node3D) -> void:
	# Reproduce the unchanged Game._spawn_props locations, order and radii.
	var route: PackedVector3Array = world.definition.main_route
	var candidates: Array[Vector3] = []
	for index in range(1,route.size()-1):
		for offset: Vector3 in [Vector3(2.1,0,1.4),Vector3(-2.1,0,-1.4)]:
			var at: Vector3 = route[index]+offset
			if world.contains_ground(at,.6):
				candidates.append(at)
	for index in mini(5,candidates.size()):
		world.register_dynamic_obstacle("actual_prop_%d" % index,candidates[index],.45 if index%3 == 2 else .34)

func _validate_anchor(world: Node3D,anchor: Dictionary,label: String,expect_short: bool) -> void:
	check(anchor.position is Vector3 and anchor.position.is_finite(),label+" finite Vector3")
	check(world.contains_ground(anchor.position,.6),label+" has 0.6m physical placement clearance")
	var start: Vector3 = world.definition.entry_position
	var path: PackedVector3Array = world.path_to(start,anchor.position)
	check(not path.is_empty(),label+" is reachable from canonical authored entry")
	var length := 0.0
	var previous := start
	for point: Vector3 in path:
		check(world.segment_clear(previous,point,Catalog.PLAYER_RADIUS),label+" every path segment is clear")
		length += previous.distance_to(point)
		previous = point
	# Independent straight-route bound catches omission of start→first waypoint.
	check(float(anchor.path_length)+.0001>=start.distance_to(anchor.position),label+" path length includes start to first waypoint")
	if world.segment_clear(start,anchor.position,Catalog.PLAYER_RADIUS):
		check(absf(float(anchor.path_length)-length)<.001,label+" direct path length is exact")
	check(anchor.short_path == expect_short,label+" explicit short-path status")
	if expect_short:
		check(float(anchor.path_length)>=6.0-.0001 and float(anchor.path_length)<=9.0+.0001,label+" measured path fits 6–9m")
	for door: String in world.definition.doors:
		check(anchor.position.distance_to(world.get_door_position(door))>=5.0-.0001,label+" stays at least 5m from "+door+" automatic door")

func _test_detour_path_length() -> void:
	# Build before entering the tree so the independent public path_to query
	# uses the same documented startup graph, without native async variation.
	var definition := Catalog.make_template(0)
	definition.doors = {}
	definition.obstacles = [{"id":"detour_wall","kind":"brick","rect":Rect2(10,7,3,2),"height":2.1}]
	definition.entry_position = Vector3(8,0,8)
	definition.main_route = PackedVector3Array([definition.entry_position,Vector3(20,0,8)])
	var world := World.new()
	world.build(definition)
	var anchor: Dictionary = world.resolve_service_anchor()
	check(anchor.get("ok",false) and anchor.get("short_path",false),"detour fixture resolves a legal 6–9m short anchor")
	if anchor.get("ok",false):
		var path: PackedVector3Array = world.path_to(definition.entry_position,anchor.position)
		check(path.size()>=2,"detour fixture genuinely has multiple path waypoints")
		var length := 0.0
		var previous: Vector3 = definition.entry_position
		for waypoint: Vector3 in path:
			length += previous.distance_to(waypoint)
			previous = waypoint
		check(absf(float(anchor.path_length)-length)<.001,"detour length includes start→first and all later waypoints exactly")
		_validate_anchor(world,anchor,"obstacle detour",true)
	world.free()

func _test_fallback() -> void:
	var definition := Catalog.make_template(0)
	definition.doors = {}
	definition.obstacles = []
	definition.entry_position = Vector3(8,0,8)
	definition.main_route = PackedVector3Array([definition.entry_position])
	definition.service_position = Vector3(9,0,8)
	var world := World.new()
	root.add_child(world)
	world.build(definition)
	var fallback: Dictionary = world.resolve_service_anchor()
	check(fallback.get("ok",false) and not fallback.get("short_path",true) and fallback.get("position") == definition.service_position,"unexpected route with no short point returns revalidated legacy service anchor")
	if fallback.get("ok",false):
		_validate_anchor(world,fallback,"legacy fallback",false)
	world.register_dynamic_obstacle("legacy_blocker",definition.service_position,.35)
	var failed: Dictionary = world.resolve_service_anchor()
	check(not failed.get("ok",true) and not failed.get("short_path",true),"no legal short/fallback point returns ok=false")
	check(failed.get("position",Vector3.INF) == Vector3.INF,"failed anchor cannot be used as a legal placement")
	world.queue_free()
	await process_frame

func _finish() -> void:
	print("CORNFIELD_SERVICE_CONTRACT: %d checks, %d failures, %d template/entrance anchors" % [checks,failures.size(),anchor_rows.size()])
	quit(0 if failures.is_empty() else 1)
