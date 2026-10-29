extends "res://scripts/baked_integration/run_visual.gd"
## Read-only resource binding. No gameplay values or clocks are configurable.
var ready:=false
var profile_label:=""
var error_text:=""
func reject(reason:String)->String:
 ready=false;textures.clear();anchors.clear()
 error_text=reason
 return reason
func load_profile(path:String)->String:
 ready=false;profile_label="";error_text="";textures.clear();anchors.clear()
 if not FileAccess.file_exists(path):return reject("Display profile is not available")
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not data is Dictionary or data.get("schema",0)!=1:return reject("Unsupported display profile schema")
 if data.get("clip_type","")!="run" or data.get("fallback","")!="directional_run_frame_0":return reject("Only actual RUN plus explicit static fallback is supported")
 var directory=data.get("asset_directory","")
 if not directory is String or not directory.begins_with("res://"):return reject("Display assets must be project-local resources")
 var manifest_path:String=directory+"/manifest.json"
 var calibration_path:String=directory+"/sprite-calibration.json"
 if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(calibration_path):return reject("Manifest/calibration files are not available")
 if FileAccess.get_sha256(manifest_path)!=data.get("manifest_sha256",""):return reject("Manifest hash does not match this profile")
 if FileAccess.get_sha256(calibration_path)!=data.get("calibration_sha256",""):return reject("Calibration hash does not match this profile")
 var frame_hashes=data.get("frame_sha256",{})
 if not frame_hashes is Dictionary or frame_hashes.size()!=64:return reject("Profile must identify all 64 real PNG bytes")
 var unique_hashes:Dictionary={}
 for hash_value in frame_hashes.values():
  if not hash_value is String or hash_value.length()!=64:return reject("Invalid PNG SHA256 identity")
  unique_hashes[hash_value]=true
 if unique_hashes.size()!=64:return reject("Fixed RUN64 contract requires 64 distinct frame images")
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
 var calibration=JSON.parse_string(FileAccess.get_file_as_string(calibration_path))
 var metadata_error:=validate_metadata(manifest,calibration,frame_hashes)
 if not metadata_error.is_empty():return reject(metadata_error)
 for frame in manifest.frames:
  var frame_path:String=directory+"/"+str(frame.file)
  if not FileAccess.file_exists(frame_path) or FileAccess.get_sha256(frame_path)!=frame_hashes.get(frame.file,""):
   return reject("Frame hash does not match this profile: "+str(frame.file))
 var error:String=load_assets(directory)
 if not error.is_empty():return reject(error)
 if textures.size()!=8 or anchors.size()!=8:return reject("Asset loader did not produce complete display data")
 profile_label=str(data.get("display_label","TECHNICAL RUN CANDIDATE"))
 ready=true
 return ""
func sample(action:String,direction:int,phase_seconds:float,moving:bool)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 var result:Dictionary=super.sample(action,direction,phase_seconds,moving)
 result.valid=true
 return result

func finite_number(value)->bool:
 return (value is int or value is float) and is_finite(float(value))
func validate_metadata(manifest,calibration,frame_hashes:Dictionary)->String:
 if not manifest is Dictionary or not calibration is Dictionary:return "Manifest/calibration must be objects"
 var frames=manifest.get("frames")
 if not frames is Array or frames.size()!=64:return "Manifest requires 64 frame records"
 if manifest.get("directions")!=DIRECTIONS:return "Unexpected authored direction order"
 var seconds=manifest.get("duration_seconds")
 if not finite_number(seconds) or seconds<=0:return "Duration must be finite and positive"
 var canvas=calibration.get("canvas")
 if not canvas is Array or canvas.size()!=2:return "Canvas requires two dimensions"
 if not finite_number(canvas[0]) or not finite_number(canvas[1]) or canvas[0]!=192 or canvas[1]!=192:return "Calibration must describe 192x192 canvas"
 var scale_value=calibration.get("pixel_size")
 if not finite_number(scale_value) or scale_value<=0:return "Pixel size must be finite and positive"
 var feet=calibration.get("foot_anchors")
 if not feet is Dictionary:return "Foot anchors must be a dictionary"
 for direction in DIRECTIONS:
  var anchor=feet.get(direction)
  if not anchor is Array or anchor.size()!=2:return "Each direction needs a two-number ground anchor"
  if not finite_number(anchor[0]) or not finite_number(anchor[1]):return "Ground anchors must be finite numbers"
  if anchor[0]<0 or anchor[0]>192 or anchor[1]<0 or anchor[1]>192:return "Ground anchor outside supported canvas"
 var files:Dictionary={};var addresses:Dictionary={}
 for entry in frames:
  if not entry is Dictionary:return "Frame record must be a dictionary"
  var filename=entry.get("file");var direction=entry.get("direction");var column=entry.get("phase_index")
  if not filename is String or filename.get_file()!=filename or not filename.ends_with(".png") or filename.contains("\\"):return "Frame file must be a local PNG basename"
  if not direction is String or not direction in DIRECTIONS:return "Invalid frame direction"
  if not finite_number(column) or column!=floor(float(column)) or column<0 or column>7:return "Phase index must be integer 0..7"
  var address:=str(direction)+":"+str(int(column))
  if files.has(filename) or addresses.has(address):return "Duplicate frame file or direction/phase address"
  if not frame_hashes.has(filename):return "Profile/frame filename sets differ"
  files[filename]=true;addresses[address]=true
 return ""
