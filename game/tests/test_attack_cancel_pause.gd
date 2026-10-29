extends SceneTree
var failures:=0
var checks:=0
func _initialize():call_deferred("run_test")
func check(ok,label):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func difference(a,b):
 var error:=0.0
 if a.size()!=b.size():return INF
 for i in a.size():
  error=maxf(error,a[i].origin.distance_to(b[i].origin))
  for c in 3:error=maxf(error,(a[i].basis[c]-b[i].basis[c]).length())
 return error
func frames(n):
 for frame in n:await physics_frame
 await process_frame
func run_test():
 Engine.max_fps=int(OS.get_environment("MOTION_FPS")) if OS.has_environment("MOTION_FPS") else 60
 for action in ["move_left","move_right","move_up","move_down","run"]:
  if not InputMap.has_action(action):InputMap.add_action(action)
 var stage:=Node3D.new();root.add_child(stage)
 var floor_body:=StaticBody3D.new();var collider:=CollisionShape3D.new();collider.shape=BoxShape3D.new();collider.shape.size=Vector3(100,.5,100);collider.position.y=-.25;floor_body.add_child(collider);stage.add_child(floor_body)
 var p=load("res://scripts/player.gd").new();stage.add_child(p);p.position=Vector3.ZERO
 await frames(20)
 check(p.cancel_pose.last_visible.size()==24,"automatic final modifier signal caches24 bones")
 for phase_frames in [6,36,72]:
  p.request_attack();await frames(phase_frames)
  var before=p.cancel_pose.last_visible.duplicate()
  var physical=p.position
  p.cancel_actions();paused=true
  var elapsed:float=p.cancel_pose.elapsed
  await create_timer(.12,true).timeout
  check(difference(before,p.cancel_pose.last_visible)<.000001,"paused rendered bone snapshot freezes")
  check(p.cancel_pose.elapsed==elapsed and p.attack.remaining==0.0,"paused transition and attack clocks freeze")
  check(p.position.is_equal_approx(physical),"pause freezes physical root")
  paused=false
  await frames(2)
  # Capture another interruption while support correction is active.
  var bridge_before=p.cancel_pose.last_visible.duplicate()
  p.request_attack()
  p.animation_player.advance(0)
  p.cancel_pose._process_modification();p.melee_hold_pose._process_modification();p.cancel_pose.capture_visible_pose()
  check(difference(bridge_before,p.cancel_pose.last_visible)<.00001,"restart inside corrected bridge preserves actual displayed pose")
  await frames(6)
  p.cancel_actions()
  Input.action_press("move_up");await frames(2)
  Input.action_release("move_up");await frames(2)
  Input.action_press("move_left");await frames(2)
  Input.action_release("move_left");await frames(30)
  check(not p.cancel_pose.bridge_active,"nested RUN/idle changes fully clear bridge")
  check(p.cancel_pose.last_lift==0.0,"no residual support lift after bridge")
 p.reset_player();await frames(3)
 check(not p.cancel_pose.bridge_active,"respawn clears correction and snapshot")
 print("AUTO_CANCEL_PAUSE ",JSON.stringify({"fps":Engine.max_fps,"checks":checks,"failures":failures,"maximum_support_lift_m":p.cancel_pose.maximum_lift}))
 p.free();stage.free();quit(1 if failures else 0)
