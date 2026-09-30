extends "res://tests/test_input.gd"

# Input regression for the corn gun. Shot observations come from the same event
# that drives product feedback; damage is checked against real game actors.
class CountedMinion extends "res://scripts/full_minion.gd":
	signal hit_observed
	func receive_hit(direction: Vector3) -> void:
		hit_observed.emit()
		super.receive_hit(direction)

var shots: Array[Dictionary] = []
var pointer := Vector2.ZERO

func observe_shot(charged: bool) -> void:
	shots.append({"charged": charged, "frame": Engine.get_physics_frames()})

func wait_seconds(seconds: float) -> void:
	for frame in ceili(seconds * Engine.physics_ticks_per_second):
		await physics_frame
	await process_frame

func mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = pointer
	event.global_position = pointer
	event.pressed = pressed
	Input.parse_input_event(event)

func aim_at(game: Node, point: Vector3) -> void:
	pointer = root.get_final_transform() * game.camera.unproject_position(point)
	var event := InputEventMouseMotion.new()
	event.position = pointer
	event.global_position = pointer
	Input.parse_input_event(event)
	await process_frame
	await physics_frame

func prepare_gun(game: Node) -> void:
	# Use the adventure progression API to prepare a legal equipped-gun fixture.
	# The behaviors under test below always use viewport Input events.
	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	game.reset_run()
	game.progress.see_chicken()
	game.progress.take_tin()
	game.progress.clear_mouth()
	game.progress.open_canal()
	game.progress.enter_dense()
	game.progress.take_board()
	game.progress.move_cart()
	game.progress.take_launcher()
	game.progress.enter_boss()
	game.progress.hurt_boss(6)
	game.progress.make_corn_gun()
	game.progress.boss_hp = game.progress.max_boss_hp
	game.boss.active = true
	game.boss.mode = "recover"
	game.boss.phase_remaining = 1000.0
	game.boss.hit_cooldown = 0.0
	game.boss.position = Vector3(0, 0, -34)
	game.player.position = Vector3(0, 0.05, -30)
	game.player.facing = Vector3.FORWARD
	game.sync_environment()
	game.update_camera(1.0)
	await tap_key(KEY_Q)
	await wait_seconds(0.20)
	await aim_at(game, Vector3(0, 0.05, -34))
	shots.clear()

func check_no_late_shot(before: int, description: String) -> void:
	await wait_seconds(0.45)
	check(shots.size() == before, description)

func run_checks() -> void:
	root.size = Vector2i(960, 600)
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await wait_seconds(0.10)
	if not game.has_signal("shot_fired"):
		check(false, "corn gun exposes the shot event used by product feedback")
		game.queue_free()
		await process_frame
		print("Corn gun input: %d failures" % failures)
		quit(1)
		return
	game.connect("shot_fired", observe_shot)
	var retry_clicks := [0]
	game.hud.retry_button.pressed.connect(func(): retry_clicks[0] += 1)

	await prepare_gun(game)
	var hp_before: int = game.progress.boss_hp
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.62)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await process_frame
	check(shots.size() >= 4 and shots.size() <= 6, "one held left press produces sustained rapid fire over 0.62 seconds")
	check(game.progress.boss_hp <= hp_before - 2, "held fire repeatedly damages the real boss through its hit cooldown")
	var released_count := shots.size()
	await check_no_late_shot(released_count, "releasing left stops automatic fire")

	await prepare_gun(game)
	game.boss.position = Vector3(4, 0, -30)
	game.player.facing = Vector3.LEFT
	await aim_at(game, Vector3(4, 0.05, -30))
	hp_before = game.progress.boss_hp
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await physics_frame
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await wait_seconds(0.10)
	check(shots.size() == 1 and game.progress.boss_hp == hp_before - 1, "mouse ground-plane aim hits a target opposite the previous facing")

	await prepare_gun(game)
	var minion_hits := [0, 0]
	for index in 2:
		var minion := CountedMinion.new()
		minion.player = game.player
		minion.position = Vector3(-1.3 if index == 0 else 1.3, 0.05, -33.4)
		game.add_child(minion)
		minion.set_physics_process(false)
		var hit_index := index
		minion.hit_observed.connect(func(): minion_hits[hit_index] += 1)
	await physics_frame
	hp_before = game.progress.boss_hp
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.60)
	check(shots.is_empty(), "holding right charges without firing before release")
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await wait_seconds(0.10)
	check(shots.size() == 1 and shots[0]["charged"], "0.60-second right hold releases one fully charged shot")
	check(game.progress.boss_hp == hp_before - 3 and minion_hits == [1, 1], "charged fan hits both real minions once and the boss for three damage once")
	await check_no_late_shot(1, "one charged release cannot repeat damage or emit a delayed shot")

	await prepare_gun(game)
	hp_before = game.progress.boss_hp
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.25)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await wait_seconds(0.10)
	check(shots.size() == 1 and not shots[0]["charged"] and game.progress.boss_hp == hp_before - 1, "short right hold releases an ordinary shot rather than a charged fan")

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await physics_frame
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.60)
	check(shots.is_empty(), "held left cannot interrupt right-button charging with rapid fire")
	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await wait_seconds(0.10)
	check(shots.size() == 1 and shots[0]["charged"], "combined-button hold still releases only one charged shot")

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.10)
	await tap_key(KEY_Q)
	var canceled_count := shots.size()
	await tap_key(KEY_Q)
	await check_no_late_shot(canceled_count, "switching away and back cancels held fire until a new press")
	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.60)
	await tap_key(KEY_Q)
	await tap_key(KEY_Q)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await check_no_late_shot(canceled_count, "switching away and back cancels a ready charge")

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.10)
	await tap_key(KEY_ESCAPE)
	canceled_count = shots.size()
	await check_no_late_shot(canceled_count, "pause immediately stops held fire")
	await tap_key(KEY_ESCAPE)
	await check_no_late_shot(canceled_count, "keyboard resume does not restart an old held press")
	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.60)
	await tap_key(KEY_ESCAPE)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await click_control(game.hud.resume_button)
	await check_no_late_shot(canceled_count, "pause cancels a ready charge and resume-button click cannot fire")

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.10)
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	canceled_count = shots.size()
	await check_no_late_shot(canceled_count, "application focus loss cancels held fire")
	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.60)
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await check_no_late_shot(canceled_count, "application focus loss cancels a ready charge before release")

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.10)
	await tap_key(KEY_R)
	canceled_count = shots.size()
	await check_no_late_shot(canceled_count, "R retry cancels a held firing input")
	check(not game.progress.corn_gun and not game.gun_equipped, "adventure retry preserves the original corn-gun unlock requirement")
	mouse_button(MOUSE_BUTTON_LEFT, false)

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.60)
	for damage in game.progress.max_health:
		game.on_player_hurt()
		game.progress.tick(2.0)
	check(game.progress.outcome == "lost" and paused, "real health depletion opens the failure menu")
	canceled_count = shots.size()
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	# Container layout settles after the pause menu changes to a failure menu.
	await process_frame
	await process_frame
	await click_control(game.hud.retry_button)
	await check_no_late_shot(canceled_count, "failure cancels charge and clicking retry cannot fire into the new run")
	check(retry_clicks[0] == 1 and game.progress.outcome == "playing" and not paused and game.player.attack.remaining == 0.0, "retry-button event returns to play without a leaked branch attack")

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.10)
	for damage in game.progress.max_health:
		game.on_player_hurt()
		game.progress.tick(2.0)
	canceled_count = shots.size()
	await check_no_late_shot(canceled_count, "failure immediately cancels a held rapid-fire press")
	mouse_button(MOUSE_BUTTON_LEFT, false)

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await wait_seconds(0.10)
	game.on_boss_hit(game.progress.boss_hp)
	check(game.progress.outcome == "won" and paused, "defeating the real boss opens the victory menu")
	canceled_count = shots.size()
	await check_no_late_shot(canceled_count, "victory immediately cancels held rapid fire")
	mouse_button(MOUSE_BUTTON_LEFT, false)

	await prepare_gun(game)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await wait_seconds(0.60)
	game.on_boss_hit(game.progress.boss_hp)
	canceled_count = shots.size()
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame
	await click_control(game.hud.retry_button)
	await check_no_late_shot(canceled_count, "victory cancels a ready charge and retry-button input cannot fire")
	check(retry_clicks[0] == 2 and game.progress.outcome == "playing" and not paused, "victory retry receives a real button click and returns to play")

	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	paused = false
	game.queue_free()
	await process_frame
	print("Corn gun input: %d failures" % failures)
	quit(1 if failures else 0)
