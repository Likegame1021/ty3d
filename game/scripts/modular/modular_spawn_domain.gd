extends RefCounted
## Authored corridor + collider clearance + seam safety; no shortest-path widening.
const PITCH := .78
var paths: Array[PackedVector3Array] = []
var anchors: Array[Dictionary] = []
var error := ""
var _world: Node3D
func build(world: Node3D) -> void:
	_world=world
	paths=[PackedVector3Array(world.definition.main_route)]
	anchors.clear();error=""
	var seen: Dictionary = {}
	for edge in range(1,paths[0].size()):
		var a: Vector3 = paths[0][edge-1]
		var b: Vector3 = paths[0][edge]
		var tangent := (b-a).normalized()
		var side := tangent.cross(Vector3.UP)
		for sample in range(ceili(a.distance_to(b)/PITCH)+1):
			var point := a+tangent*minf(sample*PITCH,a.distance_to(b))
			var key := Vector2i(roundi(point.x*100),roundi(point.z*100))
			if seen.has(key):continue
			seen[key]=true
			if not contains(point,.34):continue
			var slots := PackedVector3Array()
			for row in 5:
				for column in 5:
					var p := point+side*(column-2)*PITCH+tangent*(row-2)*PITCH
					if contains(p,.34):slots.append(p)
			if not slots.is_empty():anchors.append({"id":"module:%d:%d"%[edge,sample],"point":point,"tangent":tangent,"slots":slots})
	if anchors.is_empty():error="No complete legal corridor formations"
func contains(point: Vector3, radius: float) -> bool:
	if not point.is_finite() or radius<0 or radius>3.5:return false
	if not _world._contains_static_ground(point,radius):return false
	var p := Vector2(point.x,point.z)
	var combat := false
	for region: Dictionary in _world.definition.module_regions:
		if region.combat and region.rect.grow(-radius).has_point(p):combat=true;break
	if not combat:return false
	for seam: PackedVector3Array in _world.definition.seam_buffers:
		var nearest := Geometry2D.get_closest_point_to_segment(p,Vector2(seam[0].x,seam[0].z),Vector2(seam[1].x,seam[1].z))
		if p.distance_to(nearest)<3.5+radius:return false
	if point.distance_to(_world.definition.entry_position)<3.5+radius:return false
	# Static ground is the exact complement of the corridor rectangles; its
	# disk-vs-rectangle clearance protects the entire actor, including L corners.
	return true
