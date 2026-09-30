import bpy, os, json, math
from mathutils import Vector
ROOT=r'G:/Game/vallage'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=ROOT+'/art/characters/boy/meshy/v001/model.glb')
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
report=[]
world_points=[]
for o in meshes:
 o.data.calc_loop_triangles()
 adjacency=[[] for _ in o.data.vertices]
 for e in o.data.edges:
  a,b=e.vertices; adjacency[a].append(b); adjacency[b].append(a)
 seen=set(); components=[]
 for v in range(len(adjacency)):
  if v in seen: continue
  stack=[v]; seen.add(v); count=0
  while stack:
   q=stack.pop(); count+=1
   for k in adjacency[q]:
    if k not in seen: seen.add(k); stack.append(k)
  components.append(count)
 points=[o.matrix_world @ Vector(c) for c in o.bound_box]; world_points.extend(points)
 report.append(dict(name=o.name,vertices=len(o.data.vertices),triangles=len(o.data.loop_triangles),materials=[m.name for m in o.data.materials if m],dimensions=list(o.dimensions),location=list(o.location),rotation=list(o.rotation_euler),scale=list(o.scale),connected_components=len(components),largest_components=sorted(components,reverse=True)[:20],loose_vertices=sum(1 for a in adjacency if not a)))
lo=Vector(tuple(min(p[i] for p in world_points) for i in range(3))); hi=Vector(tuple(max(p[i] for p in world_points) for i in range(3))); center=(lo+hi)/2
out=ROOT+'/art/characters/boy/blender'
with open(out+'/precheck-data.json','w',encoding='utf-8') as f: json.dump(dict(objects=report,bounds_min=list(lo),bounds_max=list(hi),dimensions=list(hi-lo),images=[dict(name=i.name,size=list(i.size),packed=bool(i.packed_file)) for i in bpy.data.images]),f,indent=2,ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=out+'/boy-unrigged-v001.blend')
# Neutral studio preview; preserve the imported mesh and original transforms.
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=1100; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
scene.world.color=(.15,.15,.15); scene.view_settings.view_transform='AgX'
height=hi.z-lo.z
for name,pos,power,size in [('key',(2,-3,4),950,3),('fill',(-3,-1,2),500,4),('rim',(1,3,3),800,3)]:
 bpy.ops.object.light_add(type='AREA',location=center+Vector(pos)*height/2)
 light=bpy.context.object; light.name=name; light.data.energy=power; light.data.shape='DISK'; light.data.size=size; light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=center+Vector((.8,-2.8,.45))*height)
camera=bpy.context.object; camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler(); camera.data.type='ORTHO'; camera.data.ortho_scale=height*1.38; scene.camera=camera
scene.render.filepath=out+'/boy-unrigged-v001-preview.png'; bpy.ops.render.render(write_still=True)
print('CHARACTER_PRECHECK',json.dumps(report), 'BOUNDS',list(lo),list(hi))
