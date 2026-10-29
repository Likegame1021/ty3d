extends Node3D
## Decorative event consumer. This component never applies damage or changes
## collision. Recycled meshes are capped separately from hostile telegraphs.
const MAX_ACTIVE := 30
const MAX_TRAIL_SAMPLES := 12
const TRAIL_LIFE := 0.10
const TRAIL_LEAD := 0.10
const TRAIL_TAIL := 0.075
const DEBRIS_SHADER = preload("res://scripts/cornfield/combat_debris.gdshader")
const ContactAnchor = preload("res://scripts/cornfield/contact_anchor.gd")
const LIFETIMES := {"slash":0.18,"hit":0.28,"hurt":0.32,"defeat":0.52,"pickup":0.48,"upgrade":0.8,"boss_phase":0.9}
const COLORS := {"slash":Color("ffe9a7"),"hit":Color("dcc79a"),"hurt":Color("f7f0de"),"defeat":Color("938566"),"pickup":Color("eacf72"),"upgrade":Color("d3e4a0"),"boss_phase":Color("ecd9a8")}
var _slots: Array[Dictionary] = []
var _sequence := 0
var emitted_count := 0
var _particle_meshes := {}
var _player_ref: WeakRef
var _trail_skeleton: Skeleton3D
var _trail_attachment: BoneAttachment3D
var _trail_node: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_samples: Array[Dictionary] = []
var _trail_clock := 0.0
var _last_source_elapsed := -1.0
var _contact_anchor = ContactAnchor.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# The ordinary process only ages samples. A real rig supplies the final
	# modified hand pose from skeleton_updated, after every pose modifier.
	process_priority = 50

func bind_player(player: Node3D) -> void:
	if is_instance_valid(_trail_skeleton) and _trail_skeleton.skeleton_updated.is_connected(_sample_trail):
		_trail_skeleton.skeleton_updated.disconnect(_sample_trail)
	var previous = _source_player()
	if is_instance_valid(previous) and previous.has_signal("died") and previous.is_connected("died",clear_all):
		previous.disconnect("died",clear_all)
	_player_ref = weakref(player) if is_instance_valid(player) else null
	_trail_skeleton = null
	_trail_attachment = null
	_clear_trail()
	if not is_instance_valid(player):
		return
	if player.has_signal("died"):
		player.connect("died",clear_all)
	var pivot = player.get("branch_pivot")
	if is_instance_valid(pivot) and pivot.get_parent() is BoneAttachment3D:
		_trail_attachment = pivot.get_parent()
		if _trail_attachment.get_parent() is Skeleton3D:
			_trail_skeleton = _trail_attachment.get_parent()
			_trail_skeleton.skeleton_updated.connect(_sample_trail)

func _source_player():
	return _player_ref.get_ref() if _player_ref != null else null

func _trail_source_valid(player) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and player.get("controls_enabled") != false and player.get("hp") != 0.0 and player.get("weapon_id") != "corn" and player.get("ranged_stance") != true and player.attack.remaining > 0.0

func _sample_trail() -> void:
	if is_inside_tree() and get_tree().paused:
		return
	var player = _source_player()
	if not _trail_source_valid(player):
		_clear_trail()
		return
	var elapsed: float = player.attack.elapsed
	if elapsed < _last_source_elapsed:
		_clear_trail()
	_last_source_elapsed = elapsed
	if elapsed < maxf(0.0,player.attack.active_start-TRAIL_LEAD):
		_clear_trail()
		return
	if elapsed > player.attack.active_end+TRAIL_TAIL:
		return
	var pivot: Node3D = player.branch_pivot
	var branch: MeshInstance3D = pivot.get_node_or_null("Branch") if is_instance_valid(pivot) else null
	if not is_instance_valid(branch) or branch.mesh == null or not branch.is_visible_in_tree():
		_clear_trail()
		return
	var transform := branch.global_transform
	if is_instance_valid(_trail_skeleton) and is_instance_valid(_trail_attachment):
		# Compose directly from the final pose; connection order relative to
		# BoneAttachment3D cannot introduce a stale-frame socket transform.
		var index := _trail_skeleton.find_bone(_trail_attachment.bone_name)
		if index >= 0:
			transform = _trail_skeleton.global_transform*_trail_skeleton.get_bone_global_pose(index)*pivot.transform*branch.transform
	var tip_y := branch.mesh.get_aabb().end.y
	var tip := transform*Vector3(0,tip_y,0)
	var inner := transform*Vector3(0,tip_y-.18,0)
	if not tip.is_finite() or not inner.is_finite():
		_clear_trail()
		return
	if not _trail_samples.is_empty():
		var distance: float = tip.distance_to(_trail_samples[-1].tip)
		if distance > 1.25:
			_clear_trail()
		elif distance < .002:
			return
	_trail_samples.append({"tip":tip,"inner":inner,"born":_trail_clock,"source_time":elapsed})
	while _trail_samples.size() > MAX_TRAIL_SAMPLES:
		_trail_samples.pop_front()
	_rebuild_trail()

func _clear_trail() -> void:
	_trail_samples.clear()
	_last_source_elapsed = -1.0
	if is_instance_valid(_trail_node):
		_trail_node.visible = false
		_trail_mesh.clear_surfaces()

func _rebuild_trail() -> void:
	if not is_instance_valid(_trail_node):
		_trail_node = MeshInstance3D.new()
		_trail_node.name = "WoodTipTrail"
		_trail_mesh = ImmediateMesh.new()
		_trail_node.mesh = _trail_mesh
		_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.render_priority = -6
		_trail_node.material_override = material
		add_child(_trail_node)
	_trail_mesh.clear_surfaces()
	_trail_node.visible = _trail_samples.size() >= 2
	if not _trail_node.visible:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1,_trail_samples.size()):
		var a: Dictionary = _trail_samples[index-1]
		var b: Dictionary = _trail_samples[index]
		# Three non-overlapping strips keep one draw surface and the original
		# distal18cm footprint. Brown shoulders frame a readable cream core.
		for band in [[0.0,.16],[.16,.84],[.84,1.0]]:
			var core:bool=band[0]>.0 and band[1]<1.0
			var a0:Vector3=a.tip.lerp(a.inner,band[0])
			var a1:Vector3=a.tip.lerp(a.inner,band[1])
			var b0:Vector3=b.tip.lerp(b.inner,band[0])
			var b1:Vector3=b.tip.lerp(b.inner,band[1])
			for item in [[a0,a.born],[a1,a.born],[b1,b.born],[a0,a.born],[b1,b.born],[b0,b.born]]:
				var opacity:=clampf(1.0-(_trail_clock-float(item[1]))/TRAIL_LIFE,0.0,1.0)*(.86 if core else .70)
				_trail_mesh.surface_set_color(Color(1.0,.96,.83,opacity) if core else Color(.31,.20,.11,opacity))
				_trail_mesh.surface_add_vertex(to_local(item[0]))
	_trail_mesh.surface_end()

func trail_snapshot() -> Array:
	return _trail_samples.duplicate(true)

func emit_feedback(kind: String, payload: Dictionary) -> void:
	if not LIFETIMES.has(kind) or (is_inside_tree() and get_tree().paused):
		return
	if kind == "slash" and is_instance_valid(_source_player()):
		# Bound players display the actual moving wood, never a second invented
		# ground-radius arc. The event remains cosmetic and never claims a hit.
		emitted_count += 1
		return
	var at = payload.get("position")
	if not at is Vector3:
		var target = payload.get("target")
		if not is_instance_valid(target) or not target is Node3D:
			return
		at = target.global_position
	if not at.is_finite():
		return
	var slot := _acquire()
	var mesh_node: MeshInstance3D = slot.node
	var strength := clampf(float(payload.get("strength",1.0)),0.2,2.0)
	var direction: Vector3 = payload.get("direction",Vector3.FORWARD)
	if not direction.is_finite() or direction.length_squared()<0.001:
		direction = Vector3.FORWARD
	slot.active = true
	slot.elapsed = 0.0
	slot.life = float(LIFETIMES[kind])
	slot.kind = kind
	slot.serial = _sequence
	slot.origin = at
	slot.strength = strength
	slot.color = COLORS[kind]
	_sequence += 1
	emitted_count += 1
	var debris := kind in ["hit","defeat"]
	mesh_node.mesh = _debris_mesh(kind) if debris else _make_mesh(kind,strength,payload)
	# Vertex motion must remain inside the renderer's conservative bounds.
	mesh_node.custom_aabb = AABB(Vector3(-1.0,-.3,-1.0),Vector3(2.0,1.4,2.0)) if debris else AABB()
	mesh_node.position = at+Vector3.UP*(.055 if kind == "defeat" else (0.08 if kind in ["slash","boss_phase"] else 0.28))
	if kind == "hit":
		mesh_node.global_position = _impact_anchor(payload,at,direction)
	mesh_node.rotation.y = atan2(-direction.x,-direction.z)
	mesh_node.scale = Vector3.ONE
	mesh_node.visible = true
	var color: Color = COLORS[kind]
	color.a = .72 if kind=="slash" else .65
	slot.material.albedo_color = color
	mesh_node.material_override = slot.debris_material if debris else slot.material
	if debris:
		var shade := Color.WHITE
		if str(payload.get("species","")) in ["beetle","snail"]:
			shade = Color("c4b891")
		elif str(payload.get("species","")) in ["locust","corn_borer","boss_borer"]:
			shade = Color("d3d5a1")
		slot.debris_material.set_shader_parameter("age",0.0)
		slot.debris_material.set_shader_parameter("life",slot.life)
		slot.debris_material.set_shader_parameter("flash_life",.14)
		slot.debris_material.set_shader_parameter("flash_scale",1.0)
		slot.debris_material.set_shader_parameter("strength",strength)
		slot.debris_material.set_shader_parameter("ground_y",-.03 if kind=="defeat" else float(at.y)+.025-mesh_node.global_position.y)
		slot.debris_material.set_shader_parameter("tint",shade)

func _impact_anchor(payload: Dictionary,at: Vector3,direction: Vector3) -> Vector3:
	return _contact_anchor.resolve(payload.get("source_actor"),at,direction)

func _acquire() -> Dictionary:
	for slot in _slots:
		if not slot.active:
			return slot
	if _slots.size()>=MAX_ACTIVE:
		var oldest: Dictionary = _slots[0]
		for slot in _slots:
			if int(slot.serial)<int(oldest.serial):
				oldest = slot
		return oldest
	var node := MeshInstance3D.new()
	node.name = "RecycledDecoration_%02d" % _slots.size()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = -5 # Danger edges use higher render priority.
	node.material_override = material
	var debris_material := ShaderMaterial.new()
	debris_material.shader = DEBRIS_SHADER
	debris_material.render_priority = -5
	add_child(node)
	var slot := {"node":node,"material":material,"debris_material":debris_material,"active":false,"elapsed":0.0,"life":1.0,"kind":"","serial":0,"origin":Vector3.ZERO,"strength":1.0,"color":Color.WHITE}
	_slots.append(slot)
	return slot

func _debris_mesh(kind: String) -> ArrayMesh:
	if _particle_meshes.has(kind):
		return _particle_meshes[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var settling := kind == "defeat"
	for index in (8 if settling else 7):
		var angle := float(index)*2.399963
		var speed := (.20 if settling else .72)+float(index%3)*(.10 if settling else .24)
		var velocity := Vector3(cos(angle)*speed,.16+float(index%3)*.08 if settling else .45+float(index%3)*.20,sin(angle)*speed)
		var size := .022+float(index%3)*.009
		var color := Color("b39c6e") if settling else (Color("dbc695") if index%3==0 else Color("795334"))
		color.a = .65 if settling else .82
		var points := [Vector3(-size,0,-size*.45),Vector3(size*.7,0,-size*.3),Vector3(0,size*1.8,0),Vector3(0,0,size*.7)]
		for triangle in [[0,1,2],[1,3,2],[3,0,2],[0,3,1]]:
			for vertex in triangle:
				_debris_vertex(surface,points[vertex],velocity,0.0,color)
	if not settling:
		# A filled, world-sized140ms contact accent. Camera-facing orientation
		# is shader-only; ordinary scene depth still hides a blocked shell.
		for edge in [true,false]:
			var color:=Color(.27,.17,.09,.98) if edge else Color(1.0,.97,.85,.99)
			for index in 8:
				var angle:=float(index)*PI/4.0+.18
				var next_angle:=float(index+1)*PI/4.0+.18
				var radius:float=(.18 if index%2==0 else .088)* (1.0 if edge else .72)
				var next_radius:float=(.18 if (index+1)%2==0 else .088)* (1.0 if edge else .72)
				for point in [Vector3.ZERO,Vector3(cos(angle),sin(angle),0)*radius,Vector3(cos(next_angle),sin(next_angle),0)*next_radius]:
					_debris_vertex(surface,point,Vector3.ZERO,-1.0,color)

	else:
		# Low, translucent hexagons settle across the soil without hiding feet.
		for index in 4:
			var angle := float(index)*TAU/4.0+.4
			var centre := Vector3(cos(angle)*.09,0,sin(angle)*.09)
			var velocity := Vector3(cos(angle)*.23,.04,sin(angle)*.23)
			for side in 6:
				for point in [centre,centre+Vector3(cos(float(side)*TAU/6.0),0,sin(float(side)*TAU/6.0))*.14,centre+Vector3(cos(float(side+1)*TAU/6.0),0,sin(float(side+1)*TAU/6.0))*.14]:
					_debris_vertex(surface,point,velocity,2.0,Color(.58,.51,.37,.18))
	var mesh := surface.commit()
	_particle_meshes[kind] = mesh
	return mesh

func _debris_vertex(surface: SurfaceTool,point: Vector3,velocity: Vector3,kind: float,color: Color) -> void:
	surface.set_normal(Vector3.UP)
	surface.set_color(color)
	surface.set_uv(Vector2(velocity.y,kind))
	surface.set_uv2(Vector2(velocity.x,velocity.z))
	surface.add_vertex(point)

func _make_mesh(kind: String, strength: float, payload: Dictionary) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind in ["slash","boss_phase","upgrade","pickup","hurt"]:
		var radius := float(payload.get("reach",1.35)) if kind=="slash" else (.45 if kind in ["pickup","hurt"] else 1.1)
		var half_arc := deg_to_rad(float(payload.get("arc_degrees",151.045))*.5) if kind=="slash" else PI
		var width := .09 if kind=="slash" else .045
		for index in 24:
			var a := -half_arc+float(index)/24.0*half_arc*2.0
			var b := -half_arc+float(index+1)/24.0*half_arc*2.0
			var p := Vector3(sin(a),0,-cos(a))
			var q := Vector3(sin(b),0,-cos(b))
			_quad(surface,p*(radius-width),p*radius,q*radius,q*(radius-width))
	if kind in ["hit","defeat","upgrade","pickup"]:
		for index in (6 if kind=="hit" else 10):
			var angle := float(index)*2.399963
			var radius := (.1+float(index%4)*.1)*strength
			var at := Vector3(cos(angle)*radius,float(index%3)*.08,sin(angle)*radius)
			var size := .035+float(index%3)*.015
			_quad(surface,at+Vector3(-size,0,0),at+Vector3(0,size*1.7,0),at+Vector3(size,0,0),at+Vector3(0,-size*.7,0))
	return surface.commit()

func _quad(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	for point in [a,b,c,a,c,d]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(point)

func _process(delta: float) -> void:
	if (is_inside_tree() and get_tree().paused) or not is_finite(delta) or delta<=0:
		return
	_trail_clock += delta
	if _player_ref != null:
		if not _trail_source_valid(_source_player()):
			_clear_trail()
		elif not is_instance_valid(_trail_skeleton):
			_sample_trail()
	while not _trail_samples.is_empty() and _trail_clock-float(_trail_samples[0].born) >= TRAIL_LIFE:
		_trail_samples.pop_front()
	if is_instance_valid(_trail_node):
		_rebuild_trail()
	for slot in _slots:
		if not slot.active:
			continue
		slot.elapsed += delta
		var progress := clampf(float(slot.elapsed)/float(slot.life),0,1)
		if progress>=1:
			slot.active = false
			slot.node.visible = false
			continue
		if slot.kind in ["hit","defeat"]:
			slot.debris_material.set_shader_parameter("age",slot.elapsed)
			continue
		var color: Color = slot.color
		color.a = (1.0-progress)*(.72 if slot.kind=="slash" else .65)
		slot.material.albedo_color = color
		if slot.kind=="slash":
			slot.node.scale = Vector3.ONE*(.98+.06*progress)
		else:
			slot.node.scale = Vector3.ONE*(1.0+progress*(1.6 if slot.kind=="boss_phase" else .9))
			if slot.kind not in ["boss_phase","hurt"]:
				slot.node.position.y = slot.origin.y+.28+progress*.55

func active_count() -> int:
	var count := 0
	for slot in _slots:
		count += int(slot.active)
	return count

func lifetime_snapshot() -> Array:
	var values: Array = []
	for slot in _slots:
		if slot.active:
			values.append([slot.serial,slot.elapsed,slot.life])
	return values

func clear_all() -> void:
	_clear_trail()
	for slot in _slots:
		slot.active = false
		slot.node.visible = false
