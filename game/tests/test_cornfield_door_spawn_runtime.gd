extends SceneTree
# Real authored geometry, physical actors, current game camera, dynamic props.
const World=preload("res://scripts/cornfield/room_world.gd")
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:=0
var profile:Array=[]
var cold_profile:Array=[]
var steady_profile:Array=[]
var whole_tick_profile:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func definition(template:int,sides:Array)->Dictionary:
	var d:=Catalog.make_template(template);d.doors={}
	for side:String in sides:d.doors[side]=side
	d.entry_position=Catalog.door_position(sides[0],d.size)+Catalog.door_inward(sides[0])*4
	d.main_route=PackedVector3Array([d.entry_position,Vector3(d.size.x*.5,0,d.size.y*.5),Catalog.door_position(sides[1],d.size)+Catalog.door_inward(sides[1])*6])
	d.content_revision=3;d.melee_fallback="beetle";d.elite=true
	return d
func scene(d:Dictionary,stage:int=3)->Dictionary:
	var w:=World.new();root.add_child(w);w.build(d)
	var p:=CharacterBody3D.new();w.add_child(p);p.position=w.definition.entry_position
	var c:=Camera3D.new();w.add_child(c);c.projection=Camera3D.PROJECTION_ORTHOGONAL;c.size=15;c.make_current()
	var director:=Director.new();w.add_child(director);director.configure(w,p,w.definition,stage);director.set_physics_process(false)
	var slots:=0
	for anchor:Dictionary in w.spawn_formation_anchors():slots+=anchor.slots.size()
	print("DOMAIN_BUILD ",d.template_id," usec=",w.spawn_domain_build_usec," anchors=",w.spawn_formation_anchors().size()," slots=",slots)
	return {"world":w,"player":p,"director":director,"camera":c}
func aim(s:Dictionary)->void:
	s.camera.global_position=s.player.global_position+Vector3(15,19,15)
	s.camera.look_at(s.player.global_position,Vector3.UP)
func queue_until(s:Dictionary,seconds:float=30)->bool:
	for tick in ceili(seconds*5):
		var started:=Time.get_ticks_usec()
		s.director._physics_process(.2)
		whole_tick_profile.append(Time.get_ticks_usec()-started)
		profile.append(s.director.metrics().placement_usec_last)
		if s.director.metrics().placement_rank_rebuilt_last:cold_profile.append(s.director.metrics().placement_usec_last)
		else:steady_profile.append(s.director.metrics().placement_usec_last)
		check(s.director.metrics().placement_attempts_last<=4,"bounded four-anchor retry")
		if not s.director._warnings.is_empty():return true
	return false
func freeze(s:Dictionary)->void:
	for enemy in s.director.enemies:
		if is_instance_valid(enemy):enemy.set_physics_process(false)
func run()->void:
	var game:=Game.new();game.test_mode=true;game.save_path="user://qa_domain_doors.json";root.add_child(game)
	await process_frame
	game._start_new_run(5);game._choose_route(str(game.run.data.offers[0]));game._enter_room(str(game.dungeon.main_path[1]))
	game.director.set_physics_process(false)
	var first_side:String=game.world.definition.doors.keys()[0]
	game.player.position=game.world.get_door_position(first_side)+Catalog.door_inward(first_side)
	game.gameplay_time=10;game.last_door_time=0
	var prior_budget:int=game.director.metrics().planned
	var prior_room:String=game.current_room
	game._check_doors()
	check(game.director._force_queue and not game.world.doors_open and game.current_room==prior_room,"inward1m player approach invokes real exit check without crossing locked door")
	check(game.director.metrics().planned==prior_budget and game.director.metrics().spawned==0,"real door exit check preserves all owed actors")
	game.queue_free();await process_frame
	# Actual adjacent-door layout that formerly pointed 12.68m outside its band.
	var adjacent:=scene(definition(0,["north","west"]))
	aim(adjacent)
	await physics_frame;await physics_frame
	var d=adjacent.director;var w=adjacent.world
	check(str(d.metrics().content_error).is_empty(),"actual adjacent-door domain is configured")
	var schedule:Array=d.group_schedule().duplicate(true)
	for si in d.segments.size():
		for gi in d.segments[si].groups.size():
			# Consume earlier entries only in this hint fixture, never production.
			var group:Dictionary=d.segments[si].groups[gi]
			d._refresh_encounter_hint()
			var point:Vector3=d.next_encounter_hint_target()
			check(point.is_finite(),"owed adjacent-door group has reachable progress or door-trigger hint")
			if point.is_finite():
				check(not w.path_to(adjacent.player.position,point).is_empty(),"hint destination has current reachable path")
				if d._hint_kind=="formation":
					check(w.is_in_spawn_domain(point,.34),"formation hint never points outside immutable band")
					check(d._max_progress+.1>=float(group.progress) or d._project_progress(point)+.1>=float(group.progress),"locked formation hint actually reaches unchanged progress gate")
				else:
					var at_trigger:=false
					for side:String in w.definition.doors:
						if point.distance_to(w.get_door_position(side))<1.3:at_trigger=true
					check(at_trigger and not w.doors_open,"fallback is within existing locked-door trigger")
			group.spawned=group.count
			check(d._max_progress==0 and d.metrics().reward_paid==0,"hint never activates progress or rewards")
	# Reconfigure resets every cache and synthetic fixture counter.
	d.configure(w,adjacent.player,w.definition,3);d.set_physics_process(false)
	check(d.group_schedule()==schedule,"hint fixture did not mutate authored schedule")
	adjacent.world.free();await process_frame
	var waiting:=scene(definition(0,["west","east"]))
	waiting.player.position=Vector3(waiting.world.definition.size.x*.75,0,waiting.world.definition.size.y*.83)
	aim(waiting);await physics_frame;await physics_frame
	var owed_before:Dictionary=waiting.director.metrics()
	check(not queue_until(waiting,12),"off-route invisible legal band waits rather than falling back to unrelated field")
	check(waiting.director.metrics().spawned==0 and waiting.director.metrics().reserved==0 and waiting.director.metrics().planned==owed_before.planned,"all budgets remain owed during long placement wait")
	check(str(waiting.director.metrics().content_error).is_empty() and not waiting.director.is_complete(),"off-route wait never becomes fatal content error or fake clear")
	waiting.player.position=waiting.world.definition.entry_position;aim(waiting)
	await physics_frame;await physics_frame
	check(queue_until(waiting),"return from off-route resumes normal full-group warning")
	waiting.world.free();await process_frame
	# Dense first groups at both sides of representative real corridors.
	for fixture:Dictionary in [
		{"template":0,"sides":["north","west"]},
		{"template":2,"sides":["west","east"]},
		{"template":9,"sides":["north","west"]},
		{"template":5,"sides":["north","east","south"]},
		{"template":10,"sides":["north","east","south","west"]},
		{"template":3,"sides":["north","east","south","west"]},
		{"template":6,"sides":["west","east"]}]:
		var template:int=fixture.template
		for arrival:String in fixture.sides:
			var s:=scene(definition(template,fixture.sides))
			s.player.position=s.world.get_door_position(arrival)+Catalog.door_inward(arrival)*4
			aim(s);await physics_frame;await physics_frame
			check(str(s.director.metrics().content_error).is_empty(),"real template domain config %d/%s"%[template,arrival])
			var scheduled:Array=s.director.group_schedule().duplicate(true)
			var reserved:=queue_until(s)
			check(reserved,"actual camera-visible12 warning arrives %d/%s"%[template,arrival])
			if reserved:
				var warning:Dictionary=s.director._warnings[0]
				check(warning.records.size()==12 and is_equal_approx(warning.remaining,.8),"normal full12 warning retains .8 seconds")
				var records:Array=warning.records.duplicate(true)
				var roster:Array=[]
				for record:Dictionary in records:
					roster.append(record.species)
					check(s.world.is_in_spawn_domain(record.point,.34) and s.director._warning_visible(record.point),"actual warnings are visible in legal domain")
				# A newly placed actual prop cancels the entire warning.
				s.world.register_dynamic_obstacle("qa_warning_prop",records[0].point,.4)
				s.director._tick_spawn_warnings(.8)
				check(s.director.metrics().spawned==0 and s.director.metrics().reserved==0,"prop registered during warning refunds all12")
				s.world.remove_dynamic_obstacle("qa_warning_prop")
				check(queue_until(s),"breaking blocking prop retries owed full group")
				if not s.director._warnings.is_empty():
					var retried:Array=[]
					for record:Dictionary in s.director._warnings[0].records:retried.append(record.species)
					check(roster==retried,"cancel/retry keeps exact original roster IDs")
					s.director._tick_spawn_warnings(.8);freeze(s)
					check(s.director.metrics().spawned==12,"full12 actors actually resolve")
					for enemy in s.director.enemies:check(s.world.is_in_spawn_domain(enemy.position,.34),"every actual admitted actor remains in band at birth")
					# Living actors also reject placements without relying on physics sync.
					if s.director.enemies.size()>0:
						check(not s.director._spawn_valid(s.director.enemies[0].position+Vector3(.5,0,0),.34),"actual live actors enforce >=.72 separation")
					# Retain six actual actors, then demand the next full12 opening.
					for index in mini(6,s.director.enemies.size()):s.director.enemies[index].receive_hit(100000,Vector3.RIGHT)
					s.director.request_exit_check()
					await physics_frame;await physics_frame
					check(queue_until(s),"camping corridor with six living actors eventually admits next owed full group")
					if not s.director._warnings.is_empty():
						for record:Dictionary in s.director._warnings[0].records:
							for enemy in s.director.enemies:
								if not enemy.dead:check(record.point.distance_to(enemy.position)>=.71999,"dense next wave cannot clump into living first wave")
			check(s.director.metrics().planned>0 and s.director.metrics().alive_including_warnings<=20,"dense accounting stays under floor3 cap")
			s.world.free();await process_frame
	# Complete every owed real actor and reward at all three density tiers.
	for stage in [1,2,3]:
		var s:=scene(definition(0,["west","east"]),stage)
		aim(s);await physics_frame;await physics_frame
		var planned:int=s.director.metrics().planned
		s.director.request_exit_check()
		for wave in s.director.group_schedule().size()+2:
			if s.director.is_complete():break
			check(queue_until(s),"forced/backtracking corridor drains next full owed group at floor%d"%stage)
			if s.director._warnings.is_empty():break
			s.director._tick_spawn_warnings(.8);freeze(s)
			for enemy in s.director.enemies.duplicate():
				if is_instance_valid(enemy) and not enemy.dead:enemy.receive_hit(100000,Vector3.RIGHT)
			await physics_frame;await physics_frame
		check(s.director.is_complete() and s.world.doors_open,"actual full owed encounter eventually clears normally at floor%d"%stage)
		check(s.director.metrics().spawned==planned and s.director.metrics().defeated==planned,"all promised actors truly spawned and were defeated at floor%d"%stage)
		check(s.director.metrics().reward_paid==s.director.metrics().reward_budget and s.director.metrics().elite_spawned==1,"full fixed reward and sole elite preserved at floor%d"%stage)
		var final_count:int=s.director.metrics().spawned
		s.director.request_exit_check();s.director._physics_process(2.0)
		check(s.director.metrics().spawned==final_count,"cleared-room backtracking never starts another wave")
		s.world.free();await process_frame
	for entry:Dictionary in [{"label":"cold_rank","values":cold_profile},{"label":"steady_rank","values":steady_profile},{"label":"whole_director_tick","values":whole_tick_profile}]:
		entry.values.sort()
		print("PROFILE ",entry.label," samples=",entry.values.size()," median_usec=",entry.values[entry.values.size()/2] if not entry.values.is_empty() else 0," max_usec=",entry.values[-1] if not entry.values.is_empty() else 0)
	profile.sort()
	print("DOOR_RUNTIME checks=%d failures=%d profile_count=%d median_usec=%s max_usec=%s; single-door excluded"%[checks,failures,profile.size(),profile[profile.size()/2] if not profile.is_empty() else 0,profile[-1] if not profile.is_empty() else 0])
	quit(1 if failures else 0)
