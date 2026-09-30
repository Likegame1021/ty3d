extends SceneTree
func _initialize():
	var script = load("res://environment/entry_field.gd")
	assert(script != null, "M1 environment missing")
	var field = script.new()
	root.add_child(field)
	await process_frame
	field.set_story_sources(Vector3(-3.8,0,7),Vector3(-1.8,0,-6),true)
	field.set_story_stage(2)
	field.set_player_position(Vector3(-5.5,0,1))
	await process_frame
	assert(field.get_node_or_null("ExitGateway") != null)
	assert(field.story_stage == 2 and field._creature_active)
	var material: ShaderMaterial = field._corn_materials[0]
	assert(material.shader.resource_path == "res://environment/entry_corn.gdshader")
	assert(field.corn_instance_count < 1326, "Side route must remove some stalks")
	assert(material.get_shader_parameter("chicken_position") == Vector3(-3.8,0,7))
	assert(material.get_shader_parameter("creature_position") == Vector3(-1.8,0,-6))
	assert(material.get_shader_parameter("creature_active") == 1.0)
	assert(not FileAccess.get_file_as_string("res://environment/entry_corn.gdshader").contains("disturbance_position"))
	field.set_story_sources(Vector3(-3.2,0,6.2),Vector3(-2.2,0,-6),false)
	await process_frame
	assert(material.get_shader_parameter("chicken_position") == Vector3(-3.2,0,6.2))
	assert(material.get_shader_parameter("creature_active") == 0.0)
	await physics_frame
	await physics_frame
	var route: Array[Vector3] = [Vector3(0,0,12),Vector3(-1.8,0,9.2),Vector3(-3.8,0,7),Vector3(-5.5,0,1),Vector3(-1.7,0,-2.7),Vector3(0,0,-6),Vector3(0,0,-13)]
	var capsule := CapsuleShape3D.new()
	capsule.radius = .22
	capsule.height = 1.2
	var samples := 0
	for i in range(route.size()-1):
		var distance := route[i].distance_to(route[i+1])
		for j in range(int(distance/.25)+1):
			var pos := route[i].lerp(route[i+1],float(j)/maxi(1,int(distance/.25)))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis.IDENTITY,pos+Vector3.UP*.7)
			query.collision_mask = 1
			assert(field.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Blocked tutorial route")
			var ray := PhysicsRayQueryParameters3D.create(pos+Vector3.UP*.09,pos-Vector3.UP,1)
			var hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(ray)
			assert(not hit.is_empty() and absf(hit.position.y)<.01,"Missing path floor")
			samples += 1
	for plot in field.get_node("CornPlots").get_children():
		for i in range(plot.multimesh.instance_count):
			var pos: Vector3 = plot.position+(plot.multimesh.get_meta("source_transforms")[i] as Transform3D).origin
			assert(field._path_distance(Vector2(pos.x,pos.z)) >= .43,"Corn planted inside side path")
	assert(field._chirp.data.size() > 10000 and field._rustle.data.size() > 10000)
	field._chirp.save_to_wav("res://environment/entry_chirp.wav")
	field._rustle.save_to_wav("res://environment/entry_rustle.wav")
	var frozen_time: float = field._time
	paused = true
	for i in range(3):
		await process_frame
	assert(field._time == frozen_time,"Pause must freeze wind/audio schedule")
	paused = false
	field.set_story_stage(3)
	await process_frame
	assert(material.get_shader_parameter("creature_active") == 0.0)
	assert(not field._chicken_voice.playing and not field._creature_voice.playing)
	field.reset_story()
	assert(field.story_stage == 0 and not field._creature_active and field._time == 0.0)
	assert(material.get_shader_parameter("chicken_position") == Vector3(1000,0,1000))
	print("ENTRY_ENVIRONMENT_OK plots=42 corn=",field.corn_instance_count," route_samples=",samples," actual_sources=pause,reset,disabled audio=generated")
	quit()


