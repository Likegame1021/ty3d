extends RefCounted
## Passive sampler of the actual legacy-rig RUN bake. No clock/gameplay ownership.
const DIRECTIONS=["S","SE","E","NE","N","NW","W","SW"]
var textures:Array=[]
var anchors:Array=[]
var duration:=17.0/24.0
var pixel_size:=.00859375
func load_assets(directory:String)->String:
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(directory+"/manifest.json"))
 var calibration=JSON.parse_string(FileAccess.get_file_as_string(directory+"/sprite-calibration.json"))
 if not manifest is Dictionary or not calibration is Dictionary:return "Missing bake manifest or calibration"
 if manifest.get("directions",[])!=DIRECTIONS:return "Unexpected authored direction order"
 if manifest.get("frames",[]).size()!=64:return "Expected 64 real frames"
 var next_textures:Array=[]
 var next_anchors:Array=[]
 for direction in DIRECTIONS:
  next_textures.append([null,null,null,null,null,null,null,null])
  var anchor=calibration.get("foot_anchors",{}).get(direction,[])
  if anchor.size()!=2:return "Missing authored ground anchor"
  next_anchors.append(Vector2(anchor[0],anchor[1]))
 for entry in manifest.frames:
  var row:int=DIRECTIONS.find(entry.direction)
  var column:int=int(entry.phase_index)
  if row<0 or column<0 or column>7:return "Invalid frame address"
  if next_textures[row][column]!=null:return "Duplicate frame address"
  var resource:Texture2D=load(directory+"/"+entry.file)
  if resource==null or resource.get_size()!=Vector2(192,192):return "Missing or wrong-sized real baked PNG"
  next_textures[row][column]=resource
 for row in next_textures:
  if row.has(null):return "Incomplete authored frame set"
 var seconds:float=manifest.get("duration_seconds",0)
 var scale_value:float=calibration.get("pixel_size",0)
 if seconds<=0 or scale_value<=0:return "Invalid authored timing or scale"
 textures=next_textures;anchors=next_anchors;duration=seconds;pixel_size=scale_value
 return ""
func sample(action:String,direction:int,phase_seconds:float,moving:bool)->Dictionary:
 var row:=clampi(direction,0,7)
 var running:=action=="run" and moving
 var frame_index:=floori(fposmod(phase_seconds/duration,1.0)*8) if running else 0
 return {"texture":textures[row][frame_index],"direction":row,"frame_index":frame_index,
  "static_fallback":not running,"fallback_for":action if not running else "",
  "offset":Vector2(96-anchors[row].x,anchors[row].y-96),
  "tint":Color(1.6,.65,.55) if action=="hurt" else Color.WHITE}
