extends "res://scripts/moving_attack/candidate.gd"
const IdleDisplayEnemy=preload("res://scripts/monster_idle_display/enemy.gd")
@export_file("*.json") var monster_display_profile:=""
func try_spawn(link_id:int,where:Vector3)->bool:
 if link_id<0 or link_id>=layout.links.size():return false
 if not layout.corridor_contains(link_id,where) or enemies.size()+defeated>=8:return false
 var enemy=IdleDisplayEnemy.new()
 enemy.monster_display_profile=monster_display_profile
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
 var accepted:bool=not enemies.is_empty() and enemies[0].idle_visual.ready
 label.text=(enemies[0].idle_visual.label if accepted else "MONSTER DISPLAY UNAVAILABLE")+"\nIDLE ONLY · run / attack / hurt / recovery: static idle00 fallback"
 label.position=Vector2(26,174)
 label.add_theme_font_size_override("font_size",16)
 layer.add_child(label);add_child(layer)
