extends SkeletonModifier3D
## Isolated cancellation-only pose bridge. No source clips are edited.
const SUPPORT_FILE:="res://assets/characters/boy/normal_grip/cancel-support.json"
var bridge_active:=false
var holding:=false
var elapsed:=0.0
var duration:=0.16
var frozen:Array=[]
var last_visible:Array=[] # Compatibility observer only; never a freeze input.
var pose_channels
var channel_generation := -1
var channel_binding: StringName
var startup_unmodified := false
var isolation_failed := false
func configure_channels(channels, generation:int, binding:StringName, unmodified:bool) -> void:
 pose_channels=channels;channel_generation=generation;channel_binding=binding
 startup_unmodified=unmodified;isolation_failed=false
func canonical_frozen_input() -> Array:
 if isolation_failed:return []
 if pose_channels != null:
  var snapshot:Dictionary=pose_channels.canonical_copy(channel_generation,channel_binding)
  if snapshot.valid:return snapshot.pose
  if not pose_channels.produced_visual and startup_unmodified:return read_pose()
 isolation_failed=true
 push_error("Cancellation missing canonical snapshot; candidate invalid, visual fallback forbidden.")
 return []
var parents:Array[int]=[]
var points:Array=[]
var last_lift:=0.0
var maximum_lift:=0.0
func _ready() -> void:
 var sk:=get_skeleton()
 for bone in sk.get_bone_count():parents.append(sk.get_bone_parent(bone))
 var names:Array=[]
 for bone in sk.get_bone_count():names.append(sk.get_bone_name(bone))
 if not load_support_file(SUPPORT_FILE,names):
  push_warning("Cancellation support unavailable; original motion retained.")
func load_support_file(path:String,expected_names:Array) -> bool:
 points.clear()
 if not FileAccess.file_exists(path):return false
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null:return false
 var parser:=JSON.new()
 if parser.parse(file.get_as_text())!=OK:return false
 var data=parser.data
 if not data is Dictionary or not data.get("names") is Array or not data.get("points") is Array:return false
 if data.names!=expected_names or data.points.is_empty():return false
 var validated:Array=[]
 for point in data.points:
  if not point is Dictionary or not point.get("influences") is Array or point.influences.is_empty():return false
  var influences:Array=[]
  var total_weight:=0.0
  for entry in point.influences:
   if not entry is Dictionary:return false
   if typeof(entry.get("bone")) not in [TYPE_INT,TYPE_FLOAT] or typeof(entry.get("weight")) not in [TYPE_INT,TYPE_FLOAT]:return false
   var bone_value:=float(entry.bone)
   if not is_finite(bone_value) or bone_value<0 or bone_value>=expected_names.size():return false
   var bone:=int(bone_value)
   if float(bone)!=bone_value:return false
   var xyz=entry.get("bind_weighted_xyz")
   if not xyz is Array or xyz.size()!=3:return false
   for value in xyz:
    if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return false
   var vector:=Vector3(xyz[0],xyz[1],xyz[2])
   var weight:=float(entry.weight)
   if not vector.is_finite() or not is_finite(weight) or weight<=0.0 or weight>1.0001:return false
   total_weight+=weight
   influences.append([bone,vector,weight])
  if absf(total_weight-1.0)>.0001:return false
  validated.append(influences)
 points=validated
 return true
func read_pose() -> Array:
 var sk:=get_skeleton();var pose:Array=[]
 for bone in sk.get_bone_count():pose.append(sk.get_bone_pose(bone))
 return pose
func capture_visible_pose() -> void:
 last_visible=read_pose()
func freeze_visible_pose() -> void:
 if points.is_empty():return
 frozen=canonical_frozen_input()
 if frozen.is_empty():return
 bridge_active=true;holding=true;elapsed=0.0;last_lift=0.0
func begin_transition(to_idle:bool) -> void:
 if not holding:
  frozen=canonical_frozen_input()
  if frozen.is_empty():return
 duration=0.16 if to_idle else 0.14
 holding=false;elapsed=0.0
func advance_state(delta:float) -> void:
 if bridge_active and not holding:elapsed=minf(duration,elapsed+delta)
func clear_bridge() -> void:
 bridge_active=false;holding=false;elapsed=0.0;last_lift=0.0
 frozen.clear();last_visible.clear()
func globals_from(pose:Array) -> Array:
 var result:Array=[]
 for bone in pose.size():result.append(result[parents[bone]]*pose[bone] if parents[bone]>=0 else pose[bone])
 return result
func support_height(globals:Array,up:Vector3) -> float:
 var height:=INF
 for point in points:
  var position:=Vector3.ZERO
  for entry in point:
   var transform:Transform3D=globals[entry[0]]
   position+=transform.basis*entry[1]+transform.origin*entry[2]
  height=minf(height,position.dot(up))
 return height
func _process_modification() -> void:
 if not bridge_active or frozen.is_empty():return
 var sk:=get_skeleton()
 if not holding and elapsed>=duration:
  bridge_active=false;last_lift=0.0
  return
 var incoming:=read_pose()
 var alpha:=0.0 if holding else smoothstep(0.0,duration,elapsed)
 var blended:Array=[]
 for bone in incoming.size():blended.append(frozen[bone].interpolate_with(incoming[bone],alpha))
 last_lift=0.0
 if not holding:
  # Root-relative world-up frame: actor translation does not change the contract.
  var up:Vector3=sk.global_basis.transposed()*Vector3.UP
  var out_height:=support_height(globals_from(frozen),up)
  var in_height:=support_height(globals_from(incoming),up)
  var mixed_height:=support_height(globals_from(blended),up)
  last_lift=maxf(0.0,minf(out_height,in_height)-mixed_height)
  maximum_lift=maxf(maximum_lift,last_lift)
  var hip:=sk.find_bone("Hips")
  var delta:Vector3=(sk.global_basis.inverse()*Vector3.UP)*last_lift
  if parents[hip]>=0:delta=globals_from(blended)[parents[hip]].basis.inverse()*delta
  blended[hip].origin+=delta
 for bone in blended.size():sk.set_bone_pose(bone,blended[bone])
