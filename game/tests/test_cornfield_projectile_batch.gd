extends SceneTree
const Director=preload("res://scripts/cornfield/encounter_director.gd")
var failures:=0
var checks:=0
var native_readback:=false
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func _run() -> void:
	native_readback=DisplayServer.get_name()!="headless"
	var path:="res://scripts/cornfield/projectile_batch.gd"
	check(ResourceLoader.exists(path),"bounded projectile visual batch exists")
	if ResourceLoader.exists(path):
		var parent:=Node3D.new();root.add_child(parent)
		parent.position=Vector3(5,2,-3);parent.rotation.y=.4
		var batch=load(path).new();parent.add_child(batch)
		var actors:Array=[]
		for index in 80:
			var actor:=Node3D.new();root.add_child(actor)
			actor.position=Vector3(index*.2,.6,2);actors.append(actor)
		batch.sync_projectiles(actors)
		check(batch.multimesh.visible_instance_count==80,"all80existing projectiles remain drawn")
		check(batch.multimesh.instance_count==80,"visual capacity matches unchanged gameplaycap")
		for index in 80:
			var actual:Transform3D=batch.global_transform*batch.multimesh.get_instance_transform(index)
			if native_readback:
				check(actual.is_equal_approx(actors[index].global_transform),"batch preserves exact world transform%d"%index)
			else:
				check(batch.custom_aabb.grow(.001).has_point(batch.to_local(actors[index].global_position)),"explicit culling bounds retain projectile%d"%index)
		var sphere:SphereMesh=batch.multimesh.mesh
		check(is_equal_approx(sphere.radius,.11) and is_equal_approx(sphere.height,.22) and sphere.get_faces().size()/3==288,"same accepted projectile geometry")
		check(batch.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"contact shadows stay enabled")
		check(batch.material_override.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and batch.material_override.albedo_color==Color(.93,.72,.22),"same gold unshaded material")
		actors[0].position=Vector3(17,.6,-7);batch.sync_projectiles(actors)
		if native_readback:
			check((batch.global_transform*batch.multimesh.get_instance_transform(0)).origin.is_equal_approx(actors[0].position),"moved projectile follows real node")
		else:
			check(batch.custom_aabb.grow(.001).has_point(batch.to_local(actors[0].global_position)),"moved projectile remains inside explicit culling bounds")
		actors[0].queue_free();batch.sync_projectiles(actors)
		check(batch.multimesh.visible_instance_count==79,"queued deletion cannot leave a ghost projectile")
		batch.clear()
		check(batch.multimesh.visible_instance_count==0,"room clear removes all visuals immediately")
		for actor in actors:if is_instance_valid(actor):actor.queue_free()
		parent.queue_free();await process_frame
	var director:=Director.new();root.add_child(director)
	director._stopped=false;director._complete=false;director.set_physics_process(false)
	for index in 81:
		director._spawn_projectile({"origin":Vector3(index*.1,.6,0),"direction":Vector3.FORWARD,"speed":4.9,"lifetime":2.6})
	for projectile in director._projectiles:projectile.set_physics_process(false)
	check(director._projectiles.size()==80,"same80node gameplaycap")
	var batches:=director.find_children("*","MultiMeshInstance3D",false,false)
	check(batches.size()==1,"director uses one visual draw batch")
	check(director._projectiles[0].get_child_count()==0,"batched projectile keeps logic without duplicate visual")
	director.shutdown();check(director.get_child_count()==0,"shutdown detaches visual and gameplay children")
	director.queue_free();await process_frame
	print("CORNFIELDS_PROJECTILE_BATCH %d checks, %d failures; native_transform_readback=%s"%[checks,failures,native_readback])
	if not native_readback:print("Dummy rendering cannot read MultiMesh transforms:81 exact-transform assertions require the native run; headless checks only explicit bounds instead.")
	quit(1 if failures else 0)
