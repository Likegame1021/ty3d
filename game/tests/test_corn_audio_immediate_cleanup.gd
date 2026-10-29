extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for index in 12:
		var fx=load("res://weapons/corn_gun_fx.gd").new()
		root.add_child(fx)
		fx.muzzle_flash(Vector3.ZERO,Vector3.FORWARD,false)
		fx.impact(Vector3.ZERO,Vector3.FORWARD,false)
		fx.set_charge(Vector3.ZERO,.8)
		# Intentionally release before AudioStreamPlayer3D's first physics tick.
		fx.clear_effects()
		assert(fx.get_child_count()==0)
		fx.free()
	await create_timer(.2).timeout
	print("CORN_AUDIO_IMMEDIATE_CLEANUP12 passed")
	quit()
