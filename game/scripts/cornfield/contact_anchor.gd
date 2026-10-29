extends RefCounted
## Decorative attachment only. The imported creatures use measured body
## triangles and their existing skin bones, never collision or damage logic.
const DATA_PATH := "res://scripts/cornfield/contact_anchors.json"
const CORN_DATA_PATH := "res://scripts/cornfield/corn_contact_anchors.json"
const SURFACE_OFFSET := .015
const MAX_PRIMITIVES := 32
const MAX_INFLUENCES := 6
static var _profiles: Dictionary = {}
static var _loaded := false

func _init() -> void:
	if _loaded:
		return
	_loaded = true # Immutable, source-hash-checked art profiles per process.
	for data_path in [DATA_PATH, CORN_DATA_PATH]:
		_load_profiles(data_path)

func _load_profiles(data_path: String) -> void:
	if not FileAccess.file_exists(data_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not data is Dictionary or not data.get("species") is Dictionary:
		return
	for species in data.species:
		var profile = data.species[species]
		if not profile is Dictionary or not _valid_profile(profile):
			continue
		var path := "res://"+str(profile.input).trim_prefix("game/")
		if FileAccess.get_sha256(path) != str(profile.input_sha256):
			continue # Changed art must regenerate its body-triangle evidence.
		var anchors: Array[Dictionary] = []
		for record: Dictionary in profile.anchors:
			var influences: Array[Dictionary] = []
			for influence: Dictionary in record.influences:
				influences.append({"bone":str(influence.bone),"weight":float(influence.weight),"local":_vector(influence.weighted_local)})
			anchors.append({"direction":_vector(record.direction),"influences":influences})
		_profiles[path] = anchors

static func _vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

static func _valid_vector(value) -> bool:
	if not value is Array or value.size()!=3:
		return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return false
	return true

static func _valid_profile(profile: Dictionary) -> bool:
	if not profile.get("input") is String or not profile.get("input_sha256") is String or not profile.get("anchors") is Array or profile.anchors.size()!=32:
		return false
	for record in profile.anchors:
		if not record is Dictionary or not _valid_vector(record.get("direction")) or not record.get("influences") is Array:
			return false
		if record.influences.is_empty() or record.influences.size()>MAX_INFLUENCES or absf(_vector(record.direction).length()-1.0)>.0001:
			return false
		var weight := 0.0
		for influence in record.influences:
			if not influence is Dictionary or not influence.get("bone") is String or not _valid_vector(influence.get("weighted_local")):
				return false
			var amount = influence.get("weight")
			if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount)<0:
				return false
			weight += float(amount)
		if absf(weight-1.0)>.00001:
			return false
	return true

func resolve(source, at: Vector3, direction: Vector3) -> Vector3:
	if not is_instance_valid(source) or not source is Node3D:
		return at+Vector3.UP*.28
	var visual = source.get("visual")
	if not is_instance_valid(visual) or not visual is Node3D:
		return at+Vector3.UP*.28
	var outward := -Vector3(direction.x,0,direction.z).normalized()
	if outward.is_zero_approx():
		outward = Vector3.BACK
	var point := _skinned_point(source,visual,outward)
	if not point.is_finite():
		point = _primitive_point(visual,outward)
	return point+outward*SURFACE_OFFSET if point.is_finite() else at+Vector3.UP*.28

func _skinned_point(source, visual: Node3D, outward: Vector3) -> Vector3:
	# A requested variant can fail and install the original scene instead.
	# Select only the successfully installed, source-hash-checked art identity.
	if not source.get_property_list().any(func(property):return property.name=="_rigged_visual"):
		return Vector3.INF
	var adapter = source.get("_rigged_visual")
	if not is_instance_valid(adapter):
		return Vector3.INF
	var model = adapter.get("model")
	if not is_instance_valid(model) or not model is Node3D:
		return Vector3.INF
	var asset_path := str(model.scene_file_path)
	if not _profiles.has(asset_path):
		return Vector3.INF
	var skeletons := visual.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():
		return Vector3.INF
	var skeleton: Skeleton3D = skeletons[0]
	var local := skeleton.global_basis.inverse()*outward
	local.y = 0
	local = local.normalized()
	var selected: Dictionary = {}
	var best := -INF
	for anchor: Dictionary in _profiles[asset_path]:
		var score: float = local.dot(anchor.direction)
		if score > best:
			best = score
			selected = anchor
	if selected.is_empty():
		return Vector3.INF
	var point := Vector3.ZERO
	for influence: Dictionary in selected.influences:
		var index := skeleton.find_bone(influence.bone)
		if index < 0:
			return Vector3.INF
		var pose := skeleton.get_bone_global_pose(index)
		point += pose.basis*Vector3(influence.local)+pose.origin*float(influence.weight)
	return skeleton.global_transform*point

func _primitive_point(visual: Node3D, outward: Vector3) -> Vector3:
	var parts: Array[MeshInstance3D] = []
	var centre := Vector3.ZERO
	var largest := -1.0
	var extent := 1.0
	for item in visual.find_children("*","MeshInstance3D",true,false):
		var part: MeshInstance3D = item
		if not part.is_visible_in_tree() or not (part.mesh is SphereMesh or part.mesh is BoxMesh):
			continue
		parts.append(part)
		var box := part.mesh.get_aabb()
		var volume := box.size.x*box.size.y*box.size.z*absf(part.global_basis.determinant())
		if volume > largest:
			largest = volume
			centre = part.global_transform*box.get_center()
		extent = maxf(extent,(part.global_transform*box).size.length())
		if parts.size() >= MAX_PRIMITIVES:
			break
	if parts.is_empty():
		return Vector3.INF
	var begin := centre+outward*extent*2.0
	var end := centre-outward*extent*2.0
	var nearest := Vector3.INF
	var distance := INF
	for part in parts:
		var inverse := part.global_transform.affine_inverse()
		var local_begin := inverse*begin
		var local_end := inverse*end
		var hit: Variant
		if part.mesh is SphereMesh:
			var sphere: SphereMesh = part.mesh
			var radius := Vector3(sphere.radius,sphere.height*.5,sphere.radius)
			if radius.x<=.00001 or radius.y<=.00001:
				continue
			var start := local_begin/radius
			var ray := (local_end-local_begin)/radius
			var a := ray.dot(ray)
			var b := 2.0*start.dot(ray)
			var c := start.dot(start)-1.0
			var discriminant := b*b-4.0*a*c
			if a>.000001 and discriminant>=0:
				var fraction := (-b-sqrt(discriminant))/(2.0*a)
				if fraction>=0 and fraction<=1:
					hit = local_begin.lerp(local_end,fraction)
		else:
			hit = part.mesh.get_aabb().intersects_segment(local_begin,local_end)
		if hit is Vector3:
			var world: Vector3 = part.global_transform*hit
			var candidate := begin.distance_squared_to(world)
			if candidate < distance:
				distance = candidate
				nearest = world
	return nearest
