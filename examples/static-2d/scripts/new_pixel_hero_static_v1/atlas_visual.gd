extends RefCounted
## Passive original-2D static atlas. No gameplay ownership, clocks or fake frames.
const Logic=preload("res://scripts/actor_logic.gd")
const SOURCE:="res://assets/new_pixel_hero_static_v1/hd2d-hero-eight-directions-v2.png"
const SOURCE_SHA256:="3daffa7b35471ee21ee3750e71600fc0f03e2a75eda2c82c7051de27bf64058a"
# This isolated candidate accepts only the pixel-audited calibration, not
# arbitrary geometrically valid rectangles or unreviewed foot anchors.
const PROFILE_SHA256:="4071c18e749601f8b225ce43ed808a8e0ffad2ab8505c448e557366fe68c30c3"
const NAMES=["S","SE","E","NE","N","NW","W","SW"]
var ready:=false
var error_text:=""
var pixel_size:=1.56/472.0
var frames:Array=[]
var direction_logic=Logic.new()
func reject(message:String)->String:
 ready=false;frames.clear();error_text=message
 return message
func numeric_array(value,count:int)->bool:
 if not value is Array or value.size()!=count:return false
 for item in value:
  if not (item is int or item is float) or not is_finite(float(item)):return false
 return true
func load_profile(path:String)->String:
 reject("")
 if not FileAccess.file_exists(path):return reject("New 2D static profile unavailable")
 if FileAccess.get_sha256(path)!=PROFILE_SHA256:return reject("New 2D region/anchor calibration is not the verified profile")
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not data is Dictionary:return reject("New 2D static profile must be an object")
 if data.get("art_type")!="new_2d_static_eight_directions" or data.get("frame_count")!=1:return reject("Only authored static eight-way 2D art is supported")
 if data.get("source")!=SOURCE or data.get("source_sha256")!=SOURCE_SHA256:return reject("Unverified source image")
 if not FileAccess.file_exists(SOURCE) or FileAccess.get_sha256(SOURCE)!=SOURCE_SHA256:return reject("Original 2D PNG missing or modified")
 var texture=load(SOURCE)
 if not texture is Texture2D or texture.get_size()!=Vector2(1536,1024):return reject("Original 2D texture dimensions invalid")
 var entries=data.get("directions")
 if not entries is Array or entries.size()!=8:return reject("Exactly eight independently authored directions required")
 var next_frames:Array=[]
 for row in range(8):
  var entry=entries[row]
  if not entry is Dictionary or entry.get("name")!=NAMES[row]:return reject("Direction order invalid")
  if not numeric_array(entry.get("region"),4) or not numeric_array(entry.get("feet_anchor"),2):return reject("Invalid region or foot anchor")
  var r:Array=entry.region
  for number in r:
   if number!=floor(number):return reject("Atlas regions must use whole pixels")
  var region:=Rect2(r[0],r[1],r[2],r[3])
  if region.size.x<=0 or region.size.y<=0 or not Rect2(0,0,1536,1024).encloses(region):return reject("Atlas region outside original texture")
  for prior in next_frames:
   if prior.texture.region.intersects(region):return reject("Overlapping atlas rectangles")
  var anchor:=Vector2(entry.feet_anchor[0],entry.feet_anchor[1])
  if anchor.x<0 or anchor.y<0 or anchor.x>region.size.x or anchor.y>region.size.y:return reject("Foot anchor outside its own region")
  var atlas:=AtlasTexture.new()
  atlas.atlas=texture;atlas.region=region;atlas.filter_clip=true
  var offset:=Vector2(region.size.x/2-anchor.x,anchor.y-region.size.y/2)
  next_frames.append({"texture":atlas,"offset":offset,"feet_anchor":anchor})
 frames=next_frames;ready=true;error_text=""
 return ""
func sample_static(action:String,facing_world:Vector3,camera_basis:Basis,previous_direction:int)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 if previous_direction<0 or previous_direction>=8:return {"valid":false,"error":"Previous visual direction outside eight-way range"}
 var right:=Vector3(camera_basis.x.x,0,camera_basis.x.z).normalized()
 var toward:=Vector3(camera_basis.z.x,0,camera_basis.z.z).normalized()
 var row:int=direction_logic.direction_for(Vector2(facing_world.dot(right),facing_world.dot(toward)),previous_direction)
 var result:Dictionary=frames[row].duplicate()
 result.merge({"valid":true,"direction":row,"direction_name":NAMES[row],"frame_index":0,
  "pixel_size":pixel_size,"selected_clip":"static_idle","static_fallback":action!="idle",
  "fallback_for":action if action!="idle" else "","tint":Color(1.6,.65,.55) if action=="hurt" else Color.WHITE})
 return result
func apply_material(sprite:Sprite3D):
 sprite.hframes=1;sprite.vframes=1;sprite.frame=0
 sprite.flip_h=false;sprite.flip_v=false
 sprite.pixel_size=pixel_size
 sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
 sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
 sprite.alpha_scissor_threshold=.5
 sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
 sprite.shaded=false;sprite.no_depth_test=false
