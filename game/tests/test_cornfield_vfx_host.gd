extends SceneTree
## Real chapter pause, death and room replacement must clear decoration before
## the tree stops processing. This is intentionally separate from pool tests.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run_checks")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func run_checks() -> void:
	var host = load("res://scripts/cornfield/game.gd").new()
	host.test_mode = true
	host.save_path = "user://vfx_host_%d.json" % Time.get_ticks_usec()
	root.add_child(host)
	host._start_new_run(730027)
	host._choose_route(str(host.run.data.offers[0]))
	await physics_frame
	await process_frame
	host.feedback.emit_feedback("hit",{"position":host.player.global_position})
	check(host.feedback.active_count()==1,"actual chapter receives local hit decoration")
	host._show_pause()
	check(paused and host.feedback.active_count()==0,"opening pause clears combat decoration before freezing the tree")
	host._close_panel()
	await process_frame
	check(host.feedback.active_count()==0,"resume never resurrects pre-pause decoration")
	host.feedback.emit_feedback("defeat",{"position":host.player.global_position})
	host.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(host.feedback.active_count()==0,"focus loss clears incomplete effects synchronously")
	host.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.feedback.emit_feedback("hit",{"position":host.player.global_position})
	host.player.hurt_cooldown=0.0
	host.player.receive_damage(10000.0)
	check(host.feedback.active_count()==0,"player death clears both the old burst and same-frame hurt feedback")
	await process_frame
	await process_frame
	check(host.phase=="settlement","effect cleanup preserves normal death settlement")
	paused=false
	var old_feedback = host.feedback
	host.set_process(false)
	host._clear_space()
	check(not old_feedback.is_inside_tree(),"room replacement detaches all VFX before the next frame")
	host.queue_free()
	await process_frame
	await process_frame
	print("CORNFIELDS_VFX_HOST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
