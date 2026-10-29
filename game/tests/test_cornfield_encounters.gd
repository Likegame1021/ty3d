extends SceneTree

var checks := 0
var failures := 0
var coverage_summary := {"cases":0,"max_route_length":0.0,"max_group_gap":0.0,"max_tail_gap":0.0,"max_density_supplement":0}

class TestPlayer:
	extends CharacterBody3D
	var hp := 100.0
	var hits := 0
	var damage_multiplier := 1.0
	func receive_damage(amount: float, _direction := Vector3.ZERO) -> void:
		hp -= amount
		hits += 1

class TestWorld:
	extends Node3D
	var blocked := false
	var doors_open := true
	var paths_requested := 0
	var width := 64.0
	var last_actor_radius := 0.3
	func contains_ground(point: Vector3, radius := 0.3) -> bool:
		return point.x > radius and point.z > radius and point.x < width-radius and point.z < 48.0-radius
	func find_spawn(anchor: Vector3, player: Vector3, min_distance: float) -> Vector3:
		return anchor if not blocked and contains_ground(anchor,0.65) and anchor.distance_to(player) >= min_distance else Vector3.INF
	func path_to(_from: Vector3, to: Vector3, actor_radius := 0.3) -> PackedVector3Array:
		paths_requested += 1
		last_actor_radius = actor_radius
		return PackedVector3Array([to]) if not blocked and contains_ground(to) else PackedVector3Array()
	func set_doors_open(value: bool) -> void:
		doors_open = value
	func get_door_position(_side: String) -> Vector3:
		return Vector3(60,0,24)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+message)

func has_volumetric_visual(enemy:Node3D) -> bool:
	if enemy.visual==null:return false
	var meshes:Array[Node]=enemy.visual.find_children("*","MeshInstance3D",true,false)
	if not enemy.species in ["beetle","boss_borer"]:return meshes.size()>=5
	# Reviewed insects are single skinned volumes rather than many primitives.
	var rigs:Array[Node]=enemy.visual.find_children("*","Skeleton3D",true,false)
	var players:Array[Node]=enemy.visual.find_children("*","AnimationPlayer",true,false)
	if meshes.is_empty() or rigs.size()!=1 or players.size()!=1:return false
	var actions:Array[String]=[]
	for name in players[0].get_animation_list():actions.append(str(name).get_file().split("|")[-1].to_lower())
	for action in ["idle","walk","windup","strike","hurt","death"]:
		if not actions.has(action):return false
	return meshes[0].mesh!=null and meshes[0].mesh.get_aabb().size.length()>.5

func definition(kind := "combat", elite := false) -> Dictionary:
	return {"id":17,"kind":kind,"encounter":kind,"elite":elite,"completion":kind == "boss",
		"size":Vector2(64,48),"doors":{"east":18},"entry_position":Vector3(5,0,24),
		"main_route":PackedVector3Array([Vector3(5,0,24),Vector3(20,0,24),Vector3(40,0,24),Vector3(60,0,24)])}

func setup(floor_number: int, kind := "combat", elite := false) -> Dictionary:
	var world := TestWorld.new()
	root.add_child(world)
	var player := TestPlayer.new()
	world.add_child(player)
	player.position = Vector3(5,0,24)
	var director = load("res://scripts/cornfield/encounter_director.gd").new()
	world.add_child(director)
	director.configure(world,player,definition(kind,elite),floor_number)
	director.set_physics_process(false)
	return {"world":world,"player":player,"director":director}

func step(director, seconds: float) -> void:
	director._physics_process(seconds)
	for enemy in director.enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)

func kill_all(director) -> void:
	for enemy in director.enemies.duplicate():
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.receive_hit(100000,Vector3.RIGHT)

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/cornfield/encounter_director.gd"),"3D encounter director exists")
	check(ResourceLoader.exists("res://scripts/cornfield/field_enemy.gd"),"3D volumetric enemy exists")
	if failures:
		finish()
		return
	for stage in range(1,4):
		var scene := setup(stage,"combat",stage == 2)
		var director = scene.director
		var cleared_calls: Array = []
		director.cleared.connect(func(): cleared_calls.append(true))
		check(not director.is_complete() and not scene.world.doors_open,"combat starts locked before first spawn")
		check(director.segments.size() in [2,3],"route uses 2–3 one-shot segments")
		var budget: int = director.metrics().planned
		check(budget >= [24,32,40][stage-1] and budget <= [48,60,72][stage-1],"floor budget respects density range")
		step(director,0.01)
		check(director.alive_count() == [8,10,12][stage-1],"first group reserves full warning budget")
		check(director.enemies.is_empty(),"spawn warning cannot instantly create enemies")
		step(director,0.79)
		check(director.enemies.is_empty(),"full 0.8 seconds warning is respected")
		step(director,0.02)
		check(not director.enemies.is_empty(),"warning resolves into animated enemies")
		for enemy in director.enemies:
			check(enemy.global_position.distance_to(scene.player.global_position) >= 5.25,"spawn is outside player safety distance")
			check(has_volumetric_visual(enemy),"volumetric species meshes are present")
			check(enemy.find_children("*", "Sprite3D", true, false).is_empty(),"enemy does not use pixel billboards")
			check(enemy.collision_layer == 4,"enemy uses real layer 4 collision")
		check(not director.is_complete(),"pending untriggered segments prevent early clear")
		director.request_exit_check()
		for tick in range(120):
			step(director,0.81)
			check(director.alive_count() <= [12,16,20][stage-1],"warnings plus enemies share hard cap")
			kill_all(director)
			step(director,0.01)
			if director.is_complete():
				break
		check(director.is_complete() and scene.world.doors_open,"exit sweep activates missed segments and clears the gate")
		check(director.metrics().spawned == budget,"all required budget actually spawned")
		check(director.metrics().defeated == budget,"all budget killed before clear")
		check(director.metrics().reward_paid == director.metrics().reward_budget,"dense enemies do not multiply the room coin budget")
		check(cleared_calls.size() == 1,"cleared is emitted once")
		check(director.metrics().elite_spawned == (1 if stage == 2 else 0),"elite is exactly one budgeted required enemy")
		for segment in director.segments:
			check(segment.activations == 1,"exit check does not retrigger a consumed segment")
		scene.world.free()
	var blocked_scene := setup(1)
	blocked_scene.world.blocked = true
	for tick in range(5):
		step(blocked_scene.director,0.9)
	check(blocked_scene.director.metrics().spawned == 0,"failed spawn never consumes actual budget")
	check(blocked_scene.director.metrics().spawn_failure_segments.size() > 0,"three-second blocked spawn is reported")
	check(not blocked_scene.director.is_complete() and not blocked_scene.world.doors_open,"blocked spawn cannot falsely clear")
	blocked_scene.world.blocked = false
	step(blocked_scene.director,0.1)
	check(blocked_scene.director.alive_count() == 8,"safe spawn retry resumes without losing budget")
	blocked_scene.director.shutdown()
	check(blocked_scene.director.alive_count() == 0,"shutdown cancels enemies and warning reservations")
	step(blocked_scene.director,2.0)
	check(blocked_scene.director.alive_count() == 0,"shutdown cannot revive queued encounters")
	blocked_scene.world.free()
	for kind in ["entry","shop","event","exit","corridor"]:
		var service := setup(1,kind)
		check(service.director.is_complete() and service.world.doors_open,"safe/short-rest room has no mandatory combat: "+kind)
		service.world.free()
	var boss_scene := setup(3,"boss")
	var boss_updates: Array = []
	boss_scene.director.boss_status.connect(func(info): boss_updates.append(info))
	step(boss_scene.director,0.01)
	step(boss_scene.director,0.81)
	check(boss_scene.director.enemies.size() == 1 and boss_scene.director.enemies[0].boss,"final red room spawns independent boss")
	check(boss_scene.director.metrics().planned == 1,"boss does not inherit ordinary 72-enemy budget")
	check(not boss_updates.is_empty() and boss_updates[0].has("title") and boss_updates[0].has("max_hp"),"boss status matches the existing HUD contract")
	kill_all(boss_scene.director)
	check(not boss_updates.is_empty() and boss_updates[-1].is_empty(),"empty boss status hides the existing HUD after clear")
	boss_scene.world.free()
	var red_scene := setup(1,"exit")
	var red_definition := definition("exit")
	red_definition.encounter = "swarm"
	red_scene.director.configure(red_scene.world,red_scene.player,red_definition,1)
	check(not red_scene.director.is_complete(),"red exit with swarm remains a required battle")
	red_scene.world.free()
	var escaped := setup(3)
	escaped.player.position = Vector3(58,0,24)
	step(escaped.director,0.01)
	for segment in escaped.director.segments:
		check(segment.activations == 1,"dashing across the route activates every crossed required band")
	check(escaped.director.alive_count() == 12,"exit-side group uses reachable adjacent approach instead of spawning beyond the room")
	escaped.world.free()
	test_progress_gated_groups()
	test_warning_revalidation()
	await test_weapon_adapters()
	await test_enemies()
	await test_physical_damage_and_pause()
	if not "--quick" in OS.get_cmdline_user_args():
		await test_closed_door_edges()
		await test_real_rooms()
	finish()

func test_progress_gated_groups() -> void:
	var scene := setup(1)
	var director = scene.director
	var long_definition := definition()
	long_definition.size = Vector2(96,48)
	long_definition.main_route = PackedVector3Array([Vector3(5,0,24),Vector3(74,0,24)])
	scene.world.width = 96.0
	director.configure(scene.world,scene.player,long_definition,1)
	check(is_equal_approx(director._route_length,69.0),"long-room regression uses a 69u route")
	step(director,0.01)
	step(director,0.81)
	kill_all(director)
	for tick in range(6):
		step(director,0.81)
		kill_all(director)
	check(director.metrics().spawned == 8,"camping at entry cannot empty the room's full budget")
	check(director.has_method("group_schedule"),"director exposes the actual along-route group coverage schedule")
	if director.has_method("group_schedule"):
		var schedule: Array = director.group_schedule()
		var previous := 0.0
		var expected_total := 0
		for index in range(schedule.size()):
			var group: Dictionary = schedule[index]
			check(float(group.progress)-previous <= 7.0001,"69u route every actual group gap is at most 2L")
			previous = float(group.progress)
			expected_total += int(group.count)
			check(int(group.count) == 8 if bool(group.first) else int(group.count) >= 2,"segment first groups stay dense and refills have at least two enemies")
			if index == 0:
				continue
			scene.player.position = director._point_on_route(float(group.progress))
			step(director,0.01)
			check(director.alive_count() == int(group.count),"actual warning reservation matches the route group's refill count")
			step(director,0.81)
			kill_all(director)
			check(director.metrics().spawned == expected_total,"each route group consumes only its own budget")
		check(69.0-previous <= 7.0001,"69u route budget covers the tail to within 2L of exit")
		check(expected_total == 48 and director.is_complete(),"69u full-route coverage fits the original floor-one 48-enemy budget")
	long_definition.main_route = PackedVector3Array([Vector3(5,0,24),Vector3(125,0,24)])
	director.configure(scene.world,scene.player,long_definition,1)
	if director.has_method("group_schedule"):
		var previous := 0.0
		var total := 0
		for group in director.group_schedule():
			check(float(group.progress)-previous <= 7.0001,"extreme 120u route also has no group trigger gap over 2L")
			previous = float(group.progress)
			total += int(group.count)
		check(total == 54 and director.metrics().base_budget == 48 and director.metrics().density_supplement == 6,"extreme route records precisely three extra pairs inside its 54-enemy max budget")
		check(director.metrics().max_budget == total and director.cap == 12,"explicit supplement changes neither cap nor hides units outside planned")
	scene.world.free()

func test_warning_revalidation() -> void:
	var scene := setup(2,"combat",true)
	var director = scene.director
	step(director,0.01)
	check(director.alive_count() == 10 and director.metrics().reserved == 10,"pending warning reserves the entire elite opening group")
	scene.player.position = director._warnings[0].records[0].point
	step(director,0.81)
	check(director.metrics().spawned == 0,"walking into a spawn warning cancels it instead of spawning on the player")
	check(director.metrics().elite_spawned == 0,"canceled elite warning cannot consume the elite slot")
	scene.player.position = Vector3(5,0,24)
	for tick in range(4):
		step(director,0.81)
	check(director.metrics().spawned >= 10 and director.metrics().elite_spawned == 1,"revalidated spawn retries the owed group and retains its sole elite")
	scene.world.free()

func test_weapon_adapters() -> void:
	var scene := setup(1,"entry")
	var player: TestPlayer = scene.player
	var enemy = load("res://scripts/cornfield/field_enemy.gd").new()
	scene.world.add_child(enemy)
	enemy.position = Vector3(12,0,24)
	enemy.configure(scene.world,player,"boss_borer")
	enemy.set_physics_process(false)
	player.damage_multiplier = 1.5
	enemy.receive_hit(Vector3.RIGHT)
	check(is_equal_approx(enemy.hp,593.0),"damage upgrade affects the unchanged target branch interface")
	enemy.receive_projectile(3)
	check(is_equal_approx(enemy.hp,530.0),"damage upgrade affects the unchanged charged corn interface")
	enemy.receive_hit(10.0,Vector3.RIGHT)
	check(is_equal_approx(enemy.hp,520.0),"raw encounter damage is not multiplied again")
	paused = true
	enemy.receive_hit(Vector3.RIGHT)
	enemy.receive_projectile(3)
	check(is_equal_approx(enemy.hp,520.0),"pause rejects direct branch and corn damage callbacks")
	paused = false
	enemy.receive_projectile(0)
	enemy.receive_hit(-10.0)
	check(is_equal_approx(enemy.hp,520.0),"nonpositive damage cannot heal an enemy")
	enemy.take_damage(10000.0)
	check(not enemy.active and enemy.dead,"dead enemy is excluded from original gun targeting")
	scene.world.free()
	await process_frame

func test_enemies() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	var player := TestPlayer.new()
	world.add_child(player)
	player.position = Vector3(20,0,20)
	for species in ["beetle","locust","mouse","rooster","snail","corn_borer","boss_borer"]:
		var enemy = load("res://scripts/cornfield/field_enemy.gd").new()
		world.add_child(enemy)
		enemy.position = Vector3(19.5,0,20)
		enemy.configure(world,player,species,false)
		enemy.set_physics_process(false)
		check(has_volumetric_visual(enemy),"volumetric creature is constructed for "+species)
		check(enemy.is_in_group("full_enemies") and enemy.active,"enemy is compatible with target weapon group and active filter")
		var before_hp: float = enemy.hp
		enemy.receive_hit(Vector3.RIGHT)
		check(is_equal_approx(enemy.hp,before_hp-18.0),"unchanged branch Vector3 hit applies source melee damage")
		enemy.hp = enemy.max_hp
		enemy.receive_projectile(1)
		check(is_equal_approx(enemy.hp,enemy.max_hp-14.0),"unchanged corn projectile unit applies compatible damage")
		enemy.hp = enemy.max_hp
		var defeats: Array = []
		enemy.defeated.connect(func(_actor): defeats.append(true))
		var old_hits := player.hits
		enemy.phase = "strike"
		enemy.attack_pattern = "peck"
		enemy._try_melee_hit()
		check(player.hits == old_hits,"newborn cannot deal damage: "+species)
		enemy.birth_time = 0.61
		enemy._try_melee_hit()
		check(player.hits == old_hits+1,"melee hits in real 3D range after birth protection: "+species)
		if species in ["snail","corn_borer","boss_borer"]:
			var shots: Array = []
			enemy.projectile_requested.connect(func(payload): shots.append(payload))
			enemy.attack_pattern = "spit" if species == "snail" else "fan"
			enemy.strike_direction = Vector3.RIGHT
			enemy._emit_projectiles()
			check(shots.size() == (1 if species == "snail" else 5 if species == "boss_borer" else 3),"actual ranged release emits correctly typed projectile fan: "+species)
			if species == "boss_borer":
				shots.clear()
				enemy.attack_pattern = "ring"
				enemy._emit_projectiles()
				check(shots.size() == 10,"second-stage boss ring emits ten real projectiles")
		enemy.receive_hit(100000)
		enemy.receive_hit(100000)
		check(defeats.size() == 1 and enemy.dead and not enemy.active and enemy.collision_layer == 0,"one-shot defeat disables physical enemy: "+species)
		enemy.free()
	world.free()
	await process_frame

func test_physical_damage_and_pause() -> void:
	var scene := setup(3)
	var director = scene.director
	var player: TestPlayer = scene.player
	player.position = Vector3(20,0,20)
	player.collision_layer = 2
	var player_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.2
	player_shape.shape = capsule
	player_shape.position.y = 0.6
	player.add_child(player_shape)
	var enemy = load("res://scripts/cornfield/field_enemy.gd").new()
	scene.world.add_child(enemy)
	enemy.position = Vector3(19.5,0,20)
	enemy.configure(scene.world,player,"boss_borer",false)
	enemy.set_physics_process(false)
	enemy.birth_time = 1.0
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1,2.0,4.0)
	shape.shape = box
	wall.add_child(shape)
	scene.world.add_child(wall)
	wall.position = Vector3(19.75,1.0,20)
	await physics_frame
	await physics_frame
	var hit_count := player.hits
	enemy.phase = "strike"
	enemy.attack_pattern = "peck"
	enemy._try_melee_hit()
	check(player.hits == hit_count,"solid 3D wall blocks close melee")
	var shot := {"origin":Vector3(19,0.65,20),"direction":Vector3.RIGHT,"speed":20.0,"damage":5.0,"lifetime":2.6,"source_actor":enemy}
	director._spawn_projectile(shot)
	var projectile = director._projectiles[-1]
	projectile.set_physics_process(false)
	projectile._physics_process(0.2)
	check(player.hits == hit_count and projectile.is_queued_for_deletion(),"swept 3D projectile hits wall before player even on a long step")
	wall.free()
	await physics_frame
	await physics_frame
	director._spawn_projectile(shot)
	projectile = director._projectiles[-1]
	projectile.set_physics_process(false)
	projectile._physics_process(0.2)
	check(player.hits == hit_count+1,"same swept projectile hits player's layer-2 capsule after wall removal")
	var patterns: Array[String] = []
	var warnings: Array = []
	enemy.warning_requested.connect(func(payload): warnings.append(payload))
	enemy.hazard_requested.connect(func(payload): warnings.append(payload))
	for index in range(3):
		enemy._begin_attack()
		patterns.append(enemy.attack_pattern)
		check(enemy.phase == "windup" and enemy.phase_time >= 0.8,"boss pattern has a readable locked warning")
	check(patterns == ["charge","fan","fall"] and warnings.size() >= 5,"boss has three telegraphed 3D patterns")
	enemy.hp = enemy.max_hp*0.4
	enemy.phase = "follow"
	enemy._physics_process(0.01)
	check(enemy.boss_stage == 2,"boss enters stronger second phase without erasing its lifecycle")
	enemy.position = Vector3(10,0,10)
	for tick in range(2):
		enemy.phase = "follow"
		enemy._physics_process(0.4)
	check(scene.world.paths_requested > 0,"enemy chases using the world's shared path interface")
	check(is_equal_approx(scene.world.last_actor_radius,20.0/32.0),"boss navigation uses its real 0.625u collision radius")
	step(director,0.01)
	var before: Dictionary = director.metrics()
	var lifetime: float = enemy.birth_time
	director.set_physics_process(true)
	enemy.set_physics_process(true)
	paused = true
	for frame in range(3):
		await process_frame
	check(director.metrics() == before and is_equal_approx(enemy.birth_time,lifetime),"pause freezes room budgets, warning clocks and enemy clocks")
	paused = false
	director.set_physics_process(false)
	enemy.set_physics_process(false)
	scene.world.free()
	await process_frame

func finish() -> void:
	print(JSON.stringify({"suite":"cornfield_encounters","checks":checks,"failures":failures,"route_coverage":coverage_summary}))
	quit(1 if failures else 0)

func await_real_group(director:Node3D,world:Node3D,player:Node3D,camera:Camera3D,label:String) -> bool:
	# Multi-door placement has a finite four-anchor/.2s budget. A player near
	# the excluded landing may need to follow the legal approach shown by UI.
	# This geometry fixture follows verified paths with controlled positions;
	# real Input/frame-order coverage lives in separate movement/native tests.
	var before:Dictionary=director.metrics()
	var deferred_checked:=false
	for attempt in 180:
		step(director,.2)
		if not director._warnings.is_empty():return true
		if not deferred_checked:
			check(director.metrics().planned==before.planned and director.metrics().spawned==before.spawned and director.metrics().reward_paid==before.reward_paid and not director.is_complete(),"deferred placement preserves owed actors and cannot falsely clear: "+label)
			deferred_checked=true
		var target:Vector3=director.next_encounter_hint_target()
		if not target.is_finite() or player.global_position.distance_to(target)<.3:continue
		var path:PackedVector3Array=world.path_to(player.global_position,target,.3)
		check(not path.is_empty(),"deferred hint has an actual reachable player path: "+label)
		if path.is_empty():return false
		if director._hint_kind=="formation":
			check(world.is_in_spawn_domain(target,.34),"deferred hint approaches a legal immutable door-route formation: "+label)
		var next:Vector3=path[0]
		for point:Vector3 in path:
			if player.global_position.distance_to(point)>.15:next=point;break
		player.global_position=player.global_position.move_toward(next,.6)
		camera.global_position=player.global_position+Vector3.UP*.4+camera.global_basis.z*45
	return false

func resolve_real_warning(director:Node3D,label:String) -> void:
	var before:int=director.metrics().spawned
	var expected:Array=[]
	for warning:Dictionary in director._warnings:
		for record:Dictionary in warning.records:expected.append([record.species,record.elite])
	director._tick_spawn_warnings(.79)
	check(director.metrics().spawned==before,"real geometry warning cannot birth before full .8s: "+label)
	director._tick_spawn_warnings(.01)
	var actual:Array=[]
	for enemy in director.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.set_physics_process(false);actual.append([enemy.species,enemy.elite])
	check(not expected.is_empty() and actual==expected and director.metrics().spawned==before+expected.size(),"real geometry births the complete exact warned roster after .8s: "+label)

func test_real_rooms() -> void:
	var catalog = load("res://scripts/cornfield/room_catalog.gd")
	var world_script = load("res://scripts/cornfield/room_world.gd")
	for template_index in range(24):
		var room: Dictionary = catalog.make_template(template_index)
		room.doors = {"east":"next","west":"previous"}
		var size: Vector2 = room.size
		room.entry_position = Vector3(4,0,size.y*0.5)
		room.main_route = PackedVector3Array([room.entry_position,Vector3(size.x*0.5,0,size.y*0.5),Vector3(size.x-6,0,size.y*0.5)])
		var world = world_script.new()
		root.add_child(world)
		world.build(room)
		var player := TestPlayer.new()
		world.add_child(player)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 11.25
		camera.rotation_degrees = Vector3(-35,45,0)
		world.add_child(camera)
		camera.make_current()
		await physics_frame
		await physics_frame
		var director = load("res://scripts/cornfield/encounter_director.gd").new()
		world.add_child(director)
		for fraction in [0.0,0.5,0.94]:
			player.position = world.definition.entry_position
			director.configure(world,player,world.definition,3)
			director.set_physics_process(false)
			player.position = director._point_on_route(director._route_length*fraction)
			camera.global_position = player.global_position+Vector3.UP*0.4+camera.global_basis.z*45.0
			var label := "template %d route %.2f" % [template_index,fraction]
			check(await_real_group(director,world,player,camera,label) and director.alive_count()==12,"visible complete reservation after bounded legal approach: "+label)
			resolve_real_warning(director,label)
			check(director.enemies.size() == 12,"warning resolves at real geometry: "+label)
			for enemy in director.enemies:
				check(world.contains_ground(enemy.global_position,0.34),"spawn capsule inside navigable terrain: "+label)
				check(not world.path_to(enemy.global_position,player.global_position).is_empty(),"spawn actually reaches player: "+label)
			await process_frame
		for stage in range(1,4):
			player.position = world.definition.entry_position
			director.configure(world,player,world.definition,stage)
			director.set_physics_process(false)
			var schedule: Array = director.group_schedule()
			var previous := 0.0
			var total := 0
			for group in schedule:
				coverage_summary.max_group_gap = maxf(float(coverage_summary.max_group_gap),float(group.progress)-previous)
				check(float(group.progress)-previous <= 7.0001,"actual template every group-to-group gap <= 2L: %d floor %d" % [template_index,stage])
				previous = float(group.progress)
				total += int(group.count)
				check(int(group.count) == [8,10,12][stage-1] if bool(group.first) else int(group.count) >= 2,"opening/refill counts remain explicit on actual routes")
				if stage != 1:
					continue
				player.position = director._point_on_route(float(group.progress))
				camera.global_position = player.global_position+Vector3.UP*0.4+camera.global_basis.z*45.0
				var label:="template %d at %.2f"%[template_index,float(group.progress)]
				check(await_real_group(director,world,player,camera,label) and director.alive_count()==int(group.count),"real template full owed group reaches the route tail after legal approach: "+label)
				resolve_real_warning(director,label)
				check(director.metrics().spawned == total,"real template actually spawns every planned group")
				kill_all(director)
				await process_frame
			check(director._route_length-previous <= 7.0001,"actual template final group leaves at most 2L to exit")
			coverage_summary.cases = int(coverage_summary.cases)+1
			coverage_summary.max_route_length = maxf(float(coverage_summary.max_route_length),director._route_length)
			coverage_summary.max_tail_gap = maxf(float(coverage_summary.max_tail_gap),director._route_length-previous)
			coverage_summary.max_density_supplement = maxi(int(coverage_summary.max_density_supplement),int(director.metrics().density_supplement))
			check(total == int(director.metrics().planned) and total == int(director.metrics().base_budget)+int(director.metrics().density_supplement),"all density supplements are explicitly inside planned/max budget")
			if stage == 1:
				check(director.is_complete(),"real template complete route clears after every required group dies")
				check(director.metrics().spawned==total and director.metrics().defeated==total,"real template clears only after every planned actor was born and defeated")
				check(director.metrics().reward_paid==director.metrics().reward_budget,"real template pays the exact fixed reward after full drain")
		world.free()
		await process_frame

func test_closed_door_edges() -> void:
	var catalog = load("res://scripts/cornfield/room_catalog.gd")
	var world_script = load("res://scripts/cornfield/room_world.gd")
	for side in ["north","east","south","west"]:
		var room: Dictionary = catalog.make_template(0)
		var opposite: String = catalog.opposite_side(side)
		room.doors = {side:"previous",opposite:"next"}
		var door: Vector3 = catalog.door_position(side,room.size)
		var inward: Vector3 = catalog.door_inward(side)
		room.entry_position = door+inward*4.0
		room.main_route = PackedVector3Array([room.entry_position,Vector3(room.size.x*0.5,0,room.size.y*0.5),catalog.door_position(opposite,room.size)+catalog.door_inward(opposite)*6.0])
		var world = world_script.new()
		root.add_child(world)
		world.build(room)
		var player := TestPlayer.new()
		world.add_child(player)
		player.global_position = door+inward*0.51
		await physics_frame
		await physics_frame
		var director = load("res://scripts/cornfield/encounter_director.gd").new()
		world.add_child(director)
		director.configure(world,player,world.definition,3)
		director.set_physics_process(false)
		step(director,0.01)
		check(director.alive_count() == 12,"retreating against the closed "+side+" door still permits a safe full group")
		step(director,0.81)
		check(director.enemies.size() == 12,"closed-door warning resolves without point-blank fallback: "+side)
		world.free()
		await process_frame
