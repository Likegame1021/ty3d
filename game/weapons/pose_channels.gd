extends RefCounted
## Copied canonical/visual snapshots. Captures never advance gameplay clocks.
var _generation := -1
var _binding_id: StringName
var _bone_count := 0
var _canonical: Dictionary = {}
var _visual: Dictionary = {}
var produced_visual := false
var last_rejection := ""

func reset(generation: int, binding_id: StringName, bone_count: int) -> void:
 _generation = generation
 _binding_id = binding_id
 _bone_count = bone_count
 _canonical.clear()
 _visual.clear()
 produced_visual = false
 last_rejection = ""

func _reject(reason: String) -> bool:
 last_rejection = reason
 return false

func _valid(pose: Array[Transform3D], token: Dictionary, stage: String) -> bool:
 for field in ["generation", "physics_frame", "process_frame", "evaluation_serial"]:
  if typeof(token.get(field)) != TYPE_INT or token[field] < 0:
   return _reject("invalid token " + field)
 if token.generation != _generation or token.get("binding_id") != _binding_id or token.get("stage") != stage:
  return _reject("stale generation, binding, or stage")
 if pose.size() != _bone_count or _bone_count <= 0:
  return _reject("bone count mismatch")
 for transform in pose:
  if not transform.is_finite():
   return _reject("nonfinite transform")
 return true

func _same_evaluation(a: Dictionary, b: Dictionary) -> bool:
 for field in ["generation", "binding_id", "physics_frame", "process_frame", "evaluation_serial"]:
  if a[field] != b[field]: return false
 return true

func _capture(pose: Array[Transform3D], token: Dictionary, previous: Dictionary) -> Dictionary:
 if not previous.is_empty():
  if token.evaluation_serial < previous.token.evaluation_serial:
   _reject("older evaluation")
   return {}
  if token.evaluation_serial == previous.token.evaluation_serial:
   if token != previous.token or pose != previous.pose:
    _reject("conflicting duplicate")
    return {}
   return previous
 return {"pose":pose.duplicate(), "token":token.duplicate(true)}

func capture_canonical(pose: Array[Transform3D], token: Dictionary) -> bool:
 if not _valid(pose, token, "canonical"): return false
 var snapshot := _capture(pose, token, _canonical)
 if snapshot.is_empty(): return false
 _canonical = snapshot
 return true

func capture_visual(pose: Array[Transform3D], token: Dictionary) -> bool:
 if not _valid(pose, token, "visual"): return false
 if _canonical.is_empty() or not _same_evaluation(token, _canonical.token):
  return _reject("visual without matching completed canonical")
 var snapshot := _capture(pose, token, _visual)
 if snapshot.is_empty(): return false
 _visual = snapshot
 produced_visual = true
 return true

func _copy(snapshot: Dictionary, generation: int, binding_id: StringName) -> Dictionary:
 if generation != _generation or binding_id != _binding_id or snapshot.is_empty():
  return {"valid":false,"pose":[],"token":{}}
 return {"valid":true,"pose":snapshot.pose.duplicate(),"token":snapshot.token.duplicate(true)}

func canonical_copy(generation: int, binding_id: StringName) -> Dictionary:
 return _copy(_canonical, generation, binding_id)

func visual_copy(generation: int, binding_id: StringName) -> Dictionary:
 return _copy(_visual, generation, binding_id)
