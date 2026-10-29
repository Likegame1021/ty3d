extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var minimum_area_ratio: float = INF
var tested_seed_count: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run_tests() -> void:
	if "--visual" in OS.get_cmdline_user_args():
		await render_visual()
		return
	for path in ["res://scripts/cornfield/room_catalog.gd", "res://scripts/cornfield/dungeon.gd", "res://scripts/cornfield/room_world.gd"]:
		check(ResourceLoader.exists(path), "3D implementation exists: " + path)
	if not failures.is_empty():
		finish()
		return
	var catalog: Script = load("res://scripts/cornfield/room_catalog.gd")
	var generator: Script = load("res://scripts/cornfield/dungeon.gd")
	var world_script: Script = load("res://scripts/cornfield/room_world.gd")
	check(catalog.TEMPLATE_COUNT == 24, "Exactly twenty-four authored 3D templates")
	check(is_equal_approx(catalog.PLAYER_RADIUS, .22), "Target player radius stays 0.22 units")
	var signatures: Dictionary = {}
	var quick: bool = "--quick" in OS.get_cmdline_user_args()
	for index in range(1 if quick else catalog.TEMPLATE_COUNT):
		var selected_index: int = index
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--template="):
				selected_index = argument.trim_prefix("--template=").to_int()
		var definition: Dictionary = catalog.make_template(selected_index)
		definition.doors = {"north":"n", "east":"e", "south":"s", "west":"w"}
		signatures[var_to_str([definition.outline, definition.obstacles])] = true
		var world: Node3D = world_script.new()
		root.add_child(world)
		world.build(definition)
		await process_frame
		await physics_frame
		await physics_frame
		# The map can already have an iteration while the newly attached
		# region is still being synchronized by the navigation worker.
		for _sync_attempt in range(30):
			if NavigationServer3D.map_get_iteration_id(world.navigation_region.get_navigation_map()) > 0 and NavigationServer3D.map_get_closest_point_owner(world.navigation_region.get_navigation_map(),definition.entry_position) == world.navigation_region.get_rid():
				break
			await physics_frame
		check(world.get_node("Ground") is StaticBody3D, definition.id + " has real 3D floor")
		check(world.get_node("NavigationRegion3D") is NavigationRegion3D, definition.id + " uses room-shared native navigation")
		check(world.walkable_area >= definition.baseline_area * 3.0, "%s expanded reachable area %.1f >= %.1f" % [definition.id, world.walkable_area, definition.baseline_area * 3.0])
		minimum_area_ratio = minf(minimum_area_ratio,world.walkable_area/definition.baseline_area)
		check(world.find_path(definition.entry_position, definition.entry_position).size() == 1, definition.id + " supports shared find_path interface")
		check(world.get_outline_normalized().size() == definition.outline.size(), definition.id + " minimap uses same outline")
		check(world.contains_ground(definition.entry_position, .22), definition.id + " entry is traversable")
		for route_index in range(world.definition.main_route.size()-1):
			check(world.segment_clear(world.definition.main_route[route_index],world.definition.main_route[route_index+1],.22), definition.id + " main route is derived from actual shared navigation")
		check(world.contains_ground(world.definition.service_position,.6), definition.id + " service approach is physically clear")
		check(world.path_to(definition.entry_position, Vector3(-2,0,-2)).is_empty(), definition.id + " refuses outside targets")
		var ground_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(definition.entry_position+Vector3.UP*3.0,definition.entry_position+Vector3.DOWN,1)
		var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ground_ray)
		check(not floor_hit.is_empty() and floor_hit.collider == world.get_node("Ground"), definition.id + " floor triangles face up and physically support actors")
		check(NavigationServer3D.map_get_iteration_id(world.navigation_region.get_navigation_map()) > 0, definition.id + " native navigation map has synchronized")
		for side in definition.doors:
			var door: Vector3 = world.get_door_position(side)
			var inward: Vector3 = catalog.door_inward(side)
			var target: Vector3 = door + inward * 2.0
			var touching_wall: Vector3 = door+inward*.51
			check(world.contains_ground(touching_wall,.22) and not world.path_to(definition.entry_position,touching_wall,.22).is_empty(),definition.id + " legal player feet at closed doorway connect to shared navigation")
			var boss_approach: PackedVector3Array = world.path_to(definition.entry_position,touching_wall,.625)
			check(not boss_approach.is_empty() and world.contains_ground(boss_approach[-1],.625) and boss_approach[-1].distance_to(touching_wall)<1.3,definition.id + " larger actor reaches a physically legal approach to a wall-hugging player")
			var path: PackedVector3Array = world.path_to(definition.entry_position, target)
			check(not path.is_empty(), definition.id + " has reachable " + side + " door approach")
			check(not world.path_to(target,definition.entry_position).is_empty(), definition.id + " " + side + " door approach can return to entry")
			var previous: Vector3 = definition.entry_position
			for point in path:
				check(world.segment_clear(previous, point, .22), definition.id + " path never crosses solid terrain")
				previous = point
			check(not world.contains_ground(door, .22), definition.id + " closed door excluded from navigation")
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(door+inward*1.5+Vector3.UP*.75,door-inward*1.5+Vector3.UP*.75,1)
			check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), definition.id + " closed gate blocks actual 3D projectile ray")
		world.set_doors_open(true)
		await physics_frame
		for side in definition.doors:
			check(world.contains_ground(world.get_door_position(side), .22), definition.id + " opened doorway traversable")
			var door: Vector3 = world.get_door_position(side)
			var inward: Vector3 = catalog.door_inward(side)
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(door+inward*1.5+Vector3.UP*.75,door-inward*1.5+Vector3.UP*.75,1)
			check(world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), definition.id + " opened gate releases physical 3D passage")
			check(not world.path_to(door,definition.entry_position).is_empty(), definition.id + " opened doorway supports backtracking")
		world.set_doors_open(false)
		for obstacle in definition.obstacles:
			var rectangle: Rect2 = obstacle.rect
			check(not world.contains_ground(Vector3(rectangle.get_center().x,0,rectangle.get_center().y), .22), definition.id + " obstacle authority matches query")
			var top: Vector3 = Vector3(rectangle.get_center().x,obstacle.height,rectangle.get_center().y)
			var top_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(top+Vector3.UP,top-Vector3.UP*.1,1)
			check(not world.get_world_3d().direct_space_state.intersect_ray(top_ray).is_empty(), definition.id + " authored obstacle has real height and top collision")
		for obstacle in definition.obstacles:
			if obstacle.kind == "corn":
				var corn: Node3D = world.get_node("Terrain/" + obstacle.id)
				var batches: Array[Node] = corn.find_children("CornBatch*", "MultiMeshInstance3D", false, false)
				check(not batches.is_empty(), definition.id + " corn uses real GLB mesh instancing")
				check(batches.size() <= 3, definition.id + " corn batches bound draw calls per plot")
				for batch in batches:
					check(batch.multimesh.mesh is ArrayMesh, definition.id + " corn is authored mesh, not primitive cube")
		for obstacle in definition.obstacles:
			var body: Node3D = world.get_node("Terrain/" + obstacle.id)
			var rectangle: Rect2 = obstacle.rect
			for batch in body.find_children("*", "MultiMeshInstance3D", false, false):
				# Dummy headless rendering does not retain MultiMesh server transforms.
				# Explicit renderer culling bounds are computed from the real transforms.
				var bounds: AABB = batch.custom_aabb
				check(bounds.has_volume(), definition.id + " " + batch.name + " has explicit instance-correct culling bounds")
				var fits_footprint: bool = bounds.position.x >= -rectangle.size.x*.5-.06 and bounds.end.x <= rectangle.size.x*.5+.06 and bounds.position.z >= -rectangle.size.y*.5-.06 and bounds.end.z <= rectangle.size.y*.5+.06
				check(fits_footprint, definition.id + " " + batch.name + " stays inside authored collision footprint: " + str(bounds))
		var first_obstacle: Rect2 = definition.obstacles[0].rect
		var left: Vector3 = Vector3(first_obstacle.position.x-1.5,0,first_obstacle.get_center().y)
		var right: Vector3 = Vector3(first_obstacle.end.x+1.5,0,first_obstacle.get_center().y)
		var native_path: PackedVector3Array = NavigationServer3D.map_get_path(world.navigation_region.get_navigation_map(),left,right,true)
		check(native_path.size() >= 3, definition.id + " native 3D navigation finds a real detour around terrain")
		for path_index in range(native_path.size()-1):
			check(world.segment_clear(native_path[path_index],native_path[path_index+1],.22), definition.id + " native detour respects authoritative wall geometry")
		var spawn: Vector3 = world.find_spawn(Vector3(definition.size.x * 0.5,0,definition.size.y * 0.5), definition.entry_position, 5.25)
		check(spawn != Vector3.INF and world.contains_ground(spawn, 0.35), definition.id + " has a legal spawn")
		check(spawn.distance_to(definition.entry_position) >= 5.25, definition.id + " safe spawn distance")
		var prop_position: Vector3 = Vector3(definition.size.x*.5+2.1,0,definition.size.y*.5+1.4)
		var before_prop: Vector3 = prop_position+Vector3(-3,0,0)
		var beyond_prop: Vector3 = prop_position+Vector3(3,0,0)
		world.register_dynamic_obstacle("crate",prop_position,.22)
		check(not world.segment_clear(before_prop,beyond_prop,.22), definition.id + " registered physical prop interrupts straight navigation")
		var detour: PackedVector3Array = world.path_to(before_prop,beyond_prop,.22)
		check(detour.size() >= 2, definition.id + " shared graph detours around runtime prop")
		var last_point: Vector3 = before_prop
		for point in detour:
			check(world.segment_clear(last_point,point,.22),definition.id + " dynamic prop detour preserves actual actor clearance")
			last_point = point
		var touching_prop: Vector3 = prop_position+Vector3(.61,0,0)
		check(not world.path_to(touching_prop,beyond_prop,.22).is_empty(),definition.id + " legal feet at prop edge can move away")
		world.remove_dynamic_obstacle("crate")
		check(world.path_to(before_prop,beyond_prop,.22).size() == 1,definition.id + " removing a broken prop restores direct shared route")
		world.queue_free()
		await process_frame
	check(signatures.size() == (1 if quick else catalog.TEMPLATE_COUNT), "Every template has distinct authored geometry")
	var node_ids: Array[String] = ["ANVIL", "LEVEL", "REWARD", "ELITE", "EVENT", "SHOP"]
	for seed_value in range(0 if quick else 1000):
		tested_seed_count += 1
		for floor_number in range(1,4):
			var dungeon: Dictionary = generator.generate(seed_value, floor_number, node_ids[seed_value % node_ids.size()])
			var rooms: Dictionary = dungeon.rooms
			var path: Array = dungeon.main_path
			check(rooms.size() >= 5 and rooms.size() <= 8, "1000 seeds: room budget")
			check(path.size() >= 3 and path.size() <= 5, "1000 seeds: main route budget")
			check(rooms[dungeon.entry].main_route[0].distance_to(rooms[dungeon.entry].main_route[-1]) <= 7.0, "1000 seeds: safe entry avoids a long empty first walk")
			check(rooms[path[1]].elite, "1000 seeds: mandatory second-room elite")
			check(dungeon.links.size() == rooms.size() - 1, "1000 seeds: no elite bypass cycle")
			var reds: int = 0
			var branch_roots: int = 0
			var seen: Dictionary = {}
			var pending: Array = [dungeon.entry]
			while not pending.is_empty():
				var room_id: String = pending.pop_back()
				if seen.has(room_id):
					continue
				seen[room_id] = true
				var room: Dictionary = rooms[room_id]
				if room.get("optional",false):
					check(room.branch_depth >= 1 and room.branch_depth <= 2,"1000 seeds: every optional branch is at most two rooms deep")
					if room.branch_depth == 1:
						branch_roots += 1
				if room.completion:
					reds += 1
				for side in room.doors:
					var destination: String = room.doors[side]
					check(rooms[destination].doors.get(catalog.opposite_side(side), "") == room_id, "1000 seeds: reciprocal physical doors")
					pending.append(destination)
			check(seen.size() == rooms.size() and reds == 1, "1000 seeds: connected graph and unique red room")
			check(branch_roots >= 1 and branch_roots <= 2,"1000 seeds: one or two optional branches")
			check(dungeon.exit == path[-1] and rooms[dungeon.exit].completion, "1000 seeds: red objective is main-route end")
			check(floor_number != 3 or (rooms[dungeon.exit].encounter == "boss" and rooms[dungeon.exit].node_type == "BOSS"), "1000 seeds: third node always BOSS")
			if seed_value < 5:
				check(var_to_str(dungeon) == var_to_str(generator.generate(seed_value, floor_number, node_ids[seed_value % node_ids.size()])), "Same seed gives identical rooms")
	finish()

func finish() -> void:
	print("CORNFIELD_ROOMS: %s (%d checks; %d seeds x 3 nodes; minimum conservative area %.3fx frozen baseline)" % ["PASS" if failures.is_empty() else str(failures), checks,tested_seed_count,minimum_area_ratio])
	quit(0 if failures.is_empty() else 1)

func render_visual() -> void:
	var catalog: Script = load("res://scripts/cornfield/room_catalog.gd")
	var world_script: Script = load("res://scripts/cornfield/room_world.gd")
	var selected_index: int = 5
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--template="):
			selected_index = argument.trim_prefix("--template=").to_int()
	var definition: Dictionary = catalog.make_template(selected_index)
	definition.doors = {"north":"next","east":"side"}
	var world: Node3D = world_script.new()
	root.add_child(world)
	world.build(definition)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("253729")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff1cc")
	environment.environment.ambient_light_energy = .55
	root.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-28,0)
	sun.light_color = Color("ffe5b2")
	sun.light_energy = .45
	sun.shadow_enabled = true
	root.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.0
	camera.rotation_degrees = Vector3(-35,45,0)
	root.add_child(camera)
	camera.make_current()
	var focus: Vector3 = Vector3(definition.size.x*.69,0,definition.size.y*.70)
	camera.position = focus+camera.basis.z*45.0
	for _index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	var output: String = ProjectSettings.globalize_path("res://../docs/qa/cornfield-evidence/geometry-%s-materials.png" % definition.template_id)
	screenshot.save_png(output)
	print("CORNFIELD_VISUAL: ",output)
	camera.position = Vector3(definition.size.x-4,0,definition.size.y*.5+3)+camera.basis.z*45.0
	for _index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	screenshot = root.get_texture().get_image()
	output = ProjectSettings.globalize_path("res://../docs/qa/cornfield-evidence/geometry-%s-doorway.png" % definition.template_id)
	screenshot.save_png(output)
	print("CORNFIELD_VISUAL: ",output)
	quit()
