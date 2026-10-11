"""Rendus d'icônes des armes en cubes (maquette du hub) : PNG transparents, vue de 3/4."""
import bpy, sys, math, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src_dir, out_dir = argv[0], argv[1]
names = argv[2].split(",")
W, H = int(argv[3]) if len(argv) > 3 else 640, int(argv[4]) if len(argv) > 4 else 256
os.makedirs(out_dir, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.06, 0.07, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    return sc


def outline_mat():
    m = bpy.data.materials.new("outline")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0, 0, 0, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    m.use_backface_culling = True
    return m


def light(name, kind, loc, energy, size, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    d.color = color
    if kind == "AREA":
        d.size = size
    ob = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


for n in names:
    sc = reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(src_dir, n + ".glb"))
    meshes = [o for o in sc.objects if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center, size = (lo + hi) / 2, hi - lo
    # Centre à l'origine.
    for o in sc.objects:
        if o.parent is None:
            o.location -= center
    length = max(size.x, size.y)
    om = outline_mat()
    for o in meshes:
        o.data.materials.append(om)
        mod = o.modifiers.new("outline", "SOLIDIFY")
        mod.thickness = -length * 0.012
        mod.use_flip_normals = True
        mod.material_offset = len(o.data.materials) - 1
    # Canon le long de l'axe le plus long : caméra sur le côté, légèrement de 3/4 et au-dessus.
    along_x = size.x >= size.y
    side = Vector((0, -1, 0)) if along_x else Vector((1, 0, 0))
    fwd = Vector((1, 0, 0)) if along_x else Vector((0, 1, 0))
    dirv = (side + fwd * 0.28 + Vector((0, 0, 0.32))).normalized()
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = max(length * 1.15, (size.z + 0.35 * length) * W / H * 1.12)
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = dirv * length * 4
    cam.rotation_euler = (-dirv).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    L = length
    light("key", "AREA", tuple(dirv * L * 2 + Vector((0, 0, L * 1.5)) + fwd * L), 260 * L * L, L * 1.5, (1.0, 0.96, 0.9))
    light("fill", "AREA", tuple(dirv * L * 2 - fwd * L * 1.5), 120 * L * L, L * 2, (0.75, 0.85, 1.0))
    light("rim", "AREA", tuple(-side * L * 2 + Vector((0, 0, L))), 500 * L * L, L, (0.6, 1.0, 0.95))
    sc.render.filepath = os.path.join(out_dir, n + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)
