extends SceneTree
## Real imported assets, all-part retention, footprint and obstacle regression.
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const World = preload("res://scripts/cornfield/room_world.gd")
const PREFIX := "res://assets/environment/blender/cornfield_batch_v001/"
const ASSETS := ["farm-well", "farm-tool-bundle", "grain-sack-stack"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func all_meshes(node: Node) -> Array[Node]:
	var result: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		result.push_front(node)
	return result

func run_tests() -> void:
	# The real loader must ground an imported scene on the visible .16u bed,
	# rather than burying its feet inside it. A local fixture isolates this math.
	var fixture_root := Node3D.new()
	fixture_root.position = Vector3(.3,.4,-.2)
	fixture_root.rotation.y = .37
	var fixture_mesh := MeshInstance3D.new()
	fixture_mesh.mesh = BoxMesh.new()
	fixture_mesh.position.y = .5
	fixture_root.add_child(fixture_mesh)
	fixture_mesh.owner = fixture_root
	var fixture_scene := PackedScene.new()
	fixture_scene.pack(fixture_root)
	fixture_root.free()
	World._farm_scenes["grounding-fixture"] = fixture_scene
	var fixture_world := World.new()
	var fixture_body := Node3D.new()
	fixture_body.position.y = .85
	fixture_world.add_child(fixture_body)
	fixture_world._add_farm_props(fixture_body,"grounding-fixture",Vector2(4,3),1.7)
	var fixture_prop: Node3D = fixture_body.get_child(0)
	var loaded_fixture: Node3D = fixture_prop.get_child(0)
	var loaded_mesh: MeshInstance3D = loaded_fixture.get_child(0)
	var fixture_bounds: AABB = (fixture_body.transform * fixture_prop.transform * loaded_fixture.transform * loaded_mesh.transform) * loaded_mesh.get_aabb()
	var floor_y: float = fixture_bounds.position.y
	check(floor_y >= .16, "Imported props rest on top of the visible raised bed")
	check(fixture_bounds.end.y <= 1.7, "Transformed model roots fit physical height")
	fixture_world.free()
	World._farm_scenes.erase("grounding-fixture")
	for asset in ASSETS:
		check(ResourceLoader.exists(PREFIX + asset + ".glb"), "Blender GLB exists: " + asset)
	if not failures.is_empty():
		finish()
		return
	var source_counts := {}
	for asset in ASSETS:
		var scene: PackedScene = load(PREFIX + asset + ".glb")
		var model: Node3D = scene.instantiate()
		var meshes := all_meshes(model)
		check(not meshes.is_empty(), asset + " contains geometry")
		source_counts[asset] = meshes.size()
		for mesh in meshes:
			check(mesh.mesh is ArrayMesh, asset + " is a real imported Blender mesh")
			for surface in range(mesh.mesh.get_surface_count()):
				check(mesh.mesh.surface_get_material(surface) != null, asset + " retains surface material")
		check(model.find_children("*", "Camera3D", true, false).is_empty(), asset + " exports no studio camera")
		check(model.find_children("*", "Light3D", true, false).is_empty(), asset + " exports no studio lights")
		model.free()
	var seen := {}
	for index in range(Catalog.TEMPLATE_COUNT):
		var definition := Catalog.make_template(index)
		definition.doors = {"north":"n", "south":"s", "east":"e", "west":"w"}
		var world: Node3D = World.new()
		root.add_child(world)
		world.build(definition)
		await process_frame
		for obstacle in definition.obstacles:
			var asset := ""
			if obstacle.kind == "well":
				asset = "farm-well"
			elif obstacle.kind == "tools":
				asset = "farm-tool-bundle"
			elif obstacle.kind == "hay" and definition.id in ["mouse_granary", "wide_clearing"]:
				asset = "grain-sack-stack"
			if asset.is_empty():
				continue
			var body: Node3D = world.get_node("Terrain/" + obstacle.id)
			var props: Array[Node] = body.find_children("BlenderProp*", "Node3D", false, false)
			check(not props.is_empty(), definition.id + " instantiates " + asset)
			check(props.size() <= 4, definition.id + " caps complete props per island")
			seen[asset] = true
			for prop in props:
				check(prop.get_meta("asset_id", "") == asset, "Correct model selected")
				var meshes := all_meshes(prop)
				check(meshes.size() == source_counts[asset], asset + " retains every exported submesh")
				for mesh in meshes:
					var bounds: AABB = (body.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
					var extent: Vector2 = obstacle.rect.size
					check(bounds.position.x >= -extent.x*.5-.01 and bounds.end.x <= extent.x*.5+.01 and bounds.position.z >= -extent.y*.5-.01 and bounds.end.z <= extent.y*.5+.01, asset + " fits authoritative XZ collision")
					check(bounds.position.y + body.position.y >= .16, asset + " rests above visible raised bed")
					check(bounds.end.y + body.position.y <= obstacle.height + .01, asset + " stays inside physical height")
					check(mesh.is_in_group("room_3d_cuttable"), asset + " participates in actor visibility cutaway")
			check(not world.contains_ground(Vector3(obstacle.rect.get_center().x,0,obstacle.rect.get_center().y)), "Blender art does not alter collision authority")
		check(world.contains_ground(world.definition.entry_position), definition.id + " preserves safe entry")
		check(world.walkable_area >= definition.baseline_area*3.0, definition.id + " keeps required walkable size")
		world.queue_free()
		await process_frame
	check(seen.size() == 3, "All three asset families are used by the 24-room catalog")
	finish()

func finish() -> void:
	print("Cornfield Blender assets: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
