extends SceneTree
## Retains the historical 13-phase and 16-degree wrist guards on final output.
const DT := 1.0 / 60.0
const PHASES := [-1.0, 0.0, .0625, .12, .1875, .25, .30, .375, .4375, .50, .5625, .60, .6875]
var failures := 0
var checks := 0
var rows := []
func _initialize(): call_deferred("run_checks")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func pose(p, sk: Skeleton3D) -> Dictionary:
	p.cancel_pose._process_modification(); p.melee_hold_pose._process_modification(); p.cancel_pose.capture_visible_pose()
	var hand: Transform3D = p.visual.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))
	var socket: Transform3D = hand * p.branch_pivot.transform
	var vertices: PackedVector3Array = p.branch_pivot.get_node("Branch").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lowest := INF
	for vertex in vertices: lowest = minf(lowest, (socket * vertex).y)
	return {"rotation": hand.basis.orthonormalized().get_rotation_quaternion(), "surface": lowest, "tip": socket * Vector3(0, .63, 0), "hand": hand}
func rotation_angle(a: Quaternion, b: Quaternion) -> float:
	var relative := (a.normalized() * b.normalized().inverse()).normalized()
	return rad_to_deg(2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w)))
func run_checks():
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for phase in PHASES:
		var p = load("res://scripts/player.gd").new(); root.add_child(p)
		p.set_physics_process(false); p.position = Vector3.ZERO; p.visual.rotation = Vector3.ZERO
		p.corn_hold_pose.active = false; p.melee_hold_pose.active = false; p.cancel_pose.active = false
		p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		p.play_animation("idle" if phase < 0 else "run"); p.animation_player.advance(0)
		p.velocity = Vector3.ZERO if phase < 0 else Vector3(0, 0, .84)
		p.animation_player.seek(maxf(phase, 0), true); p.melee_hold_pose.advance_state(1)
		var sk: Skeleton3D = p.melee_hold_pose.get_skeleton()
		var previous := pose(p, sk)
		p.request_attack(); p.animation_player.advance(0)
		var start := pose(p, sk)
		var zero_angle := rotation_angle(start.rotation, previous.rotation)
		var zero_component := 0.0
		for column in 3: zero_component = maxf(zero_component, (start.hand.basis[column] - previous.hand.basis[column]).length())
		zero_component = maxf(zero_component, start.hand.origin.distance_to(previous.hand.origin))
		check(zero_angle < .01, "attack time zero preserves displayed carry phase %.4f: angle %.8f, component %.9f" % [phase, zero_angle, zero_component])
		var entry := 0.0; var entry_time := 0.0; var recovery := 0.0; var exit_step := 0.0; var surface: float = start.surface
		previous = start
		for frame in 140:
			p.attack.tick(DT, false)
			if p.attack.remaining <= 0: p.play_animation("run")
			p.animation_player.advance(DT); p.melee_hold_pose.advance_state(DT); p.cancel_pose.advance_state(DT)
			var current := pose(p, sk)
			var angle := rotation_angle(current.rotation, previous.rotation)
			if p.attack.remaining > 0 and p.attack.elapsed < .35:
				if angle > entry: entry_time = p.attack.elapsed
				entry = maxf(entry, angle)
			elif p.attack.remaining > 0 and p.attack.elapsed > 1.0: recovery = maxf(recovery, angle)
			elif p.attack.remaining <= 0: exit_step = maxf(exit_step, angle)
			surface = minf(surface, current.surface); previous = current
		check(entry < 16, "entry wrist <16 degrees/frame phase %.4f: %.5f" % [phase, entry])
		check(recovery < 16, "recovery wrist <16 degrees/frame phase %.4f: %.5f" % [phase, recovery])
		check(exit_step < 16, "exit wrist <16 degrees/frame phase %.4f: %.5f" % [phase, exit_step])
		check(surface > .029, "whole shaft clears visual ground through entry/recovery/exit phase %.4f: %.6f" % [phase, surface])
		rows.append({"phase": phase, "entry_deg": entry, "entry_time": entry_time, "zero_angle": zero_angle, "zero_component": zero_component, "recovery_deg": recovery, "exit_deg": exit_step, "surface_min": surface})
		p.free()
	print("REFERENCE_GRIP_TRANSITIONS ", JSON.stringify({"checks": checks, "failures": failures, "rows": rows}))
	quit(1 if failures else 0)
