extends CharacterBody3D

signal struck(target: Node3D)

const AttackState = preload("res://scripts/attack_state.gd")
const IdleBodyCalibration = preload("res://scripts/idle_body_calibration.gd")
const SPAWN := Vector3(0, 0.05, 8)
const RUN_SPEED := 3.0
const RUN_REFERENCE_SPEED := 2.4 # Median planted-foot sweep in the actual 1.2m run rig.
const MOVE_ACCELERATION := 58.0 # Full run within 67 ms at 60 Hz.
const MOVE_DECELERATION := 72.0
const TURN_RESPONSE := 18.0
const AIM_TURN_RESPONSE := 24.0
const GAIT_BONES := ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]
var attack = AttackState.new()
var visual: Node3D
var body_visual: Node3D
var branch_pivot: Node3D
var animation_player: AnimationPlayer
var animation_names := {}
var extra_animation_names := {}
var model_status := "临时外形 · 正式角色待导入"
var bone_status := "临时手部挂点"
var facing := Vector3(0, 0, -1)
var aim_direction := Vector3.ZERO
var ranged_stance := false
var state := "待机"
var walk_phase := 0.0
var has_real_model := false
var current_animation := ""
var attack_reach := 1.35
var spawn_position := SPAWN
var attack_group := "practice_targets"
var world_min := Vector2(-13.5, -15.5)
var world_max := Vector2(13.5, 15.5)
var context_action := ""
var context_remaining := 0.0
var pending_context_action := ""
var corn_hold_pose: SkeletonModifier3D
var melee_hold_pose: SkeletonModifier3D
var cancel_pose: SkeletonModifier3D
var _resetting_pose := false
var pose_channels
var pose_generation := 0
var pose_binding: StringName
var pose_evaluation_serial := 0
var pose_token: Dictionary = {}
var pose_channel_failed := false
var _pose_skeleton: Skeleton3D
var _pose_entry: SkeletonModifier3D
var _pose_final: SkeletonModifier3D
var _canonical_callback: Callable
var gait_tracks := {}
var gait_samples := {}
var _authored_attack_duration := 0.48
var _authored_attack_animation := ""
var _attack_recovery_multiplier := 1.0
var _active_attack_recovery_multiplier := 1.0
var _recovery_animation_names := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 2
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.2
	collision.shape = capsule
	collision.position.y = 0.6
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	visual.rotation.y = PI
	load_character()
	reset_player()

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	return mat

func mesh_part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func load_character() -> void:
	body_visual = Node3D.new()
	visual.add_child(body_visual)
	if ResourceLoader.exists("res://assets/characters/boy/boy.glb"):
		var scene = load("res://assets/characters/boy/boy.glb")
		if scene is PackedScene:
			var model: Node3D = scene.instantiate()
			body_visual.add_child(model)
			fit_model(model)
			has_real_model = true
			model_status = "Meshy 角色 · GLB 已载入"
			for item in model.find_children("*", "AnimationPlayer", true, false):
				animation_player = item as AnimationPlayer
				if animation_player:
					break
			resolve_animations()
			attach_branch(model)
			attach_corn_hold_pose(model)
			attach_melee_hold_pose(model)
			attach_cancel_pose(model)
			return
	build_placeholder()
	attach_branch(body_visual)

func attach_corn_hold_pose(model: Node3D) -> void:
	for item in model.find_children("*", "Skeleton3D", true, false):
		var skeleton := item as Skeleton3D
		if skeleton.find_bone("RightArm") < 0 or skeleton.find_bone("LeftArm") < 0:
			continue
		corn_hold_pose = load("res://weapons/corn_hold_pose.gd").new()
		corn_hold_pose.name = "CornHoldPose"
		corn_hold_pose.player = self
		skeleton.add_child(corn_hold_pose)
		break

func attach_melee_hold_pose(model: Node3D) -> void:
	var mesh_state: Dictionary = load("res://weapons/normal_grip_mesh.gd").apply(model)
	if mesh_state.is_empty():
		return
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	melee_hold_pose = load("res://weapons/melee_hold_pose.gd").new()
	melee_hold_pose.player = self
	melee_hold_pose.grip_mesh = mesh_state.mesh
	melee_hold_pose.grip_open_mesh = mesh_state.open_mesh
	melee_hold_pose.grip_closed_mesh = mesh_state.closed_mesh
	skeleton.add_child(melee_hold_pose)

func attach_cancel_pose(model: Node3D) -> void:
	if not has_real_model or not is_instance_valid(melee_hold_pose):
		return
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	cancel_pose = load("res://weapons/attack_cancel_pose.gd").new()
	skeleton.add_child(cancel_pose)
	skeleton.move_child(cancel_pose, 0)
	_setup_pose_channels(model, skeleton)

func _setup_pose_channels(model: Node3D, skeleton: Skeleton3D) -> void:
	_pose_skeleton = skeleton
	var identity: Array = [model.scene_file_path]
	for bone in skeleton.get_bone_count():
		identity.append([skeleton.get_bone_name(bone), skeleton.get_bone_parent(bone)])
	pose_binding = StringName(JSON.stringify(identity).sha256_text())
	pose_channels = load("res://weapons/pose_channels.gd").new()
	_pose_entry = load("res://weapons/pose_channel_stage.gd").new()
	_pose_entry.name = "CanonicalEvaluationEntry"
	skeleton.add_child(_pose_entry)
	skeleton.move_child(_pose_entry, 0)
	_pose_final = load("res://weapons/pose_channel_stage.gd").new()
	_pose_final.name = "FinalVisualCapture"
	skeleton.add_child(_pose_final)
	_reset_pose_channels()

func _reset_pose_channels() -> void:
	if pose_channels == null: return
	pose_generation += 1
	pose_token.clear()
	pose_channel_failed = false
	pose_channels.reset(pose_generation, pose_binding, _pose_skeleton.get_bone_count())
	# Bound values reject callbacks retained by old model/evaluation generations.
	_pose_entry.capture = _begin_pose_evaluation.bind(pose_generation, pose_binding)
	_pose_final.capture = _capture_visual_pose.bind(pose_generation, pose_binding)
	if _canonical_callback.is_valid() and melee_hold_pose.modification_processed.is_connected(_canonical_callback):
		melee_hold_pose.modification_processed.disconnect(_canonical_callback)
	_canonical_callback = _capture_canonical_pose.bind(pose_generation, pose_binding)
	melee_hold_pose.modification_processed.connect(_canonical_callback)
	cancel_pose.configure_channels(pose_channels, pose_generation, pose_binding, true)

func _pose_failure(reason: String) -> void:
	pose_token.clear()
	if not pose_channel_failed:
		push_error("Pose channel validation failed: " + reason)
	pose_channel_failed = true
	cancel_pose.isolation_failed = true
	# No visual layer is installed; future presentation must check this flag.

func _pose_order_valid() -> bool:
	var stages: Array = []
	for child in _pose_skeleton.get_children():
		if child is SkeletonModifier3D: stages.append(child)
	return stages == [_pose_entry, cancel_pose, corn_hold_pose, melee_hold_pose, _pose_final] and stages.all(func(stage): return stage.active and stage.influence == 1.0)

func _begin_pose_evaluation(generation: int, binding: StringName) -> void:
	if generation != pose_generation or binding != pose_binding: return
	if pose_channel_failed: return
	if not _pose_order_valid():
		_pose_failure("modifier ordering or enabled state")
		return
	pose_evaluation_serial += 1
	pose_token = {"generation":generation, "binding_id":binding, "physics_frame":Engine.get_physics_frames(), "process_frame":Engine.get_process_frames(), "evaluation_serial":pose_evaluation_serial, "stage":"canonical"}

func _channel_pose() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for bone in _pose_skeleton.get_bone_count(): pose.append(_pose_skeleton.get_bone_pose(bone))
	return pose

func _capture_canonical_pose(generation: int, binding: StringName) -> void:
	if generation != pose_generation or binding != pose_binding: return
	if pose_channel_failed: return
	if pose_token.is_empty() or not _pose_order_valid():
		_pose_failure("canonical callback without ordered evaluation")
		return
	if not pose_channels.capture_canonical(_channel_pose(), pose_token):
		_pose_failure(pose_channels.last_rejection)

func _capture_visual_pose(generation: int, binding: StringName) -> void:
	if generation != pose_generation or binding != pose_binding: return
	if pose_channel_failed: return
	if pose_token.is_empty():
		_pose_failure("visual callback without evaluation")
		return
	var token := pose_token.duplicate(true)
	token.stage = "visual"
	if not pose_channels.capture_visual(_channel_pose(), token):
		_pose_failure(pose_channels.last_rejection)

func fit_model(model: Node3D) -> void:
	var bounds := AABB()
	var found := false
	for item in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := item as MeshInstance3D
		var relative := model.global_transform.affine_inverse() * mesh_node.global_transform
		var box: AABB = relative * mesh_node.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if found and bounds.size.y > 0.01:
		var ratio := 1.2 / bounds.size.y
		model.scale = Vector3.ONE * ratio
		model.position = Vector3(-bounds.get_center().x * ratio, -bounds.position.y * ratio, -bounds.get_center().z * ratio)

func resolve_animations() -> void:
	if not animation_player:
		model_status += " · 无动画播放器"
		return
	var aliases := {
		"idle": ["idle", "standing", "breathing"],
		"walk": ["walk", "walking"],
		"run": ["run", "running", "jog"],
		"attack_branch": ["attack_branch", "attack", "slash", "swing", "strike"]
	}
	for action in aliases:
		for candidate in animation_player.get_animation_list():
			var lower := String(candidate).to_lower()
			for alias in aliases[action]:
				if lower.contains(alias) and not animation_names.has(action):
					animation_names[action] = candidate
					var animation := animation_player.get_animation(candidate)
					animation.loop_mode = Animation.LOOP_NONE if action == "attack_branch" else Animation.LOOP_LINEAR
					make_animation_in_place(animation)
	var missing: Array[String] = []
	for action in aliases:
		if not animation_names.has(action):
			missing.append(action)
	if not missing.is_empty():
		model_status += " · 缺动作: " + ", ".join(missing)
	if animation_names.has("attack_branch"):
		var attack_clip := animation_player.get_animation(animation_names["attack_branch"])
		# Actual Godot RightHand samples place the forward strike at 0.60s.
		attack.configure(attack_clip.length, 0.59, 0.63)
		_authored_attack_duration = attack_clip.length
		_authored_attack_animation = animation_names["attack_branch"]
	var optional_aliases := {
		"hurt": ["hurt", "hit_reaction"],
		"pick_up": ["pick_up", "bend_over_pick_up"],
		"interact": ["interact", "open_door"],
		"push": ["push", "push_forward"],
		"vault": ["vault", "unarmed_vault"]
	}
	for action in optional_aliases:
		for candidate in animation_player.get_animation_list():
			var lower := String(candidate).to_lower()
			for alias in optional_aliases[action]:
				if lower.contains(alias) and not extra_animation_names.has(action):
					extra_animation_names[action] = candidate
					var clip := animation_player.get_animation(candidate)
					clip.loop_mode = Animation.LOOP_NONE
					make_animation_in_place(clip)
	print("Character animation mapping: ", animation_names)
	if not extra_animation_names.is_empty():
		print("Character context animation mapping: ", extra_animation_names)
	IdleBodyCalibration.apply(self)
	configure_animation_transitions()
	cache_gait_poses()
	if _attack_recovery_multiplier != 1.0:
		apply_attack_recovery_multiplier()

func configure_animation_transitions() -> void:
	var sources := animation_names.merged(extra_animation_names)
	for source in sources:
		for destination in animation_names:
			var blend := 0.12
			if destination == "attack_branch":
				# Keep the attack clock immediate; soften the pose handoff only.
				blend = 0.14
			elif source == "attack_branch":
				blend = 0.14
			elif destination == "idle":
				blend = 0.16
			elif source == "idle":
				blend = 0.10
			elif source in ["walk", "run"] and destination in ["walk", "run"]:
				blend = 0.18
			animation_player.set_blend_time(sources[source], animation_names[destination], blend)

func cache_gait_poses() -> void:
	# Walk contains three strides, run one. Match leg poses rather than treating
	# the unequal clip lengths as a shared normalized cycle, or resetting to zero.
	for action in ["walk", "run"]:
		if not animation_names.has(action):
			continue
		var clip := animation_player.get_animation(animation_names[action])
		var tracks := {}
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var path := clip.track_get_path(track)
			if path.get_subname_count() == 0:
				continue
			var bone := String(path.get_subname(path.get_subname_count() - 1))
			if bone in GAIT_BONES:
				tracks[bone] = track
		gait_tracks[action] = tracks
		var samples: Array[Dictionary] = []
		var count := maxi(1, ceili(clip.length * 30.0))
		for index in count:
			var seconds := clip.length * float(index) / float(count)
			samples.append({"time": seconds, "pose": sample_gait_pose(action, seconds)})
		gait_samples[action] = samples

func sample_gait_pose(action: String, seconds: float) -> Dictionary:
	var clip := animation_player.get_animation(animation_names[action])
	var pose := {}
	for bone in gait_tracks[action]:
		pose[bone] = clip.rotation_track_interpolate(gait_tracks[action][bone], seconds)
	return pose

func matched_gait_time(action: String) -> float:
	if not gait_samples.has(action) or not gait_tracks.has(current_animation):
		return 0.0
	var source := sample_gait_pose(current_animation, animation_player.current_animation_position)
	var best_time := 0.0
	var best_error := INF
	for sample in gait_samples[action]:
		var error := 0.0
		for bone in source:
			if sample.pose.has(bone):
				var a: Quaternion = source[bone]
				var b: Quaternion = sample.pose[bone]
				error += 1.0 - absf(a.dot(b))
		if error < best_error:
			best_error = error
			best_time = sample.time
	return best_time

func make_animation_in_place(animation: Animation) -> void:
	# CharacterBody owns movement. Keep vertical hip motion but neutralize clip travel.
	var root_node := animation_player.get_node(animation_player.root_node)
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D or animation.track_get_key_count(track) == 0:
			continue
		var path := animation.track_get_path(track)
		var animated_node := root_node.get_node_or_null(NodePath(path.get_concatenated_names()))
		var remove_travel := false
		if animated_node is Skeleton3D and path.get_subname_count() > 0:
			var bone := String(path.get_subname(path.get_subname_count() - 1))
			var index: int = animated_node.find_bone(bone)
			remove_travel = index >= 0 and (animated_node.get_bone_parent(index) == -1 or bone.to_lower().contains("hips") or bone.to_lower().contains("pelvis"))
		elif animated_node is Node3D:
			remove_travel = true
		if remove_travel:
			var origin: Vector3 = animation.track_get_key_value(track, 0)
			for key in animation.track_get_key_count(track):
				var position_key: Vector3 = animation.track_get_key_value(track, key)
				position_key.x = origin.x
				position_key.z = origin.z
				animation.track_set_key_value(track, key, position_key)

func attach_branch(model: Node3D) -> void:
	var parent: Node3D = visual
	var attachment_found := false
	if has_real_model:
		for item in model.find_children("*", "Skeleton3D", true, false):
			var skeleton := item as Skeleton3D
			for index in skeleton.get_bone_count():
				var bone_name := skeleton.get_bone_name(index)
				var lower := bone_name.to_lower().replace("_", "").replace("-", "")
				if lower.contains("righthand") or lower.contains("handr") or lower == "hand.r":
					var attachment := BoneAttachment3D.new()
					attachment.bone_name = bone_name
					skeleton.add_child(attachment)
					parent = attachment
					bone_status = "右手挂点: " + bone_name + "（需画面验收）"
					attachment_found = true
					break
			if attachment_found:
				break
		if not attachment_found:
			bone_status = "未发现右手骨骼 · 树枝临时挂点"
	branch_pivot = Node3D.new()
	branch_pivot.name = "BranchGrip"
	parent.add_child(branch_pivot)
	if attachment_found:
		branch_pivot.position = Vector3(0, 0.045, 0)
	else:
		branch_pivot.position = Vector3(-0.36, 0.76, 0.06)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.012
	stick.bottom_radius = 0.026
	stick.height = 0.7
	var stick_node := mesh_part(branch_pivot, stick, Vector3(0, 0.28, 0) if attachment_found else Vector3(0, 0.04, 0.3), Color("795232"))
	stick_node.name = "Branch"
	stick_node.rotation.x = 0.0 if attachment_found else PI / 2.0
	# Bone parents may be in centimetres; preserve an actual metre-sized branch.
	if attachment_found:
		branch_pivot.scale = Vector3.ONE / maxf(0.001, parent.global_basis.get_scale().x)

func build_placeholder() -> void:
	var torso := BoxMesh.new()
	torso.size = Vector3(0.4, 0.43, 0.25)
	mesh_part(body_visual, torso, Vector3(0, 0.69, 0), Color("d5a747"))
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	mesh_part(body_visual, head, Vector3(0, 1.05, 0), Color("dab18a"))
	var hair := SphereMesh.new()
	hair.radius = 0.175
	hair.height = 0.21
	mesh_part(body_visual, hair, Vector3(0, 1.15, -0.02), Color("382e29"))
	for side in [-1.0, 1.0]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.13, 0.43, 0.15)
		mesh_part(body_visual, leg, Vector3(side * 0.105, 0.25, 0), Color("425e76"))
		var arm := CapsuleMesh.new()
		arm.radius = 0.065
		arm.height = 0.4
		mesh_part(body_visual, arm, Vector3(side * 0.27, 0.7, 0), Color("dab18a"))
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.15, 0.1, 0.23)
		mesh_part(body_visual, shoe, Vector3(side * 0.105, 0.05, 0.035), Color("433d36"))

func _physics_process(delta: float) -> void:
	_advance_player_physics(delta)
	if is_instance_valid(melee_hold_pose):
		melee_hold_pose.advance_state(delta)
	if is_instance_valid(cancel_pose):
		cancel_pose.advance_state(delta)

func _advance_player_physics(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Screen-space axes for the fixed diagonal camera.
	var direction := Vector3(input.x + input.y, 0, input.y - input.x).normalized()
	var running := input.length_squared() > 0.0
	var speed := RUN_SPEED * movement_speed_multiplier()
	attack.tick(delta, false)
	if attack.remaining <= 0.0 and pending_context_action != "":
		var next_action := pending_context_action
		pending_context_action = ""
		play_context_action(next_action)
	context_remaining = maxf(0.0, context_remaining - delta)
	if context_remaining == 0.0:
		context_action = ""
	if attack.remaining > 0.0:
		speed *= 0.28
	elif context_remaining > 0.0:
		speed *= 0.25 if context_action in ["hurt", "vault"] else 0.5
	if ranged_stance and aim_direction.length_squared() > 0.01:
		facing = aim_direction.normalized()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-delta * AIM_TURN_RESPONSE))
	elif direction.length_squared() > 0.01:
		facing = direction
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-delta * TURN_RESPONSE))
	var previous_speed := Vector2(velocity.x, velocity.z).length()
	if direction.is_zero_approx():
		speed = 0.0
	elif attack.remaining > 0.0 or context_remaining > 0.0:
		# Never carry sprint momentum through an attack/context movement penalty.
		speed = minf(speed, previous_speed + MOVE_ACCELERATION * delta)
	else:
		var response := MOVE_ACCELERATION if speed > previous_speed else MOVE_DECELERATION
		speed = move_toward(previous_speed, speed, response * delta)
	# Smooth speed, never direction: reversals and release stay immediately responsive.
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	var movement_start := position
	move_and_slide()
	position.x = clampf(position.x, world_min.x, world_max.x)
	position.z = clampf(position.z, world_min.y, world_max.y)
	if position.y < -4.0:
		reset_player()
		update_locomotion_animation(delta, Vector3.ZERO)
		return
	update_locomotion_animation(delta, position - movement_start)
	check_hits()
	walk_phase += delta * (13.0 if running else 8.0)
	if not has_real_model:
		body_visual.position.y = absf(sin(walk_phase)) * 0.025 if direction.length() > 0 else 0.0
		body_visual.rotation.z = sin(walk_phase) * 0.045 if direction.length() > 0 else 0.0
	# Missing imported attack uses the branch pivot only; HUD exposes the gap.
	if branch_pivot and (not has_real_model or not animation_names.has("attack_branch")):
		branch_pivot.rotation.y = sin(clampf(attack.elapsed / 0.48, 0.0, 1.0) * PI) * -2.6 if attack.remaining > 0 else -0.15

func movement_speed_multiplier() -> float:
	return 1.0

func set_attack_recovery_multiplier(value: float) -> void:
	# Equipment changes during a swing take effect on the next attack only.
	_attack_recovery_multiplier = clampf(value, 0.8464, 1.0)
	if attack.remaining <= 0.0:
		apply_attack_recovery_multiplier()

func apply_attack_recovery_multiplier() -> void:
	_active_attack_recovery_multiplier = _attack_recovery_multiplier
	attack.duration = _authored_attack_duration if _active_attack_recovery_multiplier == 1.0 else attack.active_end + (_authored_attack_duration - attack.active_end) * _active_attack_recovery_multiplier
	if animation_player and not _authored_attack_animation.is_empty():
		animation_names["attack_branch"] = _authored_attack_animation if _active_attack_recovery_multiplier == 1.0 else recovery_animation_name(_active_attack_recovery_multiplier)

func recovery_animation_name(multiplier: float) -> String:
	if _recovery_animation_names.has(multiplier):
		return _recovery_animation_names[multiplier]
	# A separate resource clock avoids feeding a physics-step speed into an idle
	# AnimationPlayer. Keep all contact keys and insert the exact boundary pose;
	# only keys after contact-end move earlier. Imported source assets stay intact.
	var source := animation_player.get_animation(_authored_attack_animation)
	var retimed := source.duplicate() as Animation
	var boundary: float = attack.active_end
	for track in retimed.get_track_count():
		match source.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				retimed.track_insert_key(track, boundary, source.position_track_interpolate(track, boundary))
			Animation.TYPE_ROTATION_3D:
				retimed.track_insert_key(track, boundary, source.rotation_track_interpolate(track, boundary))
			Animation.TYPE_SCALE_3D:
				retimed.track_insert_key(track, boundary, source.scale_track_interpolate(track, boundary))
			Animation.TYPE_VALUE:
				retimed.track_insert_key(track, boundary, source.value_track_interpolate(track, boundary))
		for key in retimed.track_get_key_count(track):
			var authored_time := retimed.track_get_key_time(track, key)
			if authored_time > boundary:
				retimed.track_set_key_time(track, key, boundary + (authored_time - boundary) * multiplier)
	retimed.length = attack.duration
	if not animation_player.has_animation_library("attack_recovery"):
		animation_player.add_animation_library("attack_recovery", AnimationLibrary.new())
	var key := "rank_%d" % _recovery_animation_names.size()
	animation_player.get_animation_library("attack_recovery").add_animation(key, retimed)
	var retimed_name := "attack_recovery/" + key
	for name in animation_player.get_animation_list():
		if name != retimed_name:
			animation_player.set_blend_time(name, retimed_name, animation_player.get_blend_time(name, _authored_attack_animation))
			animation_player.set_blend_time(retimed_name, name, animation_player.get_blend_time(_authored_attack_animation, name))
	_recovery_animation_names[multiplier] = retimed_name
	return retimed_name

func get_attack_pose_time() -> float:
	if _active_attack_recovery_multiplier == 1.0 or attack.elapsed <= attack.active_end:
		return attack.elapsed
	return attack.active_end + (attack.elapsed - attack.active_end) / _active_attack_recovery_multiplier

func get_attack_pose_duration() -> float:
	return _authored_attack_duration

func update_locomotion_animation(delta: float, displacement: Vector3) -> void:
	# Ground-relative displacement includes collisions and bounds; input speed alone skates.
	var actual_speed := Vector2(displacement.x, displacement.z).length() / maxf(delta, 0.00001)
	state = "挥树枝" if attack.remaining > 0.0 else (context_action if context_remaining > 0.0 else ("奔跑" if actual_speed > 0.03 else "待机"))
	if attack.remaining <= 0.0 and context_remaining <= 0.0:
		play_animation("run" if state == "奔跑" else "idle")
		if animation_player and current_animation == "run":
			animation_player.speed_scale = actual_speed / RUN_REFERENCE_SPEED

func play_animation(action: String) -> void:
	if is_instance_valid(cancel_pose) and cancel_pose.bridge_active and current_animation != action and animation_names.has(action):
		cancel_pose.begin_transition(action == "idle")
		# The cancellation layer owns a single real-time blend from the rendered pose.
		animation_player.stop(true)
		current_animation = ""
	if animation_player and animation_names.has(action) and current_animation != action:
		var start_time := matched_gait_time(action)
		current_animation = action
		animation_player.play(animation_names[action])
		if start_time > 0.0:
			animation_player.seek(start_time, false)
		animation_player.speed_scale = 1.0

func request_attack() -> void:
	if get_tree().paused:
		return
	if context_remaining > 0.0:
		if context_action != "hurt":
			return
		context_action = ""
		context_remaining = 0.0
	if attack.remaining <= 0.0:
		apply_attack_recovery_multiplier()
	if attack.begin(get_tree().paused):
		# Cancelling and immediately restarting keeps the same logical action name,
		# but a successful new swing must restart its clip from the beginning.
		if current_animation == "attack_branch":
			if animation_player:
				animation_player.stop(true)
			current_animation = ""
		play_animation("attack_branch")

func play_context_action(action: String) -> bool:
	if get_tree().paused or not animation_player or not extra_animation_names.has(action):
		return false
	if action == "hurt" and attack.remaining > 0.0:
		pending_context_action = action
		return true
	if action != "hurt" and (attack.remaining > 0.0 or context_remaining > 0.0):
		return false
	var name: String = extra_animation_names[action]
	if action == "hurt" and animation_player.current_animation == name:
		# A renewed logical reaction must restart its matching visible clip.
		animation_player.stop(true)
	context_action = action
	context_remaining = animation_player.get_animation(name).length
	current_animation = action
	if is_instance_valid(cancel_pose) and cancel_pose.bridge_active:
		cancel_pose.begin_transition(false)
		animation_player.stop(true)
		animation_player.play(name, 0.0)
	else:
		animation_player.play(name, 0.08)
	animation_player.speed_scale = 1.0
	return true

func can_reach(target: Node3D, distance: float) -> bool:
	var offset := target.global_position - global_position
	offset.y = 0
	if offset.length() > distance:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.7, target.global_position + Vector3.UP * 0.7, 1)
	ray.exclude = [get_rid(), target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func check_hits() -> void:
	for target in get_tree().get_nodes_in_group(attack_group):
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0
		if can_reach(target, attack_reach) and (offset.length() < 0.05 or facing.dot(offset.normalized()) > 0.25):
			if attack.claim_hit(target.get_instance_id(), get_tree().paused):
				target.receive_hit(facing)
				struck.emit(target)

func reset_player() -> void:
	_resetting_pose = true
	_reset_pose_channels()
	if animation_player:
		animation_player.stop(true)
	if is_instance_valid(cancel_pose):
		cancel_pose.clear_bridge()
	position = spawn_position
	velocity = Vector3.ZERO
	facing = Vector3(0, 0, -1)
	aim_direction = Vector3.ZERO
	ranged_stance = false
	if visual:
		visual.rotation.y = PI
	cancel_actions()
	current_animation = ""
	state = "待机"
	if is_instance_valid(melee_hold_pose) and melee_hold_pose.has_method("reset_carry_state"):
		melee_hold_pose.reset_carry_state()
	_resetting_pose = false

func cancel_actions() -> void:
	if not _resetting_pose and current_animation == "attack_branch" and is_instance_valid(cancel_pose):
		cancel_pose.freeze_visible_pose()
	if current_animation == "attack_branch":
		current_animation = ""
		if animation_player:
			# Replaying an already-playing clip resumes it unless explicitly stopped.
			animation_player.stop(true)
			animation_player.speed_scale = 1.0
	attack.reset()
	context_action = ""
	context_remaining = 0.0
	pending_context_action = ""
