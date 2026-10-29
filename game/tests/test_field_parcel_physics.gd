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
 d.id="field_test";d.kind="combat";d.encounter="elite";d.elite=true;d.floor=1;d.content_revision=3;d.melee_fallback="beetle";d.arrival_side=c[2];d.departure_side=c[3]
 d.entry_position=Catalog.door_position(c[2],d.size)+Catalog.door_inward(c[2])*4
 d.main_route=PackedVector3Array([d.entry_position,Vector3(d.size.x*.5,0,d.size.y*.5),Catalog.door_position(c[3],d.size)+Catalog.door_inward(c[3])*6])
 return d
func quad_at(x:float,z:float)->PackedVector3Array:
 return PackedVector3Array([Vector3(x,0,z),Vector3(x,0,z+.9),Vector3(x+.9,0,z+.9),Vector3(x+.9,0,z)])
func run()->void:
 for c:Array in CASES:
  var d:=canonical(c);var key:String="%s/%d/%s>%s"%[d.template_id,c[1],c[2],c[3]]
  var baseline_native:Array=[]
  var baseline:=World.new();root.add_child(baseline);baseline.field_edges_enabled=false;baseline.field_parcels_enabled=false;baseline.build(d)
  await physics_frame;await physics_frame
  var original_map:RID=baseline.navigation_region.get_navigation_map()
  for attempt in 20:
   if NavigationServer3D.map_get_iteration_id(original_map)>0 and NavigationServer3D.map_get_closest_point_owner(original_map,baseline.definition.entry_position)==baseline.navigation_region.get_rid():break
   await physics_frame
  for side:String in d.doors:
   var landing:Vector3=baseline.get_door_position(side)+Catalog.door_inward(side)*4
   if landing.distance_to(d.entry_position)<.01:continue
   var original_path:PackedVector3Array=NavigationServer3D.map_get_path(original_map,d.entry_position,landing,true)
   var original_ok:bool=original_path.size()>1 and original_path[-1].distance_to(landing)<.9
   baseline_native.append({"side":side,"connected":original_ok,"path_points":original_path.size()})
   check(original_ok,key+" original baseline direct-native positive control "+side)
  baseline.free();await physics_frame
  var w:=World.new();root.add_child(w);w.field_parcels_enabled=true;w.build(d)
  check(w.field_edge_report().status=="enabled",key+" profile enabled")
  if w.field_edge_report().status!="enabled":w.free();continue
  await physics_frame;await physics_frame
  var map:RID=w.navigation_region.get_navigation_map()
  for attempt in 20:
   if NavigationServer3D.map_get_iteration_id(map)>0 and NavigationServer3D.map_get_closest_point_owner(map,w.definition.entry_position)==w.navigation_region.get_rid():break
   await physics_frame
  check(NavigationServer3D.map_get_closest_point_owner(map,w.definition.entry_position)==w.navigation_region.get_rid(),key+" current final native owner")
  for side:String in d.doors:
   var landing:Vector3=w.get_door_position(side)+Catalog.door_inward(side)*4
   if landing.distance_to(d.entry_position)<.01:continue
   var path:PackedVector3Array=NavigationServer3D.map_get_path(map,d.entry_position,landing,true)
   check(path.size()>1 and path[-1].distance_to(landing)<.9,key+" direct native arrival path "+side)
   for i in range(1,path.size()):check(not w._field_edges_touch(path[i-1],path[i],.22),key+" native path no thin boundary crossing")
  var space:PhysicsDirectSpaceState3D=w.get_world_3d().direct_space_state
  if d.template_id=="irrigation_bank":
   var bridge:Rect2=d.presentation.bridge_zones[0]
   check(w._bridge_quad_clear(quad_at(19.35,28.35)),key+" exact four-corner bridge quad admitted")
   check(not w._bridge_quad_clear(quad_at(bridge.position.x-2.1,28.35)),key+" partially outside authored bridge+2m approach rejected")
   check(not w._bridge_quad_clear(quad_at(19.35,bridge.position.y+.1)),key+" near-water quad retains full .65 clearance")
   check(not w._bridge_quad_clear(quad_at(19.35,bridge.end.y-.4)),key+" bridge-edge/partial quad rejected")
   for pair:Array in [["west","east"],["east","west"]]:
    var start:Vector3=w.get_door_position(pair[0])+Catalog.door_inward(pair[0])*4
    var goal:Vector3=w.get_door_position(pair[1])+Catalog.door_inward(pair[1])*4
    var crossing:PackedVector3Array=NavigationServer3D.map_get_path(map,start,goal,true)
    check(crossing.size()>1 and crossing[-1].distance_to(goal)<.9,key+" both-direction native bridge crossing "+str(pair))
    for index in range(1,crossing.size()):
     check(w._static_segment_clear(crossing[index-1],crossing[index],.65),key+" native bridge path keeps largest actor clearance")
     var near_bridge:=false
     for zone:Rect2 in d.presentation.bridge_zones:
      if zone.grow(2).has_point(Vector2(crossing[index].x,crossing[index].z)) or zone.grow(2).has_point(Vector2(crossing[index-1].x,crossing[index-1].z)):near_bridge=true
     if near_bridge:
      for radius:float in [.22,.3125,.65]:
       var capsule:=CapsuleShape3D.new();capsule.radius=radius;capsule.height=maxf(1.3,radius*2)
       var bridge_query:=PhysicsShapeQueryParameters3D.new();bridge_query.shape=capsule;bridge_query.collision_mask=1;bridge_query.transform=Transform3D(Basis.IDENTITY,crossing[index-1]+Vector3.UP*(capsule.height*.5+.04));bridge_query.motion=crossing[index]-crossing[index-1]
       var bridge_motion:PackedFloat32Array=space.cast_motion(bridge_query)
       check(bridge_motion.size()==2 and bridge_motion[0]>=.9999,key+" real capsule crosses authored bridge/bank at radius"+str(radius))
  var sweeps:=0;var clips:=0;var water_rays:=0
  for item:Dictionary in w._field_edges:
   var rect:Rect2=item.rect
   for radius:float in [.22,.3125,.65]:
    for normal:Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
     var extent:float=rect.size.x*.5 if normal.x!=0 else rect.size.y*.5
     var p:Vector2=rect.get_center()+normal*(extent+radius+.12);var at:=Vector3(p.x,0,p.y)
     if not w.contains_ground(at,radius):continue
     var shape:=CapsuleShape3D.new();shape.radius=radius;shape.height=maxf(1.3,radius*2)
     var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*(shape.height*.5+.04));query.motion=Vector3(-normal.x,0,-normal.y)*(radius+.5)
     check(space.intersect_shape(query,1).is_empty(),key+" legal capsule sweep starts free")
     var fractions:PackedFloat32Array=space.cast_motion(query)
     check(fractions.size()==2 and fractions[0]<1,key+" physical field stops capsule "+str(item.id));sweeps+=1
     if radius!=.22:continue
     var origin:=at+Vector3.UP*.65;var direction:=Vector3(-normal.x,0,-normal.y)
     var hit:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*2,1))
     var paths:Array=Director.projectile_warning_paths([{"origin":origin,"direction":direction,"speed":2.0,"lifetime":1.0,"muzzle_offset":Vector3.ZERO}],space)
     check(not hit.is_empty() and paths[0].blocked,key+" y.65 field clips actual projectile warning")
     if not hit.is_empty():check(paths[0].end.distance_to(hit.position)<.0001,key+" warning/physical clipping matches")
     clips+=1
   if item.kind=="fence" and rect.size.x>rect.size.y:
    for water:Dictionary in d.obstacles:
     if water.kind!="water":continue
     var wet:Rect2=water.rect;var z:float=rect.get_center().y
     if z<wet.position.y+.7 or z>wet.end.y-.7:continue
     if minf(absf(rect.end.x-wet.position.x),absf(rect.position.x-wet.end.x))>.0001:continue
     var x:float=wet.get_center().x
     var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,.65,z-.6),Vector3(x,.65,z+.6),1)
     check(space.intersect_ray(ray).is_empty(),key+" open water has no invisible projectile-height fence")
     water_rays+=1
  check(sweeps>=20,key+" exposed physical edge coverage")
  if d.template_id=="irrigation_bank":check(water_rays>=4,key+" both channel banks include water projectile controls")
  results.append({"key":key,"sweeps":sweeps,"clips":clips,"water_rays":water_rays,"baseline_native":baseline_native})
  w.free();await physics_frame
 var f:=FileAccess.open("res://../evidence/rollout-physics.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"\t"));f.close()
 print("FIELD_PARCEL_PHYSICS checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
