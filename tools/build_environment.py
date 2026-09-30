import bpy, math, random, os
from mathutils import Vector
ROOT=r'G:/Game/vallage'
random.seed(29)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(name,col):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*col,1); bs.inputs['Roughness'].default_value=.88
 return m
leaf=mat('leaf_olive',(.27,.43,.055)); stem=mat('stem_green',(.32,.48,.08)); tip=mat('silk_gold',(.68,.49,.18)); wood=mat('weathered_wood',(.34,.21,.105)); cut=mat('wood_cut',(.51,.34,.16)); stone=mat('warm_limestone',(.43,.41,.32)); straw=mat('sun_dried_straw',(.67,.48,.20)); clay=mat('terracotta',(.42,.19,.10))
def cyl(p,q,r,material,vertices=8):
 d=Vector(q)-Vector(p); bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r*.8,depth=d.length,location=(Vector(p)+Vector(q))/2)
 o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); o.data.materials.append(material); return o

def box(loc,size,material,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.scale=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(material)
 if bevel:
  mod=o.modifiers.new('soft worn edges','BEVEL'); mod.width=bevel; mod.segments=1; bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
 return o

def sphere(loc,scale,material):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=loc); o=bpy.context.object; o.scale=scale; o.data.materials.append(material); return o

def export(name):
 objs=list(bpy.context.scene.objects); bpy.ops.object.select_all(action='SELECT'); bpy.context.view_layer.objects.active=objs[0]; bpy.ops.object.join(); o=bpy.context.object; o.name=name
 # Export loop colors for corn's single shader, while retaining material slots.
 colors=o.data.color_attributes.new(name='Color',type='BYTE_COLOR',domain='CORNER')
 for poly in o.data.polygons:
  col=o.data.materials[poly.material_index].diffuse_color
  for idx in poly.loop_indices: colors.data[idx].color=col
 bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR'); bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/art/environment/'+name+'.blend')
 bpy.ops.export_scene.gltf(filepath=ROOT+'/game/assets/environment/'+name+'.glb',export_format='GLB',use_selection=True,export_yup=True)
 print('ENV_ASSET',name,len(o.data.vertices),len(o.data.polygons))
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

# Thick curved tapered corn leaves with a central crease; each leaf has top/bottom faces.
cyl((0,0,0),(0,0,2.05),.025,stem)
for n in range(8):
 h=.32+n*.20; a=n*2.399; length=.65 if n<6 else .42
 verts=[]
 for i in range(7):
  t=i/6; reach=length*t; z=h+.34*math.sin(t*math.pi*.85)-.16*t*t
  width=.095*(math.sin(math.pi*t)**.7)+.004
  for side in [-1,0,1]:
   x=reach*math.cos(a)+side*width*math.sin(a); y=reach*math.sin(a)-side*width*math.cos(a)
   verts.append((x,y,z+(.035*math.sin(math.pi*t) if side==0 else 0)))
 faces=[]
 for i in range(6):
  for j in range(2):
   faces.append((i*3+j,i*3+j+1,(i+1)*3+j+1,(i+1)*3+j))
 mesh=bpy.data.meshes.new('leaf'); mesh.from_pydata(verts,[],faces); mesh.update(); o=bpy.data.objects.new('curved leaf',mesh); bpy.context.collection.objects.link(o); o.data.materials.append(leaf)
 bpy.context.view_layer.objects.active=o; mod=o.modifiers.new('leaf thickness','SOLIDIFY'); mod.thickness=.007; bpy.ops.object.modifier_apply(modifier=mod.name)
for a in [0,1.8,3.6]:
 cyl((0,0,1.92),(.13*math.cos(a),.13*math.sin(a),2.27),.009,tip,5)
 for j in range(3):
  h=2.03+j*.06; cyl((.04*math.cos(a),.04*math.sin(a),h),(.15*math.cos(a),.15*math.sin(a),h+.06),.006,tip,4)
sphere((.065,0,1.10),(.065,.055,.20),tip)
export('corn')
# Rough rail fence with rounded posts.
for x in [-1,1]: cyl((x,0,0),(x,0,1.05),.065,wood); sphere((x,0,1.04),(.066,.065,.07),cut)
for z in [.40,.79]: cyl((-1.04,0,z),(1.04,0,z+.045),.047,wood)
export('fence')
for i in range(3):
 sphere((random.uniform(-.20,.20),random.uniform(-.15,.15),.15),(.38,.27,.24),stone)
export('rocks')
for axis in [0,1]:
 for side in [-1,1]:
  for j in range(5):
   loc=[0,0,.12+j*.13]; loc[axis]=side*.36; size=[.70,.055,.115]; size[axis]=.055; size[1-axis]=.70
   box(loc,size,wood,.008)
for j in range(5): box((-.28+j*.14,0,.05),(.12,.7,.08),cut,.01)
for x in [-.28,.28]: box((x,-.405,.34),(.075,.04,.65),cut,.012)
export('crate')
for h,r in [(0,.65),(.3,.59),(.60,.43),(.9,.24)]: sphere((0,0,h+.19),(r,r*.8,.28),straw)
cyl((0,0,0),(0,0,1.3),.035,wood)
for i in range(36):
 a=random.random()*math.tau; r=random.uniform(.15,.6); cyl((r*math.cos(a),r*.8*math.sin(a),.05),(r*.5*math.cos(a),r*.4*math.sin(a),random.uniform(.6,1.12)),.012,tip,4)
export('haystack')
# Village pottery jar with a genuinely hollow mouth.
verts=[]; rings=[(.0,.23),(.12,.36),(.40,.39),(.66,.24),(.71,.21),(.73,.20),(.68,.17)]
for z,r in rings:
 for j in range(16): a=j*math.tau/16; verts.append((r*math.cos(a),r*math.sin(a),z))
faces=[]
for i in range(len(rings)-1):
 for j in range(16): faces.append((i*16+j,i*16+(j+1)%16,(i+1)*16+(j+1)%16,(i+1)*16+j))
mesh=bpy.data.meshes.new('jar'); mesh.from_pydata(verts,[],faces); o=bpy.data.objects.new('jar',mesh); bpy.context.collection.objects.link(o); o.data.materials.append(clay)
export('jar')

# Additional reusable verge grass and a clustered broadleaf tree.
for i in range(9):
 a=i*2.399; r=.11*(i%3); p=(r*math.cos(a),r*math.sin(a),0); h=random.uniform(.19,.42)
 cyl(p,(p[0]+.07*math.cos(a),p[1]+.07*math.sin(a),h),.015,leaf,4)
export('grass')
cyl((0,0,0),(.10,0,2.8),.16,wood,9)
for i in range(7):
 a=i*2.4; end=(math.cos(a)*1.05,math.sin(a)*.9,2.5+(i%3)*.25)
 cyl((.08,0,1.7),end,.075,wood,7)
 for j in range(3): sphere((end[0]+random.uniform(-.35,.35),end[1]+random.uniform(-.3,.3),end[2]+.45+j*.12),(.78,.70,.65),leaf if j%2 else stem)
sphere((0,0,3.32),(1.1,.9,.8),leaf)
export('tree')
