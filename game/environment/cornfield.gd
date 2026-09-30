extends Node3D
## Self-contained field; gameplay owns the player and practice target.
var _player_position := Vector3(1000, 0, 1000)
var _night := false
var _time := 0.0
var _corn_materials: Array[ShaderMaterial] = []
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _environment: Environment
var _rng := RandomNumberGenerator.new()
var corn_instance_count := 0

func _ready() -> void:
	_rng.seed = 207829
	_build_lighting()
	_build_ground()
	_build_corn()
	_build_props()
	set_night(_night)

func set_player_position(world_position: Vector3) -> void:
	_player_position = world_position

func set_night(enabled: bool) -> void:
	_night = enabled
	if _sun == null:
		return
	_sun.light_color = Color("9eb9ed") if enabled else Color("ffe7c5")
	_sun.light_energy = 0.32 if enabled else 0.68
	_fill.light_energy = 0.11 if enabled else 0.10
	_environment.background_color = Color("172438") if enabled else Color("a5c4cb")
	_environment.ambient_light_color = Color("8dadd6") if enabled else Color("f2dfbd")
	_environment.ambient_light_energy = 0.23 if enabled else 0.30
	for material in _corn_materials:
		material.set_shader_parameter("night", 1.0 if enabled else 0.0)

func _process(delta: float) -> void:
	_time += delta
	var hidden_source := Vector3(-6.5 + sin(_time * 0.47) * 2.1, 0, -2.0 + cos(_time * 0.38) * 4.5)
	for material in _corn_materials:
		material.set_shader_parameter("animation_time", _time)
		material.set_shader_parameter("player_position", _player_position)
		material.set_shader_parameter("disturbance_position", hidden_source)

func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	world.name = "RuralAtmosphere"
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = _environment
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.rotation_degrees = Vector3(-52, -35, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 45
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-32, 140, 0)
	_fill.light_color = Color("b4cad7")
	add_child(_fill)

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 0.3, 34)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = -0.15
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	mesh.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = load("res://environment/soil.gdshader")
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	# Invisible perimeter collision, separate from decorative rail instances.
	for wall in [Vector4(-14.5, 0, 0.25, 33), Vector4(14.5, 0, 0.25, 33), Vector4(0, -16.5, 29, 0.25), Vector4(0, 16.5, 29, 0.25)]:
		var border := CollisionShape3D.new()
		var border_shape := BoxShape3D.new()
		border_shape.size = Vector3(wall.z, 2.5, wall.w)
		border.shape = border_shape
		border.position = Vector3(wall.x, 1.0, wall.y)
		body.add_child(border)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

func _build_corn() -> void:
	var scene := load("res://assets/environment/corn.glb") as PackedScene
	if scene == null:
		push_error("Corn GLB unavailable")
		return
	var source := scene.instantiate()
	var source_mesh := _find_mesh(source)
	if source_mesh == null:
		source.free()
		return
	var mesh := source_mesh.mesh.duplicate() as ArrayMesh
	for surface in range(mesh.get_surface_count()):
		var original := mesh.surface_get_material(surface) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = load("res://environment/corn.gdshader")
		material.set_shader_parameter("base_color", original.albedo_color if original != null else Color("526b16"))
		mesh.surface_set_material(surface, material)
		_corn_materials.append(material)
	source.free()
	var plots := Node3D.new()
	plots.name = "CornPlots"
	add_child(plots)
	# 4 m plots retain culling granularity; no individual corn physics bodies.
	for side in [-1, 1]:
		for column in range(3):
			for row in range(7):
				var center := Vector3(side * (3.7 + column * 3.5), 0, -12.0 + row * 4.0)
				var transforms: Array[Transform3D] = []
				for x in range(5):
					for z in range(7):
						var pos := center + Vector3((x - 2) * 0.63 + _rng.randf_range(-0.09, 0.09), 0, (z - 3) * 0.54 + _rng.randf_range(-0.09, 0.09))
						# Widen the practice clearing and southern entrance.
						if absf(pos.x) < 4.0 and (absf(pos.z + 5) < 2.8 or pos.z > 6.0):
							continue
						var scale_value := _rng.randf_range(0.83, 1.06)
						var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3(scale_value, scale_value, scale_value))
						transforms.append(Transform3D(basis, pos - center))
				var multi := MultiMesh.new()
				multi.transform_format = MultiMesh.TRANSFORM_3D
				multi.use_custom_data = true
				multi.mesh = mesh
				multi.instance_count = transforms.size()
				multi.custom_aabb = AABB(Vector3(-2.4, -0.1, -2.5), Vector3(4.8, 3.1, 5.0))
				var instance_colors: Array[Color] = []
				for i in range(transforms.size()):
					multi.set_instance_transform(i, transforms[i])
					var instance_color := Color(_rng.randf(), _rng.randf(), 0, 1)
					instance_colors.append(instance_color)
					multi.set_instance_custom_data(i, instance_color)
				multi.set_meta("source_transforms", transforms)
				multi.set_meta("source_colors", instance_colors)
				var instance := MultiMeshInstance3D.new()
				instance.name = "Plot_%s_%s_%s" % [side, column, row]
				instance.multimesh = multi
				instance.position = center
				plots.add_child(instance)
				corn_instance_count += transforms.size()

func _prop(asset: String, position_value: Vector3, yaw: float = 0.0, size_value: float = 1.0) -> Node3D:
	var scene := load("res://assets/environment/%s.glb" % asset) as PackedScene
	if scene == null:
		return null
	var prop := scene.instantiate() as Node3D
	prop.position = position_value
	prop.rotation.y = yaw
	prop.scale = Vector3.ONE * size_value
	add_child(prop)
	# Major rural props block movement with simple geometry, never mesh triangles.
	if asset in ["crate", "jar", "haystack", "tree"]:
		var body := StaticBody3D.new()
		body.name = "SimplePropCollision"
		body.collision_layer = 1
		body.collision_mask = 2
		var collider := CollisionShape3D.new()
		if asset == "crate":
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.74, 0.74, 0.74)
			collider.shape = shape
			collider.position.y = 0.37
		else:
			var shape := CylinderShape3D.new()
			shape.radius = 0.18 if asset == "tree" else (0.30 if asset == "jar" else 0.52)
			shape.height = 2.1 if asset == "tree" else (0.72 if asset == "jar" else 1.05)
			collider.shape = shape
			collider.position.y = shape.height * 0.5
		body.add_child(collider)
		prop.add_child(body)
	return prop

func _build_props() -> void:
	for z in range(-14, 16, 2):
		_prop("fence", Vector3(-13.8, 0, z), PI / 2)
		_prop("fence", Vector3(13.8, 0, z), PI / 2)
	for x in range(-12, 14, 2):
		_prop("fence", Vector3(x, 0, -15.7))
		if abs(x) > 2:
			_prop("fence", Vector3(x, 0, 15.7))
	for pos in [Vector3(4.0, 0, 10.8), Vector3(5.1, 0, 11.1), Vector3(-4.2, 0, -6.7)]:
		_prop("haystack", pos, _rng.randf_range(0, PI), _rng.randf_range(0.85, 1.15))
	_prop("crate", Vector3(3.2, 0, 8.5), 0.18)
	_prop("crate", Vector3(3.9, 0, 8.7), -0.15, 0.8)
	_prop("jar", Vector3(3.2, 0, 9.6), 0.5)
	_prop("jar", Vector3(-3.6, 0, -7.4), 0, 0.8)
	for i in range(24):
		var side := -1.0 if i % 2 == 0 else 1.0
		_prop("rocks", Vector3(side * _rng.randf_range(1.7, 2.2), -0.08, _rng.randf_range(-14, 14)), _rng.randf_range(0, PI), _rng.randf_range(0.35, 0.65))


	for pos in [Vector3(-12.5, 0, 13.0), Vector3(12.5, 0, -13.0), Vector3(-12.6, 0, -13.1)]:
		_prop("tree", pos, _rng.randf_range(0, PI), 1.15)
	for i in range(90):
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := _rng.randf_range(-14.8, 15.0)
		var x := side * (_rng.randf_range(1.6, 2.0) if i < 40 else _rng.randf_range(12.6, 13.5))
		_prop("grass", Vector3(x, 0, z), _rng.randf_range(0, TAU), _rng.randf_range(0.6, 1.3))




