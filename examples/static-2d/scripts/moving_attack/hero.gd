extends "res://scripts/baked_config/hero.gd"
## Isolated gameplay experiment: movement during attack/recovery, not a display-only refactor.
## Every other branch, damage API, collider and display sampler stays inherited.
func _physics_process(delta):
 if state not in ["attack","recover"]:
  super._physics_process(delta)
  return
 life+=delta
 phase+=delta
 state_time+=delta
 invincible=maxf(0.0,invincible-delta)
 var motion:Vector2=manual_motion if automation else Input.get_vector("move_left","move_right","move_up","move_down")
 velocity.x=motion.x*speed
 velocity.z=motion.y*speed
 # Direction deliberately remains the swing's existing facing during these states.
 if state=="attack":
  if state_time>=.27 and not hit_sent:
   hit_sent=true
   strike.emit(self)
  if state_time>=.64:change_state("recover")
 elif state_time>=.22:
  change_state("idle")
 velocity.y-=18.0*delta
 move_and_slide()
 if health<=0:
  health=3
  position=home
  change_state("hurt")
 refresh_visual()
