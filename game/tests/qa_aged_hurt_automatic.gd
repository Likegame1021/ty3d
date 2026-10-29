extends SceneTree
## Controlled QA stage: real automatic player physics, AnimationPlayer and rendered
## skeleton modifiers. Only start state and scripted input/damage are selected.
## Never a gameplay-victory or target-PC performance claim.
const Player = preload("res://scripts/cornfield/player.gd")
const DT := 1.0 / 60.0
var output := ""
var variant := "candidate"
var native := false
var rows: Array = []
var checks := 0
var failures := 0
var stage: Node3D
var p
var camera: Camera3D
var label: Label
var tick := -1
var active_case := ""
var captures: Array = []
var pose_samples: Array = []
var old_points: Array = []
var old_tip := Vector3.ZERO
var pose_deltas: Array = []
var last_pose: Array = []
var hold_reference: Array = []
var modified_frames := 0
var recording := false
var detail_view: SubViewport
var detail_camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			if pair[0] == "out": output = pair[1]
			if pair[0] == "variant": variant = pair[1]
			if pair[0] == "native": native = pair[1] == "true"
	call_deferred("run_checks")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)

func vector(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func transform(t: Transform3D) -> Array:
	return [vector(t.basis.x),vector(t.basis.y),vector(t.basis.z),vector(t.origin)]

func sample_pose() -> void:
	if not is_instance_valid(p) or not recording: return
	var sk: Skeleton3D = p.cancel_pose.get_skeleton()
	var pose: Array = []
	var serialized: Array = []
	for bone in sk.get_bone_count():
		var local := sk.get_bone_pose(bone)
		pose.append(local)
		serialized.append(transform(local))
	var globals: Array = p.cancel_pose.globals_from(pose)
	var points: Array = []
	var lowest := INF
	for support in p.cancel_pose.points:
		var local := Vector3.ZERO
		for influence in support:
			var bone_transform: Transform3D = globals[influence[0]]
			local += bone_transform.basis * influence[1] + bone_transform.origin * influence[2]
		var world: Vector3 = sk.global_transform * local
		lowest = minf(lowest, world.y)
		points.append(world - p.global_position)
	var branch: Node3D = p.branch_pivot.get_node("Branch")
	var tip: Vector3 = branch.global_transform * Vector3(0,.35,0) - p.global_position
	var max_step := 0.0
	if old_points.size() == points.size():
		for index in points.size(): max_step = maxf(max_step, points[index].distance_to(old_points[index]))
	var tip_step: float = tip.distance_to(old_tip) if not old_points.is_empty() else 0.0
	var component_step := 0.0
	if not last_pose.is_empty():
		for bone in pose.size():
			component_step = maxf(component_step,pose[bone].origin.distance_to(last_pose[bone].origin))
			for column in 3: component_step = maxf(component_step,(pose[bone].basis[column]-last_pose[bone].basis[column]).length())
	pose_deltas.append({"tick":tick,"support_step_m":max_step,"weapon_tip_step_m":tip_step,"lowest_y":lowest,"component_step":component_step,"bridge":p.cancel_pose.bridge_active,"holding":p.cancel_pose.holding})
	pose_samples.append({"tick":tick,"clip":p.animation_player.current_animation,"clip_time":p.animation_player.current_animation_position if not p.animation_player.current_animation.is_empty() else -1.0,"pose":serialized,"weapon":transform(branch.global_transform),"tip_actor_relative":vector(tip)})
	old_points = points
	old_tip = tip
	last_pose = pose
	modified_frames += 1

func setup() -> void:
	stage = Node3D.new(); root.add_child(stage)
	var environment := WorldEnvironment.new(); stage.add_child(environment)
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("abc4b3")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff1cc")
	environment.environment.ambient_light_energy = .55
	var sun := DirectionalLight3D.new(); stage.add_child(sun)
	sun.rotation_degrees = Vector3(-55,-28,0); sun.light_color = Color("ffe5b2"); sun.light_energy = .9
	sun.shadow_enabled = true; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	var floor := StaticBody3D.new(); stage.add_child(floor)
	var collision := CollisionShape3D.new(); floor.add_child(collision)
	var box := BoxShape3D.new(); box.size = Vector3(30,.1,30); collision.shape = box; collision.position.y = -.05
	var plane := MeshInstance3D.new(); floor.add_child(plane)
	var mesh := PlaneMesh.new(); mesh.size = Vector2(30,30); plane.mesh = mesh
	var material := StandardMaterial3D.new(); material.albedo_color = Color("b5a680"); plane.material_override = material
	# Static one-metre markers make reposition distance visible without enemies.
	for i in range(-6,7):
		var mark := MeshInstance3D.new(); stage.add_child(mark)
		var line := BoxMesh.new(); line.size = Vector3(.025,.005,12); mark.mesh = line; mark.position=Vector3(i,.003,0)
		var mark_material := StandardMaterial3D.new(); mark_material.albedo_color = Color("93886d"); mark.material_override=mark_material
	camera=Camera3D.new();stage.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=15;camera.near=.1;camera.far=55
	camera.rotation_degrees=Vector3(-41.848,45,0);camera.position=Vector3(0,.4,0)+camera.basis.z*45;camera.make_current()
	p=Player.new();stage.add_child(p);p.set_physics_process(false)
	p.position=Vector3.ZERO;p.spawn_position=Vector3.ZERO;p.world_min=Vector2(-12,-12);p.world_max=Vector2(12,12);p.configure(camera)
	p.melee_hold_pose.modification_processed.connect(sample_pose)
	if native:
		detail_view=SubViewport.new();stage.add_child(detail_view);detail_view.size=Vector2i(512,512)
		detail_view.world_3d=stage.get_world_3d();detail_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		detail_camera=Camera3D.new();detail_view.add_child(detail_camera)
		detail_camera.projection=Camera3D.PROJECTION_ORTHOGONAL;detail_camera.size=3.0;detail_camera.near=.1;detail_camera.far=55
		detail_camera.rotation_degrees=camera.rotation_degrees;detail_camera.position=p.position+Vector3.UP*.65+detail_camera.basis.z*45;detail_camera.make_current()
	var canvas:=CanvasLayer.new();stage.add_child(canvas)
	label=Label.new();canvas.add_child(label);label.position=Vector2(22,20);label.add_theme_font_size_override("font_size",22)
	label.text="Controlled QA stage / %s / 15m camera\nAutomatic clocks. 1m grid. No enemies. No victory claim."%variant
	for ignored in 5: await physics_frame
	check(p.animation_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"automatic AnimationPlayer callback retained")
	check(p.has_real_model and p.cancel_pose.points.size()==834,"actual rig and all support vertices loaded")

func record_state() -> Dictionary:
	return {"tick":tick,"elapsed":p.attack.elapsed,"attack_remaining":p.attack.remaining,"pending":p.pending_context_action,"context":p.context_action,"context_remaining":p.context_remaining,"clip":p.animation_player.current_animation,"clip_time":p.animation_player.current_animation_position if not p.animation_player.current_animation.is_empty() else -1.0,"speed_scale":p.animation_player.speed_scale,"position":vector(p.position),"velocity":vector(p.velocity),"facing":vector(p.facing),"hp":p.hp,"bridge":p.cancel_pose.bridge_active,"holding":p.cancel_pose.holding,"expiry":p.get("_queued_hurt_expiry")}

func on_draw() -> void:
	if not native or tick<0 or not is_instance_valid(p): return
	if tick in [0,14,15,16,36,37,77,78,79,90,91,92,93,94,95,96,100,105,110,120,130,140,150,160,175] or (tick>=84 and tick<=152 and tick%2==0):
		var path:=output.path_join("%s-%s-%03d.png"%[variant,active_case,tick])
		root.get_texture().get_image().save_png(path)
		var detail_path:=output.path_join("%s-%s-detail-%03d.png"%[variant,active_case,tick])
		detail_view.get_texture().get_image().save_png(detail_path)
		captures.append({"driver_tick":tick,"phase":"post-draw after scheduled physics step","path":path,"detail_path":detail_path,"detail_camera_size":3.0,"state":record_state()})

func run_case(name: String, hit_tick: int, preparation: String="") -> void:
	active_case=name;recording=false;tick=-1;captures=[];pose_samples=[];pose_deltas=[];old_points=[];last_pose=[];modified_frames=0
	await setup()
	p.set_physics_process(true)
	recording=true
	if not preparation.is_empty():
		p.request_attack()
		for i in 36:tick=i-45;await physics_frame
		p.cancel_actions()
		p.set_physics_process(false)
		for i in 5:tick=i-9;await physics_frame
		check(p.cancel_pose.holding,"cancel holds actual automatic pose")
		if preparation=="partial":
			p.set_physics_process(true);p.play_animation("idle")
			for i in 2:tick=i-3;await physics_frame
			check(p.cancel_pose.bridge_active and not p.cancel_pose.holding,"partial bridge exists before restart")
		p.set_physics_process(true)
	p.request_attack()
	var profile: Array=[p.attack.duration,p.attack.active_start,p.attack.active_end]
	var start:Vector3=p.position
	var timeline: Array=[]
	var accepted: Array=[]
	var first_hurt: Dictionary={}
	var first_run: Dictionary={}
	var attack_end: Dictionary={}
	for n in 181:
		tick=n
		if n==hit_tick:
			accepted.append({"tick":n,"accepted":p.receive_damage(7),"clock":p.get("_hurt_gameplay_clock"),"attack_elapsed":p.attack.elapsed})
		if n==37:Input.action_press("move_down")
		var state:=record_state();timeline.append(state)
		if n>0 and attack_end.is_empty() and p.attack.remaining<=0:attack_end=state
		if first_hurt.is_empty() and p.context_action=="hurt":first_hurt=state
		if n>0 and first_run.is_empty() and p.attack.remaining<=0 and p.context_remaining<=0:first_run=state
		if native:detail_camera.position=p.position+Vector3.UP*.65+detail_camera.basis.z*45
		label.text="CONTROLLED QA / %s / %s / 15m camera\nHit %.2fs; retreat .617s; time %.3fs / %s / clip %.3f\n1m grid. Automatic clocks. No enemies or victory claim."%[variant,name,hit_tick*DT,n*DT,p.current_animation,p.animation_player.current_animation_position]
		await physics_frame
	Input.action_release("move_down")
	check(accepted.size()==1 and accepted[0].accepted,"%s same single hit accepted"%name)
	check(profile==[p.attack.duration,p.attack.active_start,p.attack.active_end],"%s attack profile unchanged"%name)
	check(attack_end.get("tick",-1)==93,"%s attack ends on original tick 93"%name)
	check(not first_run.is_empty(),"%s locomotion resumes"%name)
	var length:float=p.animation_player.get_animation(p.extra_animation_names.hurt).length
	var expected_age:float=(93-hit_tick)*DT
	var expected_tail:float=maxf(0,length-expected_age)
	if expected_tail>0.00001:
		check(not first_hurt.is_empty(),"%s unexpired hurt becomes visible"%name)
		if not first_hurt.is_empty():
			check(absf(first_hurt.context_remaining-expected_tail)<.00001,"%s uses only remaining tail"%name)
			check(absf(first_hurt.clip_time-expected_age)<DT*.1,"%s real clip clock seeks to age at 1x"%name)
	else:
		check(first_hurt.is_empty(),"%s expired hurt never becomes active"%name)
	check(first_run.get("tick",999)<=maxi(93,hit_tick+50),"%s movement restored by hit-expiry deadline"%name)
	check(modified_frames>=170,"%s actual automatic modified skeleton sampled"%name)
	var max_body:=0.0;var max_tip:=0.0;var min_height:=INF
	for sample in pose_deltas:
		max_body=maxf(max_body,float(sample.support_step_m));max_tip=maxf(max_tip,float(sample.weapon_tip_step_m));min_height=minf(min_height,float(sample.lowest_y))
	# A deliberately coarse safety ceiling catches discontinuous teleports; full
	# chronological measurements and native frames remain the visual acceptance.
	check(max_body<.45,"%s no body support teleport above .45m per rendered frame"%name)
	check(max_tip<.8,"%s no weapon tip teleport above .8m per rendered frame"%name)
	var row:={"name":name,"preparation":preparation,"hit_tick":hit_tick,"retreat_tick":37,"accepted":accepted,"attack_profile":profile,"first_hurt":first_hurt,"first_run":first_run,"attack_end":attack_end,"final_distance_m":p.position.distance_to(start),"timeline":timeline,"pose_deltas":pose_deltas,"actual_skeleton_samples":pose_samples,"captures":captures,"max_body_step_m":max_body,"max_tip_step_m":max_tip,"min_support_world_y":min_height}
	rows.append(row)
	print("AGED_AUTO_CASE ",JSON.stringify({"name":name,"first_hurt":first_hurt,"first_run":first_run,"distance":row.final_distance_m,"max_body_step":max_body,"max_tip_step":max_tip}))
	recording=false;tick=-1;stage.queue_free();await process_frame;await physics_frame

func pending_pause_case() -> void:
	active_case="raw-pause-pending";recording=false;tick=-1
	await setup();p.set_physics_process(true)
	p.request_attack()
	for ignored in 78:await physics_frame
	check(p.receive_damage(7),"automatic pause fixture arms accepted queue")
	var remaining:float=p.attack.remaining
	var clock=p.get("_hurt_gameplay_clock")
	var expiry=p.get("_queued_hurt_expiry")
	var pose:Array=p.cancel_pose.read_pose()
	var clip:float=p.animation_player.current_animation_position
	paused=true
	for ignored in 8:await physics_frame
	check(p.attack.remaining==remaining and p.get("_hurt_gameplay_clock")==clock and p.get("_queued_hurt_expiry")==expiry,"raw tree pause freezes automatic commitment and queued expiry")
	check(p.animation_player.current_animation_position==clip and p.cancel_pose.read_pose()==pose,"raw tree pause freezes actual modified skeleton and automatic animation")
	check(not p.play_context_action("hurt"),"paused request does not consume queued hurt")
	paused=false
	for ignored in 16:await physics_frame
	check(p.context_action=="hurt","unpaused automatic queue resumes without a wall-time expiry")
	p.reset_player()
	check(p.pending_context_action=="" and p.context_remaining==0 and not p.cancel_pose.bridge_active,"reset after pending pause clears all action and bridge state")
	if expiry!=null:check(p._queued_hurt_expiry<0,"reset clears queued expiry after pause")
	recording=false;tick=-1;stage.queue_free();await process_frame;await physics_frame

func refresh_case() -> void:
	active_case="active-hurt-refresh";tick=-1;old_points=[];last_pose=[];pose_samples=[];pose_deltas=[]
	await setup();p.set_physics_process(true)
	check(p.receive_damage(7),"active hurt first damage accepted")
	for n in 40:tick=n;await physics_frame
	var before:float=p.animation_player.current_animation_position
	check(before>.64 and p.context_remaining>0,"same imported hurt remains active at natural grace expiry")
	check(p.receive_damage(7),"active same-clip refresh accepted without cooldown manipulation")
	await physics_frame
	check(p.animation_player.current_animation_position<=DT+.00001,"active hurt visual restarts automatically from zero")
	check(absf(p.context_remaining-(p.animation_player.get_animation(p.extra_animation_names.hurt).length-DT))<.00001,"active hurt preserves original full renewal timer")
	p.request_attack();await physics_frame
	check(p.attack.remaining>0 and p.context_remaining==0,"attack still restarts immediately out of active hurt")
	recording=false;tick=-1;stage.queue_free();await process_frame;await physics_frame

func run_checks() -> void:
	if output.is_empty():printerr("out= required");quit(2);return
	if native and DisplayServer.get_name()=="headless":printerr("native=true requires native renderer");quit(2);return
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,800)
	for action in ["move_left","move_right","move_up","move_down","run"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	RenderingServer.frame_post_draw.connect(on_draw)
	await run_case("early-hit",15)
	await run_case("late-hit",78)
	await run_case("one-frame-tail",44)
	if not native:
		await run_case("held-restart-late",78,"held")
		await run_case("partial-restart-late",78,"partial")
		await refresh_case()
		await pending_pause_case()
	var hashes:Dictionary={}
	for source in ["scripts/player.gd","scripts/cornfield/player.gd","scripts/cornfield/game.gd","weapons/attack_cancel_pose.gd","weapons/melee_hold_pose.gd"]:
		if FileAccess.file_exists("res://"+source):hashes[source]=FileAccess.get_sha256("res://"+source)
	var result:={"variant":variant,"native":native,"evidence":"Controlled initial-state/damage/input fixture; no manual physics or AnimationPlayer advance/seek; no enemy tuning or victory", "renderer":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info().string,"camera_size":15,"checks":checks,"failures":failures,"sources":hashes,"cases":rows}
	FileAccess.open(output.path_join(variant+"-automatic.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("AGED_HURT_AUTOMATIC %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
