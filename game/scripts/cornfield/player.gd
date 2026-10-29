extends "res://scripts/player.gd"
## Chapter health adapter. The original mesh, animation, attack timing and reach stay intact.
signal health_changed(value: float, maximum: float)
signal died
signal feedback_requested(kind: String,payload: Dictionary)
var hp := 100.0
var max_hp := 100.0
var controls_enabled := true
var weapon_id := "stick"
var damage_multiplier := 1.0
var movement_multiplier := 1.0
var hurt_cooldown := 0.0
var arc_bonus_degrees := 0.0
var knockback_multiplier := 1.0
var recovery_multiplier := 1.0
var _slash_emitted := false
var _base_attack_reach := 1.35
var chapter_camera: Camera3D
var _hurt_gameplay_clock := 0.0
var _queued_hurt_expiry := -1.0
var _hurt_step_delta := 0.0
var _aged_hurt_exit_pending := false

func configure(camera_value: Camera3D, weapon: String = "stick") -> void:
	chapter_camera = camera_value
	weapon_id = weapon
	attack_group = "full_enemies"
	ranged_stance = weapon_id == "corn"
	if is_instance_valid(branch_pivot) and branch_pivot.has_node("Branch"):
		branch_pivot.get_node("Branch").visible = not ranged_stance

func _physics_process(delta: float) -> void:
	hurt_cooldown = maxf(0.0,hurt_cooldown-delta)
	if not controls_enabled or hp <= 0:
		velocity = Vector3.ZERO
		return
	# During the shared step this clock denotes its beginning. The shared
	# queue drain subtracts delta from context_remaining exactly once.
	_hurt_step_delta = delta
	super._physics_process(delta)
	_hurt_step_delta = 0.0
	if not get_tree().paused:
		_hurt_gameplay_clock += delta
	if weapon_id=="stick" and attack.remaining>0 and attack.elapsed>=attack.active_start and not _slash_emitted:
		_slash_emitted = true
		feedback_requested.emit("slash",{"position":global_position,"direction":facing,"reach":attack_reach,"arc_degrees":rad_to_deg(acos(0.25))*2.0+arc_bonus_degrees})

func movement_speed_multiplier() -> float:
	# Apply mint inside the shared movement step so collisions/bounds and cadence
	# all see one final displacement, rather than a second post-animation move.
	return maxf(1.0, movement_multiplier)

func receive_damage(amount: float, _direction: Vector3 = Vector3.ZERO) -> bool:
	if hp <= 0 or hurt_cooldown > 0 or not controls_enabled:
		return false
	hp = maxf(0,hp-amount)
	hurt_cooldown = 0.65
	if weapon_id == "stick" and not get_tree().paused and is_instance_valid(animation_player) and extra_animation_names.has("hurt"):
		var duration: float = animation_player.get_animation(extra_animation_names.hurt).length
		_queued_hurt_expiry = _hurt_gameplay_clock + duration if attack.remaining > 0.0 else -1.0
	play_context_action("hurt")
	feedback_requested.emit("hurt",{"position":global_position,"direction":_direction,"strength":1.0})
	health_changed.emit(hp,max_hp)
	if hp <= 0:
		died.emit()
	return true

func play_context_action(action: String) -> bool:
	if action != "hurt" or weapon_id != "stick" or attack.remaining > 0.0 or _queued_hurt_expiry < 0.0:
		var played := super.play_context_action(action)
		if played:
			_aged_hurt_exit_pending = false
		return played
	if get_tree().paused or not is_instance_valid(animation_player) or not extra_animation_names.has(action):
		return false
	var duration: float = animation_player.get_animation(extra_animation_names[action]).length
	var remaining := clampf(_queued_hurt_expiry - _hurt_gameplay_clock, 0.0, duration)
	_queued_hurt_expiry = -1.0
	# A tail exhausted by this same physics step must not create a transient
	# context or rebase the cancellation bridge before locomotion resumes.
	if remaining <= _hurt_step_delta:
		return true
	if not super.play_context_action(action):
		return false
	context_remaining = remaining
	animation_player.seek(duration - remaining, false)
	_aged_hurt_exit_pending = true
	return true

func play_animation(action: String) -> void:
	if _aged_hurt_exit_pending and current_animation == "hurt" and action in ["run", "idle"] and is_instance_valid(animation_player) and animation_names.has(action):
		_aged_hurt_exit_pending = false
		# Bridge once from the final rendered tail, using the shared transition.
		if is_instance_valid(cancel_pose):
			cancel_pose.freeze_visible_pose()
	super.play_animation(action)

func cancel_actions() -> void:
	_queued_hurt_expiry = -1.0
	_aged_hurt_exit_pending = false
	super.cancel_actions()

func heal(amount: float) -> void:
	hp = minf(max_hp,hp+maxf(0,amount))
	health_changed.emit(hp,max_hp)

func apply_build_effects(effects: Dictionary) -> void:
	damage_multiplier = float(effects.get("damage_multiplier",1.0))
	attack_reach = _base_attack_reach*float(effects.get("reach_multiplier",1.0))
	arc_bonus_degrees = float(effects.get("arc_bonus_degrees",0.0))
	knockback_multiplier = float(effects.get("knockback_multiplier",1.0))
	var recovery := float(effects.get("recovery_multiplier",1.0))
	if not is_equal_approx(recovery,recovery_multiplier):
		recovery_multiplier = recovery
		if has_method("set_attack_recovery_multiplier"):
			call("set_attack_recovery_multiplier",recovery)

func request_attack() -> void:
	if not controls_enabled or hp<=0 or weapon_id!="stick":
		return
	var was_active: bool = attack.remaining>0
	super.request_attack()
	if not was_active and attack.remaining>0:
		_aged_hurt_exit_pending = false
		_slash_emitted = false

func check_hits() -> void:
	var threshold := cos(acos(0.25)+deg_to_rad(arc_bonus_degrees)*.5)
	for target in get_tree().get_nodes_in_group(attack_group):
		if not is_instance_valid(target) or not target is Node3D:
			continue
		var offset: Vector3 = target.global_position-global_position
		offset.y = 0
		if can_reach(target,attack_reach) and (offset.length()<.05 or facing.dot(offset.normalized())>threshold):
			if attack.claim_hit(target.get_instance_id(),get_tree().paused):
				target.receive_hit(facing)
				struck.emit(target)
