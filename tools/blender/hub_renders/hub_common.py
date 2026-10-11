# Outils communs aux rendus du hub (armes, ennemis, personnages) : scène
# EEVEE à fond transparent, même réglage de couleur pour toute la série,
# lumières de zone braquées sur un point, contour noir par coque inversée
# (modificateur Solidify, normales retournées, matière émissive noire).
import os
import bpy
from mathutils import Vector


def reset(w, h, world_strength=0.55):
    """Scène vide, EEVEE, PNG RGBA w × h, fond transparent."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.image_settings.compression = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.05, 0.06, 0.07, 1)
    bg.inputs[1].default_value = world_strength
    return sc


def drop_helpers(min_verts=100, names=("Icosphere",)):
    """Supprime les maillages d'aide (sphère d'éclairage « Icosphere »…) :
    tout maillage de moins de `min_verts` sommets, ou nommé comme une aide."""
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        if len(o.data.vertices) < min_verts or o.name.split(".")[0] in names:
            bpy.data.objects.remove(o)


def bounds(meshes):
    """Boîte englobante monde des maillages ÉVALUÉS (pose du squelette comprise)."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi, pts


def outline(meshes, thickness):
    """Contour noir (coque inversée) d'épaisseur `thickness` (m)."""
    m = bpy.data.materials.new("outline")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0, 0, 0, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    m.use_backface_culling = True
    for ob in meshes:
        ob.data.materials.append(m)
        mod = ob.modifiers.new("outline", "SOLIDIFY")
        mod.thickness = -thickness
        mod.use_flip_normals = True
        mod.material_offset = len(ob.data.materials) - 1
    return m


def light(name, loc, target, energy, size, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, "AREA")
    d.energy, d.size, d.color = energy, size, color
    ob = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


def ortho_camera(sc, target, dirv, dist, scale):
    """Caméra orthographique placée en target + dirv × dist, visant target."""
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = scale
    cam_d.clip_end = dist * 4
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = Vector(target) + dirv.normalized() * dist
    cam.rotation_euler = (-dirv).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


def fit_ortho(cam, pts, w, h, margin):
    """Recadre la caméra ortho (échelle + décalage) pour que les points
    projetés occupent le cadre w × h avec une marge relative `margin`."""
    inv = cam.matrix_world.inverted()
    loc = [inv @ p for p in pts]
    x0, x1 = min(p.x for p in loc), max(p.x for p in loc)
    y0, y1 = min(p.y for p in loc), max(p.y for p in loc)
    aspect = w / h
    sw, sh = (x1 - x0) * (1 + margin), (y1 - y0) * (1 + margin)
    # ortho_scale = plus grand côté du cadre.
    scale = max(sw, sh * aspect) if aspect >= 1 else max(sw / aspect, sh)
    cam.data.ortho_scale = scale
    # shift : en fraction du plus grand côté du cadre (= ortho_scale).
    cam.data.shift_x = (x0 + x1) / 2 / scale
    cam.data.shift_y = (y0 + y1) / 2 / scale
    return scale


def render(sc, path):
    # Chemin ABSOLU : un chemin relatif serait résolu par Blender depuis le
    # dossier du .blend (aucun ici : racine du disque).
    path = os.path.abspath(path)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[hub_renders] ->", path)
