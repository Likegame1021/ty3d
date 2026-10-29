extends Node
## Map-only presentation. Never changes authored player/warning meshes, payloads, clocks,
## collision, actor transform, spawn budget or damage authority.
var _player: Node3D
var _director: Node3D
var _rim: ShaderMaterial
var _meshes: Array[Dictionary] = []
var _warnings: Dictionary = {}
var _location_marker: MeshInstance3D

func _ready() -> void:
 name="MapReadability"
 process_mode=Node.PROCESS_MODE_ALWAYS
 process_priority=100
 _rim=ShaderMaterial.new()
 _rim.shader=load(get_script().resource_path.get_base_dir().path_join("player_rim.gdshader"))
 _rim.render_priority=32
 _location_marker=_make_location_marker()
 add_child(_location_marker)
 _location_marker.visible=false

func bind(player:Node3D,director:Node3D) -> void:
 clear_visuals()
 _player=player;_director=director
 refresh_visuals()

func _process(_delta:float) -> void:
 if get_tree().paused or not is_instance_valid(_player) or _player.hp<=0:
  clear_visuals()
 else:
  refresh_visuals()

func refresh_visuals() -> void:
 if not is_instance_valid(_player) or not is_instance_valid(_director):return
 _refresh_location_marker()
 if _meshes.is_empty() and is_instance_valid(_player.visual):
  for mesh in _player.visual.find_children("*","MeshInstance3D",true,false):
   # Preserve any pre-existing presentation pass; current formal mesh has none.
   if mesh.material_overlay!=null:continue
   _meshes.append({"node":weakref(mesh),"overlay":mesh.material_overlay})
   mesh.material_overlay=_rim
 var live:Dictionary={}
 for warning in _director._attack_warnings:
  if not is_instance_valid(warning) or warning.is_queued_for_deletion():continue
  var id:int=warning.get_instance_id();live[id]=true
  if not _warnings.has(id):
   var pieces:Array=[]
   for node in warning.get_children():
    if not node is MeshInstance3D or not node.material_override is StandardMaterial3D:continue
    pieces.append({"node":weakref(node),"color":node.material_override.albedo_color,"priority":node.material_override.render_priority,"role":str(node.name)})
   _warnings[id]={"node":weakref(warning),"pieces":pieces}
  var remaining:float=maxf(0.0,float(warning.payload.duration)-float(warning.elapsed))
  # A shared 0.8-second visual horizon ranks equal remaining time equally.
  var urgency:float=clampf(1.0-remaining/.8,0.0,1.0)
  var hazard:bool=bool(warning.payload.get("hazard",false))
  for piece:Dictionary in _warnings[id].pieces:
   var node=piece.node.get_ref()
   if not is_instance_valid(node):continue
   var material:StandardMaterial3D=node.material_override
   var color:Color=piece.color
   if piece.role in ["DangerBoundary","DangerSymbol"]:
    # Keep the original pulse alpha and the exact original warning mesh.
    var alpha:float=material.albedo_color.a
    color=color.lerp(Color(1.0,.91,.66) if not hazard else Color(1.0,.65,.42),urgency*.85)
    color.a=alpha
    material.render_priority=int(piece.priority)+int(floor(urgency*8.0+0.00001))
   else:
    # Reduce additive visual clutter from six overlapping translucent discs;
    # every exact boundary/arrow remains present at its original opacity.
    color.a=minf(color.a,.065)
   material.albedo_color=color
 for id in _warnings.keys():
  if not live.has(id):_warnings.erase(id)

func clear_visuals() -> void:
 if is_instance_valid(_location_marker):_location_marker.visible=false
 for item in _meshes:
  var mesh=item.node.get_ref()
  if is_instance_valid(mesh):mesh.material_overlay=item.overlay
 _meshes.clear()
 for item in _warnings.values():
  for piece in item.pieces:
   var node=piece.node.get_ref()
   if not is_instance_valid(node):continue
   var color:Color=piece.color
   if piece.role=="DangerBoundary":color.a=node.material_override.albedo_color.a
   node.material_override.albedo_color=color
   node.material_override.render_priority=piece.priority
 _warnings.clear()

func _exit_tree() -> void:
 clear_visuals()

func _make_location_marker() -> MeshInstance3D:
 # Open blunt brackets identify the body root; they are not a hitbox or safe zone.
 var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 var lines:Array=[]
 for side in [-1.0,1.0]:
  var x:float=side*.31
  lines.append([Vector3(x,0,-.16),Vector3(x,0,.16)])
  lines.append([Vector3(x,0,-.16),Vector3(x-side*.13,0,-.16)])
  lines.append([Vector3(x,0,.16),Vector3(x-side*.13,0,.16)])
 for style in [{"width":.09,"color":Color(.035,.09,.12,1)},{"width":.043,"color":Color(.35,.96,1,1)}]:
  for line in lines:
   var a:Vector3=line[0];var b:Vector3=line[1]
   var side:Vector3=(b-a).cross(Vector3.UP).normalized()*float(style.width)*.5
   for point in [a-side,a+side,b+side,a-side,b+side,b-side]:
    surface.set_normal(Vector3.UP);surface.set_color(style.color);surface.add_vertex(point)
 var node:=MeshInstance3D.new();node.name="PlayerRootLocation"
 node.mesh=surface.commit();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var material:=StandardMaterial3D.new()
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.vertex_color_use_as_albedo=true
 material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 material.no_depth_test=true;material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
 material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.render_priority=34
 node.material_override=material
 return node

func _refresh_location_marker() -> void:
 var camera:Camera3D=get_viewport().get_camera_3d()
 if not is_instance_valid(camera) or camera.is_position_behind(_player.global_position):
  _location_marker.visible=false;return
 var screen:Vector2=camera.unproject_position(_player.global_position)
 if not get_viewport().get_visible_rect().has_point(screen):
  _location_marker.visible=false;return
 var right:Vector3=camera.global_basis.x;right.y=0;right=right.normalized()
 _location_marker.global_transform=Transform3D(Basis(right,Vector3.UP,right.cross(Vector3.UP)),_player.global_position+Vector3.UP*.025)
 _location_marker.visible=true
