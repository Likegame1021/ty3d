extends SceneTree
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const World = preload("res://scripts/cornfield/room_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func _run() -> void:
	for index in [2,3,6,8,9,23]:
		var definition := Catalog.make_template(index)
		check(definition.has("presentation"),"six key rooms have authored visual profiles")
	if failures.size()>0:
		_finish()
		return
	for index in [2,3,6,8,9,23]:
		var definition := Catalog.make_template(index)
		definition.doors = {"north":"north","south":"south"}
		var world := World.new()
		root.add_child(world)
		world.build(definition)
		await physics_frame
		await physics_frame
		check(world.has_node("FieldDetails"),"key room builds visual landmarks")
		check(world.has_node("FieldDetails/GroundLitter"),"shared soil has batched low rural debris")
		if world.has_node("FieldDetails/GroundLitter"):
			var litter: MultiMeshInstance3D = world.get_node("FieldDetails/GroundLitter")
			check(litter.multimesh.instance_count >= 80,"large rooms have grounded detail density at normal camera")
			check(litter.custom_aabb.end.y < .025,"ground detail stays below birth and attack telegraphs")
		for item in definition.obstacles:
			var body: Node3D = world.get_node("Terrain/"+str(item.id))
			if item.kind == "corn":
				var batch: MultiMeshInstance3D = body.get_node("CornBatch")
				check(batch.custom_aabb.position.y+body.position.y >= .16,"corn stalk roots sit above the visible soil bed")
			if item.kind in ["brick","water"]:
				var family := "broken-red-brick-wall" if item.kind == "brick" else "shallow-irrigation-bank"
				var accepted_count := 0
				for mesh in body.find_children("*","MultiMeshInstance3D",true,false):
					if str(mesh.get_meta("asset_id","")).begins_with(family):
						accepted_count += mesh.multimesh.instance_count
				check(accepted_count >= 2,"accepted original module is used for "+str(item.kind))
			if item.kind == "hay" and index == 3:
				var batch: MultiMeshInstance3D = body.get_node("HayBatch")
				check(batch.multimesh.instance_count <= 6,"hay yard islands read as broad hay mounds rather than tiny repeated cones")
				check(batch.custom_aabb.size.y >= 1.5,"hay yard keeps a substantial piled-straw silhouette at the fixed camera")
		if index == 23:
			check(world.has_node("FieldDetails/NestChurn"),"boss core has low original churned-soil dressing")
			for item in definition.obstacles:
				if item.kind == "corn":
					var batch: MultiMeshInstance3D = world.get_node("Terrain/"+str(item.id)+"/CornBatch")
					check(str(batch.get_meta("asset_id","")).begins_with("fallen-corn-stalk"),"nest edge uses accepted fallen stalks instead of standing crop rows")
		if index == 8:
			check(world.get_node("Terrain/terrain_0").has_node("PumpToolRack"),"pump landmark groups the existing tools beside the machine")
			check(world.get_node("Terrain/terrain_0").has_node("PumpSupplies"),"pump landmark includes existing rural supplies inside its footprint")
		if index == 6:
			check(world.get_node("Ground").find_children("FurrowLane*","MeshInstance3D",false,false).size() == 3,"long furrows visibly mark three clear longitudinal lanes")
		check(world._door_labels.size()==2,"door states have readable text")
		for label in world._door_labels.values():
			check(label.text.contains("清场"),"locked door has noncolor locked indication")
		world.set_doors_open(true)
		for label in world._door_labels.values():
			check(label.text.contains("通行"),"clear state shows traversable door")
		world.set_route_unlocked(true)
		for label in world._door_labels.values():
			check(label.text.contains("通行") and not label.text.contains("下一节点"),"node unlock leaves physical doors within the current node")
		if index==2:
			for bridge: Node3D in world.get_node("FieldDetails").find_children("PassableCanalBridge*","Node3D",false,false):
				for part: MeshInstance3D in bridge.find_children("*","MeshInstance3D",true,false):
					var box: AABB = part.global_transform*part.get_aabb()
					check(box.end.y < .025,"bridge visuals cannot cover ground attack or birth warning fills")
			check(definition.presentation.bridge_zones.size()==2,"double canal retains two bridges")
			for zone: Rect2 in definition.presentation.bridge_zones:
				var touching_water := 0
				for obstacle in definition.obstacles:
					var canal: Rect2 = obstacle.rect
					if obstacle.kind == "water" and is_equal_approx(canal.get_center().x,zone.get_center().x):
						if is_equal_approx(canal.end.y,zone.position.y) or is_equal_approx(canal.position.y,zone.end.y):
							touching_water += 1
				check(touching_water == 2,"each actual 2.7m crossing joins water at both deck edges")
				check(is_equal_approx(zone.size.y,2.7),"crossing width remains exactly 2.7m")
				var at := Vector3(zone.get_center().x,0,zone.get_center().y)
				check(world.segment_clear(at+Vector3.LEFT*(zone.size.x*.5+1.0),at+Vector3.RIGHT*(zone.size.x*.5+1.0),.625),"largest actor crosses full deck between canal banks")
				check(world.contains_ground(at,.22),"bridge remains physically traversable")
				var capsule := CapsuleShape3D.new()
				capsule.radius = .625
				capsule.height = 1.30
				for side in [-1,1]:
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = capsule
					query.collision_mask = 1
					query.margin = .001
					query.transform.origin = at+Vector3(side*(zone.size.x*.5+1.0),.66,0)
					query.motion = Vector3(-side*(zone.size.x+2.0),0,0)
					var fractions := world.get_world_3d().direct_space_state.cast_motion(query)
					check(fractions.size() == 2 and fractions[0] > .999,"physical largest-actor capsule crosses each bridge in both directions")
				check(world.is_spawn_excluded(at,.34),"bridge excludes enemy spawns")
				check(not world.path_to(world.definition.entry_position,at).is_empty(),"bridge connects to shared navigation")
		if index == 9:
			var rectangle: Rect2 = definition.obstacles[0].rect
			var actor := Node3D.new()
			root.add_child(actor)
			actor.position = Vector3(rectangle.position.x-.75,0,rectangle.get_center().y)
			var camera := Camera3D.new()
			root.add_child(camera)
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 15.0
			camera.position = actor.position+Vector3(15,19,15)
			camera.look_at(actor.position+Vector3.UP*.4,Vector3.UP)
			world.set_occlusion_target(camera,actor)
			await physics_frame
			world._physics_process(.2)
			var wall: MultiMeshInstance3D = world.get_node("Terrain/terrain_0/BrokenWallBatch")
			check(not wall.visible,"accepted wall cuts away when it hides an actor at the normal camera")
			actor.position += Vector3(12,0,12)
			world._physics_process(.2)
			check(wall.visible,"accepted wall is restored after the actor leaves its shadow")
			camera.queue_free()
			actor.queue_free()
		world.queue_free()
		await process_frame
	_finish()
func _finish() -> void:
	print("CORNFIELDS_PRESENTATION %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
