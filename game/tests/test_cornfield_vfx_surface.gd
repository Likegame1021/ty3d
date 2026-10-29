extends SceneTree
## Compare VFX against independently generated triangle anchors on real
## shipped rigs. A box-only fixture cannot catch antenna/leg-expanded bounds.
var failures:Array[String]=[]
var checks:=0
func _initialize() -> void:call_deferred("run_checks")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL: ",label)
func vector(value:Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func run_checks() -> void:
	var path:="res://scripts/cornfield/contact_anchors.json"
	check(FileAccess.file_exists(path),"body-triangle anchor data exists")
	if not FileAccess.file_exists(path):finish();return
	var profiles=JSON.parse_string(FileAccess.get_file_as_string(path))
	if profiles.has("species"):profiles=profiles.species
	var feedback=load("res://scripts/cornfield/combat_feedback.gd").new();root.add_child(feedback);feedback.set_process(false)
	var world:=Node3D.new();root.add_child(world)
	for species:String in ["beetle","boss_borer"]:
		check(profiles.has(species),"real rig has a generated body surface table: "+species)
		if not profiles.has(species):continue
		var profile:Dictionary=profiles[species]
		var actor=load("res://scripts/cornfield/field_enemy.gd").new();world.add_child(actor)
		actor.configure(world,null,species);actor.set_physics_process(false)
		var skeleton:Skeleton3D=actor.visual.find_children("*","Skeleton3D",true,false)[0]
		check(profile.anchors.size()==32,"all32approaches are body-triangle samples: "+species)
		skeleton.reset_bone_poses()
		for anchor:Dictionary in profile.anchors:
			var reconstructed:=Vector3.ZERO
			for influence:Dictionary in anchor.influences:
				var bone:=skeleton.find_bone(str(influence.bone))
				if bone<0:continue
				var pose:=skeleton.get_bone_global_pose(bone)
				reconstructed+=pose.basis*vector(influence.weighted_local)+pose.origin*float(influence.weight)
			var imported:Vector3=skeleton.global_transform*reconstructed
			check(imported.distance_to(actor.visual.global_transform*vector(anchor.point))<.001,"actual Godot bind hierarchy reconstructs the source triangle point")
		for action:String in ["idle","windup","strike","hurt"]:
			actor._rigged_visual.sample_state(action,1.0,.35)
			for yaw in [0.0,1.1]:
				actor.visual.rotation.y=yaw
				for anchor:Dictionary in profile.anchors:
					var expected:=Vector3.ZERO
					var valid:=true
					var total:=0.0
					for influence:Dictionary in anchor.influences:
						var bone:=skeleton.find_bone(str(influence.bone))
						if bone<0:valid=false;break
						var pose:=skeleton.get_bone_global_pose(bone)
						expected+=pose.basis*vector(influence.weighted_local)+pose.origin*float(influence.weight)
						total+=float(influence.weight)
					check(valid and absf(total-1.0)<.00001,"surface sample uses valid bones and normalized weights")
					if not valid:continue
					expected=skeleton.global_transform*expected
					var outward:Vector3=(actor.visual.global_basis*vector(anchor.direction)).normalized()
					feedback.clear_all()
					feedback.emit_feedback("hit",{"position":actor.global_position,"direction":-outward,"source_actor":actor,"species":species})
					var got:Vector3=feedback._slots[0].node.global_position
					check(got.distance_to(expected+outward*.015)<.002,"posed shell anchor stays15mm from sampled triangle: "+species+"/"+action+"/"+str(anchor.direction))
		actor.free()
	world.free();feedback.free();await process_frame
	finish()
func finish() -> void:
	print("CORNFIELDS_VFX_SURFACE: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
