extends SceneTree
const Director = preload("res://scripts/cornfield/encounter_director.gd")
var failures: Array[String] = []
var checks := 0
class Source extends Node3D:
	var dead := false
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func _run() -> void:
	var director := Director.new()
	root.add_child(director)
	var source := Source.new()
	root.add_child(source)
	for hazard in [false,true]:
		var warning := Director.AttackWarning.new()
		warning.payload = {"origin":Vector3.ZERO,"radius":1.0,"length":4.0,"direction":Vector3.FORWARD,"duration":1.0,"source_actor":source,"hazard":hazard,"damage":10.0,"pattern":"charge"}
		director.add_child(warning)
		check(warning.has_node("DangerBoundary"),"danger boundary is a separate high-priority outline")
		if warning.has_node("DangerBoundary"):
			var boundary: MeshInstance3D = warning.get_node("DangerBoundary")
			check(boundary.material_override.render_priority>=5,"danger outline priority exceeds decorations")
			if not hazard:
				var bounds: AABB=boundary.mesh.get_aabb()
				check(bounds.end.z>=.94 and bounds.position.z<=-4.94,"charge boundary includes both melee-radius end caps")
			check(warning.has_node("DangerSymbol"),"circle and charge carry distinct noncolor shapes")
			var original_scale: Vector3 = boundary.scale
			warning._physics_process(.3)
			check(boundary.scale==original_scale,"telegraph pulse never changes apparent collision radius")
		warning.queue_free()
	await process_frame
	var player=load("res://scripts/cornfield/player.gd").new()
	root.add_child(player)
	player.position=Vector3(.7,0,0)
	player.set_physics_process(false)
	var enemy=load("res://scripts/cornfield/field_enemy.gd").new()
	director.add_child(enemy)
	enemy.configure(director,player,"beetle")
	enemy.set_physics_process(false)
	var warnings:Array=[]
	enemy.warning_requested.connect(func(payload:Dictionary):warnings.append(payload))
	enemy._prepare_windup(.65)
	check(not warnings.is_empty() and float(warnings[0].radius)>=.72,"beetle warning covers existing0.72m damage reach")
	enemy.birth_time=1.0
	enemy._try_melee_hit()
	check(player.hp==91.0,"actual melee still hits at lateral0.70m without combat-stat change")
	player.queue_free()
	director.queue_free()
	source.queue_free()
	await process_frame
	print("CORNFIELDS_DANGER_READABILITY %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
