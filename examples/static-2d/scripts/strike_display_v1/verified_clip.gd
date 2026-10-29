extends "res://scripts/monster_idle_display/visual.gd"
## One shared resource-loading path for all clips. Inherits the frozen validated
## metadata, actual PNG decoder/size, source/import visible identity, pixel
## variation, camera convention and world-anchor helpers. No actor clocks.
var source_peak_begin:=0.0
var authored_clip_type:=""
func reject(reason:String)->String:
 authored_clip_type="";source_peak_begin=0.0
 return super.reject(reason)
func load_descriptor(profile)->String:
 reject("")
 if not profile is Dictionary:return reject("Clip descriptor must be an object")
 var declared=profile.get("source_clip_type")
 if not declared is String or declared not in ["idle","run","move","hurt","attack"]:return reject("Unsupported authored clip type")
 var directory=profile.get("asset_directory")
 if not directory is String or not directory.begins_with("res://") or ".." in directory:return reject("Use bounded project-local resources")
 for hash_key in ["manifest_sha256","calibration_sha256"]:
  var identity=profile.get(hash_key)
  if not identity is String or identity.length()!=64:return reject("Metadata hash must be a SHA256 string")
 var manifest_path:String=directory+"/manifest.json"
 var calibration_path:String=directory+"/sprite-calibration.json"
 if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(calibration_path):return reject("Missing actual manifest/calibration")
 if FileAccess.get_sha256(manifest_path)!=profile.get("manifest_sha256"):return reject("Manifest hash mismatch")
 if FileAccess.get_sha256(calibration_path)!=profile.get("calibration_sha256"):return reject("Calibration hash mismatch")
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
 var calibration=JSON.parse_string(FileAccess.get_file_as_string(calibration_path))
 var hashes=profile.get("frame_sha256")
 if not manifest is Dictionary:return reject("Clip manifest must be an object")
 if manifest.has("clip_type"):
  if not manifest.clip_type is String or manifest.clip_type!=declared:return reject("Declared source clip type differs from actual manifest")
 elif declared!="run" or not profile.get("legacy_source_action") is String or profile.legacy_source_action!="run_BoyRig" or not manifest.get("source_action") is String or manifest.source_action!="run_BoyRig":
  return reject("Missing actual clip type or explicit legacy RUN compatibility")
 if manifest.has("source_clip_type"):
  var source_kind=manifest.source_clip_type
  if not source_kind is String or source_kind!=declared:return reject("Conflicting source clip type metadata")
 var directions=manifest.get("directions")
 if not directions is Array:return reject("Directions must be an array")
 for direction in directions:
  if not direction is String:return reject("Direction names must be strings")
 # The sealed structural validator is action-neutral apart from its idle tag.
 # Check true source semantics above, then normalize only an in-memory copy for
 # shared shape/hash/anchor/address validation; no source file is rewritten.
 if declared in ["hurt","attack"] and not event_metadata_ok(manifest):return reject("Invalid non-looping inclusive event pose metadata")
 if declared=="attack" and not peak_metadata_ok(manifest):return reject("Invalid outgoing-strike peak metadata")
 var structural=manifest.duplicate(true)
 structural.clip_type="idle"
 var error:=validate_metadata(structural,calibration,hashes)
 if not error.is_empty():return reject(error)
 var next_textures:Array=[];var next_anchors:Array=[]
 for direction in DIRECTIONS:
  next_textures.append([null,null,null,null,null,null,null,null])
  var anchor=calibration.foot_anchors[direction]
  next_anchors.append(Vector2(anchor[0],anchor[1]))
 for entry in manifest.frames:
  var filename:String=directory+"/"+entry.file
  if not FileAccess.file_exists(filename) or FileAccess.get_sha256(filename)!=hashes[entry.file]:return reject("Actual PNG hash mismatch: "+entry.file)
  var source_bytes:=FileAccess.get_file_as_bytes(filename)
  if not valid_png_header(source_bytes):return reject("Invalid actual source PNG header or dimensions: "+entry.file)
  var source_image:=Image.new()
  if source_image.load_png_from_buffer(source_bytes)!=OK or source_image.get_size()!=Vector2i(192,192):return reject("Cannot decode actual source PNG: "+entry.file)
  if not ResourceLoader.exists(filename):return reject("Actual PNG is not imported: "+entry.file)
  var texture=load(filename)
  if not texture is Texture2D or texture.get_size()!=Vector2(192,192):return reject("Invalid imported frame texture")
  var imported_image:Image=texture.get_image()
  if imported_image==null or imported_image.is_empty():return reject("Missing decoded imported image")
  if visible_pixel_identity(source_image)!=visible_pixel_identity(imported_image):return reject("Imported texture does not match actual source pixels: "+entry.file)
  next_textures[DIRECTIONS.find(entry.direction)][int(entry.phase_index)]=texture
 var pixel_error:=validate_pixel_variation(next_textures)
 if not pixel_error.is_empty():return reject(pixel_error)
 textures=next_textures;anchors=next_anchors
 pixel_size=float(calibration.pixel_size);duration=float(manifest.duration_seconds)
 authored_clip_type=declared
 if declared=="attack":source_peak_begin=float(manifest.source_peak_hold_interval[0])
 label=str(profile.get("display_label",str(declared)+" TECHNICAL CLIP"))
 ready=true;error_text=""
 return ""

func frame_for_phase(phase_seconds:float)->int:
 return frame_index("idle",phase_seconds,duration,8)
func frame_payload(row:int,column:int)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 if row<0 or row>7 or column<0 or column>7:return {"valid":false,"error":"Invalid display frame address"}
 return {"valid":true,"texture":textures[row][column],"offset":anchor_offset(canvas,anchors[row]),"pixel_size":pixel_size,"source_clip_type":authored_clip_type}

func event_metadata_ok(manifest)->bool:
 if not manifest is Dictionary:return false
 var looping=manifest.get("loop")
 if not looping is bool or looping:return false
 var frames=manifest.get("frames")
 if not frames is Array or frames.size()!=64:return false
 for entry in frames:
  if not entry is Dictionary:return false
  var index=entry.get("phase_index");var progress=entry.get("phase")
  if not finite_number(index) or index!=floor(float(index)) or index<0 or index>7:return false
  if not finite_number(progress) or not is_equal_approx(float(progress),float(index)/7.0):return false
 return true

func peak_metadata_ok(manifest)->bool:
 if not manifest is Dictionary:return false
 var interval=manifest.get("source_peak_hold_interval")
 if not interval is Array or interval.size()!=2:return false
 if not finite_number(interval[0]) or not finite_number(interval[1]):return false
 if interval[0]<=0 or interval[0]>3.0/7.0 or interval[1]<3.0/7.0 or interval[1]>=1:return false
 var peak=manifest.get("source_peak_progress")
 if not finite_number(peak) or not is_equal_approx(float(peak),float(interval[0])):return false
 return true
