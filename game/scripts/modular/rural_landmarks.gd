extends RefCounted
## Scenic props stay inside existing blocked field; never spawn or collision authority.
const SIGN_PATH := "res://assets/environment/r48/rural-wayfinding-sign-v001.glb"
const SIGN_SCALE := .60
const TITLES := ["村口土路", "老井田头", "晒粮地边", "红砖院角", "农具田埂"]
const KINDS := ["village", "well", "grain", "brick", "tools"]

static func describe(index: int, count: int, center: Vector3) -> Dictionary:
	var kind: String = "home" if index==count-1 else KINDS[index]
	var title: String = "红旗归路" if index==count-1 else TITLES[index]
	var corners: Array[Vector2] = [Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1),Vector2(1,1)]
	var point: Vector2 = Vector2(center.x,center.z)+corners[index%4]*5.8
	return {"kind":kind,"title":title,"rect":Rect2(point-Vector2.ONE*1.6,Vector2.ONE*3.2)}

static func build(world: Node3D) -> void:
	var root := Node3D.new();root.name="RuralLandmarks";world.add_child(root)
	for region: Dictionary in world.definition.module_regions:
		var detail: Dictionary=region.landmark
		var plot: Rect2=detail.rect
		var point := Vector3(plot.get_center().x,.17,plot.get_center().y)
		var holder := Node3D.new();holder.name="Landmark_%02d_%s"%[region.index,detail.kind];root.add_child(holder)
		holder.set_meta("blocked_footprint",plot)
		# Keep the original dark field bed exposed; a bright square reads as a warning.
		match str(detail.kind):
			"well":
				world._add_farm_prop_at(holder,"farm-well","OldWell",point,Vector3(2.7,1.45,2.7))
			"home":
				_build_return_sign(world,holder,point)
			"grain":
				var rack_path := "res://assets/environment/r48/corn-drying-rack-v001.glb"
				var rack_scene: PackedScene=load(rack_path)
				if rack_scene!=null:
					# C's accepted GLB is centered, grounded, and fits the existing blocked plot at scale 1.
					var rack: Node3D=rack_scene.instantiate();rack.name="CornDryingRack"
					rack.position=point;holder.add_child(rack)
					rack.set_meta("scenic_only",true)
					for mesh: MeshInstance3D in rack.find_children("*","MeshInstance3D",true,false):
						mesh.add_to_group("room_3d_cuttable")
				else:
					push_warning("Rural drying rack missing: "+rack_path)
					world._add_farm_prop_at(holder,"grain-sack-stack","GrainSacks",point,Vector3(2.8,1.15,2.8))
			"tools":
				world._add_farm_prop_at(holder,"farm-tool-bundle","FarmTools",point,Vector3(2.4,1.45,2.4))
			"brick", "village":
				world._module_line(holder,"broken-red-brick-wall",point,2.8,.65,1.2,0.0,"VillageWall")
				world._add_farm_prop_at(holder,"farm-tool-bundle","LeaningTools",point+Vector3(0,0,.9),Vector3(1.1,.95,.8))

static func sign_yaw(home_direction: Vector3) -> float:
	# Authored barn arrow is local -X; corn arrow is +X.
	return atan2(home_direction.z,-home_direction.x)

static func _build_return_sign(world: Node3D, holder: Node3D, point: Vector3) -> void:
	var scene: PackedScene=load(SIGN_PATH)
	if scene==null:
		push_warning("Rural return sign missing: "+SIGN_PATH)
		world._add_farm_prop_at(holder,"grain-sack-stack","GrainSacks",point,Vector3(2.8,1.15,2.8))
		return
	var route: PackedVector3Array=world.definition.main_route
	var home_direction: Vector3=(route[-1]-route[-2]).normalized()
	var sign: Node3D=scene.instantiate()
	sign.name="RuralReturnSign"
	sign.position=point
	sign.scale=Vector3.ONE*SIGN_SCALE
	sign.rotation.y=sign_yaw(home_direction)
	sign.set_meta("home_direction",home_direction)
	sign.set_meta("scenic_only",true)
	holder.add_child(sign)
	for mesh: MeshInstance3D in sign.find_children("*","MeshInstance3D",true,false):
		mesh.add_to_group("room_3d_cuttable")

static func without_plot(rect: Rect2, plot: Rect2) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if not rect.intersects(plot):
		result.append(rect);return result
	var cut := rect.intersection(plot)
	for piece: Rect2 in [Rect2(rect.position,Vector2(rect.size.x,cut.position.y-rect.position.y)),Rect2(Vector2(rect.position.x,cut.end.y),Vector2(rect.size.x,rect.end.y-cut.end.y)),Rect2(Vector2(rect.position.x,cut.position.y),Vector2(cut.position.x-rect.position.x,cut.size.y)),Rect2(Vector2(cut.end.x,cut.position.y),Vector2(rect.end.x-cut.end.x,cut.size.y))]:
		if piece.size.x>.001 and piece.size.y>.001:result.append(piece)
	return result
