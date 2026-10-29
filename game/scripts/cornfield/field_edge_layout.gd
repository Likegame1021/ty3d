extends RefCounted
## Literal first-fixture boundary. Unsupported identities are never transformed.
const PROFILE_ID := "broken_wall_nw_west_to_north_connected_v1"
const ROUTE_MARGIN := 6.2
const EXPECTED_SIZE := Vector2(77.0,48.4000015258789)
const BEDS := [["C1", 7.0, 11.0, 6.0, 5.0, 24, "x"], ["C2", 7.0, 31.2, 9.0, 4.0, 27, "x"], ["C3", 21.0, 31.2, 8.0, 3.0, 16, "x"], ["C4", 33.7, 31.2, 7.3, 3.0, 14, "x"], ["C5", 45.5, 14.0, 3.0, 8.0, 16, "z"], ["C6", 45.5, 5.0, 3.0, 5.2, 10, "z"]]
const FENCES := [["F1.1", -0.09, 15.41, 12.18, 0.17999999999999972], ["F1.2", 11.91, 12.41, 0.17999999999999972, 3.1799999999999997], ["F1.3", 11.91, 12.41, 8.18, 0.17999999999999972], ["F1.4", 19.91, 3.91, 0.17999999999999972, 8.68], ["F1.5", 19.91, 3.91, 9.18, 0.17999999999999972], ["F1.6", 28.91, -0.09, 0.17999999999999972, 4.18], ["F2.1", 45.41, -0.09, 0.18000000000000682, 21.68], ["F2.2", 45.41, 21.41, 24.480000000000004, 0.17999999999999972], ["F2.3", 69.71, 21.41, 0.18000000000000682, 11.180000000000003], ["F2.4", 45.41, 32.41, 24.480000000000004, 0.18000000000000682], ["F2.5", 45.41, 31.11, 0.18000000000000682, 1.480000000000004], ["F2.6", 35.709999999999994, 31.11, 9.88000000000001, 0.17999999999999972], ["F2.7", 35.709999999999994, 31.11, 0.18000000000000682, 13.980000000000004], ["F2.8", 27.31, 44.91, 8.580000000000002, 0.18000000000000682], ["F2.9", 27.31, 31.11, 0.17999999999999972, 13.980000000000004], ["F2.10", -0.09, 31.11, 27.58, 0.17999999999999972]]
const ORIGINAL_RECTS := [[16.9400005340576, 9.19600009918213, 2.6949999332428, 10.6480007171631], [18.4799995422363, 9.19600009918213, 11.5500001907349, 1.69400000572205], [52.3600006103516, 30.0080013275146, 2.6949999332428, 9.19600009918213], [53.8999977111816, 37.7519989013672, 10.7799997329712, 1.69400000572205]]

static func applies(d: Dictionary) -> bool:
	var sides: Array = d.get("doors",{}).keys(); sides.sort()
	return str(d.get("template_id",""))=="broken_wall" and str(d.get("id",""))=="fight_1" and int(d.get("floor",0))==1 and bool(d.get("elite",false)) and sides==["north","west"] and str(d.get("arrival_side",""))=="west" and str(d.get("departure_side",""))=="north"

static func propose(world: Node3D) -> Dictionary:
	var d: Dictionary=world.definition
	if not applies(d):return {"status":"unsupported","profile_id":"","reason":"unauthored exact room/mask/canonical route"}
	if Vector2(d.size).distance_to(EXPECTED_SIZE)>.0001:return rejected("room size changed")
	if world._obstacles.size()!=ORIGINAL_RECTS.size():return rejected("original obstacle count changed")
	for index in ORIGINAL_RECTS.size():
		var v:Array=ORIGINAL_RECTS[index]
		var expected:=Rect2(v[0],v[1],v[2],v[3])
		var actual:Dictionary=world._obstacles[index]
		if actual.kind!="brick" or not actual.rect.is_equal_approx(expected):return rejected("original obstacle footprint changed")
	if world.spawn_domain_error()!="" or world.spawn_route_paths().is_empty():return rejected("baseline spawn domain unavailable")
	var proposed:Array[Dictionary]=[]
	for row:Array in BEDS:
		proposed.append({"id":"field_"+str(row[0]),"kind":"corn","rect":Rect2(row[1],row[2],row[3],row[4]),"height":1.65,"field_edge":true,"corn_count":int(row[5]),"row_axis":str(row[6])})
	for row:Array in FENCES:
		proposed.append({"id":"field_"+str(row[0]),"kind":"fence","rect":Rect2(row[1],row[2],row[3],row[4]),"height":1.10,"field_edge":true})
	var paths:Array=world.spawn_route_paths().duplicate()
	paths.append(d.main_route)
	var access:Array=[PackedVector3Array([d.entry_position,Vector3(10.01,0,20.328)]),PackedVector3Array([Vector3(38.5,0,24.2),Vector3(66.99,0,24.2),Vector3(66.99,0,29.04)]),PackedVector3Array([Vector3(31.57,0,24.2),Vector3(31.57,0,42.108)])]
	for item:Dictionary in proposed:
		var rect:Rect2=item.rect
		for path:PackedVector3Array in paths:
			for i in range(1,path.size()):
				if segment_rect_distance(path[i-1],path[i],rect)<ROUTE_MARGIN:return rejected(item.id+" enters frozen route court")
		for side:String in d.doors:
			var door:Vector3=world.get_door_position(side)
			if segment_rect_distance(door,door+world.Catalog.door_inward(side)*4,rect)<4.5:return rejected(item.id+" enters landing capsule")
		for key:String in ["service_position","reward_position"]:
			if point_rect_distance(Vector2(d[key].x,d[key].z),rect)<3.6:return rejected(item.id+" enters resolved "+key)
		for path:PackedVector3Array in access:
			for i in range(1,path.size()):
				if segment_rect_distance(path[i-1],path[i],rect)<1.85:return rejected(item.id+" blocks retained prop access")
	return {"status":"accepted","profile_id":PROFILE_ID,"obstacles":proposed,"reason":""}

static func rejected(reason:String)->Dictionary:
	return {"status":"rejected","profile_id":PROFILE_ID,"reason":reason}

static func point_rect_distance(point:Vector2,rect:Rect2)->float:
	return point.distance_to(point.clamp(rect.position,rect.end))

static func segment_rect_distance(a3:Vector3,b3:Vector3,rect:Rect2)->float:
	var a:=Vector2(a3.x,a3.z);var b:=Vector2(b3.x,b3.z)
	if rect.has_point(a) or rect.has_point(b):return 0.0
	var corners:Array[Vector2]=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var distance:=minf(point_rect_distance(a,rect),point_rect_distance(b,rect))
	for i in 4:
		if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4])!=null:return 0.0
		distance=minf(distance,corners[i].distance_to(Geometry2D.get_closest_point_to_segment(corners[i],a,b)))
	return distance

static func segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	# Liang-Barsky slabs; includes boundary contact to match grown-box clearance.
	var low := 0.0
	var high := 1.0
	var delta := b-a
	for axis in 2:
		if absf(delta[axis]) < .0000001:
			if a[axis] < rect.position[axis] or a[axis] > rect.end[axis]: return false
		else:
			var first := (rect.position[axis]-a[axis])/delta[axis]
			var last := (rect.end[axis]-a[axis])/delta[axis]
			low = maxf(low,minf(first,last))
			high = minf(high,maxf(first,last))
			if low > high: return false
	return true

static func visible_fence_modules(rect: Rect2, original_obstacles: Array, full_span: bool = false) -> Array[Dictionary]:
	# Match _add_ruined_wall's upright BrokenWallBatch, never its broader
	# soil/rubble/collider footprint. Ground shoulders cannot conceal a rail.
	var along_x := rect.size.x > rect.size.y
	var span := (rect.size.x if along_x else rect.size.y)-(0.0 if full_span else .18)
	if not full_span: span = snappedf(span,.0001)
	var center := rect.get_center()
	var axis := 0 if along_x else 1
	var pieces: Array[Vector2] = [Vector2(center[axis]-span*.5,center[axis]+span*.5)]
	for obstacle: Dictionary in original_obstacles:
		if obstacle.kind != "brick" or float(obstacle.height) < 1.1: continue
		var footprint: Rect2 = obstacle.rect
		var brick_along_x := footprint.size.x >= footprint.size.y
		var brick_length := (footprint.size.x if brick_along_x else footprint.size.y)*.985
		var brick_depth := minf((footprint.size.y if brick_along_x else footprint.size.x)*.82,.85)
		var size := Vector2(brick_length,brick_depth) if brick_along_x else Vector2(brick_depth,brick_length)
		var brick := Rect2(footprint.get_center()-size*.5,size)
		if center[1-axis]-.09 < brick.position[1-axis] or center[1-axis]+.09 > brick.end[1-axis]: continue
		var remaining: Array[Vector2] = []
		for piece: Vector2 in pieces:
			if brick.position[axis] >= piece.y or brick.end[axis] <= piece.x:
				remaining.append(piece)
			else:
				if piece.x < brick.position[axis]: remaining.append(Vector2(piece.x,brick.position[axis]))
				if piece.y > brick.end[axis]: remaining.append(Vector2(brick.end[axis],piece.y))
		pieces = remaining
	var result: Array[Dictionary] = []
	for run_index in pieces.size():
		var piece: Vector2 = pieces[run_index]
		var length := piece.y-piece.x
		if not full_span: length = snappedf(length,.0001)
		if length <= .000001: continue
		var count := ceili(length/2.0)
		var pitch := length/count
		for index in count:
			result.append({"offset":piece.x+(index+.5)*pitch-center[axis],"length":pitch,"batch":Vector2i(run_index,index/3)})
	return result
