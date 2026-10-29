extends "res://scripts/cornfield/room_world.gd"
const Landmarks = preload("res://scripts/modular/rural_landmarks.gd")
var _return_sign: Label3D
var _return_open := false
const ModuleDomain = preload("res://scripts/modular/modular_spawn_domain.gd")
func _init() -> void:
	field_parcels_enabled=false
	field_edges_enabled=false
func _normalize_room_anchors() -> void:
	# Fixed module centerline must not be replaced by pathfinding shortcuts.
	pass
func _build_spawn_domain() -> void:
	var started := Time.get_ticks_usec()
	spawn_domain_generation+=1
	_spawn_domain=ModuleDomain.new()
	_spawn_domain.build(self)
	spawn_domain_build_usec=Time.get_ticks_usec()-started
func uses_spawn_domain() -> bool:return true
func _build_field_details() -> void:
	var flag_scene:PackedScene=load("res://assets/modular/exit_flag.glb")
	var flag:Node3D=flag_scene.instantiate()
	flag.name="ExitFlag";add_child(flag)
	var route:PackedVector3Array=definition.main_route
	var incoming:Vector3=(route[-1]-route[-2]).normalized()
	flag.position=definition.reward_position+incoming.cross(Vector3.UP)*1.4
	flag.rotation.y=PI*.25
	Landmarks.build(self)
	_return_sign=Label3D.new();_return_sign.name="ReturnStatus"
	_return_sign.position=definition.reward_position+Vector3(0,1.9,0)
	_return_sign.font_size=32;_return_sign.pixel_size=.007
	_return_sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_return_sign)
	set_return_open(false)
	# Visual landmark only: no new collider, navigation or completion authority.

func set_return_open(value: bool) -> void:
	if not is_instance_valid(_return_sign):return
	if _return_open==value and not _return_sign.text.is_empty():return
	_return_open=value
	_return_sign.text="虫群散了 · 到红旗边回家" if value else "归路 · 清理虫群后回家"
	_return_sign.modulate=Color("f7dfa0") if value else Color("edc6ac")
func _build_trails() -> void:
	var ground := get_node("Ground")
	for i in definition.corridor_rects.size():
		var rect: Rect2 = definition.corridor_rects[i]
		var plane := PlaneMesh.new();plane.size=rect.size
		var visual := MeshInstance3D.new();visual.name="ModuleRoad_%d"%i
		visual.mesh=plane
		visual.position=Vector3(rect.get_center().x,.012,rect.get_center().y)
		visual.material_override=_trail_material()
		ground.add_child(visual)
func _build_obstacles() -> void:
	var terrain := Node3D.new();terrain.name="Terrain";add_child(terrain)
	for item: Dictionary in _obstacles:
		var rect: Rect2 = item.rect
		var body := _solid_box(terrain,Vector3(rect.get_center().x,.625,rect.get_center().y),Vector3(rect.size.x,1.25,rect.size.y),"corn",Color("747a38"))
		body.name=item.id
		var volume: MeshInstance3D = body.get_node("Volume")
		volume.scale.y=.16/1.25;volume.position.y=-.625+.08
		volume.remove_from_group("room_3d_cuttable")
		volume.material_override=_bed_material("corn")
		_add_box_visual(body,Vector3(0,-.625+.035,0),Vector3(rect.size.x,.07,rect.size.y),_material("soil_rim",Color("51482e")))
		# Crop only the visuals around scenery; keep the exact original collider.
		var pieces: Array[Rect2]=[rect]
		for region: Dictionary in definition.module_regions:
			var next: Array[Rect2]=[]
			for piece: Rect2 in pieces:next.append_array(Landmarks.without_plot(piece,region.landmark.rect))
			pieces=next
		for index in pieces.size():
			var piece: Rect2=pieces[index]
			var patch := Node3D.new();patch.name="CornPatch_%d"%index
			patch.position=Vector3(piece.get_center().x,.625,piece.get_center().y)
			terrain.add_child(patch)
			_add_asset_grid(patch,"corn","CornBatch",piece.size,1.25,1.8)
