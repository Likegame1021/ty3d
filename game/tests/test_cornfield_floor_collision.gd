extends SceneTree
const Enemy=preload("res://scripts/cornfield/field_enemy.gd")
var checks:=0
var failures:=0
var observations:Array=[]
class Target extends Node3D:
	var hits:=0
	func receive_damage(_amount:float,_direction:Vector3) -> void:hits+=1
class World extends Node3D:
	func path_to(_from:Vector3,to:Vector3,_radius:float) -> PackedVector3Array:return PackedVector3Array([to])
	func contains_ground(_point:Vector3,_radius:float) -> bool:return true
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func box(parent:Node3D,at:Vector3,size:Vector3,rotation:Vector3=Vector3.ZERO) -> StaticBody3D:
	var body:=StaticBody3D.new();parent.add_child(body);body.position=at;body.rotation=rotation
	var shape:=CollisionShape3D.new();body.add_child(shape)
	var cuboid:=BoxShape3D.new();cuboid.size=size;shape.shape=cuboid
	return body
func attempt(species:String,mode:String,y:float=0) -> Dictionary:
	var world:=World.new();root.add_child(world)
	var slope:=deg_to_rad(10) if mode=="slope" else 0.0
	var normal:=Vector3.UP.rotated(Vector3.FORWARD,slope)
	box(world,-normal*.1,Vector3(40,.2,40),Vector3(0,0,-slope)).name="Ground"
	if mode=="wall":box(world,Vector3(1,1,0),Vector3(.2,2,8)).name="TrueWall"
	if mode=="corner":
		box(world,Vector3(1,1,0),Vector3(.2,2,8)).name="CornerX"
		box(world,Vector3(0,1,1),Vector3(8,2,.2)).name="CornerZ"
	var target:=Target.new();world.add_child(target);target.position=Vector3(-8 if mode=="slope" else 8,0,0)
	var actor:=Enemy.new();actor.set_physics_process(false);world.add_child(actor)
	actor.position=Vector3(0,y,0);actor.configure(world,target,species,false);actor.set_physics_process(false)
	actor.birth_time=2;actor.locked_target=target.position
	actor.strike_direction=Vector3(1,0,1).normalized() if mode=="corner" else Vector3.LEFT if mode=="slope" else Vector3.RIGHT
	await physics_frame;await physics_frame
	actor._start_strike()
	var origin:=actor.position
	var expected:float=actor._strike_speed*float(actor.profile.strike)
	var ticks:=0
	var contact_normals:Array=[]
	var horizontal_contact:=false
	while actor.phase=="strike" and ticks<100:
		await physics_frame
		actor._physics_process(1.0/60.0);ticks+=1
		for index in actor.get_slide_collision_count():
			var contact:KinematicCollision3D=actor.get_slide_collision(index)
			for item in contact.get_collision_count():
				var n:=contact.get_normal(item)
				contact_normals.append(str(n))
				horizontal_contact=horizontal_contact or absf(n.y)<.707
	var travel:=Vector2(actor.position.x-origin.x,actor.position.z-origin.z).length()
	var result:={"species":species,"mode":mode,"start_y":y,"travel":travel,"expected":expected,"ticks":ticks,"phase":actor.phase,"normals":contact_normals}
	observations.append(result)
	if mode in ["wall","corner"]:
		check(actor.phase=="recover" and travel<expected*.8,"true horizontal blocker ends "+species+" "+mode)
		check(travel>.02,"wall case travels before actual impact")
		check(horizontal_contact,"wall termination requires an actual lateral contact")
	else:
		check(ticks>=floori(float(actor.profile.strike)*60),"floor cannot truncate authored strike: "+species+" "+mode+" y="+str(y))
		check(travel>=expected*.85 and travel<=expected*1.12,"real traveled distance matches authored burst: "+species+" "+mode)
	check(actor.profile==load("res://scripts/cornfield/enemy_catalog.gd").profile(species,false),"combat profile untouched")
	world.queue_free();await process_frame
	return result
func bridge_attempt() -> void:
	var definition:Dictionary=load("res://scripts/cornfield/room_catalog.gd").make_template(2)
	var world=load("res://scripts/cornfield/room_world.gd").new();root.add_child(world);world.build(definition)
	for zone:Rect2 in definition.presentation.bridge_zones:
		for direction in [-1.0,1.0]:
			var center:=Vector3(zone.get_center().x,0,zone.get_center().y)
			var target:=Target.new();world.add_child(target);target.position=center+Vector3.RIGHT*direction*8
			var actor:=Enemy.new();world.add_child(actor)
			actor.position=center-Vector3.RIGHT*direction*2.2
			actor.configure(world,target,"boss_borer");actor.set_physics_process(false)
			actor.birth_time=2;actor.locked_target=target.position;actor.strike_direction=Vector3.RIGHT*direction
			check(world.contains_ground(actor.position,.625),"largest enemy begins on legal canal crossing")
			await physics_frame;await physics_frame
			actor._start_strike();var origin:=actor.position;var ticks:=0
			while actor.phase=="strike" and ticks<60:
				await physics_frame;actor._physics_process(1.0/60);ticks+=1
			var travel:=Vector2(actor.position.x-origin.x,actor.position.z-origin.z).length()
			check(ticks>=34 and travel>4.2,"real triangle floor/deck permits full charge across bridge")
			check(world.contains_ground(actor.position,.625),"charge ends on legal far bridge approach")
			observations.append({"species":"boss_borer","mode":"actual_bridge","direction":direction,"center":str(center),"ticks":ticks,"travel":travel})
			actor.queue_free();target.queue_free();await process_frame
	world.queue_free();await process_frame

func _run() -> void:
	for species in ["beetle","locust","mouse","boss_borer"]:
		await attempt(species,"floor")
		await attempt(species,"floor",-.02)
	await attempt("beetle","wall")
	await attempt("boss_borer","wall")
	await attempt("beetle","corner")
	await attempt("beetle","slope")
	await bridge_attempt()
	print("FLOOR_COLLISION_OBSERVATIONS ",JSON.stringify(observations))
	print("CORNFIELDS_FLOOR_COLLISION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
