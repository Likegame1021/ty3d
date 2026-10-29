extends SceneTree
## Exact numerical before/after trace with the same 0/1 input policy.
## Writes no gameplay actor fields; only Input actions and evidence files.
func steer(motion:Vector2):
 for action in ["move_left","move_right","move_up","move_down"]:Input.action_release(action)
 if motion.x<0:Input.action_press("move_left")
 if motion.x>0:Input.action_press("move_right")
 if motion.y<0:Input.action_press("move_up")
 if motion.y>0:Input.action_press("move_down")
func path_to(layout,from:Vector3,to:Vector3)->Array:
 var start:Vector2i=layout.cell_at(from)
 var goal:Vector2i=layout.cell_at(to)
 var previous:={start:start}
 var queue:=[start]
 while not queue.is_empty():
  var cell:Vector2i=queue.pop_front()
  if cell==goal:break
  for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next:Vector2i=cell+step
   if layout.is_walkable(next) and not previous.has(next):previous[next]=cell;queue.append(next)
 if not previous.has(goal):return []
 var path:Array=[goal]
 while path[0]!=start:path.push_front(previous[path[0]])
 return path
func _initialize():
 var baseline_mode := "--baseline" in OS.get_cmdline_user_args()
 var scene_path := "res://scenes/corn_route_monster_strike_v1_candidate.tscn" if baseline_mode else "res://scenes/corn_route_new_pixel_hero_static_v1.tscn"
 var world=load(scene_path).instantiate()
 var trace_digest := ""
 root.add_child(world)
 await physics_frame
 var stage:=0
 var ticks:=0
 var attacks:=0
 var deaths:=0
 var next_attack:=0
 var previous:Vector3=world.hero.position
 var cache_key:=""
 var path:Array=[]
 while ticks<24000 and not world.completed:
  Input.action_release("attack")
  if world.hero.position.distance_to(world.hero.home)<.3 and previous.distance_to(world.hero.home)>1:deaths+=1;stage=0
  previous=world.hero.position
  var goal:=Vector3.ZERO
  var enemy=null
  if stage%2==0:
   var center:Vector2i=world.layout.rooms[stage/2].center
   goal=Vector3(center.x,0,center.y)
  else:
   for candidate in world.enemies:
    if candidate.corridor_id==(stage-1)/2 and (enemy==null or candidate.position.distance_to(world.hero.position)<enemy.position.distance_to(world.hero.position)):enemy=candidate
   if enemy==null:stage+=1;continue
   goal=enemy.position
  var delta:=Vector2(goal.x-world.hero.position.x,goal.z-world.hero.position.z)
  if enemy!=null and delta.length()<1.65 and world.has_clear_line(world.hero.position,enemy.position):
   steer(Vector2.ZERO)
   if ticks>=next_attack and world.hero.state not in ["attack","hurt","recover"]:
    Input.action_press("attack");attacks+=1;next_attack=ticks+74
  else:
   var key:=str(world.layout.cell_at(world.hero.position))+str(world.layout.cell_at(goal))
   if key!=cache_key:path=path_to(world.layout,world.hero.position,goal);cache_key=key
   var steering_goal:=goal
   if path.size()>1:steering_goal=Vector3(path[1].x,0,path[1].y)
   steer(Vector2(steering_goal.x-world.hero.position.x,steering_goal.z-world.hero.position.z))
   if enemy==null and delta.length()<.3 and stage<8:stage+=1
  await physics_frame
  var actors:Array=[]
  for enemy_state in world.enemies:
   actors.append({"position":enemy_state.position,"velocity":enemy_state.velocity,"state":enemy_state.state,"time":enemy_state.state_time,"phase":enemy_state.phase,"direction":enemy_state.direction,"hp":enemy_state.health,"invulnerable":enemy_state.invincible,"hit_sent":enemy_state.hit_sent})
  var inputs:Array=[]
  for action in ["move_left","move_right","move_up","move_down","attack"]:inputs.append(Input.is_action_pressed(action))
  var snapshot={"inputs":inputs,"hero_position":world.hero.position,"hero_velocity":world.hero.velocity,"state":world.hero.state,"time":world.hero.state_time,"phase":world.hero.phase,"direction":world.hero.direction,"hp":world.hero.health,"invulnerable":world.hero.invincible,"hit_sent":world.hero.hit_sent,"enemies":actors,"defeated":world.defeated,"complete":world.completed}
  trace_digest=(trace_digest+var_to_bytes(snapshot).hex_encode()).sha256_text()
  ticks+=1
  if ticks%1800==0:print("BEND DIGITAL progress ticks=",ticks," stage=",stage," kills=",world.defeated," hp=",world.hero.health," position=",world.hero.position)
 steer(Vector2.ZERO);Input.action_release("attack")
 if not world.completed:push_error("Bend digital policy failed within 400 simulated seconds");quit(1);return
 var result={"ticks":ticks,"trace_sha256":trace_digest,"kills":world.defeated,"attack_inputs":attacks,"deaths":deaths,"final_hp":world.hero.health}
 var directory := "res://evidence/new_pixel_hero_static_v1"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
 var baseline_path := directory+"/qa-binary-baseline.json"
 if baseline_mode:
  FileAccess.open(baseline_path,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
  print("RECORDED SEALED STRIKE GAMEPLAY: ",JSON.stringify(result))
 else:
  if not FileAccess.file_exists(baseline_path):push_error("Run --baseline first");quit(1);return
  var expected=JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
  FileAccess.open(directory+"/qa-binary-integrated.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
  if expected.trace_sha256!=trace_digest or int(expected.ticks)!=ticks:
   push_error("Gameplay/input numerical trace differs after display replacement");quit(1);return
  print("NEW STATIC 2D HERO DISPLAY GAMEPLAY IDENTICAL: ",JSON.stringify(result))
 quit()
