extends SceneTree
const PLAYER := "res://scripts/player.gd"
const Reference = preload("res://tests/fixtures/reference-grip-v4-r2/reference.gd")
var failed := 0
var checks := 0
func _initialize():call_deferred("run_test")
func check(ok,label):
 checks+=1
 if not ok:failed+=1;printerr("FAIL: ",label)
func run_test():
 var reference = Reference.new()
 check(reference.files_match(), "independently approved R2 files remain hash-pinned")
 for action in ["move_left","move_right","move_up","move_down"]:
  if not InputMap.has_action(action):InputMap.add_action(action)
 var p=load(PLAYER).new();root.add_child(p);p.set_physics_process(false);p.melee_hold_pose.active=false;p.corn_hold_pose.active=false
 p.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var branch=p.branch_pivot.get_node("Branch");var body=p.body_visual.find_child("BoyBody",true,false)
 for action in ["pick_up","interact","push","vault"]:
  p.context_remaining=0;p.context_action="";p.attack.reset()
  check(p.play_context_action(action),action+" still starts with original API")
  p.melee_hold_pose.advance_state(.01);p.animation_player.advance(.25);p.melee_hold_pose._process_modification()
  check(not branch.visible,action+" stows the branch while hands are busy")
  check(body.mesh==p.melee_hold_pose.grip_open_mesh,action+" uses the open action hand")
  p.context_remaining=0;p.context_action="";p.play_animation("idle");p.animation_player.advance(0);p.melee_hold_pose._process_modification()
  check(not branch.visible,action+" does not restore at the start of body blend")
  p.melee_hold_pose.advance_state(.10);p.animation_player.advance(.10);p.melee_hold_pose._process_modification()
  check(not branch.visible,action+" stays stowed during the body blend")
  p.melee_hold_pose.advance_state(.10);p.animation_player.advance(.10);p.melee_hold_pose._process_modification()
  check(branch.visible and body.mesh==p.melee_hold_pose.grip_closed_mesh,action+" restores a closed grip after settling")
 p.play_context_action("hurt");p.animation_player.advance(.25)
 var sk=p.body_visual.find_children("*","Skeleton3D",true,false)[0]
 var source=[]
 for i in sk.get_bone_count():source.append(sk.get_bone_global_pose(i))
 p.melee_hold_pose._process_modification()
 check(branch.visible,"hurt retains the held branch")
 check(body.mesh==p.melee_hold_pose.grip_closed_mesh,"hurt keeps the closed grip")
 for bone in ["RightArm","RightForeArm","RightHand"]:
  var desired:Quaternion=reference.carry_model_rotations(sk, "idle")[bone]
  check(sk.get_bone_global_pose(sk.find_bone(bone)).basis.orthonormalized().get_rotation_quaternion().angle_to(desired)<.001,"hurt reuses approved chest-relative "+bone)
 var error=0.0
 for i in sk.get_bone_count():
  if sk.get_bone_name(i) in ["RightArm","RightForeArm","RightHand"]:continue
  var now=sk.get_bone_global_pose(i);error=maxf(error,now.origin.distance_to(source[i].origin))
  for c in 3:error=maxf(error,(now.basis[c]-source[i].basis[c]).length())
 check(error<.000001,"hurt preserves all21source body bones")
 p.context_remaining=0;p.context_action="";p.play_context_action("pick_up");p.melee_hold_pose.advance_state(.01);p.animation_player.advance(.1);p.melee_hold_pose._process_modification()
 p.reset_player();p.melee_hold_pose._process_modification()
 check(branch.visible,"reset clears the visual stow timer")
 # Sparse rendering must not start the restore countdown before context actually ends.
 p.context_remaining=.2;p.context_action="pick_up"
 for i in 12:
  p.context_remaining=maxf(0.0,.2-(i+1)/60.0);p.melee_hold_pose.advance_state(1.0/60.0)
 p.context_remaining=0;p.context_action="";p.play_animation("idle");p.melee_hold_pose._process_modification()
 check(not branch.visible,"low render rate still stows at actual context completion")
 p.melee_hold_pose.advance_state(.14);p.animation_player.advance(.14);p.melee_hold_pose._process_modification()
 check(not branch.visible,"low render rate keeps the safe body-settle interval")
 p.reset_player();p.play_animation("idle");p.animation_player.advance(0);p.melee_hold_pose._process_modification()
 p.request_attack();p.attack.elapsed=p.attack.duration-.02;p.attack.remaining=.02
 p.animation_player.seek(p.attack.elapsed,true);p.melee_hold_pose._process_modification();p.pending_context_action="hurt"
 p._physics_process(.03);p.animation_player.advance(.03);p.melee_hold_pose._process_modification()
 check(p.context_action=="hurt" and p.attack.remaining==0,"queued hurt preserves original priority and starts after attack")
 for bone in ["RightArm","RightForeArm","RightHand"]:
  var desired:Quaternion=reference.carry_model_rotations(sk, "idle")[bone]
  check(sk.get_bone_global_pose(sk.find_bone(bone)).basis.orthonormalized().get_rotation_quaternion().angle_to(desired)<.001,"queued hurt uses approved chest-relative "+bone+" without stale attack exit")
 p.free();print("CONTEXT_STOW: %d checks, %d failures"%[checks,failed]);quit(1 if failed else 0)
