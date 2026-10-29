extends "res://scripts/corn_route/candidate.gd"
const BendLayout=preload("res://scripts/corn_route_bend/layout.gd")
const BendEnemy=preload("res://scripts/corn_route_bend/corridor_enemy.gd")
func _init():
 layout=BendLayout.new()
func build_route_geometry():
 box(Vector3(16,-.2,12),Vector3(51,.4,43),Color("7b8150"),true)
 for cell in layout.walkable:
  box(Vector3(cell.x,-.014,cell.y),Vector3(.99,.03,.99),Color("b8a170") if layout.kind_at(cell)=="room" else Color("c4a56d"))
 for cell in layout.blockers:
  var bank=box(Vector3(cell.x,.65,cell.y),Vector3(1,1.3,1),Color("6a7740"),true)
  for child in bank.get_children():
   if child is StaticBody3D:child.collision_layer=3
  corn(Vector3(cell.x,0,cell.y),1.8+random.randf()*.3)
 for cell in layout.blocked_roads:box(Vector3(cell.x,.02,cell.y),Vector3(.9,.04,.9),Color("988666"))
 for room in layout.rooms:
  var label:=Label3D.new()
  label.text=str(room.id+1)+" · "+room.name
  label.font_size=34;label.pixel_size=.014
  label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
  label.position=Vector3(room.center.x,2.2,room.center.y-3.3)
  add_child(label)
func try_spawn(link_id:int,where:Vector3)->bool:
 if link_id<0 or link_id>=layout.links.size():return false
 if not layout.corridor_contains(link_id,where) or enemies.size()+defeated>=8:return false
 var enemy=BendEnemy.new()
 enemy.kind="monster";enemy.name="BendMonster"+str(enemies.size())
 enemy.position=where;enemy.corridor_id=link_id;enemy.route_layout=layout
 enemy.speed=1.25;enemy.target=hero
 add_child(enemy)
 enemy.add_to_group("corn_route_enemy")
 enemy.strike.connect(on_strike)
 enemies.append(enemy)
 return true
func has_clear_line(from:Vector3,to:Vector3)->bool:
 var query:=PhysicsRayQueryParameters3D.create(from+Vector3.UP*.65,to+Vector3.UP*.65,2)
 return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func on_strike(actor):
 var angle:float=actor.direction*PI/4
 var facing:=Vector3(sin(angle),0,cos(angle))
 if fx:fx.spawn_slash(actor.position,facing)
 if actor==hero:
  for enemy in enemies.duplicate():
   var difference:Vector3=enemy.position-hero.position
   if difference.length()<1.95 and facing.dot(difference.normalized())>0 and has_clear_line(hero.position,enemy.position):apply_hit(enemy,hero.position)
 else:
  if not layout.corridor_contains(actor.corridor_id,hero.position):return
  var difference:Vector3=hero.position-actor.position
  if difference.length()<1.95 and facing.dot(difference.normalized())>0 and has_clear_line(actor.position,hero.position):hero.damage(actor.position)

func add_copied_environment_props():
 super.add_copied_environment_props()
 var modules=[
  ["road_straight","RoadWest",Vector3(4,-.042,0),PI/2],
  ["road_turn","RoadFirstTurn",Vector3(6,-.042,2),0.0],
  ["road_straight","RoadVertical",Vector3(8,-.042,4),0.0],
  ["road_turn","RoadSecondTurn",Vector3(10,-.042,6),PI],
  ["road_straight","RoadEast",Vector3(12,-.042,8),PI/2],
  ["road_straight","RoadGateWest",Vector3(22,-.042,8),PI/2],
  ["road_straight","RoadGateEast",Vector3(26,-.042,8),PI/2],
  ["gatehouse","RouteGatehouse",Vector3(24,0,8),PI/2]
 ]
 for entry in modules:
  var resource:PackedScene=load("res://assets/corn_route_bend/"+entry[0]+".glb")
  var node:Node3D=resource.instantiate()
  node.name=entry[1];node.position=entry[2];node.rotate_y(entry[3])
  add_child(node)
