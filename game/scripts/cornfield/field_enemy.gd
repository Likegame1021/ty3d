extends CharacterBody3D
## Source encounter behavior with lightweight volumetric rural creatures.
## Adapters preserve the target project's branch and corn-gun contracts.

signal defeated(actor: Node)
signal projectile_requested(payload: Dictionary)
signal warning_requested(payload: Dictionary)
signal hazard_requested(payload: Dictionary)
signal status_changed(info: Dictionary)
signal feedback_requested(kind: String,payload: Dictionary)

const Appearance = preload("res://scripts/cornfield/enemy_appearance.gd")
const RiggedVisual = preload("res://scripts/cornfield/rigged_enemy_visual.gd")
const RIGGED_ASSETS := {
	"beetle":"res://assets/sprint_20261002/insects/hard_shell_beetle.glb",
	"boss_borer":"res://assets/sprint_20261002/insects/giant_corn_borer.glb",
}
const Catalog = preload("res://scripts/cornfield/enemy_catalog.gd")
const SOURCE_UNITS_PER_METRE := 32.0
const BRANCH_DAMAGE := 18.0
const CORN_UNIT_DAMAGE := 14.0
const NEWBORN_SAFE_TIME := 0.6
const ACTIONS := ["idle","walk","windup","strike","hurt","death"]


var world: Node3D
var target: Node3D
var species := "beetle"
var elite := false
var boss := false
var dead := false
var active := true
var hp := 1.0
var max_hp := 1.0
var birth_time := 0.0
var profile: Dictionary = {}
var phase := "follow"
var phase_time := 0.0
var attack_pattern := "charge"
var strike_direction := Vector3.FORWARD
var locked_target := Vector3.ZERO
var boss_stage := 1
var visual_variant:String = "" # Visual choice only; configure still owns species/profile.
var visual: Node3D
var _limbs: Array[Node3D] = []
var _body_materials: Array[StandardMaterial3D] = []
var _body_colors: Array[Color] = []
var _visual_size := 1.0
var _rigged_visual:Node3D
var _rigged_walk_time := 0.0
var animation_state := ""
var animation_time := 0.0
var reward := 1
var _phase_duration := 1.0
var _death_time := 0.0
var _hurt_time := 0.0
var _knockback := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _path_timer := 0.0
var _struck := false
var _boss_attack_index := 0
var _combo_step := 0
var _combo_limit := 1
var _strike_speed := 0.0

func configure(room_world: Node3D, player: Node3D, id: String, is_elite := false) -> void:
	world = room_world
	target = player
	species = id if Catalog.SPECIES.has(id) else "beetle"
	elite = is_elite
	boss = species == "boss_borer"
	profile = Catalog.profile(species,elite)
	max_hp = float(profile.hp)
	hp = max_hp
	attack_pattern = str(profile.attack)
	reward = 12 if boss else (3 if elite else 1)
	add_to_group("full_enemies")
	collision_layer = 4
	collision_mask = 1 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(profile.radius)/SOURCE_UNITS_PER_METRE
	capsule.height = maxf(capsule.radius*2.0,1.15 if not boss else 2.0)
	collider.shape = capsule
	collider.position.y = capsule.height*0.5
	add_child(collider)
	_build_visual()
	_path_timer = float(get_instance_id()%9)*0.035
	_set_animation("idle")
	_emit_status()

func _physics_process(delta: float) -> void:
	if profile.is_empty():
		return
	if dead:
		_death_time += delta
		_advance_animation(delta)
		if _death_time >= 0.85:
			queue_free()
		return
	if not is_instance_valid(target) or not is_instance_valid(world):
		return
	birth_time += delta
	_hurt_time = maxf(0.0,_hurt_time-delta)
	_path_timer -= delta
	phase_time -= delta
	_knockback = _knockback.move_toward(Vector3.ZERO,delta*10.0)
	velocity = _knockback
	if boss and boss_stage == 1 and hp <= max_hp*0.48:
		boss_stage = 2
		feedback_requested.emit("boss_phase",{"position":global_position,"strength":2.0})
		_emit_status()
	match phase:
		"follow":
			var heading := _chase_direction()
			velocity += heading*float(profile.speed)/SOURCE_UNITS_PER_METRE*(1.12 if boss_stage == 2 else 1.0)
			if birth_time >= NEWBORN_SAFE_TIME and global_position.distance_to(target.global_position) <= float(profile.range)/SOURCE_UNITS_PER_METRE and _warning_in_view() and _line_clear(global_position,target.global_position):
				_begin_attack()
				velocity = _knockback
		"windup":
			if phase_time <= 0.0:
				_start_strike()
		"strike":
			if attack_pattern in ["charge","flank","peck","leap"]:
				velocity += strike_direction*_strike_speed
			if phase_time <= 0.0:
				_try_melee_hit()
				_finish_strike()
		"recover":
			if phase_time <= 0.0:
				phase = "follow"
	velocity.y = 0.0
	move_and_slide()
	if phase == "strike":
		_try_melee_hit()
		if _has_horizontal_blocker() and attack_pattern in ["charge","flank","leap"]:
			_begin_recovery()
	_update_animation(delta)

func _has_horizontal_blocker() -> bool:
	# FLOATING reports even a flat Ground recovery contact as "on_wall".
	# Only lateral collision normals may terminate a planar charge/leap.
	# A slide can contain both ground and wall contacts: inspect every one.
	var floor_limit:=cos(floor_max_angle)
	for slide in get_slide_collision_count():
		var contact:=get_slide_collision(slide)
		for index in contact.get_collision_count():
			if absf(contact.get_normal(index).dot(up_direction))<floor_limit:
				return true
	return false

func _chase_direction() -> Vector3:
	if _path_timer <= 0.0:
		# The room owns one shared navigation structure; no per-enemy AStar/map.
		_path = world.path_to(global_position,target.global_position,float(profile.radius)/SOURCE_UNITS_PER_METRE)
		_path_index = 0
		_path_timer = 0.35+float(get_instance_id()%5)*0.025
	while _path_index < _path.size() and _ground_distance(global_position,_path[_path_index]) < 0.3:
		_path_index += 1
	if _path_index >= _path.size():
		return Vector3.ZERO
	var heading := _path[_path_index]-global_position
	heading.y = 0.0
	heading = heading.normalized()
	var separate := Vector3.ZERO
	for sibling in get_parent().get_children():
		if sibling == self or not sibling is CharacterBody3D or not sibling.get("species") is String or sibling.get("dead") == true:
			continue
		var difference: Vector3 = global_position-sibling.global_position
		difference.y = 0.0
		var distance := difference.length()
		if distance > 0.01 and distance < 0.85:
			separate += difference/distance*(0.85-distance)
	return (heading+separate*1.1).normalized()

func _begin_attack() -> void:
	if dead or birth_time < NEWBORN_SAFE_TIME or not is_instance_valid(target):
		return
	_combo_step = 0
	_combo_limit = int(profile.combo)
	attack_pattern = str(profile.attack)
	if boss:
		var sequence := ["charge","ring" if boss_stage == 2 else "fan","fall"]
		attack_pattern = sequence[_boss_attack_index%sequence.size()]
		_boss_attack_index += 1
		_combo_limit = 2 if boss_stage == 2 and attack_pattern == "charge" else 1
	_prepare_windup(float(profile.windup))

func _prepare_windup(duration: float) -> void:
	phase = "windup"
	phase_time = maxf(0.45,duration)
	_phase_duration = phase_time
	locked_target = target.global_position
	strike_direction = locked_target-global_position
	strike_direction.y = 0.0
	strike_direction = strike_direction.normalized()
	if strike_direction.is_zero_approx():
		strike_direction = Vector3.FORWARD
	_struck = false
	_set_animation("windup")
	if attack_pattern == "fall":
		var side := strike_direction.cross(Vector3.UP)
		var points: Array[Vector3] = [locked_target,locked_target+side*2.6,locked_target-side*2.6]
		if boss_stage == 2:
			points.append(locked_target+strike_direction*2.9)
		for point in points:
			if world.contains_ground(point,1.0):
				hazard_requested.emit({"origin":point,"radius":1.0,"warning":maxf(0.9,phase_time),"damage":float(profile.damage),"source_actor":self})
	else:
		var melee := attack_pattern in ["charge","flank","peck","leap"]
		var distance := minf(8.0,float(profile.range)/SOURCE_UNITS_PER_METRE)
		if melee:
			var speed := float(profile.burst_speed)/SOURCE_UNITS_PER_METRE
			if attack_pattern=="leap":
				speed=minf(8.9,_ground_distance(global_position,locked_target)/float(profile.strike))
			distance=speed*float(profile.strike)
		var warning := {"origin":global_position,"direction":strike_direction,"length":distance,"radius":_melee_reach() if melee else (.75 if boss else .38),"duration":phase_time,"source_actor":self,"pattern":attack_pattern}
		if not melee:
			warning.projectile_paths = projectile_descriptors()
		warning_requested.emit(warning)

func _start_strike() -> void:
	phase = "strike"
	phase_time = float(profile.strike)
	_phase_duration = phase_time
	_strike_speed = float(profile.burst_speed)/SOURCE_UNITS_PER_METRE
	if attack_pattern == "leap":
		_strike_speed = minf(8.9,_ground_distance(global_position,locked_target)/phase_time)
	_set_animation("strike")
	if attack_pattern in ["spit","fan","ring"]:
		_emit_projectiles()

func _finish_strike() -> void:
	_combo_step += 1
	if _combo_step < _combo_limit and is_instance_valid(target) and _ground_distance(global_position,target.global_position) < float(profile.range)/SOURCE_UNITS_PER_METRE+1.5 and _line_clear(global_position,target.global_position):
		_prepare_windup(0.5)
	else:
		_begin_recovery()

func _begin_recovery() -> void:
	phase = "recover"
	phase_time = float(profile.recovery)*(0.86 if boss_stage == 2 else 1.0)
	_phase_duration = phase_time

func _melee_reach() -> float:
	return 1.05 if boss else (.94 if attack_pattern in ["leap","peck"] else .72)

func _try_melee_hit() -> void:
	if dead or _struck or birth_time < NEWBORN_SAFE_TIME or not is_instance_valid(target) or not target.has_method("receive_damage"):
		return
	if not attack_pattern in ["charge","flank","peck","leap"]:
		return
	if attack_pattern == "leap" and phase_time > 0.09:
		return
	var reach := _melee_reach()
	if _ground_distance(global_position,target.global_position) <= reach and absf(global_position.y-target.global_position.y) < 1.0 and _line_clear(global_position,target.global_position):
		_struck = true
		target.receive_damage(float(profile.damage),strike_direction)

func projectile_descriptors() -> Array[Dictionary]:
	# Intended release geometry, shared by the preview and emission. The aim
	# stays locked, but every read uses the current muzzle after knockback.
	var paths: Array[Dictionary] = []
	if not attack_pattern in ["spit","fan","ring"]:
		return paths
	var offsets: Array[float] = [0.0]
	if attack_pattern == "fan":
		offsets.assign([-0.28,0.0,0.28] if not boss else [-0.6,-0.3,0.0,0.3,0.6])
	elif attack_pattern == "ring":
		offsets.clear()
		for index in range(10):
			offsets.append(float(index)*TAU/10.0+0.16)
	for angle in offsets:
		var heading := strike_direction.rotated(Vector3.UP,angle)
		var muzzle_offset := heading*(float(profile.radius)/SOURCE_UNITS_PER_METRE+0.2)
		var origin := global_position+Vector3.UP*0.65+muzzle_offset
		if not _line_clear(global_position,origin-Vector3.UP*0.65):
			continue
		paths.append({"origin":origin,"direction":heading,"speed":3.75 if species == "snail" else 4.9,"damage":float(profile.damage)*0.8,"lifetime":2.6,"source_actor":self,"muzzle_offset":muzzle_offset})
	return paths

func _emit_projectiles() -> void:
	if dead or birth_time < NEWBORN_SAFE_TIME or not _line_clear(global_position,target.global_position):
		return
	for path in projectile_descriptors():
		# Relative geometry is preview-only; retain the exact gameplay payload.
		path.erase("muzzle_offset")
		projectile_requested.emit(path)

func receive_hit(amount_or_direction: Variant, direction: Vector3 = Vector3.ZERO) -> void:
	# The existing target player sends only its facing vector. Numeric callers
	# retain source damage semantics for encounter effects and tests.
	if amount_or_direction is Vector3:
		take_damage(BRANCH_DAMAGE*_player_damage_multiplier(),amount_or_direction)
	elif amount_or_direction is float or amount_or_direction is int:
		take_damage(float(amount_or_direction),direction)

func receive_projectile(amount: int) -> void:
	var direction := (global_position-target.global_position).normalized() if is_instance_valid(target) else Vector3.ZERO
	take_damage(float(amount)*CORN_UNIT_DAMAGE*_player_damage_multiplier(),direction)

func _player_damage_multiplier() -> float:
	if is_instance_valid(target):
		var multiplier = target.get("damage_multiplier")
		if multiplier is float or multiplier is int:
			return maxf(0.0,float(multiplier))
	return 1.0

func take_damage(amount: float, direction: Vector3 = Vector3.ZERO) -> void:
	if dead or amount <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	var shell := species == "snail" and phase == "recover"
	hp = maxf(0.0,hp-amount*(0.45 if shell else 1.0))
	_hurt_time = 0.14
	var knockback_scale := 1.0
	if is_instance_valid(target) and target.get("knockback_multiplier") != null:
		knockback_scale = maxf(0.0,float(target.get("knockback_multiplier")))
	_knockback = direction.normalized()*(0.7 if boss or shell else 2.4)*knockback_scale
	feedback_requested.emit("hit",{"position":global_position,"direction":direction,"strength":.7 if shell else 1.0,"species":species,"shell":shell,"source_actor":self})
	_emit_status()
	if hp <= 0.0:
		dead = true
		active = false
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		_set_animation("death")
		defeated.emit(self)

func _emit_status() -> void:
	if boss:
		status_changed.emit({"title":str(profile.get("name","巨型玉米螟")),"hp":hp,"max_hp":max_hp,"stage":boss_stage} if hp > 0.0 else {})

func _line_clear(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(from+Vector3.UP*0.65,to+Vector3.UP*0.65,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _warning_in_view() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true # Deterministic headless tests have no render camera.
	var screen := get_viewport().get_visible_rect().grow(-22.0)
	for point in [global_position+Vector3.UP*0.35,target.global_position+Vector3.UP*0.35]:
		if camera.is_position_behind(point) or not screen.has_point(camera.unproject_position(point)):
			return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,global_position+Vector3.UP*0.65,1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

static func _ground_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Creature3D"
	add_child(visual)
	var paths:Array[String]=[]
	var variant_path:String=Appearance.scene_path(visual_variant,species)
	if not variant_path.is_empty():paths.append(variant_path)
	if RIGGED_ASSETS.has(species):paths.append(str(RIGGED_ASSETS[species]))
	for scene_path:String in paths:
		if not ResourceLoader.exists(scene_path):continue
		var scene:PackedScene=load(scene_path) as PackedScene
		if scene==null:continue
		var adapter:=RiggedVisual.new()
		visual.add_child(adapter)
		if adapter.install(scene):
			_rigged_visual=adapter
			_visual_size=1.0 # Accepted GLBs already have world dimensions.
			_build_elite_marker()
			return
		adapter.free() # Try the original skin before the existing primitive fallback.
	_visual_size = 1.9 if boss else 1.0
	visual.scale = Vector3.ONE*_visual_size
	match species:
		"mouse":
			_ellipsoid(Vector3(0,0.25,0.03),Vector3(0.28,0.22,0.40),Color("886348"))
			_ellipsoid(Vector3(0,0.29,-0.30),Vector3(0.20,0.18,0.24),Color("ac805b"))
			_ellipsoid(Vector3(0,0.27,-0.52),Vector3(0.075,0.055,0.07),Color("dbad99"))
			for side in [-1.0,1.0]:
				_ellipsoid(Vector3(side*0.14,0.48,-0.26),Vector3(0.12,0.13,0.055),Color("ba9175"))
				_ellipsoid(Vector3(side*0.14,0.49,-0.30),Vector3(0.075,0.08,0.025),Color("daac99"))
				_leg(Vector3(side*0.19,0.11,0.22),Vector3(side*0.23,0.04,0.13),Color("71543d"))
				_leg(Vector3(side*0.17,0.12,-0.17),Vector3(side*0.22,0.04,-0.22),Color("71543d"))
			_rod(Vector3(0,0.16,0.33),Vector3(0.18,0.09,0.75),0.026,Color("bf917d"))
			_eyes(0.13,0.35,-0.46,0.036)
		"rooster":
			_ellipsoid(Vector3(0,0.43,0.03),Vector3(0.29,0.31,0.34),Color("b86a30"))
			_ellipsoid(Vector3(0,0.68,-0.23),Vector3(0.16,0.31,0.16),Color("e4c88b"))
			_ellipsoid(Vector3(0,0.88,-0.31),Vector3(0.16,0.17,0.17),Color("ebd6a0"))
			_rod(Vector3(0,0.88,-0.4),Vector3(0,0.84,-0.59),0.055,Color("e5a72c"),0.0)
			for index in range(3):
				_ellipsoid(Vector3(0,1.04,-0.38+index*0.085),Vector3(0.048,0.105,0.068),Color("b73728"))
			_ellipsoid(Vector3(0,0.73,-0.40),Vector3(0.06,0.12,0.04),Color("c4442c"))
			for side in [-1.0,1.0]:
				_ellipsoid(Vector3(side*0.24,0.45,0.07),Vector3(0.09,0.20,0.26),Color("713f2a"))
				_leg(Vector3(side*0.13,0.30,0.02),Vector3(side*0.14,0.06,-0.03),Color("c38b36"))
				_rod(Vector3(side*0.14,0.06,-0.03),Vector3(side*0.17,0.045,-0.23),0.024,Color("c38b36"))
			for index in range(3):
				_rod(Vector3((index-1)*0.06,0.48,0.28),Vector3((index-1)*0.15,0.86,0.58),0.07,Color("284943"),0.045)
			_eyes(0.12,0.93,-0.42,0.032)
		"snail":
			_ellipsoid(Vector3(0,0.14,0),Vector3(0.28,0.13,0.47),Color("91a264"))
			_ellipsoid(Vector3(0,0.43,0.11),Vector3(0.32,0.35,0.33),Color("9b6038"))
			for side in [-1.0,1.0]:
				_ellipsoid(Vector3(side*0.28,0.45,0.10),Vector3(0.055,0.24,0.24),Color("d2a25f"))
				_ellipsoid(Vector3(side*0.323,0.45,0.10),Vector3(0.025,0.14,0.14),Color("7b4d31"))
				_ellipsoid(Vector3(side*0.345,0.45,0.10),Vector3(0.022,0.07,0.07),Color("d2a25f"))
				_rod(Vector3(side*0.11,0.20,-0.34),Vector3(side*0.17,0.46,-0.42),0.022,Color("87985b"))
			_eyes(0.17,0.47,-0.44,0.045)
		"locust":
			_ellipsoid(Vector3(0,0.29,0.08),Vector3(0.18,0.17,0.43),Color("75863b"))
			_ellipsoid(Vector3(0,0.39,-0.29),Vector3(0.18,0.21,0.18),Color("9aaa43"))
			for side in [-1.0,1.0]:
				_ellipsoid(Vector3(side*0.08,0.39,0.16),Vector3(0.085,0.045,0.34),Color("b4aa52"))
				_leg(Vector3(side*0.13,0.27,0.18),Vector3(side*0.38,0.40,0.30),Color("536630"))
				_rod(Vector3(side*0.38,0.40,0.30),Vector3(side*0.42,0.045,-0.04),0.035,Color("5c7333"))
				_leg(Vector3(side*0.13,0.27,-0.12),Vector3(side*0.27,0.04,-0.33),Color("637631"))
				_rod(Vector3(side*0.085,0.52,-0.35),Vector3(side*0.17,0.77,-0.49),0.012,Color("493d27"))
			_eyes(0.14,0.44,-0.43,0.055)
		"corn_borer", "boss_borer":
			for index in range(5):
				var taper := 1.0-absf(float(index)-1.7)*0.13
				_ellipsoid(Vector3(0,0.25,-0.37+index*0.19),Vector3(0.26,0.25,0.20)*taper,Color("c9a853") if index%2 == 0 else Color("a8883d"))
				for side in [-1.0,1.0]:
					_leg(Vector3(side*0.17,0.14,-0.34+index*0.19),Vector3(side*0.30,0.04,-0.40+index*0.19),Color("654d2e"))
			_ellipsoid(Vector3(0,0.30,-0.51),Vector3(0.23,0.23,0.15),Color("765233"))
			for side in [-1.0,1.0]:
				_rod(Vector3(side*0.13,0.18,-0.58),Vector3(side*0.05,0.16,-0.77),0.049,Color("704126"),0.014)
				_rod(Vector3(side*0.11,0.46,-0.54),Vector3(side*0.19,0.65,-0.63),0.017,Color("614c28"))
			_eyes(0.15,0.37,-0.64,0.04)
			if boss:
				for index in range(4):
					_rod(Vector3(0,0.43,-0.30+index*0.22),Vector3(0,0.66,-0.25+index*0.22),0.075,Color("d98335"),0.0)
		_:
			_ellipsoid(Vector3(0,0.26,0.08),Vector3(0.31,0.25,0.36),Color("385c4c"))
			for side in [-1.0,1.0]:
				_ellipsoid(Vector3(side*0.13,0.34,0.08),Vector3(0.16,0.18,0.33),Color("4d7860"))
				for index in range(3):
					_leg(Vector3(side*0.20,0.18,-0.16+index*0.19),Vector3(side*0.43,0.04,-0.24+index*0.22),Color("424337"))
				_rod(Vector3(side*0.11,0.32,-0.34),Vector3(side*0.23,0.47,-0.55),0.02,Color("695c38"))
			_ellipsoid(Vector3(0,0.24,-0.29),Vector3(0.22,0.18,0.20),Color("3c4536"))
			_eyes(0.13,0.30,-0.45,0.038)
	_build_elite_marker()

func _build_elite_marker() -> void:
	if elite:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.38
		ring.outer_radius = 0.44
		ring.rings = 16
		ring.ring_segments = 6
		_mesh(ring,Vector3(0,0.04,0),Color("efc55c"))
		for side in [-1.0,1.0]:
			_rod(Vector3(side*0.18,0.40,0.06),Vector3(side*0.30,0.64,0.08),0.055,Color("e5b348"),0.0)

func _mesh(mesh: Mesh, point: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	part.material_override = material
	visual.add_child(part)
	_body_materials.append(material)
	_body_colors.append(color)
	return part

func _ellipsoid(point: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var part := _mesh(sphere,point,color)
	part.scale = dimensions
	return part

func _rod(start: Vector3, end: Vector3, radius: float, color: Color, tip := -1.0) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.bottom_radius = radius
	cylinder.top_radius = radius if tip < 0.0 else tip
	cylinder.height = start.distance_to(end)
	cylinder.radial_segments = 8
	var part := _mesh(cylinder,(start+end)*0.5,color)
	part.quaternion = Quaternion(Vector3.UP,(end-start).normalized())
	return part

func _leg(start: Vector3, end: Vector3, color: Color) -> void:
	var leg := _rod(start,end,0.038,color,0.028)
	_limbs.append(leg)
	leg.set_meta("base_rotation",leg.rotation)

func _eyes(width: float, height: float, depth: float, radius: float) -> void:
	for side in [-1.0,1.0]:
		_ellipsoid(Vector3(side*width,height,depth),Vector3.ONE*radius,Color("25291e"))
		_ellipsoid(Vector3(side*width,height+radius*0.28,depth-radius*0.80),Vector3.ONE*radius*0.27,Color("fff4cf"))

func _set_animation(action: String) -> void:
	if animation_state == action:
		return
	animation_state = action
	animation_time = 0.0
	_rigged_walk_time = 0.0
	if is_instance_valid(_rigged_visual):_sample_rigged_animation(0)

func _advance_animation(delta: float) -> void:
	animation_time += delta
	if visual == null:
		return
	if is_instance_valid(_rigged_visual):
		_sample_rigged_animation(delta)
		for index in _body_materials.size():
			_body_materials[index].albedo_color=_body_colors[index].lerp(Color("fff1d4"),.55) if _hurt_time>0 else _body_colors[index]
		return
	var walk := animation_state == "walk"
	var wave := sin(animation_time*12.0)
	visual.position.y = absf(wave)*0.035 if walk else 0.0
	visual.rotation.x = -0.13 if animation_state == "windup" else 0.1 if animation_state == "strike" else 0.0
	var squash := 1.0+sin(animation_time*18.0)*0.035 if animation_state == "hurt" else 1.0
	visual.scale = Vector3(squash,1.0/squash,squash)*_visual_size
	for index in range(_limbs.size()):
		var limb := _limbs[index]
		limb.rotation = limb.get_meta("base_rotation")
		if walk or animation_state == "strike":
			limb.rotation.x += sin(animation_time*15.0+index*PI)*0.22
	if animation_state == "death":
		visual.rotation.z = lerpf(0.0,PI*0.46,clampf(_death_time/0.45,0.0,1.0))
		visual.scale *= maxf(0.01,1.0-_death_time/0.85)
	for index in range(_body_materials.size()):
		_body_materials[index].albedo_color = _body_colors[index].lerp(Color("fff1d4"),0.55) if _hurt_time > 0.0 else _body_colors[index]

func _sample_rigged_animation(delta:float) -> void:
	var duration:=1.0
	var elapsed:=animation_time
	match animation_state:
		"windup","strike":
			duration=_phase_duration
			elapsed=maxf(0,_phase_duration-phase_time)
		"hurt":
			duration=.14
			elapsed=.14-_hurt_time
		"death":
			duration=.8
			elapsed=_death_time
		"walk":
			var reference_speed:=1.53125 if boss else 1.34375
			_rigged_walk_time+=delta*clampf(Vector2(velocity.x,velocity.z).length()/reference_speed,0,2.5)
			elapsed=_rigged_walk_time
	_rigged_visual.sample_state(animation_state,duration,elapsed)
	_rigged_visual.set_hit_flash(1.0 if _hurt_time>0 else 0.0)

func _update_animation(delta: float) -> void:
	var action := "walk" if phase == "follow" and velocity.length_squared() > 0.05 else "idle"
	if phase in ["windup","strike"]:
		action = phase
	if _hurt_time > 0.0:
		action = "hurt"
	_set_animation(action)
	var heading := strike_direction if phase in ["windup","strike"] else velocity
	if heading.length_squared() > 0.03:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(-heading.x,-heading.z),minf(1.0,delta*12.0))
	_advance_animation(delta)
