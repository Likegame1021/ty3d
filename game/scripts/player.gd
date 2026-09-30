extends CharacterBody3D

signal struck(target: Node3D)

const AttackState = preload("res://scripts/attack_state.gd")
const SPAWN := Vector3(0, 0.05, 8)
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
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Screen-space axes for the fixed diagonal camera.
	var direction := Vector3(input.x + input.y, 0, input.y - input.x).normalized()
	var running := Input.is_action_pressed("run")
	var speed := 4.6 if running else 2.4
	if ranged_stance:
		speed = 4.6 if running else 3.8
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
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 24.0))
	elif direction.length_squared() > 0.01:
		facing = direction
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 15.0))
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	move_and_slide()
	position.x = clampf(position.x, world_min.x, world_max.x)
	position.z = clampf(position.z, world_min.y, world_max.y)
	if position.y < -4.0:
		reset_player()
	state = "挥树枝" if attack.remaining > 0.0 else (context_action if context_remaining > 0.0 else ("奔跑" if running and input.length() > 0 else ("行走" if input.length() > 0 else "待机")))
	if attack.remaining <= 0.0 and context_remaining <= 0.0:
		play_animation("run" if state == "奔跑" else ("walk" if state == "行走" else "idle"))
	check_hits()
	walk_phase += delta * (13.0 if running else 8.0)
	if not has_real_model:
		body_visual.position.y = absf(sin(walk_phase)) * 0.025 if direction.length() > 0 else 0.0
		body_visual.rotation.z = sin(walk_phase) * 0.045 if direction.length() > 0 else 0.0
	# Missing imported attack uses the branch pivot only; HUD exposes the gap.
	if branch_pivot and (not has_real_model or not animation_names.has("attack_branch")):
		branch_pivot.rotation.y = sin(clampf(attack.elapsed / 0.48, 0.0, 1.0) * PI) * -2.6 if attack.remaining > 0 else -0.15

func play_animation(action: String) -> void:
	if animation_player and animation_names.has(action) and current_animation != action:
		current_animation = action
		animation_player.play(animation_names[action], 0.12)
		animation_player.speed_scale = 1.0

func request_attack() -> void:
	if get_tree().paused:
		return
	if context_remaining > 0.0:
		if context_action != "hurt":
			return
		context_action = ""
		context_remaining = 0.0
	if attack.begin(get_tree().paused):
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
	context_action = action
	context_remaining = animation_player.get_animation(name).length
	current_animation = action
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

func cancel_actions() -> void:
	attack.reset()
	context_action = ""
	context_remaining = 0.0
	pending_context_action = ""
