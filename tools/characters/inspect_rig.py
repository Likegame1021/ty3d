import bpy,json
from mathutils import Vector
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=r'G:/Game/vallage/art/characters/boy/meshy/v001/rigging/rigged.glb')
for o in bpy.context.scene.objects:
 print('OBJ',o.name,o.type,list(o.dimensions),list(o.location),list(o.scale),'parent',o.parent.name if o.parent else None)
 if o.type=='ARMATURE':
  for b in o.data.bones: print('BONE',b.name,'parent',b.parent.name if b.parent else None,'head',list(b.head_local),'tail',list(b.tail_local))
for a in bpy.data.actions: print('ACTION',a.name,list(a.frame_range),'slots',[(s.identifier,s.target_id_type) for s in a.slots])
