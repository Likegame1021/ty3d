extends "res://tests/test_cornfield_door_spawn_hud.gd"
## A hidden interval cannot count toward the full .8s readable warning.
func reserve(s:Dictionary)->bool:
	for attempt in 150:
		s.director._physics_process(.2)
		if not s.director._warnings.is_empty():return true
	return false
func identities(records:Array)->Array:
	var result:Array=[]
	for record:Dictionary in records:result.append([record.species,record.elite])
	return result
func positions(records:Array)->Array:
	var result:Array=[]
	for record:Dictionary in records:result.append(record.point)
	return result
func run()->void:
	for event:String in ["hud","camera","resize"]:
		root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
		var s:=scene(9,["west","north"],3)
		await process_frame;await physics_frame;await physics_frame
		check(reserve(s),"full warning exists before mid-window "+event)
		if s.director._warnings.is_empty():cleanup(s);continue
		var warning:Dictionary=s.director._warnings[0]
		var before:Dictionary=s.director.metrics()
		var original_points:Array=positions(warning.records)
		var camera_transform:Transform3D=s.camera.global_transform
		var bottom:Control
		for child in s.ui.base.get_children():
			if child is Panel:bottom=child
		var bottom_position:=bottom.position
		if event=="hud":
			var screen:Vector2=s.camera.unproject_position(warning.records[0].point)
			bottom.position=s.ui.base.get_global_transform_with_canvas().affine_inverse()*screen-bottom.size*.5
		elif event=="camera":s.camera.global_position+=Vector3(30,0,30)
		else:
			root.size=Vector2i(320,800);root.content_scale_size=Vector2i(320,800)
			await process_frame
		var hidden:=false
		for record:Dictionary in warning.records:
			if not s.director._warning_screen_visible(record.point,.4):hidden=true
		check(hidden,"actual "+event+" transition hides at least one complete projected mark")
		s.director._tick_spawn_warnings(.2)
		check(s.director.metrics().reserved==0 and s.director.metrics().spawned==0,"mid-window "+event+" hiding atomically cancels all12 before expiry")
		check(s.director.metrics().planned==before.planned and s.director.metrics().reward_paid==0 and not s.director.is_complete(),"hidden warning preserves all owed actors and rewards")
		check(positions(warning.records)==original_points,"existing world-space warning positions never follow "+event)
		bottom.position=bottom_position;s.camera.global_transform=camera_transform
		root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
		await process_frame
		# Let the original expiry time pass: merely restoring visibility must not
		# resurrect the old warning or count its hidden portion as readable time.
		s.director._tick_spawn_warnings(.6)
		check(s.director.metrics().spawned==0,"restore after hidden interval cannot birth the cancelled warning")
		if s.director.metrics().spawned>0:cleanup(s);continue
		check(reserve(s),"return to stable visible camera resumes owed group after "+event)
		if not s.director._warnings.is_empty():
			var retry:Dictionary=s.director._warnings[0]
			check(retry.segment==warning.segment and retry.group==warning.group and identities(retry.records)==identities(warning.records),"readability retry retains complete original group and roster")
			check(is_equal_approx(retry.remaining,.8),"readability retry receives a fresh full .8s")
			var fixed:Array=positions(retry.records)
			s.director._tick_spawn_warnings(.79)
			check(s.director.metrics().spawned==0 and positions(retry.records)==fixed,"new warning remains fixed and cannot resolve at .79s")
			s.director._tick_spawn_warnings(.01)
			for enemy in s.director.enemies:enemy.set_physics_process(false)
			check(s.director.metrics().spawned==12 and s.director.metrics().reserved==0,"full visible interval eventually births all12 safely after "+event)
		cleanup(s);await process_frame
	print("DOOR_HUD_WINDOW checks=%d failures=%d; HUD/camera/resize interruption,full fresh.8s"%[checks,failures]);quit(1 if failures else 0)
