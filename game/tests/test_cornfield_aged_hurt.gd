extends SceneTree
## Chapter policy: queued hurt expires from accepted damage, not attack completion.
const PLAYER = preload("res://scripts/cornfield/player.gd")
const DT := 1.0 / 60.0
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run_checks")

func actor():
	var p = PLAYER.new()
	root.add_child(p)
	p.set_physics_process(false)
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	p.animation_player.advance(0.0)
	return p

func step(p, count: int) -> void:
	for ignored in count:
		p.position.y = 0.0
		p.velocity.y = 0.0
		p._physics_process(DT)
		p.animation_player.advance(DT)

func queued_case(hit_tick: int, second_tick: int = -1, rejected_tick: int = -1, rank: float = 1.0) -> void:
	var p = actor()
	p.set_attack_recovery_multiplier(rank)
	var hurt_name: String = p.extra_animation_names.hurt
	var length: float = p.animation_player.get_animation(hurt_name).length
	p.request_attack()
	var profile := [p.attack.duration,p.attack.active_start,p.attack.active_end]
	var expected_ticks := ceili(p.attack.duration / DT)
	p.animation_player.advance(0.0)
	var tick := 0
	var latest := hit_tick
	var accepted := 0
	while p.attack.remaining > 0.0 and tick < 180:
		if tick == hit_tick or tick == second_tick:
			var remaining: float = p.attack.remaining
			check(p.receive_damage(7), "queued damage accepted at %d" % tick)
			accepted += 1
			latest = tick
			check(p.attack.remaining == remaining and p.pending_context_action == "hurt", "damage preserves committed attack and one queue")
		if tick == rejected_tick:
			check(not p.receive_damage(7), "grace rejects attempted queue refresh")
		step(p,1)
		tick += 1
	var age := float(tick-latest)*DT
	var expected := maxf(0.0,length-age)
	check(tick == expected_ticks, "unchanged ranked attack commitment ends on its original physics tick")
	check([p.attack.duration,p.attack.active_start,p.attack.active_end] == profile, "contact and commitment profile unchanged")
	check(is_equal_approx(p.hp,100.0-7.0*accepted), "only accepted damage changes health")
	check(p.pending_context_action == "", "pending reaction consumed once")
	check(absf(p.context_remaining-expected) < 0.00001, "queued tail equals accepted-hit expiry: hit %d latest %d expected %.6f actual %.6f" % [hit_tick,latest,expected,p.context_remaining])
	if expected > 0.00001:
		check(p.context_action == "hurt", "unexpired reaction keeps hurt label")
		check(absf(p.animation_player.current_animation_position-age) < 0.00001, "hurt destination is sought to real age rather than compressed")
		check(p.animation_player.speed_scale == 1.0, "aged hurt retains 1x playback")
	else:
		check(p.context_action == "", "expired queued reaction leaves no context label")
		check(p.current_animation != "hurt", "expired reaction does not start an obsolete hurt clip")
	print("AGED_HURT_CASE ",JSON.stringify({"hit_tick":hit_tick,"latest_tick":latest,"end_tick":tick,"expected_tail":expected,"actual_tail":p.context_remaining,"clip_position":p.animation_player.current_animation_position,"context":p.context_action}))
	p.free()

func lifecycle_checks() -> void:
	var p = actor()
	p.request_attack()
	step(p,70)
	check(p.receive_damage(7), "late queue accepted before lifecycle checks")
	var expiry: float = p._queued_hurt_expiry
	var clock: float = p._hurt_gameplay_clock
	var remaining: float = p.attack.remaining
	var pose_time: float = p.animation_player.current_animation_position
	paused = true
	p.set_physics_process(true)
	for ignored in 8:await process_frame
	p.set_physics_process(false)
	check(p._hurt_gameplay_clock == clock and p._queued_hurt_expiry == expiry, "raw tree pause freezes gameplay clock and queued expiry")
	check(p.attack.remaining == remaining and p.animation_player.current_animation_position == pose_time, "raw pause freezes actual attack and pose")
	check(not p.play_context_action("hurt"), "paused context request rejected")
	check(p._queued_hurt_expiry == expiry, "paused request does not consume expiry")
	paused = false
	check(not p.play_context_action("unknown_action"), "unknown context request rejected")
	check(p._queued_hurt_expiry == expiry, "unknown action cannot consume queued hurt")
	p.cancel_actions()
	check(p._queued_hurt_expiry < 0 and p.pending_context_action == "", "cancel clears pending reaction and expiry")
	p.request_attack()
	step(p,93)
	check(p.context_remaining == 0 and p.context_action == "", "cancelled queue cannot leak into next attack")
	p.hurt_cooldown = 0.0
	p.request_attack()
	step(p,70)
	p.receive_damage(7)
	p.reset_player()
	check(p._queued_hurt_expiry < 0 and p.pending_context_action == "", "reset clears queued expiry through normal cancellation")
	p.hurt_cooldown = 0.0
	p.request_attack()
	step(p,70)
	p.receive_damage(200)
	clock = p._hurt_gameplay_clock
	remaining = p.attack.remaining
	step(p,40)
	check(p.hp == 0 and p._hurt_gameplay_clock == clock and p.attack.remaining == remaining, "dead chapter cannot advance or drain queue before settlement")
	p.cancel_actions()
	check(p._queued_hurt_expiry < 0, "settlement cancellation clears a lethal pending reaction")
	p.free()
	var missing = actor()
	missing.extra_animation_names.erase("hurt")
	missing.request_attack()
	step(missing,70)
	check(missing.receive_damage(7), "missing-animation actor still receives ordinary damage")
	check(missing._queued_hurt_expiry < 0 and missing.pending_context_action == "", "missing hurt animation cannot arm phantom expiry")
	missing.free()

func run_checks() -> void:
	for action in ["move_left","move_right","move_up","move_down","run"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	for tick in [6,42,43,44,70,88,92]:
		queued_case(tick)
	queued_case(6,48)
	queued_case(70,-1,76)
	for rank in [.92,.8464]:
		queued_case(6,-1,-1,rank)
		queued_case(70,-1,-1,rank)
	await lifecycle_checks()
	await process_frame
	print("CORNFIELDS_AGED_HURT %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
