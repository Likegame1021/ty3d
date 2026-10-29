extends SceneTree
const DT := 1.0/60.0
const PLAYER := "res://scripts/player.gd"
var failures := 0
var checks := 0
func _initialize():call_deferred("run_test")
func check(value, label):
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func run_test():
 for action in ["move_left","move_right","move_up","move_down"]:
  if not InputMap.has_action(action):InputMap.add_action(action)
 var floor=StaticBody3D.new();floor.collision_layer=1;floor.collision_mask=0
 var shape=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(100,.5,100);shape.position.y=-.25;floor.add_child(shape);root.add_child(floor)
 var p=load(PLAYER).new();root.add_child(p);p.set_physics_process(false);p.melee_hold_pose.active=false;p.corn_hold_pose.active=false
 p.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 p.world_max=Vector2(.2,.2);p.world_min=Vector2(-.2,-.2);p.position=Vector3(.2,0,.2)
 await physics_frame;await physics_frame
 Input.action_press("move_down")
 for frame in 45:
  p._physics_process(DT);p.animation_player.advance(DT);p.melee_hold_pose._process_modification();await physics_frame
 check(Vector2(p.velocity.x,p.velocity.z).length()>2.99,"bounded outward input retains nonzero requested velocity")
 check(p.current_animation=="idle","actual-displacement body stops at the world bound")
 check(p.melee_hold_pose._run_target==0.0,"blocked body uses lowered idle carry")
 p.world_max=Vector2(100,100);p.world_min=Vector2(-100,-100)
 for frame in 20:
  p._physics_process(DT);p.animation_player.advance(DT);p.melee_hold_pose._process_modification();await physics_frame
 check(p.current_animation=="run","unblocked actual movement returns to original RUN")
 check(p.melee_hold_pose._run_target==1.0,"unblocked carry follows RUN body")
 Input.action_release("move_down");p.free();floor.free()
 print("WALL_CARRY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
