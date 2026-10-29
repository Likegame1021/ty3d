extends SceneTree
## Actual Game menu/focus/terminal-save-retry paths with automatic player clocks.
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:=0
var events:Array=[]
var output:=""
var variant:="candidate"
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.split("=",true,1)
		if pair.size()==2:
			if pair[0]=="out":output=pair[1]
			if pair[0]=="variant":variant=pair[1]
	call_deferred("run_checks")
func check(ok:bool,description:String) -> void:
	checks+=1
	events.append({"ok":ok,"description":description})
	if not ok:failures+=1;printerr("FAIL: ",description)
func clear(p,label:String) -> void:
	check(p.attack.remaining==0 and p.context_remaining==0 and p.pending_context_action=="",label+" removes action authority and pending reaction")
	if p.get("_queued_hurt_expiry")!=null:check(p._queued_hurt_expiry<0,label+" removes queued expiry")
func wait_ticks(count:int) -> void:
	for ignored in count:await physics_frame
func arm(p,label:String) -> void:
	await wait_ticks(42)
	p.request_attack();await wait_ticks(78)
	check(p.receive_damage(7),label+" naturally accepted late hit")
	check(p.pending_context_action=="hurt" and p.attack.remaining>0,label+" arms committed queue")
func restart(p,label:String) -> void:
	p.request_attack()
	await wait_ticks(1)
	check(p.attack.elapsed>0 and p.attack.elapsed<.04,label+" restart attack begins from its original clock")
	check(p.animation_player.current_animation_position<.04,label+" restart actual animation begins near zero")
	await wait_ticks(94)
	check(p.pending_context_action=="" and p.context_action!="hurt",label+" cancelled queue cannot reappear after restarted attack")
func run_checks() -> void:
	var game=Game.new();game.test_mode=true;game.save_path="user://qa_aged_game_%d.json"%Time.get_ticks_usec();root.add_child(game)
	await process_frame
	game.set_process(false)
	# Actual run transaction, then stay in clear village geometry. No enemies are
	# spawned: this fixture owns lifecycle transitions, not encounter behavior.
	check(game._start_new_run(92177),"actual run transaction succeeds")
	game._close_panel()
	await arm(game.player,"menu")
	game._show_pause()
	check(paused and game.ui.panel_kind=="pause" and not game.player.controls_enabled,"production menu pauses and disables controls")
	clear(game.player,"menu _refresh_pause")
	var frozen:Array=game.player.cancel_pose.read_pose()
	await wait_ticks(8)
	check(game.player.cancel_pose.read_pose()==frozen,"menu preserves actual frozen pose")
	game._close_panel();check(not paused and game.player.controls_enabled,"menu close restores controls")
	await restart(game.player,"menu")
	await arm(game.player,"focus")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(paused and not game.focused and not game.player.controls_enabled,"production focus loss pauses and disables controls")
	clear(game.player,"focus _refresh_pause")
	await wait_ticks(8)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not paused and game.focused and game.player.controls_enabled,"production focus regain restores controls")
	await restart(game.player,"focus")
	await arm(game.player,"reset")
	game.player.reset_player();clear(game.player,"actual player reset")
	check(not game.player.cancel_pose.bridge_active,"reset clears cancellation bridge")
	await restart(game.player,"reset")
	# Terminal persistence deliberately fails on a directory inside the isolated
	# user data area, not on a protected/product path.
	await wait_ticks(42)
	game.player.request_attack();await wait_ticks(78)
	var real_path:String=game.run._save_path
	var directory:="user://qa_blocked_save"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	game.run._save_path=directory
	check(game.player.receive_damage(200),"lethal queued hit is accepted")
	await process_frame;await process_frame
	check(game.pending_terminal=="FAILED" and game.run.data.status=="ACTIVE","failed terminal persistence retains pending FAILED outcome")
	check(paused and game.ui.panel_kind=="settlement","production _end_run failure displays blocking retry settlement")
	clear(game.player,"failed death-save panel")
	game.run._save_path=real_path
	game._end_run("FAILED")
	check(game.run.data.status=="FAILED" and game.pending_terminal=="" and game.phase=="settlement","production retry commits original failed result")
	clear(game.player,"successful terminal retry")
	game._settle()
	check(game.phase=="village" and not paused and game.player.hp==100,"production settlement returns fresh playable village actor")
	clear(game.player,"post-settlement actor")
	check(game._start_new_run(92178),"retry new run uses normal run transaction")
	game._close_panel();await wait_ticks(2);await restart(game.player,"new run after death")
	paused=false;game.queue_free();await process_frame
	var report:={"variant":variant,"checks":checks,"failures":failures,"events":events,"game_sha256":FileAccess.get_sha256("res://scripts/cornfield/game.gd"),"player_sha256":FileAccess.get_sha256("res://scripts/cornfield/player.gd")}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join(variant+"-lifecycle.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AGED_HURT_GAME_LIFECYCLE %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
