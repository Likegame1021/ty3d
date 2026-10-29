extends SceneTree
## Real Input + Cornfield Player physics. No observed-interval position teleports.
## BASELINE_SPAWN=1 uses both exact preserved pre-domain fixture scripts.
## Optional DOOR_MOVING_CASE=continuous|wall|reversal (default: all).
## Optional DOOR_MOVING_OUTPUT writes per-physics-frame and warning-expiry evidence.
const Player = preload("res://scripts/cornfield/player.gd")
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const UI = preload("res://scripts/cornfield/game_ui.gd")
const Game = preload("res://scripts/cornfield/game.gd")
const ACTIONS := ["move_left","move_right","move_up","move_down","run","attack"]
var World = load("res://tests/fixtures/door_spawn_baseline/room_world.gd" if OS.get_environment("BASELINE_SPAWN")=="1" else "res://scripts/cornfield/room_world.gd")
var Director = load("res://tests/fixtures/door_spawn_baseline/encounter_director.gd" if OS.get_environment("BASELINE_SPAWN")=="1" else "res://scripts/cornfield/encounter_director.gd")
var checks := 0
var failures := 0

class MotionDriver:
	extends Node
	signal finished
	var world: Node3D
	var player: CharacterBody3D
	var director: Node3D
	var camera: Camera3D
	var camera_owner: Node3D
	var camera_lift := 0.0
	var wall_direction := 1
	var mode := "continuous"
	var elapsed := 0.0
	var active := false
	var previous_position := Vector3.ZERO
	var initial_position := Vector3.ZERO
	var cancelled := 0
	var warning_count := 0
	var snapshots: Dictionary = {}
	var frames: Array = []
	var expiries: Array = []
	var warning_positions_immutable := true
	var warnings_full_duration := true
	var warning_groups_identical := true
	var elite_identity_preserved := true
	var owed_counters_preserved := true
	var birth_safe := true
	var normal_motion := true
	var steady_speed_samples := 0
	var stationary_wall_samples := 0
	var planned := 0
	var expected: Array = []
	var actual: Array = []
	var birth_time := -1.0
	var stopped_at := -1.0
	var reversed_at := -1.0
	var last_wall_motion := INF
	var first_warning_time := -1.0
	var physics_step := 0.0
	var wall_seconds := 0.0
	var started_usec := 0

	func input_x(direction: int) -> void:
		for action: String in ["move_left","move_right","move_up","move_down"]:
			Input.action_release(action)
		# Real player maps these two diagonal screen inputs to a pure world X run.
		if direction>0:
			Input.action_press("move_right")
			Input.action_press("move_down")
		elif direction<0:
			Input.action_press("move_left")
			Input.action_press("move_up")

	func input_cardinal(direction:String)->void:
		input_x(0)
		Input.action_press("move_"+direction)

	func begin() -> void:
		previous_position=player.global_position
		initial_position=previous_position
		planned=int(director.metrics().planned)
		expected=director.segments[0].groups[0].roster.duplicate()
		started_usec=Time.get_ticks_usec()
		active=true
		if mode.begins_with("direction_"):input_cardinal(mode.trim_prefix("direction_"))
		else:input_x(wall_direction if mode=="wall" else 1)

	func warning_id(warning: Dictionary) -> int:
		return warning.marks[0].get_instance_id()

	func points(warning: Dictionary) -> PackedVector3Array:
		var result := PackedVector3Array()
		for record: Dictionary in warning.records: result.append(record.point)
		return result

	func ground_distance(a: Vector3,b: Vector3) -> float:
		return Vector2(a.x-b.x,a.z-b.z).length()

	func register_warning(warning: Dictionary) -> void:
		var id := warning_id(warning)
		if snapshots.has(id):
			warning_positions_immutable=warning_positions_immutable and snapshots[id].points==points(warning)
			return
		warning_count+=1
		if first_warning_time<0: first_warning_time=elapsed
		warnings_full_duration=warnings_full_duration and is_equal_approx(float(warning.remaining),.8)
		warning_groups_identical=warning_groups_identical and int(warning.segment)==0 and int(warning.group)==0 and warning.records.size()==12
		var roster: Array=[]
		for slot in warning.records.size():
			var record: Dictionary=warning.records[slot]
			roster.append(record.species)
			elite_identity_preserved=elite_identity_preserved and bool(record.elite)==(slot==0)
		warning_groups_identical=warning_groups_identical and roster==expected
		snapshots[id]={"points":points(warning),"seconds":elapsed,"roster":roster}

	func complete() -> void:
		active=false
		input_x(0)
		player.set_physics_process(false)
		wall_seconds=float(Time.get_ticks_usec()-started_usec)/1000000.0
		finished.emit()

	func _physics_process(delta: float) -> void:
		if not active: return
		elapsed+=delta
		physics_step=delta
		var here := player.global_position
		var measured_speed := ground_distance(here,previous_position)/delta
		var measured_x := (here.x-previous_position.x)/delta
		previous_position=here
		normal_motion=normal_motion and measured_speed<=3.05 and (mode.begins_with("direction_") or absf(here.z-initial_position.z)<.05)
		if (mode=="continuous" or mode.begins_with("direction_")) and elapsed>.2 and stopped_at<0 and measured_speed>2.95 and measured_speed<3.05: steady_speed_samples+=1
		if mode=="wall" and elapsed>.5:
			last_wall_motion=measured_speed
			if measured_speed<.05: stationary_wall_samples+=1
		if is_instance_valid(camera_owner):camera_owner._follow_camera(delta)
		else:
			var camera_target:=here+Vector3.UP*camera_lift
			camera.global_position=camera_target+Vector3(15,19,15)
			camera.look_at(camera_target,Vector3.UP)
		var before: Dictionary=director.metrics()
		var before_ids: Array=[]
		var nearest := INF
		for wi in director._warnings.size():
			var warning: Dictionary=director._warnings[wi]
			var id := warning_id(warning)
			before_ids.append(id)
			register_warning(warning)
			var warning_nearest := INF
			for point: Vector3 in points(warning): warning_nearest=minf(warning_nearest,ground_distance(point,here))
			nearest=minf(nearest,warning_nearest)
			if float(warning.remaining)<=delta+.000001:
				var valid := true
				if director.has_method("_formation_valid"):
					valid=director._formation_valid(warning.records,wi)
				else:
					for record: Dictionary in warning.records:
						if not director._spawn_valid(record.point,.34): valid=false
				var serialized: Array=[]
				for point: Vector3 in points(warning): serialized.append(str(point))
				expiries.append({"seconds":elapsed,"warning_id":id,"nearest_player_distance":warning_nearest,"safe_at_expiry":valid,"positions":serialized,"player":str(here),"measured_speed":measured_speed,"body_velocity":str(player.velocity)})
		var tick_started := Time.get_ticks_usec()
		director._physics_process(delta)
		var tick_usec := Time.get_ticks_usec()-tick_started
		var after: Dictionary=director.metrics()
		var after_ids: Array=[]
		for warning: Dictionary in director._warnings:
			after_ids.append(warning_id(warning))
			register_warning(warning)
		for id: int in before_ids:
			if not after_ids.has(id) and int(after.spawned)==int(before.spawned): cancelled+=1
		owed_counters_preserved=owed_counters_preserved and int(after.planned)==planned and int(after.defeated)==0 and int(after.reward_paid)==0 and str(after.content_error).is_empty() and not director.is_complete() and int(after.alive_including_warnings)<=20
		frames.append({"seconds":elapsed,"delta":delta,"position":str(here),"measured_speed":measured_speed,"measured_x_speed":measured_x,"body_velocity":str(player.velocity),"input":str(Input.get_vector("move_left","move_right","move_up","move_down")),"nearest_warning_distance":nearest if is_finite(nearest) else -1.0,"reserved":after.reserved,"spawned":after.spawned,"director_usec":tick_usec})
		if int(after.spawned)>0:
			birth_time=elapsed
			elite_identity_preserved=elite_identity_preserved and int(after.elite_spawned)==1
			for enemy in director.enemies:
				if not is_instance_valid(enemy): continue
				enemy.set_physics_process(false)
				actual.append(enemy.species)
				birth_safe=birth_safe and ground_distance(enemy.global_position,here)>=5.25-.00001 and world.contains_ground(enemy.global_position,.34) and director._warning_visible(enemy.global_position)
				if world.has_method("is_in_spawn_domain"): birth_safe=birth_safe and world.is_in_spawn_domain(enemy.global_position,.34)
			for i in director.enemies.size():
				for j in range(i+1,director.enemies.size()):
					birth_safe=birth_safe and ground_distance(director.enemies[i].global_position,director.enemies[j].global_position)>=.72-.00001
			if not expiries.is_empty(): birth_safe=birth_safe and bool(expiries[-1].safe_at_expiry)
			complete()
			return
		if mode=="reversal" and reversed_at<0 and cancelled>0 and not director._warnings.is_empty():
			reversed_at=elapsed
			input_x(-1)
		if mode=="continuous" and elapsed>=12.0 and stopped_at<0:
			stopped_at=elapsed
			input_x(0)
		if mode=="reversal" and elapsed>=3.0 and stopped_at<0:
			stopped_at=elapsed
			input_x(0)
		if mode.begins_with("direction_"):
			if elapsed>=1.5 and reversed_at<0:
				reversed_at=elapsed
				input_cardinal({"up":"down","down":"up","left":"right","right":"left"}[mode.trim_prefix("direction_")])
			if elapsed>=3.0 and stopped_at<0:
				stopped_at=elapsed;input_x(0)
			if elapsed>=5.5:complete()
		if (mode=="continuous" and elapsed>=14.0) or (mode=="wall" and elapsed>=1.3) or (mode=="reversal" and elapsed>=5.5): complete()

	func summary() -> Dictionary:
		return {"case":mode,"physics_frames":frames.size(),"physics_delta":physics_step,"simulation_seconds":elapsed,"wall_seconds":wall_seconds,"warnings":warning_count,"cancellations":cancelled,"first_warning_seconds":first_warning_time,"birth_seconds":birth_time,"stopped_seconds":stopped_at,"reversed_seconds":reversed_at,"birth_during_continuous_motion":mode=="continuous" and birth_time>=0 and stopped_at<0,"birth_before_input_stop":birth_time>=0 and stopped_at<0,"birth_while_body_moving":birth_time>=0 and not frames.is_empty() and float(frames[-1].measured_speed)>.05,"full_original_roster_born":actual==expected and actual.size()==12,"elite_identity_preserved":elite_identity_preserved,"normal_motion":normal_motion,"steady_speed_samples":steady_speed_samples,"stationary_wall_samples":stationary_wall_samples,"last_wall_speed":last_wall_motion if is_finite(last_wall_motion) else -1.0,"immutable_warning_positions":warning_positions_immutable,"full_warning_duration":warnings_full_duration,"same_group_roster":warning_groups_identical,"safe_birth":birth_safe,"owed_counters_preserved":owed_counters_preserved}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+label)

func run() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
	var baseline := OS.get_environment("BASELINE_SPAWN")=="1"
	var hud_enabled := OS.get_environment("DOOR_MOVING_HUD")=="1"
	var two_doors := OS.get_environment("DOOR_MOVING_FIXTURE")=="west_north"
	var production_camera:=OS.get_environment("DOOR_MOVING_CAMERA")=="production"
	var selected := OS.get_environment("DOOR_MOVING_CASE")
	var cases: Array[String]=[]
	if selected=="directions":cases.append_array(["direction_up","direction_down","direction_left","direction_right"])
	elif selected.is_empty(): cases.append_array(["continuous","wall","reversal"])
	else: cases.append(selected)
	var reports: Array=[]
	var evidence: Array=[]
	for mode: String in cases:
		check(mode in ["continuous","wall","reversal","direction_up","direction_down","direction_left","direction_right"],"known real-input case: "+mode)
		if not mode in ["continuous","wall","reversal","direction_up","direction_down","direction_left","direction_right"]: continue
		var room := Catalog.make_template(9 if two_doors else 0)
		room.doors={"west":"w","north":"n"} if two_doors else {"north":"n","east":"e","south":"s","west":"w"}
		room.entry_position=Catalog.door_position("west",room.size)+Vector3.RIGHT*4
		room.main_route=PackedVector3Array([room.entry_position,Catalog.door_position("east",room.size)+Vector3.LEFT*4])
		if two_doors:room.main_route=PackedVector3Array([room.entry_position,Vector3(room.size.x*.5,0,room.size.y*.5),Catalog.door_position("north",room.size)+Vector3.BACK*6])
		room.kind="combat";room.encounter="swarm";room.content_revision=3;room.melee_fallback="beetle";room.elite=true
		var world: Node3D=World.new()
		root.add_child(world)
		world.build(room)
		var player := Player.new()
		player.spawn_position=(Vector3(.6 if two_doors else room.size.x-.6,0,room.size.y*.5) if mode=="wall" else room.entry_position)+Vector3.UP*.05
		world.add_child(player)
		player.world_min=Vector2(.25,.25)
		player.world_max=Vector2(room.size)-Vector2.ONE*.25
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=15
		camera.make_current()
		camera.global_position=player.global_position+Vector3(15,19,15)
		camera.look_at(player.global_position,Vector3.UP)
		player.configure(camera,"stick")
		var camera_owner:Node3D
		if production_camera:
			# Invoke the production method itself, including its desired offset and
			# exponential follow. No copied approximation or camera changes.
			camera_owner=Game.new();camera_owner.player=player;camera_owner.camera=camera
			camera_owner.camera_target=player.spawn_position+Vector3.UP*.35
			camera_owner._follow_camera(1.0)
		var director: Node3D=Director.new()
		world.add_child(director)
		director.configure(world,player,world.definition,3)
		director.set_physics_process(false)
		var hud:CanvasLayer
		if hud_enabled:
			hud=UI.new();root.add_child(hud);hud.update_minimap({"visible":true})
			if not baseline:
				check(director.has_method("set_spawn_visibility_ui"),"actual-input HUD fixture has a live visibility binding")
				if director.has_method("set_spawn_visibility_ui"):director.call("set_spawn_visibility_ui",hud)
		for frame in 10:
			await physics_frame
			if is_instance_valid(camera_owner):camera_owner._follow_camera(1.0/60.0)
		check(str(director.metrics().content_error).is_empty(),"real-input fixture configures "+mode)
		var driver := MotionDriver.new()
		driver.world=world;driver.player=player;driver.director=director;driver.camera=camera;driver.mode=mode
		driver.camera_owner=camera_owner
		driver.camera_lift=.4 if hud_enabled else 0.0
		driver.wall_direction=-1 if two_doors else 1
		# Player runs first at priority 0. The driver observes that real motion,
		# tracks the camera, then ticks the real director once per physics frame.
		driver.process_physics_priority=1000
		world.add_child(driver)
		driver.begin()
		await driver.finished
		var report: Dictionary=driver.summary()
		report.baseline=baseline
		report.hud_enabled=hud_enabled;report.fixture="broken_wall_west_north" if two_doors else "wide_clearing_four_doors"
		report.camera="production_Game_follow_camera" if production_camera else "centred_test_camera"
		reports.append(report)
		evidence.append({"summary":report,"frames":driver.frames,"expiries":driver.expiries})
		check(driver.normal_motion,"real input stays within normal3m/s without an observed-interval teleport: "+mode)
		check(driver.warning_positions_immutable and driver.warnings_full_duration,"warning points stay fixed for the entire .8s telegraph: "+mode)
		check(driver.warning_groups_identical and driver.elite_identity_preserved and driver.owed_counters_preserved,"original group roster, elite, cap and owed counters are preserved: "+mode)
		check(driver.birth_safe,"any actual birth passes current player-distance/domain/ground/visibility/spacing and expiry gates: "+mode)
		if mode=="continuous":
			check(driver.steady_speed_samples>=20,"continuous input actually sustains calibrated3m/s over real physics frames")
			if not baseline:
				check(driver.cancelled>0,"candidate continuous fixture exercises at least one actual cancellation before retry")
				check(driver.birth_time>=0 and driver.stopped_at<0 and driver.actual==driver.expected and driver.actual.size()==12,"candidate retry births the complete original group during bounded constant motion")
			else:
				check(driver.birth_time>=0 and driver.actual==driver.expected and driver.actual.size()==12,"baseline records continuous limitation and still births the full original group after stopping")
		elif mode=="wall":
			# A legal .8s birth may end observation around .816s. Require .25s
			# of stable60Hz wall samples after the .5s settling period.
			check(driver.stationary_wall_samples>=15 and driver.last_wall_motion<.05,"held movement input against the actual closed door produces measured zero travel")
			if not baseline:check(director._observed_player_velocity.is_zero_approx() and director._formation_motion_lead.is_zero_approx(),"closed-door input creates no false motion prediction")
		elif mode=="reversal":
			check(driver.reversed_at>=0 and driver.cancelled>0,"reversal occurs after cancellation while its real retry warning remains fixed")
			var reversed_motion := false
			for frame: Dictionary in driver.frames:
				if float(frame.seconds)>driver.reversed_at+.1 and float(frame.measured_x_speed)<-2.9: reversed_motion=true
			check(reversed_motion,"real body travels in the reversed direction without teleporting")
			check(driver.birth_time>=0 and driver.actual==driver.expected and driver.actual.size()==12,"reversal or subsequent stable stop eventually births the complete owed group")
		else:
			check(driver.steady_speed_samples>=20,"cardinal input exercises actual normal-speed motion: "+mode)
			check(driver.birth_time>=0 and driver.actual==driver.expected and driver.actual.size()==12,"cardinal movement, ordinary turn or stable stop eventually births full owed group: "+mode)
		print("DOOR_REAL_MOVING ",JSON.stringify(report))
		if not baseline:
			var prediction:Vector3=director._observed_player_velocity
			var prior_position:Vector3=director._motion_player_position
			var before_pause:Dictionary=director.metrics()
			director.set_physics_process(true);paused=true
			for frame in 3:await process_frame
			check(director._observed_player_velocity==prediction and director._motion_player_position==prior_position and director.metrics()==before_pause,"pause freezes retry prediction and encounter state: "+mode)
			paused=false;director.set_physics_process(false)
			director.configure(world,player,world.definition,3);director.set_physics_process(false)
			check(director._observed_player_velocity==Vector3.ZERO and director._formation_motion_lead==Vector3.ZERO and director._formation_retry_group==Vector2i(-1,-1) and director._motion_player_position==player.global_position,"configure clears previous-room motion and retry ranking: "+mode)
		for action: String in ACTIONS: Input.action_release(action)
		world.queue_free()
		if is_instance_valid(camera_owner):camera_owner.free()
		if is_instance_valid(hud):hud.queue_free()
		await process_frame
	var destination := OS.get_environment("DOOR_MOVING_OUTPUT")
	if not destination.is_empty():
		var file := FileAccess.open(destination,FileAccess.WRITE)
		check(file!=null,"real-input evidence file opens")
		if file!=null:
			file.store_string(JSON.stringify({"baseline":baseline,"reports":reports,"evidence":evidence},"\t"))
			file.close()
	print("DOOR_REAL_MOVING checks=%d failures=%d baseline=%s; real Cornfield Player/Input, no observed-interval teleport"%[checks,failures,baseline])
	quit(1 if failures else 0)
