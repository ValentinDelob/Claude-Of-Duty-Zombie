# Zombie « patient » CUBIQUE (GAME_CONCEPT.md § 4.19 : 1 cube = 5 cm), d'après
# la planche docs/reference/zombie_patient/turnaround.png (dossier ignoré par
# git) : grosse tête, voûté vers l'avant, bras longs, blouse d'hôpital aux
# genoux au bas déchiré, manches courtes, pieds nus.
#
#   sh tools/blender.sh tools/blender/zombies/zombie_voxel.py [--glb FICHIER] [--sheet FICHIER.png]
#
# Construit avec tools/blender/voxel/voxel_lib.py :
#   - volumes en cellules de 5 cm (36 de haut = 1,80 m), mesurés sur la planche
#     (une rangée de la planche ≈ 19 pixels = 1 cube) ; le dos voûté est un
#     ESCALIER de cubes (bassin, torse, tête de plus en plus en avant), jamais
#     un cisaillement ;
#   - bas de la blouse et des manches déchirés : la hauteur de chaque colonne
#     de cubes est relevée sur la vue qui la montre ;
#   - couleurs PRÉLEVÉES sur la planche, une par face de cube (case de 5 cm
#     projetée dans la vue correspondante) ; faces cachées comblées par la
#     face prélevée la plus proche de la même partie ; retouches : yeux jaunes
#     émissifs, bouche, dents, narines ; ombrage peint ; palette réduite.
#   - ossature du jeu (RigBuilder.BONES), os droits, repos membres pendants,
#     pondération rigide (chaque cube à 100 % sur un os).
# Sans la planche, le modèle est construit avec des couleurs unies par partie.
#
# Repère : Z en haut, face avant vers -Y, gauche du personnage vers +X. Dans
# ce script, « f » est la profondeur vers l'AVANT (f = -y) : f[a, b) = y[-b, -a).
import bpy, math, os, sys
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

# Planche : dans le dépôt, sinon dans le dépôt principal (worktree).
REF_REL = os.path.join("docs", "reference", "zombie_patient", "turnaround.png")


def _ref_path():
    p = os.path.join(ROOT, REF_REL)
    if os.path.exists(p):
        return p
    # Worktree .claude/worktrees/<nom> : la planche est dans le dépôt principal.
    main = os.path.abspath(os.path.join(ROOT, "..", "..", ".."))
    p = os.path.join(main, REF_REL)
    return p if os.path.exists(p) else None


# Couleurs unies de secours (sRGB) et retouches.
SKIN = (0.42, 0.50, 0.38)
CLOTH = (0.84, 0.82, 0.68)
EYE = (1.0, 0.86, 0.25)
TOOTH = (0.86, 0.80, 0.55)
MOUTH = (0.20, 0.05, 0.05)
NOSTRIL = (0.13, 0.15, 0.11)

# Hauteurs du bas déchiré (cubes) : bornes de mesure et de résultat.
SKIRT_HEM = (6, 8)
SLEEVE_HEM = (19, 21)


def F(m, x0, x1, f0, f1, z0, z1, mat, bone, part, color):
    """Pavé en profondeur avant f (voir l'en-tête)."""
    m.box(x0, x1, -f1, -f0, z0, z1, mat, bone, part, color)


def clear_f(m, x0, x1, f0, f1, z0, z1):
    m.clear(x0, x1, -f1, -f0, z0, z1)


# ---------------------------------------------------------------------------
# Planche : vues de la rangée du haut, classes de pixels, mesure des déchirures.
# ---------------------------------------------------------------------------

# (nom, colonnes de pixels de la silhouette, direction de la face vue,
# axe horizontal de l'écran) ; la rangée va du sommet du crâne (≈ 83) aux
# pieds (770) : 36 cubes ≈ 19,05 px.
VIEWS = [
    ("front", (166, 537), "-y", (1, 0, 0)),
    ("back", (828, 1216), "+y", (-1, 0, 0)),
    ("right", (1477, 1661), "-x", (0, -1, 0)),   # 3e colonne : côté droit, avant à droite
    ("left", (1822, 2006), "+x", (0, 1, 0)),     # 4e colonne : côté gauche, avant à gauche
]
ROW = (0, 800)
PAD = 60


class Ref:
    def __init__(self, path):
        im = bpy.data.images.load(path)
        W, H = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3].copy()
        bpy.data.images.remove(im)
        self.a = a
        mx, mn = a.max(2), a.min(2)
        self.sat = (mx - mn) / np.maximum(mx, 1e-4)
        self.lum = a.mean(2)
        self.mask = (self.sat > 0.08) | (self.lum < 0.3) | (self.lum > 0.68)
        r, g = a[..., 0], a[..., 1]
        self.green = self.mask & (g > r + 0.015) & (self.lum >= 0.16)
        self.cream = self.mask & (self.lum > 0.55) & (self.sat < 0.3) & (r >= g - 0.02)
        self.red = self.mask & (r > g + 0.1) & (r > 0.2)
        # Pixels à ne jamais prélever : encrage noir, fond gris (et 2 pixels
        # de bord : anticrénelage).
        ink = (self.lum < 0.15) & (self.sat < 0.45)
        bg = ~self.mask | ((self.sat < 0.05) & (np.abs(self.lum - 0.565) < 0.05))
        bad = ink | bg
        for _ in range(2):
            n = bad.copy()
            n[1:] |= bad[:-1]
            n[:-1] |= bad[1:]
            n[:, 1:] |= bad[:, :-1]
            n[:, :-1] |= bad[:, 1:]
            bad = n
        self.bad = bad

    def views(self):
        out = {}
        for name, (x0, x1), d, right in VIEWS:
            c0, c1 = x0 - PAD, x1 + PAD
            sl = (slice(ROW[0], ROW[1]), slice(c0, c1))
            rows = np.where(self.mask[sl].any(1))[0]
            top, bot = rows[0], rows[-1] + 1
            s = (bot - top) / 36.0
            v = vx.View(name, self.a[sl], d, right, s, (x1 - x0) / 2.0 + PAD, float(bot), ok=~self.bad[sl])
            v.mask = self.mask[sl]
            v.cls = {"green": self.green[sl], "cream": self.cream[sl], "red": self.red[sl]}
            out[name] = v
        return out


def frac(view, key, p0, p1):
    """Part des pixels de la classe `key` dans le rectangle (en cubes) p0-p1
    projeté (resserré de 25 %)."""
    us, vs = zip(view.proj(p0), view.proj(p1))
    u0, u1 = sorted(us)
    v0, v1 = sorted(vs)
    du, dv = (u1 - u0) * 0.25, (v1 - v0) * 0.25
    cell = view.cls[key][int(v0 + dv):int(math.ceil(v1 - dv)), int(u0 + du):int(math.ceil(u1 - du))]
    return float(cell.mean()) if cell.size else 0.0


def hem(view, p_lo, p_hi, rng):
    """Bas déchiré d'une colonne : plus basse cellule z de rng (bornes
    comprises) encore majoritairement crème, colonne d'axe horizontal p_lo ->
    p_hi (points en cubes, z ignoré) ; à défaut la borne haute."""
    lo, hi = rng
    for z in range(lo - 1, hi + 1):
        a = np.array(p_lo, float)
        b = np.array(p_hi, float)
        a[2], b[2] = z, z + 1
        if frac(view, "cream", a, b) > 0.5:
            return min(max(z, lo), hi)
    return hi


# ---------------------------------------------------------------------------
# Volumes.
# ---------------------------------------------------------------------------

def build_model(views=None):
    m = vx.Model()
    # --- jambes et pieds nus (os thigh / shin) ---
    for s, side in ((1, "l"), (-1, "r")):
        xs = (2, 5) if s > 0 else (-5, -2)
        F(m, *xs, -3, 0, 7, 14, "skin", "thigh_" + side, "leg_" + side, SKIN)
        F(m, *xs, -3, 0, 1, 7, "skin", "shin_" + side, "leg_" + side, SKIN)
        F(m, *xs, -3, 2, 0, 1, "skin", "shin_" + side, "leg_" + side, SKIN)  # pied, orteils devant
    # --- blouse : jupe creuse (os hips), parois d'un cube, bas déchiré ---
    SX, SF, ST = (-6, 6), (-5, 2), 15
    hems = {}
    for x in range(*SX):
        for f in range(*SF):
            wall = x in (SX[0], SX[1] - 1) or f in (SF[0], SF[1] - 1)
            if not wall:
                continue
            h = SKIRT_HEM[0] + 1
            if views:
                if f == SF[1] - 1:
                    h = hem(views["front"], (x, -f - 1, 0), (x + 1, -f - 1, 0), SKIRT_HEM)
                elif f == SF[0]:
                    h = hem(views["back"], (x, -f, 0), (x + 1, -f, 0), SKIRT_HEM)
                elif x == SX[1] - 1:
                    h = hem(views["left"], (x + 1, -f - 1, 0), (x + 1, -f, 0), SKIRT_HEM)
                else:
                    h = hem(views["right"], (x, -f - 1, 0), (x, -f, 0), SKIRT_HEM)
            hems[(x, f)] = h
            F(m, x, x + 1, f, f + 1, h, ST, "cloth", "hips", "skirt", CLOTH)
    F(m, SX[0], SX[1], SF[0], SF[1], 14, ST, "cloth", "hips", "skirt", CLOTH)  # couvercle
    # --- torse en escalier vers l'avant : bas (spine), haut (chest) ---
    F(m, -5, 5, -4, 2, ST, 21, "cloth", "spine", "torso", CLOTH)
    F(m, -5, 5, -3, 3, 21, 28, "cloth", "chest", "torso", CLOTH)
    # --- bras : manche courte (os arm), avant-bras et main (os forearm) ---
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, b):
            return (a, b) if s > 0 else (-b, -a)
        arm, fore, part = "arm_" + side, "forearm_" + side, "arm_" + side
        # Manche : x 5..9 (bras 6..9 + un cube de tissu côté torse), f -4..1.
        for xi in range(5, 9):
            for f in range(-4, 1):
                core = 6 <= xi and -3 <= f < 0
                h = SLEEVE_HEM[0] + 1
                if views:
                    sx = xi if s > 0 else -xi - 1
                    if f == 0:
                        h = hem(views["front"], (sx, -1, 0), (sx + 1, -1, 0), SLEEVE_HEM)
                    elif f == -4:
                        h = hem(views["back"], (sx, 4, 0), (sx + 1, 4, 0), SLEEVE_HEM)
                    elif xi == 8:
                        v = views["left" if s > 0 else "right"]
                        ox = 9 if s > 0 else -9
                        h = hem(v, (ox, -f - 1, 0), (ox, -f, 0), SLEEVE_HEM)
                    elif not core:
                        h = SLEEVE_HEM[1]
                    else:
                        h = 20
                x0, x1 = X(xi, xi + 1)
                if core:
                    # Haut du bras : peau sous la manche, jusqu'au coude (20).
                    F(m, x0, x1, f, f + 1, 20, 27, "skin", arm, part, SKIN)
                F(m, x0, x1, f, f + 1, h, 27, "cloth", arm, "sleeve_" + side, CLOTH)
        F(m, *X(6, 9), -3, 0, 13, 20, "skin", fore, part, SKIN)
        # Main : paume plus longue que l'avant-bras, trois doigts crochus et
        # un pouce devant.
        F(m, *X(6, 9), -4, 1, 11, 13, "skin", fore, "hand_" + side, SKIN)
        for f in (-4, -2, 0):
            F(m, *X(7, 9), f, f + 1, 10, 11, "skin", fore, "hand_" + side, SKIN)
            F(m, *X(7, 8), f, f + 1, 9, 10, "skin", fore, "hand_" + side, SKIN)
        F(m, *X(6, 7), 1, 2, 11, 12, "skin", fore, "hand_" + side, SKIN)
    # --- tête (os head), en avant du torse ---
    F(m, -4, 4, -4, 4, 28, 35, "skin", "head", "head", SKIN)
    F(m, -3, 3, -3, 3, 35, 36, "skin", "head", "head", SKIN)
    for xs in ((4, 5), (-5, -4)):
        F(m, *xs, -1, 1, 30, 32, "skin", "head", "head", SKIN)  # oreilles
    clear_f(m, -1, 1, 3, 4, 29, 30)  # narines
    # --- mâchoire (os jaw) : menton sous la tête, bouche ouverte, dents ---
    F(m, -3, 3, 2, 4, 25, 28, "skin", "jaw", "jaw", SKIN)
    clear_f(m, -2, 2, 3, 4, 26, 28)
    for x, z in ((-2, 27), (0, 27), (-1, 26), (1, 26)):
        F(m, x, x + 1, 3, 4, z, z + 1, "bone", "jaw", "teeth", TOOTH)
    return m, hems


# ---------------------------------------------------------------------------
# Couleurs.
# ---------------------------------------------------------------------------

CLOTH_PARTS = ("skirt", "torso", "sleeve_l", "sleeve_r")


def paint(m, views):
    """Prélèvement sur la planche, retouches, comblement, ombrage, palette."""
    def accept(view, c, d, px):
        r, g, b = px[:, 0], px[:, 1], px[:, 2]
        lum = px.mean(1)
        part = m.vox[c].part
        if part == "teeth":
            return np.zeros(len(px), bool)
        if part in CLOTH_PARTS:
            # Blouse : crème, plis gris, sang ; peau verte seulement dans
            # l'encolure (haut du torse, devant).
            neck = part == "torso" and d == "-y" and c[2] >= 23 and abs(c[0] + 0.5) < 4
            if neck:
                return np.ones(len(px), bool)
            ok = ~((g > r + 0.015) & (lum < 0.55))
            # Plis : traits fins de la planche ; la case reste crème si le
            # crème y domine assez.
            cream = ok & (lum > 0.62) & (r >= g - 0.02) & ~(r > g + 0.1)
            return cream if cream.mean() >= 0.3 else ok
        # Peau : ni crème ni gris clair.
        return ~((lum > 0.55) & (r >= g - 0.02))

    painted = set()
    if views:
        painted = vx.paint_from_views(m, list(views.values()), accept)
    # Retouches du visage (faces avant, plan f = 4 ; cellules f = 3, y = -4).
    def front(x, z, f=3):
        return (x, -f - 1, z, "-y")
    for x in (-3, -2, 1, 2):
        key = front(x, 31)
        m.face_color[key] = EYE
        m.face_mat[key] = "eye"
        painted.add((key[:3], key[3]))
    # Cavités (bouche ouverte, narines) : toute face qui donne dans le trou
    # est sombre ; dents unies.
    holes = {}
    for x in range(-2, 2):
        for z in (26, 27):
            holes[(x, -4, z)] = (MOUTH, "wound")
    for x in (-1, 0):
        holes[(x, -4, 29)] = (NOSTRIL, None)
    for (c, d) in m.exposed():
        v = m.vox[c]
        key = (c[0], c[1], c[2], d)
        if v.part == "teeth":
            m.face_color[key] = TOOTH
            painted.add((c, d))
            continue
        n = vx.DIRS[d]
        nb = (c[0] + n[0], c[1] + n[1], c[2] + n[2])
        if nb in holes and nb not in m.vox:
            col, mat = holes[nb]
            m.face_color[key] = col
            if mat:
                m.face_mat[key] = mat
            painted.add((c, d))
    if views:
        vx.fill_unpainted(m, painted)
    # Matière selon la couleur : sang (wound), peau de l'encolure.
    for c, d in m.exposed():
        mat = m.mat_of(c, d)
        if mat in ("eye", "bone"):
            continue
        r, g, b = m.color_of(c, d)
        if r > g + 0.1 and r > 0.2:
            m.face_mat[(c[0], c[1], c[2], d)] = "wound"
        elif mat == "cloth" and g > r + 0.015:
            m.face_mat[(c[0], c[1], c[2], d)] = "skin"
    vx.shade(m, skip_mats=("eye",))
    vx.quantize(m, {"skin": 24, "cloth": 20, "wound": 8})


# ---------------------------------------------------------------------------
# Ossature (RigBuilder.BONES), en cubes ; os droits (alignés sur les axes).
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, 1.5, 14), (0, 1.5, 15)),
    ("spine", "hips", (0, 1, 15), (0, 1, 21)),
    ("chest", "spine", (0, 0, 21), (0, 0, 27)),
    ("neck", "chest", (0, 0, 27), (0, 0, 28)),
    ("head", "neck", (0, 0, 28), (0, 0, 36)),
    ("arm_l", "chest", (7.5, 1.5, 26), (7.5, 1.5, 20)),
    ("forearm_l", "arm_l", (7.5, 1.5, 20), (7.5, 1.5, 10)),
    ("arm_r", "chest", (-7.5, 1.5, 26), (-7.5, 1.5, 20)),
    ("forearm_r", "arm_r", (-7.5, 1.5, 20), (-7.5, 1.5, 10)),
    ("thigh_l", "hips", (3.5, 1.5, 14), (3.5, 1.5, 7)),
    ("shin_l", "thigh_l", (3.5, 1.5, 7), (3.5, 1.5, 0)),
    ("thigh_r", "hips", (-3.5, 1.5, 14), (-3.5, 1.5, 7)),
    ("shin_r", "thigh_r", (-3.5, 1.5, 7), (-3.5, 1.5, 0)),
    # Mâchoire : pivot en haut, à l'arrière du menton ; ouverture vers le bas.
    ("jaw", "head", (0, -2, 28), (0, -4, 28)),
]


def build(with_ref=True):
    ref = _ref_path() if with_ref else None
    views = None
    info = {}
    if ref:
        views = Ref(ref).views()
    m, hems = build_model(views)
    if views:
        info["iou"] = {k: round(vx.register(m, v, v.mask), 3) for k, v in views.items()}
        # Déchirures remesurées sur les vues recalées.
        m, hems = build_model(views)
    paint(m, views)
    ob, mi = vx.build_mesh(m, "zombie_voxel")
    info.update(mi)
    rig = vx.build_armature("zombie_voxel_rig", BONES)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    info["cells_by_bone"] = {}
    for v in m.vox.values():
        info["cells_by_bone"][v.bone] = info["cells_by_bone"].get(v.bone, 0) + 1
    return m, ob, rig, info, views


# ---------------------------------------------------------------------------
# Planche de validation.
# ---------------------------------------------------------------------------

def pose_attack(rig):
    """Bras tendus vers l'avant, dos et tête penchés (pose des os)."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")

    def rot(name, axis, deg):
        pb = rig.pose.bones[name]
        bpy.context.view_layer.update()
        mw = pb.matrix.copy()
        loc = mw.translation.copy()
        r = Matrix.Rotation(math.radians(deg), 4, axis) @ mw
        r.translation = loc
        pb.matrix = r
        bpy.context.view_layer.update()

    rot("spine", "X", 8)
    rot("chest", "X", 4)
    rot("head", "X", 6)
    for side, spread in (("l", -6), ("r", 6)):
        rot("arm_" + side, "X", -80)
        rot("arm_" + side, "Z", spread)
        rot("forearm_" + side, "X", -10)
    rot("jaw", "X", 18)
    rot("thigh_l", "X", -12)
    rot("shin_l", "X", 10)
    rot("thigh_r", "X", 10)
    bpy.ops.object.mode_set(mode="OBJECT")


def rest_pose(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def render_sheet(rig, path, ref_path):
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    vx.setup_render((420, 720))
    tgt, ortho = (0, 0, 0.92), 2.0
    shots = [("front", 0, 0), ("back", 180, 0), ("right", -90, 0), ("left", 90, 0), ("34", 35, 10)]
    tiles = []
    for name, az, el in shots:
        tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, tgt, ortho, el)))
    pose_attack(rig)
    tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, "attack.png"), 55, (0, -0.25, 0.92), ortho, 8)))
    rest_pose(rig)
    rows = [tiles]
    if ref_path:
        im = bpy.data.images.load(ref_path)
        W, H = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3].copy()
        crops = [(110, 0, 590, 800), (780, 0, 1260, 800), (1330, 0, 1810, 800), (1675, 0, 2155, 800),
                 (2120, 0, 2700, 800), (2120, 790, 2700, 1536)]
        rows.insert(0, [a[y0:y1, x0:x1] for x0, y0, x1, y1 in crops])
    out = vx.sheet(rows, 420, 720)
    vx.save_png(out, path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "zombies", "zombie_voxel.glb")
    sheet = None
    i = 0
    while i < len(args):
        if args[i] == "--glb":
            glb = args[i + 1]
            i += 1
        elif args[i] == "--sheet":
            sheet = args[i + 1]
            i += 1
        i += 1
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m, ob, rig, info, views = build()
    vx.export_glb(os.path.abspath(glb), [ob, rig])
    print("[zombie_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(rig, os.path.abspath(sheet), _ref_path())
        print("[zombie_voxel] planche -> %s" % sheet)
