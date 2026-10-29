extends SceneTree
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
class CountingWorld:
	extends "res://scripts/cornfield/room_world.gd"
	var path_calls:=0
	func path_to(from:Vector3,to:Vector3,actor_radius:float=.3)->PackedVector3Array:
		path_calls+=1
		return super.path_to(from,to,actor_radius)
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	if not value:failures+=1;printerr("FAIL: "+label)
func run()->void:
	var room:=Catalog.make_template(0);room.doors={"west":"w","east":"e"}
	room.entry_position=Vector3(4,0,room.size.y*.5)
	room.main_route=PackedVector3Array([room.entry_position,Vector3(room.size.x-4,0,room.size.y*.5)])
	var w:=CountingWorld.new();root.add_child(w)
	w.definition=room;w._outline=PackedVector2Array(room.outline);w._obstacles=room.obstacles;w._build_boundary();w._build_navigation();w._normalize_room_anchors();w._build_spawn_domain()
	var p:=CharacterBody3D.new();w.add_child(p);p.position=Vector3(room.size.x*.75,0,room.size.y*.83)
	var c:=Camera3D.new();w.add_child(c);c.projection=Camera3D.PROJECTION_ORTHOGONAL;c.size=15;c.make_current()
	c.global_position=p.global_position+Vector3(15,19,15);c.look_at(p.global_position)
	var d:=Director.new();w.add_child(d);d.configure(w,p,w.definition,3);d.set_physics_process(false)
	await physics_frame;await physics_frame
	var candidate:=Vector3(room.size.x*.5,0,room.size.y*.5)
	check(w.is_in_spawn_domain(candidate,.34),"cost candidate is actual legal domain point")
	check(not d._warning_visible(candidate),"cost candidate is outside actual camera")
	var before:=w.path_calls
	var started:=Time.get_ticks_usec()
	check(not d._spawn_valid(candidate,.34),"offscreen spawn remains rejected")
	check(w.path_calls==before,"invisible legal spawn does not request expensive navigation")
	print("COST_SINGLE usec=",Time.get_ticks_usec()-started," path_calls=",w.path_calls-before)
	w.free();print("DOOR_SPAWN_COST failures=",failures);quit(1 if failures else 0)
