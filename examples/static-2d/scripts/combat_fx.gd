class_name CombatFX
extends Node3D
## Small original, depth-tested world-space effects. Positions are world-space;
## slash direction is horizontal X/Z. No textures, shaders, or scene dependencies.
## Each call creates one short-lived root; at most 64 roots can coexist.

const MAX_EFFECTS: int = 64
var _effects: Array[Dictionary] = []

func spawn_slash(world_position: Vector3, direction: Vector3) -> void:
	var forward := Vector3(direction.x, 0.0, direction.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3.RIGHT
	forward = forward.normalized()
	var effect := _new_effect(world_position + Vector3.UP * 0.78, 0.24, "slash")
	var node: Node3D = effect["root"]
	node.rotation.y = -atan2(forward.z, forward.x) - 0.22
	effect["base_yaw"] = node.rotation.y
	# Two narrow tapered bands make the white core read without a large glow disc.
	_add_mesh(node, _crescent(1.28, 0.19, 1.29), Color(0.43, 0.78, 1.0, 0.66))
	var core := _add_mesh(node, _crescent(1.23, 0.105, 1.23), Color(0.96, 0.99, 1.0, 0.96))
	core.position.y = 0.008

func spawn_hit(world_position: Vector3) -> void:
	var effect := _new_effect(world_position, 0.30, "hit")
	var node: Node3D = effect["root"]
	for index in range(7):
		var angle: float = float(index) * TAU / 7.0 + 0.19
		var velocity := Vector3(cos(angle), 0.55 + float(index % 3) * 0.24, sin(angle))
		var shard := _add_mesh(node, _diamond(0.06, 0.23), Color(1.0, 0.77, 0.30, 1.0))
		shard.rotation = Vector3(0.0, -angle, -0.5 + float(index % 3) * 0.35)
		shard.set_meta("velocity", velocity * (1.3 + float(index % 2) * 0.6))
		shard.position = velocity * 0.04
	var flash := _add_mesh(node, _diamond(0.12, 0.34), Color(1.0, 0.97, 0.74, 1.0))
	flash.set_meta("velocity", Vector3.ZERO)

func spawn_dust(world_position: Vector3) -> void:
	var effect := _new_effect(world_position + Vector3.UP * 0.045, 0.42, "dust")
	var node: Node3D = effect["root"]
	for index in range(3):
		var angle: float = float(index) * TAU / 3.0 + 0.7
		var dust := _add_mesh(node, _dust_mesh(), Color(0.70, 0.60, 0.43, 0.33))
		dust.position = Vector3(cos(angle), 0.0, sin(angle)) * 0.10
		dust.rotation.y = angle
		dust.set_meta("velocity", Vector3(cos(angle), 0.13, sin(angle)) * 0.34)

func _new_effect(world_position: Vector3, lifetime: float, kind: String) -> Dictionary:
	if _effects.size() >= MAX_EFFECTS:
		var oldest: Dictionary = _effects.pop_front()
		(oldest["root"] as Node3D).queue_free()
	var node := Node3D.new()
	node.name = "FX_" + kind
	add_child(node)
	node.global_position = world_position
	var effect: Dictionary = {"root": node, "age": 0.0, "lifetime": lifetime, "kind": kind}
	_effects.append(effect)
	return effect

func _process(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect: Dictionary = _effects[index]
		var node: Node3D = effect["root"]
		effect["age"] = float(effect["age"]) + delta
		var progress: float = float(effect["age"]) / float(effect["lifetime"])
		if progress >= 1.0:
			node.queue_free()
			_effects.remove_at(index)
			continue
		if effect["kind"] == "slash":
			node.rotation.y = float(effect["base_yaw"]) + progress * 0.44
			node.scale = Vector3.ONE * (0.90 + progress * 0.17)
		for child in node.get_children():
			var mesh := child as MeshInstance3D
			var material := mesh.material_override as StandardMaterial3D
			var color: Color = mesh.get_meta("base_color")
			color.a *= 1.0 - smoothstep(0.20, 1.0, progress)
			material.albedo_color = color
			if mesh.has_meta("velocity"):
				var velocity: Vector3 = mesh.get_meta("velocity")
				mesh.position += velocity * delta
				if effect["kind"] == "hit":
					mesh.scale = Vector3.ONE * (1.0 - progress * 0.70)
				else:
					mesh.scale = Vector3.ONE * (0.8 + progress * 1.1)

func _add_mesh(parent: Node3D, geometry: ArrayMesh, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = geometry
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	# Keep normal depth testing so walls and actors can occlude effects.
	mesh.material_override = material
	mesh.set_meta("base_color", color)
	parent.add_child(mesh)
	return mesh

func _crescent(radius: float, thickness: float, half_angle: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	const SEGMENTS: int = 18
	for index in range(SEGMENTS):
		var t0: float = float(index) / float(SEGMENTS)
		var t1: float = float(index + 1) / float(SEGMENTS)
		var angle0: float = lerpf(-half_angle, half_angle, t0)
		var angle1: float = lerpf(-half_angle, half_angle, t1)
		var width0: float = sin(t0 * PI) * thickness
		var width1: float = sin(t1 * PI) * thickness
		var outer0 := Vector3(cos(angle0) * radius, 0.0, sin(angle0) * radius)
		var outer1 := Vector3(cos(angle1) * radius, 0.0, sin(angle1) * radius)
		var inner0 := Vector3(cos(angle0) * (radius - width0), 0.0, sin(angle0) * (radius - width0))
		var inner1 := Vector3(cos(angle1) * (radius - width1), 0.0, sin(angle1) * (radius - width1))
		vertices.append_array(PackedVector3Array([outer0, inner0, outer1, outer1, inner0, inner1]))
	return _mesh_from_vertices(vertices)

func _diamond(width: float, length: float) -> ArrayMesh:
	# Vertical crossed diamonds stay visible from the fixed high-oblique camera.
	var points := PackedVector3Array()
	for direction in [Vector3.RIGHT, Vector3.BACK]:
		var left: Vector3 = -direction * width
		var right: Vector3 = direction * width
		var top := Vector3.UP * length
		var bottom := Vector3.DOWN * length * 0.5
		points.append_array(PackedVector3Array([left, top, right, left, right, bottom]))
	return _mesh_from_vertices(points)

func _dust_mesh() -> ArrayMesh:
	return _mesh_from_vertices(PackedVector3Array([
		Vector3(-0.10, 0, -0.065), Vector3(0.085, 0, -0.08), Vector3(0.12, 0, 0.06),
		Vector3(-0.10, 0, -0.065), Vector3(0.12, 0, 0.06), Vector3(-0.07, 0, 0.10)]))

func _mesh_from_vertices(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
