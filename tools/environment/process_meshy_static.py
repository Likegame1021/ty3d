"""Normalize one Meshy static GLB for Godot, retaining a Blender master.

Run with Blender in the background, passing arguments after ``--``. Example:

  D:/blender.exe -b --python tools/environment/process_meshy_static.py -- \
    --input art/environment/meshy/raw/cart.glb --name cart \
    --max-size 2.5 1.7 1.5

All dimensions here are meters in Blender X/Y/Z (Godot X/Z/Y). ``--roof-min-z``
splits upward-facing high polygons into a separate RoofVisual glTF node. The
caller must inspect that result before using a shed in the game.
"""

import argparse
import json
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--name", required=True, choices=("shed", "cart", "tree"))
    size_group = parser.add_mutually_exclusive_group(required=True)
    size_group.add_argument("--max-size", nargs=3, type=float, metavar=("X", "Y", "Z"))
    size_group.add_argument("--exact-size", nargs=3, type=float, metavar=("X", "Y", "Z"))
    parser.add_argument("--yaw-deg", type=float, default=0.0)
    parser.add_argument("--decimate-ratio", type=float, default=1.0)
    parser.add_argument("--texture-max", type=int, default=2048)
    parser.add_argument("--roof-min-z", type=float)
    parser.add_argument("--add-canopy", action="store_true")
    parser.add_argument("--output-glb")
    parser.add_argument("--output-blend")
    return parser.parse_args(argv)


def world_bounds(meshes):
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    if not points:
        raise ValueError("GLB contains no mesh bounds")
    low = Vector(tuple(min(point[i] for point in points) for i in range(3)))
    high = Vector(tuple(max(point[i] for point in points) for i in range(3)))
    return low, high


def clean_materials(meshes):
    seen = set()
    names = []
    for obj in meshes:
        for slot in obj.material_slots:
            material = slot.material
            if material is None or material.name in seen:
                continue
            seen.add(material.name)
            names.append(material.name)
            material.use_nodes = True
            material.metallic = 0.0
            material.roughness = 0.78
            for node in material.node_tree.nodes:
                if node.type != "BSDF_PRINCIPLED":
                    continue
                for label, value in (("Metallic", 0.0), ("Roughness", 0.78),
                                     ("Specular IOR Level", 0.35),
                                     ("Emission Strength", 0.0),
                                     ("Emission Color", (0.0, 0.0, 0.0, 1.0))):
                    socket = node.inputs.get(label)
                    if socket is None:
                        continue
                    if label.startswith("Emission") or label in {"Metallic", "Roughness"}:
                        for link in list(socket.links):
                            material.node_tree.links.remove(link)
                    socket.default_value = value
    return names


def split_roof(meshes, min_z):
    roof = [obj for obj in meshes if "roof" in obj.name.lower() or "top_cover" in obj.name.lower()]
    selected_faces = 0
    if not roof:
        candidate = max(meshes, key=lambda obj: len(obj.data.polygons))
        bpy.ops.object.select_all(action="DESELECT")
        candidate.select_set(True)
        bpy.context.view_layer.objects.active = candidate
        bpy.context.tool_settings.mesh_select_mode = (False, False, True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for polygon in candidate.data.polygons:
            center = candidate.matrix_world @ polygon.center
            polygon.select = center.z >= min_z
            selected_faces += int(polygon.select)
        if selected_faces == 0 or selected_faces == len(candidate.data.polygons):
            raise ValueError("Roof split selected none or all faces; inspect raw GLB and adjust --roof-min-z")
        before = set(bpy.data.objects)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        roof = [obj for obj in set(bpy.data.objects) - before if obj.type == "MESH"]
        if not roof:
            raise ValueError("Roof face separation produced no mesh")
    for index, obj in enumerate(roof):
        obj.name = "RoofSurface_%02d" % index
    return roof, selected_faces


def reparent_preserving_world(obj, parent):
    transform = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = transform


def add_canopy():
    """Keep Meshy's trunk and build broad, low-cost leaf masses around branches."""
    leaf_colors = [
        (0.080, 0.130, 0.045, 1.0),
        (0.110, 0.170, 0.055, 1.0),
        (0.150, 0.220, 0.065, 1.0),
        (0.190, 0.250, 0.075, 1.0),
        (0.095, 0.150, 0.050, 1.0),
    ]
    materials = []
    for index, color in enumerate(leaf_colors):
        material = bpy.data.materials.new("CanopyOlive_%02d" % index)
        material.diffuse_color = color
        material.use_nodes = True
        principled = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
        image = bpy.data.images.new("CanopyLeafTexture_%02d" % index, width=256, height=256, alpha=True)
        pixels = []
        for py in range(256):
            for px in range(256):
                u = px / 256.0 * 12.0
                v = py / 256.0 * 9.0
                cell_x, cell_y = math.floor(u), math.floor(v)
                jitter = math.sin(cell_x * 19.3 + cell_y * 7.1 + index * 13.7)
                dx = u - cell_x - 0.5 - 0.11 * jitter
                dy = v - cell_y - 0.5 - 0.08 * math.cos(cell_x * 4.7 + cell_y * 11.2)
                leaf = math.exp(-((dx + 0.35 * dy) / 0.26) ** 2 - (dy / 0.37) ** 2)
                vein = math.exp(-(dx / 0.035) ** 2 - (dy / 0.30) ** 2)
                mottling = math.sin(u * 5.3 + v * 2.9) * math.sin(v * 7.7 - u * 1.9)
                shade = 0.87 + 0.11 * leaf + 0.055 * vein + 0.035 * mottling
                pixels.extend((color[0] * shade, color[1] * shade, color[2] * shade, 1.0))
        image.pixels[:] = pixels
        image.pack()
        texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = image
        material.node_tree.links.new(texture.outputs["Color"], principled.inputs["Base Color"])
        principled.inputs["Metallic"].default_value = 0.0
        principled.inputs["Roughness"].default_value = 0.9
        materials.append(material)
    clusters = [
        (-0.58, -0.12, 0.18, 0.34, 0.30, 0.25, 0),
        (-0.40, 0.06, 0.39, 0.39, 0.32, 0.28, 1),
        (-0.14, -0.10, 0.53, 0.37, 0.33, 0.30, 2),
        (0.17, -0.08, 0.53, 0.39, 0.34, 0.29, 3),
        (0.47, -0.04, 0.38, 0.38, 0.31, 0.27, 1),
        (0.65, -0.14, 0.17, 0.31, 0.27, 0.24, 0),
        (-0.67, 0.12, 0.32, 0.30, 0.27, 0.24, 2),
        (0.61, 0.15, 0.34, 0.35, 0.30, 0.25, 3),
        (-0.37, -0.39, 0.23, 0.33, 0.28, 0.24, 0),
        (0.35, -0.38, 0.24, 0.35, 0.28, 0.26, 1),
        (-0.12, -0.34, 0.70, 0.38, 0.32, 0.27, 3),
        (0.24, 0.21, 0.65, 0.38, 0.32, 0.28, 4),
        (-0.27, 0.26, 0.61, 0.36, 0.29, 0.27, 2),
        (0.02, 0.06, 0.83, 0.38, 0.34, 0.27, 3),
        (-0.58, -0.22, 0.49, 0.29, 0.24, 0.23, 4),
        (0.55, -0.24, 0.51, 0.31, 0.26, 0.23, 2),
        (-0.04, 0.35, 0.35, 0.36, 0.25, 0.26, 1),
        (0.07, -0.50, 0.39, 0.32, 0.23, 0.24, 0),
    ]
    canopy_objects = []
    for index, (x, y, z, sx, sy, sz, material_index) in enumerate(clusters):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=1.0, location=(x, y, z))
        obj = bpy.context.object
        obj.name = "CanopyCluster_%02d" % index
        obj.scale = (sx, sy, sz)
        obj.data.materials.append(materials[material_index])
        for vertex in obj.data.vertices:
            coordinate = vertex.co
            ripple = 1.0 + 0.075 * math.sin(coordinate.x * 7.0 + index * 1.9)
            ripple += 0.055 * math.cos(coordinate.y * 8.0 + coordinate.z * 5.0 + index)
            vertex.co *= ripple
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        canopy_objects.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in canopy_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = canopy_objects[0]
    bpy.ops.object.join()
    bpy.context.object.name = "RecoveredLeafCanopy"
    return len(bpy.context.object.data.polygons)


def main():
    args = arguments()
    source = (ROOT / args.input).resolve() if not Path(args.input).is_absolute() else Path(args.input)
    if not source.is_file():
        raise FileNotFoundError(source)
    if source.suffix.lower() != ".glb":
        raise ValueError("Input must be a GLB")
    size_limits = args.max_size if args.max_size is not None else args.exact_size
    if any(value <= 0 for value in size_limits):
        raise ValueError("Target dimensions must be positive")
    if not 0.05 <= args.decimate_ratio <= 1.0:
        raise ValueError("--decimate-ratio must be between 0.05 and 1")
    if args.texture_max < 128:
        raise ValueError("--texture-max must be at least 128")
    output_glb = Path(args.output_glb) if args.output_glb else ROOT / "game/assets/environment/meshy" / (args.name + ".glb")
    output_blend = Path(args.output_blend) if args.output_blend else ROOT / "art/environment/meshy" / (args.name + "-v001.blend")
    output_glb.parent.mkdir(parents=True, exist_ok=True)
    output_blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.import_scene.gltf(filepath=str(source))
    canopy_polygons = add_canopy() if args.add_canopy else 0
    for obj in list(bpy.context.scene.objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise ValueError("Imported GLB contains no mesh")
    original_low, original_high = world_bounds(meshes)
    if args.decimate_ratio < 1.0:
        for obj in meshes:
            if len(obj.data.polygons) > 3000:
                modifier = obj.modifiers.new("DisplayBudget", "DECIMATE")
                modifier.ratio = args.decimate_ratio
    material_names = clean_materials(meshes)
    for image in bpy.data.images:
        width, height = image.size
        longest = max(width, height)
        if longest > args.texture_max:
            factor = args.texture_max / longest
            image.scale(max(1, round(width * factor)), max(1, round(height * factor)))
    roof = []
    selected_faces = 0
    if args.roof_min_z is not None:
        roof, selected_faces = split_roof(meshes, args.roof_min_z)
        meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    asset_root = bpy.data.objects.new("AssetRoot", None)
    bpy.context.collection.objects.link(asset_root)
    for obj in list(bpy.context.scene.objects):
        if obj != asset_root and obj.parent is None:
            reparent_preserving_world(obj, asset_root)
    if roof:
        roof_group = bpy.data.objects.new("RoofVisual", None)
        bpy.context.collection.objects.link(roof_group)
        roof_group.parent = asset_root
        for obj in roof:
            reparent_preserving_world(obj, roof_group)
    low, high = world_bounds(meshes)
    dimensions = high - low
    if min(dimensions) <= 0.001:
        raise ValueError("Imported geometry is flat or degenerate")
    if args.exact_size is not None:
        scale_xyz = Vector(tuple(args.exact_size[index] / dimensions[index] for index in range(3)))
    else:
        uniform = min(args.max_size[index] / dimensions[index] for index in range(3))
        scale_xyz = Vector((uniform, uniform, uniform))
    asset_root.scale = scale_xyz
    asset_root.rotation_euler.z = math.radians(args.yaw_deg)
    bpy.context.view_layer.update()
    rotated_low, rotated_high = world_bounds(meshes)
    asset_root.location += Vector((-(rotated_low.x + rotated_high.x) * 0.5,
                                   -(rotated_low.y + rotated_high.y) * 0.5,
                                   -rotated_low.z))
    bpy.context.view_layer.update()
    final_low, final_high = world_bounds(meshes)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(output_blend))
    bpy.ops.export_scene.gltf(filepath=str(output_glb), export_format="GLB", use_selection=False, export_yup=True)
    report = {
        "name": args.name,
        "source": str(source),
        "original_dimensions_blender_xyz": [round(x, 4) for x in dimensions],
        "final_dimensions_blender_xyz": [round(x, 4) for x in final_high - final_low],
        "final_min_z": round(final_low.z, 5),
        "scale_xyz": [round(value, 6) for value in scale_xyz],
        "mesh_objects": len(meshes),
        "triangles": sum(len(obj.data.loop_triangles) for obj in meshes),
        "materials": material_names,
        "images": [{"name": image.name, "size": list(image.size)} for image in bpy.data.images],
        "roof_objects": [obj.name for obj in roof],
        "roof_selected_faces": selected_faces,
        "recovered_canopy_polygons": canopy_polygons,
        "output_glb": str(output_glb),
        "output_blend": str(output_blend),
    }
    report_path = output_blend.with_suffix(".json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("MESHY_STATIC_OK " + json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
