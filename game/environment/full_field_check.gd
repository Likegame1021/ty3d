extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script = load("res://environment/full_field.gd")
	assert(script != null)
	var field: Node3D = script.new()
	root.add_child(field)
	await physics_frame
	await physics_frame
	assert(field.plot_count > 100 and field.corn_instance_count > 2000 and field.corn_instance_count < 10000)
	for asset in ["shed", "cart", "tree"]:
		assert(ResourceLoader.exists("res://assets/environment/meshy/%s.glb" % asset), "M2 Meshy asset must import: " + asset)
	var shed_visual := field.get_node_or_null("FarmToolYard/ToolShed/MeshyShedVisual")
	assert(shed_visual != null and shed_visual.find_child("RoofVisual", true, false) != null)
	assert(not field.get_node("FarmToolYard/ToolShed/ProceduralShedVisual").visible)
	assert(field._cart_visual.get_node_or_null("MeshyCartVisual") != null)
	assert(not field._cart_visual.get_node("ProceduralCartVisual").visible)
	assert(field.get_node_or_null("CanalCrossing/CanalGateBlocker") != null)
	var query := PhysicsRayQueryParameters3D.create(Vector3(5, 0.9, 21), Vector3(5, 0.9, 17), 1)
	var closed_hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not closed_hit.is_empty() and closed_hit.collider.name == "CanalGateBlocker", "Closed canal must block bridge")
	assert(field._clog_visual.visible and field._standing_mouth_corn.visible)
	var cart_query := PhysicsRayQueryParameters3D.create(Vector3(16, 0.8, -11.7), Vector3(16, 0.8, -14.3), 1)
	var cart_hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(cart_query)
	assert(not cart_hit.is_empty() and cart_hit.collider.name == "CartBodyCollision", "Cart must physically occupy its starting position")
	field.set_progress({"mouth_cleared": true})
	assert(not field._clog_visual.visible and field._wetland_material.get_shader_parameter("mouth_cleared") == 1.0)
	assert(field._water_material.get_shader_parameter("flowing") == 0.0)
	assert(not field.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	field.set_progress({"canal_open": true, "cart_moved": true, "launcher_taken": true, "corn_spilled": true})
	await physics_frame
	var open_hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(query)
	assert(open_hit.is_empty(), "Opened bridge must permit crossing")
	assert(field.get_world_3d().direct_space_state.intersect_ray(cart_query).is_empty(), "Moved cart must clear its starting position")
	var shed_passage := PhysicsRayQueryParameters3D.create(Vector3(17, 0.9, -15.7), Vector3(17, 0.9, -19.5), 1)
	assert(field.get_world_3d().direct_space_state.intersect_ray(shed_passage).is_empty(), "Shed center passage must stay open after cart moves")
	var shed_side := PhysicsRayQueryParameters3D.create(Vector3(13, 0.9, -18), Vector3(15, 0.9, -18), 1)
	assert(not field.get_world_3d().direct_space_state.intersect_ray(shed_side).is_empty(), "Shed side wall must block bypass")
	var shed_back := PhysicsRayQueryParameters3D.create(Vector3(17, 0.9, -20.5), Vector3(17, 0.9, -22.7), 1)
	assert(not field.get_world_3d().direct_space_state.intersect_ray(shed_back).is_empty(), "Shed back wall must block bypass")
	assert(not field._gate_visual.visible and not field._launcher_visual.visible and field._spill_visual.visible)
	assert(field._water_material.get_shader_parameter("flowing") == 1.0)
	assert(field._fallen_mouth_corn.visible and not field._standing_mouth_corn.visible)
	var sources: Array[Vector3] = [Vector3(-7, 0, 9), Vector3(0, 0, -34)]
	field.set_actor_sources(sources)
	field.set_player_position(Vector3(0, 0, 35))
	field.set_player_position(Vector3(17, 0, -18))
	assert(not field._shed_roof_visual.visible, "Shed roof should reveal the player and launcher")
	field.set_player_position(Vector3(10, 0, -10))
	assert(field._shed_roof_visual.visible, "Shed roof should return when player leaves")
	field.set_player_position(Vector3(0, 0, 35))
	field.set_night(true)
	field.set_weather("rain")
	await process_frame
	assert(field._weather_node._rain.visible and not field._weather_node._snow.visible)
	assert(field._corn_materials[0].get_shader_parameter("source_a") == Vector3(-7, 0, 9))
	field.set_weather("snow")
	assert(field._weather_node._snow.visible and not field._weather_node._rain.visible)
	assert(field._meshy_roof_meshes.size() > 0 and field._meshy_cart_meshes.size() > 0)
	assert(field._meshy_roof_meshes[0].material_overlay != null)
	assert(field._meshy_cart_meshes[0].material_overlay != null)
	var frozen_time: float = field._time
	var frozen_weather_time: float = field._weather_node._time
	paused = true
	for i in 3:
		await process_frame
	assert(field._time == frozen_time and field._weather_node._time == frozen_weather_time)
	paused = false
	field.reset_field()
	await physics_frame
	assert(field.weather == "sunny" and not field.night and not field.progress.canal_open)
	assert(field._meshy_roof_meshes[0].material_overlay == null and field._meshy_cart_meshes[0].material_overlay == null)
	assert(not field.progress.mouth_cleared and field._clog_visual.visible and not field._fallen_mouth_corn.visible)
	assert(not field._weather_node._rain.visible and not field._weather_node._snow.visible)
	assert(not field.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	print("FULL_ENVIRONMENT_OK plots=", field.plot_count, " corn=", field.corn_instance_count, " bridge=closed/open/closed weather=sunny/rain/snow pause=freeze")
	field.queue_free()
	await process_frame
	quit()
