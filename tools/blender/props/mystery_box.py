# Modèle de la boîte mystère (coffre de bois usé cerclé de fer, dans l'esprit
# de la Mystery Box de Black Ops 1 Zombies, avec des points d'interrogation au
# pochoir DESSINÉS POUR CE JEU : aucun logo ni élément graphique repris),
# exporté en .glb pour Godot, sans fenêtre :
#
#   sh tools/blender.sh tools/blender/props/mystery_box.py [dossier .glb] [dossier aperçus]
#
# Repère Blender : Z en haut, face avant vers -Y (devient +Z dans Godot, face
# au joueur), origine au sol au centre de l'empreinte. Encombrement : la
# collision de MysteryBox (1,80 x 0,85 x 0,85 m) ; seuls de petits détails
# (charnières, cadenas, poignées) dépassent de quelques centimètres.
#
# Couvercle : charnière sur l'arête arrière haute (y = +0,42, z = 0,75), le
# pivot de MysteryBox._lid. Ses objets sont préfixés « lid_ ».
#
# Objets exportés (lus par BoxModel côté Godot) : un objet par matériau,
# nommé comme lui (fusion : un appel de rendu par matériau) :
#   wood, lid_wood     planches (UV en mètres dans le sens du fil ; UV2.x :
#                      tirage propre à chaque planche, teinte et motif)
#   iron, lid_iron     cornières, sangles, rivets, charnières, poignées
#   brass              plaque de serrure
#   paint              points d'interrogation au pochoir (peinture écaillée)
#   inner              fond et intérieur sombre du coffre
#   glow               fond lumineux (s'allume quand le couvercle s'ouvre)
import bpy, bmesh, math, os, random, sys
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(args[0] if args else "assets/models/props")
PREVIEW_DIR = os.path.abspath(args[1]) if len(args) > 1 else ""

rng = random.Random(1963)


def srgb(c):
    def f(x):
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


# matériau -> (couleur sRGB, rugosité, métal)
MATS = {
    "wood": ((0.36, 0.23, 0.13), 0.85, 0.0),
    "lid_wood": ((0.36, 0.23, 0.13), 0.85, 0.0),
    "iron": ((0.2, 0.2, 0.19), 0.6, 0.5),
    "lid_iron": ((0.2, 0.2, 0.19), 0.6, 0.5),
    "brass": ((0.56, 0.42, 0.18), 0.4, 0.9),
    "paint": ((0.86, 0.8, 0.6), 0.8, 0.0),
    "inner": ((0.07, 0.05, 0.035), 0.95, 0.0),
    "glow": ((1.0, 0.86, 0.6), 0.5, 0.0),
}

# ------------------------------------------------------------------ dimensions
W = 0.9        # demi-largeur (x)
D = 0.425      # demi-profondeur (y)
H = 0.75       # haut du corps (charnière)
LID = 0.85     # dessus du couvercle
HINGE = (0.42, H)   # (y, z) de l'axe du couvercle
FRONT = -D + 0.01   # face avant des planches
PLANK_T = 0.032     # épaisseur des planches
GAP = 0.006         # jour entre deux planches
FLOOR = 0.30        # fond intérieur (les armes montent de 0,40 m)
ROWS = 5            # planches par paroi
Z0 = 0.026          # bas des planches (patins dessous)
ROW_H = (H - Z0) / ROWS

_parts = {}


def add(mat, bm, bevel=0.0, along=0, seed=None):
    """Ajoute une pièce (bmesh fermé) au maillage du matériau. UV en mètres,
    u dans le sens du fil (`along` : 0 = x, 1 = y, 2 = z), UV2.x = tirage."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=1,
                        affect="EDGES", profile=0.5, clamp_overlap=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    s = rng.random() if seed is None else seed
    uv = bm.loops.layers.uv.new("UVMap")
    uv2 = bm.loops.layers.uv.new("UV2")
    off = Vector((s * 13.7, s * 5.3))
    for f in bm.faces:
        n = f.normal
        d = max(range(3), key=lambda i: abs(n[i]))
        if d == along:
            a, b = [i for i in range(3) if i != d]
        else:
            a = along
            b = [i for i in range(3) if i != d and i != along][0]
        for l in f.loops:
            l[uv].uv = (l.vert.co[a] + off.x, l.vert.co[b] + off.y)
            l[uv2].uv = (s, 0.0)
    me = bpy.data.meshes.new("tmp")
    bm.to_mesh(me)
    bm.free()
    dst = _parts.setdefault(mat, [])
    dst.append(me)


def box(mat, x0, x1, y0, y1, z0, z1, bevel=0.0, along=None, seed=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
                        @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1.0)), verts=bm.verts[:])
    if along is None:
        sz = (x1 - x0, y1 - y0, z1 - z0)
        along = max(range(3), key=lambda i: sz[i])
    add(mat, bm, bevel, along, seed)


def cyl(mat, c, r, h, axis="Z", segs=10, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    rot = {"Z": Matrix.Identity(4), "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
           "X": Matrix.Rotation(math.pi / 2, 4, "Y")}[axis]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot, verts=bm.verts[:])
    add(mat, bm, 0.0, "XYZ".index(axis))


def rivet(mat, c, normal, r=0.009):
    """Tête de rivet bombée posée sur une face (normale : axe ±X, ±Y ou +Z)."""
    axis = "X" if abs(normal[0]) > 0.5 else ("Y" if abs(normal[1]) > 0.5 else "Z")
    p = Vector(c) + Vector(normal) * 0.003
    cyl(mat, p, r, 0.006, axis, 8, r * 0.55)


# ------------------------------------------------------------------ pochoir « ? »
# Point d'interrogation original, dessiné pour ce jeu : crochet épais à
# pointe de pinceau, ponts de pochoir (deux coupures), tige courte, point
# carré. Polygones convexes dans un carré unité (u à droite, v en haut).

def glyph_polys():
    polys = []
    cx, cy = 0.0, 0.17
    r_in, r_out = 0.13, 0.27
    # Crochet : de 200° à -40° (sens horaire), coupé aux ponts.
    a0, a1 = 200.0, -42.0
    bridges = [(118.0, 104.0), (8.0, -4.0)]
    n = 30
    for i in range(n):
        t0 = a0 + (a1 - a0) * i / n
        t1 = a0 + (a1 - a0) * (i + 1) / n
        mid = (t0 + t1) / 2
        if any(lo > mid > hi for lo, hi in bridges):
            continue
        # Trait de pinceau : un peu plus fin au départ (pointe).
        k0 = min(1.0, 0.55 + (a0 - t0) / 60.0)
        k1 = min(1.0, 0.55 + (a0 - t1) / 60.0)
        w0 = (r_out - r_in) * k0
        w1 = (r_out - r_in) * k1
        rm = (r_out + r_in) / 2
        pts = []
        for t, w in ((t0, w0), (t1, w1)):
            ca, sa = math.cos(math.radians(t)), math.sin(math.radians(t))
            pts.append((cx + ca * (rm - w / 2), cy + sa * (rm - w / 2), cx + ca * (rm + w / 2), cy + sa * (rm + w / 2)))
        (ia, ib, oa, ob), (ja, jb, pa, pb) = pts
        polys.append([(ia, ib), (oa, ob), (pa, pb), (ja, jb)])
    # Col : du bout du crochet vers la tige.
    ca, sa = math.cos(math.radians(a1)), math.sin(math.radians(a1))
    inner = (cx + ca * r_in, cy + sa * r_in)
    outer = (cx + ca * r_out, cy + sa * r_out)
    polys.append([inner, outer, (0.075, -0.13), (-0.075, -0.1)])
    # Tige.
    polys.append([(-0.075, -0.1), (0.075, -0.13), (0.07, -0.22), (-0.07, -0.21)])
    # Point (carré aux coins cassés).
    q = 0.075
    c = (0.0, -0.37)
    polys.append([(c[0] - q, c[1] - q * 0.6), (c[0] - q * 0.6, c[1] - q), (c[0] + q * 0.6, c[1] - q),
                  (c[0] + q, c[1] - q * 0.6), (c[0] + q, c[1] + q * 0.6), (c[0] + q * 0.6, c[1] + q),
                  (c[0] - q * 0.6, c[1] + q), (c[0] - q, c[1] + q * 0.6)])
    return polys


def decal(mat, origin, right, up, size, rot_deg=0.0, cut_v=()):
    """Peinture plate (une face) : glyphe de hauteur `size`, centré sur
    `origin`, dans le plan (right, up), décollé de 1 mm. `cut_v` : bandes
    (v0, v1) en mètres le long de `up` (jours entre planches) où la peinture
    manque."""
    bm = bmesh.new()
    ca, sa = math.cos(math.radians(rot_deg)), math.sin(math.radians(rot_deg))
    for poly in glyph_polys():
        vs = []
        for u, v in poly:
            ru, rv = (u * ca - v * sa) * size, (u * sa + v * ca) * size
            vs.append(bm.verts.new((ru, rv, 0.0)))
        bm.faces.new(vs)
    for v0, v1 in cut_v:
        for z in (v0, v1):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, z, 0), plane_no=(0, 1, 0))
        gone = [f for f in bm.faces if v0 < f.calc_center_median().y < v1]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
    right, up = Vector(right), Vector(up)
    nrm = right.cross(up)
    m = Matrix((
        (right.x, up.x, nrm.x, origin[0] + nrm.x * 0.001),
        (right.y, up.y, nrm.y, origin[1] + nrm.y * 0.001),
        (right.z, up.z, nrm.z, origin[2] + nrm.z * 0.001),
        (0, 0, 0, 1)))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for f in bm.faces:
        if f.normal.dot(nrm) < 0:
            f.normal_flip()
    uv = bm.loops.layers.uv.new("UVMap")
    uv2 = bm.loops.layers.uv.new("UV2")
    s = rng.random()
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co - Vector(origin)
            l[uv].uv = (p.dot(right) + s * 3.1, p.dot(up) + s * 1.7)
            l[uv2].uv = (s, 0.0)
    me = bpy.data.meshes.new("tmp")
    bm.to_mesh(me)
    bm.free()
    _parts.setdefault(mat, []).append(me)


def gaps_around(center_v):
    """Jours entre rangées de planches, en coordonnées locales du glyphe."""
    out = []
    for r in range(1, ROWS):
        z = Z0 + r * ROW_H
        out.append((z - GAP / 2 - center_v, z + GAP / 2 - center_v))
    return out


# ------------------------------------------------------------------ corps
def body():
    post = 0.055  # montants d'angle (carrés)
    # Patins sous le coffre.
    for y in (-0.3, 0.3):
        box("wood", -W + 0.04, W - 0.04, y - 0.05, y + 0.05, 0.0, Z0 + 0.004, 0.004)
    # Fond et âme sombre (bouche les jours sous le fond intérieur).
    box("inner", -W + 0.03, W - 0.03, -D + 0.03, D - 0.03, Z0, FLOOR, 0.0)
    # Montants d'angle.
    for sx in (-1, 1):
        for sy in (-1, 1):
            # Dans l'angle intérieur, derrière les planches (jamais coplanaire).
            x = sx * (W - 0.012 - PLANK_T - post / 2)
            y = sy * (D - 0.012 - PLANK_T - post / 2)
            box("wood", x - post / 2, x + post / 2, y - post / 2, y + post / 2, Z0, H - 0.002, 0.005, along=2)
    # Planches : avant/arrière dans le sens x, côtés dans le sens y.
    for r in range(ROWS):
        z0 = Z0 + r * ROW_H + GAP / 2
        z1 = Z0 + (r + 1) * ROW_H - GAP / 2
        for sy in (-1, 1):
            y_out = sy * (D - 0.012)
            y_in = y_out - sy * PLANK_T
            # Planche un peu gauchie : léger décalage par rangée.
            dz = (rng.random() - 0.5) * 0.004
            box("wood", -W + 0.012, W - 0.012, min(y_in, y_out), max(y_in, y_out), z0 + dz, z1 + dz, 0.004, along=0)
        for sx in (-1, 1):
            x_out = sx * (W - 0.012)
            x_in = x_out - sx * PLANK_T
            box("wood", min(x_in, x_out), max(x_in, x_out), -D + 0.012 + PLANK_T, D - 0.012 - PLANK_T, z0, z1, 0.004, along=1)
    # Fond intérieur (planches sombres) et bord intérieur.
    for i in range(4):
        y0 = -D + 0.045 + i * (2 * D - 0.09) / 4
        y1 = y0 + (2 * D - 0.09) / 4 - GAP
        box("inner", -W + 0.045, W - 0.045, y0, y1, FLOOR, FLOOR + 0.02, 0.003, along=0)
    box("glow", -W + 0.1, W - 0.1, -D + 0.1, D - 0.1, FLOOR + 0.021, FLOOR + 0.024, 0.0)

    # -------- ferrures
    t = 0.005  # épaisseur des fers plats
    fw = 0.05  # largeur des cornières
    for sx in (-1, 1):
        for sy in (-1, 1):
            # Cornière d'angle sur toute la hauteur : une aile sur chaque face.
            x_face = sx * (W - 0.012)
            y_face = sy * (D - 0.012)
            # Ailes plus épaisses (7 mm) que sangles (5) et bande (3) : les
            # fers qui se croisent ne sont jamais coplanaires.
            tw = 0.007
            box("iron", min(x_face - sx * fw, x_face + sx * tw), max(x_face - sx * fw, x_face + sx * tw),
                min(y_face, y_face + sy * tw), max(y_face, y_face + sy * tw), Z0, H - 0.004, 0.0015)
            box("iron", min(x_face, x_face + sx * tw), max(x_face, x_face + sx * tw),
                min(y_face - sy * fw, y_face), max(y_face - sy * fw, y_face), Z0, H - 0.004, 0.0015)
            # Rivets sur les deux ailes.
            for k in range(5):
                z = Z0 + 0.06 + k * (H - Z0 - 0.12) / 4
                rivet("iron", (x_face - sx * fw * 0.5, y_face + sy * tw, z), (0, sy, 0))
                rivet("iron", (x_face + sx * tw, y_face - sy * fw * 0.5, z), (sx, 0, 0))
            # Sabot d'angle en bas.
            box("iron", min(x_face - sx * 0.07, x_face + sx * t * 2), max(x_face - sx * 0.07, x_face + sx * t * 2),
                min(y_face - sy * 0.07, y_face + sy * t * 2), max(y_face - sy * 0.07, y_face + sy * t * 2),
                0.0, Z0 + 0.05, 0.002)
    # Sangles verticales en façade et au dos (dans l'axe de celles du couvercle).
    for sy in (-1, 1):
        y_face = sy * (D - 0.012)
        for x in (-0.62, 0.62):
            box("iron", x - 0.03, x + 0.03, min(y_face, y_face + sy * t), max(y_face, y_face + sy * t), Z0 + 0.02, H - 0.004, 0.0015)
            for k in range(4):
                rivet("iron", (x, y_face + sy * t, Z0 + 0.08 + k * 0.19), (0, sy, 0), 0.008)
    # Bande de fer en haut du corps (tout le tour).
    for sy in (-1, 1):
        y_face = sy * (D - 0.012)
        box("iron", -W + 0.012, W - 0.012, min(y_face, y_face + sy * 0.003), max(y_face, y_face + sy * 0.003), H - 0.05, H - 0.006, 0.0015)
    for sx in (-1, 1):
        x_face = sx * (W - 0.012)
        box("iron", min(x_face, x_face + sx * 0.003), max(x_face, x_face + sx * 0.003), -D + 0.012, D - 0.012, H - 0.05, H - 0.006, 0.0015)
    # Poignées sur les côtés : platines et barre.
    for sx in (-1, 1):
        x_face = sx * (W - 0.012) + sx * t
        for y in (-0.12, 0.12):
            box("iron", min(x_face, x_face + sx * 0.008), max(x_face, x_face + sx * 0.008), y - 0.025, y + 0.025, 0.44, 0.52, 0.002)
            rivet("iron", (x_face + sx * 0.008, y, 0.5), (sx, 0, 0), 0.007)
            cyl("iron", (x_face + sx * 0.02, y, 0.465), 0.008, 0.03, "X", 8)
        # Barre à 3 cm du flanc : ne dépasse la collision que de 3 cm.
        cyl("iron", (x_face + sx * 0.03, 0.0, 0.465), 0.01, 0.28, "Y", 10)
    # Serrure en façade : plaque de laiton et entrée de clé.
    yf = -(D - 0.012) - t
    box("brass", -0.065, 0.065, yf - 0.006, yf, H - 0.17, H - 0.055, 0.003)
    box("inner", -0.009, 0.009, yf - 0.0075, yf - 0.005, H - 0.13, H - 0.1, 0.0)
    cyl("inner", (0.0, yf - 0.0065, H - 0.095), 0.014, 0.003, "Y", 10)
    for x in (-0.048, 0.048):
        for z in (H - 0.155, H - 0.07):
            rivet("brass", (x, yf - 0.006, z), (0, -1, 0), 0.006)
    # Charnières (axes et ailes côté corps), au dos.
    yb = D - 0.012 + t
    for x in (-0.55, 0.55):
        cyl("iron", (x, HINGE[0] + 0.012, HINGE[1]), 0.013, 0.14, "X", 10)
        box("iron", x - 0.05, x + 0.05, yb, yb + 0.005, H - 0.16, H - 0.012, 0.0015)
        for k in (-1, 1):
            rivet("iron", (x + k * 0.03, yb + 0.005, H - 0.1), (0, 1, 0), 0.007)
    # Peinture : deux « ? » en façade, un sur chaque côté.
    for x, rot in ((-0.31, 6.0), (0.31, -5.0)):
        zc = 0.40
        decal("paint", (x, -(D - 0.012), zc), (1, 0, 0), (0, 0, 1), 0.46, rot, gaps_around(zc))
    for sx in (-1, 1):
        zc = 0.38
        right = (0, sx, 0)
        decal("paint", (sx * (W - 0.012), 0.0, zc), right, (0, 0, 1), 0.4, 4.0 * sx, gaps_around(zc))


# ------------------------------------------------------------------ couvercle
def lid():
    t = 0.005
    top = LID
    plank_t = 0.034
    # Planches du dessus (sens x), quatre de front.
    n = 4
    span = 2 * D
    for i in range(n):
        y0 = -D + i * span / n + GAP / 2
        y1 = -D + (i + 1) * span / n - GAP / 2
        dz = (rng.random() - 0.5) * 0.003
        box("lid_wood", -W, W, y0, y1, top - plank_t + dz, top + dz, 0.004, along=0)
    # Ceinture du couvercle (cadre sous les planches).
    sk = 0.03
    z0, z1 = H + 0.004, top - plank_t
    for sy in (-1, 1):
        box("lid_wood", -W + 0.006, W - 0.006, min(sy * (D - 0.006), sy * (D - 0.006 - sk)), max(sy * (D - 0.006), sy * (D - 0.006 - sk)), z0, z1 + 0.002, 0.004, along=0)
    for sx in (-1, 1):
        box("lid_wood", min(sx * (W - 0.006), sx * (W - 0.006 - sk)), max(sx * (W - 0.006), sx * (W - 0.006 - sk)), -D + 0.006 + sk, D - 0.006 - sk, z0, z1 + 0.002, 0.004, along=1)
    # Dessous du couvercle (planche sombre, vue couvercle ouvert).
    box("lid_wood", -W + 0.04, W - 0.04, -D + 0.04, D - 0.04, z1 - 0.004, z1 + 0.001, 0.0, along=0)
    # Sangles de fer sur le dessus, rabattues sur la ceinture avant et arrière.
    # Fers plaqués sur la ceinture (6 mm en retrait du bord des planches) ;
    # ils dépassent les planches de 1 à 2 mm.
    skf = D - 0.006
    for x in (-0.62, 0.62):
        box("lid_iron", x - 0.03, x + 0.03, -D - 0.002, D + 0.002, top, top + t, 0.0015)
        for sy in (-1, 1):
            box("lid_iron", x - 0.03, x + 0.03, min(sy * skf, sy * (D + 0.002)), max(sy * skf, sy * (D + 0.002)), z0, top + t, 0.0015)
        for k in range(4):
            rivet("lid_iron", (x, -D + 0.1 + k * (2 * D - 0.2) / 3, top + t), (0, 0, 1), 0.008)
    # Coiffes d'angle (équerres sur les quatre coins du dessus, ailes
    # rabattues sur la ceinture).
    for sx in (-1, 1):
        for sy in (-1, 1):
            xa, ya = sx * W, sy * D
            xs, ys = sx * (W - 0.006), sy * skf
            box("lid_iron", min(xa, xa - sx * 0.12), max(xa, xa - sx * 0.12), min(ya, ya - sy * 0.05), max(ya, ya - sy * 0.05), top + 0.0005, top + t + 0.001, 0.0015)
            box("lid_iron", min(xa, xa - sx * 0.05), max(xa, xa - sx * 0.05), min(ya - sy * 0.05, ya - sy * 0.12), max(ya - sy * 0.05, ya - sy * 0.12), top + 0.0005, top + t + 0.001, 0.0015)
            box("lid_iron", min(xs, xa + sx * 0.002), max(xs, xa + sx * 0.002), min(ya, ya - sy * 0.08), max(ya, ya - sy * 0.08), z0, top + t, 0.0015)
            box("lid_iron", min(xa, xa - sx * 0.08), max(xa, xa - sx * 0.08), min(ys, ya + sy * 0.003), max(ys, ya + sy * 0.003), z0, top + t, 0.0015)
            rivet("lid_iron", (xa - sx * 0.035, ya - sy * 0.035, top + t + 0.001), (0, 0, 1), 0.007)
    # Moraillon en façade (pend devant la serrure, s'ouvre avec le couvercle).
    box("lid_iron", -0.028, 0.028, -skf - 0.009, -skf, H - 0.05, top - 0.01, 0.0015)
    cyl("lid_iron", (0.0, -skf - 0.012, H - 0.045), 0.012, 0.05, "X", 8)
    rivet("lid_iron", (0.0, -skf - 0.009, top - 0.03), (0, -1, 0), 0.007)
    # Ailes des charnières côté couvercle.
    for x in (-0.55, 0.55):
        box("lid_iron", x - 0.05, x + 0.05, D - 0.02, D + t + 0.002, top, top + t + 0.002, 0.0015)
        box("lid_iron", x - 0.05, x + 0.05, D + t, D + t + 0.005, H + 0.002, top, 0.0015)


# ------------------------------------------------------------------ scène
def material(name, suffix=""):
    key = name + suffix
    m = bpy.data.materials.get(key) or bpy.data.materials.new(key)
    c, rough, metal = MATS[name]
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = srgb(c)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if name == "glow":
        p.inputs["Emission Color"].default_value = srgb(c)
        p.inputs["Emission Strength"].default_value = 2.0
    m.diffuse_color = srgb(c)
    return m


def build_objects(offset=(0.0, 0.0, 0.0), suffix="", lid_open=0.0):
    _parts.clear()
    body()
    lid()
    obs = []
    tris = 0
    for name, meshes in sorted(_parts.items()):
        bm = bmesh.new()
        for me in meshes:
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        me = bpy.data.meshes.new(name + suffix)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(material(name, suffix))
        for poly in me.polygons:
            poly.use_smooth = False
        tris += len(me.polygons)
        ob = bpy.data.objects.new(name + suffix, me)
        ob.location = offset
        if name.startswith("lid_") and lid_open != 0.0:
            # Aperçu seulement : couvercle ouvert autour de la charnière.
            piv = Vector((0, HINGE[0], HINGE[1]))
            ob.matrix_world = Matrix.Translation(Vector(offset) + piv) @ Matrix.Rotation(lid_open, 4, "X") @ Matrix.Translation(-piv)
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
    _parts.clear()
    return obs, tris


def export():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs, tris = build_objects()
    for ob in obs:
        ob.select_set(True)
    out = os.path.join(OUT_DIR, "mystery_box.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_texcoords=True,
                              export_normals=True)
    print("[mystery_box] %d objets, %d triangles -> %s" % (len(obs), tris, out))


def preview():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    build_objects((-1.1, 0.0, 0.0), "_a")
    build_objects((1.1, 0.0, 0.0), "_b", lid_open=-1.5)
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 1.0, 5), rotation=(math.pi / 2, 0, 0))
    wm = bpy.data.materials.new("mur")
    wm.use_nodes = True
    wm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.05, 0.045, 1)
    for ob in sc.objects:
        if ob.name.startswith("Plane"):
            ob.data.materials.append(wm)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.03, 0.035, 1)
    sc.world = world
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 500
    key.data.size = 5
    key.location = (-2, -5, 4)
    key.rotation_euler = (math.radians(50), 0, math.radians(-20))
    sc.collection.objects.link(key)
    sc.render.resolution_x, sc.render.resolution_y = 1600, 800
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    target = bpy.data.objects.new("cible", None)
    sc.collection.objects.link(target)
    target.location = (0, 0, 0.5)
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    for fname, loc in (("box_front.png", (-1.0, -4.6, 1.9)), ("box_side.png", (3.4, -2.2, 2.6))):
        cam.location = loc
        cam.data.lens = 35
        sc.render.filepath = os.path.join(PREVIEW_DIR, fname)
        bpy.ops.render.render(write_still=True)
        print("[mystery_box] aperçu -> %s" % sc.render.filepath)


os.makedirs(OUT_DIR, exist_ok=True)
export()
if PREVIEW_DIR:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    preview()
