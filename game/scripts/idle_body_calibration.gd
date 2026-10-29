extends RefCounted
## The source idle alone enlarges the whole body by 20/17 through Hips.
## Calibrate a private clip before blending; source clips and gameplay scale stay intact.
const SIZE_FACTOR := 0.85
const FLOOR_OFFSET_M := 0.010292326550961881
const LIBRARY_NAME := "body_calibration"
const IDLE_NAME := "body_calibration/idle"

static func apply(player) -> void:
	if not player.animation_player or not player.animation_names.has("idle"):
		return
	if player.animation_names["idle"] == IDLE_NAME:
		return
	var skeletons: Array[Node] = player.body_visual.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0]
	var source: Animation = player.animation_player.get_animation(player.animation_names["idle"])
	var calibrated := source.duplicate(true) as Animation
	var offset_local := skeleton.global_basis.inverse() * Vector3.UP * FLOOR_OFFSET_M
	var changed := 0
	for track in calibrated.get_track_count():
		var path := calibrated.track_get_path(track)
		if path.get_subname_count() == 0 or String(path.get_subname(0)) != "Hips":
			continue
		var kind := calibrated.track_get_type(track)
		if kind != Animation.TYPE_POSITION_3D and kind != Animation.TYPE_SCALE_3D:
			continue
		for key in calibrated.track_get_key_count(track):
			var value: Vector3 = calibrated.track_get_key_value(track, key) * SIZE_FACTOR
			if kind == Animation.TYPE_POSITION_3D:
				value += offset_local
			calibrated.track_set_key_value(track, key, value)
		changed += 1
	if changed != 2:
		push_error("Idle calibration requires the reviewed Hips position and scale tracks")
		return
	var library := AnimationLibrary.new()
	library.add_animation("idle", calibrated)
	if player.animation_player.add_animation_library(LIBRARY_NAME, library) == OK:
		player.animation_names["idle"] = IDLE_NAME
