extends SceneTree
const World=preload("res://scripts/cornfield/room_world.gd")
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
var failures:=0
var checks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func base()->Dictionary:
	var d:=Catalog.make_template(0);d.doors={"west":"w","east":"e"}
	d.entry_position=Vector3(4,0,d.size.y*.5)
	d.main_route=PackedVector3Array([d.entry_position,Vector3(d.size.x-4,0,d.size.y*.5)])
	return d
func run()->void:
	for label:String in ["unknown","missing","duplicate","disconnected","empty_graph","capacity"]:
		var room:=base()
		match label:
			"unknown":room.doors={"west":"w","upstairs":"e"}
			"missing":room.doors={"west":"w","":"e"}
			"duplicate":room.doors={"west":"same","east":"same"}
			"disconnected":room.obstacles.append({"id":"split","kind":"wall","rect":Rect2(room.size.x*.5,0,2,room.size.y),"height":2.0})
			"capacity":
				room.size=Vector2(40,2.5);room.outline=[Vector2.ZERO,Vector2(40,0),Vector2(40,2.5),Vector2(0,2.5)];room.obstacles=[]
				room.entry_position=Vector3(4,0,1.25);room.main_route=PackedVector3Array([room.entry_position,Vector3(36,0,1.25)])
		var w:=World.new();root.add_child(w)
		w.definition=room;w._outline=PackedVector2Array(room.outline);w._obstacles=room.obstacles
		w._build_boundary();w._build_navigation()
		if label=="empty_graph":w.navigation=AStar3D.new();w._cells.clear()
		w._build_spawn_domain()
		var p:=CharacterBody3D.new();w.add_child(p);p.position=room.entry_position
		var d:=Director.new();w.add_child(d);d.configure(w,p,room,3);d.set_physics_process(false)
		check(not str(d.metrics().content_error).is_empty(),"explicit static configuration error: "+label)
		check(d._stopped and not d.is_complete() and d.metrics().spawned==0 and d.metrics().reward_paid==0 and not w.doors_open,"invalid domain never falls back, spawns, pays or clears: "+label)
		w.free()
	print("DOOR_CONFIGURATION checks=%d failures=%d; zero/one-door policies explicitly excluded"%[checks,failures]);quit(1 if failures else 0)
