extends "res://scripts/multi_clip_display_v1/visual.gd"
## Non-looping presentation input, never a gameplay clock or event source.
func event_frame(elapsed,duration)->Dictionary:
 if not (elapsed is int or elapsed is float) or not (duration is int or duration is float):return {"valid":false,"frame":0,"error":"Event timing must be numeric"}
 if not is_finite(float(elapsed)) or not is_finite(float(duration)) or duration<=0:return {"valid":false,"frame":0,"error":"Event timing must be finite with positive duration"}
 var progress:float=clampf(float(elapsed)/float(duration),0.0,1.0)
 return {"valid":true,"frame":clampi(roundi(progress*7.0),0,7),"progress":progress}

const EventVerifiedClip=preload("res://scripts/event_clip_display_v1/verified_clip.gd")
func profile_shape_ok(data)->bool:
 if not data is Dictionary:return false
 var schema=data.get("schema")
 if not (schema is int or schema is float) or schema!=3:return false
 var sources=data.get("clips")
 if not sources is Dictionary or not sources.has("idle") or not sources.has("run"):return false
 if sources.size()!=2 and sources.size()!=3:return false
 for key in sources:
  if not key is String or key not in ["idle","run","hurt"] or not sources[key] is Dictionary:return false
 var mapped=data.get("fallbacks")
 if not mapped is Dictionary:return false
 var missing=["attack","recover"] if sources.has("hurt") else ["attack","recover","hurt"]
 if mapped.size()!=missing.size():return false
 for state in missing:
  var fallback=mapped.get(state)
  if not fallback is Dictionary:return false
  var source=fallback.get("clip");var frame=fallback.get("frame")
  if not source is String or source!="idle":return false
  if not (frame is int or frame is float) or not is_finite(float(frame)) or frame!=0:return false
 return true
func load_profile(path:String)->String:
 reject("")
 if not FileAccess.file_exists(path):return reject("Event profile unavailable")
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not profile_shape_ok(data):return reject("Invalid event schema3 profile")
 var next_clips:Dictionary={}
 for key in data.clips:
  var clip=EventVerifiedClip.new()
  var error:String=clip.load_descriptor(data.clips[key])
  if not error.is_empty() or not clip.ready:return reject(key+" clip rejected: "+error)
  if key=="idle" and clip.authored_clip_type!="idle":return reject("Idle source mismatch")
  if key=="run" and clip.authored_clip_type not in ["run","move"]:return reject("Run source mismatch")
  if key=="hurt" and clip.authored_clip_type!="hurt":return reject("Hurt source mismatch")
  next_clips[key]=clip
 clips=next_clips;fallbacks=data.fallbacks.duplicate(true)
 display_label=str(data.get("display_label","EVENT DISPLAY TECHNICAL CANDIDATE"))
 error_text="";ready=true
 return ""
func sample_event_state(action:String,phase_seconds:float,moving:bool,facing_world:Vector3,camera_basis:Basis,previous_row:int,elapsed,duration)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 if action!="hurt" or not clips.has("hurt"):return sample(action,phase_seconds,moving,facing_world,camera_basis,previous_row)
 var timing:=event_frame(elapsed,duration)
 var selected:String="hurt" if timing.valid else "idle"
 var clip=clips[selected]
 var row:int=clip.direction_index(facing_world,camera_basis,previous_row)
 var result:Dictionary=clip.frame_payload(row,timing.frame)
 result.direction=row;result.frame_index=timing.frame;result.selected_clip=selected
 result.static_fallback=not timing.valid;result.fallback_for="invalid_event_timing" if not timing.valid else ""
 result.tint=Color(1.6,.65,.55)
 if not timing.valid:result.timing_error=timing.error
 else:result.event_progress=timing.progress
 return result
