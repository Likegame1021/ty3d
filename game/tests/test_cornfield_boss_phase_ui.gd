extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	if not value:failures+=1;printerr("FAIL: ",label)
func _run() -> void:
	var game:=Game.new()
	game.test_mode=true
	game.save_path="user://qa_boss_ui_%d.json"%Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	check(game.has_method("_boss_status"),"Boss phase is connected to readable UI")
	if game.has_method("_boss_status"):
		game._boss_status({"title":"巨型玉米螟","hp":620,"max_hp":620,"stage":1})
		check(game.ui.boss_name.text.contains("第一阶段"),"first phase identified")
		game._boss_status({"title":"巨型玉米螟","hp":280,"max_hp":620,"stage":2})
		check(game.ui.boss_name.text.contains("第二阶段") and game.ui.notice.text.contains("连冲"),"phase change explains changed danger without blocking controls")
		game.ui.notice_time=1.0
		game._boss_status({"title":"巨型玉米螟","hp":260,"max_hp":620,"stage":2})
		check(game.ui.notice_time==1.0,"repeated damage status does not spam transition toast")
		game._boss_status({})
		check(not game.ui.boss_panel.visible,"defeat clears phase HUD")
	game.queue_free()
	await process_frame
	print("CORNFIELDS_BOSS_PHASE_UI %d failures"%failures)
	quit(1 if failures else 0)
