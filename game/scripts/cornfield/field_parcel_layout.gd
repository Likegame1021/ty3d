extends RefCounted
## Compact exact-coordinate proposals. Activation is explicit while native gates
## remain open; source hashes are provenance only and never runtime predicates.
const Edges=preload("res://scripts/cornfield/field_edge_layout.gd")
const SIDES=["north","east","south","west"]
const EPS:=.0001
static var _lookup:Dictionary={}
static func lookup()->Dictionary:
 if _lookup.is_empty():
  var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/field_parcel_lookup.json"))
  if parsed is Dictionary:_lookup=parsed
 return _lookup
static func key_for(d:Dictionary)->String:
 var mask:=0
 for i in 4:
  if d.get("doors",{}).has(SIDES[i]):mask|=1<<i
 return "%s/%d/%s>%s"%[d.get("template_id",""),mask,d.get("arrival_side",""),d.get("departure_side","")]
static func applies(d:Dictionary)->bool:
 return str(d.get("encounter","")) in ["swarm","combat","elite"] and str(d.get("kind","")) in ["combat","exit"] and not bool(d.get("has_toolheap",false)) and d.get("doors",{}).size()>=2 and not str(d.get("arrival_side","")).is_empty() and str(d.get("arrival_side",""))!=str(d.get("departure_side",""))
static func rejected(key:String,reason:String,status:String="rejected")->Dictionary:
 return {"status":status,"profile_id":"parcel:"+key,"reason":reason,"validation_only":true}
static func vector(p:Array)->Vector3:return Vector3(float(p[0]),0,float(p[1]))
static func rectangle(r:Array)->Rect2:return Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
static func close(actual:Variant,expected:Variant)->bool:
 if actual is Vector3:actual=[actual.x,actual.z]
 elif actual is Vector2:actual=[actual.x,actual.y]
 elif actual is Rect2:actual=[actual.position.x,actual.position.y,actual.size.x,actual.size.y]
 if expected is Array:
  if not (actual is Array or actual is PackedVector3Array or actual is PackedVector2Array) or actual.size()!=expected.size():return false
  for i in expected.size():
   if not close(actual[i],expected[i]):return false
  return true
 if expected is float or expected is int:return (actual is float or actual is int) and absf(float(actual)-float(expected))<=EPS
 return actual==expected
static func runtime_props(world:Node3D)->Array:
 var candidates:Array[Vector3]=[]
 var route:PackedVector3Array=world.definition.main_route
 for i in range(1,route.size()-1):
  for offset:Vector3 in [Vector3(2.1,0,1.4),Vector3(-2.1,0,-1.4)]:
   var at:Vector3=route[i]+offset
   if world.contains_ground(at,.6):candidates.append(at)
 var out:Array=[]
 for i in mini(5,candidates.size()):
  var kind:String=["jar","crate","hay"][i%3]
  out.append({"index":i,"kind":kind,"position":candidates[i],"radius":.45 if kind=="hay" else .34})
 return out
static func path3(raw:Array,start:Vector3)->PackedVector3Array:
 var out:=PackedVector3Array([start])
 for p:Array in raw:
  var at:=vector(p)
  if at.distance_squared_to(out[-1])>.00000001:out.append(at)
 return out
static func propose(world:Node3D,room_state:Dictionary)->Dictionary:
 var d:Dictionary=world.definition;var key:=key_for(d);var book:=lookup()
 if not applies(d) or not book.get("states",{}).has(key):return rejected(key,"unsupported hostile/mask/canonical construction","unsupported")
 var state:Dictionary=book.states[key]
 if state.design_status!="geometry_design_candidate":return rejected(key,str(state.design_status),str(state.design_status))
 if not bool(state.get("runtime_enabled",false)):return rejected(key,"profile is not enabled in the validated manifest","disabled_profile")
 var expected:Dictionary=book.templates[state.template]
 if not close(d.size,expected.size) or not close(world._outline,expected.outline):return rejected(key,"original size/outline changed")
 if world._obstacles.size()!=expected.obstacles.size():return rejected(key,"original obstacle count changed")
 for i in world._obstacles.size():
  for field:String in ["id","kind","rect","height"]:
   if not close(world._obstacles[i].get(field),expected.obstacles[i][field]):return rejected(key,"original obstacle "+field+" changed")
 if not close(d.get("presentation",{}).get("bridge_zones",[]),expected.bridge_zones):return rejected(key,"original bridge geometry changed")
 if not close(d.main_route,state.expected_normalized_main_route):return rejected(key,"normalized route coordinates changed")
 if not close(d.service_position,state.expected_service_position) or not close(d.reward_position,state.expected_reward_position):return rejected(key,"retained anchor coordinates changed")
 if world.spawn_domain_error()!="" or world.spawn_route_paths().is_empty():return rejected(key,"baseline spawn domain unavailable")
 var props:=runtime_props(world)
 if props.size()!=state.expected_runtime_props.size():return rejected(key,"runtime prop candidate count changed")
 for i in props.size():
  for field:String in ["index","kind","position","radius"]:
   if not close(props[i][field],state.expected_runtime_props[i][field]):return rejected(key,"runtime prop candidate changed")
 var geometry:Dictionary=book.geometries[state.geometry_id]
 var added:Array[Dictionary]=[];var removed:Array[Rect2]=[]
 for parcel:Dictionary in geometry.parcels:removed.append(rectangle(parcel.rect))
 for i in geometry.fence_rects.size():
  added.append({"id":"field_parcel_fence_%d"%i,"kind":"fence","rect":rectangle(geometry.fence_rects[i]),"height":1.1,"field_edge":true,"field_full_span":true})
 for bed:Dictionary in geometry.beds:
  added.append({"id":"field_parcel_"+str(bed.id),"kind":"corn","rect":rectangle(bed.rect),"height":1.65,"field_edge":true,"corn_count":int(bed.corn_count),"columns":int(bed.columns),"rows":int(bed.rows),"row_axis":"x"})
 if added.size()>22:return rejected(key,"final collider count exceeds22")
 var paths:Array=[];var points:Array=[];var static_points:Dictionary={}
 for path:PackedVector3Array in world.spawn_route_paths():
  paths.append({"path":path,"radius":6.2,"kind":"frozen pair path"})
  for point:Vector3 in path:static_points[point]=.65
 paths.append({"path":d.main_route,"radius":6.2,"kind":"frozen main route"})
 for side:String in d.doors:
  var door:Vector3=world.get_door_position(side);var landing:Vector3=door+world.Catalog.door_inward(side)*4
  paths.append({"path":PackedVector3Array([door,landing]),"radius":4.5,"kind":"door landing"});static_points[landing]=.65
 for p:Vector3 in d.main_route:static_points[p]=.65
 for key_name:String in ["service_position","reward_position"]:
  points.append({"point":d[key_name],"radius":3.6,"kind":key_name});static_points[d[key_name]]=.3
 for anchor:Dictionary in world.spawn_formation_anchors():
  static_points[anchor.point]=.34
  for p:Vector3 in anchor.slots:static_points[p]=.34
 for p:Vector3 in static_points:points.append({"point":p,"radius":static_points[p],"kind":"frozen static destination"})
 var approaches:Array[Vector3]=[]
 for prop:Dictionary in props:points.append({"point":prop.position,"radius":float(prop.radius)+.6,"kind":"runtime prop footprint"})
 for access:Dictionary in state.expected_prop_access:
  var at:=vector(access.position);approaches.append(at)
  paths.append({"path":path3(access.path,d.entry_position),"radius":1.85,"kind":"runtime prop approach"})
 var reward_path:=path3(state.expected_reward_access,d.entry_position)
 paths.append({"path":reward_path,"radius":1.85,"kind":"reward approach"});approaches.append(d.reward_position)
 # Current-node drops are transient Game state, never a new disk schema. Freeze
 # legal baseline access before any graph/obstacle change; unexpected positions
 # are retained with that path or rejected as one complete profile.
 var drops:Array[Vector3]=[]
 for record:Dictionary in room_state.get("drops",{}).values():
  var at:Vector3=record.get("position",Vector3.INF)
  if not at.is_finite() or not world.contains_ground(at,.22):return rejected(key,"retained drop is not baseline legal")
  var access:PackedVector3Array=world.path_to(d.entry_position,at,.22)
  if access.is_empty():return rejected(key,"retained drop has no baseline access")
  drops.append(at);points.append({"point":at,"radius":.3,"kind":"retained drop"})
  var full:=PackedVector3Array([d.entry_position]);full.append_array(access)
  paths.append({"path":full,"radius":1.85,"kind":"retained drop access"})
 var all_rects:Array[Rect2]=removed.duplicate()
 for item:Dictionary in added:all_rects.append(item.rect)
 for rect:Rect2 in all_rects:
  for reserve:Dictionary in paths:
   var route:PackedVector3Array=reserve.path
   for i in range(1,route.size()):
    if Edges.segment_rect_distance(route[i-1],route[i],rect)<float(reserve.radius)-.00001:return rejected(key,"removed interior/solid enters "+str(reserve.kind))
  for reserve:Dictionary in points:
   if Edges.point_rect_distance(Vector2(reserve.point.x,reserve.point.z),rect)<float(reserve.radius)-.00001:return rejected(key,"removed interior/solid enters "+str(reserve.kind))
  for bridge:Rect2 in d.get("presentation",{}).get("bridge_zones",[]):
   if rect.intersects(bridge.grow(2)):return rejected(key,"removed interior/solid enters bridge approach")
 for item:Dictionary in added:
  if item.kind!="fence":continue
  for obstacle:Dictionary in world._obstacles:
   if obstacle.kind in ["water","void"] and Rect2(item.rect).intersects(obstacle.rect):return rejected(key,"fence enters actual water/void")
 var modules:=0;var batches:Dictionary={}
 for item:Dictionary in added:
  if item.kind!="fence":continue
  for fragment:Dictionary in Edges.visible_fence_modules(item.rect,world._obstacles,true):
   modules+=1;batches[str(item.id)+str(fragment.batch)]=true
 if modules>125 or batches.size()>45:return rejected(key,"actual opaque-clipped fence inventory exceeds budget")
 return {"status":"accepted","profile_id":"parcel:"+key,"reason":"","validation_only":false,"geometry_id":state.geometry_id,"obstacles":added,"removed_parcels":removed,"static_points":static_points,"props":props,"approaches":approaches,"drops":drops,"room_state":room_state.duplicate(true),"omitted_optional_beds":geometry.omitted_optional_beds,"expected_fence_modules":modules,"expected_fence_batches":batches.size()}
