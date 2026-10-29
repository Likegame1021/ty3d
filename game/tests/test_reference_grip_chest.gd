extends SceneTree
## Coordinate contract only; synthetic quaternions do not approve authored motion.
const BONES := ["RightArm", "RightForeArm", "RightHand"]
var failures := 0
var checks := 0
func _initialize(): call_deferred("run_checks")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func finish():
	print("REFERENCE_GRIP_CHEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func run_checks():
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var p = load("res://scripts/player.gd").new()
	root.add_child(p); p.set_physics_process(false)
	p.melee_hold_pose.active = false; p.corn_hold_pose.active = false; p.cancel_pose.active = false
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var helper = p.melee_hold_pose
	check(helper.has_method("model_from_chest_reference"), "carry exposes explicit chest-frame transport")
	if not helper.has_method("model_from_chest_reference"):
		p.free(); finish(); return
	var skeleton: Skeleton3D = helper.get_skeleton()
	var chest := skeleton.find_bone("Spine")
	var shoulder := skeleton.find_bone("RightShoulder")
	var reference_chest := Quaternion(Vector3.UP, .3)
	var reference := {"reference_chest_quaternion_xyzw": [reference_chest.x, reference_chest.y, reference_chest.z, reference_chest.w], "global_rotation_quaternions_xyzw": {}}
	for index in BONES.size():
		var q := Quaternion(Vector3.RIGHT, .2 + index * .15)
		reference.global_rotation_quaternions_xyzw[BONES[index]] = [q.x, q.y, q.z, q.w]
	var before := []
	for bone in skeleton.get_bone_count(): before.append(skeleton.get_bone_pose(bone))
	for phase in [0.0, .12, .41, .75]:
		p.animation_player.play(p.animation_names.run); p.animation_player.seek(phase, true)
		var live := skeleton.get_bone_global_pose(chest).basis.orthonormalized().get_rotation_quaternion()
		var pose: Dictionary = helper.model_from_chest_reference(reference)
		for bone in BONES:
			var a: Array = reference.global_rotation_quaternions_xyzw[bone]
			var expected := (live * reference_chest.inverse() * Quaternion(a[0], a[1], a[2], a[3])).normalized()
			check(pose[bone].angle_to(expected) < .0001, "chest-relative carry follows live RUN chest " + bone)
		var prior: Dictionary = pose.duplicate()
		skeleton.set_bone_pose_rotation(shoulder, Quaternion(Vector3.FORWARD, .4))
		pose = helper.model_from_chest_reference(reference)
		for bone in BONES: check(pose[bone].angle_to(prior[bone]) < .0001, "RightShoulder is not mistakenly used as carry anchor " + bone)
	check(helper._arm_parent_index == shoulder, "actual RightArm parent remains RightShoulder")
	p.free(); finish()
