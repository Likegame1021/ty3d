import bpy,json
from mathutils import Vector
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=r'G:/Game/vallage/art/characters/boy/meshy/v001/rigging/rigged.glb')
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  pts=[o.matrix_world @ v.co for v in o.data.vertices]
  print('BOUNDS',o.name,[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)],'world',o.matrix_world)
  print('MODIFIERS',[(m.name,m.type) for m in o.modifiers], 'groups',len(o.vertex_groups))
