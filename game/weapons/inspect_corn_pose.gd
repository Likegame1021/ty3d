extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.animation_player.play("idle")
	player.animation_player.seek(0.2, true)
	var skeleton: Skeleton3D = player.body_visual.find_children("*", "Skeleton3D", true, false)[0]
	skeleton.force_update_all_bone_transforms()
	print("Skeleton basis ", skeleton.global_basis, " position ", skeleton.global_position)
	for index in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(index)
		if name.contains("Arm") or name.contains("Hand") or name.contains("Shoulder") or name.contains("Spine"):
			var pose := skeleton.get_bone_global_pose(index)
			var relative: Transform3D = player.visual.global_transform.affine_inverse() * skeleton.global_transform * pose
			print(index, " ", name, " parent ", skeleton.get_bone_parent(index), " rel ", relative.origin, " rot ", relative.basis.orthonormalized().get_euler(), " local rest ", skeleton.get_bone_rest(index))
	for type in ["SkeletonModifier3D", "TwoBoneIK3D", "SkeletonIK3D"]:
		print(type, " exists ", ClassDB.class_exists(type))
		if ClassDB.class_exists(type):
			print(ClassDB.class_get_property_list(type, true))
			print(ClassDB.class_get_method_list(type, true))
	player.free()
	quit(0)
