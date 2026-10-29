extends "res://scripts/world.gd"
## Isolated level candidate. Existing default scene and actor logic untouched.
const Layout=preload("res://scripts/corn_route/layout.gd")
const CorridorEnemy=preload("res://scripts/corn_route/corridor_enemy.gd")
var layout=Layout.new()
var enemies: Array=[]
var defeated:=0
var completed:=false
var route_camera: Camera3D
func _ready():
 random.seed=8821
 layout.build()
 setup_input()
 build_environment()
 route_camera=get_node("Camera3D")
 route_camera.size=14
 build_route_geometry()
 add_copied_environment_props()
 hero=add_actor("hero",Vector3(0,.05,0),"Hero")
 for link in layout.links:
  for cell in link.spawns: try_spawn(link.id,Vector3(cell.x,.05,cell.y))
 fx=load("res://scripts/combat_fx.gd").new()
 add_child(fx)
 build_hud()
func build_route_geometry():
 box(Vector3(16,-.2,8),Vector3(51,.4,35),Color("7b8150"),true)
 for cell in layout.walkable:
  var floor_color:=Color("b8a170") if layout.kind_at(cell)=="room" else Color("c4a56d")
  box(Vector3(cell.x,.01,cell.y),Vector3(.99,.03,.99),floor_color)
 for cell in layout.blockers:
  box(Vector3(cell.x,.65,cell.y),Vector3(1,1.3,1),Color("6a7740"),true)
  corn(Vector3(cell.x,0,cell.y),1.8+random.randf()*.3)
 for cell in layout.blocked_roads:
  box(Vector3(cell.x,.022,cell.y),Vector3(.9,.035,.9),Color("988666"))
 for room in layout.rooms:
  var c: Vector2i=room.center
  var sign_post:=Label3D.new()
  sign_post.text=str(room.id+1)+" · "+room.name
  sign_post.font_size=34
  sign_post.pixel_size=.014
  sign_post.billboard=BaseMaterial3D.BILLBOARD_ENABLED
  sign_post.position=Vector3(c.x,2.2,c.y-3.3)
  add_child(sign_post)
  # Small corn stacks and baskets distinguish the safe plots without blocking route.
  for side in [-1,1]:
   cylinder(Vector3(c.x+side*3,.4,c.y+3),.3,.8,Color("9b8150"),.2)
func try_spawn(link_id: int,where: Vector3) -> bool:
 if link_id<0 or link_id>=layout.links.size(): return false
 if not layout.corridor_contains(link_id,where): return false
 if not layout.can_spawn(layout.cell_at(where)): return false
 # Fixed slots are single-use in this candidate; never replenish cleared waves.
 if enemies.size()+defeated>=8: return false
 var enemy=CorridorEnemy.new()
 enemy.kind="monster"
 enemy.name="CorridorMonster"+str(enemies.size())
 enemy.position=where
 enemy.corridor_id=link_id
 enemy.route_layout=layout
 enemy.speed=1.25
 enemy.target=hero
 add_child(enemy)
 enemy.strike.connect(on_strike)
 enemy.add_to_group("corn_route_enemy")
 enemies.append(enemy)
 return true
func on_strike(actor):
 var angle: float=actor.direction*PI/4
 var facing:=Vector3(sin(angle),0,cos(angle))
 if fx: fx.spawn_slash(actor.global_position,facing)
 if actor==hero:
  for enemy in enemies.duplicate():
   var difference: Vector3=enemy.position-hero.position
   if difference.length()<1.95 and facing.dot(difference.normalized())>0:
    apply_hit(enemy,hero.position)
 else:
  if not layout.corridor_contains(actor.corridor_id,hero.position): return
  var difference: Vector3=hero.position-actor.position
  if difference.length()<1.95 and facing.dot(difference.normalized())>0:
   hero.damage(actor.position)
func apply_hit(enemy,from: Vector3):
 if not enemies.has(enemy): return
 enemy.damage(from)
 if fx: fx.spawn_hit(enemy.position+Vector3.UP*.7)
 if enemy.health<=0:
  enemies.erase(enemy)
  defeated+=1
  enemy.set_physics_process(false)
  enemy.queue_free()
 update_completion()
func update_completion():
 var center: Vector2i=layout.rooms[4].center
 var at_finish:=absf(hero.position.x-center.x)<=4.4 and absf(hero.position.z-center.y)<=4.4
 if defeated==8 and enemies.is_empty() and at_finish: completed=true
func _process(_delta):
 if not is_instance_valid(hero): return
 if Input.is_action_just_pressed("light_toggle"): toggle_light()
 if Input.is_action_just_pressed("reset"): restart_candidate(); return
 route_camera.position=hero.position+Vector3(0,14,17)
 route_camera.look_at(hero.position+Vector3(0,.2,0))
 update_completion()
 if hud:
  hud.text="CORN ROUTE · FIVE MAP CANDIDATE\n"+("CLEAR · all corridors cleared" if completed else "Corridor enemies "+str(defeated)+"/8 · reach map 5")

func restart_candidate():
 for enemy in enemies:
  enemy.set_physics_process(false)
  remove_child(enemy)
  enemy.queue_free()
 enemies.clear()
 defeated=0
 completed=false
 hero.position=hero.home
 hero.velocity=Vector3.ZERO
 hero.health=3
 hero.invincible=0
 hero.state="idle"
 hero.state_time=0
 hero.phase=0
 hero.life=0
 hero.hit_sent=false
 hero.manual_motion=Vector2.ZERO
 for link in layout.links:
  for cell in link.spawns: try_spawn(link.id,Vector3(cell.x,.05,cell.y))

func add_copied_environment_props():
 var props=[
  ["res://assets/corn_route/farm-well.glb","RouteWell",Vector3(-6.2,0,-2.5)],
  ["res://assets/corn_route/grain-sack-stack.glb","RouteHarvestSacks",Vector3(10,0,18.5)]
 ]
 for entry in props:
  var scene: PackedScene=load(entry[0])
  var prop: Node3D=scene.instantiate()
  prop.name=entry[1]
  prop.position=entry[2]
  add_child(prop)
