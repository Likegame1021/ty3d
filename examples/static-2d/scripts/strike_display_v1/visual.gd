extends "res://scripts/event_clip_display_v1/visual.gd"
## Strike means outgoing event emitted, not confirmed damage. Pure current inputs.
func strike_frame(elapsed,duration,strike_at=null,has_struck=null,peak_begin=null)->Dictionary:
 var timing:=event_frame(elapsed,duration)
 if not timing.valid:return timing
 if not has_struck is bool:return {"valid":false,"frame":0,"error":"Outgoing strike flag must be boolean"}
 for value in [strike_at,peak_begin]:
  if not (value is int or value is float) or not is_finite(float(value)):return {"valid":false,"frame":0,"error":"Strike timing and source peak must be finite numbers"}
 if strike_at<=0 or strike_at>=duration or peak_begin<=0 or peak_begin>3.0/7.0:return {"valid":false,"frame":0,"error":"Invalid strike interval or source peak"}
 var progress:float
 if not has_struck:
  progress=clampf(float(elapsed)/float(strike_at),0,1)*float(peak_begin)
  return {"valid":true,"frame":mini(roundi(progress*7),2),"progress":progress}
 progress=lerpf(float(peak_begin),1,clampf((float(elapsed)-float(strike_at))/(float(duration)-float(strike_at)),0,1))
 return {"valid":true,"frame":clampi(roundi(progress*7),3,7),"progress":progress}

const StrikeVerifiedClip=preload("res://scripts/strike_display_v1/verified_clip.gd")
func profile_shape_ok(data)->bool:
 if not data is Dictionary:return false
 var schema=data.get("schema")
 if not (schema is int or schema is float) or schema!=4:return false
 var sources=data.get("clips")
 if not sources is Dictionary or not sources.has("idle") or not sources.has("run"):return false
 if sources.size()<2 or sources.size()>4:return false
 for key in sources:
  if not key is String or key not in ["idle","run","hurt","attack"] or not sources[key] is Dictionary:return false
 var mapped=data.get("fallbacks")
 if not mapped is Dictionary:return false
 var missing=["recover"]
 for event in ["hurt","attack"]:
  if not sources.has(event):missing.append(event)
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
 if not profile_shape_ok(data):return reject("Invalid strike schema4 profile")
 var next_clips:Dictionary={}
 for key in data.clips:
  var clip=StrikeVerifiedClip.new()
  var error:String=clip.load_descriptor(data.clips[key])
  if not error.is_empty() or not clip.ready:return reject(key+" clip rejected: "+error)
  if key=="idle" and clip.authored_clip_type!="idle":return reject("Idle source mismatch")
  if key=="run" and clip.authored_clip_type not in ["run","move"]:return reject("Run source mismatch")
  if key in ["hurt","attack"] and clip.authored_clip_type!=key:return reject("Event source mismatch")
  next_clips[key]=clip
 clips=next_clips;fallbacks=data.fallbacks.duplicate(true)
 display_label=str(data.get("display_label","EVENT DISPLAY TECHNICAL CANDIDATE"))
 error_text="";ready=true
 return ""
func sample_strike_state(action:String,phase_seconds:float,moving:bool,facing_world:Vector3,camera_basis:Basis,previous_row:int,elapsed,duration,strike_at=null,has_struck=null)->Dictionary:
 if not ready:return {"valid":false,"error":error_text}
 if action!="attack" or not clips.has("attack"):return sample_event_state(action,phase_seconds,moving,facing_world,camera_basis,previous_row,elapsed,duration)
 var timing:=strike_frame(elapsed,duration,strike_at,has_struck,clips.attack.source_peak_begin)
 var selected:String="attack" if timing.valid else "idle"
 var clip=clips[selected]
 var row:int=clip.direction_index(facing_world,camera_basis,previous_row)
 var result:Dictionary=clip.frame_payload(row,timing.frame)
 result.direction=row;result.frame_index=timing.frame;result.selected_clip=selected
 result.static_fallback=not timing.valid;result.fallback_for="invalid_strike_timing" if not timing.valid else ""
 result.tint=Color.WHITE
 if not timing.valid:result.timing_error=timing.error
 else:
  result.source_progress=timing.progress
  result.outgoing_strike_sent=has_struck
 return result
