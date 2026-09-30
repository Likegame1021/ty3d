import bpy,bmesh,json
path=r'G:/Game/vallage/art/characters/boy/blender/'
bpy.ops.wm.open_mainfile(filepath=path+'boy-unrigged-v001.blend')
results=[]
for o in bpy.context.scene.objects:
 if o.type!='MESH': continue
 bm=bmesh.new(); bm.from_mesh(o.data); bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001)
 seen=set(); comps=[]
 for v in bm.verts:
  if v in seen:continue
  stack=[v];seen.add(v);component=[]
  while stack:
   w=stack.pop();component.append(w)
   for e in w.link_edges:
    n=e.other_vert(w)
    if n not in seen:seen.add(n);stack.append(n)
  lo=[min(v.co[i] for v in component) for i in range(3)];hi=[max(v.co[i] for v in component) for i in range(3)]
  comps.append(dict(vertices=len(component),min=lo,max=hi))
 results.append(dict(name=o.name,welded_vertices=len(bm.verts),components=sorted(comps,key=lambda c:c['vertices'],reverse=True)))
 bm.free()
with open(path+'welded-analysis.json','w') as f:json.dump(results,f,indent=2)
print('WELDED_COMPONENTS',[(r['name'],r['welded_vertices'],len(r['components']),r['components'][:12]) for r in results])
