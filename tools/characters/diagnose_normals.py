import bpy,collections,json,math
from mathutils import Vector
ROOT=r'G:/Game/vallage'
results=[]
for path in ['/art/characters/boy/meshy/v001/animations/animations.glb','/game/assets/characters/boy/boy.glb']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=ROOT+path)
 mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and len(o.vertex_groups)>0)
 groups=collections.defaultdict(list)
 for v in mesh.data.vertices:groups[tuple(round(c,5) for c in v.co)].append(v)
 unequal=0;max_delta=0
 for vertices in groups.values():
  ref={g.group:g.weight for g in vertices[0].groups}
  for vertex in vertices[1:]:
   weights={g.group:g.weight for g in vertex.groups}
   delta=max([abs(weights.get(g,0)-ref.get(g,0)) for g in set(ref)|set(weights)] or [0])
   if delta>1e-5:unequal+=1
   max_delta=max(max_delta,delta)
 info=dict(path=path,vertices=len(mesh.data.vertices),polygons=len(mesh.data.polygons),unique_positions=len(groups),has_custom_normals=mesh.data.has_custom_normals,smooth_polygons=sum(p.use_smooth for p in mesh.data.polygons),duplicate_weight_mismatches=unequal,max_duplicate_weight_delta=max_delta)
 print('NORMAL_DIAGNOSIS',info);results.append(info)
with open(ROOT+'/art/characters/boy/blender/normal-diagnosis.json','w') as f:json.dump(results,f,indent=2)
