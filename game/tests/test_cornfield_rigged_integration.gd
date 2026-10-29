extends SceneTree
const Enemy=preload("res://scripts/cornfield/field_enemy.gd")
const Catalog=preload("res://scripts/cornfield/enemy_catalog.gd")
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func _run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var target:=Node3D.new();world.add_child(target)
	for species in ["beetle","boss_borer"]:
		for elite in [false,true]:
			var actor:=Enemy.new();world.add_child(actor)
			actor.configure(world,target,species,elite);actor.set_physics_process(false)
			var rigs:=actor.visual.find_children("*","Skeleton3D",true,false)
			check(rigs.size()==1,"accepted skeletal asset integrated for "+species)
			check(actor.visual.scale.is_equal_approx(Vector3.ONE),"world-sized asset has no duplicate boss scaling")
			check(actor.profile==Catalog.profile(species,elite),"visual adapter cannot change combat profile")
			var collider:CollisionShape3D=actor.get_child(0)
			check(is_equal_approx(collider.shape.radius,float(actor.profile.radius)/32.0),"original collider radius preserved")
			if rigs.is_empty():actor.queue_free();continue
			var animator:AnimationPlayer=actor.visual.find_children("*","AnimationPlayer",true,false)[0]
			check(animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"host physics drives animation")
			actor._prepare_windup(.5)
			actor.phase_time=.25
			actor._update_animation(0)
			var clip:Animation=animator.get_animation(animator.current_animation)
			check(is_equal_approx(animator.current_animation_position,clip.length*.5),"elite combo scales to authoritative windup progress")
			actor._start_strike();actor.phase_time=actor._phase_duration*.4
			actor._update_animation(0)
			clip=animator.get_animation(animator.current_animation)
			check(is_equal_approx(animator.current_animation_position,clip.length*.6),"strike uses exact phase progress")
			check(is_zero_approx(actor.visual.rotation.x) and actor.visual.scale.is_equal_approx(Vector3.ONE),"rig does not receive primitive pitch or squash")
			actor._hurt_time=.07;actor._update_animation(0)
			check(is_equal_approx(animator.current_animation_position,.07),"hurt sample matches remaining authoritative hurt time")
			actor._hurt_time=0;actor.phase="recover";actor._update_animation(0)
			check(actor.animation_state=="idle","strike and hurt cleanly return to idle")
			actor.take_damage(100000,Vector3.ZERO)
			actor._physics_process(.4)
			check(actor.dead and is_equal_approx(animator.current_animation_position,.4),"death visual samples existing cleanup clock")
			check(actor.collision_layer==0 and actor.collision_mask==0,"death immediately disables gameplay collider")
			actor.queue_free()
	var fallback:=Enemy.new();world.add_child(fallback)
	fallback.configure(world,target,"locust",false);fallback.set_physics_process(false)
	check(fallback.visual.find_children("*","Skeleton3D",true,false).is_empty(),"unreplaced species retain procedural visual")
	check(fallback.visual.find_children("*","MeshInstance3D",true,false).size()>=5,"procedural fallback keeps volumetric body parts")
	world.queue_free();await process_frame
	print("CORNFIELDS_RIGGED_INTEGRATION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
