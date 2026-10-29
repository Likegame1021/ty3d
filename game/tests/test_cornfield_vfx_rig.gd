extends SceneTree
## Observe the actual final modified rig and BoneAttachment in their update
## signal. This catches the one-frame/raw-animation sampling mistake.
var checks := 0
var failures: Array[String] = []
var aligned_samples := 0
var max_tip_error := 0.0
var max_samples := 0
func _initialize() -> void:call_deferred("run_checks")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label);printerr("FAIL: ",label)
func run_checks() -> void:
	for action in ["move_left","move_right","move_up","move_down","run"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	var feedback=load("res://scripts/cornfield/combat_feedback.gd").new()
	root.add_child(feedback)
	check(feedback.has_method("bind_player"),"real-rig VFX binding exists")
	if not feedback.has_method("bind_player"):
		feedback.free();finish();return
	var player=load("res://scripts/cornfield/player.gd").new()
	root.add_child(player)
	player.set_physics_process(false)
	player.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	feedback.bind_player(player)
	var skeleton:Skeleton3D=player.find_children("*","Skeleton3D",true,false)[0]
	var branch:MeshInstance3D=player.branch_pivot.get_node("Branch")
	var observe:=func():
		var samples:Array=feedback.trail_snapshot()
		max_samples=maxi(max_samples,samples.size())
		if not samples.is_empty() and is_equal_approx(float(samples[-1].source_time),player.attack.elapsed):
			var exact:=branch.to_global(Vector3(0,branch.mesh.get_aabb().end.y,0))
			max_tip_error=maxf(max_tip_error,exact.distance_to(samples[-1].tip))
			aligned_samples+=1
	skeleton.skeleton_updated.connect(observe)
	for multiplier in [1.0,.92,.8464]:
		feedback.clear_all()
		player.reset_player()
		player.set_attack_recovery_multiplier(multiplier)
		player.request_attack()
		var duration:float=.63+(1.5416666667-.63)*multiplier
		check(absf(player.attack.duration-duration)<.00001,"VFX preserves recovery-only rank duration "+str(multiplier))
		for index in 105:
			player.position.y=.05
			player.velocity.y=0
			player._physics_process(1.0/60.0)
			player.animation_player.advance(1.0/60.0)
			await process_frame
		check(player.attack.active_start==.59 and player.attack.active_end==.63,"source damage window unchanged at rank "+str(multiplier))
		check(player.hp==100.0,"cosmetic sampling never damages the owner")
		check(feedback.trail_snapshot().is_empty(),"completed swing leaves no stale ribbon")
	# Exercise a real moving root and cancellation as well as stationary ranks.
	feedback.clear_all();player.reset_player();player.set_attack_recovery_multiplier(1.0)
	var start_position:Vector3=player.position
	Input.action_press("move_right");Input.action_press("run")
	player.request_attack()
	for index in 36:
		# CharacterBody3D.move_and_slide uses the engine step, not our argument.
		await physics_frame
		player.position.y=.05;player.velocity.y=0
		player._physics_process(1.0/60.0);player.animation_player.advance(1.0/60.0)
		await process_frame
	check(absf(player.position.x-start_position.x)>.2,"actual moving attack translates the root while trail samples final socket")
	check(not feedback.trail_snapshot().is_empty(),"moving actual rig produces a contact-window trail")
	Input.action_release("move_right");Input.action_release("run")
	player.cancel_actions();feedback._process(.001)
	check(feedback.trail_snapshot().is_empty(),"real moving-rig cancellation clears immediately")
	await process_frame
	check(feedback.trail_snapshot().is_empty(),"final modifier signal cannot resurrect the cancelled trail")
	check(aligned_samples>=12,"automatic final-rig signal supplied actual moving-tip samples")
	check(max_tip_error<.00001,"ribbon tip agrees with rendered BoneAttachment within10micrometres")
	check(max_samples<=12,"actual rig respects the twelve-sample cap")
	skeleton.skeleton_updated.disconnect(observe)
	feedback.bind_player(null)
	player.free();feedback.free()
	await process_frame
	finish()
func finish() -> void:
	print("CORNFIELDS_VFX_RIG: %d checks, %d failures samples=%d max_tip_error=%s max_samples=%d"%[checks,failures.size(),aligned_samples,max_tip_error,max_samples])
	quit(0 if failures.is_empty() else 1)
