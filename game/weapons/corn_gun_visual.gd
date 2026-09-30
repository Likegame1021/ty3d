extends Node3D
## Procedural corn launcher. Grip origin is zero; firing axis is local -Z.
## This is hand-authored procedural art, not a Meshy asset.

var muzzle: Marker3D
var _body: Node3D
var _leaves: Array[Node3D] = []
var _leaf_rest: Array[Vector3] = []
var _charge_core: MeshInstance3D
var _charge_material: StandardMaterial3D
var _charge := 0.0
var _recoil := 0.0
var _clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	reset_visual()

func _material(color: Color, unshaded := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _part(parent: Node3D, mesh: Mesh, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = at
	part.scale = size
	parent.add_child(part)
	return part

func _build() -> void:
	_body = Node3D.new()
	_body.name = "CornBody"
	add_child(_body)
	var kernel_mesh := SphereMesh.new()
	kernel_mesh.radius = 0.5
	kernel_mesh.height = 1.0
	kernel_mesh.radial_segments = 8
	kernel_mesh.rings = 4
	var cob_mat := _material(Color("cd982f"))
	var kernels: Array[StandardMaterial3D] = [_material(Color("f8cf4d")), _material(Color("eebc36")), _material(Color("ffdf69"))]
	_part(_body, kernel_mesh, Vector3(0, 0.115, -0.28), Vector3(0.27, 0.28, 0.65), cob_mat)
	# Staggered chunky kernels keep the silhouette readable at the gameplay camera.
	for row in 8:
		var angle := TAU * float(row) / 8.0
		for column in 7:
			var z := -0.035 - float(column) * 0.073 - float(row % 2) * 0.023
			var taper := 1.0 - 0.12 * absf(float(column) - 3.0) / 3.0
			var at := Vector3(cos(angle) * 0.126 * taper, 0.115 + sin(angle) * 0.132 * taper, z)
			var kernel := _part(_body, kernel_mesh, at, Vector3(0.086, 0.08, 0.085), kernels[(row + column * 2) % 3])
			kernel.rotation.z = angle
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var wood := _material(Color("795038"))
	var wood_light := _material(Color("ab7951"))
	var grip := _part(_body, box, Vector3(0, -0.03, 0.055), Vector3(0.105, 0.30, 0.13), wood)
	grip.rotation.x = -0.22
	_part(_body, box, Vector3(0.002, -0.03, 0.126), Vector3(0.07, 0.22, 0.01), wood_light).rotation.x = -0.22
	_part(_body, kernel_mesh, Vector3(0, 0.095, 0.118), Vector3(0.17, 0.18, 0.16), wood_light)
	# A dark recessed barrel and a warm wooden rim provide a clear forward end.
	var tube := CylinderMesh.new()
	tube.top_radius = 0.094
	tube.bottom_radius = 0.112
	tube.height = 0.10
	tube.radial_segments = 12
	_part(_body, tube, Vector3(0, 0.115, -0.588), Vector3.ONE, wood_light).rotation.x = PI * 0.5
	var hole := CylinderMesh.new()
	hole.top_radius = 0.067
	hole.bottom_radius = 0.067
	hole.height = 0.004
	hole.radial_segments = 12
	_part(_body, hole, Vector3(0, 0.115, -0.64), Vector3.ONE, _material(Color("302a20"))).rotation.x = PI * 0.5
	var rope := _material(Color("d7bd81"))
	for index in 3:
		var wrap := TorusMesh.new()
		wrap.inner_radius = 0.133
		wrap.outer_radius = 0.146
		wrap.rings = 16
		wrap.ring_segments = 5
		_part(_body, wrap, Vector3(0, 0.115, 0.002 + index * 0.027), Vector3(1, 1, 0.93), rope).rotation.x = PI * 0.5
	_part(_body, kernel_mesh, Vector3(0.125, 0.075, 0.035), Vector3(0.043, 0.065, 0.062), rope)
	# Three sculpted, ribbed husks leave the upper kernels visible.
	for index in 3:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0.095, 0.066)
		pivot.rotation.z = [0.12, PI - 0.12, -PI * 0.5][index]
		_body.add_child(pivot)
		_leaves.append(pivot)
		_leaf_rest.append(pivot.rotation)
		var mat := _material([Color("718f3b"), Color("88a548"), Color("52713a")][index])
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_part(pivot, _leaf_mesh(), Vector3.ZERO, Vector3.ONE, mat)
		var rib_mat := _material(Color("adc46a"))
		for rib in 3:
			var rib_part := _part(pivot, box, Vector3(0.077 + rib * 0.043, 0.016, -0.055 - rib * 0.077), Vector3(0.015, 0.012, 0.089), rib_mat)
			rib_part.rotation.y = -0.38
	_charge_material = _material(Color("fff2b0"), true)
	_charge_core = _part(_body, kernel_mesh, Vector3(0, 0.115, -0.647), Vector3(0.08, 0.08, 0.026), _charge_material)
	_charge_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.115, -0.69)
	_body.add_child(muzzle)

func _leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers := [Vector3(0.06, 0, 0.018), Vector3(0.135, 0, -0.07), Vector3(0.195, 0, -0.19), Vector3(0.19, 0, -0.32), Vector3(0.115, 0, -0.42)]
	var widths := [0.045, 0.064, 0.062, 0.041, 0.0]
	for segment in 4:
		var a: Vector3 = centers[segment]
		var b: Vector3 = centers[segment + 1]
		var wa: float = widths[segment]
		var wb: float = widths[segment + 1]
		var va := [a + Vector3(0, -wa, 0), a + Vector3(0.017, 0, 0), a + Vector3(0, wa, 0)]
		var vb := [b + Vector3(0, -wb, 0), b + Vector3(0.017, 0, 0), b + Vector3(0, wb, 0)]
		for side in 2:
			for vertex in [va[side], vb[side], va[side + 1], va[side + 1], vb[side], vb[side + 1]]:
				st.add_vertex(vertex)
	st.generate_normals()
	return st.commit()

func set_charge(ratio: float) -> void:
	_charge = clampf(ratio, 0.0, 1.0)

func kick(charged: bool) -> void:
	_recoil = 1.0 if charged else 0.50
	_charge = 0.0

func reset_visual() -> void:
	_charge = 0.0
	_recoil = 0.0
	_clock = 0.0
	if _body:
		_body.transform = Transform3D.IDENTITY
	for index in _leaves.size():
		_leaves[index].rotation = _leaf_rest[index]
	if _charge_core:
		_charge_core.visible = false

func _process(delta: float) -> void:
	_clock += delta
	_recoil = move_toward(_recoil, 0.0, delta * 5.0)
	_body.position.z = _recoil * 0.085
	_body.rotation.x = _recoil * 0.14
	for index in _leaves.size():
		var spread := (_charge * 0.13 + _recoil * 0.16) * (1.0 if index != 1 else -1.0)
		_leaves[index].rotation = _leaf_rest[index] + Vector3(0, spread, 0)
	_charge_core.visible = _charge > 0.01
	if _charge_core.visible:
		var pulse := 0.92 + sin(_clock * (13.0 + _charge * 12.0)) * 0.08
		_charge_core.scale = Vector3(0.065, 0.065, 0.025) * (0.8 + _charge * 0.8) * pulse
