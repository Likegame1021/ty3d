extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func _run() -> void:
	var path := "res://scripts/cornfield/combat_feedback.gd"
	check(ResourceLoader.exists(path),"dedicated event feedback component exists")
	if not ResourceLoader.exists(path):
		_finish()
		return
	var feedback = load(path).new()
	root.add_child(feedback)
	await process_frame
	for kind in ["slash","hit","hurt","defeat","pickup","upgrade","boss_phase"]:
		feedback.emit_feedback(kind,{"position":Vector3.ZERO,"direction":Vector3.FORWARD,"strength":1.0})
	check(feedback.active_count()==7,"all seven feedback events produce decoration")
	for index in 90:
		feedback.emit_feedback("hit",{"position":Vector3.ZERO,"direction":Vector3.RIGHT,"strength":1.0})
	check(feedback.active_count()<=30,"burst obeys 30-decoration hard cap")
	var snapshot: Array = feedback.lifetime_snapshot()
	paused = true
	feedback._process(1.0)
	check(feedback.lifetime_snapshot()==snapshot,"pause freezes all lifetimes")
	paused = false
	feedback.emit_feedback("hit",{"position":Vector3(INF,0,0)})
	feedback.emit_feedback("unknown",{})
	check(feedback.active_count()<=30,"invalid positions and unknown events do not leak")
	var victim := Node3D.new()
	root.add_child(victim)
	victim.free()
	feedback.emit_feedback("hit",{"target":victim})
	feedback._process(2.0)
	check(feedback.active_count()==0,"expired feedback returns to pool")
	feedback.emit_feedback("boss_phase",{"position":Vector3.ZERO,"strength":2.0})
	feedback.clear_all()
	check(feedback.active_count()==0,"room clear removes every live effect")
	check(feedback.get_children().all(func(child):return not child is CollisionObject3D),"decoration owns no damage collision")
	feedback.queue_free()
	await process_frame
	_finish()
func _finish() -> void:
	print("CORNFIELDS_FEEDBACK %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
