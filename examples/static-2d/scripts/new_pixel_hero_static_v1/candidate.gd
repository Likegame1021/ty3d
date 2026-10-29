extends "res://scripts/strike_display_v1/candidate.gd"
## The sealed route's spawn, combat, HP and reset code is inherited unchanged.
const NewPixelHero=preload("res://scripts/new_pixel_hero_static_v1/hero.gd")
func add_actor(kind_value:String,p:Vector3,node_name:String):
 if kind_value!="hero":return super.add_actor(kind_value,p,node_name)
 var actor=NewPixelHero.new()
 actor.kind=kind_value;actor.name=node_name;actor.position=p
 add_child(actor);actor.strike.connect(on_strike)
 return actor
func _ready():
 super._ready()
 # Replace only the inherited display-candidate caption, never gameplay HUD.
 for layer in get_children():
  if not layer is CanvasLayer:continue
  for caption in layer.get_children():
   if caption is Label and caption.text.contains("hero attack/recovery: static idle00"):
    caption.name="NewPixelHeroStatus"
    caption.text=("NEW 2D HERO · EIGHT AUTHORED STATIC VIEWS" if hero.multi_visual.ready else "NEW 2D HERO RESOURCE UNAVAILABLE")+"\nRun / attack / hurt: static view fallback; existing 2D monster unchanged; no villager art added"
