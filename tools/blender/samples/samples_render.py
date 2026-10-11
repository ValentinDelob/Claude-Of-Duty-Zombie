# Icônes des échantillons d'ennemis pour l'inventaire du hub : un rendu par
# modèle de samples_voxel.py, PNG 512 × 512 à fond transparent, même caméra
# 3/4 orthographique et même éclairage pour toute la série (Cycles : clé
# froide, débouchage doux, contre-jour sarcelle comme l'interface du hub,
# second contre-jour blanc), contour noir par coque inversée
# (voxel_lib.add_outline, épaisseur constante en pixels), halo (bloom)
# ajouté en numpy autour des faces « glow ». Planche samples_sheet.png.
#
#   sh tools/blender.sh tools/blender/samples/samples_render.py --out DIR [--quick] [--only id,id]
import bpy, math, os, sys
import numpy as np
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402
import samples_voxel as sv  # noqa: E402

RES = 512
FILL = 0.80          # part du cadre occupée par l'objet (plus grand côté)
AZ, EL = -32.0, 24.0  # caméra 3/4 (azimut : 0 = de face, caméra en -Y)
OUTLINE_PX = 3.2
TEAL = (0.32, 0.95, 0.88)

MAT_SETTINGS = {  # matière : (rugosité, métal, spéculaire, émission)
    "bone": (0.28, 0.0, 0.6, 0.0),
    "wound": (0.22, 0.0, 0.7, 0.0),
    "skin": (0.55, 0.0, 0.4, 0.0),
    "cloth": (0.85, 0.0, 0.25, 0.0),
    "leather": (0.62, 0.0, 0.25, 0.0),
    "metal": (0.26, 0.7, 0.6, 0.0),
    "rubber": (0.35, 0.0, 0.5, 0.0),
    "fabric": (0.55, 0.0, 0.35, 0.0),
    "heart": (0.25, 0.0, 0.7, 0.0),
    "glow": (0.3, 0.0, 0.5, 0.85),
}


def node_mat(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return mat, nt, nt.nodes.new("ShaderNodeOutputMaterial")


def setup_materials(ob, kind):
    for i, m in enumerate(ob.data.materials):
        mat, nt, out = node_mat("%s_%s" % (ob.name, m.name))
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        col = nt.nodes.new("ShaderNodeVertexColor")
        col.layer_name = "Col"
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        if kind == "glass":
            # Verre : transparent (le fond de l'interface se voit à travers),
            # teinté par la couleur de face, voile laiteux léger, reflets
            # selon Fresnel (les faces de biais brillent : cubes lisibles).
            for n in list(nt.nodes):
                if n not in (out, col):
                    nt.nodes.remove(n)
            tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            df = nt.nodes.new("ShaderNodeBsdfDiffuse")
            gl = nt.nodes.new("ShaderNodeBsdfGlossy")
            gl.inputs["Roughness"].default_value = 0.08
            fr = nt.nodes.new("ShaderNodeFresnel")
            fr.inputs["IOR"].default_value = 1.45
            m1 = nt.nodes.new("ShaderNodeMixShader")
            # Voile laiteux plus fort sur les faces vues de biais (bords
            # du verre lisibles, volume du bocal).
            lw = nt.nodes.new("ShaderNodeLayerWeight")
            lw.inputs["Blend"].default_value = 0.5
            pw = nt.nodes.new("ShaderNodeMath")
            pw.operation = "POWER"
            pw.inputs[1].default_value = 2.0
            ma = nt.nodes.new("ShaderNodeMath")
            ma.operation = "MULTIPLY_ADD"
            ma.inputs[1].default_value = float(os.environ.get("GLASS_EDGE", "0.45"))
            ma.inputs[2].default_value = float(os.environ.get("GLASS_DIFF", "0.03"))
            nt.links.new(lw.outputs["Facing"], pw.inputs[0])
            nt.links.new(pw.outputs["Value"], ma.inputs[0])
            nt.links.new(ma.outputs["Value"], m1.inputs["Fac"])
            m2 = nt.nodes.new("ShaderNodeMixShader")
            nt.links.new(col.outputs["Color"], tr.inputs["Color"])
            nt.links.new(col.outputs["Color"], df.inputs["Color"])
            nt.links.new(tr.outputs["BSDF"], m1.inputs[1])
            nt.links.new(df.outputs["BSDF"], m1.inputs[2])
            fm = nt.nodes.new("ShaderNodeMath")
            fm.operation = "MULTIPLY"
            fm.inputs[1].default_value = float(os.environ.get("GLASS_GLOSS", "0.12"))
            nt.links.new(fr.outputs["Fac"], fm.inputs[0])
            nt.links.new(fm.outputs["Value"], m2.inputs["Fac"])
            nt.links.new(m1.outputs["Shader"], m2.inputs[1])
            nt.links.new(gl.outputs["BSDF"], m2.inputs[2])
            nt.links.new(m2.outputs["Shader"], out.inputs["Surface"])
            ob.data.materials[i] = mat
            continue
        r, met, spec, em = MAT_SETTINGS.get(m.name, (0.6, 0.0, 0.4, 0.0))
        bsdf.inputs["Roughness"].default_value = r
        bsdf.inputs["Metallic"].default_value = met
        bsdf.inputs["Specular IOR Level"].default_value = spec
        if m.name in ("wound", "heart"):
            bsdf.inputs["Coat Weight"].default_value = 0.4
            bsdf.inputs["Coat Roughness"].default_value = 0.1
        if em:
            nt.links.new(col.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = em
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        ob.data.materials[i] = mat
    if kind == "glass":
        ob.hide_render = bool(os.environ.get("HIDE_GLASS"))
        ob.visible_shadow = False


def outline_material(ob):
    """Coque inversée : noire vue de dos (côté opposé, derrière le modèle),
    transparente vue de face ; seulement pour les rayons caméra (elle ne se
    voit pas à travers le verre)."""
    mat = bpy.data.materials.get("ol")
    if mat is None:
        mat, nt, out = node_mat("ol")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        lp = nt.nodes.new("ShaderNodeLightPath")
        mx = nt.nodes.new("ShaderNodeMath")
        mx.operation = "MAXIMUM"
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        nt.links.new(lp.outputs["Is Camera Ray"], inv.inputs[1])
        nt.links.new(geo.outputs["Backfacing"], mx.inputs[0])
        nt.links.new(inv.outputs["Value"], mx.inputs[1])
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (0.006, 0.007, 0.008, 1.0)
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(mx.outputs["Value"], mix.inputs["Fac"])
        nt.links.new(em.outputs["Emission"], mix.inputs[1])
        nt.links.new(tr.outputs["BSDF"], mix.inputs[2])
        nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for attr in ("visible_shadow", "visible_diffuse", "visible_glossy", "visible_transmission"):
        setattr(ob, attr, False)


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
    sc.cycles.samples = 64 if quick else 320
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 10
    sc.cycles.transmission_bounces = 10
    sc.cycles.transparent_max_bounces = 16
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "Punchy", "None"):
        try:
            sc.view_settings.look = look
            break
        except TypeError:
            continue
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.11, 0.14, 0.15, 1)
    bg.inputs["Strength"].default_value = 0.55
    sc.world = w
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    return sc


def cam_basis():
    a, e = math.radians(AZ), math.radians(EL)
    back = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))  # vers la caméra
    f = -back
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f).normalized()
    return f, r, u


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


def lights(t, S):
    f, r, u = cam_basis()
    k = S * S

    def at(a, b, c, d=2.6):
        return t + (r * a + u * b - f * c).normalized() * d * S

    area("Key", at(-1.1, 1.3, 1.2), t, 175 * k, (0.86, 0.93, 1.0), 1.4 * S)
    area("Fill", at(1.5, 0.1, 1.0), t, 45 * k, (0.80, 0.88, 0.95), 2.4 * S)
    area("Rim", at(1.25, 0.75, -1.5), t, 800 * k, TEAL, 0.8 * S)
    area("Rim2", at(-1.3, 0.9, -1.4), t, 240 * k, (0.90, 0.95, 1.0), 0.8 * S)
    area("Top", at(0.0, 2.0, 0.2), t, 70 * k, (0.92, 0.96, 1.0), 1.2 * S)


def build(sample):
    root = bpy.data.objects.new(sample.id, None)
    bpy.context.scene.collection.objects.link(root)
    lo = np.array([1e9] * 3)
    hi = -lo
    for m, kind, name in sample.parts:
        a, b = m.bounds()
        lo, hi = np.minimum(lo, a), np.maximum(hi, b)
    center = Vector(((lo + hi) / 2).tolist()) * sv.CUBE
    obs = []
    for m, kind, name in sample.parts:
        ob, info = vx.build_mesh(m, "%s_%s" % (sample.id, name))
        print("[samples_render] %s/%s %s" % (sample.id, name, info))
        ob.parent = root
        ob.location = -center
        setup_materials(ob, kind)
        obs.append((m, kind, ob))
    root.rotation_euler = Euler([math.radians(v) for v in sample.rot], "XYZ")
    bpy.context.view_layer.update()
    return root, obs, center


def frame(obs):
    f, r, u = cam_basis()
    pr, pu, pts = [], [], []
    for _, _, ob in obs:
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            pts.append(p)
            pr.append(p.dot(r))
            pu.append(p.dot(u))
    cr, cu = (min(pr) + max(pr)) / 2, (min(pu) + max(pu)) / 2
    ext = max(max(pr) - min(pr), max(pu) - min(pu))
    S = ext / FILL
    pf = [p.dot(f) for p in pts]
    cf = (min(pf) + max(pf)) / 2
    t = r * cr + u * cu + f * cf
    return t, S


def camera(sc, t, S):
    f, r, u = cam_basis()
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = S
    cam.data.clip_start = 0.01
    cam.data.clip_end = 100
    cam.location = t - f * 5.0
    cam.rotation_euler = f.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


# ---------------------------------------------------------------------------
# Halo et images.
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


def glow_pass(sc, obs, outlines, path):
    hold, nt, out = node_mat("holdout")
    h = nt.nodes.new("ShaderNodeHoldout")
    nt.links.new(h.outputs["Holdout"], out.inputs["Surface"])
    saved = []
    for _, kind, ob in obs:
        for i, m in enumerate(ob.data.materials):
            saved.append((ob, i, m))
            if not m.name.endswith("_glow"):
                ob.data.materials[i] = hold
    for o in outlines:
        o.hide_render = True
    samples = sc.cycles.samples
    sc.cycles.samples = 24
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sc.cycles.samples = samples
    for ob, i, m in saved:
        ob.data.materials[i] = m
    for o in outlines:
        o.hide_render = False


def mask_pass(sc, obs, outlines, path):
    """Masque des pièces de verre seules (blanc opaque) : sert à tracer leur
    contour noir en 2D (une coque inversée se verrait à travers le verre)."""
    white, nt, out = node_mat("white")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    saved, hidden = [], []
    for _, kind, ob in obs:
        if kind != "glass":
            ob.hide_render = True
            hidden.append(ob)
            continue
        for i, m in enumerate(ob.data.materials):
            saved.append((ob, i, m))
            ob.data.materials[i] = white
    for o in outlines:
        o.hide_render = True
        hidden.append(o)
    samples, den = sc.cycles.samples, sc.cycles.use_denoising
    sc.cycles.samples, sc.cycles.use_denoising = 4, False
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sc.cycles.samples, sc.cycles.use_denoising = samples, den
    for ob, i, m in saved:
        ob.data.materials[i] = m
    for o in hidden:
        o.hide_render = False


def add_ring(al, mask_path):
    """Contour noir de OUTLINE_PX autour du masque de verre, seulement là où
    l'image est vide (pré-multiplié : le noir n'ajoute que de l'alpha)."""
    g = load_rgba(mask_path)[..., 3] > 0.5
    r = int(round(OUTLINE_PX))
    dil = g.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r + 1:
                dil |= np.roll(np.roll(g, dy, 0), dx, 1)
    ring = (dil & ~g).astype(np.float32)
    ring = box_blur(ring[..., None], 1)[..., 0] * 0.5 + ring * 0.5
    return np.clip(al + ring[..., None] * (1 - al), 0, 1)


def composite(beauty, glow, out, strength, glass_mask=None):
    b = load_rgba(beauty)
    pre = b[..., :3] * b[..., 3:4]
    al = b[..., 3:4]
    if glow is not None:
        g = load_rgba(glow)
        gp = g[..., :3] * g[..., 3:4]
        bl = (gblur(gp, 4) * 0.8 + gblur(gp, 12) * 0.8 + gblur(gp, 34) * 0.9) * strength
        lum = bl.max(axis=2, keepdims=True)
        pre = pre + bl
        al = np.clip(al + np.clip(lum * 0.9, 0, 1) * (1 - al), 0, 1)
    if glass_mask is not None:
        al = add_ring(al, glass_mask)
    rgb = np.where(al > 1e-4, pre / np.maximum(al, 1e-4), 0)
    save_rgba(np.concatenate([np.clip(rgb, 0, 1), al], axis=2), out)


def contact_sheet(paths, out, cols=5, tile=300, gap=18):
    rows = (len(paths) + cols - 1) // cols
    H, W = rows * tile + (rows + 1) * gap, cols * tile + (cols + 1) * gap
    bg = np.array([0.075, 0.095, 0.105], np.float32)
    sheet = np.zeros((H, W, 4), np.float32)
    sheet[..., :3] = bg
    sheet[..., 3] = 1
    for k, p in enumerate(paths):
        a = load_rgba(p)  # ligne 0 en bas (Blender)
        h, w = a.shape[:2]
        ys = (np.arange(tile) * h / tile).astype(int)
        xs = (np.arange(tile) * w / tile).astype(int)
        a = a[ys][:, xs]
        r, c = k // cols, k % cols
        y0 = H - (gap + r * (tile + gap)) - tile
        x0 = gap + c * (tile + gap)
        cell = sheet[y0:y0 + tile, x0:x0 + tile]
        # Case : panneau légèrement plus clair, liseré sarcelle en bas.
        cell[..., :3] = np.array([0.11, 0.135, 0.145], np.float32)
        cell[:3, :, :3] = np.array([0.20, 0.42, 0.42], np.float32)
        al = a[..., 3:4]
        cell[..., :3] = a[..., :3] * al + cell[..., :3] * (1 - al)
    save_rgba(sheet, out)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = args[args.index("--out") + 1]
    quick = "--quick" in args
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    done = []
    for fn in sv.SAMPLES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sample = fn()
        path = os.path.join(out_dir, sample.id + ".png")
        if only and sample.id not in only:
            if os.path.exists(path):
                done.append(path)
            continue
        sc = setup_scene(quick)
        root, obs, center = build(sample)
        t, S = frame(obs)
        camera(sc, t, S)
        thick = OUTLINE_PX * S / RES
        outlines = []
        for m, kind, ob in [o for o in obs if o[1] != "glass"]:
            o = vx.add_outline(m, ob.name + "_ol", thickness=thick)
            o.parent = root
            o.location = ob.location
            outline_material(o)
            outlines.append(o)
        lights(t, S)
        bp = os.path.join(tmp, sample.id + "_beauty.png")
        sc.render.filepath = bp
        bpy.ops.render.render(write_still=True)
        has_glow = any(m.name.endswith("_glow") for _, _, ob in obs for m in ob.data.materials)
        gp = None
        if has_glow:
            gp = os.path.join(tmp, sample.id + "_glow.png")
            glow_pass(sc, obs, outlines, gp)
        gm = None
        if any(k == "glass" for _, k, _ in obs):
            gm = os.path.join(tmp, sample.id + "_glassmask.png")
            mask_pass(sc, obs, outlines, gm)
        composite(bp, gp, path, 0.75 if sample.id == "surgeon_heart" else 0.45, gm)
        print("[samples_render] -> %s (frame %.3f m)" % (path, S))
        done.append(path)
    contact_sheet(done, os.path.join(out_dir, "samples_sheet.png"))
    print("[samples_render] sheet -> %s" % os.path.join(out_dir, "samples_sheet.png"))


if __name__ == "__main__":
    main()
