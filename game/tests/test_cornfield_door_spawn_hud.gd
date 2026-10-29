extends SceneTree
const World=preload("res://scripts/cornfield/room_world.gd")
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
const Director=preload("res://scripts/cornfield/encounter_director.gd")
const UI=preload("res://scripts/cornfield/game_ui.gd")
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)
func screen_rect(control:Control)->Rect2:
	return control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)
func ground_point(camera:Camera3D,screen:Vector2)->Vector3:
	var origin:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen)
	return origin+direction*(-origin.y/direction.y)
func scene(template:int,sides:Array,stage:int)->Dictionary:
	var room:=Catalog.make_template(template);room.doors={}
	for side:String in sides:room.doors[side]=side
	room.entry_position=Catalog.door_position(sides[0],room.size)+Catalog.door_inward(sides[0])*4
	room.main_route=PackedVector3Array([room.entry_position,Vector3(room.size.x*.5,0,room.size.y*.5),Catalog.door_position(sides[1],room.size)+Catalog.door_inward(sides[1])*6])
	room.kind="combat";room.encounter="swarm";room.content_revision=3;room.melee_fallback="beetle"
	var world:=World.new();root.add_child(world);world.build(room)
	var player:=CharacterBody3D.new();world.add_child(player);player.position=world.definition.entry_position
	var camera:=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=15;camera.make_current()
	var ui:=UI.new();root.add_child(ui);ui.update_minimap({"visible":true})
	var director:=Director.new();world.add_child(director);director.configure(world,player,world.definition,stage);director.set_physics_process(false)
	if director.has_method("set_spawn_visibility_ui"):director.call("set_spawn_visibility_ui",ui)
	var target:Vector3=player.position+Vector3.UP*.4
	camera.position=target+Vector3(15,19,15);camera.look_at(target)
	var camera_owner:Node3D
	if OS.get_environment("DOOR_STATIC_PRODUCTION_CAMERA")=="1":
		camera_owner=Game.new();camera_owner.player=player;camera_owner.camera=camera;camera_owner.camera_target=target
		camera_owner._follow_camera(10.0)
	return {"world":world,"player":player,"camera":camera,"ui":ui,"director":director,"camera_owner":camera_owner}
func cleanup(s:Dictionary)->void:
	if is_instance_valid(s.camera_owner):s.camera_owner.free()
	s.world.free();s.ui.free()
func run()->void:
	for extent:Vector2i in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(960,800)]:
		root.size=extent;root.content_scale_size=extent
		var s:=scene(0,["west","east"],3)
		s.player.position=Vector3(s.world.definition.size.x*.5,0,s.world.definition.size.y*.5)
		var target:Vector3=s.player.position+Vector3.UP*.4
		s.camera.position=target+Vector3(15,19,15);s.camera.look_at(target)
		await process_frame;await physics_frame;await physics_frame
		check(s.ui.has_method("spawn_occlusion_rects"),"actual UI exposes visible canvas-transformed occlusion rectangles")
		check(s.director.has_method("set_spawn_visibility_ui"),"director accepts the live UI visibility source")
		var panels:Array=[]
		for child in s.ui.base.get_children():
			if child is Panel:panels.append(child)
		var bottom:Control=panels[-1]
		for ui_scale:float in [1.0,.85]:
			s.ui._fit_canvas();s.ui.scale*=ui_scale
			if ui_scale<1:s.ui.offset+=Vector2(13,9)
			var bottom_rect:=screen_rect(bottom)
			var screen:=Vector2(bottom_rect.get_center().x,bottom_rect.position.y-2)
			var point:=ground_point(s.camera,screen)
			check(not bottom_rect.has_point(s.camera.unproject_position(point)),"partial-HUD probe centre is outside actual bottom panel")
			check(not s.director._warning_visible(point),"complete .4m spawn disc cannot cross actual scaled bottom HUD %s/%.2f"%[extent,ui_scale])
			if s.director.has_method("_spawn_disc_screen_rect"):
				check(not bool(s.director.call("_warning_visible",point,.8)),"complete .8m footprint also rejects actual HUD overlap")
			bottom.hide()
			check(s.director._warning_visible(point),"hiding the actual bottom panel restores otherwise clear projected space")
			bottom.show()
			var clear_point:=ground_point(s.camera,Vector2(extent)*.5)
			check(s.director._warning_visible(clear_point),"unoccluded central field remains eligible")
			var mini_rect:=screen_rect(s.ui.minimap)
			var mini_point:=ground_point(s.camera,mini_rect.get_center())
			check(not s.director._warning_visible(mini_point),"visible minimap excludes its actual transformed footprint")
			s.ui.minimap.hide()
			check(s.director._warning_visible(mini_point),"hidden minimap does not leave a stale exclusion")
			s.ui.minimap.show()
			s.ui.update_boss({"title":"visibility probe","hp":50.0,"max_hp":100.0})
			var boss_point:=ground_point(s.camera,screen_rect(s.ui.boss_health).get_center())
			check(not s.director._warning_visible(boss_point),"visible boss children are masked beyond zero-size parent bounds")
			s.ui.update_boss({})
			check(s.director._warning_visible(boss_point),"hidden boss children leave no stale occlusion")
			if s.ui.has_method("spawn_occlusion_rects"):
				check(s.ui.call("spawn_occlusion_rects").has(bottom_rect),"HUD rectangles include the actual canvas scale and offset")
			var edge:=ground_point(s.camera,Vector2(18,float(extent.y)*.5))
			check(not s.director._warning_visible(edge),"full disc obeys existing16px viewport inset even when its centre fits")
		cleanup(s);await process_frame
	# Actual west-to-north first-fixture geometry and unchanged game camera.
	# Full density tiers must still reserve and really birth under the live HUD.
	for extent:Vector2i in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(960,800)]:
		root.size=extent;root.content_scale_size=extent
		for stage in [1,2,3]:
			var s:=scene(9,["west","north"],stage)
			await process_frame;await physics_frame;await physics_frame
			var planned:int=s.director.metrics().planned
			for attempt in 150:
				s.director._physics_process(.2)
				if not s.director._warnings.is_empty():break
			var expected:int=[8,10,12][stage-1]
			check(s.director.metrics().reserved==expected,"full%d legal visible HUD-safe warning fits %s"%[expected,extent])
			if not s.director._warnings.is_empty():
				var warning:Dictionary=s.director._warnings[0]
				check(warning.records.size()==expected and is_equal_approx(warning.remaining,.8),"HUD gate retains complete group and full warning duration")
				for record:Dictionary in warning.records:
					check(s.world.is_in_spawn_domain(record.point,.34) and s.director._warning_visible(record.point),"reserved full disc remains legal and visible")
					if s.director.has_method("_spawn_disc_screen_rect") and s.ui.has_method("spawn_occlusion_rects"):
						var footprint:Rect2=s.director.call("_spawn_disc_screen_rect",s.camera,record.point,.4)
						for rect:Rect2 in s.ui.call("spawn_occlusion_rects"):check(not footprint.intersects(rect),"complete projected disc does not intersect any visible HUD rectangle")
				s.director._tick_spawn_warnings(.8)
				for enemy in s.director.enemies:enemy.set_physics_process(false)
				check(s.director.metrics().spawned==expected and s.director.metrics().planned==planned,"HUD-safe warning actually births every promised actor without changing budget")
			cleanup(s);await process_frame
	# Observe current mid-window behavior separately from admission/expiry safety.
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
	var window_scene:=scene(9,["west","north"],1)
	await process_frame;await physics_frame;await physics_frame
	for attempt in 150:
		window_scene.director._physics_process(.2)
		if not window_scene.director._warnings.is_empty():break
	if not window_scene.director._warnings.is_empty():
		var bottom:Control
		for child in window_scene.ui.base.get_children():
			if child is Panel:bottom=child
		var saved:=bottom.position
		var marked:Vector3=window_scene.director._warnings[0].records[0].point
		var centre:Vector2=window_scene.camera.unproject_position(marked)
		bottom.position=window_scene.ui.base.get_global_transform_with_canvas().affine_inverse()*centre-bottom.size*.5
		var hidden:bool=not window_scene.director._warning_visible(marked)
		window_scene.director._tick_spawn_warnings(.2)
		var during:int=window_scene.director.metrics().reserved
		bottom.position=saved
		window_scene.director._tick_spawn_warnings(.6)
		print("HUD_WINDOW_OBSERVATION hidden_midwindow=",hidden," reserved_after_hidden_0.2s=",during," spawned_after_restore=",window_scene.director.metrics().spawned," policy=observation_only")
		check(window_scene.director.metrics().spawned in [0,8] and window_scene.director.metrics().reward_paid==0,"HUD transition cannot partially spawn or pay an unearned reward")
	cleanup(window_scene)
	print("DOOR_SPAWN_HUD checks=%d failures=%d; full8/10/12,3aspects,actualCanvasLayer transforms"%[checks,failures]);quit(1 if failures else 0)
