extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var skeleton: Skeleton3D = player.body_visual.find_children("*", "Skeleton3D", true, false)[0]
	var arm_names := ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]
	for clip in ["idle", "walk", "run"]:
		player.animation_player.play(clip)
		player.animation_player.seek(0.25, true)
		player.animation_player.pause()
		var original: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			original.append(skeleton.get_bone_pose(bone))
		player.ranged_stance = true
		player.corn_hold_pose._process_modification()
		for bone in skeleton.get_bone_count():
			if not skeleton.get_bone_name(bone) in arm_names:
				assert(skeleton.get_bone_pose(bone).is_equal_approx(original[bone]), "Non-arm bone changed")
		var hand := skeleton.find_bone("RightHand")
		var hand_position: Vector3 = player.visual.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
		assert(hand_position.distance_to(Vector3(-0.13, 0.68, 0.145)) < 0.006, "Right hand missed grip position")
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone, original[bone])
		player.ranged_stance = false
		player.corn_hold_pose._process_modification()
		for bone in skeleton.get_bone_count():
			assert(skeleton.get_bone_pose(bone).is_equal_approx(original[bone]), "Unequipped pose changed")
		player.ranged_stance = true
		player.context_remaining = 1.0
		player.corn_hold_pose._process_modification()
		for bone in skeleton.get_bone_count():
			assert(skeleton.get_bone_pose(bone).is_equal_approx(original[bone]), "Interaction pose changed")
		player.context_remaining = 0.0
		print("PASS: ", clip, " grip solved; legs and unequipped/interaction pose preserved")
	player.free()
	quit(0)
