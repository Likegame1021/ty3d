extends StaticBody3D

const Shapes = preload("res://scripts/entry_shapes.gd")
signal strike_attempt
signal summon_requested
signal hit_received(amount: int)
signal skill_warned(name: String)

const HOME := Vector3(0, 0, -34)
var active := false
var mode := "idle"
var skill_index := 0
var phase_remaining := 2.0
var hit_cooldown := 0.0
var player_position := Vector3.ZERO
var warning_position := Vector3.ZERO
var burrow_start := HOME
var burrow_edge := HOME
var burrow_target := HOME
var warning_ring: MeshInstance3D
var moving_mound: MeshInstance3D
var body: Node3D
var caption: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position = HOME
	collision_layer = 4
	collision_mask = 0
	add_to_group("full_enemies")
	var hitbox := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.64
	capsule.height = 2.3
	hitbox.shape = capsule
	hitbox.position.y = 1.15
	add_child(hitbox)
	body = Node3D.new()
	add_child(body)
	Shapes.box(body, Vector3(0, 0.35, 0), Vector3(0.72, 0.7, 0.68), Color("5e4932"))
	Shapes.box(body, Vector3(0, 1.23, 0), Vector3(0.82, 1.13, 0.62), Color("bea16b"))
	Shapes.sphere(body, Vector3(0, 2.02, 0), Vector3(0.67, 0.65, 0.56), Color("c0a074"))
	for side in [-1.0, 1.0]:
		Shapes.box(body, Vector3(side * 0.77, 1.50, 0), Vector3(0.76, 0.18, 0.18), Color("71533a"))
		Shapes.sphere(body, Vector3(side * 0.16, 2.08, 0.27), Vector3(0.07, 0.08, 0.04), Color("d9774a"))
	Shapes.box(body, Vector3(0, 2.38, 0), Vector3(1.25, 0.09, 0.85), Color("6e5034"))
	Shapes.box(body, Vector3(0, 2.58, 0), Vector3(0.7, 0.33, 0.58), Color("8d6840"))
	caption = Shapes.caption(self, "荒田稻草人", 3.0, Color("fff0b2"))
	warning_ring = Shapes.ring(self, 2.0, Color("ed8554"))
	moving_mound = Shapes.sphere(self, Vector3(0, 0.08, 0), Vector3(1.0, 0.22, 0.8), Color("806546"))
	reset_boss()

func _physics_process(delta: float) -> void:
	advance(delta)
	if body:
		body.position.y = sin(Time.get_ticks_msec() * 0.001 * 3.0) * 0.04 if active else 0.0

func update_visuals() -> void:
	if body:
		body.visible = active and mode != "burrow_windup"
		body.rotation.z = -0.42 * (1.0 - phase_remaining / 0.72) if mode == "sweep_windup" else (0.54 * phase_remaining / 2.25 if mode == "recover" else 0.0)
	if moving_mound:
		moving_mound.visible = active and mode == "burrow_windup"
	if warning_ring:
		warning_ring.visible = active and mode in ["sweep_windup", "burrow_windup", "summon_windup"]
		warning_ring.global_position = warning_position + Vector3(0, 0.05, 0) if mode == "burrow_windup" else global_position + Vector3(0, 0.05, 0)
	if caption:
		caption.text = {"sweep_windup":"横扫要来了 · 后退", "burrow_windup":"地下有动静 · 离开光圈", "summon_windup":"召来田鼠 · 留意四周", "recover":"收招中 · 快挥枝", "stagger":"它停住了 · 快组合玉米枪"}.get(mode, "荒田稻草人")
		caption.visible = active and mode != "burrow_windup"

func advance(delta: float) -> void:
	if not active or get_tree().paused:
		return
	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	var left := delta
	var steps := 0
	while left > 0.0 and steps < 5:
		steps += 1
		if phase_remaining > left:
			phase_remaining -= left
			update_burrow_position()
			break
		left -= phase_remaining
		phase_remaining = 0.0
		match mode:
			"idle":
				var names := ["sweep_windup", "burrow_windup", "summon_windup"]
				mode = names[skill_index % 3]
				phase_remaining = 0.72 if mode == "sweep_windup" else (1.08 if mode == "burrow_windup" else 1.05)
				warning_position = player_position if mode == "burrow_windup" else global_position
				if mode == "burrow_windup":
					burrow_start = position
					burrow_edge = Vector3(-7.2 if player_position.x >= 0 else 7.2, 0, -34)
					burrow_target = Vector3(clampf(player_position.x, -6.5, 6.5), 0, clampf(player_position.z, -41, -28))
					collision_layer = 0
				skill_warned.emit(mode)
			"sweep_windup", "burrow_windup", "summon_windup":
				if mode == "burrow_windup":
					position = burrow_target
					collision_layer = 4
				if mode == "summon_windup":
					summon_requested.emit()
				elif mode == "sweep_windup" and horizontal_distance(player_position, global_position) < 2.3:
					strike_attempt.emit()
				elif mode == "burrow_windup" and horizontal_distance(player_position, warning_position) < 1.8:
					strike_attempt.emit()
				mode = "recover"
				phase_remaining = 2.25
				skill_index += 1
			"recover":
				mode = "idle"
				phase_remaining = 0.60
			"stagger":
				mode = "recover"
				phase_remaining = 2.25
			_:
				mode = "idle"
				phase_remaining = 0.6
	update_visuals()

func update_burrow_position() -> void:
	if mode != "burrow_windup":
		return
	var t := clampf(1.0 - phase_remaining / 1.08, 0.0, 1.0)
	if t < 0.48:
		position = burrow_start.lerp(burrow_edge, t / 0.48)
	else:
		position = burrow_edge.lerp(burrow_target, (t - 0.48) / 0.52)

func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func receive_hit(_direction: Vector3) -> void:
	if not active or get_tree().paused or hit_cooldown > 0:
		return
	if mode == "recover" or mode == "stagger":
		hit_cooldown = 0.35
		hit_received.emit(1)

func receive_projectile(amount: int) -> void:
	if not active or get_tree().paused or hit_cooldown > 0:
		return
	hit_cooldown = 0.09
	hit_received.emit(amount)

func stagger_for_gun() -> void:
	mode = "stagger"
	phase_remaining = 7.0
	warning_position = global_position

func reset_boss() -> void:
	active = false
	mode = "idle"
	skill_index = 0
	phase_remaining = 2.0
	hit_cooldown = 0.0
	warning_position = HOME
	burrow_start = HOME
	burrow_edge = HOME
	burrow_target = HOME
	position = HOME
	collision_layer = 4
	if caption:
		caption.visible = false
	if body:
		body.visible = true
		body.rotation.z = 0
	if warning_ring:
		warning_ring.visible = false
	if moving_mound:
		moving_mound.visible = false
