import bpy
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=r'G:/Game/vallage/art/characters/boy/meshy/v001/animations/animations.glb')
print('FPS',bpy.context.scene.render.fps)
for o in bpy.context.scene.objects:
 print('OBJ',o.name,o.type,'scale',list(o.scale))
 if o.animation_data:print('NLA',[(t.name,[(s.name,s.action.name,s.frame_start,s.frame_end) for s in t.strips]) for t in o.animation_data.nla_tracks])
for a in bpy.data.actions:
 print('ACTION',a.name,list(a.frame_range),[(s.identifier,s.target_id_type) for s in a.slots])
 for layer in a.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for fc in bag.fcurves:
     if 'location' in fc.data_path:print('FC',fc.data_path,fc.array_index,'range', min(k.co.y for k in fc.keyframe_points),max(k.co.y for k in fc.keyframe_points))
