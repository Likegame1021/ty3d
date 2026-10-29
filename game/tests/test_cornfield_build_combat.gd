extends SceneTree
## Behavioral integration tests, distinct from the no-cheat live playtest.
const Player = preload("res://scripts/cornfield/player.gd")
const Enemy = preload("res://scripts/cornfield/field_enemy.gd")
const Effects = preload("res://scripts/cornfield/build_effects.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func _run() -> void:
	var setup = load("res://scripts/main.gd").new()
	setup.setup_input()
	setup.free()
	var world := Node3D.new()
	root.add_child(world)
	var player := Player.new()
	player.spawn_position = Vector3.ZERO
	world.add_child(player)
	player.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	player.configure(camera,"stick")
	var enemy := Enemy.new()
	world.add_child(enemy)
	enemy.position=Vector3(sin(deg_to_rad(80.0)),0,-cos(deg_to_rad(80.0)))*1.45
	enemy.configure(world,player,"beetle")
	enemy.set_physics_process(false)
	await physics_frame
	await physics_frame
	var slash_events: Array = []
	player.feedback_requested.connect(func(kind: String,payload: Dictionary):
		if kind=="slash":slash_events.append(payload))
	player.facing=Vector3.FORWARD
	player.request_attack()
	player.attack.elapsed=.59
	player._physics_process(.02)
	check(slash_events.size()==1,"real swing emits one slash at original hit window")
	player.check_hits()
	check(slash_events.size()==1,"repeated hit scans never duplicate slash")
	check(enemy.hp==48.0,"baseline does not hit beyond original arc and reach")
	player.cancel_actions()
	var sweep := {"builds_by_weapon":{"stick":{"arc":1,"reach":1},"corn":{}},"global_builds":{}}
	player.apply_build_effects(Effects.compile(sweep,"stick"))
	player.request_attack()
	player.attack.elapsed=.61
	player.check_hits()
	check(enemy.hp==30.0,"sweep build extends actual hit arc and reach")
	player.check_hits()
	check(enemy.hp==30.0,"expanded swing still hits each target only once")
	player.cancel_actions()
	enemy.position=Vector3(0,0,-1.0)
	var steady := {"builds_by_weapon":{"stick":{"damage":1,"knockback":1,"recovery":2},"corn":{"damage":1,"knockback":1}},"global_builds":{"clear_heal":1}}
	player.apply_build_effects(Effects.compile(steady,"stick"))
	var hit_start:float=player.attack.active_start
	var hit_end:float=player.attack.active_end
	var default_duration:float=player._authored_attack_duration
	player.request_attack()
	check(is_equal_approx(player.attack.duration,hit_end+(default_duration-hit_end)*.8464),"rank2 recovery changes only post-contact duration")
	check(player.attack.active_start==hit_start and player.attack.active_end==hit_end,"build leaves active hit window untouched")
	player.attack.elapsed=.61
	player.check_hits()
	check(is_equal_approx(enemy.hp,9.3),"damage rank applies18×1.15 once")
	check(is_equal_approx(enemy._knockback.length(),3.0),"knockback rank applies2.4×1.25")
	player.cancel_actions()
	player.configure(camera,"corn")
	player.apply_build_effects(Effects.compile(steady,"corn"))
	enemy.hp=48.0
	enemy.receive_projectile(1)
	check(is_equal_approx(enemy.hp,31.9),"corn damage upgrade preserves14-unit conversion")
	check(is_equal_approx(enemy._knockback.length(),3.0),"corn receives directional knockback upgrade")
	check(is_equal_approx(player.attack_reach,1.35) and player.arc_bonus_degrees==0.0,"corn ignores branch-only arc and reach")
	player.configure(camera,"stick")
	player.apply_build_effects(Effects.compile(steady,"stick"))
	check(is_equal_approx(player.damage_multiplier,1.15) and is_equal_approx(player.recovery_multiplier,.8464),"returning to branch restores its independent upgrades")
	world.queue_free()
	await process_frame
	print("CORNFIELDS_BUILD_COMBAT %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
