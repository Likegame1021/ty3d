extends "res://scripts/corn_route_bend/candidate.gd"
const BakedHero=preload("res://scripts/baked_integration/hero.gd")
func add_actor(kind_value:String,p:Vector3,node_name:String):
 if kind_value!="hero":return super.add_actor(kind_value,p,node_name)
 var actor=BakedHero.new()
 actor.kind=kind_value;actor.name=node_name;actor.position=p
 add_child(actor)
 actor.strike.connect(on_strike)
 return actor
func _ready():
 super._ready()
 var layer:=CanvasLayer.new()
 var label:=Label.new()
 label.text="LEGACY RIG BAKE · RUN ONLY\nIdle / attack / hurt: static run-frame fallback · Not approved hero art"
 label.position=Vector2(26,106)
 label.add_theme_font_size_override("font_size",16)
 label.add_theme_color_override("font_shadow_color",Color.BLACK)
 label.add_theme_constant_override("shadow_offset_x",1)
 label.add_theme_constant_override("shadow_offset_y",1)
 layer.add_child(label);add_child(layer)
