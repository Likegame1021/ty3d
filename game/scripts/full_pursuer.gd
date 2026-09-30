extends CharacterBody3D

const Shapes = preload("res://scripts/entry_shapes.gd")
signal strike_attempt
signal telegraphed
const HOME := Vector3(-8, 0.05, 4)
var active := true
var mode := "patrol"
var timer := 0.0
var chase_time := 0.0
var player_position := Vector3.ZERO
var distraction := Vector3.ZERO
var heading := Vector3.FORWARD
var caption: Label3D
var ring: MeshInstance3D
var figure: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 4
	collision_mask = 1 | 2
	var hitbox := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 0.68
	hitbox.shape = capsule
	hitbox.position.y = 0.34
	add_child(hitbox)
	figure = Node3D.new()
	add_child(figure)
	Shapes.sphere(figure, Vector3(0, 0.34, 0), Vector3(0.75, 0.52, 0.86), Color("70634d"))
	Shapes.sphere(figure, Vector3(0, 0.41, 0.38), Vector3(0.47, 0.39, 0.46), Color("a68a64"))
	for side in [-1.0, 1.0]:
		Shapes.sphere(figure, Vector3(side * 0.25, 0.66, 0.18), Vector3(0.25, 0.26, 0.09), Color("b39272"))
		Shapes.sphere(figure, Vector3(side * 0.17, 0.49, 0.57), Vector3(0.06, 0.06, 0.04), Color("f1c16a"))
	caption = Shapes.caption(self, "玉米里的田鼠", 1.15, Color("f5d99b"))
	ring = Shapes.ring(self, 1.08, Color("f5aa66"))
	reset_pursuer()

func _physics_process(delta: float) -> void:
	advance(delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	move_and_slide()
	position.x = clampf(position.x, -24, 24)
	position.z = clampf(position.z, -3, 15)
	if figure and Vector2(velocity.x, velocity.z).length() > 0.08:
		figure.rotation.y = lerp_angle(figure.rotation.y, atan2(velocity.x, velocity.z), delta * 9)
	if ring:
		ring.visible = active and mode == "windup"
	if caption:
		caption.visible = active and mode in ["chase", "windup", "lunge", "distracted"] and horizontal_distance(player_position, position) < 5.0
		caption.text = "要扑了 · 侧移！" if mode == "windup" else ("被石头引开" if mode == "distracted" else "跑开或翻过矮栏")

func advance(delta: float) -> void:
	if not active or get_tree().paused:
		return
	timer = maxf(0.0, timer - delta)
	velocity.x = 0
	velocity.z = 0
	var offset := player_position - global_position
	offset.y = 0
	var distance := offset.length()
	match mode:
		"patrol":
			if distance < 5.0 and player_position.z < 14:
				mode = "chase"
				chase_time = 0.0
		"chase":
			chase_time += delta
			if chase_time > 5.0 or distance > 8.0 or player_position.z < -5:
				mode = "return"
			elif distance < 1.3:
				mode = "windup"
				timer = 0.72
				heading = offset.normalized()
				telegraphed.emit()
			else:
				set_horizontal(offset.normalized() * 2.2)
		"windup":
			if timer <= 0:
				mode = "lunge"
				timer = 0.22
				if distance < 1.6 and heading.dot(offset.normalized()) > 0.25:
					strike_attempt.emit()
		"lunge":
			set_horizontal(heading * 4.1)
			if timer <= 0:
				mode = "recover"
				timer = 1.1
		"recover":
			if timer <= 0:
				mode = "return"
		"distracted":
			var lure := distraction - position
			lure.y = 0
			if lure.length() > 0.3:
				set_horizontal(lure.normalized() * 2.5)
			if timer <= 0:
				mode = "return"
		"return":
			var home_offset := HOME - position
			home_offset.y = 0
			if home_offset.length() < 0.3:
				mode = "patrol"
			else:
				set_horizontal(home_offset.normalized() * 1.7)

func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func set_horizontal(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z

func distract(point: Vector3) -> void:
	if not active or get_tree().paused:
		return
	distraction = point
	mode = "distracted"
	timer = 2.6

func receive_hit(direction: Vector3) -> void:
	if not active or get_tree().paused:
		return
	heading = direction
	mode = "return"
	chase_time = 0
	position += direction.normalized() * 0.42

func reset_pursuer() -> void:
	position = HOME
	velocity = Vector3.ZERO
	active = true
	mode = "patrol"
	timer = 0.0
	chase_time = 0.0
	distraction = Vector3.ZERO
	heading = Vector3.FORWARD
	if caption:
		caption.visible = false
	if ring:
		ring.visible = false
