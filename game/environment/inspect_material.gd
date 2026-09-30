extends SceneTree
func _initialize():
	var s = load('res://assets/environment/corn.glb').instantiate()
	var pending = [s]
	while not pending.is_empty():
		var n = pending.pop_back()
		if n is MeshInstance3D:
			for i in n.mesh.get_surface_count():
				print('COLOR ', n.mesh.surface_get_material(i).albedo_color)
		pending.append_array(n.get_children())
	s.free()
	quit()
