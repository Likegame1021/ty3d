extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func _run() -> void:
	root.size=Vector2i(1280,800)
	var game:=Game.new();game.test_mode=true
	game.save_path="user://qa_render_budget_%d.json"%Time.get_ticks_usec()
	root.add_child(game);await process_frame
	check(game.camera.size==15.0 and is_equal_approx(game.camera.near,.1),"gameplay framing and foreground clipping stay unchanged")
	check(game.camera.far<=55.0,"fixed-camera shadow frustum excludes invisible distant space")
	for screen in [Vector2.ZERO,Vector2(1280,0),Vector2(0,800),Vector2(1280,800)]:
		var origin:Vector3=game.camera.project_ray_origin(screen)
		var ray:Vector3=game.camera.project_ray_normal(screen)
		var ground:Vector3=Plane(Vector3.UP,-.2).intersects_ray(origin,ray)
		var depth:float=(ground-game.camera.global_position).dot(-game.camera.global_basis.z)
		check(depth+8.0<game.camera.far,"all visible ground retains eight-metre far-plane safety margin")
	var lights:=game.find_children("*","DirectionalLight3D",true,false)
	check(lights[0].shadow_enabled and lights[0].directional_shadow_mode==DirectionalLight3D.SHADOW_ORTHOGONAL,"one full shadow projection retained for orthographic camera")
	var projectile:=Director.HostileProjectile.new()
	projectile.payload={}
	root.add_child(projectile);projectile.set_physics_process(false)
	var visual:MeshInstance3D=projectile.get_child(0)
	var mesh:SphereMesh=visual.mesh
	check(mesh.get_faces().size()/3<=320,"tiny projectiles use bounded geometry instead of4224triangles each")
	check(is_equal_approx(mesh.radius,.11) and is_equal_approx(mesh.height,.22),"projectile visual size unchanged")
	check(visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"projectile contact shadows preserved")
	projectile.queue_free();game.queue_free();await process_frame
	print("CORNFIELDS_RENDER_BUDGET %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
