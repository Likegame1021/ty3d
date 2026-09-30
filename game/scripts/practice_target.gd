extends StaticBody3D

var hit_count := 0
var figure: Node3D
var counter: Label3D
var flash: MeshInstance3D
var wobble: Tween
var ring_tween: Tween
var puff_tweens: Array[Tween] = []
var puffs: Array[MeshInstance3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("practice_targets")
	collision_layer = 1
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.45
	shape.shape = capsule
	shape.position.y = 0.72
	add_child(shape)
	figure = Node3D.new()
	add_child(figure)
	add_piece(Vector3(0.14, 1.55, 0.14), Vector3(0, 0.78, 0), Color("79553b"))
	add_piece(Vector3(1.15, 0.12, 0.12), Vector3(0, 1.15, 0), Color("a08550"))
	add_piece(Vector3(0.58, 0.55, 0.36), Vector3(0, 0.97, 0), Color("b6964e"))
	add_piece(Vector3(0.25, 0.4, 0.26), Vector3(0.18, 0.54, 0), Color("d1ad61"))
	add_piece(Vector3(0.25, 0.4, 0.26), Vector3(-0.18, 0.54, 0), Color("d1ad61"))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	var head_node := MeshInstance3D.new()
	head_node.mesh = head
	head_node.position.y = 1.5
	head_node.material_override = make_material(Color("d8b46b"))
	figure.add_child(head_node)
	add_piece(Vector3(0.58, 0.055, 0.48), Vector3(0, 1.7, 0), Color("967243"))
	for height in [0.78, 1.0, 1.17]:
		add_piece(Vector3(0.61, 0.035, 0.38), Vector3(0, height, 0), Color("846841"))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	counter = Label3D.new()
	counter.font = font
	counter.font_size = 42
	counter.pixel_size = 0.007
	counter.outline_size = 8
	counter.outline_modulate = Color("342d22")
	counter.modulate = Color("fff3bd")
	counter.position.y = 2.12
	counter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(counter)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.48
	ring.outer_radius = 0.52
	flash = MeshInstance3D.new()
	flash.mesh = ring
	flash.position.y = 0.045
	var mat := make_material(Color("f9d775"))
	mat.emission_enabled = true
	mat.emission = Color("b48a32")
	flash.material_override = mat
	add_child(flash)
	update_counter()

func make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	return material

func add_piece(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = make_material(color)
	figure.add_child(node)

func update_counter() -> void:
	counter.text = "稻草练习桩  ·  %02d" % hit_count

func receive_hit(direction: Vector3) -> void:
	if get_tree().paused:
		return
	hit_count += 1
	update_counter()
	if wobble:
		wobble.kill()
	figure.rotation = Vector3.ZERO
	flash.scale = Vector3.ONE
	wobble = create_tween()
	wobble.tween_property(figure, "rotation", Vector3(direction.z, 0, -direction.x) * 0.18, 0.07)
	wobble.tween_property(figure, "rotation", Vector3(direction.z, 0, -direction.x) * -0.1, 0.10)
	wobble.tween_property(figure, "rotation", Vector3.ZERO, 0.16)
	if ring_tween:
		ring_tween.kill()
	ring_tween = create_tween()
	ring_tween.tween_property(flash, "scale", Vector3(1.6, 1, 1.6), 0.12)
	ring_tween.tween_property(flash, "scale", Vector3.ONE, 0.22)
	spawn_hit_puffs()

func spawn_hit_puffs() -> void:
	# Free old particles/tweens first so repeated practice cannot accumulate nodes.
	clear_puffs()
	for index in 7:
		var puff := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.055
		puff.mesh = mesh
		puff.material_override = make_material(Color("eaca7b"))
		puff.position = Vector3(0, 1.15, 0)
		add_child(puff)
		puffs.append(puff)
		var angle := TAU * float(index) / 7.0
		var end := Vector3(cos(angle) * 0.7, 1.4 + sin(angle) * 0.25, sin(angle) * 0.7)
		var tween := create_tween().set_parallel(true)
		puff_tweens.append(tween)
		tween.tween_property(puff, "position", end, 0.33).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "scale", Vector3.ZERO, 0.33)
		tween.chain().tween_callback(puff.queue_free)

func clear_puffs() -> void:
	for tween in puff_tweens:
		if tween and tween.is_valid():
			tween.kill()
	puff_tweens.clear()
	for puff in puffs:
		if is_instance_valid(puff):
			puff.queue_free()
	puffs.clear()

func reset_target() -> void:
	hit_count = 0
	if wobble:
		wobble.kill()
	if ring_tween:
		ring_tween.kill()
	clear_puffs()
	figure.rotation = Vector3.ZERO
	flash.scale = Vector3.ONE
	update_counter()
