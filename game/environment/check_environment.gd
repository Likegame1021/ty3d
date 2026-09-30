extends SceneTree
func _initialize():
	var source = load("res://environment/cornfield.gd")
	assert(source != null, "Environment entry missing")
	var field = source.new()
	root.add_child(field)
	await process_frame
	field.set_night(true)
	field.set_player_position(Vector3(0, 0, 8))
	assert(field.get_node_or_null("Ground") != null, "Missing collision ground")
	assert(field.get_node_or_null("CornPlots") != null, "Missing partitioned corn")
	assert(field.get_node("CornPlots").get_child_count() == 42, "Expected 42 culling plots")
	assert(field.corn_instance_count == 1326, "Unexpected corn population")
	await physics_frame
	await physics_frame
	for pos in [Vector3(0, 0, 8), Vector3(0, 0, -5), Vector3(0, 0, 0)]:
		var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.5, pos - Vector3.UP, 1)
		var hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(query)
		assert(not hit.is_empty(), "Route must have ground")
		assert(absf(hit.position.y) < 0.01, "Route floor must be at zero")
	for pos in [Vector3(3.2, 0, 8.5), Vector3(3.2, 0, 9.6), Vector3(4.0, 0, 10.8), Vector3(-12.5, 0, 13.0)]:
		var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos - Vector3.UP, 1)
		var hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(query)
		assert(not hit.is_empty() and hit.collider.name == "SimplePropCollision" and hit.position.y > 0.4, "Major prop needs simple movement blocker")
	assert(field._corn_materials[0].get_shader_parameter("night") == 1.0, "Night material update missing")
	field.set_night(false)
	assert(field._corn_materials[0].get_shader_parameter("night") == 0.0, "Day material reset missing")
	await process_frame
	var frozen_time: float = field._time
	paused = true
	for i in range(3):
		await process_frame
	assert(field._time == frozen_time, "Pause must freeze wind time")
	paused = false
	print("ENVIRONMENT_CHECK_OK plots=42 corn=1326 ground=spawn,target,route night=toggle")
	quit()



