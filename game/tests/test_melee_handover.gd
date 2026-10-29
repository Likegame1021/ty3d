extends SceneTree
const Reference = preload("res://tests/fixtures/reference-grip-v4-r2/reference.gd")
var reference = Reference.new()
const DT=1.0/60.0
var rows=[]
var p
var old
var tick=0
var ready=false
var sk
var oldsk
var lastcaptured=-1
var phase=0.0
var failed=0
var scenarios=0
var summaries=[]
const PHASES=[-1.0,0.0,0.0625,0.12,0.1875,0.25,0.30,0.375,0.4375,0.50,0.5625,0.60,0.6875]
func _initialize():call_deferred("build")
func build():
	if scenarios == 0: check(reference.files_match(), "approved R2 references remain hash-pinned")
	phase=PHASES[scenarios]
	var baseline=GDScript.new()
	baseline.source_code=FileAccess.get_file_as_string("res://tests/fixtures/reference-grip-history/player-v1.gd.txt")
	if baseline.reload()!=OK:quit(1);return
	p=load("res://scripts/player.gd").new()
	old=baseline.new()
	for actor in [p,old]:
		root.add_child(actor)
		actor.set_physics_process(false)
		actor.position=Vector3.ZERO
		actor.visual.rotation.y=0
		actor.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.play_animation("idle" if phase<0 else "run")
		actor.animation_player.advance(0)
	sk=p.find_children("*","Skeleton3D",true,false)[0]
	oldsk=old.find_children("*","Skeleton3D",true,false)[0]
	p.melee_hold_pose.modification_processed.connect(capture)
	p.velocity=Vector3(0,0,0 if phase<0 else 3)
	old.velocity=Vector3(0,0,4.6)
	await physics_frame
	ready=true
func v(x):return [x.x,x.y,x.z]
func q(x):return [x.x,x.y,x.z,x.w]
func pose(skeleton,actor):
	var result={"local":{},"global":{}}
	for name in ["RightArm","RightForeArm","RightHand","LeftArm","LeftForeArm","LeftFoot","RightFoot"]:
		var bone=skeleton.find_bone(name)
		result.local[name]=q(skeleton.get_bone_pose_rotation(bone))
		var bt=actor.visual.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(bone)
		result.global[name]=q(bt.basis.orthonormalized().get_rotation_quaternion())
	var hand=actor.visual.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
	result.tip=v(hand*actor.branch_pivot.transform*Vector3(0,.63,0))
	result.hand=v(hand.origin)
	result.elbow=v(actor.visual.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm")).origin)
	return result
func approved_attack_tip():
	var rotations: Dictionary = reference.attack_local_rotations(p.get_attack_pose_time())
	var globals: Array = []
	for index in oldsk.get_bone_count():
		var local: Transform3D = oldsk.get_bone_pose(index)
		var name: String = oldsk.get_bone_name(index)
		if name in Reference.ARM: local.basis = Basis(rotations[name]).scaled(local.basis.get_scale())
		var parent: int = oldsk.get_bone_parent(index)
		globals.append(local if parent < 0 else globals[parent] * local)
	var hand: Transform3D = old.visual.global_transform.affine_inverse() * oldsk.global_transform * globals[oldsk.find_bone("RightHand")]
	var grip: Dictionary = reference.grip
	var axis := Vector3(grip.shaft_axis_toward_tip[0], grip.shaft_axis_toward_tip[1], grip.shaft_axis_toward_tip[2])
	var normal := Vector3(grip.palm_outward_normal[0], grip.palm_outward_normal[1], grip.palm_outward_normal[2])
	var center := Vector3(grip.grip_center_right_hand_local[0], grip.grip_center_right_hand_local[1], grip.grip_center_right_hand_local[2])
	return v(hand * Transform3D(Basis(axis.cross(normal), axis, normal), center) * Vector3(0, .63, 0))
func capture():
	if not ready or lastcaptured==tick:return
	lastcaptured=tick
	rows.append({"tick":tick,"clip":p.current_animation,"clock":p.attack.elapsed,"current":pose(sk,p),"baseline":pose(oldsk,old),"approved_tip":approved_attack_tip()})
func _physics_process(delta):
	if not ready:return false
	if tick==20:
		for actor in [p,old]:
			actor.animation_player.seek(maxf(phase,0.0),true)
	elif tick==21:
		for actor in [p,old]:actor.request_attack()
	if tick!=20:
		for actor in [p,old]:
			actor.attack.tick(DT,false)
			if tick>21 and actor.attack.remaining<=0:actor.play_animation("run")
			if actor == p:actor.melee_hold_pose.advance_state(DT)
			actor.animation_player.advance(DT)
	tick+=1
	if tick==140:call_deferred("finish")
	return false
func angle(a,b):
	return rad_to_deg(Quaternion(a[0],a[1],a[2],a[3]).normalized().angle_to(Quaternion(b[0],b[1],b[2],b[3]).normalized()))
func check(ok,label):
	if not ok:
		failed+=1
		printerr("FAIL: ",label)
func finish():
	ready=false
	var entry=0.0
	var recovery=0.0
	var exit_roll=0.0
	var strike=0.0
	var tip_recovery=0.0
	var baseline_tip_recovery=0.0
	for i in range(1,rows.size()):
		var r=rows[i]
		var previous=rows[i-1]
		var wrist=angle(r.current.global.RightHand,previous.current.global.RightHand)
		if r.tick>=22 and r.clock<0.35:
			entry=maxf(entry,wrist)
		if r.clip=="attack_branch" and r.clock>1.0:
			recovery=maxf(recovery,wrist)
			var point=r.current.tip
			var oldpoint=previous.current.tip
			tip_recovery=maxf(tip_recovery,Vector3(point[0],point[1],point[2]).distance_to(Vector3(oldpoint[0],oldpoint[1],oldpoint[2])))
			point=r.approved_tip
			oldpoint=previous.approved_tip
			baseline_tip_recovery=maxf(baseline_tip_recovery,Vector3(point[0],point[1],point[2]).distance_to(Vector3(oldpoint[0],oldpoint[1],oldpoint[2])))
		if r.tick>=114 and r.tick<=135:
			exit_roll=maxf(exit_roll,angle(r.current.global.RightHand,previous.current.global.RightHand))
		if r.clip=="attack_branch" and r.clock>=0.59 and r.clock<=0.63:
			for bone in r.current.local:
				var expected = q(reference.attack_local_rotations(r.clock)[bone]) if bone in Reference.ARM else r.baseline.local[bone]
				strike=maxf(strike,angle(r.current.local[bone],expected))
	check(entry<16.0,"carry entry world wrist rotation below 16 degrees/frame at phase %.2f; %.2f" % [phase,entry])
	check(recovery<16.0,"carry recovery world wrist rotation below 16 degrees/frame; %.2f" % recovery)
	check(exit_roll<16.0,"post-attack wrist roll below 16 degrees/frame; %.2f" % exit_roll)
	check(tip_recovery<=baseline_tip_recovery+0.005,"recovery weapon endpoint no sharper than independently approved retarget; %.3f versus %.3f" % [tip_recovery,baseline_tip_recovery])
	check(strike<0.1,"actual post-modifier hit-window keeps source body and approved right arm; %.4f" % strike)
	var summary={"phase":phase,"entry_wrist_deg":entry,"recovery_wrist_deg":recovery,"exit_roll_deg":exit_roll,"recovery_tip_m":tip_recovery,"strike_pose_difference_deg":strike}
	summaries.append(summary)
	print("MELEE_HANDOVER ",JSON.stringify(summary))
	p.free();old.free()
	scenarios+=1
	if scenarios<PHASES.size():
		rows=[];tick=0;lastcaptured=-1
		call_deferred("build")
	else:
		var f=FileAccess.open("user://reference-grip-handover-summary.json",FileAccess.WRITE)
		f.store_string(JSON.stringify(summaries,"  "))
		print("MELEE_HANDOVER: %d checks, " % (PHASES.size()*5),failed," failures")
		quit(1 if failed else 0)
