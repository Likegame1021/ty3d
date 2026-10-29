extends SceneTree
const DT:=1.0/60.0
const Reference = preload("res://tests/fixtures/reference-grip-v4-r2/reference.gd")
var reference = Reference.new()
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
 check(reference.files_match(), "approved R2 attack reference remains hash-pinned")
 var candidate=load(OS.get_environment("MOTION_CANDIDATE") if OS.has_environment("MOTION_CANDIDATE") else "res://scripts/player.gd")
 for phase in [.05,.2,.6,1.0,1.4]:
  for rank in [1.0,.92,.8464]:
   for destination in ["idle","run","restart"]:
    var p=make_player(candidate)
    p.set_attack_recovery_multiplier(rank);p.request_attack()
    var elapsed:=0.0
    while elapsed<phase:
     var dt=minf(DT,phase-elapsed);step(p,dt);elapsed+=dt
    var before=sample(p);var socket=p.branch_pivot.transform
    p.cancel_actions()
    check(p.attack.remaining==0.0 and not p.attack.claim_hit(101,false),"cancel removes hit authority")
    if destination=="restart":p.request_attack()
    else:p.play_animation(destination)
    p.animation_player.advance(0.0);arm(p)
    var jump=max_difference(before,sample(p))
    check(jump<0.00001,"actual modified skeleton continuous phase %.2f rank %.4f to %s: %.8f"%[phase,rank,destination,jump])
    check(p.branch_pivot.transform.is_equal_approx(socket),"normal socket stays fixed")
    var contact_error:=0.0
    var max_scale_change:=0.0
    for frame in 45:
     step(p,DT)
     if destination=="restart" and p.attack.elapsed>=.59 and p.attack.elapsed<=.63:
      var source=p.animation_player.get_animation(p._authored_attack_animation)
      var sk=skeleton(p)
      for track in source.get_track_count():
       var path=source.track_get_path(track)
       var bone=sk.find_bone(String(path.get_subname(path.get_subname_count()-1)))
       if bone<0:continue
       if source.track_get_type(track)==Animation.TYPE_ROTATION_3D:
        var actual: Quaternion=sk.get_bone_pose_rotation(bone)
        var expected: Quaternion=reference.attack_local_rotations(p.get_attack_pose_time())[sk.get_bone_name(bone)] if sk.get_bone_name(bone) in ["RightArm", "RightForeArm", "RightHand"] else source.rotation_track_interpolate(track,p.get_attack_pose_time())
        contact_error=maxf(contact_error,1.0-absf(actual.dot(expected)))
     for bone in skeleton(p).get_bone_count():
      var scale:Vector3=skeleton(p).get_bone_pose_scale(bone)
      check(scale.is_finite() and scale.min_axis_index()>=0 and scale.x>0 and scale.y>0 and scale.z>0,"positive finite bone scales")
    if destination=="restart":check(contact_error<0.00001,"cancel/restart preserves source21 and approved three-bone contact at all ranks")
    if destination=="run":
     var expected=make_player(candidate)
     expected.play_animation("run");expected.animation_player.advance(.75);expected.animation_player.seek(p.animation_player.current_animation_position,true)
     expected.melee_hold_pose.advance_state(.75);arm(expected)
     var protected_actual=[];var protected_expected=[]
     for bone in skeleton(p).get_bone_count():
      if skeleton(p).get_bone_name(bone) not in ["RightArm","RightForeArm","RightHand"]:
       protected_actual.append(sample(p)[bone]);protected_expected.append(sample(expected)[bone])
     check(max_difference(protected_actual,protected_expected)<.00001,"all21 protected settled RUN bones exact after cancel blend")
     check(max_difference(sample(p),sample(expected))<.0001,"rightarm settled within100microunit numeric tolerance")
     expected.free()
    rows.append({"phase":phase,"rank":rank,"destination":destination,"zero_pose_component_delta":jump,"contact_rotation_dot_error":contact_error})
    p.free()
 # Repeated cancellation must not accumulate hold state or scale drift.
 var p=make_player(candidate)
 for cycle in 8:
  p.request_attack();step(p,.05 if cycle%2==0 else .6)
  var before=sample(p)
  p.cancel_actions();p.cancel_actions();p.cancel_actions()
  p.animation_player.advance(0);arm(p)
  check(max_difference(before,sample(p))<.00001,"repeatedcancel preserves current pose")
  p.play_animation("idle");step(p,.04)
 p.reset_player();p.play_animation("idle");p.animation_player.advance(.5);p.melee_hold_pose.advance_state(.5);arm(p)
 var fresh=make_player(candidate)
 check(max_difference(sample(p),sample(fresh))<.00001,"reset discards cancelled bridge")
 p.free();fresh.free()
 var report={"checks":checks,"failures":failures,"rows":rows}
 print("CANCEL_MATRIX ",JSON.stringify(report))
 if OS.has_environment("MOTION_REPORT"):FileAccess.open(OS.get_environment("MOTION_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 quit(1 if failures else 0)
