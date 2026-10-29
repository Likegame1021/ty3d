extends "res://scripts/multi_clip_display_v1/hero.gd"
## Read-only hurt display adapter. The inherited trial hurt duration is .48 s.
## This presentation contract is boundary-tested against actual state exit.
const HURT_DISPLAY_DURATION:=.48
func _init():
 multi_visual=preload("res://scripts/event_clip_display_v1/visual.gd").new()
func refresh_visual():
 if not multi_visual.ready:
  if visual:visual.texture=null
  last_display={"valid":false,"error":multi_visual.error_text}
  return
 var camera=get_viewport().get_camera_3d()
 var camera_basis:Basis=camera.global_basis if camera!=null else Basis.IDENTITY
 var angle:float=direction*PI/4
 var facing:=Vector3(sin(angle),0,cos(angle))
 last_display=multi_visual.sample_event_state(state,phase,Vector2(velocity.x,velocity.z).length_squared()>.0025,facing,camera_basis,display_row,state_time,HURT_DISPLAY_DURATION)
 if not last_display.valid:visual.texture=null;return
 display_row=last_display.direction
 visual.texture=last_display.texture;visual.frame=0
 visual.pixel_size=last_display.pixel_size
 visual.offset=last_display.offset;visual.modulate=last_display.tint
