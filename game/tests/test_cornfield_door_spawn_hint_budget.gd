extends SceneTree
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
class CountingWorld:
	extends "res://scripts/cornfield/room_world.gd"
	var hint_ground_calls:=0
	var hint_path_calls:=0
	var _inside_path:=false
	func contains_ground(point:Vector3,radius:float=.3)->bool:
		if not _inside_path:hint_ground_calls+=1
		return super.contains_ground(point,radius)
	func path_to(from:Vector3,to:Vector3,radius:float=.3)->PackedVector3Array:
		hint_path_calls+=1
		_inside_path=true
		var result:=super.path_to(from,to,radius)
		_inside_path=false
		return result
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)
func fixture(sides:Array)->Dictionary:
	var room:=Catalog.make_template(0);room.doors={}
	for side:String in sides:room.doors[side]=side
	room.entry_position=Catalog.door_position(sides[0],room.size)+Catalog.door_inward(sides[0])*4
	room.main_route=PackedVector3Array([room.entry_position,Vector3(room.size.x*.5,0,room.size.y*.5),Catalog.door_position(sides[1],room.size)+Catalog.door_inward(sides[1])*6])
	room.kind="combat";room.encounter="swarm";room.content_revision=3;room.melee_fallback="beetle"
	var world:=CountingWorld.new();root.add_child(world)
	world.definition=room;world._outline=PackedVector2Array(room.outline);world._obstacles=room.obstacles
	world._build_boundary();world._build_navigation();world._normalize_room_anchors();world._build_spawn_domain()
	var player:=CharacterBody3D.new();world.add_child(player);player.position=world.definition.entry_position
	var director:=Director.new();world.add_child(director);director.configure(world,player,world.definition,3);director.set_physics_process(false)
	return {"world":world,"player":player,"director":director}
func refresh(s:Dictionary)->void:
	s.world.hint_ground_calls=0;s.world.hint_path_calls=0
	var started:=Time.get_ticks_usec()
	s.director._refresh_encounter_hint()
	check(s.world.hint_ground_calls<=104,"one hint slice checks at most four26-point formations")
	check(s.world.hint_path_calls<=4,"one hint slice requests at most four current paths")
	print("HINT_SLICE ground=",s.world.hint_ground_calls," paths=",s.world.hint_path_calls," usec=",Time.get_ticks_usec()-started)
func run()->void:
	var s:=fixture(["west","east","north","south"])
	var initial:Array=s.director.group_schedule().duplicate(true)
	refresh(s)
	var hint:Vector3=s.director.next_encounter_hint_target()
	check(hint.is_finite() and s.world.is_in_spawn_domain(hint,.34),"cold hint resolves a legal static formation")
	refresh(s)
	check(s.world.hint_ground_calls==0 and s.world.hint_path_calls==0,"unchanged empty-field hint performs no repeated geometry work")
	s.player.position+=Vector3.RIGHT*.91
	refresh(s)
	check(s.director.next_encounter_hint_target().is_finite(),"moving one navigation cell retains a reachable approach")
	check(s.director.group_schedule()==initial and s.director._max_progress==0 and s.director.metrics().spawned==0 and s.director.metrics().reward_paid==0,"hint budget does not activate groups or alter owed counters")
	s.world.free()
	# An unfinished finite search must continue while the player crosses a cell
	# boundary, and real prop removal must invalidate cached negative capacities.
	s=fixture(["west","east"]);s.player.position.x=5.39
	var anchors:Array=s.world.spawn_formation_anchors()
	anchors.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.point.distance_squared_to(s.player.position)<b.point.distance_squared_to(s.player.position))
	var domain:Array=s.world.spawn_route_paths()
	for i in 8:s.world.register_dynamic_obstacle("hint_prefix_%d"%i,anchors[i].point,.05)
	refresh(s)
	check(not s.director.next_encounter_hint_target().is_finite(),"blocked nearest prefix defers direction within the per-refresh budget")
	for i in 8:
		s.player.position.x=5.41 if i%2==0 else 5.39
		refresh(s)
		if s.director.next_encounter_hint_target().is_finite():break
	var continued:Vector3=s.director.next_encounter_hint_target()
	check(continued.is_finite() and s.world.is_in_spawn_domain(continued,.34) and not s.world.path_to(s.player.position,continued,.3).is_empty(),"moving-cell jitter eventually resolves a later actual legal path")
	for i in 8:s.world.remove_dynamic_obstacle("hint_prefix_%d"%i)
	refresh(s)
	check(s.director.next_encounter_hint_target()==anchors[0].point,"prop removal invalidates negative hint cache and restores nearest formation")
	check(domain==s.world.spawn_route_paths(),"hint occupancy never changes static door routes")
	for i in anchors.size():s.world.register_dynamic_obstacle("all_hint_%d"%i,anchors[i].point,.05)
	for i in ceili(float(anchors.size())/4)+2:refresh(s)
	check(not s.director.next_encounter_hint_target().is_finite(),"all real formation goals blocked produces no invented hint")
	check(s.director.metrics().planned>0 and s.director.metrics().spawned==0 and not s.director.is_complete(),"exhausted hint search leaves full encounter owed")
	var next_room:=fixture(["north","west"])
	var reused:Node3D=s.director
	reused.reparent(next_room.world)
	reused.configure(next_room.world,next_room.player,next_room.world.definition,3);reused.set_physics_process(false)
	next_room.director.free();next_room.director=reused
	s.world.free();s=next_room
	refresh(s)
	check(s.director.next_encounter_hint_target().is_finite() and s.world.is_in_spawn_domain(s.director.next_encounter_hint_target(),.34),"reused director clears prior room and prop cache for new domain")
	s.world.free()
	# Locked late progress in the adjacent-door alias fixture must still reach
	# the real door-check fallback after bounded formation search exhaustion.
	s=fixture(["north","west"])
	for si in s.director.segments.size():
		for gi in s.director.segments[si].groups.size():
			if si==s.director.segments.size()-1 and gi==s.director.segments[si].groups.size()-1:continue
			var group:Dictionary=s.director.segments[si].groups[gi];group.spawned=group.count
	var owed:Dictionary=s.director.segments[-1].groups[-1]
	var late_anchors:Array=s.world.spawn_formation_anchors()
	for i in late_anchors.size():
		if s.director._project_progress(late_anchors[i].point)+.1>=float(owed.progress):s.world.register_dynamic_obstacle("late_hint_%d"%i,late_anchors[i].point,.05)
	for i in ceili(float(s.world.spawn_formation_anchors().size())/4)+2:
		refresh(s)
		if s.director.next_encounter_hint_target().is_finite():break
	var point:Vector3=s.director.next_encounter_hint_target()
	check(point.is_finite() and s.director._hint_kind=="exit_check","late locked alias reaches actual door fallback rather than dropping it")
	var trigger:=false
	for side:String in s.world.definition.doors:
		if point.distance_to(s.world.get_door_position(side))<1.3:trigger=true
	check(trigger and not s.world.path_to(s.player.position,point,.3).is_empty(),"bounded fallback remains a reachable existing door-check goal")
	check(s.director._max_progress==0 and not s.director._force_queue and s.director.metrics().reward_paid==0,"hint fallback never forces activation or pays rewards by itself")
	s.world.free()
	print("DOOR_HINT_BUDGET checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
