extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run_checks")
func check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func run_checks() -> void:
	var input_setup = load("res://scripts/main.gd").new()
	input_setup.setup_input()
	input_setup.free()
	var p = load("res://scripts/cornfield/player.gd").new()
	root.add_child(p)
	p.set_physics_process(false)
	var cam := Camera3D.new()
	root.add_child(cam)
	p.configure(cam,"stick")
	check(is_equal_approx(p.attack_reach,1.35),"original target branch reach preserved")
	check(p.has_real_model,"original target GLB boy loads")
	check(p.receive_damage(10,Vector3.RIGHT),"chapter receives enemy damage")
	check(is_equal_approx(p.hp,90),"damage decreases health once")
	check(not p.receive_damage(10,Vector3.RIGHT),"hurt grace prevents instant repeated contact")
	p.heal(100)
	check(is_equal_approx(p.hp,100),"healing clamps to maximum")
	p.configure(cam,"corn")
	check(p.ranged_stance,"corn uses existing ranged stance")
	p.queue_free()
	cam.queue_free()
	await process_frame
	print("CORNFIELDS_PLAYER: %d failures" % failures)
	quit(1 if failures else 0)
