extends "res://scripts/dual_hurt_display_v1/enemy.gd"
## Display-only authority contract from existing corridor enemy: strike .27/end .64.
const ATTACK_DISPLAY_DURATION:=.64
const OUTGOING_STRIKE_TIME:=.27
func _init():
 multi_visual=preload("res://scripts/strike_display_v1/visual.gd").new()
func refresh_visual():
 if not multi_visual.ready:
  if visual:visual.texture=null
  last_display={"valid":false,"error":multi_visual.error_text}
  return
 var camera=get_viewport().get_camera_3d()
 var camera_basis:Basis=camera.global_basis if camera!=null else Basis.IDENTITY
 var angle:float=direction*PI/4
 var facing:=Vector3(sin(angle),0,cos(angle))
 last_display=multi_visual.sample_strike_state(state,phase,Vector2(velocity.x,velocity.z).length_squared()>.0025,facing,camera_basis,display_row,state_time,ATTACK_DISPLAY_DURATION if state=="attack" else HURT_DISPLAY_DURATION,OUTGOING_STRIKE_TIME,hit_sent)
 if not last_display.valid:visual.texture=null;return
 display_row=last_display.direction
 visual.texture=last_display.texture;visual.frame=0
 visual.pixel_size=last_display.pixel_size
 visual.offset=last_display.offset;visual.modulate=last_display.tint
