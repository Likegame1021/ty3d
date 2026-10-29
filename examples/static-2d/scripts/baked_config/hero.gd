extends "res://scripts/actor.gd"
## Display-only sibling, leaving the sealed integration hero unchanged.
@export_file("*.json") var display_profile:="res://profiles/legacy_run_v2.json"
var configured_visual=preload("res://scripts/baked_config/profile_visual.gd").new()
var last_display:Dictionary={}
var display_error:=""
func _ready():
 super._ready()
 display_error=configured_visual.load_profile(display_profile)
 if not display_error.is_empty():push_error(display_error);visual.texture=null;return
 visual.hframes=1;visual.vframes=1
 visual.pixel_size=configured_visual.pixel_size
 refresh_visual()
func refresh_visual():
 if not configured_visual.ready:
  if visual:visual.texture=null
  return
 last_display=configured_visual.sample(state,direction,phase,Vector2(velocity.x,velocity.z).length_squared()>.0025)
 visual.texture=last_display.texture
 visual.frame=0;visual.offset=last_display.offset;visual.modulate=last_display.tint
