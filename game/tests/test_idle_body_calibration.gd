extends SceneTree
## Reviewed idle dimensions and immutable original RUN regression.
const Player = preload("res://scripts/player.gd")
var player_type: Script = Player
const BODY_SEGMENTS := [
	["Hips", "Spine02"], ["Spine02", "Spine01"], ["Spine01", "Spine"],
	["neck", "Head"], ["Head", "head_end"],
	["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"],
	["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"]
]
var failures := 0
var checks := 0

func _initialize() -> void:
	var candidate_path := OS.get_environment("IDLE_TEST_PLAYER")
	if not candidate_path.is_empty():
		player_type = load(candidate_path)
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func make_player():
	var actor = player_type.new()
	root.add_child(actor)
	actor.set_physics_process(false)
	for modifier in actor.find_children("*", "SkeletonModifier3D", true, false):
		modifier.active = false
	actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.animation_player.stop()
	return actor

func fingerprint(clip: Animation) -> String:
	var tracks: Array = []
	for index in clip.get_track_count():
		var keys: Array = []
		for key in clip.track_get_key_count(index):
			keys.append([clip.track_get_key_time(index, key), clip.track_get_key_value(index, key), clip.track_get_key_transition(index, key)])
		tracks.append([String(clip.track_get_path(index)), clip.track_get_type(index), clip.track_get_interpolation_type(index), keys])
	return var_to_str([clip.length, tracks]).sha256_text()

func sample(actor, clip_name: String, seconds: float) -> Dictionary:
	actor.animation_player.play(clip_name, 0.0)
	actor.animation_player.seek(seconds, true)
	actor.animation_player.advance(0.0)
	var skeleton: Skeleton3D = actor.find_children("*", "Skeleton3D", true, false)[0]
	skeleton.force_update_all_bone_transforms()
	var poses: Array = []
	for index in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(index))
	var lengths: Array = []
	for pair in BODY_SEGMENTS:
		lengths.append(poses[skeleton.find_bone(pair[0])].origin.distance_to(poses[skeleton.find_bone(pair[1])].origin))
	return {"poses": poses, "lengths": lengths, "hips_scale": poses[skeleton.find_bone("Hips")].basis.get_scale()}

func run_checks() -> void:
	var reference_path := "res://tests/fixtures/idle_calibration_original_run_pose.json"
	check(FileAccess.file_exists(reference_path), "immutable RUN master fixture exists")
	if not FileAccess.file_exists(reference_path):
		quit(1)
		return
	var reference = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	check(reference is Dictionary and reference.get("samples", []).size() == 4, "immutable RUN master has all four phases")
	if not reference is Dictionary or reference.get("samples", []).size() != 4:
		quit(1)
		return
	check(FileAccess.get_sha256("res://assets/characters/boy/boy.glb") == reference.source_model_sha256, "original character GLB remains byte-identical")
	var first = make_player()
	check(first.animation_player.has_animation("idle"), "original idle remains available as source master")
	var source_idle: Animation = first.animation_player.get_animation("idle")
	var source_run: Animation = first.animation_player.get_animation(first.animation_names["run"])
	var original_idle_hash := fingerprint(source_idle)
	var original_run_hash := fingerprint(source_run)
	var run_samples: Array = []
	for phase in [0.0, 0.25, 0.5, 0.75]:
		run_samples.append(sample(first, first.animation_names["run"], phase * source_run.length))
	for phase_index in 4:
		for bone_data in reference.samples[phase_index].poses:
			var expected: Array = bone_data.global_skeleton
			var actual: Transform3D = run_samples[phase_index].poses[int(bone_data.index)]
			var actual_columns := [actual.basis.x, actual.basis.y, actual.basis.z, actual.origin]
			var maximum_delta := 0.0
			for column in 4:
				for component in 3:
					maximum_delta = maxf(maximum_delta, absf(actual_columns[column][component] - float(expected[column][component])))
			check(maximum_delta < 0.000002, "RUN master phase%d bone%s matches frozen original" % [phase_index, bone_data.bone])
	var run_reference: Dictionary = run_samples[0]
	var idle_name: String = first.animation_names["idle"]
	var calibrated_idle: Animation = first.animation_player.get_animation(idle_name)
	check(calibrated_idle != source_idle, "runtime idle uses a private calibrated copy")
	check(is_equal_approx(calibrated_idle.length, source_idle.length), "calibration preserves idle clock and duration")
	for phase in [0.0, 0.25, 0.5, 0.75]:
		var pose := sample(first, idle_name, phase * calibrated_idle.length)
		var maximum_ratio_error := 0.0
		for index in BODY_SEGMENTS.size():
			maximum_ratio_error = maxf(maximum_ratio_error, absf(pose.lengths[index] / run_reference.lengths[index] - 1.0))
		print("IDLE_BODY_SAMPLE phase=", phase, " max_body_ratio_error=", maximum_ratio_error, " hips_scale=", pose.hips_scale)
		check(maximum_ratio_error < 0.00003, "idle phase %.2f uses original RUN body dimensions" % phase)
	check(first.scale.is_equal_approx(Vector3.ONE), "CharacterBody scale stays one")
	var second = make_player()
	check(second.animation_player.get_animation(second.animation_names["idle"]) != calibrated_idle, "players do not share the private calibrated idle resource")
	check(fingerprint(source_idle) == original_idle_hash, "source idle tracks are preserved")
	check(fingerprint(source_run) == original_run_hash, "source RUN tracks are preserved")
	var index := 0
	for phase in [0.0, 0.25, 0.5, 0.75]:
		var after := sample(first, first.animation_names["run"], phase * source_run.length)
		for bone in after.poses.size():
			check(after.poses[bone].is_equal_approx(run_samples[index].poses[bone]), "RUN phase %.2f bone %d remains unchanged after idle/second-player use" % [phase, bone])
		index += 1
	first.free()
	second.free()
	print("IDLE_BODY_CALIBRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
