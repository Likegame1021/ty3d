extends SkeletonModifier3D
## Reviewed normal grip over the original body and attack clocks.
const INPUTS := "res://assets/characters/boy/normal_grip/v4/"
const ARM_BONES := ["RightArm", "RightForeArm", "RightHand"]
const MOVEMENT_BLEND := 0.22
const ATTACK_ENTRY_BLEND := 0.24
const HANDS_BUSY := ["pick_up", "interact", "push", "vault"]
const STOW_BODY_SETTLE := 0.18
const EXIT_BODY_SETTLE := 0.16
const EXIT_ARM_SETTLE := 0.22
var player
var grip_mesh: MeshInstance3D
var grip_open_mesh: ArrayMesh
var grip_closed_mesh: ArrayMesh
var _branch_mesh: MeshInstance3D
var _stow_remaining := 0.0
var grip_data: Dictionary
var records := {}
var attack_records: Array = []
var indices := {}
var _run_weight := 0.0
var _run_from := 0.0
var _run_target := 0.0
var _run_elapsed := MOVEMENT_BLEND
var _motion_from_pose := {}
var _last_carry_pose := {}
var _last_pose := {}
var _entry_pose := {}
var _was_attacking := false
var _last_attack_time := -1.0
var _exit_pose := {}
var _exit_elapsed := EXIT_BODY_SETTLE + EXIT_ARM_SETTLE
var _exit_rebase_live := false
var _exit_parent_seed := Quaternion.IDENTITY
var _last_parent_rotation := Quaternion.IDENTITY
var _arm_parent_index := -1
var _chest_index := -1
var _source_attack: Animation
var _attack_tracks := {}
var _refresh_reset_seed := false

static func vector_from(a) -> Vector3:
	return Vector3(a[0],a[1],a[2])
static func matrix_from(a) -> Transform3D:
	return Transform3D(Basis(vector_from(a[0]),vector_from(a[1]),vector_from(a[2])),vector_from(a[3]))

static func quaternion_from(value) -> Quaternion:
	return Quaternion(value[0], value[1], value[2], value[3]).normalized()

static func valid_quaternion(value) -> bool:
	if not value is Array or value.size() != 4: return false
	var norm := 0.0
	for component in value:
		if not (component is float or component is int) or not is_finite(component): return false
		norm += component * component
	return absf(norm - 1.0) < .001

func load_reference_data(carry: Dictionary, attack: Dictionary) -> bool:
	# Parse both complete files before changing the active motion contract.
	if carry.get("anchor_bone") != "Spine" or carry.get("actual_parent_bone") != "RightShoulder": return false
	if not carry.get("records") is Array or not attack.get("records") is Array: return false
	var duration = attack.get("duration_s")
	if not (duration is float or duration is int) or not is_finite(duration): return false
	if absf(float(duration) - _source_attack.length) > .00001: return false
	if attack.get("hit_window_s") != [.59, .63]: return false
	var new_carry := {}
	for record in carry.records:
		if not record is Dictionary or record.get("name") not in ["idle", "run"]: return false
		if new_carry.has(record.name) or not valid_quaternion(record.get("reference_chest_quaternion_xyzw")): return false
		var globals = record.get("global_rotation_quaternions_xyzw")
		if not globals is Dictionary or globals.size() != ARM_BONES.size(): return false
		for bone in ARM_BONES:
			if not valid_quaternion(globals.get(bone)): return false
		new_carry[record.name] = record
	if new_carry.size() != 2: return false
	var new_attack: Array = []
	var previous := -1.0
	for record in attack.records:
		if not record is Dictionary: return false
		var source_time = record.get("time")
		if not (source_time is float or source_time is int): return false
		var time := float(source_time)
		if not is_finite(time) or time < 0.0 or time <= previous: return false
		var values = record.get("local_quaternions_xyzw")
		if not values is Dictionary or values.size() != ARM_BONES.size(): return false
		var rotations := {}
		for bone in ARM_BONES:
			if not valid_quaternion(values.get(bone)): return false
			rotations[bone] = quaternion_from(values[bone])
		new_attack.append({"time": time, "rotations": rotations})
		previous = time
	if new_attack.size() < 2 or not is_zero_approx(new_attack[0].time) or absf(previous - _source_attack.length) > .00001: return false
	records = new_carry
	attack_records = new_attack
	return true

func _ready() -> void:
	grip_data = JSON.parse_string(FileAccess.get_file_as_string(INPUTS + "grip-frame.json"))
	var skeleton := get_skeleton()
	for bone in ARM_BONES:
		indices[bone] = skeleton.find_bone(bone)
	_arm_parent_index = skeleton.get_bone_parent(indices["RightArm"])
	_chest_index = skeleton.find_bone("Spine")
	_source_attack = player.animation_player.get_animation("attack_branch")
	for bone in ARM_BONES:
		for track in _source_attack.get_track_count():
			if _source_attack.track_get_type(track) == Animation.TYPE_ROTATION_3D and String(_source_attack.track_get_path(track)).ends_with(":" + bone):
				_attack_tracks[bone] = track
		assert(_attack_tracks.has(bone))
	var carry = JSON.parse_string(FileAccess.get_file_as_string(INPUTS + "carry-reference.json"))
	var attack = JSON.parse_string(FileAccess.get_file_as_string(INPUTS + "attack-reference.json"))
	if not carry is Dictionary or not attack is Dictionary or not load_reference_data(carry, attack):
		push_error("Invalid v4 carry/attack profile; modifier left inactive")
		return
	_last_parent_rotation = skeleton.get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()
	_last_pose = model_from_chest_reference(records["idle"])
	_last_carry_pose = _last_pose.duplicate()
	_motion_from_pose = _last_pose.duplicate()
	var branch: MeshInstance3D = player.branch_pivot.get_node("Branch")
	_branch_mesh = branch
	branch.mesh = make_branch_profile()
	branch.position = Vector3.ZERO
	branch.rotation = Vector3.ZERO
	apply_socket()

func reset_carry_state() -> void:
	_refresh_reset_seed = true
	_run_weight = 0.0
	_run_from = 0.0
	_run_target = 0.0
	_run_elapsed = MOVEMENT_BLEND
	_stow_remaining = 0.0
	_exit_elapsed = EXIT_BODY_SETTLE + EXIT_ARM_SETTLE
	_exit_pose.clear()
	_was_attacking = false
	_last_attack_time = -1.0
	if not records.is_empty():
		_last_pose = model_from_chest_reference(records["idle"])
		_last_carry_pose = _last_pose.duplicate()
		_motion_from_pose = _last_pose.duplicate()
		_last_parent_rotation = get_skeleton().get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()

func advance_state(delta: float) -> void:
	if player.context_remaining > 0.0 and player.context_action in HANDS_BUSY:
		_stow_remaining = STOW_BODY_SETTLE
	else:
		_stow_remaining = maxf(0.0,_stow_remaining-delta)
	_exit_elapsed = minf(_exit_elapsed + delta,EXIT_BODY_SETTLE + EXIT_ARM_SETTLE)
	# Ordinary carry follows the body's measured-displacement decision, including walls.
	var desired := 1.0 if player.current_animation == "run" else 0.0
	if player.attack.remaining > 0.0 or player.context_remaining > 0.0:
		desired = 1.0 if Vector2(player.velocity.x,player.velocity.z).length() > 0.01 else 0.0
	if desired != _run_target:
		_run_from = _run_weight
		_run_target = desired
		_run_elapsed = 0.0
		_motion_from_pose = _last_carry_pose.duplicate()
	_run_elapsed = minf(_run_elapsed + delta,MOVEMENT_BLEND)
	_run_weight = lerpf(_run_from,_run_target,smoothstep(0.0,MOVEMENT_BLEND,_run_elapsed))

func apply_socket() -> void:
	if player.ranged_stance:
		# The corn gun uses this shared anchor; keep its established placement.
		player.branch_pivot.position = Vector3(0,0.045,0)
		player.branch_pivot.quaternion = Quaternion.IDENTITY
		return
	var axis := vector_from(grip_data.shaft_axis_toward_tip)
	var normal := vector_from(grip_data.palm_outward_normal)
	player.branch_pivot.transform = Transform3D(Basis(axis.cross(normal),axis,normal),vector_from(grip_data.grip_center_right_hand_local))

func model_from_local_pose(local_pose: Dictionary) -> Dictionary:
	var skeleton := get_skeleton()
	var result := {}
	for bone in ARM_BONES:
		var parent_index := skeleton.get_bone_parent(indices[bone])
		var parent_name := skeleton.get_bone_name(parent_index)
		var parent_q: Quaternion = result[parent_name] if result.has(parent_name) else skeleton.get_bone_global_pose(parent_index).basis.orthonormalized().get_rotation_quaternion()
		result[bone] = (parent_q * local_pose[bone]).normalized()
	return result

func set_grip_closed(closed: bool) -> void:
	if not is_instance_valid(grip_mesh): return
	var desired: ArrayMesh = grip_closed_mesh if closed else grip_open_mesh
	if desired == null or grip_mesh.mesh == desired: return
	grip_mesh.mesh = desired
	if not closed:
		# The accepted v2 base surface is the reviewed open geometry.
		for shape in desired.get_blend_shape_count(): grip_mesh.set_blend_shape_value(shape, 0.0)

func model_from_chest_reference(reference: Dictionary) -> Dictionary:
	var live := get_skeleton().get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()
	var transport := (live * quaternion_from(reference.reference_chest_quaternion_xyzw).inverse()).normalized()
	var result := {}
	for bone in ARM_BONES:
		result[bone] = (transport * quaternion_from(reference.global_rotation_quaternions_xyzw[bone])).normalized()
	return result

func sample_attack_profile(time: float) -> Dictionary:
	if time <= attack_records[0].time: return attack_records[0].rotations.duplicate()
	if time >= attack_records[-1].time: return attack_records[-1].rotations.duplicate()
	var low := 0
	var high := attack_records.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if attack_records[middle].time <= time: low = middle
		else: high = middle
	var alpha: float = (time - attack_records[low].time) / (attack_records[high].time - attack_records[low].time)
	var result := {}
	for bone in ARM_BONES:
		result[bone] = attack_records[low].rotations[bone].slerp(attack_records[high].rotations[bone], alpha).normalized()
	return result

func carry_rotations() -> Dictionary:
	var target := model_from_chest_reference(records["run"] if _run_target > 0.5 else records["idle"])
	var result := {}
	for bone in ARM_BONES:
		result[bone] = _motion_from_pose[bone].slerp(target[bone],smoothstep(0.0,MOVEMENT_BLEND,_run_elapsed)).normalized()
	_last_carry_pose = result.duplicate()
	return result

func source_attack_rotations(time: float) -> Dictionary:
	var result := {}
	for bone in ARM_BONES:
		result[bone] = _source_attack.rotation_track_interpolate(_attack_tracks[bone],time).normalized()
	return result

func rebase_pose(pose: Dictionary, previous_parent: Quaternion) -> Dictionary:
	var parent_q := get_skeleton().get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()
	var delta := (parent_q * previous_parent.inverse()).normalized()
	var result := {}
	for bone in ARM_BONES:
		result[bone] = (delta * pose[bone]).normalized()
	return result

func _process_modification() -> void:
	if not is_instance_valid(player) or records.is_empty():
		return
	apply_socket()
	var hands_busy: bool = player.context_remaining > 0.0 and player.context_action in HANDS_BUSY
	var stowed := hands_busy or _stow_remaining > 0.0
	_branch_mesh.visible = not player.ranged_stance and not stowed
	set_grip_closed(not player.ranged_stance and not stowed)
	var skeleton := get_skeleton()
	if player.ranged_stance or hands_busy:
		_refresh_reset_seed = false
		for bone in ARM_BONES:
			_last_pose[bone] = skeleton.get_bone_global_pose(indices[bone]).basis.orthonormalized().get_rotation_quaternion()
		_last_parent_rotation = skeleton.get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()
		_was_attacking = false
		return
	var pose := carry_rotations()
	if _refresh_reset_seed:
		# Reset can be followed by attack before an idle frame is displayed.
		# Seed after the new body sample, not from the obsolete pre-reset clip.
		_last_pose = model_from_local_pose(sample_attack_profile(player.get_attack_pose_time())) if player.attack.remaining > 0.0 else pose.duplicate()
		_last_parent_rotation = skeleton.get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()
		_refresh_reset_seed = false
	var in_model_space := true
	var reacting: bool = player.context_remaining > 0.0 and player.context_action == "hurt"
	if reacting:
		# A queued reaction replaces the completed swing, not its obsolete exit hold.
		_was_attacking = false
		_last_attack_time = -1.0
		_exit_elapsed = EXIT_BODY_SETTLE + EXIT_ARM_SETTLE
		_exit_pose.clear()
		var idle := model_from_chest_reference(records["idle"])
		var running := model_from_chest_reference(records["run"])
		for bone in ARM_BONES:
			pose[bone] = idle[bone].slerp(running[bone], _run_weight).normalized()
		_last_carry_pose = pose.duplicate()
	if player.attack.remaining > 0.0:
		var time: float = player.get_attack_pose_time()
		if not _was_attacking or time < _last_attack_time-0.000001:
			_entry_pose = rebase_pose(_last_pose,_last_parent_rotation) if _was_attacking else _last_pose.duplicate()
		var source := sample_attack_profile(time)
		if time < ATTACK_ENTRY_BLEND:
			var incoming := model_from_local_pose(source)
			for bone in ARM_BONES:
				pose[bone] = _entry_pose[bone].slerp(incoming[bone],smoothstep(0.0,ATTACK_ENTRY_BLEND,time)).normalized()
		else:
			in_model_space = false
			pose = source
		_was_attacking = true
		_last_attack_time = time
	else:
		if _was_attacking:
			_exit_rebase_live = _last_attack_time < player.get_attack_pose_duration()-0.05
			_exit_pose = rebase_pose(_last_pose,_last_parent_rotation) if _exit_rebase_live else _last_pose.duplicate()
			_exit_parent_seed = skeleton.get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()
			_exit_elapsed = 0.0
		if _exit_elapsed < EXIT_BODY_SETTLE + EXIT_ARM_SETTLE and not _exit_pose.is_empty():
			var outgoing := rebase_pose(_exit_pose,_exit_parent_seed) if _exit_rebase_live else _exit_pose
			var alpha := smoothstep(EXIT_BODY_SETTLE,EXIT_BODY_SETTLE+EXIT_ARM_SETTLE,_exit_elapsed)
			for bone in ARM_BONES:
				pose[bone] = outgoing[bone].slerp(pose[bone],alpha).normalized()
		_was_attacking = false
		_last_attack_time = -1.0
	for bone in ARM_BONES:
		if in_model_space:
			# Only rotations change; live local origins/scales remain byte-exact.
			var parent_index := skeleton.get_bone_parent(indices[bone])
			var parent_q := skeleton.get_bone_global_pose(parent_index).basis.orthonormalized().get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(indices[bone], (parent_q.inverse() * pose[bone]).normalized())
		else:
			skeleton.set_bone_pose_rotation(indices[bone],pose[bone])
	for bone in ARM_BONES:
		_last_pose[bone] = skeleton.get_bone_global_pose(indices[bone]).basis.orthonormalized().get_rotation_quaternion()
	_last_parent_rotation = skeleton.get_bone_global_pose(_chest_index).basis.orthonormalized().get_rotation_quaternion()

func make_branch_profile() -> ArrayMesh:
	var profile: Array = grip_data.radius_profile
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := int(grip_data.get("radial_segments",48))
	for ring in profile.size()-1:
		for side in sides:
			var a := TAU*side/sides
			var b := TAU*(side+1)/sides
			var y0: float = profile[ring][0]
			var r0: float = profile[ring][1]
			var y1: float = profile[ring+1][0]
			var r1: float = profile[ring+1][1]
			var points := [Vector3(r0*cos(a),y0,r0*sin(a)),Vector3(r0*cos(b),y0,r0*sin(b)),Vector3(r1*cos(b),y1,r1*sin(b)),Vector3(r1*cos(a),y1,r1*sin(a))]
			for index in [0,2,1,0,3,2]:surface.add_vertex(points[index])
	for end in [0,profile.size()-1]:
		var y: float = profile[end][0]
		var radius: float = profile[end][1]
		for side in sides:
			var a := TAU*side/sides
			var b := TAU*(side+1)/sides
			var points := [Vector3(0,y,0),Vector3(radius*cos(a),y,radius*sin(a)),Vector3(radius*cos(b),y,radius*sin(b))]
			for index in ([0,1,2] if end==0 else [0,2,1]):surface.add_vertex(points[index])
	surface.generate_normals()
	return surface.commit()
