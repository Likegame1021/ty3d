extends "res://scripts/actor.gd"
## Only visual setup/refresh overridden. All physics, input, damage and timing inherited.
var baked_visual=preload("res://scripts/baked_integration/run_visual.gd").new()
var baked_ready:=false
var last_display:Dictionary={}
func _ready():
 super._ready()
 var error:String=baked_visual.load_assets("res://assets/baked_run_probe")
 if not error.is_empty():push_error(error);return
 visual.hframes=1;visual.vframes=1
 visual.pixel_size=baked_visual.pixel_size
 baked_ready=true
 refresh_visual()
func refresh_visual():
 if not baked_ready:return
 var moving:=Vector2(velocity.x,velocity.z).length_squared()>.0025
 last_display=baked_visual.sample(state,direction,phase,moving)
 visual.texture=last_display.texture
 visual.frame=0
 visual.offset=last_display.offset
 visual.modulate=last_display.tint
