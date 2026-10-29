extends SceneTree
const World=preload("res://scripts/cornfield/room_world.gd")
const Catalog=preload("res://scripts/cornfield/room_catalog.gd")
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
func quad(x:float,z:float)->PackedVector3Array:return PackedVector3Array([Vector3(x,0,z),Vector3(x,0,z+.9),Vector3(x+.9,0,z+.9),Vector3(x+.9,0,z)])
func run()->void:
 var w:=World.new();w.definition=Catalog.make_template(2);w._outline=PackedVector2Array(w.definition.outline);w._obstacles=w.definition.obstacles.duplicate(true)
 check(w._bridge_quad_clear(quad(19.35,28.35)),"horizontal authored deck positive")
 check(w._bridge_quad_clear(quad(18.45,28.35)),"horizontal left bank transition within existing2m approach")
 check(w._bridge_quad_clear(quad(23.85,28.35)),"horizontal right bank transition within existing2m approach")
 check(not w._bridge_quad_clear(quad(18.45,27.75)),"bank transition adjacent-water sliver rejected")
 check(not w._bridge_quad_clear(quad(16.8,28.35)),"partial outside bridge+2m reserve rejected")
 check(not w._bridge_quad_clear(quad(19.35,27.625)),"near-water deck retains full actor radius")
 w._dynamic_obstacles={"adverse_prop":{"position":Vector3(19.8,0,28.8),"radius":.34}}
 check(not w._bridge_quad_clear(quad(19.35,28.35)),"dynamic prop in quad interior rejected")
 w._dynamic_obstacles={};w.free()
 var v:=World.new();v.definition={"doors":{},"presentation":{"bridge_zones":[Rect2(8.65,6,2.7,8)]}};v._outline=PackedVector2Array([Vector2(0,0),Vector2(20,0),Vector2(20,20),Vector2(0,20)])
 v._obstacles=[{"kind":"water","rect":Rect2(0,6,8.65,8),"height":.4},{"kind":"water","rect":Rect2(11.35,6,8.65,8),"height":.4}]
 check(v._bridge_quad_clear(quad(9.45,9.45)),"rotated north/south authored deck positive")
 check(v._bridge_quad_clear(quad(9.45,5.85)),"rotated bank transition positive")
 check(not v._bridge_quad_clear(quad(8.75,5.85)),"rotated adjacent-water sliver rejected")
 check(not v._bridge_quad_clear(quad(9.45,3.95)),"rotated partial outside reserve rejected")
 v._dynamic_obstacles={"adverse_prop":{"position":Vector3(10.0,0,9.9),"radius":.45}}
 check(not v._bridge_quad_clear(quad(9.45,9.45)),"rotated dynamic interior prop rejected")
 v.free()
 var f:=FileAccess.open("res://../evidence/bridge-quad-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));f.close()
 print("BRIDGE_QUAD_PROOF checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
