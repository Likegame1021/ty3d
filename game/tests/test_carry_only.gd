extends SceneTree
## Normal-grip contract: source body/gait/contact, reviewed arm locals and fixed grasp.
const DT := 1.0 / 120.0
const ARM := ["RightArm", "RightForeArm", "RightHand"]
var failed := 0
var checks := 0
var p
var metrics := []
func _initialize() -> void: call_deferred("run_checks")
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failed += 1
  printerr("FAIL: ", message)
func vector(v: Vector3) -> Array: return [v.x,v.y,v.z]
func v(a) -> Vector3: return Vector3(a[0],a[1],a[2])
func matrix(a) -> Transform3D: return Transform3D(Basis(v(a[0]),v(a[1]),v(a[2])),v(a[3]))
func difference(a: Transform3D,b: Transform3D) -> float:
 return maxf(a.origin.distance_to(b.origin),maxf(a.basis.x.distance_to(b.basis.x),maxf(a.basis.y.distance_to(b.basis.y),a.basis.z.distance_to(b.basis.z))))
func bone_pose(sk: Skeleton3D, bone: int) -> Transform3D:
 return p.visual.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(bone)
func sample(sk: Skeleton3D,time: float,apply_carry: bool) -> Dictionary:
 sk.reset_bone_poses()
 p.animation_player.seek(time,true)
 p.animation_player.advance(0)
 if apply_carry:p.melee_hold_pose._process_modification()
 sk.force_update_all_bone_transforms()
 var bones := []
 var locals := []
 for bone in sk.get_bone_count():
  bones.append(bone_pose(sk,bone))
  locals.append(sk.get_bone_pose(bone))
 var hand: Transform3D = bones[sk.find_bone("RightHand")]
 return {"bones":bones,"locals":locals,"hand":hand.origin,"tip":hand*p.branch_pivot.transform*Vector3(0,.63,0),"butt":hand*p.branch_pivot.transform*Vector3(0,-.07,0),"socket":p.branch_pivot.transform}
func run_checks() -> void:
 var approved = load("res://tests/fixtures/reference-grip-v4-r2/reference.gd").new()
 check(approved.files_match(), "independently accepted R2 carry/attack/socket files remain hash-pinned")
 if failed:quit(1);return
 var grip: Dictionary = approved.grip
 var axis:=v(grip.shaft_axis_toward_tip)
 var normal:=v(grip.palm_outward_normal)
 var socket:=Transform3D(Basis(axis.cross(normal),axis,normal),v(grip.grip_center_right_hand_local))
 p=load("res://scripts/player.gd").new();root.add_child(p)
 p.set_physics_process(false);p.melee_hold_pose.active=false;p.corn_hold_pose.active=false
 p.position=Vector3.ZERO;p.visual.rotation=Vector3.ZERO
 p.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var sk:Skeleton3D=p.find_children("*","Skeleton3D",true,false)[0]
 var branch=p.branch_pivot.get_node("Branch")
 var body=p.body_visual.find_child("BoyBody",true,false)
 check(sk.get_bone_count()-ARM.size()==21,"all 21 protected source bones are covered")
 for action in ["idle","run"]:
  p.animation_player.stop();p.current_animation=action
  p.animation_player.play(p.animation_names[action],0.0);p.animation_player.advance(0)
  p.velocity=Vector3(0,0,3 if action=="run" else 0)
  p.melee_hold_pose.advance_state(1.0)
  var clip:Animation=p.animation_player.get_animation(p.animation_names[action])
  var hand_min:=Vector3.INF;var hand_max:=-Vector3.INF;var tip_min:=INF
  var hand_body_forward_min:=INF
  var body_difference:=0.0;var arm_difference:=0.0;var reference_error:=0.0;var socket_error:=0.0
  var forward_down:=true
  var directions := {"max_world_y": -INF, "min_world_z": INF, "min_hip_forward": INF, "min_chest_forward": INF, "samples": []}
  for frame in int(ceil(clip.length/DT)):
   var source:=sample(sk,frame*DT,false)
   var current:=sample(sk,frame*DT,true)
   hand_min=hand_min.min(current.hand);hand_max=hand_max.max(current.hand);tip_min=minf(tip_min,current.tip.y)
   # The source idle turns inside model space; use its live pelvis-facing frame.
   var hips:Transform3D=current.bones[sk.find_bone("Hips")]
   hand_body_forward_min=minf(hand_body_forward_min,(hips.affine_inverse()*current.hand).z)
   var shaft: Vector3 = current.tip - current.butt
   var hip_forward: Vector3 = hips.basis.z; hip_forward.y = 0.0; hip_forward = hip_forward.normalized()
   var chest: Transform3D = current.bones[sk.find_bone("Spine")]
   var chest_forward: Vector3 = chest.basis.z; chest_forward.y = 0.0; chest_forward = chest_forward.normalized()
   directions.max_world_y=maxf(directions.max_world_y,shaft.y);directions.min_world_z=minf(directions.min_world_z,shaft.z)
   directions.min_hip_forward=minf(directions.min_hip_forward,shaft.dot(hip_forward));directions.min_chest_forward=minf(directions.min_chest_forward,shaft.dot(chest_forward))
   if shaft.z<=0 or shaft.y>=0: directions.samples.append({"time":frame*DT,"world_y":shaft.y,"world_z":shaft.z,"hip_forward":shaft.dot(hip_forward),"chest_forward":shaft.dot(chest_forward)})
   forward_down=forward_down and shaft.dot(hip_forward)>0 and current.tip.y<current.butt.y
   socket_error=maxf(socket_error,difference(current.socket,socket))
   var approved_globals: Dictionary = approved.carry_model_rotations(sk, action)
   for bone in sk.get_bone_count():
    var error:=difference(source.bones[bone],current.bones[bone])
    if sk.get_bone_name(bone) in ARM:
     arm_difference=maxf(arm_difference,error)
     var target: Quaternion = approved_globals[sk.get_bone_name(bone)]
     var actual: Quaternion = sk.get_bone_global_pose(bone).basis.orthonormalized().get_rotation_quaternion()
     reference_error=maxf(reference_error,actual.angle_to(target))
    else:body_difference=maxf(body_difference,error)
  print("CARRY_DIRECTION_DIAGNOSTIC ",JSON.stringify({"action":action,"directions":directions}))
  check(body_difference<.000001,action+" preserves every source torso/leg/left-arm bone")
  check(arm_difference>.01,action+" changes only the held right arm")
  check(reference_error<.001,action+" matches approved chest-relative arm rotations over the full clip")
  check(socket_error<.000001,action+" retains the exact approved normal-grip socket")
  check(forward_down,action+" points the thumb-side long end forward in live body horizontal facing and downward in world space")
  check(hand_body_forward_min>0,action+" carries the hand in front of the live hip-facing plane")
  check(tip_min>0,action+" keeps the approved weapon endpoint above the ground")
  metrics.append({"clip":action,"body_difference":body_difference,"reference_error_radians":reference_error,"hand_range_m":vector(hand_max-hand_min),"hand_min_m":vector(hand_min),"hand_max_m":vector(hand_max),"tip_min_m":tip_min,"hand_body_forward_min_m":hand_body_forward_min})
 # The grasp is intentionally new; all source contact bones remain exact.
 p.request_attack()
 p.animation_player.play(p.animation_names["attack_branch"],0.0);p.animation_player.advance(0.0)
 for time in [.59,.60,.61,.62,.63]:
  p.attack.elapsed=time;p.attack.remaining=p.attack.duration-time
  var source:=sample(sk,time,false);var current:=sample(sk,time,true)
  var contact_error:=0.0
  var approved_arm: Dictionary = approved.attack_local_rotations(time)
  var arm_error := 0.0
  for bone in sk.get_bone_count():
   if sk.get_bone_name(bone) in ARM:
    arm_error=maxf(arm_error,current.locals[bone].basis.orthonormalized().get_rotation_quaternion().angle_to(approved_arm[sk.get_bone_name(bone)]))
    check(current.locals[bone].origin.distance_to(source.locals[bone].origin)<.000001 and current.locals[bone].basis.get_scale().distance_to(source.locals[bone].basis.get_scale())<.000001,"contact retains source arm origins/scales")
   else:
    contact_error=maxf(contact_error,difference(source.bones[bone],current.bones[bone]))
    contact_error=maxf(contact_error,difference(source.locals[bone],current.locals[bone]))
  check(contact_error<.00001,"all21 source contact local/world bones unchanged at %.2f"%time)
  check(arm_error<.001,"three contact rotations match approved retarget at %.2f"%time)
  check(difference(current.socket,socket)<.000001,"contact keeps the fixed approved grasp at %.2f"%time)
 p.cancel_actions();p.ranged_stance=true;p.melee_hold_pose._process_modification()
 check(p.branch_pivot.position.distance_to(Vector3(0,.045,0))<.000001 and p.branch_pivot.quaternion.angle_to(Quaternion.IDENTITY)<.000001,"ranged restores the original shared anchor")
 check(not branch.visible and body.mesh==p.melee_hold_pose.grip_open_mesh,"ranged hides branch and opens hand")
 p.ranged_stance=false
 for action in ["pick_up","interact","push","vault"]:
  p.reset_player()
  check(p.play_context_action(action),action+" retains its source action API")
  p.melee_hold_pose.advance_state(DT);p.animation_player.advance(.25);p.melee_hold_pose._process_modification()
  check(not branch.visible and body.mesh==p.melee_hold_pose.grip_open_mesh,action+" stows branch and opens action hand")
  p.cancel_actions();p.play_animation("idle");p.animation_player.advance(0);p.melee_hold_pose._process_modification()
  check(not branch.visible,action+" stays stowed at context exit")
  p.melee_hold_pose.advance_state(.10);p.animation_player.advance(.10);p.melee_hold_pose._process_modification()
  check(not branch.visible,action+" stays stowed during body settle")
  p.melee_hold_pose.advance_state(.10);p.animation_player.advance(.10);p.melee_hold_pose._process_modification()
  check(branch.visible and body.mesh==p.melee_hold_pose.grip_closed_mesh,action+" restores closed normal grip after body settle")
 var output:=FileAccess.open("user://carry-v4-r2-pose-metrics.json",FileAccess.WRITE)
 check(output!=null,"carry evidence destination is writable")
 if output:output.store_string(JSON.stringify(metrics,"  "))
 p.free();print("CARRY_ONLY: %d checks, %d failures"%[checks,failed]);quit(1 if failed else 0)
