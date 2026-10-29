extends Node3D
## Visual-only adapter for reviewed nonhuman assets. The host owns AI, damage,
## collision, warnings and phase clocks. No asset is enabled by this module alone.
const REQUIRED_ACTIONS := ["idle","walk","windup","strike","hurt","death"]
var model:Node3D
var animator:AnimationPlayer
var skeletons:Array[Skeleton3D]=[]
var materials:Array[StandardMaterial3D]=[]
var _material_baselines:Array[Dictionary]=[]
var _clips:Dictionary={}
var _current_action:=""

func install(scene:PackedScene) -> bool:
	if scene==null or is_instance_valid(model):return false
	process_mode=Node.PROCESS_MODE_PAUSABLE
	var instance:=scene.instantiate()
	if not instance is Node3D:
		instance.free();return false
	model=instance
	add_child(model)
	for node in model.find_children("*","Skeleton3D",true,false):skeletons.append(node)
	var players:=model.find_children("*","AnimationPlayer",true,false)
	if players.is_empty() or skeletons.is_empty():
		_discard();return false
	animator=players[0]
	# Physics owns the clock; render FPS must not change attack anticipation.
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in animator.get_animation_list():
		var key:=str(clip).get_file().split("|")[-1].to_lower()
		if key in REQUIRED_ACTIONS:_clips[key]=str(clip)
	for action in REQUIRED_ACTIONS:
		if not _clips.has(action):
			_discard();return false
	# Imported materials otherwise share across every PackedScene instance.
	for node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:MeshInstance3D=node
		if mesh.mesh==null:continue
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override=_private_material(mesh.material_override)
		else:
			for surface in mesh.mesh.get_surface_count():
				var original:Material=mesh.get_active_material(surface)
				if original is StandardMaterial3D:
					mesh.set_surface_override_material(surface,_private_material(original))
	return true

func _private_material(original:StandardMaterial3D) -> StandardMaterial3D:
	# The material is private, immutable texture resources remain shared.
	var copy:StandardMaterial3D=original.duplicate()
	materials.append(copy)
	_material_baselines.append({"emission_enabled":copy.emission_enabled,"emission":copy.emission,"energy":copy.emission_energy_multiplier})
	return copy

func play_state(action:String,duration:float=1.0,elapsed:float=0.0) -> bool:
	if not is_instance_valid(animator):return false
	var selected:=action if _clips.has(action) else "idle"
	if selected==_current_action:return true
	_current_action=selected
	# Godot may remove constant rest tracks during GLB import. Reset and apply
	# the incoming clip in this same update so no previous attack pose survives
	# and no one-frame rest flash reaches rendering.
	animator.stop()
	for skeleton in skeletons:skeleton.reset_bone_poses()
	var name:String=_clips[selected]
	var clip:Animation=animator.get_animation(name)
	animator.play(name,0.0)
	animator.speed_scale=clip.length/maxf(duration,.01) if selected in ["windup","strike","hurt","death"] else 1.0
	animator.seek(clampf(elapsed/maxf(duration,.01),0,1)*clip.length,true)
	animator.advance(0)
	return true

func sample_state(action:String,duration:float,elapsed:float,speed_factor:float=1.0) -> void:
	if not play_state(action,duration,elapsed):return
	var clip:Animation=animator.get_animation(_clips[_current_action])
	var sample_time:=clampf(elapsed/maxf(duration,.01),0,1)*clip.length
	if _current_action in ["idle","walk"]:
		sample_time=fposmod(maxf(0,elapsed)*clampf(speed_factor,0,2.5),clip.length)
	animator.seek(sample_time,true)
	animator.advance(0)

func set_walk_speed(factor:float) -> void:
	if is_instance_valid(animator) and _current_action=="walk":
		animator.speed_scale=clampf(factor,0.0,2.5)

func set_hit_flash(amount:float) -> void:
	var weight:=clampf(amount,0,1)
	for index in materials.size():
		var material:=materials[index]
		var original:Dictionary=_material_baselines[index]
		material.emission_enabled=bool(original.emission_enabled) or weight>0
		material.emission=Color(original.emission).lerp(Color("fff0bd"),weight*.35)
		material.emission_energy_multiplier=float(original.energy)

func _discard() -> void:
	if is_instance_valid(model):model.free()
	model=null;animator=null
	skeletons.clear();materials.clear();_material_baselines.clear();_clips.clear()
