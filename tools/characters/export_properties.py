import bpy
props=bpy.ops.export_scene.gltf.get_rna_type().properties
for p in props:
 if 'animation' in p.identifier or 'nla' in p.identifier or 'deform' in p.identifier:
  print(p.identifier,p.type,[(i.identifier) for i in p.enum_items] if p.type=='ENUM' else '')
