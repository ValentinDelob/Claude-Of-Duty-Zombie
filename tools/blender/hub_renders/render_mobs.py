"""Portraits des ennemis en cubes (maquette du codex) : PNG transparents, vue de 3/4 face."""
import bpy, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = argv[0]
jobs = [a.split("=") for a in argv[1].split(",")]  # nom=chemin.glb
facing = float(argv[2]) if len(argv) > 2 else 1.0  # +1 : la face regarde +Y
W, H = 600, 720
os.makedirs(out_dir, exist_ok=True)


def light(name, loc, energy, size, color):
    d = bpy.data.lights.new(name, "AREA")
    d.energy, d.size, d.color = energy, size, color
    ob = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


for name, path in jobs:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.06, 0.07, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    bpy.ops.import_scene.gltf(filepath=path)
    for o in [o for o in sc.objects if o.type == "MESH" and len(o.data.vertices) < 100]:
        bpy.data.objects.remove(o)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center, size = (lo + hi) / 2, hi - lo
    om = bpy.data.materials.new("outline")
    om.use_nodes = True
    nt = om.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0, 0, 0, 1)
    o_ = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o_.inputs[0])
    om.use_backface_culling = True
    big = max(size)
    for o in meshes:
        o.data.materials.append(om)
        m = o.modifiers.new("outline", "SOLIDIFY")
        m.thickness = -big * 0.006
        m.use_flip_normals = True
        m.material_offset = len(o.data.materials) - 1
    dirv = Vector((0.6, facing * 1.0, 0.22)).normalized()
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = max(size.z * 1.12, max(size.x, size.y) * 1.2 * H / W)
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = center + dirv * big * 4
    cam.rotation_euler = (-dirv).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    L = big
    light("key", tuple(center + Vector((L * 1.2, facing * L * 1.5, L * 1.8))), 150 * L * L, L, (0.9, 0.95, 1.0))
    light("fill", tuple(center + Vector((-L * 1.5, facing * L, L * 0.5))), 50 * L * L, L * 1.5, (0.8, 0.85, 1.0))
    light("rim", tuple(center + Vector((-L * 0.5, -facing * L * 1.8, L * 1.2))), 250 * L * L, L, (0.5, 1.0, 0.9))
    sc.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)
