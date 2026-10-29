extends SceneTree
const Run=preload("res://scripts/cornfield/run_state.gd")
const Dungeon=preload("res://scripts/cornfield/dungeon.gd")
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:=0
var supports_revision:=false
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:
		failures+=1
		if failures<=25:printerr("FAIL: ",label)
func write_record(path:String,record:Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(record));file.close()
func generate(seed_value:int,floor_number:int,node:String,revision:int) -> Dictionary:
	var script:Variant=Dungeon
	return script.generate(seed_value,floor_number,node,revision) if supports_revision else script.generate(seed_value,floor_number,node)
func signature(d:Dictionary) -> String:
	var ordered:Array=[];var ids:Array=d.rooms.keys();ids.sort()
	for id in ids:
		var r:Dictionary=d.rooms[id];var door_keys:Array=r.doors.keys();door_keys.sort();var doors:Array=[]
		for side in door_keys:doors.append([side,r.doors[side]])
		ordered.append([id,r.template_id,str(r.grid),doors,r.get("branch_depth",0),r.kind,r.encounter,r.elite,r.get("has_toolheap",false)])
	return JSON.stringify([d.main_path,d.links,ordered]).sha256_text()
func reachable_without_elite(d:Dictionary) -> bool:
	var seen:={"entry":true};var queue:Array[String]=["entry"]
	while not queue.is_empty():
		var at:String=queue.pop_front()
		for next:String in d.rooms[at].doors.values():
			if next=="fight_1" or seen.has(next):continue
			seen[next]=true;queue.append(next)
	return seen.has("optional_0")
func _run() -> void:
	var script:Script=Dungeon
	for method in script.get_script_method_list():
		if method.name=="generate":supports_revision=method.args.size()==4
	check(supports_revision,"Dungeon exposes explicit content revision without breaking three-argument callers")
	var gold_path:="res://../docs/qa/sprint-10h/level-revision/legacy-graph-signatures.json"
	check(FileAccess.file_exists(gold_path),"preserved13000legacy graph signatures are packaged")
	if FileAccess.file_exists(gold_path):
		var gold:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(gold_path))
		check(gold.size()==13000,"gold signatures include all early node types plus Boss")
		for key:String in gold:
			var pieces:=key.split(":");var seed_value:=int(pieces[0]);var floor_number:=int(pieces[1]);var node:=pieces[2]
			var old:=generate(seed_value,floor_number,node,2)
			check(signature(old)==gold[key],"revision2graph parity "+key)
			var current:=generate(seed_value,floor_number,node,3)
			check(current.get("content_revision",-1)==3,"new graph stamps revision "+key)
			check(current.rooms.size()>=5 and current.rooms.size()<=8 and current.main_path.size()>=3 and current.main_path.size()<=5,"room/main budgets retained "+key)
			if floor_number<=2:
				check(reachable_without_elite(current),"optional preparation reachable before mandatory elite "+key)
				check(current.rooms.optional_0.get("has_toolheap",false),"guaranteed preparation is the original single-candidate heap "+key)
			for room in current.rooms.values():
				check(room.get("content_revision",-1)==3 and room.get("melee_fallback","")=="beetle","room recipe metadata explicit "+key)
	var path:="user://content_revision_%d.json"%Time.get_ticks_usec()
	var run:=Run.new(path);check(run.new_run(5),"new revision fixture persists")
	check(run.data.get("content_revision",-1)==3 and run._baseline.get("content_revision",-1)==3,"new run and baseline select revision3")
	check(run.choose_route(str(run.data.offers[0])),"fixture route persists")
	var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var legacy:=record.duplicate(true);legacy.baseline.erase("content_revision")
	write_record(path+".old",legacy)
	var old:=Run.new(path+".old");check(old.load_save() and old.data.get("content_revision",-1)==2,"missing old field normalizes to revision2")
	check(old.save() and old.data.get("content_revision",-1)==2,"saving old checkpoint never silently upgrades content")
	var before:=old.data.duplicate(true);var real_path:String=old._save_path;old._save_path="res://scripts"
	check(not old.advance_to_node(str(old.next_node_offers()[0]),old.next_node_offers()) and old.data==before,"failed advance restores old content revision and resources")
	old._save_path=real_path
	check(old.advance_to_node(str(old.next_node_offers()[0]),old.next_node_offers()) and old.data.get("content_revision",-1)==2,"successful old run advance preserves revision2")
	for value in [1,4,"3",3.5,true,null]:
		var bad:=record.duplicate(true);bad.baseline.content_revision=value
		var bad_path:=path+".invalid_"+str(value);write_record(bad_path,bad)
		var bytes:=FileAccess.get_file_as_bytes(bad_path)
		check(not Run.new(bad_path).load_save(),"invalid content revision safely rejects "+str(value))
		check(FileAccess.get_file_as_bytes(bad_path)==bytes,"invalid content record is preserved")
	check(run.end_run("FAILED"),"terminal fixture persists")
	var terminal:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	for pair in [[2,3],[3,2],[-1,3],[3,-1]]:
		var bad:=terminal.duplicate(true)
		if pair[0]<0:bad.baseline.erase("content_revision")
		else:bad.baseline.content_revision=pair[0]
		if pair[1]<0:bad.terminal.erase("content_revision")
		else:bad.terminal.content_revision=pair[1]
		var bad_path:=path+".mismatch_"+str(pair);write_record(bad_path,bad)
		check(not Run.new(bad_path).load_save(),"baseline terminal content consistency "+str(pair))
	var v1:=legacy.duplicate(true);v1.version=1
	for key in ["builds_by_weapon","global_builds","dice","toolheaps","legacy_damage_bonus"]:v1.baseline.erase(key)
	write_record(path+".v1",v1)
	var migrated:=Run.new(path+".v1")
	check(migrated.load_save() and migrated.data.get("content_revision",-1)==2,"official v1 content normalizes to revision2")
	v1.baseline.content_revision=3;write_record(path+".v1mixed",v1)
	check(not Run.new(path+".v1mixed").load_save(),"v1 cannot smuggle modern content revision")
	var game:=Game.new();game.test_mode=true;game.save_path=path+".old";root.add_child(game);await process_frame
	game._continue_run()
	check(game.dungeon.get("content_revision",-1)==2,"continued game actually installs old graph revision")
	for preview in game._preview_offers(2,["ANVIL","LEVEL","SHOP"]):
		check(preview.rooms.entry.get("content_revision",-1)==2,"route preview uses same content revision as installation")
	paused=false;game.queue_free();await process_frame
	print("CORNFIELDS_CONTENT_REVISION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
