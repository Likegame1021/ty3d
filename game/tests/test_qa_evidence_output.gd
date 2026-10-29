extends SceneTree
## Cold developer packages contain inputs, not pre-created QA output folders.
const HANDOVER = preload("res://tests/test_attack_recovery_handover.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run_checks")
func run_checks() -> void:
	var base := "user://qa-evidence-output-%d" % Time.get_ticks_usec()
	var target := base + "/missing/nested/summary.json"
	var contents := "{\"checks\":195,\"failures\":0}"
	check(not DirAccess.dir_exists_absolute(target.get_base_dir()), "cold output directory is genuinely absent")
	check(HANDOVER.write_evidence(target, contents) == OK, "writer creates missing parent directories")
	check(FileAccess.file_exists(target), "cold output file exists after successful write")
	if FileAccess.file_exists(target):
		check(FileAccess.get_file_as_string(target) == contents, "written evidence bytes are unchanged")
	else:
		check(false, "written evidence bytes are unchanged")
	var blocked := base + "/directory-not-a-file"
	check(DirAccess.make_dir_recursive_absolute(blocked) == OK, "file-open failure fixture is a directory")
	check(HANDOVER.write_evidence(blocked, contents) != OK, "file-open failure returns an error instead of dereferencing null")
	check(DirAccess.dir_exists_absolute(blocked), "failed writer preserves the existing directory")
	var parent_file := base + "/parent-is-a-file"
	var file := FileAccess.open(parent_file, FileAccess.WRITE)
	file.store_string("preserve");file.close()
	check(HANDOVER.write_evidence(parent_file + "/child.json", contents) != OK, "parent-creation failure returns an error")
	check(FileAccess.get_file_as_string(parent_file) == "preserve", "failed writer preserves conflicting existing file bytes")
	print("QA_EVIDENCE_OUTPUT %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
