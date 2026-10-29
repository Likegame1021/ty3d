extends SceneTree
const World=preload("res://scripts/cornfield/room_world.gd")
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
const SIDES=["north","east","south","west"]
const CASES=[[6,10,"west","east"],[9,9,"west","north"],[5,7,"north","east"],[10,15,"west","east"],[2,10,"west","east"],[9,7,"north","east"]]
var checks:=0
var failures:Array=[]
var results:Array=[]
func _initialize()->void:
 var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../evidence"))
 if output_error != OK:
  printerr("FAIL: cannot create field QA evidence directory: ", output_error)
  quit(1);return
 call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);printerr("FAIL "+label)
func canonical(c:Array)->Dictionary:
 var d:Dictionary=Catalog.make_template(c[0]);d.doors={}
 for i in 4:
  if int(c[1])&(1<<i):d.doors[SIDES[i]]=SIDES[i]
 d.id="field_test";d.kind="combat";d.encounter="elite";d.elite=true;d.floor=1;d.content_revision=3;d.melee_fallback="beetle"
 d.arrival_side=c[2];d.departure_side=c[3]
 d.entry_position=Catalog.door_position(c[2],d.size)+Catalog.door_inward(c[2])*4.0
 d.main_route=PackedVector3Array([d.entry_position,Vector3(d.size.x*.5,0,d.size.y*.5),Catalog.door_position(c[3],d.size)+Catalog.door_inward(c[3])*6.0])
 return d
func schedule(w:Node3D,floor_number:int,revision:int,elite:bool)->Dictionary:
 var d:Dictionary=w.definition.duplicate(true);d.floor=floor_number;d.content_revision=revision;d.elite=elite;d.encounter="elite" if elite else "swarm"
 var actor:=CharacterBody3D.new();w.add_child(actor);actor.position=d.entry_position
 var director:=Director.new();w.add_child(director);director.configure(w,actor,d,floor_number);director.set_physics_process(false)
 var out:Dictionary={"groups":director.group_schedule().duplicate(true),"segments":director.segments.duplicate(true),"planned":director.metrics().planned,"reward":director.metrics().reward_budget}
 director.free();actor.free();return out
func run()->void:
 for c:Array in CASES:
  var d:=canonical(c);var key:String="%s/%d/%s>%s"%[d.template_id,c[1],c[2],c[3]]
  var baseline:=World.new();root.add_child(baseline);baseline.field_edges_enabled=false;baseline.field_parcels_enabled=false;baseline.build(d)
  var candidate:=World.new();root.add_child(candidate)
  if "field_parcels_enabled" in candidate:candidate.field_parcels_enabled=true
  var started:=Time.get_ticks_usec()
  candidate.build(d)
  var build_usec:=Time.get_ticks_usec()-started
  var r:Dictionary=candidate.field_edge_report();results.append({"key":key,"report":r,"candidate_build_usec":build_usec})
  print("FIELD_CASE ",key," status=",r.status," reason=",r.get("reason","")," build_usec=",build_usec," filter_usec=",r.get("static_validation_and_filter_usec",0))
  check(r.status=="enabled" and str(r.get("profile_id","")).begins_with("parcel:"),key+" generic parcel enabled: "+str(r.get("reason","")))
  if r.status!="enabled" or not str(r.get("profile_id","")).begins_with("parcel:"):
   baseline.free();candidate.free();continue
  check(candidate.definition==baseline.definition,key+" baseline definition preserved")
  check(candidate.spawn_route_paths()==baseline.spawn_route_paths(),key+" frozen pair paths preserved")
  check(candidate.spawn_formation_anchors()==baseline.spawn_formation_anchors(),key+" all frozen slots preserved")
  check(candidate.find_children("*","NavigationRegion3D",true,false).size()==1,key+" one final region")
  for side:String in d.doors:
   var landing:Vector3=candidate.get_door_position(side)+Catalog.door_inward(side)*4
   check(candidate._nearest_reachable_node(landing,.65)>=0,key+" actual player arrival "+side)
  for a:Dictionary in candidate.spawn_formation_anchors():
   check(candidate._nearest_reachable_node(a.point,.34)>=0,key+" anchor reachable")
   for p:Vector3 in a.slots:check(candidate._nearest_reachable_node(p,.34)>=0,key+" frozen slot reachable")
  for floor_number in range(1,4):
   for revision in [2,3]:
    for elite in [false,true]:check(schedule(candidate,floor_number,revision,elite)==schedule(baseline,floor_number,revision,elite),key+" schedule unchanged floor/revision/role")
  for item:Dictionary in candidate._field_edges:
   if item.kind!="fence":continue
   for old:Dictionary in d.obstacles:
    if old.kind=="water":check(not Rect2(item.rect).intersects(old.rect),key+" no fence collider in water")
  check(int(r.get("new_boxes",99))<=22 and int(r.get("corn_instances",999))<=96 and int(r.get("fence_modules",999))<=125 and int(r.get("source_triangles",999999))<=120000,key+" final cost ledger")
  baseline.free();candidate.free()
 var out={"checks":checks,"failures":failures,"cases":results}
 var path:String=OS.get_environment("FIELD_TEST_OUTPUT")
 if path.is_empty():path="res://../evidence/rollout-focused.json"
 var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(out,"\t"));f.close()
 print("FIELD_PARCELS checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
