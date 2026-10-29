extends "res://tests/qa_aged_hurt_automatic.gd"
## Reachable cancellation bridge to fresh accepted hurt, automatic cadence only.
## No synthetic pending expiry or shortened attack is injected.
func difference(a:Array,b:Array) -> float:
	var result:=0.0
	for bone in a.size():
		result=maxf(result,a[bone].origin.distance_to(b[bone].origin))
		for column in 3:result=maxf(result,(a[bone].basis[column]-b[bone].basis[column]).length())
	return result
func run_checks() -> void:
	for action in ["move_left","move_right","move_up","move_down","run"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	var results:Array=[]
	for partial in [false,true]:
		recording=false;tick=-1;old_points=[];last_pose=[];pose_samples=[];pose_deltas=[]
		await setup();p.set_physics_process(true);p.request_attack()
		for ignored in 36:await physics_frame
		p.cancel_actions();p.set_physics_process(false)
		for ignored in 5:await physics_frame
		check(p.cancel_pose.holding,"actual cancelled pose remains held")
		if partial:
			p.set_physics_process(true);p.play_animation("idle")
			for ignored in 2:await physics_frame
			check(p.cancel_pose.bridge_active and not p.cancel_pose.holding,"fresh damage occurs during real partial bridge")
		var before:Array=p.cancel_pose.read_pose()
		var ref=Player.new();stage.add_child(ref);ref.position=Vector3(3,0,0);ref.configure(camera)
		# Both damage calls occur before the same next automatic physics step.
		check(p.receive_damage(7) and ref.receive_damage(7),"fresh damage accepted on bridged and reference actors")
		check(difference(before,p.cancel_pose.read_pose())<.00001,"fresh hurt request has no zero-time modified-pose discontinuity")
		check(p.context_action=="hurt" and p.pending_context_action=="" and not p.cancel_pose.holding,"fresh hurt releases hold directly without queuing")
		p.set_physics_process(true);recording=true
		for n in 16:tick=n;await physics_frame
		check(not p.cancel_pose.bridge_active,"fresh hurt bridge finishes at its existing duration")
		check(absf(p.animation_player.current_animation_position-ref.animation_player.current_animation_position)<.00001,"fresh hurt clock equals ordinary reference without compression")
		var error:=difference(p.cancel_pose.read_pose(),ref.cancel_pose.read_pose())
		check(error<.00001,"all actual bones reach same authored fresh-hurt pose after bridge")
		results.append({"partial":partial,"pose_error":error,"samples":pose_samples,"deltas":pose_deltas})
		recording=false;tick=-1;stage.queue_free();await process_frame;await physics_frame
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join(variant+"-fresh-hurt-bridge.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results},"\t"))
	print("FRESH_HURT_BRIDGE %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
