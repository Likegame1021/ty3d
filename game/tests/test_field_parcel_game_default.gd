extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:Array=[]
func _initialize()->void:
 var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../evidence"))
 if output_error != OK:
  printerr("FAIL: cannot create field QA evidence directory: ", output_error)
  quit(1);return
 call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);printerr("FAIL "+label)
func run()->void:
 var game:=Game.new();game.test_mode=true;game.save_path="user://field_default_on_flow.json";root.add_child(game)
 await process_frame
 game._start_new_run(2);await process_frame
 game._install_node("EVENT");game._close_panel();await process_frame
 game._enter_room("fight_1","west");await process_frame
 game.director.set_physics_process(false);game.player.set_physics_process(false)
 var report:Dictionary=game.world.field_edge_report()
 check(report.status=="enabled","real generated Game enables profile without QA opt-in")
 check(report.get("profile_id","")=="parcel:broken_wall/9/west>north","real generated seed2 exact generic construction")
 check(not report.get("validation_only",true),"runtime manifest enables actual candidate")
 check(report.get("new_boxes",0)==9,"actual generated fixture has nine new field bodies")
 check(game.world.find_children("field_parcel_*","StaticBody3D",true,false).size()==9,"nine concrete field bodies installed in real Game")
 check(game.world._dynamic_obstacles.size()==2,"real Game spawns unchanged two props")
 check(game.world.validate_field_spawned_content(),"real Game actual prop registration and usable access retained")
 check(game.world._dynamic_obstacles.fight_1_prop_0.position.distance_to(Vector3(40.6,0,25.6))<.0001,"first actual prop coordinate unchanged")
 check(game.world._dynamic_obstacles.fight_1_prop_1.position.distance_to(Vector3(36.4,0,22.8))<.0001,"second actual prop coordinate unchanged")
 var generation:int=game.world.spawn_domain_generation;check(generation==1,"one frozen domain construction in actual Game")
 var drop:Vector3=game.world._dynamic_obstacles.fight_1_prop_0.position
 game._prop_broken("fight_1_prop_0",drop,"coins")
 game._enter_room("fight_1","north");await process_frame
 game.director.set_physics_process(false);game.player.set_physics_process(false)
 check(game.world.field_edge_report().status=="enabled","alternate arrival with current-node drop keeps accepted profile")
 check(game.world.validate_field_spawned_content(),"revisited real Game retains drop collection and surviving prop access")
 check(game.room_states.fight_1.drops.has("fight_1_prop_0"),"actual Game current-node drop identity preserved")
 check(game.world.find_children("*","NavigationRegion3D",true,false).size()==1,"actual Game rebuild has one native region")
 check(game.world.find_children("field_parcel_*","StaticBody3D",true,false).size()==9,"actual Game rebuild has no duplicated field bodies")
 var f:=FileAccess.open("res://../evidence/game-default-on.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"profile":report.merged({"asset_bounds":[],"batches":[]},true)},"\t"));f.close()
 game.free();await process_frame;print("FIELD_GAME_DEFAULT checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
