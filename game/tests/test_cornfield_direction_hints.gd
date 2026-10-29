extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
const Enemy=preload("res://scripts/cornfield/field_enemy.gd")
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func _run() -> void:
	var game:=Game.new()
	game.test_mode=true
	game.save_path="user://qa_hint_%d.json"%Time.get_ticks_usec()
	root.add_child(game)
	await process_frame
	game._start_new_run(5)
	game._choose_route(str(game.run.data.offers[0]))
	game._enter_room(str(game.dungeon.main_path[1]))
	check(game.has_method("_combat_hint"),"combat HUD supplies remaining-threat direction")
	if game.has_method("_combat_hint"):
		game.director.set_physics_process(false)
		var enemy:=Enemy.new()
		game.director.add_child(enemy)
		enemy.configure(game.world,game.player,"beetle")
		enemy.set_physics_process(false)
		enemy.position=game.player.position+Vector3(6,0,-6)
		game.director.enemies.append(enemy)
		var message:String=game._combat_hint()
		check(message.contains("1") and message.contains("右") and message.contains("米"),"last live target is located in screen direction and distance")
		enemy.dead=true
		message=game._combat_hint()
		check(not message.contains("场上 0") and not message.contains("清场了"),"empty room with owed waves prompts progress instead of false completion")
	paused=false
	game.queue_free()
	await process_frame
	print("CORNFIELDS_DIRECTION_HINTS %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
