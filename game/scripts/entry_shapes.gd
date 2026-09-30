extends RefCounted

static func material(color: Color, emission := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.92
	if emission:
		result.emission_enabled = true
		result.emission = color * 0.45
	return result

static func part(parent: Node3D, mesh: Mesh, position: Vector3, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = material(color)
	result.position = position
	parent.add_child(result)
	return result

static func sphere(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var result := part(parent, mesh, position, color)
	result.scale = size
	return result

static func box(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return part(parent, mesh, position, color)

static func caption(parent: Node3D, text: String, height: float, color := Color("fff2c9")) -> Label3D:
	var result := Label3D.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	result.font = font
	result.text = text
	result.font_size = 38
	result.pixel_size = 0.006
	result.outline_size = 8
	result.outline_modulate = Color("273229")
	result.modulate = color
	result.position.y = height
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(result)
	return result

static func ring(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.02
	mesh.outer_radius = radius + 0.02
	var result := part(parent, mesh, Vector3(0, 0.035, 0), color)
	result.material_override = material(color, true)
	return result
