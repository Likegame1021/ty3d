extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	if not FileAccess.file_exists("res://scripts/main.gd"):
		check(false, "playable scene exists for movement / hit / reset regression")
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var player = game.player
	var target = game.target
	player.position = Vector3(0, 0.05, -3.8)
	player.facing = Vector3(0, 0, -1)
	player.attack.begin(false)
	player.attack.tick(player.attack.active_start + 0.02, false)
	player.check_hits()
	player.check_hits()
	check(target.hit_count == 1, "overlap hits exactly once per swing")
	paused = true
	player.attack.reset()
	player.attack.begin(false)
	player.attack.tick(player.attack.active_start + 0.02, false)
	player.check_hits()
	check(target.hit_count == 1, "pause prevents overlap hits")
	var frozen_position: Vector3 = player.position
	var frozen_attack: float = player.attack.remaining
	Input.action_press("move_up")
	for frame in 10:
		await physics_frame
	Input.action_release("move_up")
	check(player.position == frozen_position, "pause prevents character movement")
	check(player.attack.remaining == frozen_attack, "pause freezes ongoing gameplay attack")
	paused = false
	player.attack.reset()
	player.position = Vector3(0, 0.05, -8)
	player.facing = Vector3(0, 0, -1)
	player.attack.begin(false)
	player.attack.tick(player.attack.active_start + 0.02, false)
	player.check_hits()
	check(target.hit_count == 1, "out of range cannot hit")
	player.position = Vector3(0, 0.05, -3.8)
	player.facing = Vector3(0, 0, 1)
	player.check_hits()
	check(target.hit_count == 1, "wrong facing cannot hit")
	game.reset_sample()
	check(target.hit_count == 0, "reset clears target hit count")
	check(player.position.distance_to(Vector3(0, 0.05, 8)) < 0.01, "reset restores spawn")
	check(player.attack.remaining == 0.0, "reset cancels active swing")
	var start: Vector3 = player.position
	Input.action_press("move_up")
	for frame in 30:
		await physics_frame
	Input.action_release("move_up")
	check(player.position.distance_to(start) > 0.8, "movement traverses scene")
	var walked: float = player.position.distance_to(start)
	game.reset_sample()
	start = player.position
	Input.action_press("move_up")
	Input.action_press("run")
	for frame in 30:
		await physics_frame
	Input.action_release("move_up")
	Input.action_release("run")
	check(player.position.distance_to(start) > walked * 1.6, "running meaningfully faster than walking")
	player.position = Vector3(0, 0.05, -3.0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_up")
	Input.action_press("move_right")
	Input.action_press("run")
	for frame in 45:
		await physics_frame
	Input.action_release("move_up")
	Input.action_release("move_right")
	Input.action_release("run")
	check(player.position.z > -4.6, "practice target collision prevents crossing")
	check(absf(player.position.y) < 0.08, "feet remain on ground")
	player.position = Vector3(13.4, 0.05, 0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_right")
	Input.action_press("move_down")
	for frame in 25:
		await physics_frame
	Input.action_release("move_right")
	Input.action_release("move_down")
	check(player.position.x <= 13.51, "map boundary prevents escape")
	player.position = Vector3(0, 0.05, -3.5)
	player.velocity = Vector3.ZERO
	var barrier := StaticBody3D.new()
	var barrier_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.4, 0.15)
	barrier_shape.shape = box
	barrier.add_child(barrier_shape)
	barrier.position = Vector3(0, 0.7, -4.2)
	root.add_child(barrier)
	await physics_frame
	await physics_frame
	check(not player.can_reach(target, 2.3), "solid obstruction blocks interaction and attack")
	Input.action_press("move_up")
	Input.action_press("move_right")
	Input.action_press("run")
	for frame in 30:
		await physics_frame
	Input.action_release("move_up")
	Input.action_release("move_right")
	Input.action_release("run")
	check(player.position.z > -4.0 and player.position.z < -3.6, "CharacterBody physically stops at an ordinary solid wall")
	barrier.queue_free()
	game.reset_sample()
	target.receive_hit(Vector3(0, 0, -1))
	for frame in 5:
		await physics_frame
	target.reset_target()
	for frame in 10:
		await physics_frame
	check(target.flash.scale.distance_to(Vector3.ONE) < 0.01, "reset cancels lingering impact ring tween")
	var original_animation_player = player.animation_player
	var fixture_player := AnimationPlayer.new()
	fixture_player.root_node = NodePath("..")
	player.add_child(fixture_player)
	var fixture_skeleton := Skeleton3D.new()
	fixture_skeleton.name = "RootMotionFixture"
	fixture_skeleton.add_bone("Root")
	fixture_skeleton.add_bone("RightHand")
	fixture_skeleton.set_bone_parent(1, 0)
	player.add_child(fixture_skeleton)
	player.animation_player = fixture_player
	var animation := Animation.new()
	var root_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(root_track, NodePath("RootMotionFixture:Root"))
	animation.track_insert_key(root_track, 0.0, Vector3(1, 2, 3))
	animation.track_insert_key(root_track, 1.0, Vector3(8, 5, 9))
	var hand_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hand_track, NodePath("RootMotionFixture:RightHand"))
	animation.track_insert_key(hand_track, 0.0, Vector3(0.1, 0.2, 0.3))
	animation.track_insert_key(hand_track, 1.0, Vector3(0.4, 0.5, 0.6))
	player.make_animation_in_place(animation)
	check(animation.track_get_key_value(root_track, 1) == Vector3(1, 5, 3), "animation travel removed while vertical root motion preserved")
	check(animation.track_get_key_value(hand_track, 1) == Vector3(0.4, 0.5, 0.6), "in place conversion preserves limb animation")
	player.animation_player = original_animation_player
	fixture_player.queue_free()
	fixture_skeleton.queue_free()
	game.set_night(true)
	check(game.night, "night toggle stores visible mode")
	game.set_night(false)
	check(not game.night, "day toggle restores visible mode")
	print("Playable integration: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
