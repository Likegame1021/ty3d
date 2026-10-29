extends SceneTree
## Accepted repeated damage renews the existing hurt timer. Its visual clock must
## renew with that timer; this does not change damage, grace or action priority.
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
	for i in count:
		# Position is irrelevant to this timer test. Avoid the unrelated fall reset.
		p.position.y = 0.0
		p.velocity.y = 0.0
		p._physics_process(DT)
		p.animation_player.advance(DT)

func run_checks() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var p = actor()
	var hurt_name: String = p.extra_animation_names["hurt"]
	var hurt_length: float = p.animation_player.get_animation(hurt_name).length
	var attack_profile := [p.attack.duration, p.attack.active_start, p.attack.active_end]
	check(p.receive_damage(7.0), "first damage is accepted")
	p.animation_player.advance(0.0)
	check(p.hp == 93.0 and p.hurt_cooldown == 0.65, "first hit preserves damage and 0.65 second grace")
	check(p.context_action == "hurt" and p.context_remaining == hurt_length, "first hit starts the full authored context duration")
	check(is_zero_approx(p.animation_player.current_animation_position), "first hit starts the hurt clip at zero")
	step(p, 12)
	var before_rejected_time: float = p.animation_player.current_animation_position
	var before_rejected_timer: float = p.context_remaining
	check(not p.receive_damage(7.0), "damage during grace is rejected")
	p.animation_player.advance(0.0)
	check(p.hp == 93.0 and p.context_remaining == before_rejected_timer, "rejected damage cannot renew logical hurt")
	check(p.animation_player.current_animation_position == before_rejected_time, "rejected damage cannot restart the visual clip")
	step(p, 28)
	check(p.hurt_cooldown == 0.0 and p.context_remaining > 0.0, "natural grace expiry overlaps the still active hurt clip")
	var old_visual_time: float = p.animation_player.current_animation_position
	check(old_visual_time > 0.65 and p.animation_player.current_animation == hurt_name, "repeat hit occurs in the actual same imported hurt clip")
	check(p.receive_damage(7.0), "repeat damage after grace is accepted")
	p.animation_player.advance(0.0)
	print("HURT_RENEWAL ", JSON.stringify({"old_visual_time": old_visual_time, "new_visual_time": p.animation_player.current_animation_position, "new_context_remaining": p.context_remaining, "authored_duration": hurt_length, "hp": p.hp, "grace": p.hurt_cooldown}))
	check(p.hp == 86.0 and p.hurt_cooldown == 0.65, "repeat hit preserves damage and grace")
	check(p.context_remaining == hurt_length and p.context_action == "hurt", "accepted renewal retains the existing full-duration policy")
	check(is_zero_approx(p.animation_player.current_animation_position), "accepted same-hurt renewal resets the visual clock with its logical timer")
	step(p, 1)
	check(absf(p.animation_player.current_animation_position - DT) < 0.00001, "renewed hurt advances from zero at the unchanged 1x rate")
	check(absf(p.context_remaining - (hurt_length - DT)) < 0.00001, "renewed logical hurt advances at its unchanged rate")
	check(p.animation_player.speed_scale == 1.0, "hurt playback speed remains unchanged")
	paused = true
	var paused_time: float = p.animation_player.current_animation_position
	var paused_timer: float = p.context_remaining
	check(not p.play_context_action("hurt"), "paused context request is rejected")
	check(p.context_remaining == paused_timer and p.animation_player.current_animation_position == paused_time, "paused request mutates neither clock")
	paused = false
	p.request_attack()
	p.animation_player.advance(0.0)
	check(p.attack.remaining > 0.0 and p.context_remaining == 0.0 and p.context_action == "", "attack input retains its existing priority over hurt")
	check(p.current_animation == "attack_branch" and is_zero_approx(p.animation_player.current_animation_position), "attack begins normally after hurt")
	step(p, 40)
	var attack_time: float = p.animation_player.current_animation_position
	var attack_remaining: float = p.attack.remaining
	check(p.receive_damage(7.0), "damage during a committed attack is accepted after grace")
	p.animation_player.advance(0.0)
	check(p.pending_context_action == "hurt" and p.context_remaining == 0.0, "hurt remains a single pending action behind the attack")
	check(p.attack.remaining == attack_remaining and p.animation_player.current_animation_position == attack_time, "queued hurt does not restart or interrupt the committed attack")
	check([p.attack.duration, p.attack.active_start, p.attack.active_end] == attack_profile, "damage and renewals preserve attack duration and contact window")
	var guard := 0
	while p.attack.remaining > 0.0 and guard < 120:
		step(p, 1)
		guard += 1
	check(guard < 120 and p.pending_context_action == "" and p.context_action == "" and p.context_remaining == 0.0, "chapter consumes an already expired queued hurt without a new movement penalty")
	check(p.current_animation != "hurt", "expired chapter queue does not replay the full old injury clip")
	p.free()
	await process_frame
	print("CORNFIELDS_HURT_RESTART %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
