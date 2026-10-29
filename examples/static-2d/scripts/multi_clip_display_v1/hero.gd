extends "res://scripts/moving_attack/hero.gd"
## Presentation-only candidate; all gameplay branches stay inherited.
@export_file("*.json") var multi_display_profile:=""
var multi_visual=preload("res://scripts/multi_clip_display_v1/visual.gd").new()
var display_row:=0
func _ready():
 super._ready()
 display_error=multi_visual.load_profile(multi_display_profile)
 visual.hframes=1;visual.vframes=1
 refresh_visual()
func refresh_visual():
 if not multi_visual.ready:
  if visual:visual.texture=null
  last_display={"valid":false,"error":multi_visual.error_text}
  return
 var camera=get_viewport().get_camera_3d()
 var camera_basis:Basis=camera.global_basis if camera!=null else Basis.IDENTITY
 var angle:float=direction*PI/4
 var facing:=Vector3(sin(angle),0,cos(angle))
 last_display=multi_visual.sample(state,phase,Vector2(velocity.x,velocity.z).length_squared()>.0025,facing,camera_basis,display_row)
 if not last_display.valid:visual.texture=null;return
 display_row=last_display.direction
 visual.texture=last_display.texture;visual.frame=0
 visual.pixel_size=last_display.pixel_size
 visual.offset=last_display.offset;visual.modulate=last_display.tint
