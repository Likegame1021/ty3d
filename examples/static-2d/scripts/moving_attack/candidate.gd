extends "res://scripts/baked_config/candidate.gd"
const MovingHero=preload("res://scripts/moving_attack/hero.gd")
func add_actor(kind_value:String,p:Vector3,node_name:String):
 if kind_value!="hero":return super.add_actor(kind_value,p,node_name)
 var actor=MovingHero.new()
 actor.display_profile=display_profile
 actor.kind=kind_value;actor.name=node_name;actor.position=p
 add_child(actor);actor.strike.connect(on_strike)
 return actor
func _ready():
 super._ready()
 var layer:=CanvasLayer.new()
 var label:=Label.new()
 label.text="GAMEPLAY EXPERIMENT · Attack/recovery movement 3.1 · Swing facing locked"
 label.position=Vector2(26,150)
 label.add_theme_font_size_override("font_size",16)
 layer.add_child(label);add_child(layer)
