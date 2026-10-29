extends Node3D
## One authoritative XZ footprint drives 3D geometry, collision and shared navigation.
## Native navigation serves normal queries after synchronization; the shared AStar3D
## graph is a deterministic startup fallback. Neither supports layered floors yet.

const SpawnDomain = preload("res://scripts/cornfield/spawn_domain.gd")
const FieldEdges = preload("res://scripts/cornfield/field_edge_layout.gd")
const FieldParcels = preload("res://scripts/cornfield/field_parcel_layout.gd")
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const WALL_THICKNESS: float = 0.4
const WALL_HEIGHT: float = 1.75
const NAV_STEP: float = 0.9
# One shared graph accommodates the largest current actor (0.625u Boss).
# Per-query endpoint connections still use each actor's real physical radius.
const NAV_RADIUS: float = 0.65

var field_edges_enabled := false
# Each manifest-enabled hostile profile still requires complete live atomic validation.
var field_parcels_enabled := true
var _field_retained_state: Dictionary = {}
var _field_validation: Dictionary = {}
var _field_staged_bodies: Dictionary = {}
var _field_edge_report: Dictionary = {"status":"unsupported"}
var _field_edges: Array[Dictionary] = []
var _field_base_obstacles: Array = []
var _field_edge_grid: Dictionary = {}
const FIELD_EDGE_CELL := 6.0
var _spawn_domain: RefCounted
var spawn_domain_generation := 0
var spawn_domain_build_usec := 0
var dynamic_obstacle_revision := 0
var definition: Dictionary = {}
var walkable_area: float = 0.0
var doors_open: bool = false
var navigation_region: NavigationRegion3D
var navigation: AStar3D = AStar3D.new()
var _outline: PackedVector2Array = PackedVector2Array()
var _obstacles: Array = []
var _wall_segments: Array = []
var _door_bodies: Dictionary = {}
var _door_visuals: Dictionary = {}
var _door_labels: Dictionary = {}
var _exit_labels: Dictionary = {}
var _route_unlocked := false
var _cells: Dictionary = {}
var _dynamic_obstacles: Dictionary = {}
var _spawn_cursor: int = 0
var _materials: Dictionary = {}
var _occludable: Array[MeshInstance3D] = []
var _cut_meshes: Array[GeometryInstance3D] = []
var _occlusion_camera: Camera3D
var _occlusion_target: Node3D
var _occlusion_time: float = 0.0
var _occlusion_targets: Array[Node3D] = []
static var _asset_meshes: Dictionary = {}
static var _farm_scenes: Dictionary = {}
const FARM_ASSET_PATH := "res://assets/environment/blender/cornfield_batch_v001/"
const SPRINT_ASSET_PATH := "res://assets/sprint_20261002/environment/"

func build(room_definition: Dictionary, retained_room_state: Dictionary = {}) -> void:
	for body: Node in _field_staged_bodies.values():
		if is_instance_valid(body): body.free()
	_field_staged_bodies.clear()
	_field_retained_state = retained_room_state.duplicate(true)
	_field_validation.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	definition = room_definition.duplicate(true)
	_outline = PackedVector2Array(definition.outline)
	_obstacles = definition.obstacles.duplicate(true)
	_wall_segments.clear()
	_door_bodies.clear()
	_door_visuals.clear()
	_door_labels.clear()
	_exit_labels.clear()
	_route_unlocked = false
	_occludable.clear()
	_cut_meshes.clear()
	_materials.clear()
	_dynamic_obstacles.clear()
	doors_open = false
	_spawn_cursor = 0
	_field_edges.clear()
	_field_base_obstacles.clear()
	_field_edge_grid.clear()
	_field_edge_report = {"status":"disabled" if not field_edges_enabled else "unsupported"}
	navigation_region = null
	_build_ground()
	_build_boundary()
	# Original static graph owns canonical normalization and spawn permission.
	# The candidate creates no temporary native region and never re-normalizes.
	var edge_candidate: bool = (field_parcels_enabled and FieldParcels.applies(definition)) or (field_edges_enabled and FieldEdges.applies(definition))
	_build_navigation(not edge_candidate)
	_normalize_room_anchors()
	_build_spawn_domain()
	if edge_candidate:
		_apply_field_edges()
	_build_obstacles()
	_build_trails()
	_build_field_details()

func get_door_position(side: String) -> Vector3:
	return Catalog.door_position(side,definition.size)

func get_outline_normalized() -> Array:
	var normalized: Array[Vector2] = []
	var size: Vector2 = definition.size
	for point in _outline:
		normalized.append(point/size)
	return normalized

func set_doors_open(value: bool) -> void:
	doors_open = value
	for side in _door_bodies:
		var body: StaticBody3D = _door_bodies[side]
		body.collision_layer = 0 if value else 1
		var bars: Node3D = _door_visuals[side]
		bars.visible = not value
	_update_door_labels()
	# The room navmesh intentionally ends at the inside door approach. Room
	# transitions own the final doorway crossing; enemies never leave the room.

func contains_ground(point: Vector3, radius: float = Catalog.PLAYER_RADIUS) -> bool:
	if not _contains_static_ground(point,radius): return false
	var ground_xz := Vector2(point.x,point.z)
	for obstacle in _dynamic_obstacles.values():
		var center: Vector3 = obstacle.position
		if ground_xz.distance_squared_to(Vector2(center.x,center.z)) < pow(float(obstacle.radius)+radius,2): return false
	return true

func _contains_static_ground(point: Vector3, radius: float) -> bool:
	var ground_xz: Vector2 = Vector2(point.x,point.z)
	var inside: bool = Geometry2D.is_point_in_polygon(ground_xz,_outline)
	if not inside and doors_open:
		for side in definition.doors:
			var door: Vector3 = get_door_position(side)
			if absf((point-door).dot(Catalog.door_inward(side))) <= WALL_THICKNESS and point.distance_to(door) < Catalog.DOOR_WIDTH*.5-radius:
				inside = true
	if not inside:
		return false
	for segment in _wall_segments:
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(ground_xz,segment[0],segment[1])
		if ground_xz.distance_squared_to(nearest) < pow(radius+WALL_THICKNESS*.5,2):
			return false
	if not doors_open:
		for side in definition.doors:
			var door: Vector3 = get_door_position(side)
			var inward: Vector3 = Catalog.door_inward(side)
			var relative: Vector3 = point-door
			if absf(relative.dot(inward)) < radius+WALL_THICKNESS*.5 and absf(relative.dot(inward.cross(Vector3.UP))) < Catalog.DOOR_WIDTH*.5+radius:
				return false
	var static_obstacles: Array = _obstacles if _field_edge_grid.is_empty() else _field_base_obstacles
	for obstacle in static_obstacles:
		var rectangle: Rect2 = obstacle.rect
		if rectangle.grow(radius).has_point(ground_xz):
			return false
	if not _field_edge_grid.is_empty():
		var first := Vector2i(floori((ground_xz.x-radius)/FIELD_EDGE_CELL),floori((ground_xz.y-radius)/FIELD_EDGE_CELL))
		var last := Vector2i(floori((ground_xz.x+radius)/FIELD_EDGE_CELL),floori((ground_xz.y+radius)/FIELD_EDGE_CELL))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				for rectangle: Rect2 in _field_edge_grid.get(Vector2i(x,z),[]):
					if rectangle.grow(radius).has_point(ground_xz): return false
	return true

func register_dynamic_obstacle(id: String, at: Vector3, radius: float = .35) -> void:
	dynamic_obstacle_revision += 1
	var previous: Dictionary = _dynamic_obstacles.get(id,{})
	_dynamic_obstacles[id] = {"position":at,"radius":radius}
	if not previous.is_empty():
		_refresh_dynamic_cells(previous.position,float(previous.radius))
	_refresh_dynamic_cells(at,radius)

func remove_dynamic_obstacle(id: String) -> void:
	if not _dynamic_obstacles.has(id):
		return
	dynamic_obstacle_revision += 1
	var previous: Dictionary = _dynamic_obstacles[id]
	_dynamic_obstacles.erase(id)
	_refresh_dynamic_cells(previous.position,float(previous.radius))

func _refresh_dynamic_cells(at: Vector3, radius: float) -> void:
	# Disable whole affected cell squares rather than only their centers, so
	# graph diagonals cannot cut through the circular collider between vertices.
	var padding: float = radius+NAV_RADIUS+NAV_STEP*.7072
	var first: Vector2i = Vector2i(floori((at.x-padding)/NAV_STEP-.5),floori((at.z-padding)/NAV_STEP-.5))
	var last: Vector2i = Vector2i(ceili((at.x+padding)/NAV_STEP-.5),ceili((at.z+padding)/NAV_STEP-.5))
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell: Vector2i = Vector2i(x,z)
			if not _cells.has(cell):
				continue
			var point: Vector3 = navigation.get_point_position(_cells[cell])
			var blocked: bool = false
			for obstacle in _dynamic_obstacles.values():
				var other: Vector3 = obstacle.position
				if Vector2(point.x-other.x,point.z-other.z).length() < float(obstacle.radius)+NAV_RADIUS+NAV_STEP*.7072:
					blocked = true
					break
			navigation.set_point_disabled(_cells[cell],blocked)

func segment_clear(start: Vector3, finish: Vector3, radius: float = Catalog.PLAYER_RADIUS) -> bool:
	for obstacle in _dynamic_obstacles.values():
		var center: Vector3 = obstacle.position
		var ground_center: Vector2 = Vector2(center.x,center.z)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(ground_center,Vector2(start.x,start.z),Vector2(finish.x,finish.z))
		if closest.distance_squared_to(ground_center) < pow(float(obstacle.radius)+radius,2):
			return false
	var steps: int = maxi(1,ceili(start.distance_to(finish)/.2))
	for index in range(steps+1):
		if not contains_ground(start.lerp(finish,float(index)/steps),radius):
			return false
	return true

func path_to(from: Vector3, to: Vector3, actor_radius: float = Catalog.PLAYER_RADIUS) -> PackedVector3Array:
	# Nav-grid clearance is a conservative construction margin, not the actor's
	# physical radius. Legal feet touching a wall must still connect to the graph.
	if not contains_ground(from,actor_radius):
		return PackedVector3Array()
	if not contains_ground(to,actor_radius):
		# A larger enemy cannot occupy a small player's exact wall-hugging
		# position. End at the nearest legal approach rather than stop chasing.
		if not contains_ground(to,Catalog.PLAYER_RADIUS):
			return PackedVector3Array()
		to = _closest_legal_goal(to,actor_radius)
		if not to.is_finite():
			return PackedVector3Array()
	if segment_clear(from,to,actor_radius):
		return PackedVector3Array([to])
	if navigation_region != null and is_inside_tree():
		var map: RID = navigation_region.get_navigation_map()
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			var native_path: PackedVector3Array = NavigationServer3D.map_get_path(map,from,to,true)
			if native_path.size() > 1 and native_path[-1].distance_to(to) < .9:
				var native_valid: bool = true
				var previous: Vector3 = from
				for waypoint in native_path:
					if not segment_clear(previous,waypoint,actor_radius):
						native_valid = false
						break
					previous = waypoint
				if native_valid and segment_clear(previous,to,actor_radius):
					native_path.append(to)
					return _smooth_path(from,native_path,actor_radius)
	var start_id: int = _nearest_reachable_node(from,actor_radius)
	var end_id: int = _nearest_reachable_node(to,actor_radius)
	if start_id < 0 or end_id < 0:
		return PackedVector3Array()
	var path: PackedVector3Array = navigation.get_point_path(start_id,end_id)
	if path.is_empty():
		return path
	path.append(to)
	var result: PackedVector3Array = _smooth_path(from,path,actor_radius)
	var previous: Vector3 = from
	for point in result:
		if not segment_clear(previous,point,actor_radius):
			return PackedVector3Array()
		previous = point
	return result

func resolve_service_anchor() -> Dictionary:
	# The authored entry is canonical. A player's alternate-door revisit must
	# not relocate the service. Call only after all dynamic props are registered.
	var failed: Dictionary = {"ok":false,"position":Vector3.INF,"path_length":INF,"short_path":false}
	var start: Vector3 = definition.get("entry_position",Vector3.INF)
	if not start.is_finite() or not contains_ground(start,Catalog.PLAYER_RADIUS):
		return failed
	var route: PackedVector3Array = PackedVector3Array([start])
	for target: Vector3 in definition.get("main_route",PackedVector3Array()):
		if not target.is_finite() or target.distance_squared_to(route[-1]) < .0001:
			continue
		var leg: PackedVector3Array = _service_anchor_path(route[-1],target)
		for waypoint: Vector3 in leg:
			if waypoint.distance_squared_to(route[-1]) > .0001:
				route.append(waypoint)
	# Fixed distance and left/right order make this independent of global RNG,
	# native-navigation synchronization and arrival/player position.
	for distance: float in [6.0,6.5,7.0,7.5,8.0,8.5,9.0]:
		var remaining: float = distance
		for index in range(1,route.size()):
			var previous: Vector3 = route[index-1]
			var delta: Vector3 = route[index]-previous
			var span: float = delta.length()
			if span < .0001:
				continue
			if remaining > span+.0001:
				remaining -= span
				continue
			var sample: Vector3 = previous+delta*(clampf(remaining/span,0.0,1.0))
			var lateral: Vector3 = delta.normalized().cross(Vector3.UP)
			for offset: float in [0.0,.45,-.45,.9,-.9]:
				var result: Dictionary = _validate_service_anchor(start,sample+lateral*offset,true)
				if result.ok:
					return result
			break
	# Custom/unexpected layouts may have no short point. The legacy anchor is
	# merely a candidate, never a permission to overlap a wall, prop or doorway.
	var fallback: Vector3 = definition.get("service_position",Vector3.INF)
	var validated: Dictionary = _validate_service_anchor(start,fallback,false)
	return validated if validated.ok else failed

func _validate_service_anchor(start: Vector3, candidate: Vector3, short_path: bool) -> Dictionary:
	var failed: Dictionary = {"ok":false,"position":Vector3.INF,"path_length":INF,"short_path":false}
	if not candidate.is_finite() or not contains_ground(candidate,.6):
		return failed
	for side: String in definition.get("doors",{}):
		if candidate.distance_to(get_door_position(side)) < 5.0-.0001:
			return failed
	var path: PackedVector3Array = _service_anchor_path(start,candidate)
	if path.is_empty():
		return failed
	var length: float = 0.0
	var previous: Vector3 = start
	for waypoint: Vector3 in path:
		length += previous.distance_to(waypoint)
		previous = waypoint
	if short_path and (length < 6.0-.0001 or length > 9.0+.0001):
		return failed
	return {"ok":true,"position":candidate,"path_length":length,"short_path":short_path}

func _service_anchor_path(start: Vector3, target: Vector3) -> PackedVector3Array:
	# Use the existing deterministic graph rather than native asynchronous paths
	# for placement. Ground, segment, graph topology and dynamic-cell authority
	# are unchanged; actor travel still uses the original path_to interface.
	if not contains_ground(start,Catalog.PLAYER_RADIUS) or not contains_ground(target,Catalog.PLAYER_RADIUS):
		return PackedVector3Array()
	if segment_clear(start,target,Catalog.PLAYER_RADIUS):
		return PackedVector3Array([target])
	var start_id: int = _nearest_reachable_node(start,Catalog.PLAYER_RADIUS)
	var end_id: int = _nearest_reachable_node(target,Catalog.PLAYER_RADIUS)
	if start_id < 0 or end_id < 0:
		return PackedVector3Array()
	var path: PackedVector3Array = navigation.get_point_path(start_id,end_id)
	if path.is_empty():
		return path
	path.append(target)
	var smooth: PackedVector3Array = _smooth_path(start,path,Catalog.PLAYER_RADIUS)
	var previous: Vector3 = start
	for waypoint: Vector3 in smooth:
		if not segment_clear(previous,waypoint,Catalog.PLAYER_RADIUS):
			return PackedVector3Array()
		previous = waypoint
	return smooth

func find_path(from: Vector3, to: Vector3, actor_radius: float = Catalog.PLAYER_RADIUS) -> PackedVector3Array:
	return path_to(from,to,actor_radius)

func _build_spawn_domain() -> void:
	var started := Time.get_ticks_usec()
	spawn_domain_build_usec = 0
	spawn_domain_generation += 1
	_spawn_domain = null
	if definition.get("doors",{}).size()<2: return
	_spawn_domain = SpawnDomain.new()
	_spawn_domain.build(self)
	spawn_domain_build_usec = Time.get_ticks_usec()-started

func uses_spawn_domain() -> bool:
	return definition.get("doors",{}).size()>=2

func spawn_domain_error() -> String:
	return "multi-door domain was not built" if uses_spawn_domain() and _spawn_domain==null else (str(_spawn_domain.error) if _spawn_domain!=null else "")

func spawn_route_paths() -> Array:
	return _spawn_domain.paths.duplicate(true) if _spawn_domain!=null else []

func spawn_formation_anchors() -> Array:
	return _spawn_domain.anchors.duplicate(true) if _spawn_domain!=null else []

func is_in_spawn_domain(point: Vector3, radius: float = .34) -> bool:
	# Single-door hostile interpretation is deliberately outside this change.
	return _spawn_domain.contains(point,radius) if _spawn_domain!=null else not uses_spawn_domain()

func _static_segment_clear(start: Vector3, finish: Vector3, radius: float) -> bool:
	var steps := maxi(1,ceili(start.distance_to(finish)/.2))
	for index in range(steps+1):
		if not _contains_static_ground(start.lerp(finish,float(index)/steps),radius): return false
	return true

func find_spawn(anchor: Vector3, player: Vector3, min_distance: float) -> Vector3:
	if uses_spawn_domain():
		var result := Vector3.INF
		var nearest := INF
		for formation: Dictionary in spawn_formation_anchors():
			for candidate: Vector3 in formation.slots:
				var distance := candidate.distance_squared_to(anchor)
				if distance>=nearest or candidate.distance_to(player)<min_distance: continue
				if is_in_spawn_domain(candidate,.4) and contains_ground(candidate,.4) and not path_to(player,candidate,.4).is_empty():
					nearest=distance; result=candidate
		return result
	# Golden-angle order stays deterministic and spreads consecutive group slots.
	for index in range(96):
		var cursor: int = (_spawn_cursor+index) % 96
		var angle: float = float(cursor)*2.39996323
		var radius: float = 1.0+sqrt(float(cursor)/96.0)*5.0
		var candidate: Vector3 = anchor+Vector3(cos(angle),0,sin(angle))*radius
		if candidate.distance_to(player) < min_distance or not contains_ground(candidate,.4) or is_spawn_excluded(candidate,.4):
			continue
		if candidate.distance_to(definition.entry_position) < Catalog.ENTRY_SAFE_RADIUS:
			continue
		var safe: bool = true
		for side in definition.doors:
			if candidate.distance_to(get_door_position(side)+Catalog.door_inward(side)*2.0) < Catalog.ENTRY_SAFE_RADIUS:
				safe = false
		if safe and not path_to(player,candidate).is_empty():
			_spawn_cursor = (cursor+17)%96
			return candidate
	return Vector3.INF

func set_occlusion_target(camera: Camera3D, target: Node3D) -> void:
	_occlusion_camera = camera
	_occlusion_target = target

func set_occlusion_targets(camera: Camera3D, targets: Array[Node3D]) -> void:
	_occlusion_camera = camera
	_occlusion_targets = targets

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_occlusion_camera):
		return
	_occlusion_time += delta
	if _occlusion_time < .12:
		return
	_occlusion_time = 0.0
	for mesh in _cut_meshes:
		if is_instance_valid(mesh):
			mesh.visible = true
	_cut_meshes.clear()
	var targets: Array[Node3D] = _occlusion_targets.duplicate()
	if is_instance_valid(_occlusion_target) and not targets.has(_occlusion_target):
		targets.append(_occlusion_target)
	for actor in get_tree().get_nodes_in_group("full_enemies"):
		if actor is CharacterBody3D and not targets.has(actor):
			targets.append(actor)
	for actor in targets:
		if not is_instance_valid(actor) or not actor.is_inside_tree():
			continue
		var target: Vector3 = actor.global_position+Vector3.UP*.65
		if not _occlusion_camera.is_position_in_frustum(target):
			continue
		var camera_point: Vector3 = target+_occlusion_camera.global_basis.z*30.0
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera_point,target,1)
		var excluded: Array[RID] = []
		for _index in range(8):
			query.exclude = excluded
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var body: CollisionObject3D = hit.collider
			excluded.append(body.get_rid())
			# Imported Blender scenes retain their hierarchy and all mesh parts.
			# Include descendants so pumps/tool heads cannot obscure an actor.
			for child in body.find_children("*","GeometryInstance3D",true,false):
				if child is GeometryInstance3D and child.is_in_group("room_3d_cuttable"):
					child.visible = false
					_cut_meshes.append(child)

func _build_ground() -> void:
	var size: Vector2 = definition.size
	var backdrop: MeshInstance3D = MeshInstance3D.new()
	backdrop.name = "OutsideMeadow"
	var meadow: PlaneMesh = PlaneMesh.new()
	meadow.size = size+Vector2(24,24)
	backdrop.mesh = meadow
	backdrop.position = Vector3(size.x*.5,-.16,size.y*.5)
	backdrop.material_override = _meadow_material()
	add_child(backdrop)
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	add_child(ground)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(_outline)
	for index in range(0,indices.size(),3):
		# Godot front faces use clockwise winding. XZ projects the authored
		# 2D winding correctly already; reversing it makes the floor face down.
		for offset in [0,1,2]:
			var point: Vector2 = _outline[indices[index+offset]]
			surface.set_normal(Vector3.UP)
			# Continuous warm soil, independent of the legacy sprite pipeline.
			surface.set_uv(point/8.0)
			surface.add_vertex(Vector3(point.x,0,point.y))
	var mesh: ArrayMesh = surface.commit()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _ground_material()
	ground.add_child(visual)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	ground.add_child(collision)

func _build_trails() -> void:
	var ground: Node3D = get_node("Ground")
	# Worn paths give the broad crossing a direction without becoming obstacles.
	for route_index in range(definition.main_route.size()-1):
		var a: Vector3 = definition.main_route[route_index]
		var b: Vector3 = definition.main_route[route_index+1]
		var length: float = a.distance_to(b)
		if length < .1:
			continue
		var path_mesh: MeshInstance3D = MeshInstance3D.new()
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(3.1,length)
		path_mesh.mesh = plane
		path_mesh.position = (a+b)*.5+Vector3.UP*.012
		path_mesh.rotation.y = atan2(b.x-a.x,b.z-a.z)
		path_mesh.material_override = _trail_material()
		ground.add_child(path_mesh)
	if str(definition.template_id) == "long_furrows":
		for index in 3:
			var lane := MeshInstance3D.new()
			lane.name = "FurrowLane%d" % index
			var plane := PlaneMesh.new()
			plane.size = Vector2(3.0,definition.size.y*.76)
			lane.mesh = plane
			lane.position = Vector3(definition.size.x*[.09,.51,.92][index],.013,definition.size.y*.5)
			lane.material_override = _trail_material()
			ground.add_child(lane)

func _build_boundary() -> void:
	var walls: Node3D = Node3D.new()
	walls.name = "Boundary"
	add_child(walls)
	for index in range(_outline.size()):
		var a: Vector2 = _outline[index]
		var b: Vector2 = _outline[(index+1)%_outline.size()]
		var door_side: String = ""
		for side in definition.doors:
			var door: Vector3 = get_door_position(side)
			if Geometry2D.get_closest_point_to_segment(Vector2(door.x,door.z),a,b).distance_to(Vector2(door.x,door.z)) < .05:
				door_side = side
				break
		if door_side == "":
			_add_wall(a,b,walls)
		else:
			var door: Vector3 = get_door_position(door_side)
			var center: Vector2 = Vector2(door.x,door.z)
			var tangent: Vector2 = (b-a).normalized()
			var first: Vector2 = center-tangent*Catalog.DOOR_WIDTH*.5
			var second: Vector2 = center+tangent*Catalog.DOOR_WIDTH*.5
			_add_wall(a,first,walls)
			_add_wall(second,b,walls)
			_add_door(door_side,center,tangent,walls)

func _add_wall(a: Vector2, b: Vector2, parent: Node3D) -> void:
	_wall_segments.append([a,b])
	var direction: Vector2 = b-a
	var body: StaticBody3D = _solid_box(parent,Vector3((a.x+b.x)*.5,WALL_HEIGHT*.5,(a.y+b.y)*.5),Vector3(direction.length()+.05,WALL_HEIGHT,WALL_THICKNESS),"boundary",Color(.42,.39,.25))
	body.rotation.y = -direction.angle()
	# A low, always visible plinth remains when the foreground top is cut away.
	_add_box_visual(body,Vector3(0,-WALL_HEIGHT*.5+.19,0),Vector3(direction.length()+.07,.38,WALL_THICKNESS+.07),_material("wall_foot",Color(.39,.34,.23)))
	var top: MeshInstance3D = _add_box_visual(body,Vector3(0,WALL_HEIGHT*.5+.035,0),Vector3(direction.length()+.08,.1,WALL_THICKNESS+.12),_material("wall_cap",Color(.48,.47,.32)))
	top.add_to_group("room_3d_cuttable")

func _add_door(side: String, center: Vector2, tangent: Vector2, parent: Node3D) -> void:
	var size: Vector3 = Vector3(Catalog.DOOR_WIDTH,2.2,WALL_THICKNESS)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Door_"+side
	body.position = Vector3(center.x,1.1,center.y)
	body.rotation.y = -tangent.angle()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var bars: Node3D = Node3D.new()
	body.add_child(bars)
	for offset in [-.6,.2]:
		_add_box_visual(bars,Vector3(0,offset,0),Vector3(Catalog.DOOR_WIDTH,.17,.22),_material("gate_closed",Color(.55,.25,.11)))
	for sign in [-1,1]:
		var pole: Node3D = Node3D.new()
		parent.add_child(pole)
		pole.position = Vector3(center.x+tangent.x*sign*(Catalog.DOOR_WIDTH*.5+.12),0,center.y+tangent.y*sign*(Catalog.DOOR_WIDTH*.5+.12))
		_add_box_visual(pole,Vector3(0,.92,0),Vector3(.25,1.84,.25),_material("gate_post",Color(.30,.25,.15)))
		_add_box_visual(pole,Vector3(0,1.9,0),Vector3(.38,.34,.38),_material("gate_green",Color(.40,.91,.36)))
	_door_bodies[side] = body
	_door_visuals[side] = bars
	var label := Label3D.new()
	label.name = "GateState_"+side
	label.position = Vector3(center.x,2.35,center.y)
	label.font_size = 24
	label.pixel_size = 1.0/80.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5
	label.modulate = Color("eee1b9")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC","Microsoft YaHei","sans-serif"])
	label.font = font
	parent.add_child(label)
	_door_labels[side] = label
	_update_door_labels()

func _build_obstacles() -> void:
	var terrain: Node3D = Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var palette: Dictionary = {"corn":Color("747a38"),"hay":Color("ae864c"),"tree":Color("776640"),"water":Color("496c6b"),"fence":Color("80603c"),"brick":Color("a66e51"),"well":Color("89826a"),"stone":Color("99927b"),"tools":Color("826842")}
	for item in _obstacles:
		if _field_staged_bodies.has(str(item.id)):
			var staged: StaticBody3D = _field_staged_bodies[str(item.id)]
			terrain.add_child(staged)
			_field_staged_bodies.erase(str(item.id))
			continue
		var rectangle: Rect2 = item.rect
		var center: Vector2 = rectangle.get_center()
		var height: float = item.height
		var kind: String = item.kind
		var color: Color = palette.get(kind,Color(.4,.4,.3))
		var body: StaticBody3D = _solid_box(terrain,Vector3(center.x,height*.5,center.y),Vector3(rectangle.size.x,height,rectangle.size.y),kind,color)
		body.name = item.id
		if bool(item.get("field_edge",false)):
			_build_field_edge_art(body,item)
			continue
		var volume: MeshInstance3D = body.get_node("Volume")
		# The planted/raised bed is the visible boundary of the full solid footprint.
		# Actors never walk among decorative stalks or beneath a canopy collider.
		volume.scale.y = .16/height
		volume.position.y = -height*.5+.08
		volume.remove_from_group("room_3d_cuttable")
		volume.material_override = _bed_material(kind)
		if kind == "water":
			volume.scale.y = .004/height
			volume.position.y = -height*.5+.002
		# A dark earth/stone foot visibly owns the collider without a bright tray.
		var foot_height := .004 if kind == "water" else .07
		_add_box_visual(body,Vector3(0,-height*.5+foot_height*.5,0),Vector3(rectangle.size.x+.035,foot_height,rectangle.size.y+.035),_material("soil_rim",Color("51482e")))
		match kind:
			"corn":
				if str(definition.template_id) == "borer_nest":
					_add_fallen_corn_bed(body,rectangle.size,height)
				else:
					_add_asset_grid(body,"corn","CornBatch",rectangle.size,height,.91)
			"hay":
				if str(definition.template_id) in ["mouse_granary","wide_clearing"]:
					_add_farm_props(body,"grain-sack-stack",rectangle.size,height)
				else:
					_add_hay_mounds(body,rectangle.size,height)
			"tree":
				_add_asset_grid(body,"tree","TreeBatch",rectangle.size,height,4.5)
				_add_asset_grid(body,"grass","TreeGrassBatch",rectangle.size,.32,.7)
			"stone":
				_add_asset_grid(body,"rocks","StoneBatch",rectangle.size,height,1.0)
			"tools":
				_add_farm_props(body,"farm-tool-bundle",rectangle.size,height)
			"fence":
				_add_fence_rows(body,rectangle.size,height)
			"water":
				_add_water(body,rectangle.size,height)
			"well":
				_add_farm_props(body,"farm-well",rectangle.size,height)
				if str(definition.template_id) == "pump_corner":
					_add_pump_dressing(body,rectangle.size,height)
			_:
				_add_ruined_wall(body,rectangle.size,height)
		if kind != "water":
			_add_edge_tufts(body,rectangle.size,height,kind)

func _add_farm_props(body: Node3D, asset: String, size: Vector2, height: float) -> void:
	# Preserve full exported scenes, not just their first mesh. Each island keeps
	# its authored collision and a visible raised boundary; props fit inside it.
	if not _farm_scenes.has(asset):
		_farm_scenes[asset] = load(FARM_ASSET_PATH+asset+".glb")
	var scene: PackedScene = _farm_scenes[asset]
	if scene == null:
		return
	var columns: int = 1 if asset == "farm-well" else clampi(floori(size.x/2.6),1,4)
	var rows: int = 1 if asset == "farm-well" else clampi(floori(size.y/2.0),1,maxi(1,floori(4.0/columns)))
	var cell: Vector2 = size/Vector2(columns,rows)
	for row in range(rows):
		for column in range(columns):
			var model: Node3D = scene.instantiate()
			var anchor := Node3D.new()
			anchor.name = "BlenderProp_%d_%d" % [row,column]
			anchor.set_meta("asset_id",asset)
			body.add_child(anchor)
			anchor.add_child(model)
			var bounds := AABB()
			var found := false
			var meshes: Array[Node] = model.find_children("*","MeshInstance3D",true,false)
			if model is MeshInstance3D:
				meshes.push_front(model)
			for mesh in meshes:
				# Local transforms work even when a room is built before entering
				# the SceneTree; no global-transform queries are required.
				var local: Transform3D = mesh.transform
				var ancestor: Node = mesh.get_parent()
				while ancestor != anchor:
					if ancestor is Node3D:
						local = ancestor.transform*local
					ancestor = ancestor.get_parent()
				var box: AABB = local*mesh.get_aabb()
				bounds = bounds.merge(box) if found else box
				found = true
				mesh.add_to_group("room_3d_cuttable")
			if not found or bounds.size.y < .001:
				anchor.queue_free()
				continue
			var ratio: float = minf((height-.18)/bounds.size.y,minf(cell.x*.90/bounds.size.x,cell.y*.90/bounds.size.z))
			anchor.scale = Vector3.ONE*ratio
			anchor.position = Vector3((column+.5)*cell.x-size.x*.5,-body.position.y+.17,(row+.5)*cell.y-size.y*.5)-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*ratio

func _asset_mesh(asset: String) -> Mesh:
	if _asset_meshes.has(asset):
		return _asset_meshes[asset]
	var scene: PackedScene = load("res://assets/environment/"+asset+".glb")
	if scene == null:
		return null
	var instance: Node3D = scene.instantiate()
	var meshes: Array[Node] = instance.find_children("*","MeshInstance3D",true,false)
	if instance is MeshInstance3D:
		meshes.push_front(instance)
	if meshes.is_empty():
		instance.free()
		return null
	var result: Mesh = meshes[0].mesh.duplicate()
	# Imported palette is normalized under the unchanged warm gameplay sun.
	# Keep the three authored corn materials distinct instead of flat overrides.
	if asset in ["corn","grass","haystack"]:
		for surface in result.get_surface_count():
			var source: Material = result.surface_get_material(surface)
			if source is StandardMaterial3D:
				var mat: StandardMaterial3D = source.duplicate()
				mat.albedo_color *= .66 if asset == "haystack" else .72
				mat.albedo_color.a = 1.0
				mat.roughness = 1.0
				result.surface_set_material(surface,mat)
		if asset == "haystack":
			result.surface_set_material(0,_hay_material())
	_asset_meshes[asset] = result
	instance.free()
	return result

func _add_batch(parent: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index,transforms[index])
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = multimesh
	# Explicit bounds avoid renderer-dependent readback and ensure whole plots
	# remain visible when their origins are offscreen.
	if not transforms.is_empty():
		var bounds: AABB = transforms[0]*mesh.get_aabb()
		for index in range(1,transforms.size()):
			bounds = bounds.merge(transforms[index]*mesh.get_aabb())
		visual.custom_aabb = bounds
	visual.add_to_group("room_3d_cuttable")
	parent.add_child(visual)
	return visual

func _add_asset_grid(body: Node3D, asset: String, label: String, size: Vector2, height: float, spacing: float) -> void:
	var mesh: Mesh = _asset_mesh(asset)
	if mesh == null:
		return
	var bounds: AABB = mesh.get_aabb()
	var columns: int = maxi(1,floori(size.x/spacing))
	var rows: int = maxi(1,floori(size.y/spacing))
	var cell: Vector2 = size/Vector2(columns,rows)
	# Uniform scale preserves each real model; the cell fit keeps leaves inside
	# the authored footprint instead of hiding actors in an adjacent aisle.
	var scale_factor: float = minf((height-.17)/bounds.size.y,minf(cell.x*.90/bounds.size.x,cell.y*.90/bounds.size.z))
	var transforms: Array[Transform3D] = []
	var ground: float = -float(body.position.y)+.17
	for row in range(rows):
		for column in range(columns):
			var variation: float = .78+.055*float((row*7+column*3)%5)
			var scale_value: float = scale_factor*variation
			var location: Vector3 = Vector3((column+.5)*cell.x-size.x*.5,ground-bounds.position.y*scale_value,(row+.5)*cell.y-size.y*.5)
			location -= Vector3(bounds.get_center().x,0,bounds.get_center().z)*scale_value
			var basis: Basis = Basis(Vector3.UP,float((row*11+column*7)%9-4)*.055).scaled(Vector3.ONE*scale_value)
			transforms.append(Transform3D(basis,location))
	_add_batch(body,label,mesh,transforms)

func _add_fence_rows(body: Node3D, size: Vector2, height: float) -> void:
	var mesh: Mesh = _asset_mesh("fence")
	if mesh == null:
		return
	var along_x: bool = size.x >= size.y
	var span: float = size.x if along_x else size.y
	var thickness: float = size.y if along_x else size.x
	var count: int = maxi(1,ceili(span/2.0))
	var transforms: Array[Transform3D] = []
	for index in range(count):
		var basis: Basis = Basis(Vector3.UP,0 if along_x else PI*.5)*Basis.from_scale(Vector3(span/count/2.13,height/1.11,minf(1.0,thickness/.13)))
		var offset: float = (index+.5)*span/count-span*.5
		var at: Vector3 = Vector3(offset if along_x else 0,-height*.5,0 if along_x else offset)
		transforms.append(Transform3D(basis,at))
	_add_batch(body,"FenceBatch",mesh,transforms)

func _add_bricks(body: Node3D, size: Vector2, height: float) -> void:
	var columns: int = maxi(1,ceili(size.x/1.0))
	var rows: int = maxi(1,ceili(height/.34))
	var layers: int = maxi(1,ceili(size.y/.75))
	var brick: BoxMesh = BoxMesh.new()
	brick.size = Vector3(size.x/columns-.025,height/rows-.025,size.y/layers-.025)
	brick.material = _material("brick_units",Color("a77556"))
	var transforms: Array[Transform3D] = []
	for y in range(rows):
		for z in range(layers):
			for x in range(columns):
				# Internal cells are unseen; leave only the shell and top course.
				if y < rows-1 and x > 0 and x < columns-1 and z > 0 and z < layers-1:
					continue
				var at: Vector3 = Vector3((x+.5)*size.x/columns-size.x*.5,(y+.5)*height/rows-height*.5,(z+.5)*size.y/layers-size.y*.5)
				transforms.append(Transform3D(Basis.IDENTITY,at))
	_add_batch(body,"BrickBatch",brick,transforms)

func _add_water(body: Node3D, size: Vector2, height: float) -> void:
	# Dark quiet water sits below rough masonry. High-contrast checker waves
	# previously read like a raised swimming pool at the normal gameplay camera.
	var water := PlaneMesh.new()
	water.size = size-Vector2(.16,.16)
	var visual := MeshInstance3D.new()
	visual.name = "WaterSurface"
	visual.mesh = water
	visual.position.y = -height*.5+.009
	visual.material_override = _water_material()
	body.add_child(visual)
	var bank_width := .29
	for sign_value in [-1,1]:
		_module_line(body,"shallow-irrigation-bank",Vector3(sign_value*(size.x*.5-bank_width*.5),-height*.5+.006,0),size.y,bank_width,.12,PI*.5,"CanalLongBank")
		_module_line(body,"shallow-irrigation-bank",Vector3(0,-height*.5+.006,sign_value*(size.y*.5-bank_width*.5)),size.x-bank_width*2.0,bank_width,.12,0,"CanalEndBank")

func _water_material() -> ShaderMaterial:
	if _materials.has("quiet_canal_water"):
		return _materials.quiet_canal_water
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    float broad=sin(world_pos.z*1.9+world_pos.x*.4+TIME*.30);
    float ripple=sin(world_pos.z*10.0+world_pos.x*2.5+TIME*.8)*.012;
    ALBEDO=vec3(.095,.19,.165)+broad*.012+ripple;
    ROUGHNESS=.64;
    METALLIC=.02;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_materials.quiet_canal_water = mat
	return mat

func _add_well(body: Node3D, size: Vector2, height: float) -> void:
	var radius: float = minf(size.x,size.y)*.42
	var blocks: BoxMesh = BoxMesh.new()
	blocks.size = Vector3(radius*.47,height/3.0-.018,.3)
	blocks.material = _material("well_stone",Color("aca387"))
	var transforms: Array[Transform3D] = []
	for row in range(3):
		for index in range(12):
			var angle: float = (index+row*.5)*TAU/12.0
			transforms.append(Transform3D(Basis(Vector3.UP,PI*.5-angle),Vector3(cos(angle)*radius,(row+.5)*height/3.0-height*.5,sin(angle)*radius)))
	_add_batch(body,"WellRingBatch",blocks,transforms)
	var dark: CylinderMesh = CylinderMesh.new()
	dark.top_radius = radius
	dark.bottom_radius = radius
	dark.height = .02
	var pool: MeshInstance3D = MeshInstance3D.new()
	pool.mesh = dark
	pool.position.y = -height*.5+.1
	pool.material_override = _material("well_inside",Color("354344"))
	body.add_child(pool)

func _solid_box(parent: Node3D, at: Vector3, size: Vector3, kind: String, color: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var visual: MeshInstance3D = _add_box_visual(body,Vector3.ZERO,size,_material(kind,color))
	visual.name = "Volume"
	visual.add_to_group("room_3d_cuttable")
	_occludable.append(visual)
	return body

func _add_box_visual(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	parent.add_child(visual)
	return visual

func _material(key: String, color: Color, texture_path: String = "", uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_scale = uv_scale
	if texture_path != "" and ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
	_materials[key] = material
	return material

func _ground_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float soil_noise(vec2 p) {
    vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
    float macro=soil_noise(UV*1.7)*.065+soil_noise(UV*6.0)*.023;
    float grain=soil_noise(UV*113.0)*.018;
    float furrow=pow(max(0.0,sin(UV.y*23.0+soil_noise(UV*2.0)*1.4)),14.0)*.012;
    ALBEDO=vec3(.355,.285,.182)+macro+grain-furrow;
    ROUGHNESS=.97;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _trail_material() -> ShaderMaterial:
	if _materials.has("soft_trail"):
		return _materials.soft_trail
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
void fragment() {
    float edge=smoothstep(0.0,.23,UV.x)*smoothstep(0.0,.23,1.0-UV.x);
    edge*=smoothstep(0.0,.11,UV.y)*smoothstep(0.0,.11,1.0-UV.y);
    float tire=exp(-pow((UV.x-.3)*45.0,2.0))+exp(-pow((UV.x-.7)*45.0,2.0));
    ALBEDO=vec3(.41,.32,.202)-tire*.10;
    ALPHA=edge*.27;
    ROUGHNESS=1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_materials.soft_trail = material
	return material

func _meadow_material() -> StandardMaterial3D:
	return _material("meadow",Color("677647"))

func field_edge_report() -> Dictionary:
	return _field_edge_report.duplicate(true)

func _apply_field_edges() -> void:
	var started := Time.get_ticks_usec()
	var is_parcel: bool = field_parcels_enabled and FieldParcels.applies(definition)
	_field_edge_report = FieldParcels.propose(self,_field_retained_state) if is_parcel else FieldEdges.propose(self)
	_field_edge_report.proposal_usec = Time.get_ticks_usec()-started
	_field_validation = _field_edge_report.duplicate(true) if is_parcel and _field_edge_report.status == "accepted" else {}
	if _field_edge_report.status != "accepted":
		_refresh_navigation_region()
		return
	_field_base_obstacles = _obstacles.duplicate(true)
	_field_edges.assign(_field_edge_report.obstacles)
	_field_edge_report.erase("obstacles")
	var original_count := _obstacles.size()
	var retained: Array[Vector3] = []
	if is_parcel:
		for point: Vector3 in _field_validation.static_points: retained.append(point)
		for hidden: String in ["static_points","props","approaches","drops","room_state"]: _field_edge_report.erase(hidden)
	else:
		retained.assign([definition.service_position,definition.reward_position])
		for prop: Dictionary in definition.get("breakables",[]): retained.append(prop.position)
		var frozen_route: PackedVector3Array = definition.main_route
		for index in range(1,frozen_route.size()-1):
			for offset: Vector3 in [Vector3(2.1,0,1.4),Vector3(-2.1,0,-1.4)]:
				var at: Vector3 = frozen_route[index]+offset
				if contains_ground(at,.6): retained.append(at)
	_obstacles.append_array(_field_edges)
	# Live final clearance must agree with every frozen permission slot.
	var reason := ""
	for anchor: Dictionary in spawn_formation_anchors():
		if _field_edges_touch(anchor.point,anchor.point,.34): reason = "frozen anchor no longer legal"; break
		for point: Vector3 in anchor.slots:
			if _field_edges_touch(point,point,.34): reason = "frozen slot no longer legal"; break
		if not reason.is_empty(): break
	if not reason.is_empty():
		_obstacles.resize(original_count)
		_field_edges.clear(); _field_base_obstacles.clear(); _field_validation.clear()
		_field_edge_report = FieldParcels.rejected(FieldParcels.key_for(definition),reason) if is_parcel else FieldEdges.rejected(reason)
		_refresh_navigation_region()
		return
	# Filter the frozen regular graph once. No new edges are invented and no
	# spawn path or anchor is recomputed from the reduced movement graph.
	var rejected_ids: Dictionary = {}
	var rejected_edges: Dictionary = {}
	# Only cells touching a new expanded footprint can change. Edges from
	# the one-cell halo are tested too, including diagonal corner crossings.
	for item: Dictionary in _field_edges:
		var grown: Rect2 = Rect2(item.rect).grow(NAV_RADIUS)
		var first := Vector2i(floori(grown.position.x/NAV_STEP-.5)-1,floori(grown.position.y/NAV_STEP-.5)-1)
		var last := Vector2i(ceili(grown.end.x/NAV_STEP-.5)+1,ceili(grown.end.y/NAV_STEP-.5)+1)
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var cell := Vector2i(x,z)
				if not _cells.has(cell): continue
				var id: int = _cells[cell]
				var p: Vector3 = navigation.get_point_position(id)
				var a := Vector2(p.x,p.z)
				if grown.has_point(a): rejected_ids[id] = true; continue
				for other: int in navigation.get_point_connections(id):
					var q: Vector3 = navigation.get_point_position(other)
					if FieldEdges.segment_intersects_rect(a,Vector2(q.x,q.z),grown):
						rejected_edges[Vector2i(mini(id,other),maxi(id,other))] = true
	for id: int in rejected_ids: navigation.remove_point(id)
	for cell: Vector2i in _cells.keys():
		if not navigation.has_point(_cells[cell]): _cells.erase(cell)
	for edge: Vector2i in rejected_edges:
		if navigation.has_point(edge.x) and navigation.has_point(edge.y) and navigation.are_points_connected(edge.x,edge.y):
			navigation.disconnect_points(edge.x,edge.y)
	var reached: Dictionary = {}
	var pending: Array[int] = [navigation.get_closest_point(definition.entry_position)]
	while not pending.is_empty():
		var id: int = pending.pop_back()
		if id < 0 or reached.has(id): continue
		reached[id] = true
		for other: int in navigation.get_point_connections(id): pending.append(other)
	for cell: Vector2i in _cells.keys():
		var id: int = _cells[cell]
		if not reached.has(id): navigation.remove_point(id); _cells.erase(cell)
	_index_field_edges()
	var retained_check_started := Time.get_ticks_usec()
	_field_edge_report.fast_endpoint_witnesses = 0
	_field_edge_report.slow_endpoint_witnesses = 0
	# Every remaining graph vertex belongs to the entry component. A clear
	# endpoint-to-vertex edge proves reachability without seven full searches.
	for anchor: Vector3 in retained:
		var radius: float = float(_field_validation.static_points.get(anchor,.65)) if is_parcel else .6
		var connected: bool = _field_static_endpoint_connected(anchor,radius) if is_parcel else (_contains_static_ground(anchor,radius) and _nearest_reachable_node(anchor,radius)>=0)
		if not connected:
			# No field body/art or native region has been created yet. Restore
			# the complete baseline graph atomically and keep the frozen domain.
			_obstacles.resize(original_count)
			_field_edges.clear(); _field_edge_grid.clear(); _field_base_obstacles.clear(); _field_validation.clear()
			_field_edge_report = FieldParcels.rejected(FieldParcels.key_for(definition),"retained static destination disconnected: "+str(anchor)) if is_parcel else FieldEdges.rejected("retained anchor disconnected: "+str(anchor))
			_build_navigation()
			return
	_field_edge_report.retained_points_usec = Time.get_ticks_usec()-retained_check_started
	_field_edge_report.movement_nodes = navigation.get_point_count()
	_field_edge_report.new_boxes = _field_edges.size()
	_field_edge_report.corn_instances = 0
	_field_edge_report.fence_modules = 0
	_field_edge_report.source_triangles = 0
	for item: Dictionary in _field_edges:
		if item.kind == "corn": _field_edge_report.source_triangles += 12
	_field_edge_report.batches = []
	_field_edge_report.asset_bounds = []
	if is_parcel:
		var content_error := _field_validate_content_access(true)
		if not content_error.is_empty():
			_rollback_field_bundle(content_error)
			return
		var art_error := _stage_field_art()
		if not art_error.is_empty():
			_rollback_field_bundle(art_error)
			return
	dynamic_obstacle_revision += 1
	_field_edge_report.status = "enabled"
	_field_edge_report.static_validation_and_filter_usec = Time.get_ticks_usec()-started
	started = Time.get_ticks_usec()
	_refresh_navigation_region()
	_field_edge_report.final_region_usec = Time.get_ticks_usec()-started

func _field_static_endpoint_connected(point: Vector3, radius: float) -> bool:
	# All retained graph nodes already belong to the one entry component. The
	# nearest grid centre is only a witness, not a claim about shortest paths.
	# Keep the original complete query as the fallback for narrow old geometry.
	var cell := Vector2i(roundi(point.x/NAV_STEP-.5),roundi(point.z/NAV_STEP-.5))
	if _cells.has(cell):
		var id: int = _cells[cell]
		var target: Vector3 = navigation.get_point_position(id)
		if not navigation.is_point_disabled(id) and not _field_edges_touch(point,target,radius) and _static_segment_clear(point,target,radius):
			_field_edge_report.fast_endpoint_witnesses += 1
			return true
	_field_edge_report.slow_endpoint_witnesses += 1
	return _nearest_reachable_node(point,radius)>=0

func _field_validate_content_access(simulate_props: bool) -> String:
	if _field_validation.is_empty(): return ""
	var saved_revision := dynamic_obstacle_revision
	var simulated_ids: Array[String] = []
	var state: Dictionary = _field_validation.room_state
	for prop: Dictionary in _field_validation.props:
		var id := "%s_prop_%d"%[definition.id,int(prop.index)]
		if state.get("broken",{}).has(id): continue
		if simulate_props:
			register_dynamic_obstacle(id,prop.position,float(prop.radius))
			simulated_ids.append(id)
		elif not _dynamic_obstacles.has(id) or not Vector3(_dynamic_obstacles[id].position).is_equal_approx(prop.position) or absf(float(_dynamic_obstacles[id].radius)-float(prop.radius))>.0001:
			return "actual retained prop registration changed"
	var reason := ""
	for point: Vector3 in _field_validation.approaches:
		if not contains_ground(point,.3) or path_to(definition.entry_position,point,.3).is_empty():
			reason = "retained interaction/reward approach disconnected"; break
	if reason.is_empty():
		for point: Vector3 in _field_validation.drops:
			if not contains_ground(point,.22) or path_to(definition.entry_position,point,.22).is_empty():
				reason = "retained drop collection position disconnected"; break
	for id: String in simulated_ids: remove_dynamic_obstacle(id)
	dynamic_obstacle_revision = saved_revision
	return reason

func validate_field_prop_candidates(candidates: Array) -> bool:
	if _field_validation.is_empty() or _field_edge_report.status != "enabled": return true
	var expected: Array = _field_validation.props
	if mini(5,candidates.size()) != expected.size():
		_rollback_field_bundle("actual Game prop count changed after geometry")
		return false
	for index in expected.size():
		if Vector3(candidates[index]).distance_to(expected[index].position)>.0001:
			_rollback_field_bundle("actual Game prop position changed after geometry")
			return false
	return true

func validate_field_spawned_content() -> bool:
	if _field_validation.is_empty() or _field_edge_report.status != "enabled": return true
	var reason := _field_validate_content_access(false)
	if reason.is_empty(): return true
	_rollback_field_bundle(reason)
	return false

func _stage_field_art() -> String:
	var staging := Node3D.new()
	var reason := ""
	for item: Dictionary in _field_edges:
		var rect: Rect2 = item.rect
		var height: float = item.height
		var center := rect.get_center()
		var mesh: Mesh = _asset_mesh(str(item.kind))
		if mesh == null:
			reason = "accepted field asset missing"; break
		var body := _solid_box(staging,Vector3(center.x,height*.5,center.y),Vector3(rect.size.x,height,rect.size.y),str(item.kind),Color("747a38"))
		body.name = item.id
		_build_field_edge_art(body,item)
		staging.remove_child(body)
		_field_staged_bodies[str(item.id)] = body
	staging.free()
	if not reason.is_empty(): return reason
	if int(_field_edge_report.corn_instances)>96 or int(_field_edge_report.fence_modules)>125 or int(_field_edge_report.source_triangles)>120000:
		return "actual staged source inventory exceeds budget"
	var corn_batches := 0
	var fence_batches := 0
	for batch: Dictionary in _field_edge_report.batches:
		if maxf(batch.size.x,batch.size.z)>6.0001 or int(batch.count)>16: return "actual staged spatial batch exceeds budget"
		if str(batch.owner).begins_with("field_parcel_fence_"): fence_batches += 1
		else: corn_batches += 1
	if corn_batches>8 or fence_batches>45: return "actual staged batch count exceeds budget"
	for bound: Dictionary in _field_edge_report.asset_bounds:
		var owner: Dictionary = {}
		for item: Dictionary in _field_edges:
			if str(item.id)==str(bound.owner): owner=item; break
		if owner.is_empty(): return "staged asset has no physical owner"
		var footprint := Rect2(Vector2(bound.position.x,bound.position.z),Vector2(bound.size.x,bound.size.z))
		if not Rect2(owner.rect).grow(.00001).encloses(footprint): return "transformed asset exceeds admitted physical footprint"
		if bound.position.y<-.00001 or bound.position.y+bound.size.y>float(owner.height)+.00001: return "transformed asset root/top exceeds admitted height"
	_field_edge_report.corn_batches = corn_batches
	_field_edge_report.fence_batches = fence_batches
	return ""

func _rollback_field_bundle(reason: String) -> void:
	var key := FieldParcels.key_for(definition)
	for item: Dictionary in _field_edges:
		var body := get_node_or_null("Terrain/"+str(item.id))
		if body != null:
			body.get_parent().remove_child(body)
			body.free()
	for body: Node in _field_staged_bodies.values():
		if is_instance_valid(body): body.free()
	_field_staged_bodies.clear()
	for index in range(_cut_meshes.size()-1,-1,-1):
		if not is_instance_valid(_cut_meshes[index]): _cut_meshes.remove_at(index)
	for index in range(_occludable.size()-1,-1,-1):
		if not is_instance_valid(_occludable[index]): _occludable.remove_at(index)
	_obstacles = _field_base_obstacles.duplicate(true)
	_field_edges.clear(); _field_edge_grid.clear(); _field_base_obstacles.clear()
	_field_validation.clear()
	_field_edge_report = FieldParcels.rejected(key,reason)
	# Restore the original static graph exactly, then apply the existing live
	# dynamic registrations as baseline Game would. Spawn domain stays frozen.
	var dynamic := _dynamic_obstacles.duplicate(true)
	_dynamic_obstacles.clear()
	_build_navigation()
	_dynamic_obstacles = dynamic
	for obstacle: Dictionary in dynamic.values(): _refresh_dynamic_cells(obstacle.position,float(obstacle.radius))
	# Domain permissions stay frozen; live geometry consumers must revalidate.
	dynamic_obstacle_revision += 1

func _index_field_edges() -> void:
	_field_edge_grid.clear()
	for item: Dictionary in _field_edges:
		var rect: Rect2 = item.rect
		var first := Vector2i(floori(rect.position.x/FIELD_EDGE_CELL),floori(rect.position.y/FIELD_EDGE_CELL))
		var last := Vector2i(floori(rect.end.x/FIELD_EDGE_CELL),floori(rect.end.y/FIELD_EDGE_CELL))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var cell := Vector2i(x,z)
				if not _field_edge_grid.has(cell): _field_edge_grid[cell] = []
				_field_edge_grid[cell].append(rect)

func _field_edges_touch(a: Vector3, b: Vector3, radius: float) -> bool:
	var start := Vector2(a.x,a.z)
	var finish := Vector2(b.x,b.z)
	for item: Dictionary in _field_edges:
		var grown: Rect2 = Rect2(item.rect).grow(radius)
		if start == finish:
			if grown.has_point(start): return true
		elif FieldEdges.segment_intersects_rect(start,finish,grown): return true
	return false

func _build_field_edge_art(body: StaticBody3D, item: Dictionary) -> void:
	var rect: Rect2 = item.rect
	var height: float = item.height
	var volume: MeshInstance3D = body.get_node("Volume")
	if item.kind == "corn":
		volume.scale.y = .16/height
		volume.position.y = -height*.5+.08
		volume.remove_from_group("room_3d_cuttable")
		volume.material_override = _bed_material("corn")
	else:
		# Accepted fence posts already meet the ground; an extra dirt strip
		# adds no boundary information and otherwise costs a draw per segment.
		_occludable.erase(volume)
		body.remove_child(volume)
		volume.free()
	var mesh: Mesh = _asset_mesh(str(item.kind))
	if mesh == null: return
	var bounds: AABB = mesh.get_aabb()
	var batches: Dictionary = {}
	if item.kind == "corn":
		var columns := int(item.get("columns",int(item.corn_count)/2 if item.row_axis == "z" else floori(rect.size.x)))
		var rows := int(item.get("rows",2 if item.row_axis == "z" else int(item.corn_count)/columns))
		if item.row_axis == "z":
			rows = columns; columns = 2
		var cell := rect.size/Vector2(columns,rows)
		var batch_columns := 1
		var batch_rows := 1
		var best_batches := columns*rows
		for candidate_columns in range(1,mini(columns,floori(6.0/cell.x))+1):
			for candidate_rows in range(1,mini(rows,floori(6.0/cell.y))+1):
				if candidate_columns*candidate_rows > 16: continue
				var count := ceili(float(columns)/candidate_columns)*ceili(float(rows)/candidate_rows)
				if count < best_batches or (count == best_batches and candidate_columns*candidate_rows > batch_columns*batch_rows):
					best_batches = count; batch_columns = candidate_columns; batch_rows = candidate_rows
		for row in rows:
			for column in columns:
				var yaw := float((row*11+column*7)%9-4)*.03
				var rotation := Basis(Vector3.UP,yaw)
				var rotated: AABB = Transform3D(rotation,Vector3.ZERO)*bounds
				var scale_value := minf(.6512631341,minf((1.65-.17)/bounds.size.y,minf(cell.x*.94/rotated.size.x,cell.y*.94/rotated.size.z)))
				scale_value *= .96+.01*float((row*7+column*3)%5)
				var basis := rotation.scaled(Vector3.ONE*scale_value)
				var at := Vector3((column+.5)*cell.x-rect.size.x*.5,-height*.5+.17,(row+.5)*cell.y-rect.size.y*.5)
				at -= basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
				var transform := Transform3D(basis,at)
				# Fill each spatial run without exceeding six metres or sixteen plants.
				var key := Vector2i(column/batch_columns,row/batch_rows)
				if not batches.has(key): batches[key] = []
				batches[key].append(transform)
				_field_edge_report.corn_instances += 1
				_field_edge_report.source_triangles += 844
	else:
		var along_x := rect.size.x > rect.size.y
		for piece: Dictionary in FieldEdges.visible_fence_modules(rect,definition.obstacles,bool(item.get("field_full_span",false))):
			var basis := Basis(Vector3.UP,0 if along_x else PI*.5)*Basis.from_scale(Vector3(float(piece.length)/bounds.size.x,height/bounds.size.y,.18/bounds.size.z))
			var offset: float = piece.offset
			var at := Vector3(offset if along_x else 0,-height*.5,0 if along_x else offset)
			at -= basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			var transform := Transform3D(basis,at)
			var key: Vector2i = piece.batch
			if not batches.has(key): batches[key] = []
			batches[key].append(transform)
			_field_edge_report.fence_modules += 1
			_field_edge_report.source_triangles += 152
	for key in batches:
		var transforms: Array[Transform3D] = []
		transforms.assign(batches[key])
		var visual := _add_batch(body,"FieldBatch_"+str(key),mesh,transforms)
		var world_bounds: AABB = body.transform*visual.custom_aabb
		_field_edge_report.batches.append({"owner":item.id,"count":transforms.size(),"size":world_bounds.size,"position":world_bounds.position})
		for transform: Transform3D in transforms:
			var actual: AABB = body.transform*transform*bounds
			_field_edge_report.asset_bounds.append({"owner":item.id,"position":actual.position,"size":actual.size})

func _build_navigation(install_region: bool = true) -> void:
	navigation = AStar3D.new()
	_cells.clear()
	walkable_area = 0.0
	var size: Vector2 = definition.size
	var columns: int = ceili(size.x/NAV_STEP)
	var rows: int = ceili(size.y/NAV_STEP)
	for z in range(rows):
		for x in range(columns):
			var point: Vector3 = Vector3((x+.5)*NAV_STEP,0,(z+.5)*NAV_STEP)
			if not contains_ground(point,NAV_RADIUS):
				continue
			var id: int = z*columns+x
			_cells[Vector2i(x,z)] = id
			navigation.add_point(id,point)
	for cell in _cells:
		for offset in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i(1,1),Vector2i(-1,1)]:
			if not _cells.has(cell+offset):
				continue
			var a: int = _cells[cell]
			var b: int = _cells[cell+offset]
			if segment_clear(navigation.get_point_position(a),navigation.get_point_position(b),NAV_RADIUS):
				navigation.connect_points(a,b)
	if install_region:
		_refresh_navigation_region()

func _refresh_navigation_region() -> void:
	if is_instance_valid(navigation_region):
		remove_child(navigation_region)
		navigation_region.free()
		navigation_region = null
	walkable_area = 0.0
	# Keep only entry-reachable cells when calculating area and baking polygons.
	var entry_id: int = navigation.get_closest_point(definition.entry_position)
	var reachable: Dictionary = {}
	var pending: Array[int] = []
	if entry_id>=0: pending.append(entry_id)
	while not pending.is_empty():
		var id: int = pending.pop_back()
		if reachable.has(id):
			continue
		reachable[id] = true
		for neighbor in navigation.get_point_connections(id):
			pending.append(neighbor)
	var vertices: PackedVector3Array = PackedVector3Array()
	var vertex_ids: Dictionary = {}
	var polygons: Array[PackedInt32Array] = []
	for cell in _cells:
		var quad: Array[Vector2i] = [cell,cell+Vector2i.DOWN,cell+Vector2i(1,1),cell+Vector2i.RIGHT]
		var good: bool = true
		for corner in quad:
			if not _cells.has(corner) or not reachable.has(_cells[corner]):
				good = false
		if not good:
			continue
		# Extra clearance bounds each square, including concave wall corners.
		var center: Vector3 = navigation.get_point_position(_cells[cell])+Vector3(NAV_STEP*.5,0,NAV_STEP*.5)
		if not contains_ground(center,NAV_RADIUS+NAV_STEP*.7072):
			var bridge_points := PackedVector3Array()
			for corner: Vector2i in quad: bridge_points.append(navigation.get_point_position(_cells[corner]))
			if not _bridge_quad_clear(bridge_points): continue
		var polygon: PackedInt32Array = PackedInt32Array()
		for corner in quad:
			if not vertex_ids.has(corner):
				vertex_ids[corner] = vertices.size()
				vertices.append(navigation.get_point_position(_cells[corner]))
			polygon.append(vertex_ids[corner])
		polygons.append(polygon)
		walkable_area += NAV_STEP*NAV_STEP
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.agent_radius = NAV_RADIUS
	mesh.agent_height = 1.3
	mesh.vertices = vertices
	for polygon in polygons:
		mesh.add_polygon(polygon)
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "NavigationRegion3D"
	navigation_region.navigation_mesh = mesh
	add_child(navigation_region)

func _bridge_quad_clear(points: PackedVector3Array) -> bool:
	# The legacy centre-circle gate overestimates an axis-aligned cell's
	# half-width by .186m. The exception stays wholly inside a real bridge deck
	# plus its existing2m approach reserve,
	# with exact complete-quad obstacle and edge-capsule clearance at NAV_RADIUS.
	if points.size()!=4: return false
	var bridge_zones: Array = definition.get("presentation",{}).get("bridge_zones",[])
	if bridge_zones.is_empty(): return false
	var first := Vector2(points[0].x,points[0].z)
	var footprint := Rect2(first,Vector2.ZERO)
	for point: Vector3 in points:
		if not point.is_finite(): return false
		footprint = footprint.expand(Vector2(point.x,point.z))
	var authored_bridge := false
	for bridge: Rect2 in bridge_zones:
		if bridge.grow(2.0).encloses(footprint): authored_bridge = true; break
	if not authored_bridge: return false
	for point: Vector3 in points:
		if not _contains_static_ground(point,NAV_RADIUS): return false
	# A rebuilt region may have live props. Test the full quad interior against
	# the exact registered circle expanded by the unchanged actor radius.
	for obstacle: Dictionary in _dynamic_obstacles.values():
		var at: Vector3 = obstacle.position
		if FieldEdges.point_rect_distance(Vector2(at.x,at.z),footprint)<NAV_RADIUS+float(obstacle.radius): return false
	# Check the entire quad, not only endpoints, against every full static solid.
	for obstacle: Dictionary in _obstacles:
		if footprint.intersects(Rect2(obstacle.rect).grow(NAV_RADIUS)): return false
	for i in 4:
		var a := Vector2(points[i].x,points[i].z)
		var b := Vector2(points[(i+1)%4].x,points[(i+1)%4].z)
		for wall: Array in _wall_segments:
			var c: Vector2 = wall[0]
			var d: Vector2 = wall[1]
			if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return false
			var distance := minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d)))
			distance = minf(distance,c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)))
			distance = minf(distance,d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b)))
			if distance<NAV_RADIUS+WALL_THICKNESS*.5: return false
	return true

func _nearest_reachable_node(point: Vector3, actor_radius: float = NAV_RADIUS) -> int:
	var cell: Vector2i = Vector2i(roundi(point.x/NAV_STEP-.5),roundi(point.z/NAV_STEP-.5))
	var nearest: int = -1
	var distance: float = INF
	for dz in range(-2,3):
		for dx in range(-2,3):
			var candidate: Vector2i = cell+Vector2i(dx,dz)
			if not _cells.has(candidate):
				continue
			var id: int = _cells[candidate]
			if navigation.is_point_disabled(id):
				continue
			var candidate_point: Vector3 = navigation.get_point_position(id)
			var candidate_distance: float = point.distance_squared_to(candidate_point)
			if candidate_distance < distance and segment_clear(point,candidate_point,actor_radius):
				nearest = id
				distance = candidate_distance
	return nearest

func _closest_legal_goal(point: Vector3, actor_radius: float) -> Vector3:
	var cell: Vector2i = Vector2i(roundi(point.x/NAV_STEP-.5),roundi(point.z/NAV_STEP-.5))
	var result: Vector3 = Vector3.INF
	var nearest_distance: float = INF
	for dz in range(-3,4):
		for dx in range(-3,4):
			var candidate: Vector2i = cell+Vector2i(dx,dz)
			if not _cells.has(candidate) or navigation.is_point_disabled(_cells[candidate]):
				continue
			var location: Vector3 = navigation.get_point_position(_cells[candidate])
			var distance: float = location.distance_squared_to(point)
			if distance < nearest_distance and contains_ground(location,actor_radius) and segment_clear(point,location,Catalog.PLAYER_RADIUS):
				result = location
				nearest_distance = distance
	return result

func _normalize_room_anchors() -> void:
	var authored: PackedVector3Array = definition.main_route
	var route: PackedVector3Array = PackedVector3Array([definition.entry_position])
	for index in range(1,authored.size()):
		var target: Vector3 = authored[index]
		if not contains_ground(target,NAV_RADIUS):
			var closest: int = navigation.get_closest_point(target)
			if closest < 0:
				continue
			target = navigation.get_point_position(closest)
		var path: PackedVector3Array = path_to(route[-1],target)
		for point in path:
			if point.distance_squared_to(route[-1]) > .01:
				route.append(point)
	definition.main_route = route
	for key in ["service_position","reward_position"]:
		var anchor: Vector3 = definition.get(key,route[-1])
		if not contains_ground(anchor,.6) or path_to(route[0],anchor).is_empty():
			definition[key] = route[mini(1,route.size()-1)]

func _smooth_path(start: Vector3, input: PackedVector3Array, actor_radius: float = NAV_RADIUS) -> PackedVector3Array:
	var output: PackedVector3Array = PackedVector3Array()
	var cursor: int = 0
	var previous: Vector3 = start
	while cursor < input.size():
		var furthest: int = cursor
		for candidate in range(cursor+1,input.size()):
			if segment_clear(previous,input[candidate],actor_radius):
				furthest = candidate
		output.append(input[furthest])
		previous = input[furthest]
		cursor = furthest+1
	return output

func set_route_unlocked(value: bool) -> void:
	_route_unlocked = value
	_update_door_labels()

func set_exit_labels(value: Dictionary) -> void:
	_exit_labels = value.duplicate()
	_update_door_labels()

static func exit_labels_for(dungeon: Dictionary, room_id: String) -> Dictionary:
	# Presentation only. Validate the tree instead of guessing from optional_N
	# names, arrival direction, room rewards, or undisclosed destination titles.
	var rooms: Dictionary = dungeon.get("rooms",{})
	var main: Array = dungeon.get("main_path",[])
	var links: Array = dungeon.get("links",[])
	if not rooms.has(room_id) or main.size()<2 or links.size()!=rooms.size()-1:
		return {}
	if main[0]!=dungeon.get("entry","") or main[-1]!=dungeon.get("exit",""):
		return {}
	var adjacency: Dictionary = {}
	for id: String in rooms:
		adjacency[id] = []
	for link in links:
		if not link is Array or link.size()!=2:
			return {}
		if not rooms.has(link[0]) or not rooms.has(link[1]) or link[0]==link[1]:
			return {}
		if adjacency[link[0]].has(link[1]):
			return {}
		adjacency[link[0]].append(link[1])
		adjacency[link[1]].append(link[0])
	for id: String in rooms:
		var doors: Dictionary = rooms[id].get("doors",{})
		if doors.size()!=adjacency[id].size():
			return {}
		for neighbor: String in adjacency[id]:
			if not doors.values().has(neighbor):
				return {}
	var distance: Dictionary = {}
	var queue: Array = []
	for index in main.size():
		var id: String = main[index]
		if not rooms.has(id) or distance.has(id):
			return {}
		if index>0 and not adjacency[main[index-1]].has(id):
			return {}
		distance[id] = 0
		queue.append(id)
	# A connected n-1-edge graph is a tree, so each optional room has exactly
	# one route back. Multi-source distance distinguishes each branch depth.
	var cursor := 0
	while cursor<queue.size():
		var id: String = queue[cursor]
		cursor += 1
		for neighbor: String in adjacency[id]:
			if not distance.has(neighbor):
				distance[neighbor] = int(distance[id])+1
				queue.append(neighbor)
	if distance.size()!=rooms.size():
		return {}
	var result: Dictionary = {}
	var source_index := main.find(room_id)
	for side: String in rooms[room_id].doors:
		var target: String = rooms[room_id].doors[side]
		var target_index := main.find(target)
		if source_index>=0 and target_index>=0:
			result[side] = "主路前进" if target_index==source_index+1 else "原路返回"
		elif target_index>=0:
			result[side] = "返回主路"
		else:
			result[side] = "原路返回" if int(distance[target])<int(distance[room_id]) else "支路探索"
	return result

func _update_door_labels() -> void:
	for side: String in _door_labels:
		var label: Label3D = _door_labels[side]
		# Physical gates stay within this node; the existing HUD owns N / next
		# node selection. An unlock must never hide a locked gate or its role.
		label.text = "› "+str(_exit_labels.get(side,"通行")) if doors_open else "× 清场后开启"
		label.modulate = (Color("eed088") if _route_unlocked else Color("d1e1ab")) if doors_open else Color("ecd3b5")

func is_spawn_excluded(point: Vector3,radius: float = .34) -> bool:
	for zone: Rect2 in definition.get("presentation",{}).get("bridge_zones",[]):
		if zone.grow(radius+.2).has_point(Vector2(point.x,point.z)):
			return true
	return false

func _build_field_details() -> void:
	var details := Node3D.new()
	details.name = "FieldDetails"
	add_child(details)
	var info: Dictionary = definition.get("presentation",{})
	_add_ground_litter(details)
	_add_ground_contacts(details)
	if str(definition.template_id) == "borer_nest":
		_add_nest_churn(details)
	for zone: Rect2 in info.get("bridge_zones",[]):
		var center := zone.get_center()
		var deck := Node3D.new()
		deck.name = "PassableCanalBridge%d" % details.get_child_count()
		deck.position = Vector3(center.x,.002,center.y)
		details.add_child(deck)
		for index in 8:
			_add_box_visual(deck,Vector3(0,.008,(index+.5)*zone.size.y/8.0-zone.size.y*.5),Vector3(zone.size.x,.016,zone.size.y/8.0-.023),_material("bridge_planks",Color("705b39")))
		for sign_value in [-1,1]:
			_add_box_visual(deck,Vector3(0,.008,sign_value*(zone.size.y*.5-.1)),Vector3(zone.size.x+.06,.016,.12),_material("bridge_end",Color("62533b")))
	# Low furrow rims and sparse edge tufts remain inside authored obstacles.
	# Field-edge art already supplies its exact bounded soil foot.
	for item in _obstacles:
		if bool(item.get("field_edge",false)): continue
		var rect: Rect2 = item.rect
		if item.kind=="corn" and str(definition.template_id) != "borer_nest":
			var rows := maxi(1,int(rect.size.y/.6))
			for row in rows:
				var at := Vector3(rect.get_center().x,.18,rect.position.y+(row+.5)*rect.size.y/rows)
				_add_box_visual(details,at,Vector3(rect.size.x*.97,.035,.065),_material("furrow_ridge",Color("6f5c3c")))
		elif item.kind=="hay":
			for index in 5:
				var at := Vector3(rect.position.x+(index+.5)*rect.size.x/5.0,.182,rect.position.y+.12)
				var straw := _add_box_visual(details,at,Vector3(.32,.014,.035),_material("loose_straw",Color("b49a60")))
				straw.rotation.y = float(index)*1.7
	if bool(info.get("key_room",false)):
		# Original painted wayfinding at the entry: a soft chevron, no collider.
		var at: Vector3 = definition.entry_position
		var route: PackedVector3Array = definition.main_route
		if route.size()>1:
			var forward := (route[1]-route[0]).normalized()
			var side := forward.cross(Vector3.UP)
			for sign_value in [-1,1]:
				var start: Vector3 = at+forward*.8+side*.3*sign_value
				var end := at+forward*1.2
				var line := _add_box_visual(details,(start+end)*.5+Vector3.UP*.025,Vector3(.055,.008,start.distance_to(end)),_material("painted_waymark",Color("b4a273")))
				line.rotation.y = atan2(end.x-start.x,end.z-start.z)


func _bed_material(kind: String) -> ShaderMaterial:
	var key := "bed_"+kind
	if _materials.has(key):
		return _materials[key]
	var colors := {"corn":Vector3(.235,.225,.125),"hay":Vector3(.31,.26,.15),"well":Vector3(.33,.32,.255),"water":Vector3(.12,.17,.145),"brick":Vector3(.285,.225,.155),"stone":Vector3(.32,.30,.225)}
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec3 soil_color;
varying vec3 at;
void vertex(){at=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
    float fleck=hash(floor(at.xz*17.0));
    float patch=sin(at.x*2.1+sin(at.z*.8))*sin(at.z*1.3)*.017;
    ALBEDO=soil_color+patch+fleck*.025;
    ROUGHNESS=1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var color: Vector3 = Vector3(.275,.24,.145) if kind == "corn" and str(definition.template_id) == "borer_nest" else colors.get(kind,Vector3(.265,.255,.17))
	mat.set_shader_parameter("soil_color",color)
	_materials[key] = mat
	return mat

func _sprint_mesh(asset: String) -> Mesh:
	var key := "sprint_"+asset
	if _asset_meshes.has(key):
		return _asset_meshes[key]
	# Only assets accepted in docs/qa/sprint-10h/assets.json are called here.
	var packed: PackedScene = load(SPRINT_ASSET_PATH+asset+".glb")
	if packed == null:
		return null
	var model := packed.instantiate()
	var nodes := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:
		nodes.push_front(model)
	var mesh: Mesh = nodes[0].mesh.duplicate() if not nodes.is_empty() else null
	if mesh != null and (asset.begins_with("shallow-irrigation-bank") or asset.begins_with("fallen-corn-stalk")):
		for surface in mesh.get_surface_count():
			var source: Material = mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				material.albedo_color *= .60 if asset.begins_with("shallow") else .73
				material.albedo_color.a = 1.0
				material.roughness = 1.0
				mesh.surface_set_material(surface,material)
	model.free()
	_asset_meshes[key] = mesh
	return mesh

func _module_line(parent: Node3D, asset: String, at: Vector3, length: float, width: float, height: float, yaw: float, label: String) -> void:
	var mesh := _sprint_mesh(asset)
	if mesh == null or length < .05:
		return
	var box := mesh.get_aabb()
	var count := maxi(1,ceili(length/2.7))
	var step := length/count
	var rotation := Basis(Vector3.UP,yaw)
	var scale_value := Vector3(step*.997/box.size.x,height/box.size.y,width/box.size.z)
	var transforms: Array[Transform3D] = []
	for index in count:
		var basis := rotation*Basis.from_scale(scale_value)
		var origin := at+rotation*Vector3((index+.5)*step-length*.5,0,0)-basis*Vector3(box.get_center().x,box.position.y,box.get_center().z)
		transforms.append(Transform3D(basis,origin))
	var batch := _add_batch(parent,label,mesh,transforms)
	batch.set_meta("asset_id",asset)

func _add_ruined_wall(body: Node3D, size: Vector2, height: float) -> void:
	var along_x := size.x >= size.y
	var length := size.x if along_x else size.y
	var depth := size.y if along_x else size.x
	var yaw := 0.0 if along_x else PI*.5
	_module_line(body,"broken-red-brick-wall",Vector3(0,-height*.5+.17,0),length*.985,minf(depth*.82,.85),height-.17,yaw,"BrokenWallBatch")
	# A few low fallen bricks ground the ruined wall inside its solid footprint.
	var rubble := BoxMesh.new()
	rubble.size = Vector3(.32,.12,.19)
	rubble.material = _material("brick_rubble",Color("72503b"))
	var pieces: Array[Transform3D] = []
	var count := maxi(3,int(length/.9))
	for sign_value in [-1,1]:
		for index in count:
			var location := Vector3((index+.5)*length/count-length*.5,-height*.5+.24,sign_value*depth*.35)
			if not along_x:
				location = Vector3(location.z,location.y,location.x)
			var basis := Basis(Vector3.UP,float(index%5)*.47)
			pieces.append(Transform3D(basis,location))
	_add_batch(body,"FallenBrickBatch",rubble,pieces)

func _add_hay_mounds(body: Node3D, size: Vector2, height: float) -> void:
	var mesh := _asset_mesh("haystack")
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var columns := clampi(ceili(size.x/3.8),1,3)
	var rows := clampi(ceili(size.y/3.2),1,2)
	var cell := size/Vector2(columns,rows)
	var transforms: Array[Transform3D] = []
	for row in rows:
		for column in columns:
			var variation := .84+.08*float((row+column)%3)
			var scale_value := Vector3(cell.x*.91/box.size.x,(height-.17)*variation/box.size.y,cell.y*.89/box.size.z)
			var basis := Basis.from_scale(scale_value)
			var at := Vector3((column+.5)*cell.x-size.x*.5,-height*.5+.17,(row+.5)*cell.y-size.y*.5)-basis*Vector3(box.get_center().x,box.position.y,box.get_center().z)
			transforms.append(Transform3D(basis,at))
	_add_batch(body,"HayBatch",mesh,transforms)

func _add_edge_tufts(body: Node3D, size: Vector2, height: float, kind: String) -> void:
	var mesh := _asset_mesh("grass")
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var transforms: Array[Transform3D] = []
	var step := .65 if kind == "corn" else 1.2
	for side in 4:
		var span := size.x if side < 2 else size.y
		var count := maxi(1,int(span/step))
		for index in count:
			if (index+side*3)%5 == 0:
				continue
			var t := (index+.5)*span/count-span*.5
			var at := Vector3(t,0,(-1 if side == 0 else 1)*(size.y*.5-.22)) if side < 2 else Vector3((-1 if side == 2 else 1)*(size.x*.5-.22),0,t)
			var scale_value := .28+.045*float(index%4)
			var basis := Basis(Vector3.UP,float(index)*1.7).scaled(Vector3.ONE*scale_value)
			at.y = -height*.5+.17-box.position.y*scale_value
			transforms.append(Transform3D(basis,at))
	_add_batch(body,"EdgeGrassBatch",mesh,transforms)

func _add_ground_litter(parent: Node3D) -> void:
	# Flat original husks and grit sit below danger decals. They never add a
	# collider, hide feet, or consume navigable space in the broad combat lanes.
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(str(definition.template_id).hash())
	var blade := SurfaceTool.new()
	blade.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[Vector3(-.04,0,-.30),Vector3(.065,0,.08),Vector3(0,0,.30)],[Vector3(-.04,0,-.30),Vector3(.065,0,.08),Vector3(-.075,0,.02)]]:
		for vertex: Vector3 in triangle:
			blade.set_normal(Vector3.UP)
			blade.add_vertex(vertex)
	var mesh := blade.commit()
	mesh.surface_set_material(0,_material("ground_husks",Color("695637")))
	var transforms: Array[Transform3D] = []
	var size: Vector2 = definition.size
	for z in range(2,int(size.y)-2,2):
		for x in range(2,int(size.x)-2,2):
			var center := Vector3(x+rng.randf_range(-.85,.85),0,z+rng.randf_range(-.85,.85))
			if not contains_ground(center,.6) or is_spawn_excluded(center,.5):
				continue
			var near_crop := false
			for obstacle in _obstacles:
				var rect: Rect2 = obstacle.rect
				if rect.grow(2.2).has_point(Vector2(center.x,center.z)):
					near_crop = true
					break
			if not near_crop and rng.randf() < .7:
				continue
			for index in rng.randi_range(2,4):
				var point := center+Vector3(rng.randf_range(-.4,.4),.011,rng.randf_range(-.4,.4))
				var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.20,.46))
				transforms.append(Transform3D(basis,point))
	var litter := _add_batch(parent,"GroundLitter",mesh,transforms)
	litter.remove_from_group("room_3d_cuttable")
	litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_pump_dressing(body: Node3D, size: Vector2, height: float) -> void:
	_add_farm_prop_at(body,"farm-tool-bundle","PumpToolRack",Vector3(-size.x*.30,-height*.5+.17,0),Vector3(size.x*.24,height-.22,size.y*.66))
	_add_farm_prop_at(body,"grain-sack-stack","PumpSupplies",Vector3(size.x*.31,-height*.5+.17,-size.y*.13),Vector3(size.x*.23,height*.63,size.y*.43))
	var coil := TorusMesh.new()
	coil.inner_radius = .27
	coil.outer_radius = .35
	coil.rings = 16
	coil.ring_segments = 6
	var hose := MeshInstance3D.new()
	hose.name = "CoiledPumpHose"
	hose.mesh = coil
	hose.scale.y = .35
	hose.position = Vector3(size.x*.26,-height*.5+.20,size.y*.27)
	hose.material_override = _material("pump_hose",Color("3f4434"))
	hose.add_to_group("room_3d_cuttable")
	body.add_child(hose)

func _add_farm_prop_at(parent: Node3D, asset: String, label: String, at: Vector3, fit: Vector3) -> void:
	if not _farm_scenes.has(asset):
		_farm_scenes[asset] = load(FARM_ASSET_PATH+asset+".glb")
	var packed: PackedScene = _farm_scenes[asset]
	if packed == null:
		return
	var model: Node3D = packed.instantiate()
	var holder := Node3D.new()
	holder.name = label
	holder.set_meta("asset_id",asset)
	parent.add_child(holder)
	holder.add_child(model)
	var bounds := AABB()
	var found := false
	var nodes := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:
		nodes.push_front(model)
	for mesh: MeshInstance3D in nodes:
		var transform := mesh.transform
		var ancestor := mesh.get_parent()
		while ancestor != holder:
			if ancestor is Node3D:
				transform = ancestor.transform*transform
			ancestor = ancestor.get_parent()
		var box: AABB = transform*mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
		mesh.add_to_group("room_3d_cuttable")
	if not found:
		holder.queue_free()
		return
	var ratio := minf(fit.x/bounds.size.x,minf(fit.y/bounds.size.y,fit.z/bounds.size.z))
	holder.scale = Vector3.ONE*ratio
	holder.position = at-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*ratio

func _add_ground_contacts(parent: Node3D) -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec3 tint=vec3(.23,.205,.135);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
    vec2 edge=min(UV,1.0-UV);
    float grain=hash(floor(UV*130.0));
    float fade=smoothstep(0.0,.13,min(edge.x,edge.y)+grain*.02);
    ALBEDO=tint;
    ALPHA=fade*.18;
    ROUGHNESS=1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for item in _obstacles:
		if bool(item.get("field_edge",false)): continue
		var rect: Rect2 = item.rect
		var visual := MeshInstance3D.new()
		visual.name = "GroundContact_"+str(item.id)
		var plane := PlaneMesh.new()
		plane.size = rect.size+Vector2(1.7,1.7)
		visual.mesh = plane
		visual.position = Vector3(rect.get_center().x,.006,rect.get_center().y)
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(visual)


func _add_fallen_corn_bed(body: Node3D, size: Vector2, height: float) -> void:
	var asset := "fallen-corn-stalk-cluster"
	var mesh := _sprint_mesh(asset)
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var along_x := size.x >= size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(str(body.name).hash())+73
	var count := maxi(3,int(size.x*size.y/1.4))
	var transforms: Array[Transform3D] = []
	for index in count:
		var yaw := (0.0 if along_x else PI*.5)+rng.randf_range(-.78,.78)
		var ratio := rng.randf_range(.68,.96)
		var basis := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*ratio)
		var rotated_box: AABB = Transform3D(basis,Vector3.ZERO)*box
		var margin := Vector2(rotated_box.size.x,rotated_box.size.z)*.5+Vector2(.04,.04)
		var center := Vector3(rng.randf_range(-size.x*.5+margin.x,size.x*.5-margin.x),-height*.5+.17,rng.randf_range(-size.y*.5+margin.y,size.y*.5-margin.y))
		var at := center-Vector3(rotated_box.get_center().x,rotated_box.position.y,rotated_box.get_center().z)
		transforms.append(Transform3D(basis,at))
	var batch := _add_batch(body,"CornBatch",mesh,transforms)
	batch.set_meta("asset_id",asset)

func _add_nest_churn(parent: Node3D) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(22,19)
	var churn := MeshInstance3D.new()
	churn.name = "NestChurn"
	churn.mesh = mesh
	churn.position = Vector3(definition.size.x*.5,.014,definition.size.y*.51)
	churn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
    float radius=length((UV-.5)*2.0);
    float clods=noise(UV*38.0)*.4+noise(UV*7.0)*.6;
    float fade=1.0-smoothstep(.48,.93,radius+clods*.22);
    ALBEDO=vec3(.235,.225,.155)+clods*.065;
    ALPHA=fade*(.10+clods*.20);
    ROUGHNESS=1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	churn.material_override = mat
	parent.add_child(churn)


func _hay_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 local_pos;
void vertex(){local_pos=VERTEX;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
    float fibers=sin(local_pos.y*145.0+sin(local_pos.x*36.0)*.65+sin(local_pos.z*40.0)*.65);
    float weather=hash(floor(local_pos.xz*70.0));
    ALBEDO=vec3(.43,.335,.172)+fibers*.012+weather*.012;
    ROUGHNESS=1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
