extends SceneTree
const Run = preload("res://scripts/cornfield/run_state.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func _run() -> void:
	var path := "user://qa_build_save_%d.json" % Time.get_ticks_usec()
	var run := Run.new(path)
	check(run.new_run(730027,"stick"),"new run persists")
	check(run.data.has("dice") and run.data.get("dice",-1)==2,"new run starts with two dice")
	check(run.data.has("toolheaps"),"new run snapshots first guaranteed heap")
	if not run.data.has("toolheaps") or run.data.run_id.is_empty():
		_finish()
		return
	var original := run.data.duplicate(true)
	check(run.data.toolheaps.has("1"),"node one candidate is created before checkpoint")
	check(run.has_method("act_on_toolheap"),"save owns heap transaction interface")
	if not run.has_method("act_on_toolheap"):
		_finish()
		return
	check(run.choose_route(str(run.data.offers[0])),"route commits")
	var candidate: String = run.data.toolheaps["1"].candidate_id
	var action: Dictionary = run.act_on_toolheap("reroll")
	check(action.ok and run.data.dice==1,"reroll spends exactly one live die")
	check(run.data.toolheaps["1"].candidate_id!=candidate,"legal alternative excludes original")
	check(run.act_on_toolheap("accept").ok,"accept candidate")
	var accepted := run.data.duplicate(true)
	check(not run.act_on_toolheap("accept").ok and run.data==accepted,"repeat accept leaves state unchanged")
	check(run.save(),"live resources can save timing without advancing entry baseline")
	var loaded := Run.new(path)
	check(loaded.load_save(),"active save reloads")
	check(loaded.data.dice==2 and loaded.data.toolheaps==original.toolheaps,"continue restores dice and same entry candidate")
	check(loaded.data.builds_by_weapon==original.builds_by_weapon,"entry rollback removes live upgrades")
	check(run.advance_to_node(str(run.next_node_offers()[0]),run.next_node_offers()),"advance commits build and next heap")
	check(run.data.floor==2 and run.data.toolheaps.has("2"),"node two has guaranteed candidate")
	check(run.data.builds_by_weapon==accepted.builds_by_weapon,"acquired weapon upgrades carried to node two")
	loaded = Run.new(path)
	check(loaded.load_save() and loaded.data.dice==1 and loaded.data.toolheaps==run.data.toolheaps,"node two checkpoint preserves exact dice heap cursor")
	var before := run.data.duplicate(true)
	var save_path: String = run._save_path
	run._save_path = "res://scripts"
	check(not run.advance_to_node("BOSS",["BOSS"]) and run.data==before,"failed destination write restores all builds dice and heaps")
	run._save_path = save_path
	check(run.end_run("FAILED"),"terminal state persists")
	loaded = Run.new(path)
	check(loaded.load_save() and loaded.data.status=="FAILED" and loaded.data.dice==1,"terminal reload preserves live resources without resurrection")
	# A v1 fixture migrates its old tier to one legacy additive bonus, never two.
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	record.version = 1
	for section in ["baseline","terminal"]:
		record[section].tier = 2
		for key in ["builds_by_weapon","global_builds","dice","toolheaps","legacy_damage_bonus","content_revision"]:
			record[section].erase(key)
	var legacy_path := path+".legacy"
	_write(legacy_path,record)
	var legacy := Run.new(legacy_path)
	check(legacy.load_save() and is_equal_approx(legacy.data.legacy_damage_bonus,0.7),"legacy tier migrates once")
	check(legacy.data.status=="FAILED","old terminal cannot resurrect")
	check(legacy.save(),"migrated save writes current version")
	var migrated := Run.new(legacy_path)
	check(migrated.load_save() and is_equal_approx(migrated.data.legacy_damage_bonus,0.7),"second migration never doubles legacy bonus")
	var corrupt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	corrupt.baseline.builds_by_weapon.stick.damage = 3
	var corrupt_path := path+".corrupt"
	_write(corrupt_path,corrupt)
	var invalid := Run.new(corrupt_path)
	check(not invalid.load_save(),"out of range build rank rejects unsafe record")
	check(FileAccess.get_file_as_string(corrupt_path)==JSON.stringify(corrupt),"invalid original is not overwritten")
	# Version-one records must not smuggle malformed modern fields past validation.
	var old_bad := record.duplicate(true)
	old_bad.baseline.builds_by_weapon = "not-a-dictionary"
	var old_bad_path := path+".oldbad"
	_write(old_bad_path,old_bad)
	check(not Run.new(old_bad_path).load_save(),"malformed modern field in old-version record is rejected safely")
	var high_seed := Run.new(path+".highseed")
	check(high_seed.new_run(4294967295,"corn"),"unsigned32-bit seed writes normalized heap seed")
	var high_loaded := Run.new(path+".highseed")
	check(high_loaded.load_save() and high_loaded.data.toolheaps==high_seed.data.toolheaps,"large seed restores exact heap candidate and cursor")
	_finish()
func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
func _finish() -> void:
	print("CORNFIELDS_BUILD_SAVE %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
