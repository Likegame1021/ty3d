extends SceneTree
## Versioned topology-swap regression. Historical morph tests remain provenance.
var loader = load("res://weapons/normal_grip_mesh.gd")
const OPEN_PATH := "res://assets/characters/boy/normal_grip/boy-closed-grip-v2.glb"
const CLOSED_PATH := "res://assets/characters/boy/normal_grip/v4/boy-closed-diagonal-surface-v4.glb"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run_checks")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func finish() -> void:
	print("REFERENCE_GRIP_RUNTIME: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func body(scene: Node) -> MeshInstance3D: return scene.find_child("BoyBody", true, false)
func run_checks() -> void:
	var source = load("res://assets/characters/boy/boy.glb").instantiate()
	var target := body(source)
	var skin := target.skin
	var fit: Transform3D = source.transform
	var material := target.mesh.surface_get_material(0)
	var animation = source.find_children("*", "AnimationPlayer", true, false)[0]
	var result: Dictionary = loader.apply(source)
	check(result.has("open_mesh") and result.has("closed_mesh"), "loader returns two cached mesh resources, not a morph index")
	if not result.has("open_mesh") or not result.has("closed_mesh"):
		source.free(); finish(); return
	check(result.mesh == target and target.mesh == result.closed_mesh, "successful setup installs closed resource on the original node")
	check(target.skin == skin and source.transform == fit, "setup retains fitted model and Skin identity")
	check(target.mesh.surface_get_material(0) == material, "closed resource retains source material identity")
	check(source.find_children("*", "AnimationPlayer", true, false)[0] == animation, "setup retains source animation player")
	check(result.closed_mesh.get_blend_shape_count() == 0, "v4 topology is honestly closed-only")
	var accepted_open = load(OPEN_PATH).instantiate()
	var expected_open := body(accepted_open).mesh
	check(result.open_mesh.surface_get_arrays(0) == expected_open.surface_get_arrays(0), "ranged mesh preserves accepted v2 Grip_Right=0 geometry exactly")
	var closed_import = load(CLOSED_PATH).instantiate()
	var bad_skin: Skin = body(closed_import).skin.duplicate()
	body(closed_import).skin = bad_skin
	bad_skin.set_bind_name(0, &"WrongBone")
	var before_mesh := target.mesh
	var rejected: Dictionary = loader.apply_imports(source, accepted_open, closed_import)
	check(rejected.is_empty() and target.mesh == before_mesh and target.skin == skin, "invalid bind mapping rejects atomically without mutating the live actor")
	closed_import.free(); accepted_open.free(); source.free()
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var p = load("res://scripts/player.gd").new()
	root.add_child(p)
	p.set_physics_process(false)
	p.melee_hold_pose.active = false
	p.corn_hold_pose.active = false
	p.cancel_pose.active = false
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var helper = p.melee_hold_pose
	var mesh := body(p.body_visual)
	var open_mesh: ArrayMesh = helper.grip_open_mesh
	var closed_mesh: ArrayMesh = helper.grip_closed_mesh
	var branch: MeshInstance3D = p.branch_pivot.get_node("Branch")
	var stable_skin := mesh.skin
	var node_count: int = p.body_visual.find_children("*", "MeshInstance3D", true, false).size()
	for iteration in 100:
		p.ranged_stance = iteration % 2 == 0
		helper._process_modification()
		check(mesh.mesh == (open_mesh if p.ranged_stance else closed_mesh), "repeated stance swap uses cached exact resource %d" % iteration)
		if p.ranged_stance:
			check(p.branch_pivot.position == Vector3(0, .045, 0) and p.branch_pivot.quaternion.is_equal_approx(Quaternion.IDENTITY), "ranged anchor remains established")
	check(mesh.skin == stable_skin and p.body_visual.find_children("*", "MeshInstance3D", true, false).size() == node_count, "100 swaps preserve Skin and node inventory")
	for action in ["pick_up", "interact", "push", "vault"]:
		p.ranged_stance = false
		p.context_remaining = .2; p.context_action = action
		helper.advance_state(.01); helper._process_modification()
		check(mesh.mesh == open_mesh and not branch.visible, action + " opens and stows")
		p.ranged_stance = true; helper._process_modification()
		p.ranged_stance = false; helper._process_modification()
		check(mesh.mesh == open_mesh, "ranged return during " + action + " remains open")
		p.context_remaining = 0; p.context_action = ""
		helper.advance_state(.17); helper._process_modification()
		check(mesh.mesh == open_mesh and not branch.visible, action + " retains .18 s stow guard")
		helper.advance_state(.02); helper._process_modification()
		check(mesh.mesh == closed_mesh and branch.visible, action + " restores closed after settling")
	p.context_remaining = .2; p.context_action = "hurt"
	helper._process_modification()
	check(mesh.mesh == closed_mesh and branch.visible, "hurt retains closed hand and branch")
	p.context_action = "pick_up"; helper.advance_state(.01); helper._process_modification()
	p.reset_player(); helper._process_modification()
	check(mesh.mesh == closed_mesh and branch.visible, "reset clears stow on first visible pass")
	var frozen := mesh.mesh
	paused = true
	await create_timer(.05, true).timeout
	check(mesh.mesh == frozen, "paused actor retains exact mesh state")
	paused = false
	p.free()
	finish()
