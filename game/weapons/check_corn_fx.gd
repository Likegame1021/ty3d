extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var visual_script = load("res://weapons/corn_gun_visual.gd")
	var fx_script = load("res://weapons/corn_gun_fx.gd")
	if not visual_script.can_instantiate() or not fx_script.can_instantiate():
		quit(1)
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var visual = visual_script.new()
	var fx = fx_script.new()
	holder.add_child(visual)
	holder.add_child(fx)
	assert(is_instance_valid(visual.muzzle))
	assert(visual.muzzle.position.z < -0.6)
	visual.set_charge(1.0)
	fx.set_charge(Vector3(0, 1, 0), 0.8)
	for frame in 4:
		await process_frame
	var charge_clock: float = fx._charge_clock
	paused = true
	for frame in 3:
		await process_frame
	assert(fx._charge_clock == charge_clock)
	assert(fx._charge_audio.stream_paused)
	paused = false
	fx.muzzle_flash(Vector3(0, 1, 0), Vector3.FORWARD, true)
	visual.kick(true)
	for index in 7:
		fx.tracer(Vector3(0, 1, 0), Vector3(float(index) - 3.0, 1, -8), true, index)
	assert(get_nodes_in_group("corn_tracers").size() == 7)
	fx.impact(Vector3(0, 1, -8), Vector3.FORWARD, true)
	fx.damage_number(Vector3(0, 1, -8), 24, true)
	await create_timer(0.10).timeout
	for index in 100:
		fx.tracer(Vector3.ZERO, Vector3(0, 0, -8), false)
	assert(fx._effects.size() <= fx.MAX_EFFECTS)
	fx.clear_effects()
	assert(fx.get_child_count() == 0)
	assert(get_nodes_in_group("corn_tracers").is_empty())
	fx.muzzle_flash(Vector3.ZERO, Vector3.FORWARD, false)
	fx.tracer(Vector3.ZERO, Vector3(0, 0, -8), false)
	fx.impact(Vector3(0, 0, -8), Vector3.FORWARD, false)
	fx.damage_number(Vector3.ZERO, 1, false)
	fx._process(1.0)
	assert(fx._effects.is_empty())
	assert(get_nodes_in_group("corn_tracers").is_empty())
	visual.reset_visual()
	assert(visual._body.transform == Transform3D.IDENTITY)
	fx.clear_effects()
	holder.free()
	await create_timer(0.15).timeout
	print("CORN_VISUAL_FX_LIFECYCLE_OK")
	quit(0)
