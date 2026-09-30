extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TargetScript = preload("res://scripts/practice_target.gd")
const HudScript = preload("res://ui/hud.gd")
var player: CharacterBody3D
var target: StaticBody3D
var environment: Node3D
var camera: Camera3D
var hud: CanvasLayer
var night := false
var fallback_light: DirectionalLight3D
var fallback_world: WorldEnvironment
var camera_focus := Vector3(0, 0.6, 5)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_input()
	if ResourceLoader.exists("res://environment/cornfield.gd"):
		environment = load("res://environment/cornfield.gd").new()
		environment.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(environment)
	else:
		build_fallback_ground()
	player = PlayerScript.new()
	player.name = "Boy"
	add_child(player)
	target = TargetScript.new()
	target.name = "PracticeTarget"
	target.position = Vector3(0, 0, -5)
	add_child(target)
	player.struck.connect(on_hit)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.5
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.current = true
	update_camera(1.0)
	hud = HudScript.new()
	add_child(hud)
	hud.resume_requested.connect(func(): set_paused(false))
	set_night(false)
	hud.show_message("夏日的风里，去试试手中的树枝。", 4.0)

func setup_input() -> void:
	var actions := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"run": [KEY_SHIFT], "attack": [KEY_SPACE], "interact": [KEY_E],
		"night": [KEY_TAB], "reset": [KEY_R], "pause": [KEY_ESCAPE]
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("attack", mouse):
		InputMap.action_add_event("attack", mouse)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("attack") and not event.is_echo():
		# Unhandled events exclude pointer clicks consumed by the pause UI.
		player.request_attack()
	elif event.is_action_pressed("night") and not event.is_echo():
		set_night(not night)
		hud.show_message("月色预览" if night else "午后预览")
	elif event.is_action_pressed("reset") and not event.is_echo():
		reset_sample()
	elif event.is_action_pressed("interact") and not event.is_echo():
		if player.can_reach(target, 2.3):
			hud.show_message("稻草练习桩：靠近、面向它，再挥枝。\n每次挥动只记一次；R 可重置练习。", 5.0)
		else:
			hud.show_message("再靠近一点，才能与练习桩交互。")

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not get_tree().paused:
		update_camera(delta)
		if environment and environment.has_method("set_player_position"):
			environment.set_player_position(player.global_position)
	# can_reach needs physics state; plain distance is enough for a UI prompt.
	hud.update_display(player, night, target.hit_count, player.global_position.distance_to(target.global_position) <= 2.3)

func update_camera(delta: float) -> void:
	var desired := player.global_position + Vector3(0, 0.7, -2.8)
	camera_focus = camera_focus.lerp(desired, 1.0 - exp(-delta * 4.0))
	camera.global_position = camera_focus + Vector3(15, 19, 15)
	camera.look_at(camera_focus, Vector3.UP)

func set_night(value: bool) -> void:
	night = value
	if environment and environment.has_method("set_night"):
		environment.set_night(value)
	elif fallback_light:
		fallback_light.light_energy = 0.5 if value else 1.15
		fallback_light.light_color = Color("a7b9e8") if value else Color("fff0d0")
		fallback_world.environment.background_color = Color("182539") if value else Color("9cb5b3")
		fallback_world.environment.ambient_light_energy = 0.5 if value else 0.75

func set_paused(value: bool) -> void:
	get_tree().paused = value
	hud.set_paused(value)

func reset_sample() -> void:
	player.reset_player()
	target.reset_target()
	camera_focus = player.global_position + Vector3(0, 0.7, -2.8)
	update_camera(1.0)
	hud.show_message("练习已重置。沿路再走一遍吧。")

func on_hit(_target: Node3D) -> void:
	hud.show_message("啪！  命中 %02d" % target.hit_count, 1.3)

func build_fallback_ground() -> void:
	# Only used while the separately-owned environment is still being delivered.
	var floor_body := StaticBody3D.new()
	floor_body.process_mode = Node.PROCESS_MODE_PAUSABLE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(28, 0.3, 32)
	shape.shape = box
	shape.position.y = -0.15
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = box.size
	mesh.mesh = floor_mesh
	mesh.position.y = -0.15
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8e9761")
	mesh.material_override = material
	floor_body.add_child(mesh)
	add_child(floor_body)
	fallback_light = DirectionalLight3D.new()
	fallback_light.rotation_degrees = Vector3(-55, -35, 0)
	fallback_light.shadow_enabled = true
	add_child(fallback_light)
	fallback_world = WorldEnvironment.new()
	fallback_world.environment = Environment.new()
	fallback_world.environment.background_mode = Environment.BG_COLOR
	fallback_world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	fallback_world.environment.ambient_light_color = Color("bcc5ac")
	add_child(fallback_world)
