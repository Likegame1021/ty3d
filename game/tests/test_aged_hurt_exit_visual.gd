extends "res://tests/qa_aged_hurt_automatic.gd"
## Narrow aged-hurt exit regression, grounded in matched native ordinary RUN.
## Reference is actual baseline automatic normal-grip rig data, source-bound.
## Required invocation: --fixed-fps 60, normal 60Hz physics, time_scale 1.
const GripReference = preload("res://tests/fixtures/reference-grip-v4-r2/reference.gd")
const REFERENCE:="res://tests/fixtures/aged_hurt_baseline_run_poses.json"
class CadenceProbe:
	extends Node
	var samples: Array[float] = []
	func _process(delta: float) -> void:
		samples.append(delta)

func has_reference_cadence() -> bool:
	# Godot consumes --fixed-fps before OS.get_cmdline_args() is exposed.
	# Verify the effective automatic render clock before creating any actors.
	var probe := CadenceProbe.new()
	root.add_child(probe)
	for ignored in 7:
		await process_frame
	var valid := probe.samples.size() >= 6 and Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0
	for sample in probe.samples:
		valid = valid and absf(sample - DT) < 0.000000001
	print("QA_REFERENCE_CADENCE ", JSON.stringify({"process_deltas":probe.samples,"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"valid":valid}))
	probe.free()
	return valid
func max_component(a,b) -> float:
	if a is Array:
		var result:=0.0
		for i in a.size():result=maxf(result,max_component(a[i],b[i]))
		return result
	return absf(float(a)-float(b))
func v3(a) -> Vector3: return Vector3(a[0], a[1], a[2])
func matrix(a) -> Transform3D: return Transform3D(Basis(v3(a[0]), v3(a[1]), v3(a[2])), v3(a[3]))
func approved_run_pose(old_pose: Array, skeleton: Skeleton3D, grip_reference) -> Array:
	var locals := []
	var globals := []
	for index in old_pose.size():
		var local := matrix(old_pose[index])
		locals.append(local)
		var parent := skeleton.get_bone_parent(index)
		globals.append(local if parent < 0 else globals[parent] * local)
	var record: Dictionary
	for candidate in grip_reference.carry.records:
		if candidate.name == "run": record = candidate; break
	var chest: Quaternion = globals[skeleton.find_bone("Spine")].basis.orthonormalized().get_rotation_quaternion()
	for name in GripReference.ARM:
		var index := skeleton.find_bone(name)
		var parent := skeleton.get_bone_parent(index)
		var target: Quaternion = (chest * GripReference.q(record.reference_chest_quaternion_xyzw).inverse() * GripReference.q(record.global_rotation_quaternions_xyzw[name])).normalized()
		var parent_q: Quaternion = globals[parent].basis.orthonormalized().get_rotation_quaternion()
		var local: Transform3D = locals[index]
		local.basis = Basis((parent_q.inverse() * target).normalized()).scaled_local(local.basis.get_scale())
		locals[index] = local
		globals[index] = globals[parent] * local
	var result: Array = old_pose.duplicate(true)
	for name in GripReference.ARM:
		var index := skeleton.find_bone(name)
		result[index] = transform(locals[index])
	return result
func run_checks() -> void:
	if not await has_reference_cadence():
		printerr("QA_INVOCATION_ERROR: exact rendered-pose reference requires --fixed-fps 60, 60Hz physics, and time_scale 1")
		quit(2)
		return
	for action in ["move_left","move_right","move_up","move_down","run"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	var reference=JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	var grip_reference = GripReference.new()
	check(grip_reference.files_match(), "approved R2 carry reference remains hash-pinned")
	var source_model = load("res://assets/characters/boy/boy.glb").instantiate()
	var reference_skeleton: Skeleton3D = source_model.find_children("*", "Skeleton3D", true, false)[0]
	await run_case("one-frame-tail",44)
	var row:Dictionary=rows[0]
	var first_run:int=row.first_run.tick
	var maximum:=0.0
	var tip_maximum:=0.0
	var minimum_support:=INF
	for sample in row.pose_deltas:
		if int(sample.tick)>=first_run and int(sample.tick)<first_run+12:
			maximum=maxf(maximum,float(sample.support_step_m));tip_maximum=maxf(tip_maximum,float(sample.weapon_tip_step_m));minimum_support=minf(minimum_support,float(sample.lowest_y))
	var limit:float=reference.matched_run_max_support_step_m*1.05
	check(maximum<=limit,"one-frame aged-hurt exit support step no sharper than matched baseline +5pct: %.9f <= %.9f"%[maximum,limit])
	check(minimum_support>=float(reference.matched_run_min_support_world_y)-.001,"aged exit introduces no extra support penetration beyond matched ordinary baseline +1mm")
	var matches:=0
	var max_pose_error:=0.0
	for sample in row.actual_skeleton_samples:
		if sample.clip!="run" or int(sample.tick)<first_run+18:continue
		for expected in reference.poses:
			if absf(float(sample.clip_time)-float(expected.clip_time))<.000001:
				matches+=1;max_pose_error=maxf(max_pose_error,max_component(sample.pose,approved_run_pose(expected.pose, reference_skeleton, grip_reference)));break
	check(matches>=15,"at least15 settled RUN frames keep same authored gait clock as ordinary baseline")
	check(matches>0 and max_pose_error<.0001,"all21 settled source RUN transforms and three approved carry transforms converge within100microunit")
	var report:={"checks":checks,"failures":failures,"max_run_handover_support_step_m":maximum,"matched_baseline_support_step_m":reference.matched_run_max_support_step_m,"support_limit_5pct":limit,"max_run_handover_tip_step_m":tip_maximum,"min_run_handover_support_world_y":minimum_support,"matched_settled_frames":matches,"max_all24_bone_pose_error":max_pose_error,"reference_sha256":FileAccess.get_sha256(REFERENCE),"chapter_player_sha256":FileAccess.get_sha256("res://scripts/cornfield/player.gd"),"case":row}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join(variant+"-exit-visual.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	source_model.free()
	print("AGED_HURT_EXIT_VISUAL ",JSON.stringify({"checks":checks,"failures":failures,"support_step":maximum,"limit":limit,"settled_matches":matches,"all24_pose_error":max_pose_error}));quit(1 if failures else 0)
