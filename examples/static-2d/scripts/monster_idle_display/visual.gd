extends RefCounted
## Passive authored-IDLE presentation. Never owns actor clocks, movement or combat.
const DIRECTIONS=["S","SE","E","NE","N","NW","W","SW"]
const DirectionLogic=preload("res://scripts/actor_logic.gd")
var logic=DirectionLogic.new()
var ready:=false
var error_text:=""
var label:=""
var textures:Array=[]
var anchors:Array=[]
var canvas:=Vector2(192,192)
var pixel_size:=0.0
var duration:=0.0
func reject(reason:String)->String:
 ready=false;textures.clear();anchors.clear();label="";error_text=reason
 return reason
func finite_number(value)->bool:
 return (value is int or value is float) and is_finite(float(value))
func validate_metadata(manifest,calibration,hashes)->String:
 if not manifest is Dictionary or not calibration is Dictionary:return "Manifest and calibration must be objects"
 if manifest.get("clip_type")!="idle":return "Only actual IDLE clips are supported"
 if manifest.get("directions")!=DIRECTIONS:return "Expected authored eight-direction order"
 var frames=manifest.get("frames")
 if not frames is Array or frames.size()!=64:return "Expected eight-by-eight frame records"
 var seconds=manifest.get("duration_seconds")
 if not finite_number(seconds) or seconds<=0:return "Invalid authored idle duration"
 var size_value=calibration.get("canvas")
 if not size_value is Array or size_value.size()!=2:return "Invalid canvas structure"
 if not finite_number(size_value[0]) or not finite_number(size_value[1]) or size_value[0]!=192 or size_value[1]!=192:return "Expected authored 192x192 canvas"
 var scale_value=calibration.get("pixel_size")
 if not finite_number(scale_value) or scale_value<=0:return "Invalid authored pixel size"
 var alpha=calibration.get("alpha_scissor_threshold")
 if not finite_number(alpha) or not is_equal_approx(alpha,.4):return "This material contract requires alpha scissor .4"
 var feet=calibration.get("foot_anchors")
 if not feet is Dictionary:return "Ground anchors must be an object"
 for direction in DIRECTIONS:
  var anchor=feet.get(direction)
  if not anchor is Array or anchor.size()!=2:return "Missing directional ground anchor"
  if not finite_number(anchor[0]) or not finite_number(anchor[1]):return "Ground anchor must be finite"
  if anchor[0]<0 or anchor[0]>192 or anchor[1]<0 or anchor[1]>192:return "Ground anchor outside canvas"
 if not hashes is Dictionary or hashes.size()!=64:return "Profile must identify all 64 actual files"
 var files:Dictionary={};var addresses:Dictionary={};var rows:Array=[]
 for _direction in DIRECTIONS:rows.append(["","","","","","","",""])
 for entry in frames:
  if not entry is Dictionary:return "Frame record must be an object"
  var filename=entry.get("file");var direction=entry.get("direction");var column=entry.get("phase_index")
  if not filename is String or filename.get_file()!=filename or filename.contains("\\") or not filename.ends_with(".png"):return "Frame must name a local PNG"
  if not direction is String or not direction in DIRECTIONS:return "Invalid frame direction"
  if not finite_number(column) or column!=floor(float(column)) or column<0 or column>7:return "Frame phase must be integer 0..7"
  var address:=str(direction)+":"+str(int(column))
  if files.has(filename) or addresses.has(address):return "Duplicate file or frame address"
  var identity=hashes.get(filename)
  if not identity is String or identity.length()!=64:return "Missing frame SHA256 identity"
  files[filename]=true;addresses[address]=true
  rows[DIRECTIONS.find(direction)][int(column)]=identity
 var distinct_rows:Dictionary={}
 for row in rows:
  var phase_images:Dictionary={}
  for identity in row:phase_images[identity]=true
  if phase_images.size()<2:return "An IDLE animation needs real phase variation, not eight static copies"
  distinct_rows["|".join(PackedStringArray(row))]=true
 if distinct_rows.size()!=8:return "Authored eight-view contract rejects cloned directional sequences"
 return ""
func load_profile(path:String)->String:
 reject("")
 if not FileAccess.file_exists(path):return reject("Monster idle profile is unavailable")
 var profile=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not profile is Dictionary or profile.get("schema")!=1:return reject("Invalid monster profile schema")
 if profile.get("clip_type")!="idle" or profile.get("fallback")!="directional_idle_frame_0":return reject("Only authored idle plus explicit static fallback supported")
 var directory=profile.get("asset_directory")
 if not directory is String or not directory.begins_with("res://") or ".." in directory:return reject("Use bounded project-local resources")
 var manifest_path:String=directory+"/manifest.json"
 var calibration_path:String=directory+"/sprite-calibration.json"
 if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(calibration_path):return reject("Missing actual manifest/calibration")
 if FileAccess.get_sha256(manifest_path)!=profile.get("manifest_sha256"):return reject("Manifest hash mismatch")
 if FileAccess.get_sha256(calibration_path)!=profile.get("calibration_sha256"):return reject("Calibration hash mismatch")
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
 var calibration=JSON.parse_string(FileAccess.get_file_as_string(calibration_path))
 var hashes=profile.get("frame_sha256")
 var error:=validate_metadata(manifest,calibration,hashes)
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
 label=str(profile.get("display_label","MONSTER IDLE TECHNICAL CANDIDATE"))
 ready=true;error_text=""
 return ""
func direction_index(facing_world:Vector3,camera_basis:Basis,previous:int)->int:
 var right:=Vector3(camera_basis.x.x,0,camera_basis.x.z).normalized()
 var toward:=Vector3(camera_basis.z.x,0,camera_basis.z.z).normalized()
 return logic.direction_for(Vector2(facing_world.dot(right),facing_world.dot(toward)),clampi(previous,0,7))
func frame_index(action:String,phase_seconds:float,period:float,count:int)->int:
 if action!="idle" or not is_finite(phase_seconds) or period<=0 or count<1:return 0
 return floori(fposmod(phase_seconds/period,1.0)*count)
func anchor_offset(size_value:Vector2,anchor:Vector2)->Vector2:
 return Vector2(size_value.x*.5-anchor.x,anchor.y-size_value.y*.5)
func sample(action:String,phase_seconds:float,facing_world:Vector3,camera_basis:Basis,previous:int)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 var row:=direction_index(facing_world,camera_basis,previous)
 var column:=frame_index(action,phase_seconds,duration,8)
 return {"valid":true,"texture":textures[row][column],"direction":row,"frame_index":column,
  "static_fallback":action!="idle","fallback_for":action if action!="idle" else "",
  "offset":anchor_offset(canvas,anchors[row]),"tint":Color(1.6,.65,.55) if action=="hurt" else Color.WHITE}

func validate_pixel_variation(rows:Array)->String:
 # Container SHA identifies a file, not visual variation. Compare decoded pixels too.
 var directional_sequences:Dictionary={}
 for row in rows:
  var phases:Dictionary={};var identities:PackedStringArray=[]
  for texture in row:
   if not texture is Texture2D:return "Missing decoded idle texture"
   var image:Image=texture.get_image()
   if image==null or image.is_empty():return "Missing decoded idle image"
   if image.is_compressed() and image.decompress()!=OK:return "Cannot decode idle image"
   var identity:=visible_pixel_identity(image)
   phases[identity]=true;identities.append(identity)
  if phases.size()<2:return "Decoded idle pixels are static copies, not animation"
  directional_sequences["|".join(identities)]=true
 if directional_sequences.size()!=8:return "Decoded directional sequences are clones, not eight authored views"
 return ""

func valid_png_header(bytes:PackedByteArray)->bool:
 if bytes.size()<33 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]):return false
 if bytes.slice(12,16).get_string_from_ascii()!="IHDR":return false
 var width:int=(int(bytes[16])<<24)|(int(bytes[17])<<16)|(int(bytes[18])<<8)|int(bytes[19])
 var height:int=(int(bytes[20])<<24)|(int(bytes[21])<<16)|(int(bytes[22])<<8)|int(bytes[23])
 return width==192 and height==192
func visible_pixel_identity(image:Image)->String:
 if image.is_compressed() and image.decompress()!=OK:return ""
 image.convert(Image.FORMAT_RGBA8)
 image.clear_mipmaps()
 var bytes:=image.get_data()
 # Godot's normal import repairs RGB beneath transparent borders. Those pixels
 # are discarded by this fixed alpha-scissor .4 material and must not cause a
 # false stale-import rejection or pretend to be visible animation variation.
 for offset in range(0,bytes.size(),4):
  if bytes[offset+3]<102:
   bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0;bytes[offset+3]=0
 var digest:=HashingContext.new()
 digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
 return digest.finish().hex_encode()
