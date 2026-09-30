extends CharacterBody3D

const Shapes = preload("res://scripts/entry_shapes.gd")

signal strike_attempt
signal defeated
signal telegraphed

const HOME := Vector3(-1.8, 0.05, -6)
var player: CharacterBody3D
var mode := "patrol"
var state_time := 0.0
var chase_elapsed := 0.0
var clock := 0.0
var health := 2
var hit_count := 0
var active := true
var story_revealed := false
var locked_direction := Vector3.FORWARD
var figure: Node3D
var caption: Label3D
var warning_ring: MeshInstance3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("entry_enemies")
	collision_layer = 4
	collision_mask = 1 | 2
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 0.65
	collider.shape = capsule
	collider.position.y = 0.325
	add_child(collider)
	figure = Node3D.new()
	add_child(figure)
	Shapes.sphere(figure, Vector3(0, 0.3, 0), Vector3(0.57, 0.5, 0.7), Color("706552"))
	Shapes.sphere(figure, Vector3(0, 0.38, 0.32), Vector3(0.38, 0.36, 0.46), Color("9c8260"))
	Shapes.sphere(figure, Vector3(0, 0.33, 0.57), Vector3(0.11, 0.1, 0.10), Color("453c39"))
	for side in [-1.0, 1.0]:
		Shapes.sphere(figure, Vector3(side * 0.2, 0.59, 0.22), Vector3(0.2, 0.22, 0.08), Color("927c61"))
		Shapes.sphere(figure, Vector3(side * 0.2, 0.59, 0.27), Vector3(0.13, 0.14, 0.045), Color("d1a383"))
		var eye := Shapes.sphere(figure, Vector3(side * 0.14, 0.44, 0.44), Vector3(0.05, 0.045, 0.05), Color("ecae4b"))
		eye.material_override = Shapes.material(Color("ecae4b"), true)
		for front in [-0.18, 0.21]:
			Shapes.box(figure, Vector3(side * 0.2, 0.06, front), Vector3(0.16, 0.1, 0.18), Color("554b3f"))
	for index in 5:
		Shapes.sphere(figure, Vector3(sin(index * 0.5) * 0.09, 0.12 - index * 0.009, -0.39 - index * 0.11), Vector3(0.06, 0.06, 0.17), Color("b39a83"))
	caption = Shapes.caption(self, "田鼠怪 · 可绕行", 1.02, Color("f1c47e"))
	warning_ring = Shapes.ring(self, 0.84, Color("f5a65b"))
	reset_creature()

func _physics_process(delta: float) -> void:
	update_behaviour(delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	move_and_slide()
	position.x = clampf(position.x, -13.0, 13.0)
	position.z = clampf(position.z, -15.0, 15.0)
	if figure and Vector2(velocity.x, velocity.z).length() > 0.05:
		figure.rotation.y = lerp_angle(figure.rotation.y, atan2(velocity.x, velocity.z), delta * 9.0)
	if warning_ring:
		warning_ring.visible = mode == "windup"
		warning_ring.scale = Vector3.ONE * (1.0 + sin(clock * 18.0) * 0.055)
	if caption:
		caption.text = {"patrol": "田鼠怪 · 可绕行", "chase": "靠近了！可跑开", "windup": "要扑了！躲开", "lunge": "扑击", "cooldown": "喘息中", "return": "田鼠返回了", "stunned": "被树枝击退", "flee": "田鼠退走了"}.get(mode, "田鼠怪")
		var close_danger := mode in ["chase", "windup", "lunge", "stunned"] and is_instance_valid(player) and Vector2(player.position.x - position.x, player.position.z - position.z).length() < 3.6
		caption.visible = story_revealed or close_danger

func update_behaviour(delta: float) -> void:
	if get_tree().paused:
		return
	clock += delta
	state_time = maxf(0.0, state_time - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	if not active:
		if mode == "flee" and state_time > 0:
			set_horizontal(locked_direction * 2.8)
		elif figure:
			figure.visible = false
			caption.visible = false
		return
	if not is_instance_valid(player):
		return
	var offset: Vector3 = player.global_position - global_position
	offset.y = 0
	var distance := offset.length()
	var player_home_distance := Vector2(player.position.x - HOME.x, player.position.z - HOME.z).length()
	match mode:
		"patrol":
			var patrol_goal := HOME + Vector3(sin(clock * 0.75) * 1.15, 0, cos(clock * 0.75) * 0.65)
			set_horizontal((patrol_goal - position).normalized() * 0.9)
			if distance < 3.4 and player.position.z < -1.8 and player_home_distance < 5.3 and has_sight():
				mode = "chase"
				chase_elapsed = 0.0
		"chase":
			chase_elapsed += delta
			if chase_elapsed > 4.5 or player_home_distance > 5.3 or position.distance_to(HOME) > 5.0 or player.position.z > -1.8 or not has_sight():
				mode = "return"
			elif distance < 1.05:
				mode = "windup"
				state_time = 0.72
				locked_direction = offset.normalized()
				telegraphed.emit()
			else:
				set_horizontal(offset.normalized() * 2.0)
		"windup":
			if state_time <= 0.0:
				mode = "lunge"
				state_time = 0.18
				if distance < 1.15 and locked_direction.dot(offset.normalized()) > 0.30 and has_sight():
					strike_attempt.emit()
		"lunge":
			set_horizontal(locked_direction * 3.6)
			if state_time <= 0.0:
				mode = "cooldown"
				state_time = 1.10
		"cooldown":
			if state_time <= 0.0:
				mode = "chase" if player_home_distance < 5.3 and player.position.z < -1.8 else "return"
		"stunned":
			set_horizontal(locked_direction * 3.0 * state_time / 0.7)
			if state_time <= 0.0:
				mode = "return"
		"return":
			var home_offset := HOME - position
			home_offset.y = 0
			set_horizontal(home_offset.normalized() * 1.5)
			if home_offset.length() < 0.18:
				mode = "patrol"
				chase_elapsed = 0.0

func set_horizontal(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z

func has_sight() -> bool:
	if not is_instance_valid(player):
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, player.global_position + Vector3.UP * 0.4, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func receive_hit(direction: Vector3) -> void:
	if not active or get_tree().paused:
		return
	hit_count += 1
	health = maxi(0, health - 1)
	locked_direction = direction.normalized()
	mode = "stunned"
	state_time = 0.7
	if health == 0:
		active = false
		mode = "flee"
		state_time = 1.4
		if caption:
			caption.visible = story_revealed
		collision_layer = 0
		remove_from_group("entry_enemies")
		defeated.emit()

func reset_creature() -> void:
	position = HOME
	velocity = Vector3.ZERO
	mode = "patrol"
	state_time = 0.0
	chase_elapsed = 0.0
	clock = 0.0
	health = 2
	hit_count = 0
	active = true
	story_revealed = false
	locked_direction = Vector3.FORWARD
	collision_layer = 4
	if not is_in_group("entry_enemies"):
		add_to_group("entry_enemies")
	if figure:
		figure.visible = true
		figure.rotation = Vector3.ZERO
		caption.visible = false
		warning_ring.visible = false
