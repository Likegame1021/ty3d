extends SkeletonModifier3D
## Read-only evaluation boundary. Callback retains its registered generation.
var capture: Callable
func _process_modification() -> void:
 if capture.is_valid(): capture.call()
