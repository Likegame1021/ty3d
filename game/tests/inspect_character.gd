extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var player = game.player
	player.set_physics_process(false)
	var skeleton: Skeleton3D = player.body_visual.find_children("*", "Skeleton3D", true, false)[0]
	var hand := skeleton.find_bone("RightHand")
	var hips := skeleton.find_bone("Hips")
	player.animation_player.play("attack_branch")
	var samples := []
	for frame in 21:
		var seconds := 0.50 + frame * 0.01
		player.animation_player.seek(seconds, true)
		skeleton.force_update_all_bone_transforms()
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
		var relative_hand: Vector3 = player.visual.global_transform.affine_inverse() * pose.origin
		var hand_axis: Vector3 = (player.visual.global_transform.basis.inverse() * pose.basis.y).normalized()
		var tip := relative_hand + hand_axis * 0.675
		print("t=%.2f hand=" % seconds, relative_hand, " axisY=", hand_axis, " tip=", tip)
		samples.append({"seconds": seconds, "hand": [relative_hand.x, relative_hand.y, relative_hand.z], "hand_axis_y": [hand_axis.x, hand_axis.y, hand_axis.z], "tip": [tip.x, tip.y, tip.z]})
	var output := FileAccess.open("res://tests/character-hand-samples.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"animations": player.animation_player.get_animation_list(), "bone_status": player.bone_status, "attack_length": player.animation_player.get_animation("attack_branch").length, "samples": samples}, "  "))
	game.queue_free()
	await process_frame
	quit()
