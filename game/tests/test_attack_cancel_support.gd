extends SceneTree
const DIR:="user://cancel-loader/"
const SUPPORT:="res://assets/characters/boy/normal_grip/cancel-support.json"
var checks:=0
var failures:=0
func _initialize():call_deferred("run_test")
func check(ok,label):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func fixture(name:String,data) -> String:
 var path:=DIR+"loader-"+name+".json"
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
 return path
func run_test():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
 var helper=load("res://weapons/attack_cancel_pose.gd").new()
 check(helper.has_method("load_support_file"),"support loader safely reports invalid or missing resources")
 if not helper.has_method("load_support_file"):
  helper.free();quit(1);return
 var valid=JSON.parse_string(FileAccess.get_file_as_string(SUPPORT))
 check(helper.load_support_file(SUPPORT,valid.names),"verified support resource loads")
 check(helper.points.size()==834,"all unique support vertices retained")
 check(not helper.load_support_file(DIR+"no-such-support.json",valid.names),"missing support file returns false without exception")
 check(helper.points.is_empty(),"failed initialization leaves no partial point cloud")
 for data in [[],{}, {"names":valid.names,"points":[]}, {"names":[],"points":valid.points}]:
  check(not helper.load_support_file(fixture("shape",data),valid.names),"invalid schema rejected")
 for kind in ["coordinates","bone","weight","weightsum","entry"]:
  var data=valid.duplicate(true)
  match kind:
   "coordinates":data.points[0].influences[0].bind_weighted_xyz=["wrong",0,0]
   "bone":data.points[0].influences[0].bone=99
   "weight":data.points[0].influences[0].weight=-1
   "weightsum":data.points[0].influences[0].weight=.001
   "entry":data.points[0].influences=[null]
  check(not helper.load_support_file(fixture(kind,data),valid.names),"malformed "+kind+" rejected")
  check(helper.points.is_empty(),"no partial data accepted for "+kind)
 var malformed:=DIR+"loader-malformed.json";FileAccess.open(malformed,FileAccess.WRITE).store_string("{broken")
 check(not helper.load_support_file(malformed,valid.names),"malformed JSON returns false")
 check(helper.load_support_file(SUPPORT,valid.names),"valid resource can load after failures")
 helper.free();print("SUPPORT_LOADER ",checks," checks ",failures," failures");quit(1 if failures else 0)
