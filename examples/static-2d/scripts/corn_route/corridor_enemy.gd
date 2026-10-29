extends "res://scripts/actor.gd"
var corridor_id := 0
var route_layout: RefCounted
func _physics_process(delta):
 # The original actor only turned while moving; this isolated enemy must
 # acquire close targets before attack, then keep facing locked during swing.
 if is_instance_valid(target) and state not in ["attack","hurt","recover"]:
  var toward: Vector3=target.global_position-global_position
  if toward.length_squared()>.001:
   direction=logic.direction_for(Vector2(toward.x,toward.z),direction)
 super._physics_process(delta)
 if route_layout:
  position=route_layout.clamp_to_corridor(corridor_id,position)
