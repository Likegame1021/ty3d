extends RefCounted
## Passive schema2 selector: actor state/phase remain entirely authoritative.
const VerifiedClip=preload("res://scripts/multi_clip_display_v1/verified_clip.gd")
var ready:=false
var error_text:=""
var display_label:=""
var clips:Dictionary={}
var fallbacks:Dictionary={}
func reject(reason:String)->String:
 ready=false;clips.clear();fallbacks.clear();display_label="";error_text=reason
 return reason
func validate_profile_structure(data)->String:
 if not data is Dictionary:return "Expected multi-clip profile object"
 var schema=data.get("schema")
 if not (schema is int or schema is float):return "Schema must be numeric 2"
 if schema!=2:return "Expected multi-clip profile schema2"
 var sources=data.get("clips")
 if not sources is Dictionary or sources.size()!=2 or not sources.has("idle") or not sources.has("run"):return "Both actual idle and run clips are required"
 for key in ["idle","run"]:
  if not sources[key] is Dictionary:return "Each clip descriptor must be an object"
 var mapped=data.get("fallbacks")
 if not mapped is Dictionary or mapped.size()!=3:return "Declare exactly attack/hurt/recover static fallbacks"
 for state in ["attack","hurt","recover"]:
  var fallback=mapped.get(state)
  if not fallback is Dictionary:return "Fallback must be an object"
  var source=fallback.get("clip")
  if not source is String or source!="idle":return "Missing actions must explicitly select idle00"
  var frame=fallback.get("frame")
  if not (frame is int or frame is float) or not is_finite(float(frame)) or frame!=0:return "Fallback must explicitly hold frame0"
 return ""
func load_profile(path:String)->String:
 reject("")
 if not FileAccess.file_exists(path):return reject("Real multi-clip profile is unavailable")
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 var structural_error:=validate_profile_structure(data)
 if not structural_error.is_empty():return reject(structural_error)
 var next_clips:Dictionary={}
 for key in ["idle","run"]:
  var clip=VerifiedClip.new()
  var error:String=clip.load_descriptor(data.clips[key])
  if not error.is_empty():return reject(key+" clip rejected: "+error)
  if key=="idle" and clip.authored_clip_type!="idle":return reject("Idle state requires an actual idle source")
  if key=="run" and clip.authored_clip_type not in ["run","move"]:return reject("Run state requires an actual run/move source")
  next_clips[key]=clip
 clips=next_clips;fallbacks=data.fallbacks.duplicate(true)
 display_label=str(data.get("display_label","MULTI-CLIP TECHNICAL CANDIDATE"))
 error_text="";ready=true
 return ""
func selection(action:String,moving:bool,mapped:Dictionary)->Dictionary:
 if action=="idle":return {"valid":true,"clip":"idle","animate":true,"frame":0,"reason":""}
 if action=="run":return {"valid":true,"clip":"run","animate":moving,"frame":0,"reason":"" if moving else "run_without_motion"}
 if mapped.has(action):return {"valid":true,"clip":mapped[action].clip,"animate":false,"frame":int(mapped[action].frame),"reason":action}
 return {"valid":false,"error":"No declared clip/fallback for authoritative state"}
func sample(action:String,phase_seconds:float,moving:bool,facing_world:Vector3,camera_basis:Basis,previous_row:int)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 var selected:=selection(action,moving,fallbacks)
 if not selected.valid:return selected
 var clip=clips[selected.clip]
 var row:int=clip.direction_index(facing_world,camera_basis,previous_row)
 var column:int=clip.frame_for_phase(phase_seconds) if selected.animate else selected.frame
 var result:Dictionary=clip.frame_payload(row,column)
 result.direction=row;result.frame_index=column;result.selected_clip=selected.clip
 result.static_fallback=not selected.animate;result.fallback_for=selected.reason
 result.tint=Color(1.6,.65,.55) if action=="hurt" else Color.WHITE
 return result
