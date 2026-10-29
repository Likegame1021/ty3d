extends SceneTree
var checks:=0
var failures:=0
func check(value:bool,label:String):
 checks+=1
 if not value:failures+=1;push_error(label)
func _initialize():call_deferred("run")
func run():
 var scene:="res://scenes/corn_route_new_pixel_hero_static_v1.tscn"
 if not ResourceLoader.exists(scene):check(false,"New isolated 2D hero scene missing");quit(1);return
 var world=load(scene).instantiate();root.add_child(world)
 world.set_physics_process(false);world.hero.set_physics_process(false)
 for enemy in world.enemies:enemy.set_physics_process(false)
 var hero=world.hero
 check(hero.configured_visual==hero.multi_visual and hero.multi_visual.ready,"Both inherited display setup paths use only new 2D atlas")
 check(hero.visual.texture is AtlasTexture,"Hero is new 2D original atlas")
 check(hero.textures.is_empty(),"Unused legacy hero sheets released")
 check(world.enemies.size()==8,"Existing eight monsters preserved")
 for enemy in world.enemies:check(enemy.get_script().resource_path=="res://scripts/strike_display_v1/enemy.gd","Monster renderer/gameplay unchanged")
 for row in range(8):
  hero.direction=row;hero.refresh_visual()
  check(hero.last_display.valid and hero.visual.texture is AtlasTexture,"Actual actor applies atlas direction "+str(row))
  check(hero.visual.offset==hero.last_display.offset,"Actual actor applies per-direction feet anchor")
  check(hero.visual.frame==0 and not hero.visual.flip_h,"Actual actor stays static and unmirrored")
 var strikes:Array=[];hero.strike.connect(func(_actor):strikes.append(true))
 hero.automation=true;hero.manual_motion=Vector2.RIGHT
 hero.attack();hero._physics_process(.26)
 check(hero.state=="attack" and not hero.hit_sent and hero.velocity.x>0,"Moving attack before original hit time")
 check(hero.last_display.static_fallback and hero.last_display.fallback_for=="attack","Attack is honestly static display")
 hero._physics_process(.02)
 check(strikes.size()==1 and hero.hit_sent,"Original .27 second strike unchanged")
 hero._physics_process(.36)
 check(hero.state=="recover" and strikes.size()==1,"Original .64 second exit unchanged")
 var hp:int=hero.health;hero.damage(hero.position+Vector3.LEFT);hero.refresh_visual()
 check(hero.health==hp-1 and hero.state=="hurt","Original HP/damage unchanged")
 check(hero.last_display.static_fallback and hero.visual.modulate==Color(1.6,.65,.55),"Static hurt retains gameplay tint")
 world.restart_candidate()
 check(world.enemies.size()==8 and world.hero.visual.texture is AtlasTexture,"Reset retains new hero and original monsters")
 check(ProjectSettings.get_setting("application/run/main_scene")=="res://main.tscn","Default scene untouched")
 print("NEW 2D HERO CANDIDATE checks=",checks," failures=",failures)
 world.queue_free();quit(1 if failures else 0)
