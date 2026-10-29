extends RefCounted
## Immutable static permission, separate from the authored encounter schedule.
## Constructed before breakables; runtime availability never changes these paths.
const SIDES := ["north","east","south","west"]
const HALF_WIDTH := 3.5
const LANDING_INSET := 4.0
const PITCH := .78
const ACTOR_RADIUS := .34
var paths: Array[PackedVector3Array] = []
var anchors: Array[Dictionary] = []
var error := ""
var _world: Node3D
var _landings: Array[PackedVector3Array] = []

func build(world: Node3D) -> void:
	_world = world
	paths.clear(); anchors.clear(); _landings.clear(); error = ""
	var doors: Dictionary = world.definition.get("doors",{})
	var sides: Array[String] = []
	var destinations: Array = []
	for side in doors:
		if not side in SIDES:
			error = "unknown actual door: "+str(side); return
		if destinations.has(doors[side]):
			error = "duplicate actual door destination: "+str(doors[side]); return
		destinations.append(doors[side])
	if world.navigation==null or world.navigation.get_point_count()==0:
		error = "empty deterministic navigation graph"; return
	for side: String in SIDES:
		if doors.has(side):
			sides.append(side)
			var door: Vector3 = world.get_door_position(side)
			_landings.append(PackedVector3Array([door,door+world.Catalog.door_inward(side)*LANDING_INSET]))
	for a in sides.size():
		for b in range(a+1,sides.size()):
			var start: Vector3 = _landings[a][1]
			var target: Vector3 = _landings[b][1]
			var path := PackedVector3Array([start])
			if world.segment_clear(start,target,world.NAV_RADIUS):
				path.append(target)
			else:
				var ai: int = world._nearest_reachable_node(start,world.NAV_RADIUS)
				var bi: int = world._nearest_reachable_node(target,world.NAV_RADIUS)
				if ai<0 or bi<0:
					error = "disconnected door landing: %s/%s"%[sides[a],sides[b]]; return
				var raw: PackedVector3Array = world.navigation.get_point_path(ai,bi)
				if raw.is_empty():
					error = "disconnected door pair: %s/%s"%[sides[a],sides[b]]; return
				raw.append(target)
				path.append_array(world._smooth_path(start,raw,world.NAV_RADIUS))
			for i in range(1,path.size()):
				if not world.segment_clear(path[i-1],path[i],world.NAV_RADIUS):
					error = "uncleared door path: %s/%s"%[sides[a],sides[b]]; return
			paths.append(path)
	if paths.is_empty():
		error = "empty multi-door route union"; return
	var seen: Dictionary = {}
	for path_index in paths.size():
		var path: PackedVector3Array = paths[path_index]
		for edge in range(1,path.size()):
			var span: Vector3 = path[edge]-path[edge-1]
			var length := span.length()
			if length<.0001: continue
			var tangent := span/length
			var side := tangent.cross(Vector3.UP)
			for sample in range(ceili(length/PITCH)+1):
				var point: Vector3 = path[edge-1]+tangent*minf(sample*PITCH,length)
				var key := Vector2i(roundi(point.x*100),roundi(point.z*100))
				if seen.has(key): continue
				seen[key] = true
				# Every formation centre is itself a legal hint/placement anchor.
				if not contains(point,ACTOR_RADIUS): continue
				var slots := PackedVector3Array()
				for row in 5:
					for column in 5:
						var candidate := point+side*float(column-2)*PITCH+tangent*float(row-2)*PITCH
						if contains(candidate,ACTOR_RADIUS): slots.append(candidate)
				if not slots.is_empty():
					anchors.append({"id":"%d:%d:%d"%[path_index,edge,sample],"point":point,"tangent":tangent,"slots":slots})
	if anchors.is_empty(): error = "no legal static formation anchors"

func contains(point: Vector3, radius: float) -> bool:
	if not error.is_empty() or not point.is_finite() or radius<0 or radius>HALF_WIDTH:
		return false
	if not _world._contains_static_ground(point,radius) or _world.is_spawn_excluded(point,radius):
		return false
	var p := Vector2(point.x,point.z)
	var entry: Vector3 = _world.definition.get("entry_position",Vector3.INF)
	if Vector2(point.x-entry.x,point.z-entry.z).length()<3.5: return false
	for landing: PackedVector3Array in _landings:
		var nearest := Geometry2D.get_closest_point_to_segment(p,Vector2(landing[0].x,landing[0].z),Vector2(landing[1].x,landing[1].z))
		if p.distance_to(nearest)<HALF_WIDTH+radius: return false
	for path: PackedVector3Array in paths:
		for i in range(1,path.size()):
			var nearest := Geometry2D.get_closest_point_to_segment(p,Vector2(path[i-1].x,path[i-1].z),Vector2(path[i].x,path[i].z))
			if p.distance_to(nearest)+radius<=HALF_WIDTH+.000001 and _world._static_segment_clear(point,Vector3(nearest.x,0,nearest.y),radius):
				return true
	return false
