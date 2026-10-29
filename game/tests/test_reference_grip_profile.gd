extends SceneTree
## Validates profile sampling mechanics; this is not the independent motion gate.
const BONES := ["RightArm", "RightForeArm", "RightHand"]
var checks := 0
var failures := 0
func _initialize(): call_deferred("run_checks")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func finish():
	print("REFERENCE_GRIP_PROFILE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func run_checks():
	var helper = load("res://weapons/melee_hold_pose.gd").new()
	check(helper.has_method("sample_attack_profile"), "retarget consumes a full source-clock three-bone profile")
	if not helper.has_method("sample_attack_profile"):
		helper.free(); finish(); return
	# q and -q must denote the same orientation across a key boundary.
	var q := Quaternion(Vector3.RIGHT, .8)
	var a := {}; var b := {}
	for bone in BONES:
		a[bone] = Quaternion.IDENTITY
		b[bone] = -q
	helper.attack_records = [{"time": 0.0, "rotations": a}, {"time": 1.0, "rotations": b}]
	for phase in [0.0, .25, .5, .75, 1.0, 1.5]:
		var actual: Dictionary = helper.sample_attack_profile(phase)
		var expected := Quaternion.IDENTITY.slerp(q, clampf(phase, 0, 1))
		for bone in BONES:
			check(actual[bone].angle_to(expected) < .0001 and absf(actual[bone].length_squared() - 1) < .00001, "normalized shortest-path source-clock interpolation " + bone)
	helper.free(); finish()
