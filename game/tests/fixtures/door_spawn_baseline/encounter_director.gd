extends Node3D
## One room budget, including reserved warnings. All actors, hostile projectiles
## and ground warnings are descendants of this pauseable director.
## Density ruling (2026-09-29): each segment starts with 8/10/12 enemies; its
## remaining budget is split into 2+ enemy refills spaced at most 2L along the
## actual route, including the tail. Only an unusually long route can add the
## minimum extra pairs required for coverage; metrics report that supplement
## inside planned/max_budget. The room cap and fixed coin budget never increase.

signal encounter_error(reason: String)
signal cleared
signal enemy_defeated(position: Vector3, reward: int)
signal boss_status(info: Dictionary)
signal feedback_requested(kind: String,payload: Dictionary)

const ProjectileBatch = preload("res://scripts/cornfield/projectile_batch.gd")
const Recipe = preload("res://scripts/cornfield/encounter_recipe.gd")
const Enemy = preload("res://scripts/cornfield/field_enemy.gd")
const SPAWN_WARNING := 0.8
const PLAYER_DIAMETER := 0.6
const ROUTE_COVERAGE_UNIT := 3.5 # Source encounter spacing unit; target has no dash.
const MIN_SPAWN_DISTANCE := 5.25 # max(6D, 1.5L)
const ENTRY_CLEARANCE := 3.5
const GROUP_SPACING := 0.78 # >= 1.2D
const MIN_GROUP_SPACING := 1.2*PLAYER_DIAMETER
const MAX_PROJECTILES := ProjectileBatch.CAPACITY
const MAX_ATTACK_WARNINGS := 30

var world: Node3D
var player: Node3D
var definition: Dictionary = {}
var floor_number := 1
var cap := 12
var group_size := 8
var segments: Array[Dictionary] = []
var enemies: Array = []
var _warnings: Array[Dictionary] = []
var _route := PackedVector3Array()
var _route_length := 0.0
var _max_progress := 0.0
var _stopped := true
var _complete := false
var _boss_room := false
var _elite_assigned := false
var _spawned := 0
var _defeated := 0
var _elite_spawned := 0
var _peak_alive := 0
var _rng := RandomNumberGenerator.new()
var _failed_segments: Array[String] = []
var _projectiles: Array = []
var _projectile_batch:MultiMeshInstance3D
var _attack_warnings: Array = []
var _reward_budget := 6
var _reward_paid := 0
var _force_queue := false
var _density_supplement := 0
var _content_error := ""

func _process(_delta:float) -> void:
	if is_instance_valid(_projectile_batch):
		if _stopped or _complete:_projectile_batch.clear()
		else:_projectile_batch.sync_projectiles(_projectiles)

func configure(room_world: Node3D, target: Node3D, room_definition: Dictionary, stage: int) -> void:
	shutdown()
	world = room_world
	player = target
	definition = room_definition.duplicate(true)
	floor_number = clampi(stage,1,3)
	cap = [12,16,20][floor_number-1]
	group_size = [8,10,12][floor_number-1]
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_stopped = false
	_complete = false
	_spawned = 0
	_defeated = 0
	_elite_spawned = 0
	_reward_paid = 0
	_force_queue = false
	_density_supplement = 0
	_content_error = ""
	_peak_alive = 0
	_max_progress = 0.0
	_elite_assigned = false
	_failed_segments.clear()
	segments.clear()
	_rng.seed = hash(str(definition.get("seed",0))+":"+str(definition.get("id",0))+":"+str(stage))
	_route = PackedVector3Array(definition.get("main_route",PackedVector3Array()))
	if _route.size() < 2:
		var size: Vector2 = definition.get("size",Vector2(40,30))
		_route = PackedVector3Array([player.global_position,Vector3(size.x*0.7,0,size.y*0.5)])
	_route_length = 0.0
	for index in range(1,_route.size()):
		_route_length += _route[index-1].distance_to(_route[index])
	var kind := str(definition.get("kind","combat")).to_lower()
	var encounter := str(definition.get("encounter",kind)).to_lower()
	_boss_room = kind == "boss" or encounter == "boss" or (floor_number == 3 and bool(definition.get("completion",false)))
	var safe := encounter in ["none","safe","service","entry","shop","event","exit","corridor","entrance","treasure"]
	_reward_budget = 12 if _boss_room else (8 if bool(definition.get("elite",false)) else 6)+2*(floor_number-1)
	if safe and not _boss_room:
		_complete = true
		world.set_doors_open(true)
		return
	world.set_doors_open(false)
	var count := 1 if _boss_room else (3 if _route_length >= 30.0 else 2)
	var budget: int = 1 if _boss_room else ([16,20,24][floor_number-1] if count == 3 else [12,16,20][floor_number-1])
	for index in range(count):
		var start := _route_length*float(index)/float(count)
		var finish := _route_length*float(index+1)/float(count)
		var groups: Array[Dictionary] = []
		groups.append({"progress":start,"count":1 if _boss_room else group_size,"spawned":0,"reserved":0,"first":true})
		var actual_budget := budget
		if not _boss_room:
			var final_segment := index == count-1
			var coverage_end := maxf(start,_route_length-2.0*ROUTE_COVERAGE_UNIT) if final_segment else finish
			var span := coverage_end-start
			var intervals := maxi(1,ceili(span/(2.0*ROUTE_COVERAGE_UNIT)))
			var refill_count := maxi(1,intervals if final_segment else intervals-1)
			var remaining := budget-group_size
			var supplement := maxi(0,refill_count*2-remaining)
			remaining += supplement
			actual_budget += supplement
			_density_supplement += supplement
			# Enough groups to avoid exceeding the floor's group-size ceiling too.
			refill_count = maxi(refill_count,ceili(float(remaining)/float(group_size)))
			for refill in range(refill_count):
				var amount := remaining/refill_count+(1 if refill < remaining%refill_count else 0)
				var denominator := float(refill_count if final_segment else refill_count+1)
				var progress := start+span*float(refill+1)/denominator
				groups.append({"progress":progress,"count":amount,"spawned":0,"reserved":0,"first":false})
		if int(definition.get("content_revision",2))>=3 and not _boss_room:
			for group_index in groups.size():
				var group: Dictionary = groups[group_index]
				var intro := floor_number==1 and bool(definition.get("elite",false)) and index==0 and group_index==0
				group.roster = Recipe.roster(definition,floor_number,index,group_index,int(group.count),intro)
				group.elite_slot = 0 if bool(definition.get("elite",false)) and index==0 and group_index==0 else -1
				if group.roster.size()!=int(group.count):
					_fail_content("田块 %s 的敌群配方无效（段 %d / 组 %d）。"%[str(definition.get("id","?")),index,group_index])
					return
		segments.append({"id":str(definition.get("id",0))+":segment:"+str(index),
			"start":start,"end":finish,"groups":groups,
			"budget":actual_budget,"spawned":0,"reserved":0,"activations":0,"first_group":false,"failed_time":0.0})

func _fail_content(reason: String) -> void:
	if not _content_error.is_empty():
		return
	_content_error = reason
	_stopped = true
	encounter_error.emit(reason)

func _physics_process(delta: float) -> void:
	if _stopped or _complete or not is_instance_valid(player) or not is_instance_valid(world):
		return
	_max_progress = maxf(_max_progress,_project_progress(player.global_position))
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		# Projection of the swept forward progress also covers movement past a band.
		if float(segment.start) <= _max_progress+0.1:
			_activate(segment)
	# A path can double back over an earlier segment after obstacle routing.
	# Reaching its authored endpoint is authoritative even when nearest-point
	# projection aliases the outward segment. Still spawn/defeat the full budget.
	var reached_endpoint := _max_progress>ENTRY_CLEARANCE and _ground_distance(player.global_position,_route[-1])<=1.4
	if _max_progress >= _route_length-3.5 or reached_endpoint:
		request_exit_check()
	_tick_spawn_warnings(delta)
	if alive_count() <= cap/2:
		var index := _next_segment()
		if index >= 0:
			_queue_group(index,delta)
	_peak_alive = maxi(_peak_alive,alive_count())
	_check_clear()

func alive_count() -> int:
	var count := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			count += 1
	for warning in _warnings:
		count += warning.records.size()
	return count

func is_complete() -> bool:
	return _complete

func request_exit_check() -> void:
	if _stopped or _complete:
		return
	_force_queue = true
	for segment in segments:
		_activate(segment)

func shutdown() -> void:
	_stopped = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	enemies.clear()
	_warnings.clear()
	_projectiles.clear()
	_projectile_batch=null
	_attack_warnings.clear()
	for segment in segments:
		segment.reserved = 0
		for group in segment.groups:
			group.reserved = 0

func metrics() -> Dictionary:
	var planned := 0
	var reserved := 0
	for segment in segments:
		planned += int(segment.budget)
		reserved += int(segment.reserved)
	return {"planned":planned,"max_budget":planned,"base_budget":planned-_density_supplement,"density_supplement":_density_supplement,"spawned":_spawned,"defeated":_defeated,"reserved":reserved,
		"alive_including_warnings":alive_count(),"peak_alive":_peak_alive,"cap":cap,"elite_spawned":_elite_spawned,
		"reward_budget":_reward_budget,"reward_paid":_reward_paid,
		"content_error":_content_error,"spawn_failure_segments":_failed_segments.duplicate(),"segments":segments.duplicate(true)}

func group_schedule() -> Array[Dictionary]:
	var schedule: Array[Dictionary] = []
	for segment in segments:
		for group in segment.groups:
			var row: Dictionary = group.duplicate()
			row.segment_id = segment.id
			schedule.append(row)
	return schedule

func _activate(segment: Dictionary) -> void:
	if int(segment.activations) == 0:
		segment.activations = 1

func _next_segment() -> int:
	var fallback := -1
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		if int(segment.activations) == 0 or int(segment.spawned)+int(segment.reserved) >= int(segment.budget):
			continue
		if _next_group(segment) < 0:
			continue
		if not bool(segment.first_group):
			return index
		if fallback < 0:
			fallback = index
	return fallback

func _next_group(segment: Dictionary) -> int:
	for index in range(segment.groups.size()):
		var group: Dictionary = segment.groups[index]
		if int(group.spawned)+int(group.reserved) >= int(group.count):
			continue
		if not _force_queue and _max_progress+0.1 < float(group.progress):
			return -1
		# Never turn a promised 8/10/12 opening into a handful through cap truncation.
		if cap-alive_count() < int(group.count)-int(group.spawned)-int(group.reserved):
			return -1
		return index
	return -1

func _queue_group(index: int, delta: float) -> void:
	var segment: Dictionary = segments[index]
	var group_index := _next_group(segment)
	if group_index < 0:
		return
	var group: Dictionary = segment.groups[group_index]
	var count := int(group.count)-int(group.spawned)-int(group.reserved)
	if count <= 0:
		return
	var records := _find_group(count,index,group_index)
	if records.size() != count:
		segment.failed_time = float(segment.failed_time)+delta
		if float(segment.failed_time) >= 3.0 and not str(segment.id) in _failed_segments:
			_failed_segments.append(str(segment.id))
			push_warning("3D encounter template spawn blocked for 3 seconds: "+str(segment.id))
		return
	segment.failed_time = 0.0
	segment.first_group = true
	group.reserved = int(group.reserved)+count
	segment.reserved = int(segment.reserved)+count
	var marks: Array = []
	for record in records:
		var mark := ground_disc(0.4 if record.species != "boss_borer" else 0.8,Color(1.0,0.64,0.12,0.7))
		add_child(mark)
		mark.global_position = record.point+Vector3.UP*0.025
		marks.append(mark)
	_warnings.append({"segment":index,"group":group_index,"remaining":SPAWN_WARNING,"records":records,"marks":marks})

func _find_group(count: int, segment_index: int, group_index: int = 0) -> Array[Dictionary]:
	var forward := _point_on_route(minf(_route_length,_max_progress+MIN_SPAWN_DISTANCE+2.0))-player.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.25:
		forward = player.global_position-_point_on_route(maxf(0.0,_max_progress-4.0))
		forward.y = 0.0
	if forward.length_squared() < 0.25:
		forward = Vector3.RIGHT
	forward = forward.normalized()
	var records: Array[Dictionary] = []
	var special_count := count/4
	var authored := int(definition.get("content_revision",2))>=3 and not _boss_room
	var group: Dictionary = segments[segment_index].groups[group_index] if authored else {}
	var headings: Array[Vector3] = [forward,forward.rotated(Vector3.UP,PI*0.5),forward.rotated(Vector3.UP,-PI*0.5)]
	# A player who swept all the way to the exit still owes earlier budgets. Use
	# a visible adjacent approach, or the cleared approach after the first group.
	if _spawned > 0:
		headings.append(-forward)
	for heading in headings:
		records.clear()
		var side := heading.cross(Vector3.UP)
		var center: Vector3 = player.global_position+heading*(MIN_SPAWN_DISTANCE+2.4)
		for row in range(5):
			for column in range(5):
				var offset := Vector2(float(column-2),float(row-2))*GROUP_SPACING
				if offset.length() > ROUTE_COVERAGE_UNIT*0.75:
					continue
				var candidate: Vector3 = center+side*offset.x+heading*offset.y
				var id := "boss_borer" if _boss_room else ("mouse" if (records.size()+_spawned)%2 == 0 else "rooster")
				if not _boss_room and records.size() < special_count:
					id = ["beetle","locust","snail","corn_borer"][(segment_index+_spawned/group_size+records.size())%4]
				if authored:
					id = str(group.roster[int(group.spawned)+records.size()])
				var radius := 0.65 if _boss_room else 0.34
				var point := candidate
				if not _spawn_valid(point,radius):
					point = world.find_spawn(candidate,player.global_position,MIN_SPAWN_DISTANCE)
				if not point.is_finite() or _ground_distance(point,center) > ROUTE_COVERAGE_UNIT*0.75 or (point-player.global_position).dot(heading) < 1.0 or not _spawn_valid(point,radius):
					continue
				var separated := true
				for other in records:
					# Placement grid spacing is not a second safety requirement:
					# float roundoff at 0.78 must not delete half a valid dense grid.
					if _ground_distance(other.point,point)+0.00001 < MIN_GROUP_SPACING:
						separated = false
						break
				if not separated:
					continue
				var is_elite: bool = int(group.elite_slot)==int(group.spawned)+records.size() if authored else (bool(definition.get("elite",false)) and not _elite_assigned and records.is_empty() and not _boss_room)
				records.append({"point":point,"species":id,"elite":is_elite})
				if records.size() == count:
					if not _retreat_sector_open(records):
						break
					if records[0].elite and not authored:
						_elite_assigned = true
					return records
	return []

func _retreat_sector_open(records: Array[Dictionary]) -> bool:
	var angles: Array[float] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			var relative: Vector3 = enemy.global_position-player.global_position
			angles.append(atan2(relative.z,relative.x))
	for warning in _warnings:
		for record in warning.records:
			var relative: Vector3 = record.point-player.global_position
			angles.append(atan2(relative.z,relative.x))
	for record in records:
		var relative: Vector3 = record.point-player.global_position
		angles.append(atan2(relative.z,relative.x))
	angles.sort()
	var largest := 0.0
	for index in range(angles.size()):
		var next: float = angles[(index+1)%angles.size()]+(TAU if index == angles.size()-1 else 0.0)
		largest = maxf(largest,next-angles[index])
	# At the 5.25u minimum radius a 90-degree gap is wider than L=3.5u.
	return largest >= PI*0.5

func _spawn_valid(point: Vector3, radius: float) -> bool:
	if not world.contains_ground(point,radius) or (world.has_method("is_spawn_excluded") and world.is_spawn_excluded(point,radius)) or _ground_distance(point,player.global_position) < MIN_SPAWN_DISTANCE:
		return false
	var entry: Vector3 = definition.get("entry_position",_route[0])
	if _ground_distance(point,entry) < ENTRY_CLEARANCE:
		return false
	for side in definition.get("doors",{}):
		if _ground_distance(point,world.get_door_position(str(side))) < ENTRY_CLEARANCE:
			return false
	var route: PackedVector3Array = world.path_to(point,player.global_position,radius)
	if route.is_empty() or not _warning_visible(point):
		return false
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(radius*2.0,1.15)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*(shape.height*0.5+0.04))
	query.collision_mask = 1 | 4
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _warning_visible(point: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	if camera.is_position_behind(point) or not get_viewport().get_visible_rect().grow(-16).has_point(camera.unproject_position(point)):
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,point+Vector3.UP*0.08,1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _tick_spawn_warnings(delta: float) -> void:
	for index in range(_warnings.size()-1,-1,-1):
		var warning: Dictionary = _warnings[index]
		warning.remaining = float(warning.remaining)-delta
		if float(warning.remaining) > 0.000001:
			continue
		var valid := true
		for record in warning.records:
			if not _spawn_valid(record.point,0.65 if record.species == "boss_borer" else 0.34):
				valid = false
				break
		var segment: Dictionary = segments[int(warning.segment)]
		var group: Dictionary = segment.groups[int(warning.group)]
		segment.reserved = int(segment.reserved)-warning.records.size()
		group.reserved = int(group.reserved)-warning.records.size()
		for mark in warning.marks:
			mark.queue_free()
		_warnings.remove_at(index)
		if not valid:
			# Moving into a warning never turns it into a point-blank spawn.
			if int(definition.get("content_revision",2))<3:
				for record in warning.records:
					if record.elite:
						_elite_assigned = false
			continue
		for record in warning.records:
			var enemy = Enemy.new()
			add_child(enemy)
			enemy.global_position = record.point
			enemy.defeated.connect(_on_enemy_defeated)
			enemy.projectile_requested.connect(_spawn_projectile)
			enemy.warning_requested.connect(_spawn_attack_warning)
			enemy.hazard_requested.connect(_spawn_hazard)
			enemy.status_changed.connect(func(info: Dictionary): boss_status.emit(info))
			enemy.feedback_requested.connect(func(kind: String,payload: Dictionary):feedback_requested.emit(kind,payload))
			enemy.configure(world,player,record.species,record.elite)
			enemies.append(enemy)
			segment.spawned = int(segment.spawned)+1
			group.spawned = int(group.spawned)+1
			_spawned += 1
			if record.elite:
				_elite_spawned += 1

func _on_enemy_defeated(enemy: Node3D) -> void:
	if _stopped:
		return
	_defeated += 1
	var planned: int = metrics().planned
	var paid_after := floori(float(_defeated*_reward_budget)/float(maxi(1,planned)))
	var reward := maxi(0,paid_after-_reward_paid)
	_reward_paid += reward
	enemy_defeated.emit(enemy.global_position,reward)
	_check_clear()

func _check_clear() -> void:
	if _stopped or _complete or alive_count() > 0:
		return
	for segment in segments:
		if int(segment.activations) == 0 or int(segment.spawned) < int(segment.budget) or int(segment.reserved) > 0:
			return
	_complete = true
	if is_instance_valid(_projectile_batch):_projectile_batch.clear()
	world.set_doors_open(true)
	for node in _projectiles+_attack_warnings:
		if is_instance_valid(node):
			node.queue_free()
	boss_status.emit({})
	cleared.emit()

func _project_progress(point: Vector3) -> float:
	var nearest_distance := INF
	var nearest_progress := 0.0
	var accumulated := 0.0
	for index in range(1,_route.size()):
		var span := _route[index]-_route[index-1]
		var length := span.length()
		if length <= 0.0001:
			continue
		var weight := clampf((point-_route[index-1]).dot(span)/(length*length),0.0,1.0)
		var distance := point.distance_squared_to(_route[index-1]+span*weight)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_progress = accumulated+weight*length
		accumulated += length
	return nearest_progress

func _point_on_route(distance: float) -> Vector3:
	for index in range(1,_route.size()):
		var length := _route[index-1].distance_to(_route[index])
		if distance <= length:
			return _route[index-1].lerp(_route[index],distance/maxf(length,0.0001))
		distance -= length
	return _route[-1]

static func _ground_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

static func ground_disc(radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.014
	mesh.radial_segments = 24
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func danger_geometry(payload: Dictionary, symbol: bool = false) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := float(payload.get("radius",.5))
	var length := float(payload.get("length",2.0))
	var heading: Vector3 = payload.get("direction",Vector3.FORWARD)
	var side := heading.cross(Vector3.UP).normalized()
	var width := .065
	var hazard := bool(payload.get("hazard",false))
	if symbol:
		if hazard:
			for sign_value in [-1,1]:
				_danger_line(surface,Vector3(-radius*.27,0,-radius*.27*sign_value),Vector3(radius*.27,0,radius*.27*sign_value),width)
		else:
			for fraction in [.4,.7]:
				var tip: Vector3 = heading*length*fraction
				_danger_line(surface,tip-heading*.35+side*.28,tip,width)
				_danger_line(surface,tip-heading*.35-side*.28,tip,width)
	elif hazard:
		for index in 48:
			var a := Vector3(cos(index*TAU/48.0),0,sin(index*TAU/48.0))*radius
			var b := Vector3(cos((index+1)*TAU/48.0),0,sin((index+1)*TAU/48.0))*radius
			_danger_line(surface,a,b,width)
	else:
		# Swept melee is a capsule: the body can damage within its reach both
		# behind the initial position and beyond the final strike position.
		for index in 48:
			var angle_a := float(index)*TAU/48.0
			var angle_b := float(index+1)*TAU/48.0
			var a := side*sin(angle_a)*radius+heading*cos(angle_a)*radius
			var b := side*sin(angle_b)*radius+heading*cos(angle_b)*radius
			if cos(angle_a)>=0:a+=heading*length
			if cos(angle_b)>=0:b+=heading*length
			_danger_line(surface,a,b,width)
	var node := MeshInstance3D.new()
	node.name = "DangerSymbol" if symbol else "DangerBoundary"
	node.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0,.74,.32,.95) if not hazard else Color(1.0,.44,.28,.97)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 8
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.y = .023
	return node

static func _danger_line(surface: SurfaceTool,a: Vector3,b: Vector3,width: float) -> void:
	var normal := (b-a).cross(Vector3.UP).normalized()*width*.5
	for vertex in [a-normal,a+normal,b+normal,a-normal,b+normal,b-normal]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(vertex)

static func projectile_clearance(target: Node3D) -> float:
	# This is a conservative ground-space player-center envelope for the
	# existing upright capsule, not the projectile sphere's visual radius or
	# an exact safe-standing-space solver across walls/elevation changes.
	if not is_instance_valid(target):
		return 0.0
	var radius := 0.0
	for child in target.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is CapsuleShape3D:
			var scale_x: float = child.global_basis.x.length()
			var scale_z: float = child.global_basis.z.length()
			radius = maxf(radius,child.shape.radius*maxf(scale_x,scale_z))
	return radius

static func projectile_warning_paths(descriptors: Array, space: PhysicsDirectSpaceState3D) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	for descriptor in descriptors:
		var path: Dictionary = descriptor.duplicate()
		var origin: Vector3 = path.origin
		var end: Vector3 = origin+Vector3(path.direction)*float(path.speed)*float(path.lifetime)
		# Match the real .65m-height center ray, excluding the moving player.
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,end,1))
		path.end = end if hit.is_empty() else hit.position
		path.blocked = not hit.is_empty()
		paths.append(path)
	return paths

static func projectile_lane_polygons(paths: Array, clearance: float) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	if clearance <= 0.0:
		return polygons
	for path in paths:
		var origin := Vector2(path.origin.x,path.origin.z)
		var end := Vector2(path.end.x,path.end.z)
		var heading := Vector2(path.direction.x,path.direction.z).normalized()
		var side := Vector2(-heading.y,heading.x)
		var lane := PackedVector2Array()
		# Round muzzle clearance; blocked flight has an honest flat stop.
		for index in 13:
			var angle := float(index)*PI/12.0
			lane.append(origin+(side*cos(angle)-heading*sin(angle))*clearance)
		if path.blocked:
			lane.append(end-side*clearance)
			lane.append(end+side*clearance)
		else:
			for index in 13:
				var angle := float(index)*PI/12.0
				lane.append(end+(-side*cos(angle)+heading*sin(angle))*clearance)
		# Union overlaps once, so alpha never stacks into a false solid fan.
		var index := 0
		while index < polygons.size():
			var merged := Geometry2D.merge_polygons(polygons[index],lane)
			if merged.size() == 1:
				lane = merged[0]
				polygons.remove_at(index)
				index = 0
			else:
				index += 1
		polygons.append(lane)
	return polygons

static func projectile_danger_geometry(paths: Array, polygons: Array[PackedVector2Array], kind: String) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_vertices := false
	if kind == "DangerSymbol":
		for path in paths:
			var origin: Vector3 = path.origin
			var end: Vector3 = path.end
			var length := origin.distance_to(end)
			if length < .55:
				continue # Do not squeeze an arrow through a short wall stop.
			var heading: Vector3 = path.direction
			var side := heading.cross(Vector3.UP).normalized()
			var tip := origin+heading*minf(length-.12,maxf(.43,length*.62))
			_danger_line(surface,tip-heading*.28+side*.15,tip,.065)
			_danger_line(surface,tip-heading*.28-side*.15,tip,.065)
			has_vertices = true
	else:
		for polygon in polygons:
			if kind == "DangerBoundary":
				for index in polygon.size():
					var a: Vector2 = polygon[index]
					var b: Vector2 = polygon[(index+1)%polygon.size()]
					_danger_line(surface,Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),.065)
					has_vertices = true
			else:
				var triangles := Geometry2D.triangulate_polygon(polygon)
				for index in triangles:
					var vertex: Vector2 = polygon[index]
					surface.set_normal(Vector3.UP)
					surface.add_vertex(Vector3(vertex.x,0,vertex.y))
					has_vertices = true
	return surface.commit() if has_vertices else ArrayMesh.new()

static func projectile_danger_node(kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = kind
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0,.42,.13,.12) if kind == "DangerFill" else Color(1.0,.74,.32,.95)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 7 if kind == "DangerFill" else 8
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.y = .009 if kind == "DangerFill" else .023
	return node

func _spawn_projectile(payload: Dictionary) -> void:
	_projectiles = _projectiles.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	if _stopped or _complete or _projectiles.size() >= MAX_PROJECTILES:
		return
	if not is_instance_valid(_projectile_batch):
		_projectile_batch=ProjectileBatch.new()
		add_child(_projectile_batch)
	var projectile := HostileProjectile.new()
	projectile._batched_visual=true
	projectile.payload = payload
	projectile.player = player
	add_child(projectile)
	projectile.global_position = payload.origin
	_projectiles.append(projectile)
	_projectile_batch.sync_projectiles(_projectiles)

func _spawn_attack_warning(payload: Dictionary) -> void:
	_attack_warnings = _attack_warnings.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	if _stopped or _complete or _attack_warnings.size() >= MAX_ATTACK_WARNINGS:
		return
	var warning := AttackWarning.new()
	warning.payload = payload
	warning.player = player
	add_child(warning)
	_attack_warnings.append(warning)

func _spawn_hazard(payload: Dictionary) -> void:
	if not _warning_visible(payload.origin) or not world.contains_ground(payload.origin,float(payload.radius)):
		return
	var value := payload.duplicate()
	value.duration = float(value.warning)
	value.hazard = true
	_spawn_attack_warning(value)

class HostileProjectile:
	extends Node3D
	var payload: Dictionary
	var player: Node3D
	var elapsed := 0.0
	var _batched_visual:=false
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		if _batched_visual:return
		# Standalone projectiles retain exactly the same visual for tooling and
		# any caller outside a director; the normal room uses one instanced draw.
		var body := MeshInstance3D.new()
		body.mesh=ProjectileBatch.make_mesh()
		body.material_override=ProjectileBatch.make_material()
		add_child(body)
	func _physics_process(delta: float) -> void:
		var source = payload.get("source_actor")
		if not is_instance_valid(source) or source.dead:
			queue_free()
			return
		elapsed += delta
		if elapsed >= float(payload.lifetime):
			queue_free()
			return
		var next: Vector3 = global_position+Vector3(payload.direction)*float(payload.speed)*delta
		var query := PhysicsRayQueryParameters3D.create(global_position,next,1 | 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			if hit.collider == player and is_instance_valid(player) and player.has_method("receive_damage"):
				player.receive_damage(float(payload.damage),Vector3(payload.direction))
			queue_free()
			return
		global_position = next

class AttackWarning:
	extends Node3D
	var payload: Dictionary
	var player: Node3D
	var elapsed := 0.0
	var resolved := false
	var preview_paths: Array[Dictionary] = []
	var clearance := 0.0
	var _local_paths: Array[Dictionary] = []
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		global_position = payload.origin+Vector3.UP*0.035
		if payload.has("projectile_paths"):
			for kind in ["DangerBoundary","DangerSymbol","DangerFill"]:
				add_child(get_parent().projectile_danger_node(kind))
			_refresh_projectile_paths()
			return
		var radius := float(payload.get("radius",0.5))
		add_child(get_parent().danger_geometry(payload))
		add_child(get_parent().danger_geometry(payload,true))
		if bool(payload.get("hazard",false)):
			add_child(get_parent().ground_disc(radius,Color(1.0,0.28,0.12,0.22)))
		else:
			var length := float(payload.get("length",2.0))
			var heading: Vector3 = payload.get("direction",Vector3.FORWARD)
			for index in range(1,7):
				var mark: MeshInstance3D = get_parent().ground_disc(radius,Color(1.0,0.42,0.13,0.18))
				add_child(mark)
				mark.position = heading*length*float(index)/6.0
	func _refresh_projectile_paths() -> void:
		var source = payload.get("source_actor")
		if not is_instance_valid(source) or source.dead:
			return
		payload.origin = source.global_position
		payload.projectile_paths = source.projectile_descriptors()
		global_position = payload.origin+Vector3.UP*.035
		preview_paths = get_parent().projectile_warning_paths(payload.projectile_paths,get_world_3d().direct_space_state)
		var local_paths: Array[Dictionary] = []
		for path in preview_paths:
			# Stable source-relative geometry avoids add/subtract float jitter
			# during pure translation. Keep clipped world endpoints exact.
			var origin: Vector3 = path.muzzle_offset
			var end: Vector3 = path.end-Vector3(payload.origin) if path.blocked else origin+Vector3(path.direction)*float(path.speed)*float(path.lifetime)
			end.y = 0.0
			local_paths.append({"origin":origin,"end":end,"direction":path.direction,"blocked":path.blocked})
		var radius: float = get_parent().projectile_clearance(player)
		if local_paths == _local_paths and is_equal_approx(radius,clearance):
			return
		_local_paths = local_paths
		clearance = radius
		var polygons: Array[PackedVector2Array] = get_parent().projectile_lane_polygons(_local_paths,clearance)
		for kind in ["DangerBoundary","DangerSymbol","DangerFill"]:
			get_node(kind).mesh = get_parent().projectile_danger_geometry(_local_paths,polygons,kind)
	func _physics_process(delta: float) -> void:
		var source = payload.get("source_actor")
		if not is_instance_valid(source) or source.dead:
			queue_free()
			return
		if payload.has("projectile_paths"):
			_refresh_projectile_paths()
		elapsed += delta
		var boundary: MeshInstance3D = get_node_or_null("DangerBoundary")
		if boundary != null:
			var color: Color = boundary.material_override.albedo_color
			color.a = .72+.25*absf(sin(elapsed*12.0))
			boundary.material_override.albedo_color = color
		if elapsed < float(payload.duration):
			return
		if not resolved and bool(payload.get("hazard",false)):
			resolved = true
			var center: Vector3 = payload.origin
			if is_instance_valid(player) and Vector2(center.x-player.global_position.x,center.z-player.global_position.z).length() <= float(payload.radius) and absf(center.y-player.global_position.y) <= 1.0:
				var query := PhysicsRayQueryParameters3D.create(center+Vector3.UP*0.6,player.global_position+Vector3.UP*0.6,1)
				if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
					player.receive_damage(float(payload.damage),(player.global_position-center).normalized())
		queue_free()
