extends "res://scripts/actor.gd"
## Same prototype attack/hurt/recovery values; only locomotion follows corridor cells.
var corridor_id:=0
var route_layout:RefCounted
func _physics_process(delta):
 life+=delta;phase+=delta;state_time+=delta
 invincible=maxf(0,invincible-delta)
 if state=="attack":
  velocity.x=0;velocity.z=0
  if state_time>=.27 and not hit_sent:hit_sent=true;strike.emit(self)
  if state_time>=.64:change_state("recover")
 elif state=="hurt":
  velocity.x=move_toward(velocity.x,0,delta*9)
  velocity.z=move_toward(velocity.z,0,delta*9)
  if state_time>=.48:change_state("recover")
 elif state=="recover":
  velocity.x=0;velocity.z=0
  if state_time>=.22:change_state("idle")
 else:
  var motion:=Vector2.ZERO
  if is_instance_valid(target):
   var toward:Vector3=target.global_position-global_position
   var clear_line:bool=get_parent().has_clear_line(position,target.position)
   if toward.length()<6 and (toward.length()>1.15 or not clear_line):
    var path:Array=route_layout.corridor_path(corridor_id,position,target.position)
    var goal:Vector3=target.position
    if path.size()>1:goal=Vector3(path[1].x,position.y,path[1].y)
    var route_delta:=Vector2(goal.x-position.x,goal.z-position.z)
    if route_delta.length()>.06:motion=route_delta.normalized()
   if toward.length()<=1.15 and clear_line:
    direction=logic.direction_for(Vector2(toward.x,toward.z),direction)
    if fmod(life,2.2)<.07:attack()
  if motion.length()>.05:
   direction=logic.direction_for(motion,direction)
   if state!="attack":change_state("run")
  elif state!="attack":change_state("idle")
  velocity.x=motion.x*speed;velocity.z=motion.y*speed
 velocity.y-=18*delta
 move_and_slide()
 position=route_layout.clamp_to_corridor(corridor_id,position)
 refresh_visual()
