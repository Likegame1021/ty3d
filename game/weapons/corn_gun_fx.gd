extends Node3D
## Bounded, Compatibility-renderer effects; tracers are cosmetic only.

const MAX_EFFECTS := 72
# Two muzzle voices preserve rapid-fire sample tails; crowd hits only recycle
# their six impact voices. The separate charge loop keeps the total cap at nine.
const MAX_SHOT_VOICES := 2
const MAX_IMPACT_VOICES := 6
const MAX_VOICES := MAX_SHOT_VOICES + MAX_IMPACT_VOICES + 1
static var _playback_refs: Dictionary = {}
static var _owned_shutdown_busy := false
var _shutdown_draining := false
var _effects: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _shot_voices: Array[AudioStreamPlayer3D] = []
var _voice_cursor := 0
var _shot_voice_cursor := 0
var _sphere: SphereMesh
var _box: BoxMesh
var _gold: StandardMaterial3D
var _white: StandardMaterial3D
var _husk: StandardMaterial3D
var _shot_sound: AudioStreamWAV
var _scatter_sound: AudioStreamWAV
var _hit_sound: AudioStreamWAV
var _charge_sound: AudioStreamWAV
var _charge_root: Node3D
var _charge_audio: AudioStreamPlayer3D
var _charge_ratio := 0.0
var _charge_clock := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("corn_audio_fx")
	_prune_playbacks()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 742198
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 8
	_sphere.rings = 4
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_gold = _mat(Color("ffd75e"))
	_white = _mat(Color("fff9d6"))
	_husk = _mat(Color("accb61"))
	# Samples are generated once. Shooting never allocates waveform data.
	_shot_sound = _synthesize(0, 0.14)
	_scatter_sound = _synthesize(1, 0.25)
	_hit_sound = _synthesize(2, 0.10)
	_charge_sound = _synthesize(3, 0.40)

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	return mat

func _part(parent: Node3D, mesh: Mesh, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.scale = size
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part

func _effect(at: Vector3, kind: String, life: float) -> Dictionary:
	while _effects.size() >= MAX_EFFECTS:
		var oldest: Dictionary = _effects.pop_front()
		if is_instance_valid(oldest.node):
			oldest.node.free()
	var node := Node3D.new()
	node.name = "Corn" + kind.capitalize()
	add_child(node)
	node.global_position = at
	var effect := {"node": node, "kind": kind, "age": 0.0, "life": life}
	_effects.append(effect)
	return effect

func _direction(direction: Vector3) -> Vector3:
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD

func _orient(node: Node3D, direction: Vector3) -> void:
	var forward := _direction(direction)
	node.look_at(node.global_position + forward, Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > 0.99 else Vector3.UP)

func muzzle_flash(at: Vector3, direction: Vector3, charged: bool) -> void:
	var effect := _effect(at, "flash", 0.12 if charged else 0.075)
	var node: Node3D = effect.node
	_orient(node, direction)
	var strength := 1.35 if charged else 1.0
	_part(node, _sphere, Vector3(0, 0, -0.12), Vector3(0.11, 0.11, 0.36) * strength, _white)
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var ray := _part(node, _box, Vector3(cos(angle) * 0.07, sin(angle) * 0.07, -0.12), Vector3(0.034, 0.033, 0.28) * strength, _gold)
		ray.rotation = Vector3(sin(angle) * 0.48, cos(angle) * 0.48, 0)
	_play(_scatter_sound if charged else _shot_sound, at, -7.0 if charged else -9.0, _rng.randf_range(0.94, 1.06), true)
	set_charge(at, 0)

func tracer(from: Vector3, to: Vector3, charged: bool, index: int = 0) -> void:
	var distance := from.distance_to(to)
	if distance < 0.001:
		return
	var travel := clampf(distance / 115.0, 0.06, 0.14)
	var effect := _effect(from, "tracer", travel + 0.085)
	var node: Node3D = effect.node
	node.add_to_group("corn_tracers")
	_orient(node, to - from)
	var width := 0.062 if charged else 0.071
	var tail := _part(node, _box, Vector3(0, 0, 0.16), Vector3(width * 0.48, width * 0.48, 0.38), _gold)
	var core := _part(node, _box, Vector3(0, 0, 0.13), Vector3(width * 0.20, width * 0.20, 0.32), _white)
	var kernel := _part(node, _sphere, Vector3.ZERO, Vector3(width * 1.5, width * 1.24, width * 1.85), _gold)
	kernel.rotation.z = float(index) * 0.9
	effect["from"] = from
	effect["to"] = to
	effect["travel"] = travel
	effect["tail"] = tail
	effect["core"] = core
	effect["kernel"] = kernel

func impact(at: Vector3, direction: Vector3, charged: bool) -> void:
	var effect := _effect(at, "impact", 0.34 if charged else 0.27)
	var node: Node3D = effect.node
	var normal := _direction(direction)
	_orient(node, -normal)
	var count := 10 if charged else 7
	var fragments: Array[Dictionary] = []
	for index in count:
		var angle := TAU * float(index) / float(count) + _rng.randf_range(-0.15, 0.15)
		var speed := _rng.randf_range(1.0, 2.0) * (1.2 if charged else 1.0)
		var velocity := Vector3(cos(angle) * speed, sin(angle) * speed, _rng.randf_range(-0.3, 0.2))
		var scale_value := _rng.randf_range(0.045, 0.072)
		var fragment := _part(node, _sphere, Vector3.ZERO, Vector3(scale_value, scale_value * 0.8, scale_value * 1.4), _husk if index % 4 == 0 else _gold)
		fragments.append({"node": fragment, "velocity": velocity, "size": fragment.scale})
	var flower := _part(node, _sphere, Vector3.ZERO, Vector3(0.20, 0.20, 0.022), _white)
	for index in 4:
		var ray := _part(flower, _box, Vector3.ZERO, Vector3(0.23, 1.9, 0.65), _gold)
		ray.rotation.z = float(index) * PI * 0.25
	effect["fragments"] = fragments
	effect["flower"] = flower
	_play(_hit_sound, at, -16.0, _rng.randf_range(0.85, 1.2))

func damage_number(at: Vector3, amount: int, charged: bool) -> void:
	var effect := _effect(at + Vector3.UP * 0.28, "number", 0.62)
	var label := Label3D.new()
	label.text = str(amount)
	label.font_size = 42 if charged else 34
	label.pixel_size = 0.012
	label.outline_size = 7
	label.modulate = Color("fff0a3") if charged else Color("fff9de")
	label.outline_modulate = Color("593b26")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.node.add_child(label)
	effect["label"] = label
	effect["origin"] = effect.node.global_position

func set_charge(at: Vector3, ratio: float) -> void:
	if _shutdown_draining and ratio > 0.0:
		return
	_charge_ratio = clampf(ratio, 0.0, 1.0)
	if _charge_ratio <= 0.001:
		if is_instance_valid(_charge_root):
			_charge_root.free()
		_charge_root = null
		if is_instance_valid(_charge_audio):
			_charge_audio.stop()
			_charge_audio.stream = null
			_charge_audio.free()
		_charge_audio = null
		_charge_clock = 0.0
		return
	if not is_instance_valid(_charge_root):
		_charge_root = Node3D.new()
		_charge_root.name = "CornCharge"
		add_child(_charge_root)
		for index in 6:
			_part(_charge_root, _sphere, Vector3.ZERO, Vector3.ONE * 0.038, _white if index % 2 == 0 else _gold)
		_charge_audio = _new_audio()
		_charge_audio.stream = _charge_sound
		_charge_audio.volume_db = -22
		# Keep playback lifecycle identical on silent/headless and audible drivers.
		# clear_effects stops and detaches streams before freeing their nodes.
		_charge_audio.play()
		_remember_playback(_charge_audio)
	_charge_root.global_position = at
	_charge_audio.global_position = at
	_charge_audio.pitch_scale = 0.85 + _charge_ratio * 0.65
	_charge_audio.volume_db = -24.0 + _charge_ratio * 7.0

func clear_effects() -> void:
	_prune_playbacks()
	# Free synchronously: a retry can immediately re-arm without stale visuals/sound.
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
		child.free()
	_effects.clear()
	_voices.clear()
	_shot_voices.clear()
	_voice_cursor = 0
	_shot_voice_cursor = 0
	_charge_root = null
	_charge_audio = null
	_charge_ratio = 0.0
	_charge_clock = 0.0

func _process(delta: float) -> void:
	_prune_playbacks()
	for index in range(_effects.size() - 1, -1, -1):
		var effect: Dictionary = _effects[index]
		effect.age += delta
		if effect.age >= effect.life:
			if is_instance_valid(effect.node):
				effect.node.free()
			_effects.remove_at(index)
			continue
		var age: float = effect.age
		var fraction: float = age / effect.life
		match effect.kind:
			"flash":
				effect.node.scale = Vector3.ONE * maxf(0.01, 1.0 - fraction * fraction)
			"tracer":
				var progress := minf(1.0, age / effect.travel)
				effect.node.global_position = effect.from.lerp(effect.to, progress)
				if progress >= 1.0:
					var fade := maxf(0.01, 1.0 - (age - effect.travel) / 0.085)
					effect.node.scale = Vector3.ONE * fade
				effect.kernel.rotation.z += delta * 12.0
			"impact":
				effect.flower.visible = age < 0.095
				for fragment in effect.fragments:
					fragment.node.position = fragment.velocity * age + Vector3.DOWN * age * age * 1.5
					fragment.node.scale = fragment.size * (1.0 - fraction * 0.85)
					fragment.node.rotation += Vector3(9, 6, 4) * delta
			"number":
				effect.node.global_position = effect.origin + Vector3.UP * (0.9 * fraction)
				effect.label.modulate.a = minf(1.0, (1.0 - fraction) * 3.0)
	if is_instance_valid(_charge_root):
		_charge_clock += delta
		var orbit := 0.17 - _charge_ratio * 0.075
		for index in _charge_root.get_child_count():
			var angle := float(index) * TAU / 6.0 + _charge_clock * (4.0 + _charge_ratio * 6.0)
			var spark: Node3D = _charge_root.get_child(index)
			spark.position = Vector3(cos(angle) * orbit, sin(angle * 1.3) * orbit * 0.7, sin(angle) * orbit)
			spark.scale = Vector3.ONE * (0.023 + _charge_ratio * 0.019)

func _new_audio() -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.max_polyphony = 1
	voice.max_distance = 45.0
	voice.unit_size = 12.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(voice)
	return voice

func _play(stream: AudioStreamWAV, at: Vector3, volume: float, pitch: float, muzzle: bool = false) -> void:
	if _shutdown_draining:
		return
	_prune_playbacks()
	var pool: Array[AudioStreamPlayer3D] = _shot_voices if muzzle else _voices
	var limit := MAX_SHOT_VOICES if muzzle else MAX_IMPACT_VOICES
	if pool.size() < limit:
		pool.append(_new_audio())
	var cursor := _shot_voice_cursor if muzzle else _voice_cursor
	var voice := pool[cursor % pool.size()]
	if muzzle:
		_shot_voice_cursor += 1
	else:
		_voice_cursor += 1
	voice.stop()
	voice.global_position = at
	voice.stream = stream
	voice.volume_db = volume
	voice.pitch_scale = pitch
	voice.play()
	_remember_playback(voice)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		var paused := what == NOTIFICATION_PAUSED
		for voice in _voices + _shot_voices:
			if is_instance_valid(voice):
				voice.stream_paused = paused
		if is_instance_valid(_charge_audio):
			_charge_audio.stream_paused = paused
	elif what == NOTIFICATION_EXIT_TREE:
		# Explicitly stop audio even when the entire level is freed while paused.
		clear_effects()

func _synthesize(kind: int, duration: float) -> AudioStreamWAV:
	const RATE := 22050
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 472 + kind
	var phase := 0.0
	for index in count:
		var time := float(index) / RATE
		var progress := time / duration
		var frequency := 430.0 - progress * 280.0
		var envelope := exp(-time * 36.0)
		var sample := 0.0
		match kind:
			0:
				phase += TAU * frequency / RATE
				sample = (sin(phase) * 0.7 + noise.randf_range(-1, 1) * 0.30) * envelope
			1:
				phase += TAU * (190.0 - progress * 95.0) / RATE
				sample = (sin(phase) * 0.68 + noise.randf_range(-1, 1) * 0.4) * exp(-time * 21.0)
			2:
				phase += TAU * (870.0 - progress * 220.0) / RATE
				sample = (sin(phase) * 0.55 + sin(phase * 1.73) * 0.2 + noise.randf_range(-1, 1) * 0.25) * exp(-time * 51.0)
			3:
				# Integer periods make the loop seam click-free.
				sample = (sin(TAU * 140.0 * time) * 0.34 + sin(TAU * 280.0 * time) * 0.12) * (0.8 + sin(TAU * 5.0 * time) * 0.2)
		if kind != 3:
			sample *= minf(1.0, time * 1800.0) * minf(1.0, (duration - time) * 200.0)
		data.encode_s16(index * 2, int(clampf(sample, -1, 1) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if kind == 3:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream

# Weak history includes replaced and already-freed voices: AudioServer can own
# their playback until a later mix/update even after the scene nodes are gone.
static func _remember_playback(voice: AudioStreamPlayer3D) -> void:
	var playback := voice.get_stream_playback()
	if playback != null:
		_playback_refs[playback.get_instance_id()] = weakref(playback)

static func _prune_playbacks() -> void:
	for id in _playback_refs.keys():
		if _playback_refs[id].get_ref() == null:
			_playback_refs.erase(id)

static func await_owned_shutdown(tree: SceneTree, timeout_seconds: float = 2.0) -> bool:
	if _owned_shutdown_busy:
		return false
	_owned_shutdown_busy = true
	var effects: Array[Dictionary] = []
	var voices: Array[Dictionary] = []
	# Snapshot every mode before an override can propagate pause notifications.
	for fx in tree.get_nodes_in_group("corn_audio_fx"):
		effects.append({"node":fx,"mode":fx.process_mode,"draining":fx._shutdown_draining})
		for child in fx.get_children():
			if child is AudioStreamPlayer3D:
				voices.append({"node":child,"mode":child.process_mode,"paused":child.stream_paused})
	for state in effects:
		state.node.set_charge(Vector3.ZERO,0.0)
		state.node._shutdown_draining = true
		state.node.process_mode = Node.PROCESS_MODE_ALWAYS
	for state in voices:
		if is_instance_valid(state.node):
			state.node.process_mode = Node.PROCESS_MODE_ALWAYS
			state.node.stream_paused = false
	var deadline := Time.get_ticks_usec()+int(maxf(0.0,timeout_seconds)*1000000.0)
	var tails_released := false
	var complete := false
	while true:
		var playing := false
		for state in voices:
			# The server can stop before the node emits finished and drops its playback.
			if is_instance_valid(state.node) and (state.node.playing or state.node.has_stream_playback()):
				playing = true
		if not playing and not tails_released:
			for state in effects:
				if is_instance_valid(state.node):
					state.node.clear_effects()
			tails_released = true
		_prune_playbacks()
		if tails_released and _playback_refs.is_empty():
			complete = true
			break
		if Time.get_ticks_usec() >= deadline:
			break
		# No strong playback resource is retained across this await.
		await tree.process_frame
	for state in effects:
		if is_instance_valid(state.node):
			state.node._shutdown_draining = state.draining
			state.node.process_mode = state.mode
	for state in voices:
		if is_instance_valid(state.node):
			state.node.process_mode = state.mode
			state.node.stream_paused = state.paused
	_owned_shutdown_busy = false
	return complete
