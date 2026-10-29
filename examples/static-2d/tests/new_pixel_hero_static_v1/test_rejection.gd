extends SceneTree
var failures:=0
var checks:=0
func check(value:bool,label:String):
 checks+=1
 if not value:failures+=1;push_error(label)
func _initialize():
 var sampler=load("res://scripts/new_pixel_hero_static_v1/atlas_visual.gd").new()
 var profile:="res://profiles/new_pixel_hero_static_v1.json"
 check(sampler.load_profile(profile).is_empty(),"Original measured profile loads")
 check(not sampler.sample_static("idle",Vector3.BACK,Basis.IDENTITY,99).valid,"Invalid previous direction rejected")
 var data=JSON.parse_string(FileAccess.get_file_as_string(profile))
 data.directions[0].region=[0,0,100,100]
 data.directions[0].feet_anchor=[50,100]
 var path:="user://new-pixel-invalid-profile.json"
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
 check(not sampler.load_profile(path).is_empty(),"Geometrically valid but unmeasured blank-region profile rejected")
 check(not sampler.ready and sampler.frames.is_empty(),"Rejected reload clears all frames")
 check(not sampler.sample_static("run",Vector3.BACK,Basis.IDENTITY,0).valid,"Rejected reload cannot silently show old 3D or stale 2D")
 check(sampler.load_profile(profile).is_empty(),"Actual original profile can be reloaded")
 data=JSON.parse_string(FileAccess.get_file_as_string(profile))
 data.directions[0].feet_anchor=[120,475]
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
 check(not sampler.load_profile(path).is_empty() and not sampler.ready,"Unreviewed foot-anchor drift rejected")
 for mutation in ["blank_cells","zero_anchors","swapped_directions"]:
  check(sampler.load_profile(profile).is_empty(),"Valid reload before "+mutation)
  data=JSON.parse_string(FileAccess.get_file_as_string(profile))
  if mutation=="blank_cells":
   for row in range(8):
    data.directions[row].region=[row*4,0,1,1]
    data.directions[row].feet_anchor=[0,0]
  elif mutation=="zero_anchors":
   for entry in data.directions:entry.feet_anchor=[0,0]
  else:
   var region=data.directions[0].region
   var anchor=data.directions[0].feet_anchor
   data.directions[0].region=data.directions[1].region;data.directions[0].feet_anchor=data.directions[1].feet_anchor
   data.directions[1].region=region;data.directions[1].feet_anchor=anchor
  FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
  check(not sampler.load_profile(path).is_empty() and not sampler.ready and sampler.frames.is_empty(),"Reject unmeasured "+mutation+" and clear all frames")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("NEW 2D FAIL-CLOSED checks=",checks," failures=",failures)
 quit(1 if failures else 0)
