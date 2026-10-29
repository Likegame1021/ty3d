extends SceneTree
## Actual domain, camera, dynamic blockers and admission gates. No mocked validity.
## A camera-only key change must not starve a legal formation beyond a bad prefix.
const World = preload("res://scripts/cornfield/room_world.gd")
const Director = preload("res://scripts/cornfield/encounter_director.gd")
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func aim(camera: Camera3D, player: Node3D, boundary: float, offset: float) -> void:
	camera.global_position = player.global_position + Vector3(15,19,15)
	camera.global_position.x = boundary + offset
	camera.look_at(player.global_position,Vector3.UP)

func run() -> void:
	var room := Catalog.make_template(0)
	room.doors = {"west":"w","east":"e"}
	room.entry_position = Vector3(4,0,room.size.y*.5)
	room.main_route = PackedVector3Array([room.entry_position,Vector3(room.size.x-4,0,room.size.y*.5)])
	room.kind = "combat"
	room.encounter = "swarm"
	room.content_revision = 3
	room.melee_fallback = "beetle"
	var world := World.new()
	root.add_child(world)
	world.build(room)
	var player := CharacterBody3D.new()
	world.add_child(player)
	player.position = Vector3(room.size.x*.5,0,room.size.y*.5)
	var fixed_player := player.global_position
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15
	camera.make_current()
	var boundary := roundf((fixed_player.x+15)/.9)*.9
	aim(camera,player,boundary,-.01)
	var director := Director.new()
	world.add_child(director)
	director.configure(world,player,world.definition,3)
	director.set_physics_process(false)
	director.request_exit_check()
	await physics_frame
	await physics_frame
	check(world.spawn_domain_error().is_empty(),"actual two-door domain builds without a configuration error")
	check(world.contains_ground(fixed_player,.3),"fixed player occupies real legal ground")
	var planned: int = director.metrics().planned
	var paths_before: Array = world.spawn_route_paths()
	# Obtain the real implementation's ranking without reserving a warning.
	# Revision 3 lookup does not claim the revision 2 global elite assignment.
	director._find_group(12,0,0)
	var ranked: Array = director._formation_order.duplicate()
	check(ranked.size()>4,"real static domain contains formations beyond the first four")
	if ranked.size()<=4:
		world.free()
		print("DOOR_CAMERA_JITTER checks=%d failures=%d fixture_unavailable=true"%[checks,failures])
		quit(1)
		return
	# Cover the actual static slots of the first four ranked anchors with tiny
	# authoritative dynamic obstacles. Later anchors and all static paths remain.
	var seen: Dictionary = {}
	var blocker_count := 0
	for rank in 4:
		var anchor: Dictionary = director._formation_anchors[int(ranked[rank])]
		for point: Vector3 in anchor.slots:
			var key := Vector2i(roundi(point.x*1000),roundi(point.z*1000))
			if seen.has(key): continue
			seen[key] = true
			world.register_dynamic_obstacle("jitter_prefix_%d"%blocker_count,point,.04)
			blocker_count += 1
	check(paths_before==world.spawn_route_paths(),"prefix blockers do not mutate immutable pair paths")
	var prefix_blocked := true
	for rank in 4:
		var anchor: Dictionary = director._formation_anchors[int(ranked[rank])]
		for point: Vector3 in anchor.slots:
			if director._spawn_valid(point,.34): prefix_blocked=false
	check(prefix_blocked,"all slots of the first four ranked formations fail actual admission")
	# Positive control: a fixed camera must really reserve a full legal warning
	# beyond the blocked prefix. Failure here is a fixture failure, never a skip.
	director.configure(world,player,world.definition,3)
	director.set_physics_process(false)
	director.request_exit_check()
	var sweep_retries := ceili(float(ranked.size())/4.0)+1
	for retry in sweep_retries:
		director._queue_group(0,.21)
		if not director._warnings.is_empty(): break
	var control_ok: bool = director._warnings.size()==1 and director.metrics().reserved==12
	check(control_ok,"fixed camera really admits a complete later formation through existing safety gates")
	if not control_ok:
		print("DOOR_CAMERA_JITTER fixture_unavailable=true anchors=%d blockers=%d"%[ranked.size(),blocker_count])
		world.free()
		print("DOOR_CAMERA_JITTER checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	var witness: Array = director._warnings[0].records.duplicate(true)
	for record: Dictionary in witness:
		check(world.is_in_spawn_domain(record.point,.34),"positive-control warning has full footprint in actual static domain")
	# Reset only the encounter; retain the same world, blocks, player and camera.
	director.configure(world,player,world.definition,3)
	director.set_physics_process(false)
	director.request_exit_check()
	await physics_frame
	await physics_frame
	var witness_stable := true
	for offset: float in [-.01,.01]:
		aim(camera,player,boundary,offset)
		if not director._formation_valid(witness,-1): witness_stable=false
	check(witness_stable,"the same later full formation remains legal at both tiny camera offsets")
	check(floori((boundary-.01)/.9)!=floori((boundary+.01)/.9),"tiny camera positions straddle an actual rank-cache bucket")
	var preferred_before: Vector3 = director._preferred_spawn_point()
	var attempts := 0
	# Two complete finite-list sweeps are sufficient if reranking preserves
	# progress; time elapsed must never permit an unsafe or partial reservation.
	for retry in sweep_retries*2:
		aim(camera,player,boundary,-.01 if retry%2==0 else .01)
		director._queue_group(0,.21)
		attempts += 1
		if not director._warnings.is_empty(): break
	check(player.global_position==fixed_player and director._preferred_spawn_point()==preferred_before,"camera jitter leaves the player and preferred ranking point unchanged")
	check(director._warnings.size()==1 and director.metrics().reserved==12,"camera bucket jitter eventually admits the same full owed group beyond the rejected prefix")
	check(director.metrics().planned==planned and director.metrics().spawned==0 and director.metrics().reward_paid==0,"jitter never changes planned actors or advances birth and reward counters")
	if not director._warnings.is_empty():
		var warning: Dictionary = director._warnings[0]
		check(warning.segment==0 and warning.group==0 and warning.records.size()==12,"camera jitter preserves complete segment and group identity")
		check(is_equal_approx(warning.remaining,.8),"successful jitter admission retains the full warning duration")
		check(director._formation_valid(warning.records,0),"eventual warning still passes every real formation safety gate")
	print("DOOR_CAMERA_JITTER anchors=%d blockers=%d retries=%d checks=%d failures=%d; actual-camera fixture, no mocked admission"%[ranked.size(),blocker_count,attempts,checks,failures])
	world.free()
	quit(1 if failures else 0)
