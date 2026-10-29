extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func fixture() -> PackedScene:
	var model:=Node3D.new()
	var skeleton:=Skeleton3D.new()
	skeleton.name="Skeleton3D"
	model.add_child(skeleton);skeleton.owner=model
	skeleton.add_bone("root");skeleton.add_bone("head")
	skeleton.set_bone_parent(1,0)
	skeleton.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,.5,0)))
	var mesh:=MeshInstance3D.new()
	mesh.name="TexturedShell"
	var sphere:=SphereMesh.new();sphere.radius=.4;sphere.height=.8
	var material:=StandardMaterial3D.new();material.albedo_color=Color("456e3f");material.roughness=.83
	sphere.material=material;mesh.mesh=sphere
	model.add_child(mesh);mesh.owner=model
	var animator:=AnimationPlayer.new();animator.name="AnimationPlayer"
	model.add_child(animator);animator.owner=model
	var library:=AnimationLibrary.new()
	for action in ["idle","walk","windup","strike","hurt","death"]:
		var animation:=Animation.new();animation.length=1.0
		if action in ["idle","walk"]:animation.loop_mode=Animation.LOOP_LINEAR
		if action=="strike":
			var track:=animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track,NodePath("Skeleton3D:head"))
			animation.rotation_track_insert_key(track,0,Quaternion(Vector3.RIGHT,.8))
		library.add_animation(action,animation)
	animator.add_animation_library("",library)
	var scene:=PackedScene.new();scene.pack(model);model.free();return scene
func _run() -> void:
	var path:="res://scripts/cornfield/rigged_enemy_visual.gd"
	check(ResourceLoader.exists(path),"isolated rigged enemy visual adapter exists")
	if ResourceLoader.exists(path):
		var scene:=fixture()
		var first=load(path).new();var second=load(path).new()
		root.add_child(first);root.add_child(second)
		check(first.install(scene) and second.install(scene),"six-clip skeletal asset installs at unit scale")
		check(first.scale==Vector3.ONE and first.model.scale==Vector3.ONE,"world-sized model avoids legacy boss1.9 multiplier")
		check(first.materials[0]!=second.materials[0],"imported materials cloned per enemy")
		var second_color:Color=second.materials[0].albedo_color
		first.set_hit_flash(1.0)
		check(first.materials[0].emission_enabled and not second.materials[0].emission_enabled,"one hit cannot flash neighboring instances")
		check(second.materials[0].albedo_color==second_color and is_equal_approx(second.materials[0].roughness,.83),"texture-tint and roughness survive cloning")
		first.set_hit_flash(0)
		check(not first.materials[0].emission_enabled,"flash restores original material emission")
		check(first.play_state("strike",.36),"strike clip starts")
		check(first.skeletons[0].get_bone_pose_rotation(1).angle_to(Quaternion.IDENTITY)>.7,"strike actually drives imported bone")
		first.play_state("idle",1.0)
		check(first.skeletons[0].get_bone_pose_rotation(1).angle_to(Quaternion.IDENTITY)<.001,"constant omitted rest track cannot retain strike pose")
		first.play_state("windup",.65,.325)
		check(is_equal_approx(first.animator.current_animation_position,.5),"phase progress seeks matching clip position")
		check(is_equal_approx(first.animator.speed_scale,1.0/.65),"clip duration scales to authoritative windup")
		first.play_state("walk",1.0)
		first.set_walk_speed(1.12)
		check(is_equal_approx(first.animator.speed_scale,1.12),"elite walk follows measured movement speed")
		check(first.animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"render FPS cannot advance combat phase clips")
		check(first.has_method("sample_state"),"host can sample authoritative physics clock")
		if first.has_method("sample_state"):
			first.sample_state("windup",.65,.13)
			check(is_equal_approx(first.animator.current_animation_position,.2),"first host phase sample")
			first.sample_state("windup",.65,.39)
			check(is_equal_approx(first.animator.current_animation_position,.6),"repeated action resamples authoritative phase")
			first.sample_state("walk",1.0,1.25,1.2)
			check(is_equal_approx(first.animator.current_animation_position,.5),"walk wraps by measured movement speed")
			first.sample_state("death",.8,1.0)
			check(is_equal_approx(first.animator.current_animation_position,1.0),"one-shot death clamps at authored endpoint")
		paused=true
		var old:float=first.animator.current_animation_position
		await process_frame;await process_frame
		check(first.animator.current_animation_position==old,"rig pauses with combat")
		paused=false
		first.queue_free();second.queue_free()
		await process_frame
	print("CORNFIELDS_RIGGED_VISUAL %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
