extends "res://tests/qa_aged_hurt_automatic.gd"
## Black-box lifecycle contracts for the one-shot aged-hurt exit bridge.
## All timer/animation progression is automatic. Missing support is an explicit
## test-only resource-availability fixture, never a product asset change.
func ticks(count:int) -> void:
	for ignored in count:await physics_frame
func start_case(name:String) -> void:
	active_case=name;recording=false;tick=-1;old_points=[];last_pose=[];pose_samples=[];pose_deltas=[]
	await setup();p.set_physics_process(true)
func arm_tail() -> void:
	p.request_attack();await ticks(78)
	check(p.receive_damage(7),active_case+" accepted damage")
	await ticks(16)
	check(p.context_action=="hurt" and p.context_remaining>0,active_case+" reaches aged tail")
func finish_case() -> void:
	Input.action_release("move_right");paused=false;stage.queue_free();await process_frame;await physics_frame
func drain_tail() -> void:
	var count:=0
	while p.context_remaining>0 and count<90:await ticks(1);count+=1
	check(count<90,active_case+" existing tail ends normally")
func run_checks() -> void:
	for action in ["move_left","move_right","move_up","move_down","run"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	# Accepted aged idle exit must use the existing bridge once, then retire.
	await start_case("aged-idle-exit");await arm_tail();await drain_tail()
	check(p.current_animation=="idle" and p.context_remaining==0,"aged idle exit keeps its exact gameplay completion")
	check(p.cancel_pose.bridge_active and not p.cancel_pose.holding,"aged idle exit starts ordinary cancellation bridge")
	var previous:float=p.cancel_pose.elapsed
	for ignored in 12:
		await ticks(1)
		check(p.cancel_pose.elapsed>=previous,"idle bridge time never restarts or regresses")
		previous=p.cancel_pose.elapsed
	check(not p.cancel_pose.bridge_active,"aged idle bridge retires at original standard duration")
	await finish_case()
	# Expired tail must not arm any transition bridge.
	await start_case("zero-tail")
	p.request_attack();await ticks(15);check(p.receive_damage(7),"zero-tail hit accepted")
	Input.action_press("move_right");await ticks(78)
	check(p.attack.remaining==0 and p.context_remaining==0 and p.current_animation=="run","expired tail exits directly to RUN on original tick")
	check(not p.cancel_pose.bridge_active,"zero-tail does not rebase cancellation bridge")
	await finish_case()
	for operation in ["cancel","reset","restart","refresh","missing-support","raw-pause"]:
		await start_case(operation);await arm_tail()
		match operation:
			"cancel":
				p.cancel_actions();Input.action_press("move_right");await ticks(1)
				check(p.current_animation=="run" and not p.cancel_pose.bridge_active,"cancel clears pending aged exit before next locomotion")
			"reset":
				p.reset_player();Input.action_press("move_right");await ticks(1)
				check(p.current_animation=="run" and not p.cancel_pose.bridge_active,"reset clears pending aged exit and previous snapshot")
			"restart":
				p.request_attack();Input.action_press("move_right");await ticks(93)
				check(p.attack.remaining==0 and p.context_remaining==0 and not p.cancel_pose.bridge_active,"restart cannot carry stale aged snapshot to next attack completion")
			"refresh":
				await ticks(24)
				check(p.receive_damage(7),"fresh same-hurt rehit accepted after natural grace")
				await ticks(1)
				check(p.animation_player.current_animation_position<=1.0/60.0+.00001,"fresh rehit restarts visible hurt normally")
				Input.action_press("move_right");await drain_tail()
				check(not p.cancel_pose.bridge_active,"fresh rehit does not inherit stale aged-exit capture")
			"missing-support":
				p.cancel_pose.points.clear();Input.action_press("move_right");await drain_tail()
				check(p.current_animation=="run" and not p.cancel_pose.bridge_active,"missing support keeps normal transition without phantom hold")
			"raw-pause":
				var before:float=p.context_remaining;var pose:Array=p.cancel_pose.read_pose();paused=true;await ticks(8)
				check(p.context_remaining==before and p.cancel_pose.read_pose()==pose,"raw pause freezes actual aged hurt pose and timer")
				paused=false;Input.action_press("move_right");await drain_tail()
				check(p.cancel_pose.bridge_active and not p.cancel_pose.holding,"raw pause resumes one normal aged-exit bridge without stale wall-time expiry")
		await finish_case()
	var report:={"checks":checks,"failures":failures,"chapter_player_sha256":FileAccess.get_sha256("res://scripts/cornfield/player.gd")}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output);FileAccess.open(output.path_join(variant+"-exit-adverse.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AGED_HURT_EXIT_ADVERSE %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
