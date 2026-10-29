extends RefCounted
## One fitted actor, two cached mesh resources. The accepted v2 zero morph is open.
const OPEN_SCENE_PATH := "res://assets/characters/boy/normal_grip/boy-closed-grip-v2.glb"
const HAND_SCENE_PATH := "res://assets/characters/boy/normal_grip/v4/boy-closed-diagonal-surface-v4.glb"

static func apply(model: Node3D) -> Dictionary:
	var open_scene := ResourceLoader.load(OPEN_SCENE_PATH, "PackedScene") as PackedScene
	var closed_scene := ResourceLoader.load(HAND_SCENE_PATH, "PackedScene") as PackedScene
	if open_scene == null or closed_scene == null:
		push_error("Cannot load reviewed open/closed hand mesh resources")
		return {}
	var open_import := open_scene.instantiate()
	var closed_import := closed_scene.instantiate()
	var result := apply_imports(model, open_import, closed_import)
	open_import.free()
	closed_import.free()
	return result

static func apply_imports(model: Node3D, open_import: Node, closed_import: Node) -> Dictionary:
	var target := model.find_child("BoyBody", true, false) as MeshInstance3D
	var opened := open_import.find_child("BoyBody", true, false) as MeshInstance3D
	var closed := closed_import.find_child("BoyBody", true, false) as MeshInstance3D
	# Validate the whole contract before touching the existing fitted actor.
	if not compatible(target, opened) or not compatible(target, closed):
		return {}
	if closed.mesh.get_blend_shape_count() != 0:
		return {}
	var open_shape := -1
	for index in opened.mesh.get_blend_shape_count():
		if opened.mesh.get_blend_shape_name(index) == "Grip_Right": open_shape = index
	if open_shape < 0 or not is_zero_approx(opened.get_blend_shape_value(open_shape)):
		return {}
	var open_mesh: ArrayMesh = opened.mesh.duplicate()
	var closed_mesh: ArrayMesh = closed.mesh.duplicate()
	for surface in target.mesh.get_surface_count():
		var material := target.mesh.surface_get_material(surface)
		open_mesh.surface_set_material(surface, material)
		closed_mesh.surface_set_material(surface, material)
	target.mesh = closed_mesh
	return {"mesh": target, "open_mesh": open_mesh, "closed_mesh": closed_mesh}

static func compatible(target: MeshInstance3D, candidate: MeshInstance3D) -> bool:
	if target == null or candidate == null or not target.mesh is ArrayMesh or not candidate.mesh is ArrayMesh:
		return false
	if target.mesh.get_surface_count() != candidate.mesh.get_surface_count() or not target.transform.is_equal_approx(candidate.transform):
		return false
	var target_skeleton := target.get_node_or_null(target.skeleton) as Skeleton3D
	var candidate_skeleton := candidate.get_node_or_null(candidate.skeleton) as Skeleton3D
	if target_skeleton == null or candidate_skeleton == null or target.skeleton != candidate.skeleton:
		return false
	if target_skeleton.get_bone_count() != candidate_skeleton.get_bone_count() or not target_skeleton.transform.is_equal_approx(candidate_skeleton.transform):
		return false
	for bone in target_skeleton.get_bone_count():
		if target_skeleton.get_bone_name(bone) != candidate_skeleton.get_bone_name(bone) or target_skeleton.get_bone_parent(bone) != candidate_skeleton.get_bone_parent(bone):
			return false
		if not target_skeleton.get_bone_rest(bone).is_equal_approx(candidate_skeleton.get_bone_rest(bone)):
			return false
	var original_skin := target.skin
	var imported_skin := candidate.skin
	if original_skin == null or imported_skin == null or original_skin.get_bind_count() != imported_skin.get_bind_count():
		return false
	for bind in original_skin.get_bind_count():
		if original_skin.get_bind_name(bind) != imported_skin.get_bind_name(bind) or original_skin.get_bind_bone(bind) != imported_skin.get_bind_bone(bind):
			return false
		if not original_skin.get_bind_pose(bind).is_equal_approx(imported_skin.get_bind_pose(bind)):
			return false
	for surface in candidate.mesh.get_surface_count():
		if target.mesh.surface_get_primitive_type(surface) != candidate.mesh.surface_get_primitive_type(surface):
			return false
		var arrays := candidate.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or joints.size() != weights.size() or joints.size() not in [vertices.size() * 4, vertices.size() * 8]:
			return false
		var stride: int = joints.size() / vertices.size()
		for vertex in vertices.size():
			var total := 0.0
			for influence in stride:
				var index := vertex * stride + influence
				if joints[index] < 0 or joints[index] >= imported_skin.get_bind_count() or not is_finite(weights[index]) or weights[index] < 0.0:
					return false
				total += weights[index]
			if absf(total - 1.0) > .001: return false
	return true
