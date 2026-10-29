extends SceneTree
## A confirmed hit must be readable at the near surface of the rendered body,
## not hidden beneath its centre. Damage and physical colliders are untouched.
var checks:=0
var failures:Array[String]=[]
class VisualTarget extends Node3D:
	var visual:Node3D
	func _ready() -> void:
		visual=Node3D.new();add_child(visual)
		var body:=MeshInstance3D.new();var shape:=BoxMesh.new()
		shape.size=Vector3(1.0,1.2,1.4);body.mesh=shape;body.position.y=.6;visual.add_child(body)
func _initialize() -> void:call_deferred("run_checks")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL: ",label)
func run_checks() -> void:
	var feedback=load("res://scripts/cornfield/combat_feedback.gd").new();root.add_child(feedback);feedback.set_process(false)
	var target:=VisualTarget.new();root.add_child(target);target.position=Vector3(2,.05,3)
	feedback.emit_feedback("hit",{"position":target.global_position,"direction":Vector3.FORWARD,"source_actor":target})
	var at:Vector3=feedback._slots[0].node.global_position
	check(at.z>=target.global_position.z+.7,"contact tick is outside the incoming near face of the actual body bounds")
	check(absf(at.y-(target.global_position.y+.6))<.02,"contact height follows the real body centre instead of a fixed low offset")
	check(at.distance_to(target.global_position)<1.0,"feedback stays local to the struck creature")
	feedback.clear_all()
	target.rotation.y=PI*.5
	feedback.emit_feedback("hit",{"position":target.global_position,"direction":Vector3.LEFT,"source_actor":target})
	at=feedback._slots[0].node.global_position
	check(at.x>=target.global_position.x+.7,"rotated body bounds put lateral impacts on the visible incoming face")
	feedback.clear_all();target.rotation.y=0
	var body:MeshInstance3D=target.visual.get_child(0)
	var sphere:=SphereMesh.new();sphere.radius=1.0;sphere.height=2.0
	body.mesh=sphere;body.scale=Vector3(.5,.6,.7)
	var incoming:=Vector3(1,0,1).normalized()
	feedback.emit_feedback("hit",{"position":target.global_position,"direction":incoming,"source_actor":target})
	var surface:Vector3=feedback._slots[0].node.global_position+incoming*.015-body.global_position
	check(absf(pow(surface.x/.5,2)+pow(surface.z/.7,2)-1.0)<.001,"diagonal primitive contact lies on the actual ellipsoid, not its box corner")
	var world:=Node3D.new();root.add_child(world)
	var enemy=load("res://scripts/cornfield/field_enemy.gd").new();world.add_child(enemy)
	enemy.configure(world,null,"beetle");enemy.set_physics_process(false)
	var emitted:Array=[]
	enemy.feedback_requested.connect(func(kind,payload):emitted.append([kind,payload]))
	var original_hp:float=enemy.hp
	enemy.take_damage(18.0,Vector3.FORWARD)
	check(enemy.hp==original_hp-18.0,"cosmetic contact metadata does not change ordinary damage")
	check(emitted.size()==1 and emitted[0][0]=="hit" and emitted[0][1].get("source_actor")==enemy,"real confirmed hit passes its rendered actor to the decoration consumer")
	world.free();target.free();feedback.free();await process_frame
	print("CORNFIELDS_VFX_CONTACT: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
