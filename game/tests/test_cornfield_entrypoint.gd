extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:
	var entry:=str(ProjectSettings.get_setting("application/run/main_scene",""))
	check(entry=="res://levels/cornfield.tscn","default project launch selects the reviewed first chapter")
	var scene:PackedScene=load(entry)
	check(scene!=null,"default entry is a valid packed scene")
	if scene!=null:
		var node:=scene.instantiate()
		check(node.get_script().resource_path=="res://scripts/cornfield/game.gd","default entry uses the three-node chapter rather than the old prototype")
		node.free()
	check(ResourceLoader.exists("res://levels/full.tscn"),"older source scene remains available explicitly")
	print("CORNFIELDS_ENTRYPOINT %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
