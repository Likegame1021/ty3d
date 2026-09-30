extends "res://environment/cornfield.gd"
## M1 field only: actors and objectives are owned by the level script.
var story_stage := 0
var _chicken_position := Vector3(1000,0,1000)
var _creature_position := Vector3(1000,0,1000)
var _creature_active := false
var _chirp_timer := 1.0
var _rustle_timer := 0.5
var _chicken_voice: AudioStreamPlayer3D
var _creature_voice: AudioStreamPlayer3D
var _chirp: AudioStreamWAV
var _rustle: AudioStreamWAV
var _audio_playback_enabled := false
var _lantern_material: StandardMaterial3D

func _ready() -> void:
	super._ready()
	_audio_playback_enabled = DisplayServer.get_name() != "headless"
	_configure_story_ground()
	_configure_story_corn()
	_build_gateway()
	_build_audio()
	set_story_stage(story_stage)

func _configure_story_ground() -> void:
	for child in get_node("Ground").get_children():
		if child is MeshInstance3D:
			var material := ShaderMaterial.new()
			material.shader = load("res://environment/entry_soil.gdshader")
			child.material_override = material

func _path_distance(point: Vector2) -> float:
	var result := 1000.0
	var path: Array[Vector2] = [Vector2(-1.8,9.2),Vector2(-3.8,7),Vector2(-5.5,1),Vector2(-1.7,-2.7)]
	for i in range(path.size()-1):
		var edge := path[i+1]-path[i]
		var t := clampf((point-path[i]).dot(edge)/edge.length_squared(),0,1)
		result = minf(result,point.distance_to(path[i]+edge*t))
	return result

func _configure_story_corn() -> void:
	for material in _corn_materials:
		material.shader = load("res://environment/entry_corn.gdshader")
	corn_instance_count = 0
	for plot in get_node("CornPlots").get_children():
		var multi: MultiMesh = plot.multimesh
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		var source_transforms: Array = multi.get_meta("source_transforms")
		var source_colors: Array = multi.get_meta("source_colors")
		for i in range(multi.instance_count):
			var transform: Transform3D = source_transforms[i]
			var position_value: Vector3 = transform.origin + plot.position
			# Thin path plus a small discovery pocket; the iron box is still surrounded by tall corn.
			if _path_distance(Vector2(position_value.x,position_value.z)) < 0.43 or position_value.distance_to(Vector3(-5.5,0,1)) < 0.78:
				continue
			transforms.append(transform)
			colors.append(source_colors[i])
		multi.instance_count = transforms.size()
		for i in range(transforms.size()):
			multi.set_instance_transform(i,transforms[i])
			multi.set_instance_custom_data(i,colors[i])
		multi.set_meta("source_transforms",transforms)
		multi.set_meta("source_colors",colors)
		corn_instance_count += transforms.size()

func set_story_sources(chicken_position: Vector3, creature_position: Vector3, creature_active: bool) -> void:
	_chicken_position = chicken_position
	_creature_position = creature_position
	_creature_active = creature_active
	if _chicken_voice != null:
		_chicken_voice.position = to_local(chicken_position)
		_creature_voice.position = to_local(creature_position)

func set_story_stage(stage: int) -> void:
	story_stage = clampi(stage,0,3)
	if _lantern_material != null:
		_lantern_material.emission_enabled = story_stage == 2
		_lantern_material.emission = Color("bd742f")
		_lantern_material.emission_energy_multiplier = 0.3
	if story_stage == 3 and _chicken_voice != null:
		_chicken_voice.stop()
		_creature_voice.stop()

func reset_story() -> void:
	_time = 0.0
	_chirp_timer = 1.0
	_rustle_timer = 0.5
	_chicken_position = Vector3(1000,0,1000)
	_creature_position = Vector3(1000,0,1000)
	_creature_active = false
	_player_position = Vector3(1000,0,1000)
	if _chicken_voice != null:
		_chicken_voice.stop()
		_creature_voice.stop()
	set_story_stage(0)
	_update_story_materials()

func _update_story_materials() -> void:
	for material in _corn_materials:
		material.set_shader_parameter("animation_time",_time)
		material.set_shader_parameter("player_position",_player_position)
		material.set_shader_parameter("chicken_position",_chicken_position if story_stage < 3 else Vector3(1000,0,1000))
		material.set_shader_parameter("creature_position",_creature_position)
		material.set_shader_parameter("creature_active",1.0 if _creature_active and story_stage < 3 else 0.0)

func _process(delta: float) -> void:
	# Do not call the M0 process: its independent demonstration source must not enter M1.
	_time += delta
	_update_story_materials()
	if _chicken_voice == null or story_stage == 3:
		return
	_chirp_timer -= delta
	_rustle_timer -= delta
	if _chirp_timer <= 0:
		_chirp_timer = 5.6 if story_stage == 0 else 9.0
		if _audio_playback_enabled and _chicken_position.length() < 100 and _player_position.distance_to(_chicken_position) < 11.0:
			_chicken_voice.stream = _chirp
			_chicken_voice.volume_db = -15
			_chicken_voice.play()
	if _rustle_timer <= 0:
		_rustle_timer = 2.5
		if _audio_playback_enabled and _creature_active and _player_position.distance_to(_creature_position) < 10.0:
			_creature_voice.stream = _rustle
			_creature_voice.volume_db = -13
			_creature_voice.play()
		elif _audio_playback_enabled and story_stage < 2 and _chicken_position.length() < 100 and _player_position.distance_to(_chicken_position) < 9.0:
			_chicken_voice.stream = _rustle
			_chicken_voice.volume_db = -23
			_chicken_voice.play()

func _tone(chirp: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * (0.45 if chirp else 0.75))
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var random := RandomNumberGenerator.new()
	random.seed = 701 if chirp else 702
	var previous := 0.0
	var phase := 0.0
	for i in range(count):
		var t := float(i)/sample_rate
		var noise := random.randf_range(-1,1)
		var envelope := sin(PI*float(i)/count)
		var value := (noise-previous)*0.20*envelope
		previous = lerpf(previous,noise,0.3)
		if chirp:
			var pulse := fmod(t,0.15)/0.15
			var burst := pow(sin(PI*pulse),3.0)
			phase += TAU*(1800.0+sin(t*39.0)*450.0-700.0*pulse)/sample_rate
			value = (sin(phase)*0.60+sin(phase*2)*0.10+noise*.04)*burst*envelope
		else:
			value *= .70+sin(t*27.0)*.30
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*26000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _build_audio() -> void:
	_chirp = _tone(true)
	_rustle = _tone(false)
	_chicken_voice = AudioStreamPlayer3D.new()
	_creature_voice = AudioStreamPlayer3D.new()
	for player in [_chicken_voice,_creature_voice]:
		player.max_distance = 12
		player.unit_size = 2.0
		player.attenuation_filter_cutoff_hz = 7000
		player.tree_exiting.connect(_release_audio_stream.bind(player))
		add_child(player)
	_chicken_voice.name = "ChickenSpatialCue"
	_creature_voice.name = "CreatureSpatialRustle"
	_chicken_voice.position = to_local(_chicken_position)
	_creature_voice.position = to_local(_creature_position)

func _release_audio_stream(player: AudioStreamPlayer3D) -> void:
	player.stop()
	player.stream = null

func _exit_tree() -> void:
	if is_instance_valid(_chicken_voice):
		_release_audio_stream(_chicken_voice)
	if is_instance_valid(_creature_voice):
		_release_audio_stream(_creature_voice)
	_chirp = null
	_rustle = null

func _wood_piece(parent: Node3D, position_value: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_value
	node.mesh = box
	node.position = position_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .94
	node.material_override = material
	parent.add_child(node)
	return node

func _build_gateway() -> void:
	var gate := Node3D.new()
	gate.name = "ExitGateway"
	gate.position = Vector3(0,0,-13.7)
	add_child(gate)
	for x in [-1.45,1.45]:
		_wood_piece(gate,Vector3(x,1.05,0),Vector3(.10,2.1,.11),Color("6c492a"))
	_wood_piece(gate,Vector3(0,2.12,0),Vector3(3.1,.10,.12),Color("825b34"))
	var cloth := _wood_piece(gate,Vector3(0,1.93,.03),Vector3(.70,.30,.025),Color("775543"))
	_lantern_material = cloth.material_override as StandardMaterial3D
	# Worn directional planks at the entrance and side-path split, no glowing loot locator.
	for pos in [Vector3(-1.3,0,10.7),Vector3(-2.3,0,4.8)]:
		var sign := Node3D.new()
		sign.position = pos
		add_child(sign)
		_wood_piece(sign,Vector3(0,.45,0),Vector3(.065,.9,.065),Color("6e5133"))
		_wood_piece(sign,Vector3(-.12,.73,0),Vector3(.45,.16,.04),Color("a18251"))




