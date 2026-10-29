extends SceneTree
# Multi-door acceptance only. One-door hostile policy remains baseline/unresolved.
const World = preload("res://scripts/cornfield/room_world.gd")
const Director = preload("res://scripts/cornfield/encounter_director.gd")
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const Game = preload("res://scripts/cornfield/game.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: "+message)
func fixture() -> Dictionary:
	var d := Catalog.make_template(0)
	d.doors = {"west":"w","east":"e"}
	d.entry_position = Catalog.door_position("west",d.size)+Vector3.RIGHT*4
	d.main_route = PackedVector3Array([d.entry_position,Catalog.door_position("east",d.size)-Vector3.RIGHT*4])
	d.kind="combat";d.encounter="swarm";d.species=["beetle","mouse","rooster","snail"];d.melee_fallback="mouse";d.content_revision=3
	return d
func setup(d: Dictionary) -> Dictionary:
	var w := World.new();root.add_child(w)
	w.definition=d.duplicate(true);w._outline=PackedVector2Array(d.outline);w._obstacles=d.obstacles
	w._build_boundary();w._build_navigation();w._normalize_room_anchors()
	if w.has_method("_build_spawn_domain"):w._build_spawn_domain()
	var p := CharacterBody3D.new();w.add_child(p);p.position=d.entry_position
	var director := Director.new();w.add_child(director);director.configure(w,p,w.definition,3);director.set_physics_process(false)
	return {"world":w,"player":p,"director":director}
func run() -> void:
	var s := setup(fixture())
	var w = s.world;var d = s.director
	check(not d._spawn_valid(Vector3(w.definition.size.x*.5,0,w.definition.size.y*.75),.34),"actual two-door room rejects clear-ground off-corridor actor")
	check(w.has_method("is_in_spawn_domain"),"RoomWorld supplies shared immutable spawn membership")
	check(w.has_method("spawn_formation_anchors"),"RoomWorld supplies finite static formation anchors")
	if w.has_method("is_in_spawn_domain"):
		check(w.is_in_spawn_domain(Vector3(w.definition.size.x*.5,0,w.definition.size.y*.5+3.15),.34),"full actor footprint fits 3.5m half-width")
		check(not w.is_in_spawn_domain(Vector3(w.definition.size.x*.5,0,w.definition.size.y*.5+3.18),.34),"centre alone does not establish corridor membership")
		for side in w.definition.doors:
			var landing:Vector3=w.get_door_position(side)+Catalog.door_inward(side)*4
			check(not w.is_in_spawn_domain(landing+Catalog.door_inward(side)*3.5,.34),"each real landing protects a 3.5m plus actor-radius capsule")
		var path_before = w.spawn_route_paths().duplicate(true)
		w.register_dynamic_obstacle("test",Vector3(w.definition.size.x*.5,0,w.definition.size.y*.5),1.2)
		w.remove_dynamic_obstacle("test")
		check(path_before==w.spawn_route_paths(),"breaking props cannot expand or reroute immutable domain")
	if w.has_method("spawn_formation_anchors"):
		var anchors:Array=w.spawn_formation_anchors()
		check(anchors.size()>4 and anchors.size()<2000,"domain supplies bounded finite anchor cache")
		var has_twelve:bool=false
		for anchor:Dictionary in anchors:
			if anchor.slots.size()>=12:has_twelve=true
		check(has_twelve,"static geometry admits full twelve-actor compact group")
	var legal:Vector3=Vector3(w.definition.size.x*.5,0,w.definition.size.y*.5)
	d._warnings.append({"records":[{"point":legal,"species":"mouse"}],"remaining":10.0,"segment":0,"group":0,"marks":[]})
	check(not d._spawn_valid(legal+Vector3(.5,0,0),.34),"all pending warning reservations enforce real separation")
	d._warnings.clear()
	check(d.has_method("next_encounter_hint_target"),"director supplies cached legal owed-group hint")
	if d.has_method("next_encounter_hint_target"):
		var untouched:Array=d.group_schedule().duplicate(true)
		var progress:float=d._max_progress
		d._refresh_encounter_hint()
		var hint:Vector3=d.next_encounter_hint_target()
		check(hint.is_finite() and w.is_in_spawn_domain(hint,.34),"eligible group hint targets reachable legal spawn formation")
		check(not w.path_to(s.player.position,hint).is_empty(),"hint anchor is reachable from current player")
		check(d.group_schedule()==untouched and d._max_progress==progress,"hint selection cannot mutate schedule or progress")
		w.register_dynamic_obstacle("hint_block",hint,1.0)
		d._refresh_encounter_hint()
		check(d.next_encounter_hint_target()!=hint,"prop revision invalidates occupied hint target")
		w.remove_dynamic_obstacle("hint_block")
		d._refresh_encounter_hint()
		check(d.next_encounter_hint_target()==hint,"removing prop restores deterministic reachable hint without changing domain")
		check(d.group_schedule()==untouched and d._max_progress==progress,"hint refresh never mutates owed counters")
	var before:Dictionary = d.metrics()
	d._activate(d.segments[0]);d._queue_group(0,.21)
	check(d.metrics().reserved==12,"actual floor-three room reserves full compact opening")
	if d._warnings.size()>0:
		var records:Array=d._warnings[0].records.duplicate(true)
		for a in records.size():
			if w.has_method("is_in_spawn_domain"):check(w.is_in_spawn_domain(records[a].point,.34),"every reserved actor belongs to shared domain")
			for b in range(a+1,records.size()):check(records[a].point.distance_to(records[b].point)>=.71999,"balanced formation has at least .72m real spacing")
		s.player.position=records[0].point
		d._tick_spawn_warnings(.8)
		check(d.metrics().spawned==0 and d.metrics().reserved==0,"moving into warning refunds full group atomically")
		check(d.group_schedule()[0].count==12 and d.group_schedule()[0].spawned==0,"canceled warning retains identical owed group")
		s.player.position=w.definition.entry_position
		for i in 10:
			d._queue_group(0,.21)
			if d.metrics().reserved==12:break
		check(d.metrics().reserved==12,"returning to corridor resumes full promised group")
	if d._warnings.size()>0:
		var first:Dictionary=d._warnings[0]
		var overlap:Dictionary={"records":first.records.duplicate(true),"remaining":10.0,"segment":0,"group":0,"marks":[]}
		d._warnings.append(overlap)
		d._tick_spawn_warnings(.8)
		check(d.metrics().spawned==0,"warning expiry rejects overlap with another pending group")
		d._warnings.clear()
	# A real actor near a later group's candidate must be rejected even before
	# its physics body synchronizes; the conservative actor bound remains .34.
	var living = load("res://scripts/cornfield/field_enemy.gd").new()
	d.add_child(living);living.position=legal;living.configure(w,s.player,"mouse");living.set_physics_process(false)
	d.enemies.append(living)
	check(not d._spawn_valid(legal+Vector3(.5,0,0),.34),"live actor list enforces spacing independent of collider sync")
	var hint_ui := Game.new();hint_ui.director=d;hint_ui.player=s.player
	var owed_before_occupancy:Array=d.group_schedule().duplicate(true)
	d._refresh_encounter_hint()
	var cached_approach:Vector3=d.next_encounter_hint_target()
	check(hint_ui._combat_hint().begins_with("场上余"),"living actors take precedence over cached approach direction")
	d.enemies.clear();living.free()
	d._warnings.append({"records":[{"point":cached_approach,"species":"mouse"}],"remaining":10.0,"segment":0,"group":0,"marks":[]})
	check(hint_ui._combat_hint().begins_with("地面预警"),"warning reservations take precedence over cached approach direction")
	check(not d._spawn_valid(cached_approach,.34),"cached approach cannot bypass an occupied warning reservation")
	d._warnings.clear()
	d._refresh_encounter_hint()
	check(d.next_encounter_hint_target().is_finite() and w.is_in_spawn_domain(d.next_encounter_hint_target(),.34) and not w.path_to(s.player.position,d.next_encounter_hint_target()).is_empty(),"occupancy cleanup reveals a still-legal reachable cached approach")
	check(hint_ui._combat_hint().begins_with("前方还有虫群 · 向"),"empty-field approach direction returns only after occupancy cleanup")
	check(d.group_schedule()==owed_before_occupancy,"hint display under occupancy never changes owed group accounting")
	hint_ui.free()
	check(d.metrics().planned==before.planned and d.metrics().reward_budget==before.reward_budget,"admission never changes schedule or reward budget")
	w.free()
	print("MULTI_DOOR_DOMAIN checks=%d failures=%d; single-door intentionally excluded"%[checks,failures])
	quit(1 if failures else 0)
