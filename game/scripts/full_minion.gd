extends CharacterBody3D

const Shapes = preload("res://scripts/entry_shapes.gd")
signal strike_attempt
var player: Node3D
var active := true
var lifetime := 12.0
var cooldown := 0.0
var figure: Node3D
var mode := "approach"
var warning_ring: MeshInstance3D
var caption: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 4
	collision_mask = 1 | 2
	add_to_group("full_enemies")
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 0.55
	collider.shape = capsule
	collider.position.y = 0.275
	add_child(collider)
	figure = Node3D.new()
	add_child(figure)
	Shapes.sphere(figure, Vector3(0, 0.28, 0), Vector3(0.55, 0.44, 0.65), Color("786a4d"))
	Shapes.sphere(figure, Vector3(0, 0.35, 0.32), Vector3(0.34, 0.32, 0.36), Color("ad956e"))
	caption = Shapes.caption(self, "小田鼠", 0.9, Color("f5d79b"))
	warning_ring = Shapes.ring(self, 0.7, Color("e9a25e"))
	warning_ring.visible = false

func _physics_process(delta: float) -> void:
	advance(delta)
	if not active:
		return
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	move_and_slide()

func advance(delta: float) -> void:
	if not active or get_tree().paused:
		return
	lifetime -= delta
	cooldown = maxf(0.0, cooldown - delta)
	if lifetime <= 0:
		retreat()
		return
	if is_instance_valid(player):
		var offset := player.global_position - global_position
		offset.y = 0
		if mode == "windup":
			velocity.x = 0
			velocity.z = 0
			if cooldown <= 0:
				mode = "cooldown"
				cooldown = 1.4
				if offset.length() < 1.4:
					strike_attempt.emit()
		elif mode == "cooldown":
			velocity.x = 0
			velocity.z = 0
			if cooldown <= 0:
				mode = "approach"
		elif offset.length() < 1.15:
			mode = "windup"
			cooldown = 0.55
			velocity.x = 0
			velocity.z = 0
		else:
			velocity.x = offset.normalized().x * 2.1
			velocity.z = offset.normalized().z * 2.1
			figure.rotation.y = lerp_angle(figure.rotation.y, atan2(velocity.x, velocity.z), delta * 8)
	if warning_ring:
		warning_ring.visible = mode == "windup"
	if caption:
		caption.text = "要扑了 · 侧移" if mode == "windup" else "小田鼠"

func receive_hit(_direction: Vector3) -> void:
	if active and not get_tree().paused:
		retreat()

func retreat() -> void:
	active = false
	collision_layer = 0
	remove_from_group("full_enemies")
	queue_free()
