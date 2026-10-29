extends SceneTree
## Actual target player + inherited M2 corn-gun controller + new room enemies.

var failures := 0
var checks := 0
var shots: Array[bool] = []
var controller: Node3D
var player: CharacterBody3D
var camera: Camera3D
var arena: Node3D
var enemy: CharacterBody3D
var pointer := Vector2.ZERO

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func wait_seconds(seconds: float) -> void:
	for frame in ceili(seconds*Engine.physics_ticks_per_second):
		await physics_frame
	await process_frame

func button(which: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = which
	event.pressed = pressed
	event.position = pointer
	event.global_position = pointer
	Input.parse_input_event(event)

func reset_target() -> void:
	controller.cancel_gun_input(true)
	controller.fire_cooldown = 0.0
	enemy.hp = enemy.max_hp
	player.damage_multiplier = 1.0
	player.facing = Vector3.FORWARD
	player.aim_direction = Vector3.FORWARD
	shots.clear()

func run_checks() -> void:
	root.size = Vector2i(1280,800)
	for path in ["res://scripts/cornfield/weapon_controller.gd","res://scripts/cornfield/player.gd","res://scripts/cornfield/field_enemy.gd"]:
		check(ResourceLoader.exists(path),"required chapter weapon component exists: "+path)
	if failures:
		finish()
		return
	arena = Node3D.new()
	root.add_child(arena)
	player = load("res://scripts/cornfield/player.gd").new()
	player.spawn_position = Vector3(0,0.05,0)
	arena.add_child(player)
	player.set_physics_process(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.5
	arena.add_child(camera)
	camera.position = Vector3(7,11,9)
	camera.look_at(Vector3(0,0,-2.5))
	camera.make_current()
	player.configure(camera,"corn")
	var hud := CanvasLayer.new()
	arena.add_child(hud)
	controller = load("res://scripts/cornfield/weapon_controller.gd").new()
	controller.player = player
	controller.camera = camera
	controller.hud = hud
	arena.add_child(controller)
	controller.setup_input()
	if not InputMap.has_action("charge_shot"):
		InputMap.add_action("charge_shot")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("charge_shot",right)
	controller.shot_fired.connect(func(charged: bool): shots.append(charged))
	enemy = load("res://scripts/cornfield/field_enemy.gd").new()
	arena.add_child(enemy)
	enemy.position = Vector3(0,0,-4)
	enemy.configure(arena,player,"boss_borer")
	enemy.set_physics_process(false)
	await physics_frame
	await physics_frame
	pointer = camera.unproject_position(enemy.global_position+Vector3.UP*0.4)
	reset_target()
	player.configure(camera,"stick")
	player.damage_multiplier = 1.5
	enemy.position = Vector3(0,0,-1.0)
	player.request_attack()
	player.attack.tick(maxf(0.0,player.attack.active_start-0.01),false)
	player.check_hits()
	check(enemy.hp == 620.0,"original branch windup cannot damage the new enemy early")
	player.attack.tick(0.02,false)
	player.check_hits()
	player.check_hits()
	check(enemy.hp == 593.0,"original branch active window deals one upgraded 18-damage hit")
	player.attack.reset()
	player.configure(camera,"corn")
	enemy.position = Vector3(0,0,-4)
	await physics_frame
	reset_target()
	button(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.05)
	button(MOUSE_BUTTON_LEFT,false)
	await process_frame
	check(enemy.hp == 606.0 and shots == [false],"real mouse shot damages new enemy through unchanged M2 fire_gun")
	await wait_seconds(0.45)
	check(shots.size() == 1,"left release stops automatic fire without a delayed shot")

	reset_target()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3,2,0.3)
	collision.shape = shape
	wall.add_child(collision)
	arena.add_child(wall)
	wall.position = Vector3(0,1,-2)
	await physics_frame
	await physics_frame
	controller.fire_gun(false)
	check(enemy.hp == 620.0,"solid wall blocks inherited corn damage against real new enemy")
	wall.free()
	await physics_frame
	await physics_frame

	reset_target()
	player.damage_multiplier = 1.5
	var side = load("res://scripts/cornfield/field_enemy.gd").new()
	arena.add_child(side)
	side.position = Vector3(1.4,0,-3.5)
	side.configure(arena,player,"boss_borer")
	side.set_physics_process(false)
	await physics_frame
	button(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.60)
	check(shots.is_empty() and enemy.hp == 620.0,"right mouse hold charges without premature damage")
	button(MOUSE_BUTTON_RIGHT,false)
	await wait_seconds(0.10)
	check(shots == [true] and enemy.hp == 557.0 and side.hp == 557.0,"charged fan applies 3×14×1.5 once to each real target")
	await wait_seconds(0.50)
	check(shots.size() == 1 and enemy.hp == 557.0,"charged release cannot leave a repeated or stale shot")
	side.free()

	reset_target()
	button(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.20)
	button(MOUSE_BUTTON_RIGHT,false)
	await wait_seconds(0.10)
	check(shots == [false] and enemy.hp == 606.0,"short charge preserves original ordinary-shot behavior")

	reset_target()
	button(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.60)
	player.controls_enabled = false
	button(MOUSE_BUTTON_RIGHT,false)
	await wait_seconds(0.10)
	check(shots.is_empty() and enemy.hp == 620.0,"disabled chapter controls prevent inherited release from firing during transition")
	player.controls_enabled = true
	reset_target()
	button(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.60)
	player.hp = 0.0
	button(MOUSE_BUTTON_RIGHT,false)
	await wait_seconds(0.10)
	check(shots.is_empty() and enemy.hp == 620.0,"zero health rejects release before a deferred host death callback")
	button(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.20)
	check(shots.is_empty(),"zero health also rejects fresh press and held-fire ticks")
	player.hp = 100.0
	button(MOUSE_BUTTON_LEFT,false)
	button(MOUSE_BUTTON_RIGHT,false)
	controller.cancel_gun_input()
	arena.queue_free()
	await process_frame
	await process_frame
	await test_host_pause_and_death()
	# AudioServer releases stopped playback on its asynchronous mix cadence.
	# Two idle frames can be less than one mix on a fast headless runner; use
	# the same bounded teardown grace as the full-corn audio lifecycle suite.
	await create_timer(0.15).timeout
	finish()

func test_host_pause_and_death() -> void:
	var host = load("res://scripts/cornfield/game.gd").new()
	host.test_mode = true
	host.save_path = "user://qa_cornfield_weapon_%d.json" % Time.get_ticks_usec()
	host.prepared_weapon = "corn"
	root.add_child(host)
	host._start_new_run(730027)
	host._choose_route(str(host.run.data.offers[0]))
	await physics_frame
	await physics_frame
	controller = host.weapon_controller
	player = host.player
	camera = host.camera
	player.set_physics_process(false)
	controller.shot_fired.connect(func(charged: bool): shots.append(charged))
	pointer = camera.unproject_position(player.global_position+Vector3.FORWARD*4)
	shots.clear()
	button(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.60)
	host._show_pause()
	check(paused and not controller.charging and not controller.fire_held,"actual chapter pause panel cancels ready charge immediately")
	button(MOUSE_BUTTON_RIGHT,false)
	host._close_panel()
	await wait_seconds(0.20)
	button(MOUSE_BUTTON_RIGHT,false)
	await wait_seconds(0.45)
	check(shots.is_empty(),"actual chapter resume and late release cannot fire pre-pause charge")
	button(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.20)
	host.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var before := shots.size()
	await wait_seconds(0.20)
	host.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	await wait_seconds(0.30)
	button(MOUSE_BUTTON_LEFT,false)
	check(shots.size() == before and not controller.fire_held,"actual chapter focus loss cancels held fire through resume")
	shots.clear()
	controller.fire_cooldown = 0
	button(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.60)
	player.hurt_cooldown = 0.0
	player.receive_damage(10000.0)
	button(MOUSE_BUTTON_RIGHT,false)
	await process_frame
	await process_frame
	check(shots.is_empty() and host.phase == "settlement","death cancels ready charge before deferred settlement")
	paused = false
	host.queue_free()
	await process_frame
	await process_frame

func finish() -> void:
	print(JSON.stringify({"suite":"cornfield_weapon","checks":checks,"failures":failures}))
	quit(1 if failures else 0)
