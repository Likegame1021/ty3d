import bpy,bmesh,json
from mathutils import Vector
ROOT=r'G:/Game/vallage';OUT=ROOT+'/art/characters/boy/blender'
bpy.ops.wm.open_mainfile(filepath=OUT+'/boy-rigged-v001.blend')
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=850;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.world.color=(.12,.12,.12);scene.view_settings.view_transform='AgX'
center=Vector((0,0,.62))
for pos,power,size in [((2,-3,4),700,3),((-3,-1,2),350,3),((1,3,3),500,3)]:
 bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(1.5,-3.8,1.5));camera=bpy.context.object;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.65;scene.camera=camera
for t in arm.animation_data.nla_tracks:t.mute=True
action=bpy.data.actions['attack_branch'];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0];scene.frame_set(14,subframe=.4)
scene.render.filepath=OUT+'/normals-before.png';bpy.ops.render.render(write_still=True)
old_poly=len(mesh.data.polygons);old_uvs=sum(len(layer.data) for layer in mesh.data.uv_layers)
bm=bmesh.new();bm.from_mesh(mesh.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
for e in bm.edges:e.smooth=True
for f in bm.faces:f.smooth=True
bm.to_mesh(mesh.data);bm.free();mesh.data.update()
bpy.context.view_layer.objects.active=mesh
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True)
bpy.ops.mesh.customdata_custom_splitnormals_clear()
for e in mesh.data.edges:e.use_edge_sharp=False
for p in mesh.data.polygons:p.use_smooth=True
assert len(mesh.data.polygons)==old_poly
assert sum(len(layer.data) for layer in mesh.data.uv_layers)==old_uvs
scene.render.filepath=OUT+'/normals-after.png';bpy.ops.render.render(write_still=True)
# Keep candidate separate until the rendered comparison has been reviewed.
for o in list(bpy.context.scene.objects):
 if o not in [arm,mesh]:bpy.data.objects.remove(o,do_unlink=True)
arm.animation_data.action=None
from mathutils import Matrix
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
scene.frame_set(0);scene.camera=None
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/boy-rigged-v002.blend')
print('NORMAL_REPAIR_CANDIDATE_OK',len(mesh.data.vertices),len(mesh.data.polygons),'custom',mesh.data.has_custom_normals,flush=True)
