extends Node3D
## A modest departure clearing for this map prototype, not the finished village.
const SIZE := Vector2(24,18)
const SPAWN := Vector3(12,0.05,12)
var player: Node3D
var npcs: Array[Dictionary] = []

func install(actor: Node3D) -> void:
	player=actor
	_box(Vector3(12,-0.18,9),Vector3(24,0.3,18),Color("839264"))
	# Broad packed-earth track connects the preparation nook to the field gate.
	_patch(Vector3(12,-0.015,9),Vector2(5.2,18),Color("b9a176"))
	_patch(Vector3(7,-0.012,11),Vector2(8,4),Color("b7a077"))
	_patch(Vector3(5,-0.01,5),Vector2(7.5,5.5),Color("a99570"))
	_asset("meshy/shed",Vector3(5,0,4.5),3.0,Vector2(5,3.2),0.0)
	_asset("meshy/cart",Vector3(7.2,0,5.2),1.4,Vector2(1.7,1.1),-0.35)
	_asset("haystack",Vector3(3.0,0,8),1.25,Vector2(1.4,1.3),0.3)
	_asset("crate",Vector3(6.6,0,10.8),0.7,Vector2(0.75,0.75),0.1)
	_asset("jar",Vector3(7.5,0,10.7),0.6,Vector2(0.5,0.5),0.0)
	for at in [Vector3(2.0,0,14.3),Vector3(21.4,0,14.5),Vector3(21.5,0,3.5)]:
		_asset("tree",at,4.0,Vector2(0.7,0.7),at.x*0.2)
	for x in [17.0,18.2,19.4,20.6]:
		for z in [4.8,6.0,7.2]:
			_asset("corn",Vector3(x,0,z),1.5,Vector2.ZERO,x+z)
	for at in [Vector3(2,0,11),Vector3(4,0,15.6),Vector3(18,0,13),Vector3(20,0,10)]:
		_asset("grass",at,0.45,Vector2.ZERO,at.x)
	for x in range(2,24,3):
		_asset("fence",Vector3(x,0,17),0.9,Vector2.ZERO,0)
		if x<9 or x>14:
			_asset("fence",Vector3(x,0,1),0.9,Vector2.ZERO,0)
	for z in range(3,17,3):
		_asset("fence",Vector3(1,0,z),0.9,Vector2.ZERO,PI*0.5)
		_asset("fence",Vector3(23,0,z),0.9,Vector2.ZERO,PI*0.5)
	# Invisible outer collision stays outside the visual fence and main track.
	_collider(Vector3(12,0.75,-0.2),Vector3(24,1.5,0.4))
	_collider(Vector3(12,0.75,18.2),Vector3(24,1.5,0.4))
	_collider(Vector3(-0.2,0.75,9),Vector3(0.4,1.5,18))
	_collider(Vector3(24.2,0.75,9),Vector3(0.4,1.5,18))
	_sign(Vector3(12,0,8.3),Color("9b744a"))
	_add_station({"id":"guide","name":"田埂路牌","role":"向玉米地出发","action":"start","label":"挑选一条田埂","dialogue":["前面就是玉米地。","准备好了，选择下一片田地开始探索。"]},Vector3(12,0,8.3))
	_add_station({"id":"prepare","name":"行前准备","role":"选择本趟武器","action":"prepare","label":"整理出发装备","dialogue":["树枝和玉米枪都放在准备处。","在出发前选好这一趟的武器，再沿田埂进地。"]},Vector3(7,0,11))
	_label("村口原型 · 出发准备区",Vector3(12,2.8,3.2),32)
	_label("玉米地 ↑",Vector3(12,1.5,1.1),26)

func nearest_npc(point: Vector3) -> Dictionary:
	var best: Dictionary={}
	var distance:=2.3
	for npc in npcs:
		var value: float=point.distance_to(npc.position)
		if value<distance:
			distance=value
			best=npc.info
	return best

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	for npc in npcs:
		var nearby: bool=player.global_position.distance_to(npc.position)<2.3
		npc.label.modulate=Color("fff1bb") if nearby else Color("e7d9ae")
		npc.label.text=("E · " if nearby else "")+str(npc.info.name)+" · "+str(npc.info.role)

func _add_station(info: Dictionary, at: Vector3) -> void:
	var label:=_label(str(info.name)+" · "+str(info.role),at+Vector3.UP*1.7,25)
	npcs.append({"info":info,"position":at,"label":label})

func _sign(at: Vector3, color: Color) -> void:
	_box(at+Vector3(0,0.62,0),Vector3(0.12,1.24,0.12),Color("6f573c"))
	_box(at+Vector3(0,1.15,0),Vector3(1.2,0.48,0.12),color)

func _patch(at: Vector3, extent: Vector2, color: Color) -> void:
	var mesh:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=extent
	mesh.mesh=plane
	mesh.position=at
	mesh.material_override=_material(color)
	add_child(mesh)

func _asset(id: String, at: Vector3, height: float, footprint: Vector2, turn: float) -> void:
	var scene: PackedScene=load("res://assets/environment/%s.glb" % id)
	var model: Node3D=scene.instantiate()
	var anchor:=Node3D.new()
	anchor.name=id.replace("/","_").capitalize()
	anchor.position=at
	anchor.rotation.y=turn
	add_child(anchor)
	anchor.add_child(model)
	var bounds:=AABB()
	var found:=false
	for node in model.find_children("*","MeshInstance3D",true,false):
		var local: Transform3D=model.global_transform.affine_inverse()*node.global_transform
		var box: AABB=local*node.get_aabb()
		bounds=bounds.merge(box) if found else box
		found=true
	if found and bounds.size.y>0.001:
		var ratio:=height/bounds.size.y
		model.scale=Vector3.ONE*ratio
		model.position=Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)*ratio
	if footprint!=Vector2.ZERO:
		var body:=_collider(at+Vector3(0,height*0.4,0),Vector3(footprint.x,height*0.8,footprint.y))
		body.rotation.y=turn

func _collider(at: Vector3, extent: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.position=at
	body.collision_layer=1
	body.collision_mask=0
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=extent
	collision.shape=shape
	body.add_child(collision)
	add_child(body)
	return body

func _box(at: Vector3, extent: Vector3, color: Color) -> StaticBody3D:
	var body:=_collider(at,extent)
	var mesh:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=extent
	mesh.mesh=box
	mesh.material_override=_material(color)
	body.add_child(mesh)
	return body

func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=0.95
	return material

func _label(value: String, at: Vector3, font_size: int=24) -> Label3D:
	var label:=Label3D.new()
	label.text=value
	label.position=at
	label.font_size=font_size
	label.pixel_size=1.0/64.0
	label.outline_size=5
	label.outline_modulate=Color("314631")
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
	label.font=font
	add_child(label)
	return label
