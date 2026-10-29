extends RefCounted
## JSON manifest is authoritative. Geometry is rebuilt from its validated ports.
const Landmarks = preload("res://scripts/modular/rural_landmarks.gd")
const SIZE := 24.0
const WIDTH := 8.0
const SIDES := ["north","east","south","west"]
const DELTAS := [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]
const LIMIT := 32

static func generate(seed_value: int, force_fallback: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := rng.randi_range(5,6)
	var cells: Array[Vector2i] = []
	var attempts := 0
	if not force_fallback:
		for attempt in LIMIT:
			attempts = attempt+1
			cells = [Vector2i.ZERO]
			while cells.size()<count:
				var options: Array[Vector2i] = []
				for delta: Vector2i in DELTAS:
					var candidate := cells[-1]+delta
					if cells.has(candidate): continue
					var neighbors := 0
					for other: Vector2i in cells:
						if absi(candidate.x-other.x)+absi(candidate.y-other.y)==1: neighbors+=1
					if neighbors==1: options.append(candidate)
				if options.is_empty(): break
				cells.append(options[rng.randi_range(0,options.size()-1)])
			if cells.size()==count: break
	var fallback := cells.size()!=count
	if fallback:
		attempts=LIMIT
		cells.clear()
		for i in count: cells.append(Vector2i(i,0))
	var modules: Array = []
	for i in count:
		var incoming := side_for(cells[i-1]-cells[i]) if i>0 else ""
		var outgoing := side_for(cells[i+1]-cells[i]) if i<count-1 else ""
		var kind := "entry_dirt" if i==0 else ("exit_flag" if i==count-1 else ("corn_straight" if opposite(incoming)==outgoing else "corn_turn"))
		modules.append({"id":kind,"cell":[cells[i].x,cells[i].y],"in_side":incoming,"out_side":outgoing,"rotation":SIDES.find(incoming) if i>0 else SIDES.find(outgoing)})
	return {"version":1,"seed":seed_value,"modules":modules,"attempts":attempts,"fallback":fallback}

static func opposite(side: String) -> String:
	return SIDES[(SIDES.find(side)+2)%4] if side in SIDES else ""

static func side_for(delta: Vector2i) -> String:
	return SIDES[DELTAS.find(delta)] if delta in DELTAS else ""

static func validate(m: Dictionary) -> String:
	if m.get("version")!=1 or not m.get("modules") is Array: return "unsupported manifest"
	if not _integer(m.get("seed")) or not _integer(m.get("attempts")) or int(m.attempts)<1 or int(m.attempts)>LIMIT or not m.get("fallback") is bool: return "invalid generation metadata"
	if float(m.seed)<-2147483648.0 or float(m.seed)>2147483647.0:return "seed must be a signed 32-bit integer"
	if m.modules.size() not in [5,6]: return "module count must be five or six"
	var cells: Array[Vector2i] = []
	for i in m.modules.size():
		var item = m.modules[i]
		if not item is Dictionary or not item.get("cell") is Array or item.cell.size()!=2: return "invalid module"
		if not _integer(item.cell[0]) or not _integer(item.cell[1]) or absf(item.cell[0])>6 or absf(item.cell[1])>6: return "invalid grid cell"
		var cell := Vector2i(int(item.cell[0]),int(item.cell[1]))
		if cells.has(cell): return "overlapping modules"
		cells.append(cell)
		if not item.get("in_side") is String or not item.get("out_side") is String: return "invalid ports"
		if (i==0 and item.in_side!="") or (i>0 and item.in_side not in SIDES): return "invalid entrance port"
		if (i==m.modules.size()-1 and item.out_side!="") or (i<m.modules.size()-1 and item.out_side not in SIDES): return "invalid exit port"
		if item.in_side==item.out_side: return "ports overlap"
		var expected := "entry_dirt" if i==0 else ("exit_flag" if i==m.modules.size()-1 else ("corn_straight" if opposite(item.in_side)==item.out_side else "corn_turn"))
		if item.get("id")!=expected: return "module does not match ports"
		if not _integer(item.get("rotation")) or int(item.rotation)!=SIDES.find(item.in_side if i>0 else item.out_side): return "rotation mismatch"
	for i in cells.size():
		for j in range(i+1,cells.size()):
			var delta := cells[j]-cells[i]
			var adjacent := absi(delta.x)+absi(delta.y)==1
			if adjacent != (j==i+1): return "chain adjacency mismatch"
			if j==i+1 and (side_for(delta)!=m.modules[i].out_side or opposite(side_for(delta))!=m.modules[j].in_side): return "incompatible ports"
	return ""

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))

static func port(side: String) -> Vector2:
	return {"north":Vector2(12,0),"east":Vector2(24,12),"south":Vector2(12,24),"west":Vector2(0,12)}.get(side,Vector2(12,12))

static func materialize(m: Dictionary) -> Dictionary:
	if validate(m)!="": return {}
	var low := Vector2i(99,99)
	var high := Vector2i(-99,-99)
	for item: Dictionary in m.modules:
		var cell := Vector2i(int(item.cell[0]),int(item.cell[1]))
		low=low.min(cell); high=high.max(cell)
	var size := Vector2(high-low+Vector2i.ONE)*SIZE
	var roads: Array[Rect2] = []
	var regions: Array[Dictionary] = []
	var seams: Array[PackedVector3Array] = []
	var route := PackedVector3Array()
	var occupied: Dictionary = {}
	for i in m.modules.size():
		var item: Dictionary = m.modules[i]
		var cell := Vector2i(int(item.cell[0]),int(item.cell[1]))-low
		occupied[cell]=true
		var origin := Vector2(cell)*SIZE
		var center := origin+Vector2.ONE*12
		var local_roads: Array[Rect2] = [Rect2(center-Vector2.ONE*WIDTH*.5,Vector2.ONE*WIDTH)]
		for side: String in [item.in_side,item.out_side]:
			if side=="": continue
			var end := origin+port(side)
			local_roads.append(Rect2(Vector2(minf(center.x,end.x)-WIDTH*.5 if side in ["north","south"] else minf(center.x,end.x), minf(center.y,end.y)-WIDTH*.5 if side in ["east","west"] else minf(center.y,end.y)), Vector2(WIDTH if side in ["north","south"] else absf(center.x-end.x), WIDTH if side in ["east","west"] else absf(center.y-end.y))))
		roads.append_array(local_roads)
		regions.append({"index":i,"id":item.id,"rect":Rect2(origin,Vector2.ONE*SIZE),"center":Vector3(center.x,0,center.y),"roads":local_roads,"combat":i>0 and i<m.modules.size()-1,"landmark":Landmarks.describe(i,m.modules.size(),Vector3(center.x,0,center.y))})
		route.append(Vector3(center.x,0,center.y))
		if item.out_side!="":
			var end := origin+port(item.out_side)
			var point := Vector3(end.x,0,end.y)
			route.append(point)
			var delta := Vector3(DELTAS[SIDES.find(item.out_side)].x,0,DELTAS[SIDES.find(item.out_side)].y)
			seams.append(PackedVector3Array([point-delta*4,point+delta*4]))
	# Exact rectangular complement. Global grid includes unoccupied cells, so
	# diagonally neighboring modules cannot cut across the intervening field.
	var xs: Array[float] = [0.0,size.x]
	var ys: Array[float] = [0.0,size.y]
	for rect: Rect2 in roads:
		for x: float in [rect.position.x,rect.end.x]:
			if not xs.has(x): xs.append(x)
		for y: float in [rect.position.y,rect.end.y]:
			if not ys.has(y): ys.append(y)
	xs.sort();ys.sort()
	var obstacles: Array = []
	for ix in xs.size()-1:
		for iy in ys.size()-1:
			var rect := Rect2(Vector2(xs[ix],ys[iy]),Vector2(xs[ix+1]-xs[ix],ys[iy+1]-ys[iy]))
			var inside := false
			for road: Rect2 in roads:
				if road.has_point(rect.get_center()): inside=true;break
			if not inside: obstacles.append({"id":"field_%d"%obstacles.size(),"kind":"corn","rect":rect,"height":1.25})
	return {"id":"modular_chain","template_id":"modular_chain_v1","title":"田埂上的暑假","kind":"combat","grid":Vector2i.ZERO,"size":size,"doors":{},"completion":false,"encounter":"swarm","elite":false,"outline":[Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)],"obstacles":obstacles,"main_route":route,"entry_position":route[0],"baseline_size":size,"baseline_area":size.x*size.y,"species":["beetle"],"door_width":WIDTH,"ground_y":0.0,"reward_position":route[-1],"service_position":route[0],"breakables":[],"presentation":{"profile":"modular","bridge_zones":[],"key_room":false,"soil_tint":Color("796440"),"furrow_direction":Vector2.DOWN},"corridor_rects":roads,"module_regions":regions,"seam_buffers":seams,"modular_manifest":m.duplicate(true),"content_revision":3,"floor":1,"node_type":"ANVIL","melee_fallback":"beetle"}
