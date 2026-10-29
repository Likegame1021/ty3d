extends "res://scripts/cornfield/player.gd"
## Frozen carry layer only. All gameplay/locomotion comes from current production.
func attach_melee_hold_pose(model: Node3D) -> void:
 var source := FileAccess.get_file_as_string("res://../docs/qa/carry-only-evidence/melee-before.gd.txt")
 assert(not source.is_empty(),"Missing preserved carry fixture")
 var script := GDScript.new()
 script.source_code = source
 assert(script.reload() == OK,"Invalid preserved carry fixture")
 for item in model.find_children("*","Skeleton3D",true,false):
  var skeleton := item as Skeleton3D
  if skeleton.find_bone("RightHand") < 0: continue
  melee_hold_pose = script.new()
  melee_hold_pose.player = self
  skeleton.add_child(melee_hold_pose)
  break

func _physics_process(delta: float) -> void:
 # The preserved visual modifier predates the new state hook.
 _advance_player_physics(delta)
