extends "res://scripts/event_clip_display_v1/hero.gd"
## Both inherited presentation initialization paths point to the same new 2D
## adapter. All input, movement, damage, hit timing and state branches stay inherited.
const AtlasVisual=preload("res://scripts/new_pixel_hero_static_v1/atlas_visual.gd")
const PROFILE:="res://profiles/new_pixel_hero_static_v1.json"
func _init():
 configured_visual=AtlasVisual.new()
 multi_visual=configured_visual
 display_profile=PROFILE;multi_display_profile=PROFILE
func _ready():
 super._ready()
 textures.clear()
 multi_visual.apply_material(visual)
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
 last_display=multi_visual.sample_static(state,facing,camera_basis,display_row)
 if not last_display.valid:visual.texture=null;return
 display_row=last_display.direction
 visual.texture=last_display.texture;visual.frame=0
 visual.pixel_size=last_display.pixel_size
 visual.offset=last_display.offset;visual.modulate=last_display.tint
