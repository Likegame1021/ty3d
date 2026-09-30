import bpy,json,hashlib
from mathutils import Matrix
ROOT=r'G:/Game/vallage';OUT=ROOT+'/art/characters/boy/blender'
def snapshot(path):
 bpy.ops.wm.open_mainfile(filepath=path)
 arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
 bones=[(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in arm.data.bones]
 actions=[]
 for action in sorted(bpy.data.actions,key=lambda a:a.name):
  curves=[fc for l in action.layers for s in l.strips for b in s.channelbags for fc in b.fcurves]
  actions.append((action.name,list(action.frame_range),[(fc.data_path,fc.array_index,[(list(k.co),k.interpolation) for k in fc.keyframe_points]) for fc in curves]))
 poses={}
 for a in bpy.data.actions:
  arm.animation_data.action=a;arm.animation_data.action_slot=a.slots[0]
  for t in arm.animation_data.nla_tracks:t.mute=True
  for fraction in [0,.25,.40,.5,.75,1]:
   frame=float(a.frame_range[1])*fraction;bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
   e=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());poses[(a.name,fraction)]=set(tuple(round(c,5) for c in e.matrix_world@v.co) for v in e.data.vertices)
 return bones,actions,poses
before=snapshot(OUT+'/boy-rigged-v001.blend');after=snapshot(OUT+'/boy-rigged-v002.blend')
assert before[0]==after[0],'Bone matrices changed'
assert before[1]==after[1],'Animation keys changed'
differences={str(k):len(before[2][k]^after[2][k]) for k in before[2]}
assert max(differences.values())==0,'Geometry positions changed at 1e-5m quantization'
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
arm.animation_data.action=None
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.scene.frame_set(0);bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=arm
bpy.ops.export_scene.gltf(filepath=ROOT+'/game/assets/characters/boy/boy.glb',export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_optimize_animation_size=True)
with open(OUT+'/normal-repair-verification.json','w') as f:json.dump(dict(bones_unchanged=True,animation_keys_unchanged=True,geometry_sample_differences=differences,vertex_count=len(mesh.data.vertices),triangle_count=len(mesh.data.polygons),custom_normals=mesh.data.has_custom_normals),f,indent=2)
print('NORMAL_REPAIR_EXPORT_OK bones=unchanged clips=unchanged geometry=unchanged vertices=',len(mesh.data.vertices))
