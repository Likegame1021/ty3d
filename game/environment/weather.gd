extends Node3D
## Local weather volume follows the player; it never covers the HUD canvas.

var mode := "sunny"
var night := false
var _time := 0.0
var _player_position := Vector3.ZERO
var _rain: MultiMeshInstance3D
var _snow: MultiMeshInstance3D
var _rain_material: ShaderMaterial
var _snow_material: ShaderMaterial
var _sound: AudioStreamPlayer
var _rain_sound: AudioStreamWAV
var _snow_sound: AudioStreamWAV
var _audio_enabled := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_audio_enabled = DisplayServer.get_name() != "headless"
	_build_particles()
	_build_audio()
	set_weather(mode)

func set_player_position(world_position: Vector3) -> void:
	_player_position = world_position
	position = Vector3(world_position.x, 0, world_position.z)

func set_night(value: bool) -> void:
	night = value
	if _rain_material != null:
		_rain_material.set_shader_parameter("night", 1.0 if value else 0.0)
		_snow_material.set_shader_parameter("night", 1.0 if value else 0.0)

func set_weather(value: String) -> void:
	mode = value if value in ["sunny", "rain", "snow"] else "sunny"
	if _rain == null:
		return
	_rain.visible = mode == "rain"
	_snow.visible = mode == "snow"
	_sound.stop()
	_sound.stream = null
	if _audio_enabled and mode != "sunny":
		_sound.stream = _rain_sound if mode == "rain" else _snow_sound
		_sound.volume_db = -29.0 if mode == "rain" else -34.0
		_sound.play()

func reset_weather() -> void:
	_time = 0.0
	set_weather("sunny")
	_update_time()

func _process(delta: float) -> void:
	_time += delta
	_update_time()

func _update_time() -> void:
	_rain_material.set_shader_parameter("animation_time", _time)
	_snow_material.set_shader_parameter("animation_time", _time)

func _build_particles() -> void:
	var shader := load("res://environment/weather_precip.gdshader")
	var random := RandomNumberGenerator.new()
	random.seed = 928204
	for kind in ["rain", "snow"]:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.035, 0.72) if kind == "rain" else Vector2(0.085, 0.095)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("snow", 0.0 if kind == "rain" else 1.0)
		mesh.material = material
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = 340 if kind == "rain" else 175
		multi.custom_aabb = AABB(Vector3(-14, -1, -14), Vector3(28, 11, 28))
		for i in multi.instance_count:
			var spot := Vector3(random.randf_range(-13, 13), 8.2, random.randf_range(-13, 13))
			var tilt := Basis(Vector3.UP, random.randf_range(-0.6, 0.6))
			multi.set_instance_transform(i, Transform3D(tilt, spot))
			multi.set_instance_custom_data(i, Color(random.randf(), random.randf(), 0, 1))
		var node := MultiMeshInstance3D.new()
		node.name = "LocalRain" if kind == "rain" else "LocalSnow"
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		if kind == "rain":
			_rain = node
			_rain_material = material
		else:
			_snow = node
			_snow_material = material

func _noise_stream(seed_value: int, airy: bool) -> AudioStreamWAV:
	var rate := 22050
	var count := rate
	var data := PackedByteArray()
	data.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var previous := 0.0
	for i in count:
		var noise := random.randf_range(-1.0, 1.0)
		var value := (noise - previous) * (0.13 if airy else 0.28)
		previous = lerpf(previous, noise, 0.42)
		if airy:
			value *= 0.7 + sin(float(i) / rate * 8.0) * 0.2
		data.encode_s16(i * 2, int(clampf(value, -1, 1) * 20000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream

func _build_audio() -> void:
	_rain_sound = _noise_stream(203, false)
	_snow_sound = _noise_stream(207, true)
	_sound = AudioStreamPlayer.new()
	_sound.name = "QuietWeatherAmbience"
	_sound.tree_exiting.connect(_release_audio)
	add_child(_sound)

func _release_audio() -> void:
	if is_instance_valid(_sound):
		_sound.stop()
		_sound.stream = null

func _exit_tree() -> void:
	_release_audio()
	_rain_sound = null
	_snow_sound = null
