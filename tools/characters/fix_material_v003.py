import bpy,json,struct
from mathutils import Matrix
ROOT=r'G:/Game/vallage';OUT=ROOT+'/art/characters/boy/blender'
bpy.ops.wm.open_mainfile(filepath=OUT+'/boy-rigged-v002.blend')
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
def state():
 return dict(bones=[(b.name,b.parent.name if b.parent else None,[list(r) for r in b.matrix_local]) for b in arm.data.bones],actions=[(a.name,list(a.frame_range),[(fc.data_path,fc.array_index,[(list(k.co),k.interpolation) for k in fc.keyframe_points]) for l in a.layers for s in l.strips for bag in s.channelbags for fc in bag.fcurves]) for a in sorted(bpy.data.actions,key=lambda a:a.name)])
before=state()
for material in mesh.data.materials:
 bs=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 base_links=[(l.from_node.name,l.from_socket.name) for l in bs.inputs['Base Color'].links]
 for name,value in [('Metallic',0.0),('Roughness',.8),('Specular IOR Level',.25),('Emission Strength',0.0)]:
  socket=bs.inputs.get(name)
  if socket:
   for link in list(socket.links):material.node_tree.links.remove(link)
   socket.default_value=value
 for name in ['Emission Color','Emission','Specular Tint']:
  socket=bs.inputs.get(name)
  if socket:
   for link in list(socket.links):material.node_tree.links.remove(link)
   if name=='Specular Tint':socket.default_value=(1,1,1,1)
   else:socket.default_value=(0,0,0,1)
 assert base_links==[(l.from_node.name,l.from_socket.name) for l in bs.inputs['Base Color'].links]
 print('MATERIAL_FIXED',material.name,'base texture links',base_links)
assert before==state(),'Skeleton/animation changed'
arm.animation_data.action=None
for track in arm.animation_data.nla_tracks:track.mute=True
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/boy-rigged-v003.blend')
bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=arm
path=ROOT+'/game/assets/characters/boy/boy.glb'
bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_optimize_animation_size=True)
with open(path,'rb') as f:
 header=f.read(12);length,kind=struct.unpack('<II',f.read(8));data=json.loads(f.read(length))
for material in data['materials']:
 pbr=material['pbrMetallicRoughness'];assert pbr.get('metallicFactor',1)==0
 assert abs(pbr.get('roughnessFactor',1)-.8)<.00001
 assert 'baseColorTexture' in pbr
 assert material.get('emissiveFactor',[0,0,0])==[0,0,0]
 assert 'emissiveTexture' not in material
 spec=material.get('extensions',{}).get('KHR_materials_specular',{})
 assert max(spec.get('specularColorFactor',[1,1,1]))<=1
 print('GLB_MATERIAL_VERIFIED',json.dumps(material))
assert set(a['name'] for a in data['animations'])=={'idle','walk','run','attack_branch'}
with open(OUT+'/material-v003-verification.json','w') as f:json.dump(dict(materials=data['materials'],animations=[a['name'] for a in data['animations']],bones_and_animation_keys_unchanged=True,base_color_texture_preserved=True),f,indent=2)
print('MATERIAL_V003_EXPORT_OK')
