extends SceneTree
## Real queued groups; another warning resolves between cancellation and retry.
const World = preload("res://scripts/cornfield/room_world.gd")
const Director = preload("res://scripts/cornfield/encounter_director.gd")
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + label)
func reserve(d: Node3D, segment: int) -> bool:
	var before: int = d._warnings.size()
	for attempt in 100:
		d._queue_group(segment,.21)
		if d._warnings.size()>before: return true
	return false
func identities(records: Array) -> Array:
	var result: Array = []
	for record: Dictionary in records: result.append([record.species,record.elite])
	return result
func elite_reservations(d: Node3D) -> int:
	var count := 0
	for warning: Dictionary in d._warnings:
		for record: Dictionary in warning.records:
			if record.elite: count+=1
	return count
func check_elite_retry(d: Node3D,w: Node3D,p: Node3D,revision: int) -> void:
	d.configure(w,p,w.definition,1); d.set_physics_process(false); d.request_exit_check()
	check(reserve(d,0),"elite opening reserves rev%d"%revision)
	if d._warnings.is_empty(): return
	var first: Dictionary=d._warnings[0].duplicate(true)
	check(elite_reservations(d)==1,"only one initial elite reservation rev%d"%revision)
	d._tick_spawn_warnings(.2)
	# Exercise the admission API at its real cap with a concurrent small warning.
	# Normal scheduler's half-cap throttle is intentionally bypassed in this case.
	check(reserve(d,0),"concurrent nonelite refill fits actual cap rev%d"%revision)
	if d._warnings.size()!=2: return
	check(elite_reservations(d)==1 and d.alive_count()<=d.cap,"concurrent admission does not duplicate elite rev%d"%revision)
	w.register_dynamic_obstacle("elite_cancel",first.records[0].point,.1)
	d._tick_spawn_warnings(.6)
	w.remove_dynamic_obstacle("elite_cancel")
	d._tick_spawn_warnings(.2)
	for enemy in d.enemies:
		if is_instance_valid(enemy): enemy.set_physics_process(false)
	check(d._next_segment()==int(first.segment) and reserve(d,int(first.segment)),"canceled elite opening retries before another owed group rev%d"%revision)
	if not d._warnings.is_empty():
		check(identities(d._warnings[0].records)==identities(first.records),"concurrent resolution preserves elite warning's exact roster rev%d"%revision)
	check(elite_reservations(d)==1 and d.metrics().elite_spawned==0,"exactly one elite remains reserved before retry birth rev%d"%revision)
	d._tick_spawn_warnings(.8)
	check(d.metrics().elite_spawned==1 and elite_reservations(d)==0,"exactly one elite actually born after retry rev%d"%revision)
	d.shutdown()
	check(d._warnings.is_empty() and d._retry_groups.is_empty() and d._retry_rosters.is_empty() and d.alive_count()==0,"shutdown releases warnings retry ownership and actors rev%d"%revision)
	d.configure(w,p,w.definition,1); d.set_physics_process(false)
	check(d._retry_groups.is_empty() and d._retry_rosters.is_empty() and d.metrics().spawned==0 and d.metrics().reserved==0 and d.metrics().elite_spawned==0,"reconfigure clears all cancellation state rev%d"%revision)
func run() -> void:
	for revision in [2,3]:
		var room := Catalog.make_template(0)
		room.doors = {"west":"w","east":"e"}
		room.entry_position = Vector3(4,0,room.size.y*.5)
		room.main_route = PackedVector3Array([room.entry_position,Vector3(room.size.x-4,0,room.size.y*.5)])
		room.kind="combat"; room.encounter="swarm"; room.content_revision=revision; room.melee_fallback="beetle"; room.elite=true
		var w := World.new(); root.add_child(w)
		w.definition=room; w._outline=PackedVector2Array(room.outline); w._obstacles=room.obstacles
		w._build_boundary(); w._build_navigation(); w._normalize_room_anchors(); w._build_spawn_domain()
		var p := CharacterBody3D.new(); w.add_child(p); p.position=room.entry_position
		var d := Director.new(); w.add_child(d); d.configure(w,p,w.definition,1); d.set_physics_process(false)
		d.request_exit_check()
		var planned: int = d.metrics().planned
		# Settle each actual opening so small refills can overlap under the cap.
		for segment in d.segments.size():
			check(reserve(d,segment),"opening queues rev%d segment%d"%[revision,segment])
			d._tick_spawn_warnings(.8)
			for enemy in d.enemies.duplicate():
				if is_instance_valid(enemy) and not enemy.dead:
					enemy.set_physics_process(false); enemy.receive_hit(100000,Vector3.RIGHT)
			await physics_frame; await physics_frame
		check(reserve(d,0),"first actual refill queues rev%d"%revision)
		if d._warnings.is_empty(): w.free(); continue
		var first: Dictionary=d._warnings[0].duplicate(true)
		d._tick_spawn_warnings(.2)
		check(reserve(d,0),"second actual refill queues beside first rev%d"%revision)
		if d._warnings.size()!=2: w.free(); continue
		var second: Dictionary=d._warnings[1].duplicate(true)
		var before: Dictionary=d.metrics()
		w.register_dynamic_obstacle("late_cancel",first.records[0].point,.1)
		d._tick_spawn_warnings(.6)
		check(d._warnings.size()==1 and d.metrics().reserved==second.records.size(),"cancel releases only its own reservation rev%d"%revision)
		check(d.metrics().spawned==before.spawned and d.metrics().defeated==before.defeated and d.metrics().reward_paid==before.reward_paid,"cancel consumes no actor defeat or reward rev%d"%revision)
		w.remove_dynamic_obstacle("late_cancel")
		d._tick_spawn_warnings(.2)
		check(d.metrics().spawned==before.spawned+second.records.size(),"other pending warning really resolves before retry rev%d"%revision)
		for enemy in d.enemies:
			if is_instance_valid(enemy): enemy.set_physics_process(false)
		check(d._next_segment()==int(first.segment),"canceled segment retains retry priority rev%d"%revision)
		check(reserve(d,int(first.segment)),"late canceled group can reserve again rev%d"%revision)
		if not d._warnings.is_empty():
			var retry: Dictionary=d._warnings[0]
			check(retry.segment==first.segment and retry.group==first.group,"late retry keeps exact owed segment and group rev%d"%revision)
			check(identities(retry.records)==identities(first.records),"late retry keeps exact warned species and elite slots rev%d"%revision)
			check(retry.records.size()==first.records.size(),"late retry keeps complete group count rev%d"%revision)
		check(d.metrics().planned==planned and d.metrics().alive_including_warnings<=d.cap,"late retry preserves planned count and cap rev%d"%revision)
		check_elite_retry(d,w,p,revision)
		w.free(); await process_frame
	print("DOOR_LATE_CANCEL checks=%d failures=%d; actual warnings, revisions2/3, single-door excluded"%[checks,failures])
	quit(1 if failures else 0)
