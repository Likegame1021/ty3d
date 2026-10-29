extends SceneTree
## Focused shared-descriptor / real physics / aggregate-warning regression.
const Director = preload("res://scripts/cornfield/encounter_director.gd")
const Enemy = preload("res://scripts/cornfield/field_enemy.gd")
const Catalog = preload("res://scripts/cornfield/enemy_catalog.gd")
var checks := 0
var failures: Array[String] = []

class TestWorld extends Node3D:
	func set_doors_open(_value: bool) -> void: pass

class TestPlayer extends CharacterBody3D:
	var hits := 0
	var hp := 100.0
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .22
		capsule.height = 1.2
		collider.shape = capsule
		collider.position.y = .6
		add_child(collider)
	func receive_damage(amount: float, _direction := Vector3.ZERO) -> void:
		hits += 1
		hp -= amount

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ",label)

func fixture(species := "corn_borer", elite := false) -> Dictionary:
	var world := TestWorld.new()
	root.add_child(world)
	var player := TestPlayer.new()
	world.add_child(player)
	player.position = Vector3(4,0,0)
	var director := Director.new()
	world.add_child(director)
	director.player = player
	director.world = world
	director._stopped = false
	director.set_physics_process(false)
	var enemy := Enemy.new()
	world.add_child(enemy)
	# No art is needed for these tests; use real attack, preview and physics code.
	enemy.world = world
	enemy.target = player
	enemy.species = species
	enemy.elite = elite
	enemy.boss = species == "boss_borer"
	enemy.profile = Catalog.profile(species,elite)
	enemy.birth_time = 1.0
	enemy.attack_pattern = str(enemy.profile.attack)
	enemy.set_physics_process(false)
	return {"world":world,"player":player,"director":director,"enemy":enemy}

func begin(scene: Dictionary, pattern: String) -> Dictionary:
	var warnings: Array = []
	var collect := func(payload: Dictionary): warnings.append(payload)
	scene.enemy.warning_requested.connect(collect)
	scene.enemy.attack_pattern = pattern
	scene.enemy._prepare_windup(float(scene.enemy.profile.windup))
	scene.enemy.warning_requested.disconnect(collect)
	return warnings[0]

func warning_for(scene: Dictionary, payload: Dictionary):
	scene.director._spawn_attack_warning(payload)
	var warning = scene.director._attack_warnings[-1]
	warning.set_physics_process(false)
	return warning

func wall(scene: Dictionary, origin: Vector3, size: Vector3, angle := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	scene.world.add_child(body)
	body.position = origin
	body.rotation.y = angle
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body

func settle() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	# The RED run must fail for the actual missing 1/3/5/10 path payloads.
	for specification in [["snail","spit",1],["corn_borer","fan",3],["boss_borer","fan",5],["boss_borer","ring",10]]:
		var scene := fixture(specification[0])
		var payload := begin(scene,specification[1])
		check(payload.has("projectile_paths") and payload.get("projectile_paths",[]).size()==specification[2],"%s %s warning contains all %d actual shot paths"%specification)
		check(scene.enemy.has_method("projectile_descriptors"),"one authoritative descriptor API exists for "+str(specification[1]))
		scene.world.free()
	if not failures.is_empty():
		finish()
		return
	await test_descriptors_and_parameters()
	await test_geometry_and_cache()
	await test_translation_cache()
	await test_short_wall_and_clear()
	await test_clipping_and_displacement()
	await test_hit_boundary()
	await test_lifecycle_and_cap()
	finish()

func test_descriptors_and_parameters() -> void:
	for specification in [["snail","spit",[0.0]],["corn_borer","fan",[-.28,0.0,.28]],["boss_borer","fan",[-.6,-.3,0.0,.3,.6]],["boss_borer","ring",[]]]:
		for elite in [false,true]:
			var scene := fixture(specification[0],elite)
			var enemy = scene.enemy
			var offsets: Array = specification[2].duplicate()
			if specification[1]=="ring":
				for index in 10: offsets.append(index*TAU/10.0+.16)
			for stage in [1,2]:
				enemy.boss_stage = stage
				scene.player.position = Vector3(3.1,0,2.3)
				var payload := begin(scene,specification[1])
				var descriptors: Array = enemy.projectile_descriptors()
				var shots: Array = []
				var collect := func(shot: Dictionary): shots.append(shot)
				enemy.projectile_requested.connect(collect)
				enemy._start_strike()
				enemy.projectile_requested.disconnect(collect)
				check(shots.size()==offsets.size(),"exact volley count/order "+str(specification[0]))
				check(payload.projectile_paths==descriptors and shots==emission_payloads(descriptors),"warning and emission consume identical ordered descriptors")
				for index in mini(shots.size(),offsets.size()):
					var shot: Dictionary = shots[index]
					check(shot.size()==6 and not shot.has("muzzle_offset"),"preview-only relative geometry does not leak into original six-field signal payload")
					var heading: Vector3 = enemy.strike_direction.rotated(Vector3.UP,offsets[index])
					var muzzle: Vector3 = enemy.global_position+Vector3.UP*.65+heading*(float(enemy.profile.radius)/32.0+.2)
					check(shot.origin.is_equal_approx(muzzle) and shot.direction.is_equal_approx(heading),"original exact muzzle/heading including ring phase")
					check(is_equal_approx(shot.speed,3.75 if specification[0]=="snail" else 4.9) and is_equal_approx(shot.lifetime,2.6) and is_equal_approx(shot.damage,float(enemy.profile.damage)*.8),"speed/lifetime/damage unchanged")
				check(is_equal_approx(payload.duration,float(enemy.profile.windup)) and is_equal_approx(enemy.phase_time,float(enemy.profile.strike)),"windup and strike timings preserved")
				enemy._begin_recovery()
				check(is_equal_approx(enemy.phase_time,float(enemy.profile.recovery)*(.86 if stage==2 else 1.0)),"stage recovery factor unchanged")
			var calls: Array = []
			enemy.projectile_requested.connect(func(shot: Dictionary): calls.append(shot))
			enemy.birth_time = .59
			enemy._emit_projectiles()
			check(calls.is_empty(),"newborn emission gate unchanged")
			enemy.birth_time = 1.0
			enemy.dead = true
			enemy._emit_projectiles()
			check(calls.is_empty(),"dead emission gate unchanged")
			scene.world.free()
	await process_frame

func emission_payloads(descriptors: Array) -> Array:
	var values: Array = []
	for descriptor in descriptors:
		var value: Dictionary = descriptor.duplicate()
		value.erase("muzzle_offset")
		values.append(value)
	return values

func mesh_contains(mesh: Mesh, point: Vector2) -> bool:
	if mesh == null: return false
	var vertices := mesh.get_faces()
	for index in range(0,vertices.size(),3):
		var triangle := PackedVector2Array()
		for offset in 3:
			triangle.append(Vector2(vertices[index+offset].x,vertices[index+offset].z))
		if Geometry2D.is_point_in_polygon(point,triangle): return true
	return false

func test_geometry_and_cache() -> void:
	for specification in [["snail","spit",1],["corn_borer","fan",3],["boss_borer","fan",5],["boss_borer","ring",10]]:
		var scene := fixture(specification[0])
		var payload := begin(scene,specification[1])
		var warning = warning_for(scene,payload)
		check(warning.get_child_count()==3 and warning.has_node("DangerFill"),"one volley has three aggregate meshes, no per-path disc nodes")
		check(warning.preview_paths.size()==specification[2],"every side/rear path has clipped preview")
		check(is_equal_approx(warning.clearance,.22),"clearance comes from actual player capsule, excludes visual .11 radius")
		for path in warning.preview_paths:
			check(is_equal_approx(path.origin.y,.65) and is_equal_approx(path.origin.distance_to(path.end),float(path.speed)*float(path.lifetime)),"preview uses actual muzzle and full speed*lifetime reach")
		var fill: MeshInstance3D = warning.get_node("DangerFill")
		var symbol: MeshInstance3D = warning.get_node("DangerSymbol")
		check(symbol.mesh.get_faces().size()==specification[2]*12,"exactly one two-stroke chevron per visible path")
		var ids: Array = []
		for node in warning.get_children(): ids.append(node.mesh.get_instance_id())
		for tick in 60: warning._physics_process(.001)
		var after: Array = []
		for node in warning.get_children(): after.append(node.mesh.get_instance_id())
		check(ids==after,"60 unchanged opacity ticks do not rebuild any aggregate mesh")
		check(warning.get_node("DangerBoundary").scale==Vector3.ONE,"opacity pulse cannot change lane bounds")
		if specification[0]=="snail":
			check(mesh_contains(fill.mesh,Vector2(3,.21)) and not mesh_contains(fill.mesh,Vector2(3,.24)),"fill covers .22 player center clearance, not arbitrary old radius")
			var collision: CollisionShape3D = scene.player.get_child(0)
			collision.shape.radius = .31
			warning._physics_process(0)
			check(is_equal_approx(warning.clearance,.31) and mesh_contains(warning.get_node("DangerFill").mesh,Vector2(3,.30)),"preview reads collider shape rather than hard-coding .22")
		if specification[0]=="corn_borer":
			check(mesh_contains(fill.mesh,Vector2(.8,.11)),"near-source fan overlap is filled without a false safe cutout")
			check(not mesh_contains(fill.mesh,Vector2(6,.83)),"farther-out actual fan gap stays open")
			scene.player.position = Vector3(1.5,0,0)
			await settle()
			warning._physics_process(0)
			check(is_equal_approx(warning.preview_paths[1].origin.distance_to(warning.preview_paths[1].end),12.74),"present player capsule never shortens preview")
		scene.world.free()
	await process_frame

func test_translation_cache() -> void:
	for start in [Vector3(4,0,4),Vector3(7,0,7),Vector3(15,0,7),Vector3(16,0,16),Vector3(31.13,0,23.79),Vector3(47.13,0,33.79)]:
		var scene := fixture("boss_borer")
		scene.enemy.position = start
		scene.player.position = scene.enemy.position+Vector3(3.1,0,2.3)
		var warning = warning_for(scene,begin(scene,"ring"))
		var meshes: Array = []
		for child in warning.get_children(): meshes.append(child.mesh.get_instance_id())
		var rebuilds := 0
		for tick in 60:
			scene.enemy.position += Vector3(.017,0,-.013)
			warning._physics_process(.001)
			var current: Array = []
			for child in warning.get_children(): current.append(child.mesh.get_instance_id())
			if current != meshes: rebuilds += 1
			meshes = current
			check(warning.payload.projectile_paths==scene.enemy.projectile_descriptors(),"moving-source cache preserves exact world-space descriptors")
		print("TRANSLATION_CACHE start=",start," ticks=60 rebuild_ticks=",rebuilds)
		check(rebuilds==0,"pure unblocked source translation reanchors without rebuilding unchanged lanes at "+str(start))
		scene.enemy.strike_direction=scene.enemy.strike_direction.rotated(Vector3.UP,.11)
		warning._physics_process(0)
		check(meshes[0]!=warning.get_node("DangerBoundary").mesh.get_instance_id(),"true changed heading invalidates geometry cache")
		scene.world.free()
	await process_frame

func test_short_wall_and_clear() -> void:
	var scene := fixture("snail")
	var blocker := wall(scene,Vector3(.9,.65,0),Vector3(.1,.4,1))
	await settle()
	var warning = warning_for(scene,begin(scene,"spit"))
	check(warning.preview_paths[0].blocked and warning.get_node("DangerSymbol").mesh.get_surface_count()==0,"short clipped lane omits arrow rather than crossing wall")
	blocker.free()
	await settle()
	warning._physics_process(0)
	check(not warning.preview_paths[0].blocked and warning.get_node("DangerSymbol").mesh.get_faces().size()==12,"changed world obstruction restores full lane and arrow")
	scene.director._check_clear()
	check(warning.is_queued_for_deletion(),"room clear removes ranged aggregate warning")
	await process_frame
	check(not is_instance_valid(warning),"room clear leaves no old aggregate meshes")
	scene.director._complete = false
	warning = warning_for(scene,begin(scene,"spit"))
	check(scene.director._attack_warnings.size()==1 and warning.get_child_count()==3,"repeated volley replaces freed old lanes with one reservation")
	scene.world.free()
	await process_frame

func test_clipping_and_displacement() -> void:
	var scene := fixture()
	var payload := begin(scene,"fan")
	var warning = warning_for(scene,payload)
	var blocker := wall(scene,Vector3(3,.65,0),Vector3(.2,.5,.4))
	await settle()
	warning._physics_process(0)
	check(warning.preview_paths.size()==3 and warning.preview_paths[1].blocked,"projectile-height centered wall stops central path")
	check(not warning.preview_paths[0].blocked and not warning.preview_paths[2].blocked,"unblocked sibling fan paths survive")
	check(is_equal_approx(warning.preview_paths[1].end.x,2.9),"centerline ends at first actual wall surface")
	var end: Vector3 = warning.preview_paths[1].end
	check(not mesh_contains(warning.get_node("DangerFill").mesh,Vector2(end.x+.05,0)),"blocked end is flat rather than a round cap through wall")
	var symbols: PackedVector3Array = warning.get_node("DangerSymbol").mesh.get_faces()
	for vertex in symbols:
		if absf(vertex.z)<.2: check(vertex.x<=end.x,"central arrow never projects through wall")
	blocker.rotation.y = .55
	await settle()
	warning._physics_process(0)
	var direct: Dictionary = scene.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(warning.preview_paths[1].origin,Vector3(14,.65,0),1))
	check(not direct.is_empty() and warning.preview_paths[1].end.is_equal_approx(direct.position),"angled wall uses same projectile-height ray endpoint")
	blocker.position.y = .15
	await settle()
	warning._physics_process(0)
	check(not warning.preview_paths[1].blocked,"low ground obstacle does not falsely block a .65m shot")
	blocker.free()
	await settle()
	# A tiny actor-to-muzzle wall blocks only the middle heading.
	blocker = wall(scene,Vector3(.30,.65,0),Vector3(.05,.2,.045))
	await settle()
	warning._physics_process(0)
	check(warning.preview_paths.size()==2,"blocked muzzle path omitted while side siblings remain")
	blocker.free()
	await settle()
	var locked: Vector3 = scene.enemy.strike_direction
	scene.enemy.position += Vector3(0,0,1.2)
	scene.player.position = Vector3(1,0,4)
	warning._physics_process(0)
	var shots: Array = []
	scene.enemy.projectile_requested.connect(func(shot: Dictionary): shots.append(shot))
	scene.enemy._emit_projectiles()
	check(scene.enemy.strike_direction==locked,"moving target never retargets locked windup heading")
	check(emission_payloads(warning.payload.projectile_paths)==shots,"displaced source preview matches actual release muzzles")
	check(warning.global_position.is_equal_approx(scene.enemy.global_position+Vector3.UP*.035),"aggregate meshes follow displaced source")
	blocker = wall(scene,(scene.player.position+scene.enemy.position)*.5+Vector3.UP*.65,Vector3(2,.5,2))
	await settle()
	shots.clear()
	scene.enemy._emit_projectiles()
	check(shots.is_empty(),"release cancels when current target LOS is lost")
	scene.world.free()
	await process_frame

func test_hit_boundary() -> void:
	var scene := fixture("snail")
	var warning = warning_for(scene,begin(scene,"spit"))
	for lateral in [.21,.24,-.21,-.24]:
		scene.player.position = Vector3(3,0,lateral)
		await settle()
		var shot: Dictionary = scene.enemy.projectile_descriptors()[0]
		var projectile := Director.HostileProjectile.new()
		projectile.payload = shot
		projectile.player = scene.player
		projectile._batched_visual = true
		scene.world.add_child(projectile)
		projectile.global_position = shot.origin
		projectile.set_physics_process(false)
		var before: int = scene.player.hits
		projectile._physics_process(1.0)
		var expected := absf(lateral)<.22
		check((scene.player.hits>before)==expected,"real swept-ray/player capsule lateral boundary "+str(lateral))
		check(mesh_contains(warning.get_node("DangerFill").mesh,Vector2(3,lateral))==expected,"warning envelope matches sampled player-center hit rule "+str(lateral))
		projectile.queue_free()
	scene.world.free()
	await process_frame

func test_lifecycle_and_cap() -> void:
	var scene := fixture("boss_borer")
	var payload := begin(scene,"ring")
	var warning = warning_for(scene,payload)
	check(scene.director._attack_warnings.size()==1,"ten-shot ring consumes one warning reservation")
	warning.set_physics_process(true)
	var before: float = warning.elapsed
	paused = true
	for frame in 4: await process_frame
	check(warning.elapsed==before,"pause freezes ranged warning time")
	paused = false
	warning.set_physics_process(false)
	scene.enemy.dead = true
	warning._physics_process(0)
	check(warning.is_queued_for_deletion(),"source death removes aggregate warning")
	await process_frame
	scene.enemy.dead = false
	for index in 31:
		var current = warning_for(scene,payload)
		current.set_physics_process(false)
	check(scene.director._attack_warnings.size()==30,"unchanged 30 warning cap remains one reservation per volley")
	check(Director.MAX_PROJECTILES==80,"unchanged 80 projectile cap")
	scene.director.shutdown()
	check(scene.director.get_child_count()==0 and scene.director._attack_warnings.is_empty(),"shutdown detaches all aggregate nodes and reservations")
	var detached := Director.AttackWarning.new()
	detached.payload = payload
	detached.player = scene.player
	scene.director.add_child(detached)
	detached.set_physics_process(false)
	scene.enemy.free()
	detached._physics_process(0)
	check(detached.is_queued_for_deletion(),"freed source cannot leave stale lanes")
	scene.world.free()
	await process_frame

func finish() -> void:
	print("CORNFIELDS_PROJECTILE_TELEGRAPHS %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
