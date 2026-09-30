import bpy, json, math, os
from mathutils import Vector,Matrix
ROOT=r'G:/Game/vallage'; OUT=ROOT+'/art/characters/boy/blender'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=ROOT+'/art/characters/boy/meshy/v001/animations/animations.glb')
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'); mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.modifiers)
for pb in arm.pose.bones:pb.custom_shape=None
for o in list(bpy.context.scene.objects):
 if o not in [arm,mesh]:bpy.data.objects.remove(o,do_unlink=True)
actions=list(bpy.data.actions)
mapping={'Idle':'idle','Casual_Walk_inplace':'walk','Run_02':'run','Right_Hand_Sword_Slash':'attack_branch'}
assert len(actions)==4
# Meshy exports centimetre bone/mesh data under a .01 Armature node. Normalize both data blocks and all translation channels together.
factor=arm.scale.x
arm.data.transform(Matrix.Scale(factor,4));mesh.data.transform(Matrix.Scale(factor,4));arm.scale=(1,1,1)
def curves(action):
 return [fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
for action in actions:
 action.name=mapping[action.name]
 for fc in curves(action):
  if fc.data_path.endswith('.location'):
   for k in fc.keyframe_points:
    k.co.y*=factor;k.handle_left.y*=factor;k.handle_right.y*=factor
 for track in list(arm.animation_data.nla_tracks):arm.animation_data.nla_tracks.remove(track)
arm.animation_data.action=None
scene=bpy.context.scene; fps=scene.render.fps; clips={}
for action in actions:
 arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
 start,end=map(float,action.frame_range)
 frames=sorted(set([float(i) for i in range(math.ceil(start),math.floor(end)+1)]+[start,end]))
 samples=[]
 for frame in frames:
  scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
  matrix=arm.pose.bones['Hips'].matrix.copy()
  matrix.translation.x=arm.data.bones['Hips'].matrix_local.translation.x
  matrix.translation.y=arm.data.bones['Hips'].matrix_local.translation.y
  samples.append((frame,matrix))
 # Remove subframe source root keys as well; leaving them would restore drift between inserted integer keys.
 for layer in action.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for fc in list(bag.fcurves):
     if fc.data_path=='pose.bones["Hips"].location':bag.fcurves.remove(fc)
 for frame,matrix in samples:
  scene.frame_set(int(frame),subframe=frame-int(frame));arm.pose.bones['Hips'].matrix=matrix
  arm.pose.bones['Hips'].keyframe_insert(data_path='location',frame=frame,group='Hips')
 for fc in curves(action):
  if fc.data_path=='pose.bones["Hips"].location':
   for key in fc.keyframe_points:key.interpolation='LINEAR'
 # Pose samples are geometry checks, not a guarantee that every intermediate frame is perfect.
 poses=[]
 for fraction in [0,.25,.5,.75,1]:
  frame=start+(end-start)*fraction;scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
  evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());pts=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
  lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
  hips=arm.matrix_world@arm.pose.bones['Hips'].matrix.translation
  poses.append(dict(fraction=fraction,min=lo,max=hi,hips=list(hips)))
  assert hi[2]-lo[2]<1.6 and hi[0]-lo[0]<1.6,'Exploded normalization deformation'
 clips[action.name]=dict(seconds=(end-start)/fps,frames=[start,end],sampled_bounds=poses)
arm.animation_data.action=None
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
scene.frame_set(0);bpy.context.view_layer.update()
pts=[mesh.matrix_world@v.co for v in mesh.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
assert abs(hi[2]-lo[2]-1.2)<.001 and abs(lo[2])<.001
for action in actions:
 track=arm.animation_data.nla_tracks.new();track.name=action.name
 strip=track.strips.new(action.name,1,action);strip.action_slot=action.slots[0]
 # Stashed tracks must not compound in the editable default pose.
 track.mute=True
for poly in mesh.data.polygons:poly.use_smooth=True
arm.name='BoyRig';mesh.name='BoyBody';scene.frame_start=0;scene.frame_end=102
bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=arm
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/boy-rigged-v001.blend')
# NLA_TRACKS explicitly exports independent clips, without relying on old default Action merging.
bpy.ops.export_scene.gltf(filepath=ROOT+'/game/assets/characters/boy/boy.glb',export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_optimize_animation_size=True)
report=dict(scale=1.2,rest_min=lo,rest_max=hi,armature_scale=list(arm.scale),bones=[b.name for b in arm.data.bones],right_hand='RightHand',clips=clips)
with open(OUT+'/rigged-validation.json','w') as f:json.dump(report,f,indent=2)
print('CHARACTER_EXPORT_OK',json.dumps({k:v['seconds'] for k,v in clips.items()}),flush=True)
# Studio previews of real evaluated poses after the export.
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=850;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.world.color=(.12,.12,.12);scene.view_settings.view_transform='AgX'
center=Vector((0,0,.62))
for pos,power,size in [((2,-3,4),700,3),((-3,-1,2),350,3),((1,3,3),500,3)]:
 bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(1.5,-3.8,1.5));camera=bpy.context.object;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.65;scene.camera=camera
for name,fraction in [('idle',.25),('run',.25),('attack_branch',.40)]:
 action=next(a for a in actions if a.name==name);arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
 frame=action.frame_range[0]+(action.frame_range[1]-action.frame_range[0])*fraction;scene.frame_set(int(frame),subframe=frame-int(frame))
 scene.render.filepath=OUT+'/pose-'+name+'.png';bpy.ops.render.render(write_still=True)
print('CHARACTER_PREVIEWS_OK',flush=True)

