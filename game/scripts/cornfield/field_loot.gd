extends StaticBody3D
## Room-local breakable geometry. Damage units match the preserved 3D weapons.
signal broken(id: String, position: Vector3, drop: String)

var prop_id := ""
var drop := ""
var hp := 2
var destroyed := false
var active := true
var collision_radius := 0.34

func configure(id: String, kind: String, loot: String) -> void:
	prop_id = id
	drop = loot
	collision_layer = 5
	collision_mask = 0
	add_to_group("full_enemies")
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	collision_radius = 0.34 if kind != "hay" else 0.45
	shape.radius = collision_radius
	shape.height = 0.7
	collider.shape = shape
	collider.position.y = 0.35
	add_child(collider)
	var asset := "haystack" if kind == "hay" else (kind if kind in ["jar","crate"] else "crate")
	var scene: PackedScene = load("res://assets/environment/%s.glb" % asset)
	var model: Node3D = scene.instantiate()
	model.name = "PropGeometry"
	add_child(model)
	_fit_model(model,0.85 if kind == "hay" else 0.7)

func _fit_model(model: Node3D, height: float) -> void:
	var bounds := AABB()
	var found := false
	for node in model.find_children("*","MeshInstance3D",true,false):
		# Room props are configured before add_child; global transforms are unavailable.
		var relative := Transform3D.IDENTITY
		var cursor: Node = node
		while cursor != model:
			if cursor is Node3D:
				relative = cursor.transform*relative
			cursor = cursor.get_parent()
		var box: AABB = relative*node.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if not found or bounds.size.y<0.001:
		return
	var ratio := height/bounds.size.y
	model.scale=Vector3.ONE*ratio
	model.position=Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)*ratio

func receive_hit(_direction: Vector3 = Vector3.ZERO) -> void:
	receive_projectile(1)

func receive_projectile(amount: int) -> void:
	if destroyed or amount<=0:
		return
	hp=maxi(0,hp-amount)
	if hp>0:
		return
	destroyed=true
	active=false
	collision_layer=0
	broken.emit(prop_id,global_position,drop)
	queue_free()

class Pickup extends Node3D:
	signal collected(id: String, kind: String)
	var id := ""
	var kind := ""
	var player: Node3D
	var timer := 0.0
	var done := false
	var visual: Node3D

	func setup(identifier: String, value: String, target: Node3D) -> void:
		id=identifier
		kind=value
		player=target
		visual=Node3D.new()
		visual.name="PickupGeometry"
		add_child(visual)
		if kind=="coins":
			var coin:=CylinderMesh.new()
			coin.top_radius=0.16
			coin.bottom_radius=0.16
			coin.height=0.055
			coin.radial_segments=12
			_part(coin,Vector3.ZERO,Color("efc35e")).rotation.x=PI*0.5
		elif kind=="heal":
			var bottle:=CylinderMesh.new()
			bottle.top_radius=0.105
			bottle.bottom_radius=0.115
			bottle.height=0.3
			bottle.radial_segments=10
			_part(bottle,Vector3.ZERO,Color("61b58b"))
			var cap:=CylinderMesh.new()
			cap.top_radius=0.075
			cap.bottom_radius=0.075
			cap.height=0.05
			_part(cap,Vector3(0,0.175,0),Color("f4e4b5"))
			var band:=BoxMesh.new()
			band.size=Vector3(0.15,0.085,0.03)
			_part(band,Vector3(0,0,0.11),Color("fff3d3"))
		else:
			var candy:=SphereMesh.new()
			candy.radius=0.14
			candy.height=0.2
			candy.radial_segments=8
			candy.rings=4
			_part(candy,Vector3.ZERO,Color("98c598") if kind=="mint" else Color("e8a26a"))
		visual.position.y=0.33

	func _part(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
		var node:=MeshInstance3D.new()
		node.mesh=mesh
		node.position=at
		var material:=StandardMaterial3D.new()
		material.albedo_color=color
		material.roughness=0.75
		node.material_override=material
		visual.add_child(node)
		return node

	func _physics_process(delta: float) -> void:
		if done or not is_instance_valid(player) or visual==null:
			return
		timer+=delta
		visual.position.y=0.33+sin(timer*5)*0.07
		visual.rotation.y+=delta*1.2
		var destination:=player.global_position+Vector3.UP*0.15
		if kind!="heal" and timer>0.3:
			global_position=global_position.move_toward(destination,delta*(4+timer*12))
		var distance:=Vector2(global_position.x-player.global_position.x,global_position.z-player.global_position.z).length()
		if distance<0.65 and (kind!="heal" or float(player.hp)<float(player.max_hp)):
			done=true
			collected.emit(id,kind)
			queue_free()
