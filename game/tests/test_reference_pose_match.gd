extends SceneTree
const Reference = preload("res://tests/fixtures/reference-grip-v4-r2/reference.gd")
var failures := 0
var checks := 0
func _initialize():
	call_deferred("run_checks")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func v(a):
	return Vector3(a[0],a[1],a[2])
func matrix(a):
	return Transform3D(Basis(v(a[0]),v(a[1]),v(a[2])),v(a[3]))
func difference(a: Transform3D,b: Transform3D):
	var x=[a.basis.x,a.basis.y,a.basis.z,a.origin]
	var y=[b.basis.x,b.basis.y,b.basis.z,b.origin]
	var result=0.0
	for col in 4:
		for row in 3:result=maxf(result,absf(x[col][row]-y[col][row]))
	return result
func run_checks():
	var reference = Reference.new()
	check(reference.files_match(), "independently approved R2 references remain hash-pinned")
	var path=OS.get_environment("CARRY_TEST_PLAYER")
	if path.is_empty():path="res://scripts/player.gd"
	var player=load(path).new()
	root.add_child(player)
	player.set_physics_process(false)
	player.position=Vector3.ZERO
	player.visual.rotation=Vector3.ZERO
	player.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.corn_hold_pose.active=false
	var modifier=player.melee_hold_pose
	check(modifier.has_method("advance_state"),"runtime has the reviewed data-driven carry/state layer")
	var body=player.body_visual.find_child("BoyBody",true,false) as MeshInstance3D
	check(body.mesh == modifier.grip_closed_mesh and body.get_blend_shape_count() == 0, "runtime uses reviewed closed-only topology")
	if not modifier.has_method("advance_state"):
		player.free()
		print("NORMAL_REFERENCE_POSE_MATCH: %d checks, %d failures"%[checks,failures])
		quit(1)
		return
	var data=JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("reference_pose_master.json")))
	var skeleton=player.body_visual.find_children("*","Skeleton3D",true,false)[0]
	check(difference(player.body_visual.get_child(0).transform,matrix(data.original_body_fit))<0.000001,"mesh-only replacement keeps original body fitting transform")
	for sample in data.samples:
		player.animation_player.stop()
		skeleton.reset_bone_poses()
		player.current_animation=sample.clip
		player.animation_player.play(player.animation_names[sample.clip],0.0)
		player.animation_player.seek(sample.time,true)
		player.animation_player.advance(0.0)
		player.velocity=Vector3(0,0,3.0 if sample.clip=="run" else 0.0)
		player.attack.elapsed=sample.time if sample.clip=="attack_branch" else 0.0
		player.attack.remaining=player.attack.duration-sample.time if sample.clip=="attack_branch" else 0.0
		# Preserve all 21 old world-space goldens. Reconstruct only the three
		# newly approved rotations using their old, unchanged local offsets/scales.
		var original_world := {}
		for bone in sample.poses: original_world[int(bone.index)] = matrix(bone.global_world)
		var expected_world := original_world.duplicate()
		var rotations: Dictionary = reference.attack_local_rotations(sample.time) if sample.clip == "attack_branch" else reference.carry_model_rotations(skeleton, sample.clip)
		for name in Reference.ARM:
			var index: int = skeleton.find_bone(name)
			var parent: int = skeleton.get_bone_parent(index)
			var old_local: Transform3D = original_world[parent].affine_inverse() * original_world[index]
			if sample.clip == "attack_branch":
				old_local.basis = Basis(rotations[name]).scaled(old_local.basis.get_scale())
				expected_world[index] = expected_world[parent] * old_local
			else:
				var world_q: Quaternion = skeleton.global_transform.basis.orthonormalized().get_rotation_quaternion() * rotations[name]
				expected_world[index] = Transform3D(Basis(world_q.normalized()).scaled(original_world[index].basis.get_scale()), expected_world[parent] * old_local.origin)
		modifier.advance_state(1.0)
		modifier._process_modification()
		skeleton.force_update_all_bone_transforms()
		var maximum=0.0
		for bone in sample.poses:
			var actual: Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(bone.index)
			var error=difference(actual,expected_world[int(bone.index)])
			maximum=maxf(maximum,error)
			check(error<0.00001,"%s bone%s matches independently viewed reference"%[sample.name,bone.bone])
		var hand_world: Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
		var socket_world: Transform3D=hand_world*player.branch_pivot.transform
		var axis: Vector3 = v(reference.grip.shaft_axis_toward_tip)
		var normal: Vector3 = v(reference.grip.palm_outward_normal)
		var approved_socket := Transform3D(Basis(axis.cross(normal), axis, normal), v(reference.grip.grip_center_right_hand_local))
		var expected_socket: Transform3D = expected_world[skeleton.find_bone("RightHand")] * approved_socket
		check((socket_world*Vector3(0,-0.07,0)).distance_to(expected_socket*Vector3(0,-.07,0))<0.00001,"%s butt matches fixed-grip reference"%sample.name)
		check((socket_world*Vector3(0,0.63,0)).distance_to(expected_socket*Vector3(0,.63,0))<0.00001,"%s tip matches fixed-grip reference"%sample.name)
		print("REFERENCE_MATCH ",sample.name," max_matrix_error=",maximum)
	player.free()
	print("NORMAL_REFERENCE_POSE_MATCH: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
