extends RefCounted
## Passive, deterministic presentation sampler. No node, clock, physics, hit
## events or state transitions. The caller owns every time and state input.
const DirectionLogic = preload("res://scripts/actor_logic.gd")
var direction_logic = DirectionLogic.new()
var frame_count := 8
var foot_offset := Vector2(0,20)
var available_actions: Array[String] = ["idle","run","attack","hurt"]
# Presentation-only clip settings. span is the fraction of the authoritative
# action duration occupied by the animation; subsequent time holds last frame.
# No hit window is encoded here. Defaults stretch once over the entire action.
var clip_span := {}
var loop_fps := {"idle":6.0,"run":10.0}
func sample(action: String, action_elapsed: float, action_duration: float,
  facing_world: Vector3, camera_basis: Basis, locomotion_phase: float,
  hurt: bool, dead: bool, previous_direction: int) -> Dictionary:
 var right := Vector3(camera_basis.x.x,0,camera_basis.x.z).normalized()
 var toward_camera := Vector3(camera_basis.z.x,0,camera_basis.z.z).normalized()
 var screen_facing := Vector2(facing_world.dot(right),facing_world.dot(toward_camera))
 var row: int = direction_logic.direction_for(screen_facing,previous_direction)
 var resolved := action
 if resolved == "recover" or not available_actions.has(resolved): resolved = "idle"
 var looping: bool = resolved in ["idle","run"] and not dead
 var column := 0
 if dead:
  # No authored death sheet in this trial: hold the selected clip's last frame.
  column = frame_count - 1
 elif looping:
  column = direction_logic.frame_at(maxf(0,locomotion_phase),frame_count,float(loop_fps.get(resolved,6.0)))
 else:
  var duration := maxf(action_duration * float(clip_span.get(resolved,1.0)),0.000001)
  var normalized_phase := clampf(action_elapsed / duration,0.0,1.0)
  column = mini(floori(normalized_phase * frame_count),frame_count-1)
 return {"action":resolved,"direction":row,"frame":row*frame_count+column,
  "tint":Color(1.6,.65,.55) if hurt else Color.WHITE,"offset":foot_offset}
