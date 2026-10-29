extends SceneTree
## Controlled same-frame host signals; not a legal-input Boss victory attempt.
const Game=preload("res://scripts/cornfield/game.gd")
const Run=preload("res://scripts/cornfield/run_state.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func fixture() -> Node3D:
	var game:=Game.new();game.test_mode=true
	game.save_path="user://simultaneous_terminal_%d.json"%Time.get_ticks_usec()
	root.add_child(game);await process_frame
	game._start_new_run(5);game._choose_route(str(game.run.data.offers[0]))
	game.run.advance_to_node(str(game.run.next_node_offers()[0]),game.run.next_node_offers())
	game.run.advance_to_node("BOSS",["BOSS"])
	game._install_node("BOSS");game._enter_room("entry");game._enter_room("exit")
	game.director.set_physics_process(false)
	return game
func _run() -> void:
	for heal_rank in [0,2]:
		for order in ["clear_first","damage_first"]:
			for save_failure in [false,true]:
				var game:=await fixture()
				game.run.data.global_builds.clear_heal=heal_rank
				var real_path:String=game.run._save_path
				if save_failure:game.run._save_path="res://scripts"
				if order=="clear_first":game._room_cleared();game.player.receive_damage(10000)
				else:game.player.receive_damage(10000);game._room_cleared()
				var label:="%s heal%d diskfail%s"%[order,heal_rank,save_failure]
				check(game.player.hp==0,"clear healing cannot revive fatal hit "+label)
				await process_frame
				if save_failure:
					check(game.run.data.status=="ACTIVE" and game.pending_terminal=="FAILED","failed persistence retains failed outcome for retry "+label)
					check(game.ui.panel_kind=="settlement" and paused,"failed persistence locks play behind recoverable result panel "+label)
					game.run._save_path=real_path
					game._end_run("VICTORY_PENDING_SETTLEMENT") # A stale queued victory cannot win a retry race.
				check(game.run.data.status=="FAILED" and game.run.data.hp==0,"fatal outcome wins either event order "+label)
				check(game.phase=="settlement" and game.ui.panel_kind=="settlement","one terminal panel remains "+label)
				var loaded:=Run.new(real_path)
				check(loaded.load_save() and loaded.data.status=="FAILED" and loaded.data.hp==0,"failed terminal survives reload "+label)
				game._settle()
				check(game.run.data.status=="COMPLETE" and game.run.data.meta==0,"mutual defeat never grants victory meta "+label)
				paused=false;game.queue_free();await process_frame
	var success:=await fixture()
	success._room_cleared();await process_frame
	check(success.run.data.status=="VICTORY_PENDING_SETTLEMENT","ordinary living Boss completion still succeeds")
	success._settle();var meta:int=success.run.data.meta;success._settle()
	check(meta==10 and success.run.data.meta==10,"ordinary victory meta remains exactly once")
	paused=false;success.queue_free();await process_frame
	print("CORNFIELDS_SIMULTANEOUS_TERMINAL %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
