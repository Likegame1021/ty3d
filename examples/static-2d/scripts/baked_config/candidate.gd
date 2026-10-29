extends "res://scripts/corn_route_bend/candidate.gd"
const ConfiguredHero=preload("res://scripts/baked_config/hero.gd")
@export_file("*.json") var display_profile:="res://profiles/legacy_run_v2.json"
func add_actor(kind_value:String,p:Vector3,node_name:String):
 if kind_value!="hero":return super.add_actor(kind_value,p,node_name)
 var actor=ConfiguredHero.new()
 actor.display_profile=display_profile
 actor.kind=kind_value;actor.name=node_name;actor.position=p
 add_child(actor);actor.strike.connect(on_strike)
 return actor
func _ready():
 super._ready()
 var layer:=CanvasLayer.new()
 var label:=Label.new()
 label.text=(hero.configured_visual.profile_label if hero.display_error.is_empty() else "DISPLAY REJECTED: "+hero.display_error)+"\nRUN ONLY · Idle / attack / hurt: static run00 fallback"
 label.position=Vector2(26,106)
 label.add_theme_font_size_override("font_size",16)
 label.add_theme_color_override("font_shadow_color",Color.BLACK)
 label.add_theme_constant_override("shadow_offset_x",1)
 label.add_theme_constant_override("shadow_offset_y",1)
 layer.add_child(label);add_child(layer)
