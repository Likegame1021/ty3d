extends SceneTree
const World=preload("res://scripts/cornfield/room_world.gd")
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Parcels=preload("res://scripts/cornfield/field_parcel_layout.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
var checks:=0
var failures:Array=[]
func _initialize()->void:
 var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../evidence"))
 if output_error != OK:
  printerr("FAIL: cannot create field QA evidence directory: ", output_error)
  quit(1);return
 call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);printerr("FAIL "+label)
func definition()->Dictionary:
 var d:Dictionary=Catalog.make_template(6)
 d.id="field_test";d.kind="combat";d.encounter="elite";d.elite=true;d.floor=1;d.content_revision=3;d.melee_fallback="beetle";d.doors={"west":"w","east":"e"};d.arrival_side="west";d.departure_side="east"
 d.entry_position=Catalog.door_position("west",d.size)+Catalog.door_inward("west")*4
 d.main_route=PackedVector3Array([d.entry_position,Vector3(d.size.x*.5,0,d.size.y*.5),Catalog.door_position("east",d.size)+Catalog.door_inward("east")*6])
 return d
func assert_baseline(w:Node3D,base:Node3D,label:String)->void:
 check(w._obstacles==base._obstacles,label+" exact baseline obstacles")
 check(w.navigation.get_point_ids()==base.navigation.get_point_ids(),label+" baseline graph ids")
 check(w.spawn_route_paths()==base.spawn_route_paths() and w.spawn_formation_anchors()==base.spawn_formation_anchors(),label+" frozen domain")
 check(w.find_children("*","NavigationRegion3D",true,false).size()==1,label+" one region")
 check(w.find_children("field_parcel_*","StaticBody3D",true,false).is_empty(),label+" no stale field body")
 check(w._field_edges.is_empty() and w._field_staged_bodies.is_empty() and w._field_edge_grid.is_empty(),label+" no retained candidate inventory")
func run()->void:
 var d:=definition();var original:Dictionary=d.duplicate(true)
 var base:=World.new();root.add_child(base);base.field_edges_enabled=false;base.field_parcels_enabled=false;base.build(d)
 var w:=World.new();root.add_child(w);w.field_parcels_enabled=true;w.field_edges_enabled=false;w.build(d)
 check(w.field_edge_report().status=="enabled","supported initial real build")
 var props:Array=Parcels.runtime_props(base)
 var broken:Dictionary={};broken[d.id+"_prop_0"]=true
 var drops:Dictionary={};drops[d.id+"_prop_0"]={"position":props[0].position,"kind":"coins"}
 w.build(d,{"broken":broken,"drops":drops})
 check(w.field_edge_report().status=="enabled","current-node broken prop/drop retained on revisit")
 var bad_drop:=Vector3(8,0,8)
 check(base.contains_ground(bad_drop,.22) and not base.path_to(d.entry_position,bad_drop,.22).is_empty(),"negative drop is reachable in original baseline")
 w.build(d,{"drops":{"unexpected":{"position":bad_drop,"kind":"coins"}}})
 check(w.field_edge_report().status=="rejected","full removed interior rejects retained drop")
 assert_baseline(w,base,"drop rejection")
 w.build(d);check(w.field_edge_report().status=="enabled","rejected to supported same instance")
 var actor:=CharacterBody3D.new();w.add_child(actor);actor.position=w.definition.entry_position
 var director:=Director.new();w.add_child(director);director.configure(w,actor,w.definition,1);director.set_physics_process(false);director._refresh_encounter_hint()
 var old_revision:int=w.dynamic_obstacle_revision;var old_generation:int=w.spawn_domain_generation;var old_cache:String=director._hint_ground_key
 check(not old_cache.is_empty(),"real doorway ground cache populated before rollback")
 var bad_candidates:Array=[Vector3(8,0,8)]
 check(not w.validate_field_prop_candidates(bad_candidates),"post-build actual prop mismatch rejected")
 check(w.dynamic_obstacle_revision>old_revision,"rollback invalidates live geometry cache revision")
 check(w.spawn_domain_generation==old_generation,"rollback preserves frozen domain generation")
 director._refresh_encounter_hint()
 check(director._hint_ground_key!=old_cache,"live doorway cache observes rollback revision")
 director.free();actor.free()
 assert_baseline(w,base,"actual prop rollback")
 w.build(d);check(w.field_edge_report().status=="enabled","rollback to supported same instance")
 check(not w.validate_field_spawned_content(),"missing expected live props rejects complete bundle")
 assert_baseline(w,base,"actual dynamic rollback")
 var drift:Dictionary=d.duplicate(true);drift.reward_position=Vector3(8,0,8)
 w.build(drift)
 check(w.field_edge_report().status=="rejected","identity-preserving reward drift rejected")
 check(w._field_edges.is_empty(),"reward drift keeps all field bodies absent")
 var unsupported:Dictionary=d.duplicate(true);unsupported.encounter="boss";w.build(unsupported)
 check(w.field_edge_report().status!="enabled","Boss role not converted")
 check(w._field_edges.is_empty(),"Boss has no candidate body")
 w.build(d);check(w.field_edge_report().status=="enabled","unsupported to supported same instance")
 check(d==original,"input definition never mutated")
 var f:=FileAccess.open("res://../evidence/rollout-rollback.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));f.close()
 print("FIELD_PARCEL_ROLLBACK checks=",checks," failures=",failures.size());w.free();base.free();quit(0 if failures.is_empty() else 1)
