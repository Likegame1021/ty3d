extends Node3D
## M2 five-zone environment. Gameplay owns all actors and interaction decisions.

const WeatherScript = preload("res://environment/weather.gd")
const INVALID_SOURCE := Vector3(1000, 0, 1000)
const DEFAULT_PROGRESS := {
	"mouth_cleared": false,
	"canal_open": false,
	"cart_moved": false,
	"launcher_taken": false,
	"boss_active": false,
	"corn_spilled": false,
	"boss_defeated": false,
}

var corn_instance_count := 0
var plot_count := 0
var weather := "sunny"
var night := false
var progress: Dictionary = DEFAULT_PROGRESS.duplicate()
var _player_position := INVALID_SOURCE
var _actor_sources: Array[Vector3] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _corn_materials: Array[ShaderMaterial] = []
var _ground_material: ShaderMaterial
var _water_material: ShaderMaterial
var _wetland_material: ShaderMaterial
var _seasonal_materials: Array[StandardMaterial3D] = []
var _seasonal_colors: Array[Color] = []
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _landmark_lights: Array[OmniLight3D] = []
var _atmosphere: Environment
var _weather_node: Node3D
var _gate_blocker: StaticBody3D
var _gate_visual: Node3D
var _clog_visual: Node3D
var _standing_mouth_corn: Node3D
var _fallen_mouth_corn: Node3D
var _cart_visual: Node3D
var _launcher_visual: Node3D
var _spill_visual: Node3D
var _shed_roof_visual: Node3D
var _meshy_roof_meshes: Array[MeshInstance3D] = []
var _snow_roof_overlay: StandardMaterial3D
var _meshy_cart_meshes: Array[MeshInstance3D] = []
var _snow_cart_overlay: ShaderMaterial
var _chicken_voice: AudioStreamPlayer3D
var _rustle_voice: AudioStreamPlayer3D
var _chirp_stream: AudioStream
var _rustle_stream: AudioStream
var _audio_enabled := false
var _chirp_timer := 2.0
var _rustle_timer := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 9281928
	_build_lighting()
	_build_ground()
	_build_canal()
	_build_landmarks()
	_build_corn()
	_build_farm()
	_build_boss_arena()
	_build_perimeter()
	_build_lanterns()
	_weather_node = WeatherScript.new()
	_weather_node.name = "LocalWeather"
	add_child(_weather_node)
	_build_field_audio()
	reset_field()

func set_player_position(world_position: Vector3) -> void:
	_player_position = world_position
	if _shed_roof_visual != null:
		_shed_roof_visual.visible = not (absf(world_position.x - 17.0) < 3.2 and absf(world_position.z + 18.5) < 3.2)
	if _weather_node != null:
		_weather_node.set_player_position(world_position)

func set_actor_sources(sources: Array[Vector3]) -> void:
	_actor_sources = sources.slice(0, 4)
	if _chicken_voice != null and not _actor_sources.is_empty() and _actor_sources[0] != INVALID_SOURCE:
		_chicken_voice.global_position = _actor_sources[0] + Vector3.UP * 0.6
	_update_corn_parameters()

func set_night(value: bool) -> void:
	night = value
	if _sun == null:
		return
	_update_lighting()
	_update_materials()
	_weather_node.set_night(value)

func set_weather(value: String) -> void:
	weather = value if value in ["sunny", "rain", "snow"] else "sunny"
	if _weather_node == null:
		return
	_weather_node.set_weather(weather)
	_update_lighting()
	_update_materials()

func set_progress(state: Dictionary) -> void:
	for key in DEFAULT_PROGRESS:
		if state.has(key):
			progress[key] = bool(state[key])
	if _gate_blocker == null:
		return
	var open: bool = progress.canal_open
	_gate_blocker.collision_layer = 0 if open else 1
	_gate_visual.visible = not open
	_clog_visual.visible = not (progress.mouth_cleared or open)
	_standing_mouth_corn.visible = not open
	_fallen_mouth_corn.visible = open
	_cart_visual.position = Vector3(19.1, 0, -13.4) if progress.cart_moved else Vector3(16, 0, -13)
	_launcher_visual.visible = not progress.launcher_taken
	_spill_visual.visible = progress.corn_spilled
	_update_materials()

func reset_field() -> void:
	_time = 0.0
	_chirp_timer = 2.0
	_rustle_timer = 1.0
	_chicken_voice.stop()
	_rustle_voice.stop()
	_actor_sources.clear()
	_player_position = INVALID_SOURCE
	_shed_roof_visual.visible = true
	progress = DEFAULT_PROGRESS.duplicate()
	set_progress(progress)
	set_weather("sunny")
	set_night(false)
	_weather_node.reset_weather()
	_update_corn_parameters()
	_update_materials()

func _process(delta: float) -> void:
	_time += delta
	_update_field_audio(delta)
	_update_corn_parameters()
	if _ground_material != null:
		_ground_material.set_shader_parameter("animation_time", _time)
		_water_material.set_shader_parameter("animation_time", _time)
		_wetland_material.set_shader_parameter("animation_time", _time)

func _update_corn_parameters() -> void:
	var values: Array[Vector3] = [INVALID_SOURCE, INVALID_SOURCE, INVALID_SOURCE, INVALID_SOURCE]
	for i in mini(4, _actor_sources.size()):
		values[i] = _actor_sources[i]
	for material in _corn_materials:
		material.set_shader_parameter("animation_time", _time)
		material.set_shader_parameter("player_position", _player_position)
		material.set_shader_parameter("source_a", values[0])
		material.set_shader_parameter("source_b", values[1])
		material.set_shader_parameter("source_c", values[2])
		material.set_shader_parameter("source_d", values[3])

func _update_materials() -> void:
	var weather_value := 0.0 if weather == "sunny" else (1.0 if weather == "rain" else 2.0)
	_ground_material.set_shader_parameter("weather_mode", weather_value)
	_ground_material.set_shader_parameter("night", 1.0 if night else 0.0)
	_water_material.set_shader_parameter("weather_mode", weather_value)
	_water_material.set_shader_parameter("night", 1.0 if night else 0.0)
	_water_material.set_shader_parameter("flowing", 1.0 if progress.canal_open else 0.0)
	_wetland_material.set_shader_parameter("mouth_cleared", 1.0 if progress.mouth_cleared or progress.canal_open else 0.0)
	_wetland_material.set_shader_parameter("flowing", 1.0 if progress.canal_open else 0.0)
	_wetland_material.set_shader_parameter("weather_mode", weather_value)
	_wetland_material.set_shader_parameter("night", 1.0 if night else 0.0)
	for material in _corn_materials:
		material.set_shader_parameter("weather_mode", weather_value)
		material.set_shader_parameter("night", 1.0 if night else 0.0)
	for i in _seasonal_materials.size():
		_seasonal_materials[i].albedo_color = _seasonal_colors[i].lerp(Color("dce8e7"), 0.72) if weather == "snow" else _seasonal_colors[i]
	for roof_mesh in _meshy_roof_meshes:
		roof_mesh.material_overlay = _snow_roof_overlay if weather == "snow" else null
	for cart_mesh in _meshy_cart_meshes:
		cart_mesh.material_overlay = _snow_cart_overlay if weather == "snow" else null

func _update_lighting() -> void:
	var rain := weather == "rain"
	var snow := weather == "snow"
	_sun.light_color = Color("a9bfda") if night else (Color("bfcbd0") if rain else Color("f2ead8") if snow else Color("ffe4b8"))
	_sun.light_energy = 0.34 if night else (0.46 if rain else 0.58 if snow else 0.70)
	_fill.light_energy = 0.15 if night else (0.17 if rain or snow else 0.12)
	_atmosphere.background_color = Color("18243a") if night else (Color("879ca7") if rain else Color("d5dde2") if snow else Color("a8c5c8"))
	_atmosphere.ambient_light_color = Color("9bb7d9") if night else (Color("c7d1d4") if rain else Color("edf0ec") if snow else Color("ead9bc"))
	_atmosphere.ambient_light_energy = 0.27 if night else (0.32 if rain else 0.31 if snow else 0.38)
	for lamp in _landmark_lights:
		lamp.light_energy = 1.10 if night else (0.38 if rain or snow else 0.10)

func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	world.name = "FullFieldAtmosphere"
	_atmosphere = Environment.new()
	_atmosphere.background_mode = Environment.BG_COLOR
	_atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = _atmosphere
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.rotation_degrees = Vector3(-52, -37, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 42
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-32, 137, 0)
	_fill.light_color = Color("b4cad7")
	add_child(_fill)

func _material(color: Color, roughness := 0.9, seasonal_top := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if seasonal_top:
		_seasonal_materials.append(material)
		_seasonal_colors.append(color)
	return material

func _box(parent: Node3D, label: String, pos: Vector3, size: Vector3, color: Color, seasonal_top := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color, 0.91, seasonal_top)
	node.position = pos
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, label: String, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	parent.add_child(node)
	return node

func _collision_box(parent: Node3D, label: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = pos
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body

func _build_ground() -> void:
	var body := _collision_box(self, "FullGround", Vector3(0, -0.16, 0), Vector3(56, 0.32, 96))
	var surface := MeshInstance3D.new()
	surface.name = "SoilAndRoad"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(160, 180)
	surface.mesh = mesh
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://environment/full_soil.gdshader")
	surface.material_override = _ground_material
	surface.position.y = 0.16
	body.add_child(surface)

func _build_canal() -> void:
	var zone := Node3D.new()
	zone.name = "CanalCrossing"
	add_child(zone)
	var water := MeshInstance3D.new()
	water.name = "CanalWater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(55.5, 3.4)
	water.mesh = plane
	water.position = Vector3(0, 0.035, 19)
	_water_material = ShaderMaterial.new()
	_water_material.shader = load("res://environment/full_water.gdshader")
	water.material_override = _water_material
	zone.add_child(water)
	var wetland := MeshInstance3D.new()
	wetland.name = "MuddyWetland"
	var wet_mesh := PlaneMesh.new()
	wet_mesh.size = Vector2(10.0, 6.0)
	wetland.mesh = wet_mesh
	wetland.position = Vector3(0, 0.044, 23.1)
	_wetland_material = ShaderMaterial.new()
	_wetland_material.shader = load("res://environment/full_wetland.gdshader")
	wetland.material_override = _wetland_material
	zone.add_child(wetland)
	for z in [17.15, 20.85]:
		_box(zone, "MuddyCanalBank", Vector3(0, 0.10, z), Vector3(55.5, 0.20, 0.55), Color("6b5736"))
	# The two solid spans reach the perimeter; only the bridge gate can open.
	_collision_box(zone, "WestCanalBarrier", Vector3(-12.4, 0.72, 19), Vector3(31.2, 1.44, 3.5))
	_collision_box(zone, "EastCanalBarrier", Vector3(17.4, 0.72, 19), Vector3(21.2, 1.44, 3.5))
	_gate_blocker = _collision_box(zone, "CanalGateBlocker", Vector3(5, 0.72, 19), Vector3(3.7, 1.44, 3.5))
	for x in range(-27, 28, 2):
		if absf(float(x) - 5.0) < 2.8:
			continue
		var rock := _box(zone, "StoneCanalRim", Vector3(x, 0.38, 19), Vector3(1.8, 0.75, 3.3), Color("756f5d"))
		rock.rotation.y = _rng.randf_range(-0.08, 0.08)
	for z in range(17, 22):
		_box(zone, "BridgePlank", Vector3(5, 0.13, z), Vector3(3.9, 0.20, 0.72), Color("8b6540"), true)
	for x in [3.0, 7.0]:
		for z in [17.1, 20.9]:
			_cylinder(zone, "BridgePost", Vector3(x, 0.65, z), 0.10, 1.3, Color("715030"))
	_gate_visual = Node3D.new()
	_gate_visual.name = "ClosedCanalGate"
	zone.add_child(_gate_visual)
	for x in [3.7, 4.4, 5.1, 5.8, 6.5]:
		_box(_gate_visual, "GatePicket", Vector3(x, 0.75, 19), Vector3(0.16, 1.5, 0.22), Color("684a2a"))
	_box(_gate_visual, "GateCrossbar", Vector3(5, 1.13, 19), Vector3(3.1, 0.14, 0.27), Color("a17a49"))
	# A visible clogged water mouth and lever stand; interaction targets belong to gameplay.
	_clog_visual = Node3D.new()
	_clog_visual.name = "WaterMouthClog"
	zone.add_child(_clog_visual)
	for i in 7:
		var stone := _box(_clog_visual, "CloggedWaterStones", Vector3(_rng.randf_range(-1.1, 1.1), 0.22, 21.9 + _rng.randf_range(-0.5, 0.5)), Vector3(_rng.randf_range(0.35, 0.75), 0.4, 0.4), Color("79745f"))
		stone.rotation.y = _rng.randf_range(0, TAU)
	_standing_mouth_corn = Node3D.new()
	_standing_mouth_corn.name = "StandingMouthCorn"
	zone.add_child(_standing_mouth_corn)
	_fallen_mouth_corn = Node3D.new()
	_fallen_mouth_corn.name = "FlattenedMouthCorn"
	zone.add_child(_fallen_mouth_corn)
	var corn_scene := load("res://assets/environment/corn.glb") as PackedScene
	if corn_scene != null:
		for x in [-2.5, -1.9, 1.9, 2.5]:
			var standing := corn_scene.instantiate() as Node3D
			standing.position = Vector3(x, 0, 23.4)
			standing.scale = Vector3.ONE * 0.85
			_standing_mouth_corn.add_child(standing)
			var fallen := corn_scene.instantiate() as Node3D
			fallen.position = Vector3(x, 0.09, 23.4)
			fallen.scale = Vector3.ONE * 0.85
			fallen.rotation.x = 1.12
			_fallen_mouth_corn.add_child(fallen)
	_cylinder(zone, "GateLeverPost", Vector3(7.7, 0.8, 21.4), 0.10, 1.6, Color("775433"))
	var lever := _box(zone, "GateLever", Vector3(7.45, 1.51, 21.4), Vector3(0.72, 0.09, 0.09), Color("a07745"))
	lever.rotation.z = -0.28

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

func _distance_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var edge := end - start
	return point.distance_to(start + edge * clampf((point - start).dot(edge) / edge.length_squared(), 0, 1))

func _plant_allowed(pos: Vector3) -> bool:
	if absf(pos.z - 19) < 4.1 or Vector2(pos.x, pos.z + 34).length() < 9.2:
		return false
	if pos.x > 10.0 and pos.z < -6.0 and pos.z > -24.0:
		return false
	if pos.z > 29 and absf(pos.x) < 7.6:
		return false
	var p := Vector2(pos.x, pos.z)
	var routes := [
		[Vector2(0, 42), Vector2(0, -29)],
		[Vector2(0, 39), Vector2(-3.5, 36)],
		[Vector2(-3.5, 36), Vector2(-5, 31)],
		[Vector2(0, 23), Vector2(5, 19)],
		[Vector2(0, 7), Vector2(-7, 9)],
		[Vector2(0, -5), Vector2(16, -15)],
		[Vector2(16, -15), Vector2(0, -27)],
	]
	for route in routes:
		if _distance_segment(p, route[0], route[1]) < 2.0:
			return false
	return true

func _build_corn() -> void:
	var scene := load("res://assets/environment/corn.glb") as PackedScene
	if scene == null:
		push_error("M2 corn mesh unavailable")
		return
	var source := scene.instantiate()
	var source_mesh := _find_mesh(source)
	if source_mesh == null:
		source.free()
		return
	var mesh := source_mesh.mesh.duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		var original := mesh.surface_get_material(surface) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = load("res://environment/full_corn.gdshader")
		material.set_shader_parameter("base_color", original.albedo_color if original != null else Color("526b16"))
		mesh.surface_set_material(surface, material)
		_corn_materials.append(material)
	source.free()
	var plots := Node3D.new()
	plots.name = "CornPlots"
	add_child(plots)
	for x in range(-25, 26, 5):
		for z in range(-45, 46, 5):
			var center := Vector3(x, 0, z)
			var stalks: Array[Transform3D] = []
			for a in 5:
				for b in 5:
					var pos := center + Vector3((a - 2) * 0.88 + _rng.randf_range(-0.15, 0.15), 0, (b - 2) * 0.88 + _rng.randf_range(-0.15, 0.15))
					if not _plant_allowed(pos):
						continue
					var scale_value := _rng.randf_range(0.82, 1.12)
					var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_value)
					stalks.append(Transform3D(basis, pos - center))
			if stalks.is_empty():
				continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_custom_data = true
			multi.mesh = mesh
			multi.instance_count = stalks.size()
			multi.custom_aabb = AABB(Vector3(-3, -0.1, -3), Vector3(6, 3.3, 6))
			for i in stalks.size():
				multi.set_instance_transform(i, stalks[i])
				multi.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), 0, 1))
			var plot := MultiMeshInstance3D.new()
			plot.name = "Corn_%s_%s" % [x, z]
			plot.multimesh = multi
			plot.position = center
			plots.add_child(plot)
			plot_count += 1
			corn_instance_count += stalks.size()

func _prop(asset: String, pos: Vector3, size_value := 1.0, yaw := 0.0) -> Node3D:
	var path := "res://assets/environment/%s.glb" % asset
	var meshy_tree := "res://assets/environment/meshy/tree.glb"
	if asset == "tree" and ResourceLoader.exists(meshy_tree):
		path = meshy_tree
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	node.position = pos
	node.scale = Vector3.ONE * size_value
	node.rotation.y = yaw
	add_child(node)
	return node

func _optional_meshy_visual(asset: String, parent: Node3D) -> Node3D:
	var path := "res://assets/environment/meshy/%s.glb" % asset
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Meshy static asset failed to import: " + path)
		return null
	var visual := scene.instantiate() as Node3D
	visual.name = "Meshy%sVisual" % asset.capitalize()
	parent.add_child(visual)
	return visual

func _build_landmarks() -> void:
	var entrance := Node3D.new()
	entrance.name = "EntranceLandmark"
	add_child(entrance)
	for x in [-2.2, 2.2]:
		_cylinder(entrance, "EntrancePost", Vector3(x, 1.0, 42), 0.13, 2.0, Color("75502e"))
	_box(entrance, "EntranceLintel", Vector3(0, 2.05, 42), Vector3(4.6, 0.16, 0.16), Color("8f6638"), true)
	var sign := _box(entrance, "BentWoodSign", Vector3(-2.2, 1.15, 37.8), Vector3(0.8, 0.28, 0.09), Color("ad844e"))
	sign.rotation.z = 0.15
	_cylinder(entrance, "SignboardStake", Vector3(-2.2, 0.56, 37.8), 0.055, 1.12, Color("765333"))
	for pos in [Vector3(-6.8, 0, 36), Vector3(-7.5, 0, 31), Vector3(6.5, 0, 35)]:
		_prop("haystack", pos, 0.8, _rng.randf_range(0, TAU))
	for pos in [Vector3(-10, 0, 40), Vector3(10, 0, 39), Vector3(-23, 0, 26), Vector3(23, 0, 26), Vector3(-24, 0, -10), Vector3(24, 0, -28)]:
		_prop("tree", pos, _rng.randf_range(1.0, 1.35), _rng.randf_range(0, TAU))
	var marker := Node3D.new()
	marker.name = "DenseCornWaymark"
	marker.position = Vector3(-7, 0, 9)
	add_child(marker)
	_cylinder(marker, "WeatheredPost", Vector3.ZERO + Vector3.UP * 0.65, 0.07, 1.3, Color("705139"))
	_box(marker, "ArrowTowardField", Vector3(0.18, 1.15, 0), Vector3(0.64, 0.17, 0.06), Color("b88e55"))
	# A low visible fence marks the vault prototype at (-5, 3); gameplay owns vault collision.
	for x in [-6.5, -5.5, -4.5, -3.5]:
		_cylinder(self, "VaultFencePost", Vector3(x, 0.35, 3), 0.07, 0.7, Color("8a663f"))
	_box(self, "VaultFenceRail", Vector3(-5, 0.48, 3), Vector3(3.2, 0.08, 0.09), Color("997445"))
	for i in 58:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := _rng.randf_range(-43, 43)
		var x := side * _rng.randf_range(3.5, 5.1)
		if _plant_allowed(Vector3(x, 0, z)):
			_prop("rocks" if i % 3 == 0 else "grass", Vector3(x, -0.05, z), _rng.randf_range(0.4, 0.8), _rng.randf_range(0, TAU))

func _build_farm() -> void:
	var farm := Node3D.new()
	farm.name = "FarmToolYard"
	add_child(farm)
	for pos in [Vector3(12, 0, -9), Vector3(10, 0, -13), Vector3(22, 0, -12)]:
		_prop("haystack", pos, 0.95, _rng.randf_range(0, TAU))
	for pos in [Vector3(11, 0, -18), Vector3(23, 0, -19)]:
		_prop("tree", pos, 1.1, _rng.randf_range(0, TAU))
	# Distinct pitched-roof tool shed with open southern face.
	var shed := Node3D.new()
	shed.name = "ToolShed"
	shed.position = Vector3(17, 0, -18.5)
	farm.add_child(shed)
	var procedural_shed := Node3D.new()
	procedural_shed.name = "ProceduralShedVisual"
	shed.add_child(procedural_shed)
	for x in [-3.2, 3.2]:
		for z in [-3.0, 3.0]:
			_box(procedural_shed, "ShedTimberPost", Vector3(x, 1.25, z), Vector3(0.19, 2.5, 0.19), Color("765537"))
	_shed_roof_visual = Node3D.new()
	_shed_roof_visual.name = "RoofVisual"
	procedural_shed.add_child(_shed_roof_visual)
	for x in [-1.65, 1.65]:
		var roof := _box(_shed_roof_visual, "SnowCatchingRoof", Vector3(x, 2.90, 0), Vector3(3.9, 0.20, 7.0), Color("786448"), true)
		roof.rotation.z = 0.34 if x < 0 else -0.34
		for row in 6:
			var seam := _box(_shed_roof_visual, "RoofBoardSeam", Vector3(x, 3.025, -2.7 + row * 1.08), Vector3(3.87, 0.025, 0.055), Color("4d4537"), true)
			seam.rotation.z = roof.rotation.z
		for row in 3:
			var weathered := _box(_shed_roof_visual, "WeatheredRoofBoard", Vector3(x, 3.014, -2.15 + row * 2.15), Vector3(3.72, 0.016, 0.34), Color("897252"), true)
			weathered.rotation.z = roof.rotation.z
	_box(_shed_roof_visual, "RoofRidge", Vector3(0, 3.48, 0), Vector3(0.22, 0.13, 7.1), Color("9d7e50"), true)
	_box(procedural_shed, "BackSlatWall", Vector3(0, 1.1, -3.0), Vector3(6.3, 2.15, 0.17), Color("93734b"))
	_collision_box(shed, "ShedBackCollision", Vector3(0, 1.1, -3.0), Vector3(6.3, 2.2, 0.22))
	for x in [-3.2, 3.2]:
		_box(procedural_shed, "ShedSideWall", Vector3(x, 0.9, 0), Vector3(0.14, 1.75, 5.5), Color("856544"))
		_collision_box(shed, "ShedSideCollision", Vector3(x, 0.95, 0), Vector3(0.20, 1.9, 5.7))
	for i in 6:
		_box(procedural_shed, "HangingToolHandle", Vector3(-2.35 + i * 0.45, 1.0, -2.75), Vector3(0.045, 1.2, 0.05), Color("ad8c5c"))
	var meshy_shed := _optional_meshy_visual("shed", shed)
	if meshy_shed != null:
		meshy_shed.rotation.y = PI
		var meshy_roof := meshy_shed.find_child("RoofVisual", true, false) as Node3D
		if meshy_roof == null:
			push_warning("Meshy shed has no RoofVisual; retaining procedural shed")
			meshy_shed.queue_free()
		else:
			procedural_shed.visible = false
			_shed_roof_visual = meshy_roof
			_snow_roof_overlay = StandardMaterial3D.new()
			_snow_roof_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_snow_roof_overlay.albedo_color = Color(0.78, 0.84, 0.86, 0.48)
			_snow_roof_overlay.roughness = 0.96
			for descendant in meshy_roof.find_children("*", "MeshInstance3D", true, false):
				_meshy_roof_meshes.append(descendant as MeshInstance3D)
	_cart_visual = Node3D.new()
	_cart_visual.name = "VisualCart"
	farm.add_child(_cart_visual)
	var procedural_cart := Node3D.new()
	procedural_cart.name = "ProceduralCartVisual"
	_cart_visual.add_child(procedural_cart)
	_box(procedural_cart, "CartBed", Vector3(0, 0.75, 0), Vector3(2.4, 0.25, 1.6), Color("7c5432"), true)
	_collision_box(_cart_visual, "CartBodyCollision", Vector3(0, 0.62, 0), Vector3(2.35, 1.10, 1.55))
	for x in [-1.0, 1.0]:
		for z in [-0.72, 0.72]:
			var wheel := _cylinder(procedural_cart, "CartWheel", Vector3(x, 0.42, z), 0.36, 0.14, Color("473d2c"))
			wheel.rotation.x = PI / 2
	for x in [-1.1, 1.1]:
		_box(procedural_cart, "CartSideRail", Vector3(x, 1.05, 0), Vector3(0.10, 0.38, 1.7), Color("927049"))
	var meshy_cart := _optional_meshy_visual("cart", _cart_visual)
	if meshy_cart != null:
		procedural_cart.visible = false
		_snow_cart_overlay = ShaderMaterial.new()
		_snow_cart_overlay.shader = load("res://environment/full_cart_snow.gdshader")
		for descendant in meshy_cart.find_children("*", "MeshInstance3D", true, false):
			_meshy_cart_meshes.append(descendant as MeshInstance3D)
	_launcher_visual = Node3D.new()
	_launcher_visual.name = "VisualOldLauncher"
	_launcher_visual.position = Vector3(17, 0, -18)
	farm.add_child(_launcher_visual)
	for x in [-0.24, 0.24]:
		var fork := _box(_launcher_visual, "LauncherFork", Vector3(x, 0.72, 0), Vector3(0.08, 1.4, 0.08), Color("80582e"))
		fork.rotation.z = 0.24 if x < 0 else -0.24
	_box(_launcher_visual, "LauncherBinding", Vector3(0, 1.25, 0), Vector3(0.43, 0.07, 0.05), Color("574332"))
	_prop("crate", Vector3(20.5, 0, -18.4), 0.95, 0.28)
	_prop("jar", Vector3(22, 0, -17), 1.1, 0.2)

func _build_boss_arena() -> void:
	var arena := Node3D.new()
	arena.name = "AbandonedHarvestRing"
	add_child(arena)
	var rim := MeshInstance3D.new()
	rim.name = "BareArenaDisc"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 8.0
	mesh.bottom_radius = 8.15
	mesh.height = 0.06
	rim.mesh = mesh
	rim.position = Vector3(0, 0.015, -34)
	rim.material_override = _material(Color("75563a"))
	arena.add_child(rim)
	for i in 14:
		var angle := TAU * i / 14.0
		var pos := Vector3(sin(angle) * 9.1, 0, -34 + cos(angle) * 9.1)
		if pos.z > -26.2 and absf(pos.x) < 3.0:
			continue
		_prop("haystack" if i % 3 == 0 else "rocks", pos, 0.8, angle)
		_cylinder(arena, "ArenaBoundaryStake", pos + Vector3.UP * 0.62, 0.065, 1.25, Color("6c4a30"))
	# Boss is spawned by gameplay; leave center clear and stage only the breakable store.
	var store := Node3D.new()
	store.name = "CornStore"
	store.position = Vector3(5, 0, -33)
	arena.add_child(store)
	for x in [-0.7, 0.7]:
		for z in [-0.55, 0.55]:
			_cylinder(store, "StorePole", Vector3(x, 0.9, z), 0.08, 1.8, Color("6e4b2e"))
	_box(store, "StoreRoof", Vector3(0, 1.95, 0), Vector3(2.3, 0.18, 1.9), Color("907349"), true)
	for i in 5:
		_box(store, "DryCornBundle", Vector3(-0.6 + i * 0.3, 0.6, 0), Vector3(0.14, 1.0, 0.16), Color("baa35b"), true)
	_spill_visual = Node3D.new()
	_spill_visual.name = "SpilledCornVisual"
	_spill_visual.position = Vector3(5, 0, -33)
	arena.add_child(_spill_visual)
	for i in 14:
		var ear := _cylinder(_spill_visual, "SpilledEar", Vector3(_rng.randf_range(-1.5, 1.5), 0.08, _rng.randf_range(-1.3, 1.3)), 0.085, 0.38, Color("ddb85d"))
		ear.rotation.z = PI / 2

func _build_perimeter() -> void:
	_collision_box(self, "WestWorldEdge", Vector3(-28.2, 1.0, 0), Vector3(0.45, 2.0, 96.5))
	_collision_box(self, "EastWorldEdge", Vector3(28.2, 1.0, 0), Vector3(0.45, 2.0, 96.5))
	_collision_box(self, "NorthWorldEdge", Vector3(0, 1.0, -48.2), Vector3(56.5, 2.0, 0.45))
	_collision_box(self, "SouthWorldEdge", Vector3(0, 1.0, 48.2), Vector3(56.5, 2.0, 0.45))
	for z in range(-46, 47, 3):
		for x in [-27.1, 27.1]:
			_prop("fence", Vector3(x, 0, z), 1.0, PI / 2)
	for x in range(-26, 27, 3):
		for z in [-47.1, 47.1]:
			_prop("fence", Vector3(x, 0, z), 1.0, 0)

func _build_lanterns() -> void:
	for pos in [Vector3(-1.8, 0, 38), Vector3(8.1, 0, 21), Vector3(-2.5, 0, 7), Vector3(12.6, 0, -15), Vector3(-6.5, 0, -32.5)]:
		var stand := Node3D.new()
		stand.name = "WarmRouteLantern"
		stand.position = pos
		add_child(stand)
		_cylinder(stand, "LanternPole", Vector3(0, 0.90, 0), 0.055, 1.8, Color("65492f"))
		_box(stand, "LampCanopy", Vector3(0, 1.99, 0), Vector3(0.40, 0.09, 0.40), Color("6e5638"), true)
		var glass := _box(stand, "AmberGlass", Vector3(0, 1.79, 0), Vector3(0.23, 0.30, 0.23), Color("e5ae65"))
		var glass_material := glass.material_override as StandardMaterial3D
		glass_material.emission_enabled = true
		glass_material.emission = Color("d79045")
		glass_material.emission_energy_multiplier = 0.90
		var lamp := OmniLight3D.new()
		lamp.name = "SmallWarmPool"
		lamp.position.y = 1.78
		lamp.light_color = Color("ffc887")
		lamp.omni_range = 8.0
		lamp.shadow_enabled = false
		stand.add_child(lamp)
		_landmark_lights.append(lamp)

func _build_field_audio() -> void:
	_audio_enabled = DisplayServer.get_name() != "headless"
	_chirp_stream = load("res://environment/entry_chirp.wav") as AudioStream
	_rustle_stream = load("res://environment/entry_rustle.wav") as AudioStream
	_chicken_voice = AudioStreamPlayer3D.new()
	_chicken_voice.name = "ChickenCueAtEntrance"
	_chicken_voice.position = Vector3(-3.5, 0.6, 36)
	_rustle_voice = AudioStreamPlayer3D.new()
	_rustle_voice.name = "MovingCornRustle"
	for voice in [_chicken_voice, _rustle_voice]:
		voice.max_distance = 11.0
		voice.unit_size = 2.0
		voice.tree_exiting.connect(_release_field_audio.bind(voice))
		add_child(voice)

func _update_field_audio(delta: float) -> void:
	_chirp_timer -= delta
	_rustle_timer -= delta
	if _chirp_timer <= 0.0:
		_chirp_timer = 6.8
		if _audio_enabled and _chirp_stream != null and not _actor_sources.is_empty() and _actor_sources[0] != INVALID_SOURCE and _player_position.distance_to(_chicken_voice.global_position) < 10.0:
			_chicken_voice.stream = _chirp_stream
			_chicken_voice.volume_db = -20.0
			_chicken_voice.play()
	if _rustle_timer <= 0.0:
		_rustle_timer = 3.0
		if not _audio_enabled or _rustle_stream == null:
			return
		var nearest := INVALID_SOURCE
		var distance_value := 10.0
		var nearest_index := 1
		for i in range(1, _actor_sources.size()):
			var source := _actor_sources[i]
			var source_distance := _player_position.distance_to(source)
			if source_distance < distance_value:
				nearest = source
				distance_value = source_distance
				nearest_index = i
		if nearest != INVALID_SOURCE:
			_rustle_voice.global_position = nearest + Vector3.UP * 0.4
			_rustle_voice.stream = _rustle_stream
			_rustle_voice.volume_db = -21.0 if nearest_index == 2 else -25.0
			_rustle_voice.play()

func _release_field_audio(voice: AudioStreamPlayer3D) -> void:
	if is_instance_valid(voice):
		voice.stop()
		voice.stream = null

func _exit_tree() -> void:
	_release_field_audio(_chicken_voice)
	_release_field_audio(_rustle_voice)
	_chirp_stream = null
	_rustle_stream = null
