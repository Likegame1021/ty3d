extends SceneTree
const Director=preload("res://scripts/cornfield/encounter_director.gd")
const Recipe=preload("res://scripts/cornfield/encounter_recipe.gd")
const Fixtures=preload("res://tests/test_cornfield_encounters.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func definition(revision:int=3,elite:bool=false,boss:bool=false) -> Dictionary:
	return {"id":"recipe_fixture","content_revision":revision,"kind":"boss" if boss else "combat","encounter":"boss" if boss else "combat","elite":elite,"completion":boss,"species":["locust","snail"],"melee_fallback":"beetle","size":Vector2(64,48),"doors":{"east":"exit"},"entry_position":Vector3(5,0,24),"main_route":PackedVector3Array([Vector3(5,0,24),Vector3(20,0,24),Vector3(40,0,24),Vector3(60,0,24)])}
func fixture(data:Dictionary,stage:int=1,script:Script=Director) -> Dictionary:
	var world:=Fixtures.TestWorld.new();root.add_child(world)
	var player:=Fixtures.TestPlayer.new();world.add_child(player);player.position=Vector3(5,0,24)
	var director:Node3D=script.new();world.add_child(director)
	var errors:Array=[]
	if director.has_signal("encounter_error"):director.connect("encounter_error",func(reason:String):errors.append(reason))
	director.configure(world,player,data,stage);director.set_physics_process(false);director.set_process(false)
	return {"world":world,"player":player,"director":director,"errors":errors}
func release(scene:Dictionary) -> void:
	scene.world.queue_free();await process_frame
func roster_of(records:Array) -> Array:
	var result:Array=[]
	for record in records:result.append(record.species)
	return result
func spawn_warning(director:Node3D) -> void:
	director._tick_spawn_warnings(.81)
	for enemy in director.enemies:enemy.set_physics_process(false)
func _run() -> void:
	# Exact old code is the oracle for actual revision-2 allocations and budgets.
	var old_script:=GDScript.new();old_script.source_code=FileAccess.get_file_as_string("res://../docs/qa/sprint-10h/level-revision/director-before-task5.gd.txt")
	check(old_script.reload()==OK,"preserved legacy director compiles")
	for stage in [1,2,3]:
		var scene:=fixture(definition(3,false),stage);var d:Node3D=scene.director
		check(d.has_signal("encounter_error"),"director exposes bounded content failure")
		for si in d.segments.size():
			for gi in d.segments[si].groups.size():
				var group:Dictionary=d.segments[si].groups[gi]
				check(group.get("roster",[])==Recipe.roster(d.definition,stage,si,gi,int(group.count),false),"stable cached authored roster %d/%d/%d"%[stage,si,gi])
		d._activate(d.segments[0]);d._queue_group(0,.01)
		check(d._warnings.size()==1,"first authored group reserves one warning")
		if not d._warnings.is_empty():
			check(roster_of(d._warnings[0].records)==Recipe.roster(d.definition,stage,0,0,d.group_size,false),"actual reservation uses authored species")
			spawn_warning(d)
			var actual:Array=[]
			for enemy in d.enemies:actual.append(enemy.species)
			check(actual==Recipe.roster(d.definition,stage,0,0,d.group_size,false),"actual enemies use same roster")
		await release(scene)
		var legacy:=fixture(definition(2,true),stage,old_script)
		var current:=fixture(definition(2,true),stage)
		for si in legacy.director.segments.size():
			for spawned in [0,8,17]:
				legacy.director._spawned=spawned;current.director._spawned=spawned
				legacy.director._elite_assigned=false;current.director._elite_assigned=false
				var a:Array=legacy.director._find_group(legacy.director.group_size,si)
				var b:Array=current.director._find_group(current.director.group_size,si)
				check(a==b,"revision2 preserves exact species/elite/position %d/%d/%d"%[stage,si,spawned])
		check(legacy.director.metrics().planned==current.director.metrics().planned and legacy.director.metrics().reward_budget==current.director.metrics().reward_budget,"legacy budget and coin contract unchanged")
		await release(legacy);await release(current)
	# Cancel the teaching warning, allow another segment first, then retry it.
	var scene:=fixture(definition(3,true));var d:Node3D=scene.director
	d.request_exit_check();d._queue_group(0,.01)
	var original:Array=d._warnings[0].records.duplicate(true)
	check(roster_of(original)==Recipe.INTRO_ROSTER and original.filter(func(r):return r.elite).size()==1 and original[0].elite,"fixed eight-member teaching group owns exactly one beetle elite")
	scene.world.blocked=true;spawn_warning(d);scene.world.blocked=false
	check(d._warnings.is_empty() and d.enemies.is_empty() and d.segments[0].groups[0].spawned==0,"invalid warning returns reservation without consuming roster")
	d._queue_group(1,.01)
	check(not d._warnings.is_empty() and d._warnings[0].records.filter(func(r):return r.elite).is_empty(),"other segment cannot steal teaching elite after cancellation")
	spawn_warning(d)
	for enemy in d.enemies:enemy.receive_hit(100000,Vector3.RIGHT)
	d._queue_group(0,.01)
	check(not d._warnings.is_empty() and roster_of(d._warnings[0].records)==Recipe.INTRO_ROSTER and d._warnings[0].records[0].elite,"retry retains original teaching species and elite slot")
	spawn_warning(d)
	check(d.metrics().elite_spawned==1,"only original teaching elite spawns")
	await release(scene)
	for invalid in ["empty","unknown","missing_fallback"]:
		var data:=definition()
		match invalid:
			"empty":data.species=[]
			"unknown":data.species=["invalid"]
			"missing_fallback":data.erase("melee_fallback")
		scene=fixture(data);d=scene.director
		for i in 12:d._physics_process(.81);d.request_exit_check()
		check(scene.errors.size()==1 and not str(scene.errors[0]).is_empty(),"one explicit content error "+invalid)
		check(d.enemies.is_empty() and d._warnings.is_empty() and d.metrics().reward_paid==0 and not d.is_complete() and not scene.world.doors_open,"bad content neither spawns nor awards/fakes clear "+invalid)
		await release(scene)
	var boss:=definition(3,false,true);boss.species=[];boss.erase("melee_fallback")
	scene=fixture(boss,3);d=scene.director;d._activate(d.segments[0]);d._queue_group(0,.01)
	check(scene.errors.is_empty() and d.metrics().planned==1 and d._warnings.size()==1 and roster_of(d._warnings[0].records)==["boss_borer"],"Boss bypasses ordinary recipes and keeps single budget")
	await release(scene)
	print("CORNFIELDS_RECIPE_INTEGRATION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
