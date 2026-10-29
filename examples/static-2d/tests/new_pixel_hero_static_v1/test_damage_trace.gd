extends SceneTree
## Controlled damage-event regression plus fixed keyboard input sequence.
## Uses the real damage() API; does not assign HP/state/position/invulnerability.
## This is NOT the separate pure-input normal-AI clear test.
func _initialize():
 var baseline_mode:bool="--baseline" in OS.get_cmdline_user_args()
 var scene_path:="res://scenes/corn_route_monster_strike_v1_candidate.tscn" if baseline_mode else "res://scenes/corn_route_new_pixel_hero_static_v1.tscn"
 var world=load(scene_path).instantiate()
 root.add_child(world)
 await physics_frame
 var digest:=""
 var states:={}
 var respawns:=0
 var previous:Vector3=world.hero.position
 Input.action_press("move_right")
 for tick in range(800):
  Input.action_release("attack")
  if tick==20:Input.action_press("attack")
  if tick in [120,121,220,320]:world.hero.damage(world.hero.position+Vector3.LEFT)
  await physics_frame
  states[world.hero.state]=true
  if previous.distance_to(world.hero.home)>1 and world.hero.position.distance_to(world.hero.home)<.3:respawns+=1
  previous=world.hero.position
  var enemies:Array=[]
  for enemy in world.enemies:enemies.append([enemy.position,enemy.velocity,enemy.state,enemy.state_time,enemy.health,enemy.invincible,enemy.hit_sent,enemy.direction])
  var sample=[tick,world.hero.position,world.hero.velocity,world.hero.state,world.hero.state_time,world.hero.phase,world.hero.health,world.hero.invincible,world.hero.hit_sent,world.hero.direction,enemies]
  digest=(digest+var_to_bytes(sample).hex_encode()).sha256_text()
 Input.action_release("move_right");Input.action_release("attack")
 if not states.has("attack") or not states.has("hurt") or respawns<1:
  push_error("Controlled damage trace coverage missing: states="+str(states.keys())+" respawns="+str(respawns)+" hp="+str(world.hero.health)+" pos="+str(world.hero.position));quit(1);return
 var result={"ticks":800,"trace_sha256":digest,"respawns":respawns,"states":states.keys(),"final_hp":world.hero.health}
 var dir:="res://evidence/new_pixel_hero_static_v1"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
 var path:=dir+"/damage-baseline.json"
 if baseline_mode:
  FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
  print("RECORDED ORIGINAL CONTROLLED DAMAGE TRACE: ",JSON.stringify(result))
 else:
  var expected=JSON.parse_string(FileAccess.get_file_as_string(path))
  FileAccess.open(dir+"/damage-integrated.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
  if expected.trace_sha256!=digest:push_error("Damage/attack/death numerical trace changed");quit(1);return
  print("NEW STATIC 2D HERO CONTROLLED DAMAGE TRACE IDENTICAL: ",JSON.stringify(result))
 quit()
