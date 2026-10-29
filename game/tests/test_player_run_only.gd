extends SceneTree
## Regression for reported skating and downward weapon carry, on actual imported bones.
var failed := 0
var checks := 0
var p
const DT := 1.0 / 120.0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failed += 1
  printerr("FAIL: ", message)
func _initialize() -> void:
 call_deferred("run_checks")
func pose_point(sk: Skeleton3D, bone: String) -> Transform3D:
 return p.visual.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(sk.find_bone(bone))
func carry_samples(action: String) -> Dictionary:
 p.animation_player.play(p.animation_names[action],0)
 p.current_animation = action
 p.animation_player.speed_scale = 1.0
 var sk: Skeleton3D = p.find_children("*","Skeleton3D",true,false)[0]
 var rows := []
 var clip: Animation = p.animation_player.get_animation(p.animation_names[action])
 p.animation_player.advance(0.0)
 p.melee_hold_pose.advance_state(1.0)
 for frame in int(clip.length/DT):
  p.animation_player.seek(frame*DT,true)
  sk.force_update_all_bone_transforms()
  # Invoke the real modifier explicitly because the mixer is manually sampled.
  if "melee_hold_pose" in p and p.melee_hold_pose:
   p.melee_hold_pose._process_modification()
  var hand := pose_point(sk,"RightHand")
  var tip: Vector3 = hand*p.branch_pivot.transform*Vector3(0,0.63,0)
  rows.append({"t":frame*DT,"tip":tip,"hand":hand.origin,"hand_body":pose_point(sk,"Hips").affine_inverse()*hand.origin,"left":pose_point(sk,"LeftFoot").origin,"right":pose_point(sk,"RightFoot").origin})
 var tip_min := INF
 var hand_min := Vector3.INF
 var hand_max := -Vector3.INF
 for row in rows:
  tip_min = minf(tip_min,row.tip.y)
  hand_min = hand_min.min(row.hand_body)
  hand_max = hand_max.max(row.hand_body)
 var clearance_guard:=0.05 if action=="idle" else 0.10
 # Reviewed lowered idle/RUN minima are0.0599/0.1225m; retain margin above29mm visualground.
 check(tip_min > clearance_guard,"%s reviewed carry clears ground guard %.2fm (min %.3f)" % [action,clearance_guard,tip_min])
 check(hand_max.z-hand_min.z < 0.16,"%s armed hand has restrained sway in live hip-facing frame" % action)
 print("CARRY_CLEARANCE ",action," tip_min_m=",tip_min," hand_range=",hand_max-hand_min)
 return {"action":action,"tip_min":tip_min,"hand_range":hand_max-hand_min,"rows":rows}
func run_checks() -> void:
 for action in ["move_left","move_right","move_up","move_down","run"]:
  if not InputMap.has_action(action): InputMap.add_action(action)
 p = load("res://scripts/cornfield/player.gd").new()
 root.add_child(p)
 p.set_physics_process(false)
 p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 p.position = Vector3.ZERO
 if "melee_hold_pose" in p and p.melee_hold_pose:
  p.melee_hold_pose._process_modification() # Cold-start callback must be safe before a clip plays.
 Input.action_press("move_up")
 for frame in 8:
  p._physics_process(1.0/60.0)
  p.animation_player.advance(1.0/60.0)
 check(p.current_animation == "run","direction input directly selects run without Shift")
 var before: float = Vector2(p.velocity.x,p.velocity.z).length()
 var phase: float = p.animation_player.current_animation_position
 Input.action_press("run")
 p._physics_process(1.0/60.0)
 check(is_equal_approx(before,Vector2(p.velocity.x,p.velocity.z).length()),"Shift cannot change movement speed")
 check(p.current_animation == "run" and p.animation_player.current_animation_position >= phase,"Shift cannot restart/change locomotion clip")
 Input.action_release("move_up")
 Input.action_release("run")
 p._physics_process(1.0/60.0)
 check(Vector2(p.velocity.x,p.velocity.z).is_zero_approx(),"release immediately stops the body")
 check(p.current_animation == "idle","release selects idle")
 p.position = Vector3.ZERO
 p.visual.rotation = Vector3.ZERO
 p.attack.reset()
 var idle := carry_samples("idle")
 p.velocity = Vector3(0,0,3.0)
 var run := carry_samples("run")
 var scale_value: float = 1.0
 Input.action_press("move_up")
 Input.action_press("run")
 for frame in 8: p._physics_process(1.0/60.0)
 scale_value = p.animation_player.speed_scale
 var speed: float = Vector2(p.velocity.x,p.velocity.z).length()
 for key in ["left","right"]:
  var lowest := INF
  for row in run.rows: lowest = minf(lowest,row[key].y)
  var slip: Array[float] = []
  for i in range(1,run.rows.size()-1):
   if run.rows[i][key].y < lowest+0.03:
    var foot_speed: float = (run.rows[i+1][key].z-run.rows[i-1][key].z)/(2*DT)*scale_value
    slip.append(absf(speed+foot_speed))
  slip.sort()
  var median: float = slip[slip.size()/2]
  check(median < 0.65,"%s low-foot median world slip < 0.65 m/s, measured %.3f" % [key,median])
  print("RUN_SLIP ",key," speed=",speed," playback=",scale_value," median=",median)
 var normal_scale := scale_value
 p.movement_multiplier = 1.2
 p._physics_process(1.0/60.0)
 check(absf(p.animation_player.speed_scale-normal_scale*1.2)<0.015,"mint bonus displacement also scales the run cadence")
 p.movement_multiplier = 1.0
 p.world_max = Vector2(p.position.x,p.position.z)
 Input.action_release("move_up")
 Input.action_press("move_down")
 p._physics_process(1.0/60.0)
 check(p.current_animation == "idle","world-bound clamp cannot leave a full run cycle on a stationary body")
 p.movement_multiplier = 1.2
 var starts: Array[String] = []
 p.animation_player.animation_started.connect(func(name: String): starts.append(name))
 for frame in 8: p._physics_process(1.0/60.0)
 check(starts.is_empty() and p.current_animation == "idle","mint against a world boundary cannot restart run/idle every frame")
 p.movement_multiplier = 1.0
 Input.action_release("move_down")
 p.world_max = Vector2(100,100)
 p.request_attack()
 check(is_equal_approx(p.animation_player.speed_scale,1.0),"attack retains 1x playback after locomotion scaling")
 check(absf(p.attack.duration-1.5416667)<0.001 and is_equal_approx(p.attack.active_start,0.59) and is_equal_approx(p.attack.active_end,0.63),"original attack duration and hit window preserved")
 Input.action_release("move_up")
 Input.action_release("run")
 p.position.y = -5.0
 p._physics_process(1.0/60.0)
 check(p.current_animation == "idle" and p.animation_player.speed_scale<=1.0,"fall recovery cannot treat respawn teleport as a running stride")
 p.queue_free()
 await process_frame
 print("PLAYER_RUN_ONLY: %d checks, %d failures" % [checks,failed])
 quit(1 if failed else 0)
