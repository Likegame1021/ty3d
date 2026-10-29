extends "res://tests/test_cornfield_encounters.gd"
## Reproducer from a legal input playthrough: route geometry doubles back, so
## nearest-segment projection aliases the earlier outward segment at the end.
func _run() -> void:
	var scene:=setup(1)
	var room:=definition()
	room.main_route=PackedVector3Array([Vector3(5,0,24),Vector3(45,0,24),Vector3(25,0,24)])
	scene.director.configure(scene.world,scene.player,room,1)
	var original_budget:int=scene.director.metrics().planned
	for waypoint in room.main_route:
		scene.player.position=waypoint
		for tick in 40:
			step(scene.director,.81)
			kill_all(scene.director)
			step(scene.director,.01)
	check(scene.director.is_complete(),"reaching a backtracking route endpoint drains every owed group without gate probing")
	check(scene.director.metrics().spawned==original_budget,"endpoint recovery preserves exact room enemy budget")
	check(scene.director.metrics().reward_paid==scene.director.metrics().reward_budget,"endpoint recovery preserves fixed coin reward")
	scene.world.free()
	await process_frame
	print("CORNFIELDS_BACKTRACKING_ROUTE %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
