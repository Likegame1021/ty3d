"""Read-only Blender structure report for a downloaded Meshy static GLB."""

import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) != 1:
        raise ValueError("Usage: blender -b --python inspect_meshy_static.py -- INPUT.glb")
    source = Path(argv[0]).resolve()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    low = [min(point[i] for point in points) for i in range(3)]
    high = [max(point[i] for point in points) for i in range(3)]
    materials = []
    for material in bpy.data.materials:
        links = []
        if material.use_nodes:
            links = ["%s.%s -> %s.%s" % (link.from_node.name, link.from_socket.name,
                                             link.to_node.name, link.to_socket.name)
                     for link in material.node_tree.links]
        materials.append({"name": material.name, "metallic": material.metallic,
                          "roughness": material.roughness,
                          "surface_render_method": str(getattr(material, "surface_render_method", "unknown")),
                          "use_backface_culling": bool(getattr(material, "use_backface_culling", False)),
                          "links": links})
    report = {
        "source": str(source),
        "mesh_count": len(meshes),
        "meshes": [{"name": obj.name, "vertices": len(obj.data.vertices), "polygons": len(obj.data.polygons)} for obj in meshes],
        "total_polygons": sum(len(obj.data.polygons) for obj in meshes),
        "polygons_above_midheight": sum(1 for obj in meshes for polygon in obj.data.polygons
                                         if (obj.matrix_world @ polygon.center).z > (low[2] + high[2]) * 0.5),
        "bounds_blender_xyz": {"min": low, "max": high, "size": [high[i] - low[i] for i in range(3)]},
        "materials": materials,
        "images": [{"name": image.name, "size": list(image.size)} for image in bpy.data.images],
    }
    print("MESHY_STATIC_INSPECTION " + json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
