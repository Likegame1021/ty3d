extends SceneTree
const Run=preload("res://scripts/cornfield/run_state.gd")
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL: ",label)
func write_record(path:String,record:Dictionary) -> void:
	write_text(path,JSON.stringify(record))
func write_text(path:String,value:String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value);file.close()
func _run() -> void:
	var prefix:="user://qa_save_recovery_%d"%Time.get_ticks_usec()
	var path:=prefix+".json"
	var run:=Run.new(path)
	check(run.new_run(730027),"recovery fixture run created")
	check(run.choose_route(str(run.data.offers[0])),"recovery fixture route committed")
	var old_text:=FileAccess.get_file_as_string(path)
	check(run.end_run("FAILED"),"recovery fixture terminal committed")
	var terminal:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	write_text(path,old_text) # Crash after new backup rename but before primary rename.
	var recovery:=Run.new(path)
	check(recovery.load_save() and recovery.data.status=="FAILED","newest durable mirror wins over valid older primary")
	var damaged:=terminal.duplicate(true)
	damaged.terminal.erase("seed")
	write_record(prefix+".missing",damaged)
	check(not Run.new(prefix+".missing").load_save(),"missing terminal field rejects without script error")
	for section in ["baseline","terminal"]:
		var missing_weapon:=terminal.duplicate(true)
		missing_weapon[section].erase("weapon")
		var missing_path:String=prefix+".missing_weapon_"+section
		write_record(missing_path,missing_weapon)
		check(not Run.new(missing_path).load_save(),"v2 missing weapon rejects safely in "+section)
	var mismatch:=terminal.duplicate(true)
	mismatch.terminal={}
	mismatch.baseline.toolheaps["1"].weapon_id="corn"
	mismatch.baseline.toolheaps["1"].candidate_id="damage"
	write_record(prefix+".mismatch",mismatch)
	check(not Run.new(prefix+".mismatch").load_save(),"current heap weapon must match run weapon")
	var invalid_original:="{malformed current save; preserve bytes}"
	write_text(path,invalid_original)
	var game:=Game.new()
	game.test_mode=true
	game.save_path=path
	root.add_child(game)
	await process_frame
	check(game.run.data.status=="FAILED","valid terminal backup remains usable after corrupt primary")
	check(not game.recovered_save_paths.is_empty(),"backup recovery preserves invalid primary")
	var recovery_path:String=game.recovered_save_paths[0] if not game.recovered_save_paths.is_empty() else ""
	if not recovery_path.is_empty():
		check(FileAccess.get_file_as_string(recovery_path)==invalid_original,"recovery copy contains exact original bytes")
		check(game.run.save(),"valid recovered state can save after preservation")
		check(FileAccess.get_file_as_string(recovery_path)==invalid_original,"next save cannot overwrite recovery evidence")
	paused=false
	game.queue_free()
	await process_frame
	print("CORNFIELDS_SAVE_RECOVERY %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
