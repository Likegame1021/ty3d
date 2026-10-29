extends SceneTree
## Real geometry/navigation: mixed-player-cell exhaustion must not cache stale
## reachability failures forever. No mocked ground, path or hint-validity result.
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const Director = preload("res://scripts/cornfield/encounter_director.gd")
class CountingWorld:
	extends "res://scripts/cornfield/room_world.gd"
	var path_calls := 0
	var path_targets := PackedVector3Array()
	func path_to(from: Vector3,to: Vector3,radius: float=.3) -> PackedVector3Array:
		path_calls+=1
		path_targets.append(to)
		return super.path_to(from,to,radius)

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+label)

func run() -> void:
	var room := Catalog.make_template(0)
	room.doors={"west":"w","east":"e"}
	room.entry_position=Catalog.door_position("west",room.size)+Vector3.RIGHT*4
	room.main_route=PackedVector3Array([room.entry_position,Catalog.door_position("east",room.size)+Vector3.LEFT*4])
	room.kind="combat";room.encounter="swarm";room.content_revision=3;room.melee_fallback="beetle"
	var world := CountingWorld.new()
	root.add_child(world)
	world.build(room)
	var immutable_paths: Array=world.spawn_route_paths()
	var anchors: Array=world.spawn_formation_anchors()
	check(anchors.size()>8,"actual straight two-door domain needs more than one bounded hint slice")
	var goal_index := -1
	var nearest := INF
	var centre := Vector3(room.size.x*.5,0,room.size.y*.5)
	for index in anchors.size():
		var anchor: Dictionary=anchors[index]
		if anchor.slots.size()<12: continue
		var distance: float=anchor.point.distance_squared_to(centre)
		if distance<nearest:
			nearest=distance
			goal_index=index
	check(goal_index>=0,"actual static anchor can support the complete owed group")
	if goal_index<0:
		world.free()
		print("DOOR_HINT_EXHAUSTION checks=%d failures=%d fixture_unavailable=true"%[checks,failures])
		quit(1)
		return
	var goal: Vector3=anchors[goal_index].point
	# Every other hint centre is genuinely blocked. Tiny obstacles leave goal A
	# and enough of A's existing static slots legal; its paths are not fabricated.
	for index in anchors.size():
		if index!=goal_index:
			world.register_dynamic_obstacle("hint_other_%d"%index,anchors[index].point,.01)
	var initial := goal+Vector3(0,0,5.4)
	var resumed := goal+Vector3(0,0,4.4)
	check(world.contains_ground(initial,.3) and world.contains_ground(resumed,.3),"both controlled player samples are ordinary legal static ground")
	world.register_dynamic_obstacle("hint_initial_player_block",initial,.25)
	var usable := 0
	for point: Vector3 in anchors[goal_index].slots:
		if world.contains_ground(point,.34): usable+=1
	check(world.contains_ground(goal,.34) and usable>=12,"goal A centre and full static capacity remain actually available")
	check(not world.contains_ground(initial,.3) and world.contains_ground(resumed,.3),"initial prop blocks only the first controlled player location")
	var player := CharacterBody3D.new()
	world.add_child(player)
	player.position=initial
	var director := Director.new()
	world.add_child(director)
	director.configure(world,player,world.definition,3)
	director.set_physics_process(false)
	await physics_frame
	await physics_frame
	var before: Dictionary=director.metrics()
	var schedule: Array=director.group_schedule().duplicate(true)
	var progress: float=director._max_progress
	world.path_calls=0
	world.path_targets.clear()
	director._refresh_encounter_hint()
	var first_cursor: int=director._hint_cursor
	check(world.path_targets.has(goal),"first bounded slice really tests A from the blocked initial player sample")
	check(not director.next_encounter_hint_target().is_finite() and first_cursor>0 and first_cursor<director._hint_candidates.size(),"first real slice leaves a pending finite traversal")
	check(world.path_calls<=4,"first slice stays within the four-path bound")
	# This single controlled relocation is outside the real-input movement test.
	# It models the current-cell change while a hint search is unfinished.
	player.position=resumed
	check(Vector2i(floori(initial.x/.9),floori(initial.z/.9))!=Vector2i(floori(resumed.x/.9),floori(resumed.z/.9)),"resumed player is in a different navigation cell")
	check(not world.path_to(resumed,goal,.3).is_empty(),"positive control: A is actually reachable from the final stable player cell")
	var other_centres_blocked := true
	for index in anchors.size():
		if index!=goal_index and world.contains_ground(anchors[index].point,.34): other_centres_blocked=false
	check(other_centres_blocked,"all later non-A hint centres still fail actual dynamic-ground legality")
	world.path_calls=0
	director._refresh_encounter_hint()
	check(director._hint_cursor>first_cursor,"player-cell crossing continues the unfinished sweep rather than restarting its rejected prefix")
	check(world.path_calls<=4,"cell-crossing slice keeps its bounded path work")
	var max_slice_paths := 0
	var refreshes := 0
	var limit := ceili(float(anchors.size())/4.0)*2+3
	for attempt in limit:
		world.path_calls=0
		director._refresh_encounter_hint()
		refreshes+=1
		max_slice_paths=maxi(max_slice_paths,world.path_calls)
		if director.next_encounter_hint_target().is_finite(): break
	var result: Vector3=director.next_encounter_hint_target()
	check(result.is_finite() and result.distance_to(goal)<.00001,"mixed-cell exhaustion revisits earlier A and returns it from the final stable cell")
	check(max_slice_paths<=4,"stable-cell retry does not exceed four navigation calls per refresh")
	check(world.spawn_route_paths()==immutable_paths,"temporary hint availability never changes immutable actual-door paths")
	check(director.group_schedule()==schedule and director._max_progress==progress and not director._force_queue,"hint continuation never advances scheduled progress or forces a group")
	var after: Dictionary=director.metrics()
	check(after.planned==before.planned and after.spawned==0 and after.reserved==0 and after.defeated==0 and after.reward_paid==0 and not director.is_complete(),"hint continuation preserves all owed actors and reward accounting")
	print("DOOR_HINT_EXHAUSTION anchors=%d goal_index=%d usable=%d refreshes=%d maximum_slice_paths=%d checks=%d failures=%d; real path positive control, controlled blocked-origin relocation"%[anchors.size(),goal_index,usable,refreshes,max_slice_paths,checks,failures])
	world.free()
	quit(1 if failures else 0)
