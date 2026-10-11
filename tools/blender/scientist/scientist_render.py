# Images « héros » du scientifique pour le hub (fond transparent) : Cycles,
# éclairage trois points + contre-jours, lueur sarcelle de la fiole, contour
# noir par coque inversée (voxel_lib.add_outline), halo (bloom) ajouté en
# numpy à partir d'une passe ne gardant que les faces « glow ».
#
#   sh tools/blender.sh tools/blender/scientist/scientist_render.py --out DIR [--quick] [--only hero|bust]
import bpy, math, os, sys
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402
import scientist_voxel as sv  # noqa: E402

# Pose du héros (rotations monde autour de la tête de chaque os, dans l'ordre).
HERO_POSE = [
    ("hips", "Z", 12),
    ("spine", "X", -4),
    ("chest", "Z", -8), ("chest", "X", -3),
    ("thigh_l", "Y", -7), ("thigh_l", "X", -6),
    ("thigh_r", "Y", 6), ("thigh_r", "X", 8), ("shin_r", "X", -10),
    # Bras droit : coude écarté, avant-bras levé, fiole au-dessus de l'épaule.
    ("arm_r", "Y", 62), ("arm_r", "X", 18),
    ("forearm_r", "Y", 120), ("forearm_r", "X", 22),
    # Bras gauche : poing sur la hanche.
    ("arm_l", "Y", -38), ("arm_l", "X", -10),
    ("forearm_l", "Y", 92), ("forearm_l", "X", 20),
    # Tête tournée vers la fiole, menton levé, inclinée.
    ("neck", "X", -6),
    ("head", "Z", -22), ("head", "X", -6), ("head", "Y", 7),
]

MAT_SETTINGS = {  # matière : (rugosité, métal, spéculaire, émission)
    "skin": (0.55, 0.0, 0.35, 0.0),
    "cloth": (0.85, 0.0, 0.25, 0.0),
    "fabric": (0.7, 0.0, 0.3, 0.0),
    "leather": (0.5, 0.0, 0.4, 0.0),
    "rubber": (0.32, 0.0, 0.55, 0.0),
    "metal": (0.32, 0.75, 0.5, 0.0),
    "glass": (0.08, 0.0, 0.8, 0.0),
    "bone": (0.35, 0.0, 0.5, 0.0),
    "wound": (0.6, 0.0, 0.3, 0.0),
    "glow": (0.2, 0.0, 0.5, 1.3),
}


def setup_materials(ob):
    for m in ob.data.materials:
        nt = m.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        col = nt.nodes.new("ShaderNodeVertexColor")
        col.layer_name = "Col"
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        r, met, spec, em = MAT_SETTINGS.get(m.name, (0.7, 0.0, 0.3, 0.0))
        bsdf.inputs["Roughness"].default_value = r
        bsdf.inputs["Metallic"].default_value = met
        bsdf.inputs["Specular IOR Level"].default_value = spec
        if m.name == "skin":
            bsdf.inputs["Subsurface Weight"].default_value = 0.15
            bsdf.inputs["Subsurface Radius"].default_value = (0.02, 0.008, 0.005)
        if em:
            nt.links.new(col.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = em
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        m["_bsdf_out"] = True


def outline_material(ob):
    mat = bpy.data.materials.new("hero_outline")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.008, 0.008, 0.01, 1.0)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    # Face arrière (vue de l'extérieur) : transparente ; face avant (côté
    # opposé de la coque, derrière le modèle) : noire.
    nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
    nt.links.new(em.outputs["Emission"], mix.inputs[1])
    nt.links.new(tr.outputs["BSDF"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    ob.visible_transmission = False


def area(name, loc, target, energy, color, size):
    lt = bpy.data.lights.new(name, "AREA")
    lt.energy = energy
    lt.color = color
    lt.shape = "DISK"
    lt.size = size
    ob = bpy.data.objects.new(name, lt)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


def glow_center(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    gi = [i for i, m in enumerate(ob.data.materials) if m.name == "glow"]
    pts = []
    for p in me.polygons:
        if p.material_index in gi:
            pts.append(ob.matrix_world @ p.center)
    ev.to_mesh_clear()
    # Fiole : faces glow les plus hautes (les tubes à essai sont plus bas).
    pts.sort(key=lambda v: -v.z)
    pts = pts[:max(1, len(pts) // 2)]
    return sum(pts, Vector()) / len(pts)


def setup_scene(quick):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for dev in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = dev
            prefs.get_devices()
            for d in prefs.devices:
                d.use = True
            sc.cycles.device = "GPU"
            break
        except Exception:
            continue
    sc.cycles.samples = 48 if quick else 384
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = os.environ.get("SCI_VIEW", "AgX")
    for look in (os.environ.get("SCI_LOOK", "AgX - Punchy"), "Punchy", "None"):
        try:
            sc.view_settings.look = look
            break
        except TypeError:
            continue
    sc.view_settings.exposure = float(os.environ.get("SCI_EXP", "0.0"))
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.06, 0.08, 0.09, 1)
    bg.inputs["Strength"].default_value = 0.2
    sc.world = w
    return sc


def lights(vial):
    T = (0, 0, 1.15)
    area("Key", (1.8, -2.4, 3.3), T, 240, (0.90, 0.96, 1.0), 1.4)
    area("Fill", (-3.0, -2.2, 1.3), T, 45, (0.70, 0.90, 0.95), 2.5)
    area("RimL", (2.2, 2.4, 2.4), (0, 0, 1.4), 1300, (0.55, 0.95, 0.95), 0.8)
    area("RimR", (-2.4, 2.4, 1.6), (0, 0, 1.3), 1500, (1.0, 0.52, 0.18), 0.9)
    area("Top", (0.0, 0.3, 3.6), (0, 0, 1.6), 140, (0.85, 0.95, 1.0), 1.2)
    pl = bpy.data.lights.new("Vial", "POINT")
    pl.energy = 10
    pl.color = (0.35, 1.0, 0.78)
    pl.shadow_soft_size = 0.03
    o = bpy.data.objects.new("Vial", pl)
    bpy.context.scene.collection.objects.link(o)
    o.location = vial + Vector((0.10, -0.04, -0.12))
    # Lueur plus large et douce autour de la fiole.
    pl2 = bpy.data.lights.new("VialWide", "POINT")
    pl2.energy = 6
    pl2.color = (0.35, 1.0, 0.78)
    pl2.shadow_soft_size = 0.25
    o2 = bpy.data.objects.new("VialWide", pl2)
    bpy.context.scene.collection.objects.link(o2)
    o2.location = vial + Vector((0.18, -0.12, -0.15))


def camera(sc, target, az, el, height, res, lens=85.0):
    cam = bpy.data.objects.get("HeroCam")
    if cam is None:
        cam = bpy.data.objects.new("HeroCam", bpy.data.cameras.new("HeroCam"))
        sc.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.sensor_fit = "VERTICAL"
    cam.data.sensor_height = 24.0
    fov = 2 * math.atan(12.0 / lens)
    dist = (height / 2) / math.tan(fov / 2)
    a, e = math.radians(az), math.radians(el)
    t = Vector(target)
    pos = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.location = pos
    cam.rotation_euler = (t - pos).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    return cam


# ---------------------------------------------------------------------------
# Halo : passe « glow seul » (le reste en holdout), flou, ajout.
# ---------------------------------------------------------------------------

def load_rgba(path):
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(im)
    return a


def save_rgba(a, path):
    h, w = a.shape[:2]
    im = bpy.data.images.new("out", w, h, alpha=True)
    im.pixels = np.clip(a, 0, 1).ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def box_blur(a, r):
    if r < 1:
        return a
    k = 2 * r + 1
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
        n = a.shape[axis]
        hi = np.take(c, np.arange(k, k + n), axis=axis)
        lo = np.take(c, np.arange(0, n), axis=axis)
        a = ((hi - lo) / k).astype(np.float32)
    return a


def gblur(a, sigma):
    r = max(1, int(sigma * 0.9))
    for _ in range(3):
        a = box_blur(a, r)
    return a


def bloom_pass(sc, ob, outline, path):
    saved = {}
    hold = bpy.data.materials.new("holdout")
    hold.use_nodes = True
    nt = hold.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    h = nt.nodes.new("ShaderNodeHoldout")
    nt.links.new(h.outputs["Holdout"], o.inputs["Surface"])
    for i, m in enumerate(ob.data.materials):
        saved[i] = m
        if m.name != "glow":
            ob.data.materials[i] = hold
    outline.hide_render = True
    samples = sc.cycles.samples
    sc.cycles.samples = 16
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sc.cycles.samples = samples
    for i, m in saved.items():
        ob.data.materials[i] = m
    outline.hide_render = False


def composite(beauty, glow, out, scale):
    b = load_rgba(beauty)
    g = load_rgba(glow)
    gp = g[..., :3] * g[..., 3:4]
    h = b.shape[0]
    bl = gblur(gp, 6 * scale) * 1.0 + gblur(gp, 22 * scale) * 1.0 + gblur(gp, 70 * scale) * 1.0
    tint = np.array([0.45, 1.0, 0.82], np.float32)
    lum = bl.max(axis=2, keepdims=True)
    add = np.maximum(bl, lum * tint * 0.6)
    pre = b[..., :3] * b[..., 3:4]
    al = b[..., 3:4]
    pre = pre + add * 1.0
    al2 = np.clip(al + np.clip(lum * 0.9, 0, 1) * (1 - al), 0, 1)
    rgb = np.where(al2 > 1e-4, pre / np.maximum(al2, 1e-4), 0)
    save_rgba(np.concatenate([np.clip(rgb, 0, 1), al2], axis=2), out)
    # Aperçu sur un fond sombre de couloir (contrôle seulement).
    bg = np.array([0.07, 0.09, 0.10], np.float32)
    prev = np.clip(pre + bg * (1 - al2), 0, 1)
    save_rgba(np.concatenate([prev, np.ones_like(al2)], axis=2),
              os.path.join(os.path.dirname(beauty), os.path.basename(out).replace(".png", "_preview.png")))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[args.index("--out") + 1])
    quick = "--quick" in args
    only = args[args.index("--only") + 1] if "--only" in args else None
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m, ob, rig, info = sv.build()
    print("[scientist_render] model %s" % info)
    if "--rest" not in args:
        sv.pose(rig, HERO_POSE)
    setup_materials(ob)
    outline = vx.add_outline(m, "scientist_outline", rig, thickness=0.0055)
    outline_material(outline)
    sc = setup_scene(quick)
    vial = glow_center(ob)
    print("[scientist_render] vial at %s" % (tuple(vial),))
    lights(vial)
    tmp = os.path.join(out_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    k = 0.6 if quick and only not in ("turn", "head") else 1.0
    shots = []
    if only in (None, "hero"):
        shots.append(("scientist_hero", (-0.05, 0.0, 1.07), -24, 5, 2.2, (1400, 1800), 70.0))
    if only == "turn":
        for az in (0, -35, 90, 180):
            shots.append(("turn_%d" % (az % 360), (0.0, 0.0, 1.45), az, 0, 1.2, (700, 900), 85.0))
    if only == "head":
        for az in (0, -35, 40, 180):
            shots.append(("head_%d" % (az % 360), (0.0, -0.02, 1.70), az, 0, 0.55, (600, 600), 85.0))
    if only in (None, "bust"):
        shots.append(("scientist_bust", (-0.13, 0.0, 1.70), -24, 4, 0.92, (900, 900), 85.0))
    for name, target, az, el, hgt, res, lens in shots:
        r = (int(res[0] * k), int(res[1] * k))
        camera(sc, target, az, el, hgt, r, lens)
        bp = os.path.join(tmp, name + "_beauty.png")
        gp = os.path.join(tmp, name + "_glow.png")
        sc.render.filepath = bp
        bpy.ops.render.render(write_still=True)
        bloom_pass(sc, ob, outline, gp)
        composite(bp, gp, os.path.join(out_dir, name + ".png"), r[1] / 1800.0 if name.endswith("hero") else r[1] / 900.0 * 1.4)
        print("[scientist_render] -> %s" % os.path.join(out_dir, name + ".png"))


if __name__ == "__main__":
    main()
