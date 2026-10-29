extends "res://scripts/corn_route_bend/candidate.gd"
const MultiHero=preload("res://scripts/event_clip_display_v1/hero.gd")
const MultiEnemy=preload("res://scripts/multi_clip_display_v1/enemy.gd")
@export_file("*.json") var hero_multi_profile:=""
@export_file("*.json") var monster_multi_profile:=""
func add_actor(kind_value:String,p:Vector3,node_name:String):
 if kind_value!="hero":return super.add_actor(kind_value,p,node_name)
 var actor=MultiHero.new()
 actor.display_profile="res://profiles/clothing_v7_run.json"
 actor.multi_display_profile=hero_multi_profile
 actor.kind=kind_value;actor.name=node_name;actor.position=p
 add_child(actor);actor.strike.connect(on_strike)
 return actor
func try_spawn(link_id:int,where:Vector3)->bool:
 if link_id<0 or link_id>=layout.links.size():return false
 if not layout.corridor_contains(link_id,where) or enemies.size()+defeated>=8:return false
 var enemy=MultiEnemy.new()
 enemy.multi_display_profile=monster_multi_profile
 enemy.kind="monster";enemy.name="BendMonster"+str(enemies.size())
 enemy.position=where;enemy.corridor_id=link_id;enemy.route_layout=layout
 enemy.speed=1.25;enemy.target=hero
 add_child(enemy)
 enemy.add_to_group("corn_route_enemy")
 enemy.strike.connect(on_strike)
 enemies.append(enemy)
 return true
func _ready():
 super._ready()
 var layer:=CanvasLayer.new()
 var label:=Label.new()
 var accepted:bool=hero.multi_visual.ready and not enemies.is_empty() and enemies[0].multi_visual.ready
 label.text=("HERO HURT EVENT · TECHNICAL DISPLAY" if accepted else "MULTI-CLIP RESOURCES UNAVAILABLE")+"\nHero hurt: actual 8 poses; hero attack/recovery + monster attack/hurt: static idle00"
 label.position=Vector2(26,150)
 label.add_theme_font_size_override("font_size",16)
 layer.add_child(label);add_child(layer)
