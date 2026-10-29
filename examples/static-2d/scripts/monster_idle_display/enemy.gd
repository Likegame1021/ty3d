extends "res://scripts/corn_route_bend/corridor_enemy.gd"
## Visual-only child. All movement, collision, timing, strikes and damage are inherited.
@export_file("*.json") var monster_display_profile:=""
var idle_visual=preload("res://scripts/monster_idle_display/visual.gd").new()
var display_error:=""
var display_row:=0
var last_display:Dictionary={}
func _ready():
 super._ready()
 display_error=idle_visual.load_profile(monster_display_profile)
 if not display_error.is_empty():visual.texture=null;return
 visual.hframes=1;visual.vframes=1;visual.pixel_size=idle_visual.pixel_size
 refresh_visual()
func refresh_visual():
 if not idle_visual.ready:
  if visual:visual.texture=null
  return
 var camera=get_viewport().get_camera_3d()
 var camera_basis:Basis=camera.global_basis if camera!=null else Basis.IDENTITY
 var angle:float=direction*PI/4
 var facing:=Vector3(sin(angle),0,cos(angle))
 last_display=idle_visual.sample(state,phase,facing,camera_basis,display_row)
 display_row=last_display.direction
 visual.texture=last_display.texture;visual.frame=0
 visual.offset=last_display.offset;visual.modulate=last_display.tint
