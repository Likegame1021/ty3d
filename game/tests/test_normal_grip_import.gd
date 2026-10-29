extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run_checks")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func finish() -> void:
	print("NORMAL_GRIP_IMPORTED_SCENE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func run_checks() -> void:
	var original := ResourceLoader.load("res://assets/characters/boy/boy.glb", "PackedScene") as PackedScene
	var accepted := ResourceLoader.load("res://assets/characters/boy/normal_grip/v4/boy-closed-diagonal-surface-v4.glb", "PackedScene") as PackedScene
	check(original != null and accepted != null, "both GLBs load through imported PackedScene resources")
	if original == null or accepted == null:
		finish()
		return
	var source := original.instantiate()
	var derivative := accepted.instantiate()
	var source_mesh := source.find_child("BoyBody", true, false) as MeshInstance3D
	var derivative_mesh := derivative.find_child("BoyBody", true, false) as MeshInstance3D
	check(source_mesh != null and derivative_mesh != null, "cold imported scenes expose BoyBody")
	if source_mesh == null or derivative_mesh == null:
		source.free()
		derivative.free()
		finish()
		return
	var original_skin := source_mesh.skin
	var derivative_skin := derivative_mesh.skin
	check(original_skin != null and derivative_skin != null, "both cold imports retain Skin resources")
	if original_skin != null and derivative_skin != null:
		check(original_skin.get_bind_count() == derivative_skin.get_bind_count(), "mesh-only replacement has the same Skin bind count")
		var same_mapping := original_skin.get_bind_count() == derivative_skin.get_bind_count()
		var same_poses := same_mapping
		for bind in mini(original_skin.get_bind_count(), derivative_skin.get_bind_count()):
			same_mapping = same_mapping and original_skin.get_bind_name(bind) == derivative_skin.get_bind_name(bind) and original_skin.get_bind_bone(bind) == derivative_skin.get_bind_bone(bind)
			same_poses = same_poses and original_skin.get_bind_pose(bind).is_equal_approx(derivative_skin.get_bind_pose(bind))
		check(same_mapping, "cold import preserves bind-index to named-bone mapping")
		check(same_poses, "cold import preserves inverse bind transforms")
	var material := source_mesh.mesh.surface_get_material(0)
	var animation := source.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton := source.find_children("*", "Skeleton3D", true, false)[0]
	var fitted_transform: Transform3D = source.transform
	var rests := []
	for bone in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(bone))
	var applied: Dictionary = load("res://weapons/normal_grip_mesh.gd").apply(source)
	check(not applied.is_empty(), "production PackedScene helper applies accepted mesh")
	if not applied.is_empty():
		check(applied.mesh == source_mesh, "helper retains the original mesh node")
		check(source_mesh.skin == original_skin, "helper retains the original Skin instance")
		check(source_mesh.mesh.surface_get_material(0) == material, "helper retains source material instance")
		check(source.find_children("*", "AnimationPlayer", true, false)[0] == animation, "helper retains source AnimationPlayer")
		check(source.transform == fitted_transform, "helper does not refit or move source model")
		check(source_mesh.mesh == applied.closed_mesh and applied.closed_mesh.get_blend_shape_count() == 0, "helper installs honest closed-only topology")
		check(applied.open_mesh != applied.closed_mesh, "helper retains a separate accepted open resource")
		var rests_equal := true
		for bone in skeleton.get_bone_count():
			rests_equal = rests_equal and skeleton.get_bone_rest(bone) == rests[bone]
		check(rests_equal, "helper preserves every source skeleton rest")
	source.free()
	derivative.free()
	finish()
