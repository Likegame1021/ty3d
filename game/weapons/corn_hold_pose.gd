extends SkeletonModifier3D
## Small additive upper-body pose. Animation still owns the torso and legs.

var player: Node3D
var _arms: Array[Dictionary] = []

func _ready() -> void:
	var skeleton := get_skeleton()
	for side in ["Right", "Left"]:
		var upper := skeleton.find_bone(side + "Arm")
		var lower := skeleton.find_bone(side + "ForeArm")
		var hand := skeleton.find_bone(side + "Hand")
		if upper >= 0 and lower >= 0 and hand >= 0:
			_arms.append({"upper": upper, "lower": lower, "hand": hand, "right": side == "Right"})

func _process_modification() -> void:
	if not is_instance_valid(player) or not player.ranged_stance:
		return
	# Interactions and melee clips keep their authored arms.
	if player.attack.remaining > 0.0 or player.context_remaining > 0.0:
		return
	var skeleton := get_skeleton()
	var visual_to_skeleton: Transform3D = skeleton.global_transform.affine_inverse() * player.visual.global_transform
	for arm in _arms:
		var target := Vector3(-0.13, 0.68, 0.145) if arm.right else Vector3(-0.015, 0.67, 0.30)
		var pole := Vector3(-0.34, 0.57, 0.07) if arm.right else Vector3(0.26, 0.60, 0.20)
		_solve_arm(skeleton, arm, visual_to_skeleton * target, visual_to_skeleton * pole)
		# Finger direction points along the grip / fore-end instead of down the leg.
		var hand_pose := skeleton.get_bone_global_pose(arm.hand)
		var hand_direction := Vector3(0, -0.10, 1) if arm.right else Vector3(-0.6, 0.08, 0.8)
		var desired_direction := (visual_to_skeleton.basis * hand_direction).normalized()
		var rotate_hand := Quaternion(hand_pose.basis.y.normalized(), desired_direction)
		hand_pose.basis = Basis(rotate_hand) * hand_pose.basis
		skeleton.set_bone_global_pose(arm.hand, hand_pose)

func _solve_arm(skeleton: Skeleton3D, arm: Dictionary, target: Vector3, pole: Vector3) -> void:
	var shoulder := skeleton.get_bone_global_pose(arm.upper).origin
	var elbow := skeleton.get_bone_global_pose(arm.lower).origin
	var hand := skeleton.get_bone_global_pose(arm.hand).origin
	var upper_length := shoulder.distance_to(elbow)
	var lower_length := elbow.distance_to(hand)
	var offset := target - shoulder
	var distance := clampf(offset.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.002)
	var forward := offset.normalized()
	var bend := pole - shoulder
	bend = (bend - forward * bend.dot(forward)).normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var solved_elbow := shoulder + forward * along + bend * height
	_rotate_bone_towards(skeleton, arm.upper, elbow - shoulder, solved_elbow - shoulder)
	elbow = skeleton.get_bone_global_pose(arm.lower).origin
	hand = skeleton.get_bone_global_pose(arm.hand).origin
	_rotate_bone_towards(skeleton, arm.lower, hand - elbow, target - elbow)

func _rotate_bone_towards(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
