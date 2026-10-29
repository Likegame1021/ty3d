extends "res://levels/full.gd"
## Reuse the shipped M2 corn-gun routines directly; only the chapter host changes.
## Inherited fire_gun, aim, charged scatter, sound, recoil and hit occlusion are untouched.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	progress.corn_gun = true
	progress.outcome = "playing"
	gun_equipped = true
	build_gun_visual()
	gun_fx = load("res://weapons/corn_gun_fx.gd").new()
	add_child(gun_fx)
	shot_fired.connect(on_corn_shot_feedback)

func _input(event: InputEvent) -> void:
	# A release may arrive between death/transition and the host's next tick.
	# Cancel before the inherited release handler can emit a stored shot.
	if not is_instance_valid(player) or not player.controls_enabled or player.hp <= 0.0:
		cancel_gun_input()
		return
	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or get_tree().paused or not player.controls_enabled or player.hp <= 0.0:
		return
	if event.is_action_pressed("attack"):
		if event is InputEventMouseButton:
			aim_screen = event.position
			mouse_aim_active = true
			update_corn_aim()
		fire_held = true
		if not charging:
			fire_gun(false)
	elif event.is_action_pressed("charge_shot"):
		if event is InputEventMouseButton:
			aim_screen = event.position
			mouse_aim_active = true
			update_corn_aim()
		charging = true
		charge_time = 0

func _physics_process(delta: float) -> void:
	if get_tree().paused or not player.controls_enabled or player.hp <= 0.0:
		cancel_gun_input()
		return
	fire_cooldown = maxf(0,fire_cooldown-delta)
	update_corn_aim()
	if charging:
		charge_time = minf(2,charge_time+delta)
	elif fire_held:
		fire_gun(false)

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	kick_clock += delta
	camera_kick = move_toward(camera_kick,0,delta*0.8)
	update_gun_transform()
	if is_instance_valid(gun_fx):
		gun_fx.set_charge(gun_model.muzzle.global_position,clampf(charge_time/CORN_CHARGE_SECONDS,0,1) if charging else 0.0)
