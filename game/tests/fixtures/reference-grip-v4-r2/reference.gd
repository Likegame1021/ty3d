extends RefCounted
## Independent immutable author reference; never sample the runtime helper for goldens.
const ROOT := "res://tests/fixtures/reference-grip-v4-r2/"
const ARM := ["RightArm", "RightForeArm", "RightHand"]
const HASHES := {"carry-reference.json": "58e1d4df233ea26ef4f2c1d18336782165f806f5e132be3ee3243a7e35dd0737", "attack-reference.json": "a6dd65f01263b6809392dd92763e980a53b8c8c11260fd9c85105f4a1c3e78d3", "grip-frame.json": "685fae8d9bd416828a59ee2cb99bfd8944977c56a65c5fbb122f9bf33744ebcc"}
var carry: Dictionary
var attack: Dictionary
var grip: Dictionary
func _init():
	carry = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "carry-reference.json"))
	attack = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "attack-reference.json"))
	grip = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "grip-frame.json"))
func files_match() -> bool:
	for file in HASHES:
		if FileAccess.get_sha256(ROOT + file) != HASHES[file]: return false
	return true
static func q(a) -> Quaternion: return Quaternion(a[0], a[1], a[2], a[3]).normalized()
func carry_model_rotations(skeleton: Skeleton3D, action: String) -> Dictionary:
	var record: Dictionary
	for candidate in carry.records:
		if candidate.name == action: record = candidate; break
	var chest := skeleton.get_bone_global_pose(skeleton.find_bone("Spine")).basis.orthonormalized().get_rotation_quaternion()
	var result := {}
	for bone in ARM: result[bone] = (chest * q(record.reference_chest_quaternion_xyzw).inverse() * q(record.global_rotation_quaternions_xyzw[bone])).normalized()
	return result
func attack_local_rotations(time: float) -> Dictionary:
	var left: Dictionary = attack.records[0]
	var right: Dictionary = attack.records[-1]
	for key in attack.records:
		if key.time <= time: left = key
		if key.time >= time: right = key; break
	var alpha := 0.0 if right.time == left.time else clampf((time - left.time) / (right.time - left.time), 0, 1)
	var result := {}
	for bone in ARM: result[bone] = q(left.local_quaternions_xyzw[bone]).slerp(q(right.local_quaternions_xyzw[bone]), alpha).normalized()
	return result
