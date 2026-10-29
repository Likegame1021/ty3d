extends SceneTree
## Same production movement, with old/new carry layers, under identical real inputs.
const ACTIONS := ["move_up","move_right","move_down","move_left","run"]
var actors := []
var frame := 0
var failed := 0
var max_position := 0.0
var max_speed := 0.0
var max_phase := 0.0
var max_cadence := 0.0
func _initialize() -> void: call_deferred("build")
func build() -> void:
 for action in ACTIONS:
  if not InputMap.has_action(action): InputMap.add_action(action)
 for path in ["res://tests/fixtures/carry_before_player.gd","res://scripts/cornfield/player.gd"]:
  var actor = load(path).new()
  actor.collision_layer = 0
  actor.collision_mask = 0
  root.add_child(actor)
  actor.set_physics_process(false)
  actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
  actors.append(actor)
func _physics_process(delta: float) -> bool:
 if actors.size() != 2: return false
 if frame in [0,20,40,60,80,100,120,140,160,180,200]:
  for action in ACTIONS: Input.action_release(action)
  match frame:
   0,20,120,140: Input.action_press("move_up")
   40,60: Input.action_press("move_right")
   80: Input.action_press("move_down"); Input.action_press("move_left")
   180: Input.action_press("move_down")
  if frame in [20,60]: Input.action_press("run")
  for actor in actors:
   if frame == 120: actor.movement_multiplier = 1.2
   if frame == 140: actor.world_min.y = actor.position.z
   if frame == 160:
    actor.world_min.y = -100
    actor.set_attack_recovery_multiplier(.8464)
    actor.request_attack()
   if frame == 180: actor.cancel_actions()
   if frame == 200: actor.position.y = -5
 for actor in actors:
  actor._physics_process(delta)
  actor.animation_player.advance(delta)
 var a = actors[0]
 var b = actors[1]
 max_position = maxf(max_position,a.position.distance_to(b.position))
 max_speed = maxf(max_speed,a.velocity.distance_to(b.velocity))
 max_phase = maxf(max_phase,absf(a.animation_player.current_animation_position-b.animation_player.current_animation_position))
 max_cadence = maxf(max_cadence,absf(a.animation_player.speed_scale-b.animation_player.speed_scale))
 if a.current_animation != b.current_animation: failed += 1
 frame += 1
 if frame == 220: call_deferred("finish")
 return false
func finish() -> void:
 for action in ACTIONS: Input.action_release(action)
 for value in [max_position,max_speed,max_phase,max_cadence]:
  if value > .000001: failed += 1
 var summary := {"frames":frame,"position_difference_m":max_position,"velocity_difference_mps":max_speed,"phase_difference_s":max_phase,"cadence_difference":max_cadence,"failures":failed}
 var output := FileAccess.open("res://../docs/qa/carry-only-evidence/motion-invariance.json",FileAccess.WRITE)
 output.store_string(JSON.stringify(summary,"  "))
 print("CARRY_MOTION_INVARIANCE ",JSON.stringify(summary))
 for actor in actors: actor.free()
 quit(1 if failed else 0)
