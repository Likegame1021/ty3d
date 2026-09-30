extends SceneTree

const ROUTE_LIMIT_MS := 360000
const TARGET_FRAME_LIMIT := 2400
const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "run"]

var game: Node
var failed := 0
var started_ms := 0
var route_stages: Array[String] = []

func record(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func release_movement() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)

func timed_out() -> bool:
	return Time.get_ticks_msec() - started_ms > ROUTE_LIMIT_MS

func steer_to(target: Vector3, radius: float = 1.5, frame_limit: int = TARGET_FRAME_LIMIT) -> bool:
	var previous_distance := INF
	var stuck_frames := 0
	for _frame in frame_limit:
		if timed_out() or game.progress.outcome != "playing":
			release_movement()
			return false
		var offset: Vector3 = target - game.player.global_position
		offset.y = 0
		var distance := offset.length()
		if distance <= radius:
			release_movement()
			return true
		var direction := offset / distance
		# Invert player.gd's screen-space-to-world mapping so this follows a world target.
		var screen_x := (direction.x - direction.z) * 0.5
		var screen_y := (direction.x + direction.z) * 0.5
		release_movement()
		if screen_x < -0.08:
			Input.action_press("move_left", absf(screen_x))
		elif screen_x > 0.08:
			Input.action_press("move_right", absf(screen_x))
		if screen_y < -0.08:
			Input.action_press("move_up", absf(screen_y))
		elif screen_y > 0.08:
			Input.action_press("move_down", absf(screen_y))
		Input.action_press("run")
		await physics_frame
		var next_offset: Vector3 = target - game.player.global_position
		next_offset.y = 0
		var next_distance := next_offset.length()
		if next_distance > previous_distance - 0.003:
			stuck_frames += 1
		else:
			stuck_frames = 0
		previous_distance = next_distance
		if stuck_frames >= 90:
			release_movement()
			return false
	release_movement()
	return false

func tap_key_action(action: String, key: Key) -> bool:
	var key_template: InputEventKey
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == key:
			key_template = event.duplicate() as InputEventKey
			break
	if key_template == null:
		printerr("No physical key mapped for action: ", action)
		return false
	key_template.pressed = true
	key_template.echo = false
	Input.parse_input_event(key_template)
	await physics_frame
	var release_event := key_template.duplicate() as InputEventKey
	release_event.pressed = false
	release_event.echo = false
	Input.parse_input_event(release_event)
	await physics_frame
	return true

func tap_mouse(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	var release_event := event.duplicate() as InputEventMouseButton
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await physics_frame

func wait_frames(count: int) -> bool:
	for _frame in count:
		if timed_out() or game.progress.outcome != "playing":
			return false
		await physics_frame
	return true

func go_and_interact(target: Vector3, label: String, radius := 1.7) -> bool:
	var reached := await steer_to(target, radius)
	if not reached:
		record(false, "input route reaches " + label)
		return false
	if not await tap_key_action("interact", KEY_E):
		record(false, "E event mapped for " + label)
		return false
	await physics_frame
	return game.progress.outcome == "playing"

func run_route() -> void:
	started_ms = Time.get_ticks_msec()
	game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	if not game.player.has_real_model:
		record(false, "formal character is loaded")
		return
	var route_ok := true
	route_ok = await steer_to(Vector3(-3.5, 0.05, 36), 1.7)
	if route_ok:
		route_stages.append("chicken")
		await wait_frames(3)
		record(game.progress.chicken_seen, "input route discovers harmless chicken")
		route_ok = game.progress.chicken_seen
	if route_ok:
		route_ok = await go_and_interact(Vector3(-5, 0.05, 31), "marble tin")
		record(game.progress.tin_taken, "E collects the tin once")
		route_ok = route_ok and game.progress.tin_taken
	if route_ok:
		route_ok = await go_and_interact(Vector3(0, 0.05, 22), "water mouth")
		record(game.progress.mouth_cleared, "E clears the water mouth")
		route_ok = route_ok and game.progress.mouth_cleared
	if route_ok:
		route_ok = await go_and_interact(Vector3(5, 0.05, 20), "sluice")
		record(game.progress.canal_open, "E opens the sluice")
		route_ok = route_ok and game.progress.canal_open
	if route_ok:
		route_ok = await steer_to(Vector3(-7, 0.05, 9), 1.8)
		record(route_ok and game.progress.dense_entered, "input route reaches dense corn")
		route_ok = route_ok and game.progress.dense_entered
	if route_ok:
		route_stages.append("dense_corn")
		route_ok = await tap_key_action("throw_stone", KEY_F)
		await wait_frames(4)
		record(game.progress.stones_thrown > 0, "F throws a real stone input in dense corn")
		route_ok = route_ok and game.progress.stones_thrown > 0
	if route_ok:
		route_ok = await steer_to(Vector3(-5, 0.05, 4.1), 0.25)
		if route_ok:
			print("INPUT_FENCE_APPROACH position=", game.player.position, " distance=", game.flat_distance(game.player.position, Vector3(-5, 0.05, 3)))
			route_ok = await tap_key_action("interact", KEY_E)
			await physics_frame
		record(game.progress.fence_vaulted, "E vaults the low fence")
		route_ok = route_ok and game.progress.fence_vaulted
	if route_ok:
		route_stages.append("farm_yard")
		route_ok = await go_and_interact(Vector3(12, 0.05, -9), "wood board")
		record(game.progress.board_taken, "E takes the board")
		route_ok = route_ok and game.progress.board_taken
	if route_ok:
		route_ok = await go_and_interact(Vector3(16, 0.05, -13), "farm cart")
		record(game.progress.cart_moved, "E moves the cart using the board")
		route_ok = route_ok and game.progress.cart_moved
	if route_ok:
		route_ok = await go_and_interact(Vector3(17, 0.05, -18), "tool shed launcher")
		record(game.progress.launcher_taken, "E takes the old launcher")
		route_ok = route_ok and game.progress.launcher_taken
	if route_ok:
		route_stages.append("boss_arena")
		# Exit the tool shed through its south opening, then follow the west
		# side of the shed and the marked route into the arena.
		route_ok = await steer_to(Vector3(17, 0.05, -14.0), 0.35)
		if route_ok:
			route_ok = await steer_to(Vector3(9, 0.05, -14.0), 0.35)
		if route_ok:
			route_ok = await steer_to(Vector3(9, 0.05, -20.0), 0.5)
		if route_ok:
			route_ok = await steer_to(Vector3(4, 0.05, -24.0), 0.5)
		if route_ok:
			route_ok = await steer_to(Vector3(0, 0.05, -30.5), 0.4)
		await wait_frames(8)
		print("INPUT_BOSS_APPROACH position=", game.player.position, " launcher=", game.progress.launcher_taken, " gate_disabled=", game.boss_gate_shape.disabled, " boss_active=", game.progress.boss_active)
		record(route_ok and game.progress.boss_active, "input route physically enters the active boss arena")
		route_ok = route_ok and game.progress.boss_active
	if route_ok:
		route_ok = await fight_boss()
		record(route_ok and game.progress.outcome == "won", "real-input boss route reaches victory")
	print("FULL_INPUT_EVIDENCE: ", {"stages": route_stages, "route_ok": route_ok, "outcome": game.progress.outcome if game else "no_game", "elapsed_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0, "hearts": game.progress.health if game else -1, "boss_hp": game.progress.boss_hp if game else -1, "corn_gun": game.progress.corn_gun if game else false, "failures": failed})

func dodge_boss_warning() -> bool:
	var warning: Vector3 = game.boss.warning_position if game.boss.mode == "burrow_windup" else game.boss.global_position
	var away: Vector3 = game.player.global_position - warning
	away.y = 0
	if away.length() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var desired := warning + away * 3.2
	return await steer_to(desired, 0.35, 100)

func hit_boss_with_branch() -> bool:
	var away: Vector3 = game.player.global_position - game.boss.global_position
	away.y = 0
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	var attack_stand: Vector3 = game.boss.global_position + away.normalized() * 1.12
	if not await steer_to(attack_stand, 0.25, 120):
		print("INPUT_BOSS_APPROACH_STALLED player=", game.player.position, " target=", attack_stand, " boss=", game.boss.position, " mode=", game.boss.mode)
		return false
	var previous_hp: int = game.progress.boss_hp
	print("INPUT_BRANCH_ATTEMPT pos=", game.player.position, " facing=", game.player.facing, " boss=", game.boss.position, " mode=", game.boss.mode)
	if not await tap_key_action("attack", KEY_SPACE):
		return false
	# The imported attack clip's verified contact window begins near 0.59s.
	if not await wait_frames(45):
		return false
	var hit: bool = game.progress.boss_hp < previous_hp
	print("INPUT_BRANCH_RESULT hit=", hit, " hp=", game.progress.boss_hp, " attack_elapsed=", game.player.attack.elapsed, " remaining=", game.player.attack.remaining)
	return hit

func move_and_fire(charged: bool) -> bool:
	var away: Vector3 = game.player.global_position - game.boss.global_position
	away.y = 0
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	var distance := away.length()
	if distance < 2.4 or distance > 7.5:
		var aim_point: Vector3 = game.boss.global_position + away.normalized() * 4.2
		if not await steer_to(aim_point, 0.22, 240):
			return false
	# A short real movement toward the boss sets facing without teleporting.
	var toward_boss := -away.normalized()
	var sx := (toward_boss.x - toward_boss.z) * 0.5
	var sy := (toward_boss.x + toward_boss.z) * 0.5
	release_movement()
	if sx < -0.08:
		Input.action_press("move_left", absf(sx))
	elif sx > 0.08:
		Input.action_press("move_right", absf(sx))
	if sy < -0.08:
		Input.action_press("move_up", absf(sy))
	elif sy > 0.08:
		Input.action_press("move_down", absf(sy))
	Input.action_press("run")
	if not await wait_frames(3):
		release_movement()
		return false
	release_movement()
	while game.fire_cooldown > 0.0:
		if not await wait_frames(2):
			return false
	var pointer := aim_mouse_at_boss()
	await process_frame
	await physics_frame
	var previous_hp: int = game.progress.boss_hp
	if charged:
		var held := InputEventMouseButton.new()
		held.button_index = MOUSE_BUTTON_RIGHT
		held.pressed = true
		held.position = pointer
		held.global_position = pointer
		Input.parse_input_event(held)
		for frame in 72:
			aim_mouse_at_boss()
			if not await wait_frames(1):
				held.pressed = false
				Input.parse_input_event(held)
				return false
		var released := held.duplicate() as InputEventMouseButton
		released.pressed = false
		Input.parse_input_event(released)
		await physics_frame
	else:
		if not await tap_key_action("attack", KEY_SPACE):
			return false
	if game.progress.outcome == "won":
		return true
	if not await wait_frames(12):
		return false
	return game.progress.boss_hp < previous_hp

func aim_mouse_at_boss() -> Vector2:
	# The corn gun now aims with the pointer independently from movement.
	# Exercise the real viewport mouse path at the visible boss body.
	var pointer: Vector2 = root.get_final_transform() * game.camera.unproject_position(game.boss.global_position + Vector3.UP)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	motion.global_position = pointer
	Input.parse_input_event(motion)
	return pointer

func fight_boss() -> bool:
	var boss_start_ms := Time.get_ticks_msec()
	var has_switched := false
	var did_charge := false
	var last_branch_recover_index := -1
	while not timed_out() and Time.get_ticks_msec() - boss_start_ms < 180000:
		if game.progress.outcome != "playing":
			return game.progress.outcome == "won"
		if not game.progress.corn_gun:
			if game.progress.corn_spilled:
				if not await go_and_interact(Vector3(5, 0.05, -33), "spilled corn weapon", 2.2):
					return false
				route_stages.append("corn_gun_combined")
				record(game.progress.corn_gun and game.gun_equipped, "E combines the launcher and spilled corn")
				continue
			if game.boss.mode == "recover":
				if game.boss.skill_index != last_branch_recover_index:
					last_branch_recover_index = game.boss.skill_index
					if not await hit_boss_with_branch():
						return false
					record(true, "space branch strike damages boss in recover window")
				else:
					await physics_frame
			elif game.boss.mode.ends_with("_windup") and game.flat_distance(game.player.position, game.boss.warning_position if game.boss.mode == "burrow_windup" else game.boss.position) < 2.5:
				await dodge_boss_warning()
			else:
				await physics_frame
		else:
			if not has_switched:
				if not game.gun_equipped:
					if not await tap_key_action("switch_weapon", KEY_Q):
						return false
				has_switched = true
			if not did_charge:
				var charged_hit := await move_and_fire(true)
				if game.progress.outcome == "won":
					route_stages.append("boss_defeated")
					return true
				if not charged_hit:
					return false
				did_charge = true
				record(true, "held real right mouse charges and fires the scatter shot")
			else:
				var normal_hit := await move_and_fire(false)
				if game.progress.outcome == "won":
					route_stages.append("boss_defeated")
					return true
				if not normal_hit:
					return false
				record(true, "space fires a real mid-range corn shot")
			if game.progress.outcome == "won":
				route_stages.append("boss_defeated")
				return true
	return game.progress.outcome == "won"

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	await run_route()
	release_movement()
	Input.action_release("interact")
	Input.action_release("throw_stone")
	Input.action_release("attack")
	Input.action_release("switch_weapon")
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	quit(1 if failed else 0)
