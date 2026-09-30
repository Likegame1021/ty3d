extends StaticBody3D

const Shapes = preload("res://scripts/entry_shapes.gd")
var active := true
var health := 24
var reset_time := 0.0
var wobble := 0.0
var figure: Node3D
var caption: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 4
	add_to_group("full_enemies")
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.4
	collider.shape = shape
	collider.position.y = 0.7
	add_child(collider)
	figure = Node3D.new()
	add_child(figure)
	Shapes.box(figure, Vector3(0, 0.46, 0), Vector3(0.12, 0.92, 0.13), Color("866044"))
	Shapes.box(figure, Vector3(0, 0.07, 0), Vector3(0.8, 0.14, 0.5), Color("6a4e39"))
	for data in [[0.45, 0.0, "c9a16b"], [0.31, 0.085, "477762"], [0.16, 0.12, "f2ca64"]]:
		var disc := CylinderMesh.new()
		disc.top_radius = data[0]
		disc.bottom_radius = data[0]
		disc.height = 0.1
		disc.radial_segments = 24
		var node := Shapes.part(figure, disc, Vector3(0, 0.95, data[1]), Color(data[2]))
		node.rotation.x = PI * 0.5
	caption = Shapes.caption(self, "木靶 · 24", 1.65, Color("fff0bf"))
	caption.font_size = 28

func _process(delta: float) -> void:
	wobble = move_toward(wobble, 0.0, delta * 3.0)
	figure.rotation.z = sin(wobble * 21.0) * wobble * 0.12
	if reset_time > 0:
		reset_time -= delta
		figure.rotation.x = lerpf(figure.rotation.x, -0.9, delta * 9.0)
		if reset_time <= 0:
			reset_target()

func receive_projectile(amount: int) -> void:
	if not active or get_tree().paused:
		return
	health = maxi(0, health - amount)
	wobble = 1.0
	caption.text = "木靶 · %d" % health
	if health == 0:
		active = false
		reset_time = 1.2
		caption.text = "击倒！"

func receive_hit(_direction: Vector3) -> void:
	receive_projectile(1)

func reset_target() -> void:
	health = 24
	active = true
	reset_time = 0
	wobble = 0
	figure.rotation = Vector3.ZERO
	caption.text = "木靶 · 24"
