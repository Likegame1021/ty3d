extends SceneTree
const DT:=1.0/60.0
var checks:=0
var failures:=0
var rows:=[]
func _initialize():call_deferred("run_checks")
func check(ok,label):
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL: ",label)
func skeleton(p):return p.body_visual.find_children("*","Skeleton3D",true,false)[0]
func sample(p):
 var sk=skeleton(p)
 var values=[]
 for i in sk.get_bone_count():values.append(sk.get_bone_pose(i))
 return values
func max_difference(a,b):
 var value:=0.0
 for i in a.size():
  value=maxf(value,a[i].origin.distance_to(b[i].origin))
  for column in 3:value=maxf(value,(a[i].basis[column]-b[i].basis[column]).length())
 return value
func arm(p):
 if p.get("cancel_pose")!=null:p.cancel_pose._process_modification()
 p.melee_hold_pose._process_modification()
 skeleton(p).force_update_all_bone_transforms()
 if p.get("cancel_pose")!=null:p.cancel_pose.capture_visible_pose()
func step(p,dt):
 p.attack.tick(dt,false)
 p.animation_player.advance(dt)
 p.melee_hold_pose.advance_state(dt)
 if p.get("cancel_pose")!=null:p.cancel_pose.advance_state(dt)
 arm(p)
func make_player(script):
 var p=script.new();root.add_child(p);p.set_physics_process(false)
 p.corn_hold_pose.active=false;p.melee_hold_pose.active=false
 if p.get("cancel_pose")!=null:p.cancel_pose.active=false
 p.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 p.play_animation("idle");p.animation_player.advance(.5);p.melee_hold_pose.advance_state(.5);arm(p)
 return p
func run_checks():
 var candidate=load("res://scripts/player.gd")
 for action in ["hurt","pick_up","interact","push","vault"]:
  for partial in [false,true]:
   var p=make_player(candidate)
   p.request_attack();step(p,.6);p.cancel_actions()
   if partial:p.play_animation("idle");step(p,.04)
   check(p.play_context_action(action),"context accepted after cancellation")
   for frame in 15:step(p,DT)
   check(not p.cancel_pose.holding and not p.cancel_pose.bridge_active,"cancel to %s exits hold and bridge (partial %s)"%[action,partial])
   var expected=make_player(candidate);expected.play_context_action(action)
   for frame in 15:step(expected,DT)
   var a=[];var b=[]
   for bone in skeleton(p).get_bone_count():
    if skeleton(p).get_bone_name(bone) not in ["RightArm","RightForeArm","RightHand"]:a.append(sample(p)[bone]);b.append(sample(expected)[bone])
   check(max_difference(a,b)<.00001,"context body authoritative after cancelled bridge")
   p.free();expected.free()
 var p=make_player(candidate)
 p.request_attack();step(p,.6);p.cancel_actions();p.request_attack();step(p,.04)
 var bridge_time:float=p.cancel_pose.elapsed
 check(p.play_context_action("hurt") and p.pending_context_action=="hurt","hurt queues while restarted attack owns action")
 check(p.cancel_pose.elapsed==bridge_time and not p.cancel_pose.holding,"queued hurt does not restart bridge")
 check(not p.play_context_action("pick_up"),"busy pickup request rejected")
 check(p.cancel_pose.elapsed==bridge_time,"rejected pickup leaves bridge unchanged")
 check(not p.play_context_action("unknown_action"),"unknown context request rejected")
 check(p.cancel_pose.elapsed==bridge_time,"unknown context leaves bridge unchanged")
 p.free()
 print("CANCEL_CONTEXT ",checks," checks ",failures," failures")
 quit(1 if failures else 0)
