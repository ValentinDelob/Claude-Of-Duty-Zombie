# Modèles des machines d'atouts (distributeurs de soda des années 50, dans
# l'esprit des Perk-a-Cola de Black Ops 1 Zombies, avec des noms et des
# emblèmes ORIGINAUX) exportés en .glb pour Godot, sans fenêtre :
#
#   sh tools/blender.sh tools/blender/props/perk_machines.py <dossier .glb> [dossier aperçus] [ids...]
#
# Sans liste d'ids : les 7 atouts de PerkDB. Avec un dossier d'aperçus :
# rendus PNG (alignement de face, vue de trois quarts, courant rétabli).
#
# Repère Blender : Z en haut, face avant vers -Y (devient +Z dans Godot, face
# au joueur), origine au sol au centre de l'empreinte, dos à y = +0,40 au plus.
#
# Objets exportés (lus par PerkMachine côté Godot) : un objet par matériau,
# nommé comme lui (fusion : un appel de rendu par matériau) :
#   paint, paint2        peinture principale et secondaire
#   chrome, dark, glass  garnitures, caoutchouc/fonte, vitres sombres
#   lit_sign             panneau lumineux (s'allume avec le courant)
#   lit_ink              lettrage et emblèmes (s'allument plus faiblement)
#   lit_lamp             ampoules, hublots, bouteilles (les plus vives)
#   col_<n>              boîtes de collision (invisibles : Godot en fait des
#                        BoxShape3D d'après leur boîte englobante)
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
# Chemins absolus : Blender résout un chemin de rendu relatif depuis la
# racine du disque (fichier .blend sans nom), pas depuis le dossier courant.
OUT_DIR = os.path.abspath(args[0] if args else "assets/models/perks")
PREVIEW_DIR = os.path.abspath(args[1]) if len(args) > 1 else ""
ONLY = args[2:]


def srgb(c):
    """Couleur sRGB -> linéaire (Blender et glTF travaillent en linéaire)."""
    def f(x):
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


# Matière commune : [rugosité, métal].
MAT_PBR = {
    "paint": (0.62, 0.2), "paint2": (0.58, 0.2), "chrome": (0.22, 1.0),
    "dark": (0.75, 0.1), "glass": (0.08, 0.0),
    "lit_sign": (0.45, 0.0), "lit_ink": (0.45, 0.0), "lit_lamp": (0.2, 0.0),
}
COMMON = {"chrome": (0.78, 0.78, 0.76), "dark": (0.05, 0.05, 0.05), "glass": (0.04, 0.05, 0.06)}

# Couleurs (sRGB) par atout : peinture, peinture 2, panneau, lettrage, ampoules.
PERKS = {
    # Juggernog : grand distributeur bordeaux, dôme crème éclairé.
    "titan": {"paint": (0.36, 0.05, 0.04), "paint2": (0.5, 0.1, 0.06), "lit_sign": (0.95, 0.85, 0.66),
              "lit_ink": (0.55, 0.05, 0.03), "lit_lamp": (1.0, 0.45, 0.3)},
    # Speed Cola : caisse verte, tête blanche, colonne de hublots.
    "rapid": {"paint": (0.06, 0.25, 0.12), "paint2": (0.1, 0.34, 0.17), "lit_sign": (0.88, 0.92, 0.86),
              "lit_ink": (0.04, 0.36, 0.13), "lit_lamp": (0.6, 1.0, 0.7)},
    # Double Tap : grand coffre ambré, bande de tôle ondulée, capsule.
    "twin": {"paint": (0.66, 0.44, 0.16), "paint2": (0.26, 0.13, 0.05), "lit_sign": (0.98, 0.8, 0.45),
             "lit_ink": (0.3, 0.13, 0.04), "lit_lamp": (1.0, 0.78, 0.4)},
    # Quick Revive : glacière bleu-gris, fronton bleu clair, panneau rond.
    "lazarus": {"paint": (0.2, 0.3, 0.38), "paint2": (0.82, 0.84, 0.82), "lit_sign": (0.78, 0.92, 1.0),
                "lit_ink": (0.06, 0.3, 0.7), "lit_lamp": (0.6, 0.85, 1.0)},
    # Atout de sprint : vitrine en arche violette.
    "stride": {"paint": (0.24, 0.1, 0.32), "paint2": (0.36, 0.18, 0.46), "lit_sign": (0.9, 0.84, 0.96),
               "lit_ink": (0.3, 0.05, 0.48), "lit_lamp": (0.85, 0.6, 1.0)},
    # PhD Flopper : machine « âge atomique » violette et jaune, dôme de verre.
    "nova": {"paint": (0.22, 0.06, 0.36), "paint2": (0.85, 0.62, 0.12), "lit_sign": (1.0, 0.86, 0.45),
             "lit_ink": (0.34, 0.05, 0.55), "lit_lamp": (0.95, 0.55, 1.0)},
    # Deadshot : caisse kaki à fronton, grande cible rouge.
    "deadeye": {"paint": (0.4, 0.38, 0.28), "paint2": (0.2, 0.2, 0.15), "lit_sign": (0.96, 0.93, 0.8),
                "lit_ink": (0.45, 0.05, 0.03), "lit_lamp": (1.0, 0.5, 0.4)},
}

# ------------------------------------------------------------------ géométrie
_parts = {}   # matériau -> bmesh fusionné
_cols = []    # boîtes de collision (centre, taille)


def reset():
    global _parts, _cols
    for bm in _parts.values():
        bm.free()
    _parts = {}
    _cols = []


def add(mat, bm, bevel=0.0, seg=2):
    """Ajoute une pièce (bmesh fermé) au maillage du matériau."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=seg,
                        affect="EDGES", profile=0.5, clamp_overlap=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("tmp")
    bm.to_mesh(me)
    bm.free()
    dst = _parts.setdefault(mat, bmesh.new())
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)


def prism_xz(mat, pts, y0, y1, bevel=0.0, seg=2):
    """Profil vu de face (points x, z) extrudé en profondeur de y0 à y1."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in pts]
    b = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    add(mat, bm, bevel, seg)


def prism_yz(mat, pts, x0, x1, bevel=0.0, seg=2):
    """Profil vu de côté (points y, z) extrudé en largeur de x0 à x1."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in pts]
    b = [bm.verts.new((x1, y, z)) for y, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    add(mat, bm, bevel, seg)


def box(mat, x0, x1, y0, y1, z0, z1, bevel=0.0, seg=2):
    prism_xz(mat, [(x0, z0), (x1, z0), (x1, z1), (x0, z1)], y0, y1, bevel, seg)


def cyl(mat, c, r, h, axis="Z", segs=20, r2=None):
    """Cylindre (ou cône si r2) centré en c, de longueur h selon l'axe."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    rot = {"Z": Matrix.Identity(4), "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
           "X": Matrix.Rotation(math.pi / 2, 4, "Y")}[axis]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot, verts=bm.verts[:])
    add(mat, bm)


def sphere(mat, c, r, half=False, segs=20):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r)
    if half:
        # Dôme : on garde l'hémisphère du haut et on referme la base.
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
        edges = [e for e in bm.edges if e.is_boundary]
        bmesh.ops.edgeloop_fill(bm, edges=edges)
    bmesh.ops.translate(bm, vec=c, verts=bm.verts[:])
    add(mat, bm)


def ring_y(mat, cx, cz, y0, y1, r_in, r_out, segs=32):
    """Anneau (jante chromée d'un panneau rond ou d'un hublot), axe Y."""
    bm = bmesh.new()
    vs = []
    for i in range(segs):
        t = 2 * math.pi * i / segs
        c, s = math.cos(t), math.sin(t)
        vs.append([bm.verts.new((cx + c * r, y, cz + s * r)) for r, y in
                   ((r_in, y0), (r_out, y0), (r_out, y1), (r_in, y1))])
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(4):
            l = (k + 1) % 4
            bm.faces.new((vs[i][k], vs[j][k], vs[j][l], vs[i][l]))
    add(mat, bm)


def flat(mat, pts, cx, cz, size, y_front, depth=0.006, tilt=0.0, yb=None):
    """Motif plat (emblème) : points (u, v) dans [-0,5, 0,5], posé sur un plan
    de face à y_front, centré en (cx, cz), incliné vers l'arrière de `tilt` rad."""
    bm = bmesh.new()
    rot = Matrix.Rotation(tilt, 3, "X")

    def P(u, v, d):
        return Vector((cx, y_front, cz)) + rot @ Vector((u * size, d, v * size))
    a = [bm.verts.new(P(u, v, -depth)) for u, v in pts]
    b = [bm.verts.new(P(u, v, 0.001)) for u, v in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    add(mat, bm)


def text(mat, s, cx, cz, y_front, height, max_w, shear=0.18, tilt=0.0, bold=0.03, spacing=1.0):
    """Lettrage en relief (police intégrée de Blender), face vers -Y, mis à
    l'échelle pour tenir dans max_w x height."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.shear = shear
    cu.extrude = 0.02
    cu.offset = bold
    cu.space_line = 0.82
    cu.space_character = spacing
    cu.size = 1.0
    ob = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), 0))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), 0))
    k = min(max_w / (hi.x - lo.x), height / (hi.y - lo.y))
    mid = (lo + hi) * 0.5
    # Texte dans le plan XY (face +Z), épaisseur 0..0,02 en Z : on le
    # recentre, on l'aplatit (relief de 3 mm) puis on le tourne face à -Y.
    for v in bm.verts:
        v.co = Vector(((v.co.x - mid.x) * k, (v.co.y - mid.y) * k, (v.co.z - 0.01) * 0.15 + 0.0015))
    m = Matrix.Translation((cx, y_front, cz)) @ Matrix.Rotation(tilt, 4, "X") @ Matrix.Rotation(math.pi / 2, 4, "X")
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    add(mat, bm)


def col(x0, x1, y0, y1, z0, z1):
    _cols.append(((x0, x1), (y0, y1), (z0, z1)))


# ------------------------------------------------------------------ profils

def rounded_top(w, z0, z1, r, n=8):
    """Rectangle de largeur w, coins du haut arrondis (rayon r)."""
    h = w / 2
    pts = [(-h, z0), (h, z0)]
    for i in range(n + 1):
        t = math.pi / 2 * i / n
        pts.append((h - r + math.cos(t) * r, z1 - r + math.sin(t) * r))
    for i in range(n + 1):
        t = math.pi / 2 + math.pi / 2 * i / n
        pts.append((-h + r + math.cos(t) * r, z1 - r + math.sin(t) * r))
    return pts


def arch(w, z0, z_spring, n=16):
    """Rectangle surmonté d'un demi-cercle (vitrine en arche)."""
    h = w / 2
    pts = [(-h, z0), (h, z0)]
    for i in range(n + 1):
        t = math.pi * i / n
        pts.append((math.cos(t) * h, z_spring + math.sin(t) * h))
    return pts


def circle(r, n=24, cx=0.0, cz=0.0):
    return [(cx + math.cos(2 * math.pi * i / n) * r, cz + math.sin(2 * math.pi * i / n) * r) for i in range(n)]


# ------------------------------------------------------------------ emblèmes
# Motifs (u, v) dans un carré unité, dessinés pour ce jeu (aucun logo repris).

def em_anvil():
    return [(-0.5, 0.3), (0.46, 0.3), (0.46, 0.14), (0.2, 0.06), (0.12, -0.16), (0.3, -0.28),
            (-0.3, -0.28), (-0.12, -0.16), (-0.18, 0.06), (-0.3, 0.12), (-0.5, 0.16)]


def em_bolt():
    return [(0.16, 0.48), (-0.26, -0.02), (-0.02, -0.02), (-0.16, -0.48), (0.28, 0.06), (0.04, 0.06)]


def em_bullet(x):
    pts = [(x - 0.09, -0.4), (x + 0.09, -0.4), (x + 0.09, 0.1)]
    for i in range(1, 8):
        t = math.pi * i / 8
        pts.append((x + math.cos(t) * 0.09, 0.1 + math.sin(t) * 0.26))
    pts.append((x - 0.09, 0.1))
    return pts


def em_heart():
    pts = []
    for i in range(28):
        t = 2 * math.pi * i / 28
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 34.0, y / 34.0 + 0.04))
    return pts


def em_chevron(x):
    return [(x - 0.14, 0.34), (x + 0.02, 0.34), (x + 0.2, 0.0), (x + 0.02, -0.34), (x - 0.14, -0.34), (x + 0.04, 0.0)]


def em_star(points=8, r1=0.48, r2=0.2):
    pts = []
    for i in range(points * 2):
        t = math.pi * i / points + math.pi / 2
        r = r1 if i % 2 == 0 else r2
        pts.append((math.cos(t) * r, math.sin(t) * r))
    return pts


def em_cross_bar(ax, ay, bx, by, w):
    """Barre épaisse de (ax, ay) à (bx, by)."""
    d = Vector((bx - ax, by - ay)).normalized()
    n = Vector((-d.y, d.x)) * w / 2
    return [(ax + n.x, ay + n.y), (ax - n.x, ay - n.y), (bx - n.x, by - n.y), (bx + n.x, by + n.y)]


def emblem(perk, cx, cz, size, y_front, tilt=0.0, mat="lit_ink"):
    if perk == "titan":
        flat(mat, em_anvil(), cx, cz, size, y_front, tilt=tilt)
    elif perk == "rapid":
        flat(mat, em_bolt(), cx, cz, size, y_front, tilt=tilt)
    elif perk == "twin":
        flat(mat, em_bullet(-0.13), cx, cz, size, y_front, tilt=tilt)
        flat(mat, em_bullet(0.13), cx, cz, size, y_front, tilt=tilt)
    elif perk == "lazarus":
        flat(mat, em_heart(), cx, cz, size, y_front, tilt=tilt)
    elif perk == "stride":
        flat(mat, em_chevron(-0.24), cx, cz, size, y_front, tilt=tilt)
        flat(mat, em_chevron(0.06), cx, cz, size, y_front, tilt=tilt)
    elif perk == "nova":
        flat(mat, em_star(), cx, cz, size, y_front, tilt=tilt)
    elif perk == "deadeye":
        # Réticule : anneau, quatre traits, point central.
        outer = circle(0.4, 32)
        inner = circle(0.32, 32)
        for i in range(32):
            j = (i + 1) % 32
            flat(mat, [outer[i], outer[j], inner[j], inner[i]], cx, cz, size, y_front, tilt=tilt)
        for a, b in (((0, 0.5), (0, 0.14)), ((0, -0.5), (0, -0.14)), ((0.5, 0), (0.14, 0)), ((-0.5, 0), (-0.14, 0))):
            flat(mat, em_cross_bar(a[0], a[1], b[0], b[1], 0.07), cx, cz, size, y_front, tilt=tilt)
        flat(mat, circle(0.06, 12), cx, cz, size, y_front, tilt=tilt)


def round_sign(perk, cx, cz, y, r, depth=0.07):
    """Panneau rond lumineux (enseigne du dessus) : disque, jante, emblème
    des deux côtés."""
    cyl("lit_sign", (cx, y, cz), r, depth, "Y", 32)
    ring_y("chrome", cx, cz, y - depth / 2 - 0.012, y + depth / 2 + 0.012, r - 0.012, r + 0.022)
    emblem(perk, cx, cz, r * 1.35, y - depth / 2)


def coin_slot(cx, cz, y_front):
    box("chrome", cx - 0.045, cx + 0.045, y_front - 0.02, y_front + 0.01, cz - 0.06, cz + 0.06, 0.008)
    box("dark", cx - 0.006, cx + 0.006, y_front - 0.024, y_front, cz - 0.035, cz + 0.035)


def flap(cx, cz, w, h, y_front):
    """Trappe de distribution : cadre chromé, ouverture sombre."""
    box("chrome", cx - w / 2 - 0.02, cx + w / 2 + 0.02, y_front - 0.015, y_front + 0.01, cz - h / 2 - 0.02, cz + h / 2 + 0.02, 0.006)
    box("dark", cx - w / 2, cx + w / 2, y_front - 0.02, y_front, cz - h / 2, cz + h / 2)


def plinth(w, d, h=0.07):
    box("dark", -w / 2, w / 2, -d / 2, d / 2, 0.0, h, 0.01)


def bottle(mat, cx, cy, z0, s=1.0):
    """Petite bouteille (ornement du dessus)."""
    cyl(mat, (cx, cy, z0 + 0.08 * s), 0.055 * s, 0.16 * s, "Z", 16)
    cyl(mat, (cx, cy, z0 + 0.2 * s), 0.055 * s, 0.08 * s, "Z", 16, r2=0.022 * s)
    cyl(mat, (cx, cy, z0 + 0.28 * s), 0.02 * s, 0.08 * s, "Z", 12)
    cyl("chrome", (cx, cy, z0 + 0.33 * s), 0.025 * s, 0.025 * s, "Z", 12)


# ------------------------------------------------------------------ machines
# Hauteurs visées (BO1) : 2,1 à 2,35 m ornement compris, ~0,95 m de large.
D = 0.72
YF = -D / 2   # face avant


def m_titan():
    plinth(0.86, 0.64)
    prism_xz("paint", [(-0.47, 0.07), (0.47, 0.07), (0.47, 1.38), (-0.47, 1.38)], YF, -YF, 0.03)
    box("chrome", -0.485, 0.485, YF - 0.012, -YF + 0.012, 1.36, 1.41, 0.012)
    prism_xz("lit_sign", rounded_top(0.94, 1.41, 2.0, 0.2), YF, -YF, 0.03)
    text("lit_ink", "Buvez", -0.2, 1.9, YF, 0.06, 0.2, shear=0.3, bold=0.0)
    text("lit_ink", "TITAN\nBREW", 0.0, 1.66, YF, 0.36, 0.72)
    # Porte de distribution en relief.
    box("paint2", -0.25, 0.25, YF - 0.035, YF + 0.01, 0.28, 1.3, 0.025)
    box("chrome", -0.2, 0.2, YF - 0.05, YF - 0.03, 1.12, 1.26, 0.008)
    box("glass", -0.18, 0.18, YF - 0.056, YF - 0.04, 1.14, 1.24)
    coin_slot(0.12, 1.0, YF - 0.035)
    cyl("chrome", (-0.02, YF - 0.05, 0.9), 0.016, 0.12, "Z", 10)
    flap(0.0, 0.52, 0.16, 0.16, YF - 0.035)
    box("chrome", -0.12, 0.12, YF - 0.06, YF - 0.03, 0.38, 0.41, 0.008)  # plateau
    # Enseigne ronde sur le dessus.
    cyl("chrome", (0, 0.05, 2.06), 0.05, 0.14, "Z", 14)
    round_sign("titan", 0.0, 2.32, 0.05, 0.21)
    col(-0.49, 0.49, YF - 0.02, -YF + 0.02, 0.0, 2.02)


def m_rapid():
    plinth(0.86, 0.64)
    prism_xz("paint", [(-0.46, 0.07), (0.46, 0.07), (0.46, 1.3), (-0.46, 1.3)], YF, -YF, 0.035)
    box("chrome", -0.475, 0.475, YF - 0.012, -YF + 0.012, 1.28, 1.33, 0.012)
    prism_xz("lit_sign", rounded_top(0.92, 1.33, 1.94, 0.09), YF, -YF, 0.03)
    text("lit_ink", "RAPID\nFIZZ", -0.04, 1.63, YF, 0.4, 0.66, shear=0.25)
    text("lit_ink", "GLACÉ", 0.34, 1.86, YF, 0.05, 0.14, shear=0.0, bold=0.0)
    # Porte (à gauche) et colonne de hublots (à droite), comme les
    # distributeurs à bouteilles des années 50.
    box("paint2", -0.4, 0.14, YF - 0.035, YF + 0.01, 0.22, 1.24, 0.025)
    box("chrome", -0.34, 0.08, YF - 0.05, YF - 0.03, 1.06, 1.2, 0.008)
    box("glass", -0.32, 0.06, YF - 0.056, YF - 0.04, 1.08, 1.18)
    coin_slot(-0.03, 0.94, YF - 0.035)
    cyl("chrome", (-0.2, YF - 0.05, 0.84), 0.016, 0.12, "Z", 10)
    flap(-0.13, 0.42, 0.18, 0.14, YF - 0.035)
    box("chrome", 0.2, 0.38, YF - 0.02, YF + 0.01, 0.32, 1.24, 0.01)
    for i in range(6):
        z = 0.44 + i * 0.145
        cyl("lit_lamp", (0.29, YF - 0.024, z), 0.052, 0.012, "Y", 16)
        ring_y("chrome", 0.29, z, YF - 0.035, YF - 0.018, 0.05, 0.064, 16)
    # Grille d'aération du bas.
    for i in range(4):
        z = 0.1 + i * 0.035
        box("dark", -0.36, 0.36, YF - 0.012, YF + 0.01, z, z + 0.016)
    # Enseigne ronde sur une tige, en arrière et décalée.
    cyl("chrome", (-0.16, 0.22, 2.08), 0.028, 0.3, "Z", 12)
    round_sign("rapid", -0.16, 2.4, 0.22, 0.2)
    col(-0.48, 0.48, YF - 0.02, -YF + 0.02, 0.0, 1.96)


def m_twin():
    plinth(0.88, 0.64)
    prism_xz("paint", [(-0.47, 0.07), (0.47, 0.07), (0.47, 2.04), (-0.47, 2.04)], YF, -YF, 0.035)
    # Bande basse brune et nom lumineux.
    box("paint2", -0.46, 0.46, YF - 0.012, -YF + 0.012, 0.1, 0.5, 0.012)
    text("lit_lamp", "TWIN SHOT", 0.0, 0.3, YF - 0.012, 0.2, 0.8, shear=0.2)
    # Tôle ondulée chromée au milieu.
    for i in range(12):
        z = 0.84 + i * 0.043
        cyl("chrome", (0.0, YF + 0.004, z), 0.024, 0.9, "X", 10)
    # Colonne de distribution devant la tôle.
    box("paint2", -0.1, 0.12, YF - 0.04, YF + 0.01, 0.55, 1.42, 0.02)
    coin_slot(0.01, 1.28, YF - 0.04)
    box("glass", -0.06, 0.08, YF - 0.046, YF - 0.03, 1.02, 1.16)
    flap(0.01, 0.72, 0.12, 0.14, YF - 0.04)
    # Panneau haut éclairé avec la capsule.
    box("lit_sign", -0.44, 0.44, YF - 0.01, YF + 0.02, 1.48, 2.0, 0.01)
    teeth = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        r = 0.5 if i % 2 == 0 else 0.46
        teeth.append((math.cos(t) * r, math.sin(t) * r))
    flat("paint2", teeth, -0.1, 1.73, 0.5, YF - 0.01, depth=0.012)
    cyl("lit_sign", (-0.1, YF - 0.024, 1.73), 0.19, 0.012, "Y", 32)
    emblem("twin", -0.1, 1.73, 0.3, YF - 0.03)
    text("lit_ink", "GLACÉ !", 0.28, 1.92, YF - 0.01, 0.06, 0.2, shear=0.25, bold=0.0)
    text("lit_ink", "2x", 0.29, 1.66, YF - 0.01, 0.16, 0.2, shear=0.2)
    # Bouteille sur le dessus.
    bottle("lit_lamp", 0.26, 0.05, 2.04)
    col(-0.49, 0.49, YF - 0.02, -YF + 0.02, 0.0, 2.05)


def m_lazarus():
    d = 0.68
    yf = -d / 2
    for x in (-0.4, 0.4):
        for y in (-0.24, 0.24):
            cyl("dark", (x, y, 0.06), 0.04, 0.12, "Z", 10)
    box("paint", -0.49, 0.49, yf, -yf, 0.1, 0.92, 0.06, 3)
    box("chrome", -0.5, 0.5, yf - 0.01, -yf + 0.01, 0.9, 0.94, 0.012)
    box("paint", -0.505, 0.505, yf - 0.015, -yf + 0.015, 0.94, 1.0, 0.025)
    # Panneau central blanc, décapsuleur, bulles « glacé ».
    box("paint2", -0.17, 0.17, yf - 0.012, yf + 0.02, 0.18, 0.86, 0.015)
    box("chrome", 0.34, 0.42, yf - 0.03, yf + 0.01, 0.72, 0.84, 0.01)
    box("dark", 0.36, 0.4, yf - 0.034, yf, 0.75, 0.79)
    for x, z, r in ((-0.36, 0.74, 0.035), (-0.28, 0.62, 0.025), (-0.4, 0.5, 0.03), (-0.3, 0.3, 0.04),
                    (0.28, 0.5, 0.03), (0.38, 0.36, 0.025), (0.3, 0.22, 0.035)):
        o, i_ = circle(r, 16), circle(r * 0.72, 16)
        for k in range(16):
            j = (k + 1) % 16
            flat("paint2", [o[k], o[j], i_[j], i_[k]], x, z, 1.0, yf, depth=0.004)
    text("paint2", "GLACÉ", -0.34, 0.2, yf, 0.05, 0.16, shear=0.0, bold=0.0)
    # Fronton incliné éclairé à l'arrière du couvercle.
    tilt = math.radians(-22)
    prism_yz("lit_sign", [(0.0, 1.0), (0.34, 1.0), (0.34, 1.36), (0.14, 1.36)], -0.48, 0.48, 0.015)
    # Face avant du fronton : du point (0, 1,0) au point (0,14, 1,36).
    fy, fz = 0.07 - 0.001, 1.18
    text("lit_ink", "LAZARUS\nTONIC", 0.0, fz, fy - 0.004, 0.28, 0.82, shear=0.2, tilt=tilt)
    # Enseigne ronde sur un mât.
    cyl("chrome", (0.0, 0.26, 1.5), 0.03, 0.3, "Z", 12)
    round_sign("lazarus", 0.0, 1.84, 0.26, 0.23)
    col(-0.51, 0.51, yf - 0.02, -yf + 0.02, 0.0, 1.36)


def m_stride():
    plinth(0.84, 0.64)
    prism_xz("paint", arch(0.9, 0.07, 1.62), YF, -YF, 0.03)
    box("chrome", -0.465, 0.465, YF - 0.012, -YF + 0.012, 1.3, 1.34, 0.012)
    # Vitrine en arche éclairée.
    prism_xz("lit_sign", arch(0.78, 1.38, 1.62), YF - 0.012, YF + 0.02, 0.008)
    text("lit_ink", "STRIDE\nSODA", 0.0, 1.62, YF - 0.012, 0.36, 0.64, shear=0.22)
    # Pilastres chromés.
    for x in (-0.43, 0.43):
        cyl("chrome", (x, YF - 0.005, 0.7), 0.022, 1.2, "Z", 10)
    box("paint2", -0.24, 0.24, YF - 0.035, YF + 0.01, 0.26, 1.2, 0.025)
    box("chrome", -0.18, 0.18, YF - 0.05, YF - 0.03, 1.02, 1.14, 0.008)
    box("glass", -0.16, 0.16, YF - 0.056, YF - 0.04, 1.04, 1.12)
    coin_slot(0.12, 0.88, YF - 0.035)
    cyl("chrome", (0.19, YF - 0.05, 0.62), 0.014, 0.3, "Z", 10)
    flap(-0.04, 0.46, 0.16, 0.14, YF - 0.035)
    # Fleuron : petite enseigne ronde au sommet de l'arche.
    cyl("chrome", (0.0, 0.0, 2.1), 0.035, 0.08, "Z", 12)
    round_sign("stride", 0.0, 2.24, 0.0, 0.13, 0.05)
    col(-0.47, 0.47, YF - 0.02, -YF + 0.02, 0.0, 2.08)


def taper(w0, w1, z0, z1, off=0.0, zb=None, zt=None):
    """Trapèze vu de face (plus large en bas), éventuellement élargi de off et
    coupé entre zb et zt."""
    zb = z0 if zb is None else zb
    zt = z1 if zt is None else zt

    def hw(z):
        return (w0 + (w1 - w0) * (z - z0) / (z1 - z0)) / 2 + off
    return [(-hw(zb), zb), (hw(zb), zb), (hw(zt), zt), (-hw(zt), zt)]


def m_nova():
    plinth(0.92, 0.66)
    prism_xz("paint", taper(0.98, 0.8, 0.07, 1.76), YF, -YF, 0.03)
    for zb, zt in ((0.16, 0.26), (0.3, 0.34)):
        prism_xz("paint2", taper(0.98, 0.8, 0.07, 1.76, 0.012, zb, zt), YF - 0.012, -YF + 0.012, 0.004)
    # Bandeau éclairé du haut, légèrement en saillie.
    prism_xz("lit_sign", taper(0.98, 0.8, 0.07, 1.76, -0.03, 1.4, 1.72), YF - 0.015, YF + 0.02, 0.008)
    text("lit_ink", "NOVA FLOP", 0.0, 1.56, YF - 0.015, 0.18, 0.7, shear=0.2)
    # Grand hublot lumineux.
    cyl("lit_lamp", (0.0, YF - 0.01, 0.98), 0.2, 0.03, "Y", 32)
    ring_y("chrome", 0.0, 0.98, YF - 0.04, YF + 0.01, 0.19, 0.25, 32)
    emblem("nova", 0.0, 0.98, 0.32, YF - 0.025)
    coin_slot(0.3, 1.2, YF)
    flap(0.0, 0.56, 0.2, 0.12, YF)
    # Dôme de verre et antenne.
    cyl("chrome", (0.0, 0.0, 1.785), 0.33, 0.05, "Z", 28)
    sphere("lit_lamp", (0.0, 0.0, 1.81), 0.29, half=True, segs=24)
    cyl("chrome", (0.0, 0.0, 2.14), 0.012, 0.12, "Z", 8)
    sphere("chrome", (0.0, 0.0, 2.22), 0.03, segs=10)
    col(-0.5, 0.5, YF - 0.03, -YF + 0.02, 0.0, 2.1)


def m_deadeye():
    plinth(0.86, 0.64)
    # Caisse à épaule chanfreinée (profil vu de côté) puis fronton en retrait.
    prism_yz("paint", [(YF, 0.07), (-YF, 0.07), (-YF, 1.56), (YF + 0.16, 1.56), (YF, 1.44)], -0.45, 0.45, 0.03)
    box("paint", -0.43, 0.43, YF + 0.16, -YF, 1.56, 2.14, 0.03)
    box("chrome", -0.445, 0.445, YF + 0.145, -YF + 0.012, 2.12, 2.16, 0.01)
    box("lit_sign", -0.39, 0.39, YF + 0.148, YF + 0.18, 1.62, 2.08, 0.008)
    text("lit_ink", "DEADEYE\nDRAM", 0.0, 1.85, YF + 0.148, 0.34, 0.66, shear=0.12)
    # Grande cible lumineuse.
    cyl("lit_lamp", (0.0, YF - 0.01, 1.08), 0.2, 0.03, "Y", 32)
    ring_y("chrome", 0.0, 1.08, YF - 0.035, YF + 0.01, 0.19, 0.24, 32)
    emblem("deadeye", 0.0, 1.08, 0.36, YF - 0.025)
    box("paint2", -0.26, 0.26, YF - 0.03, YF + 0.01, 0.22, 0.74, 0.02)
    coin_slot(0.14, 0.62, YF - 0.03)
    flap(-0.06, 0.42, 0.18, 0.14, YF - 0.03)
    box("dark", -0.43, 0.43, YF - 0.012, YF + 0.01, 1.3, 1.34)
    # Lampe de signalisation sur le fronton.
    cyl("chrome", (0.0, 0.1, 2.18), 0.07, 0.04, "Z", 16)
    cyl("lit_lamp", (0.0, 0.1, 2.25), 0.055, 0.1, "Z", 16)
    sphere("chrome", (0.0, 0.1, 2.31), 0.03, segs=10)
    col(-0.47, 0.47, YF - 0.02, -YF + 0.02, 0.0, 2.17)


BUILDERS = {"titan": m_titan, "rapid": m_rapid, "twin": m_twin, "lazarus": m_lazarus,
            "stride": m_stride, "nova": m_nova, "deadeye": m_deadeye}


# ------------------------------------------------------------------ scène
def material(perk, name, suffix=""):
    # Nom exporté = clé lue par PerkMachine ; suffixe pour l'aperçu seulement.
    key = name + suffix
    m = bpy.data.materials.get(key) or bpy.data.materials.new(key)
    c = PERKS[perk].get(name, COMMON.get(name, (0.5, 0.5, 0.5)))
    rough, metal = MAT_PBR.get(name, (0.5, 0.0))
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = srgb(c)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if name.startswith("lit_"):
        # Aperçu « courant rétabli » (Godot pilote l'émission lui-même).
        p.inputs["Emission Color"].default_value = srgb(c)
        p.inputs["Emission Strength"].default_value = {"lit_sign": 1.6, "lit_ink": 0.6, "lit_lamp": 3.0}[name]
    m.diffuse_color = srgb(c)
    return m


def build_objects(perk, offset=(0.0, 0.0, 0.0), suffix=""):
    reset()
    BUILDERS[perk]()
    obs = []
    for name, bm in sorted(_parts.items()):
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0002)
        me = bpy.data.meshes.new(name + suffix)
        bm.to_mesh(me)
        me.materials.append(material(perk, name, suffix))
        for poly in me.polygons:
            poly.use_smooth = False
        ob = bpy.data.objects.new(name + suffix, me)
        ob.location = offset
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
    for i, ((x0, x1), (y0, y1), (z0, z1)) in enumerate(_cols):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.transform(bm, matrix=Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
                            @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1.0)), verts=bm.verts[:])
        me = bpy.data.meshes.new("col_%d%s" % (i, suffix))
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("col_%d%s" % (i, suffix), me)
        ob.location = offset
        ob.hide_render = True
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
    for p in _parts.values():
        p.free()
    _parts.clear()
    return obs


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def export(perk):
    clear_scene()
    obs = build_objects(perk)
    for ob in obs:
        ob.select_set(True)
    out = os.path.join(OUT_DIR, perk + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    tris = 0
    for ob in obs:
        if not ob.name.startswith("col_"):
            tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("[perk_machines] %s : %d objets, %d triangles -> %s" % (perk, len(obs), tris, out))


def preview(perks):
    clear_scene()
    sc = bpy.context.scene
    step = 1.35
    x0 = -step * (len(perks) - 1) / 2
    for i, perk in enumerate(perks):
        build_objects(perk, (x0 + i * step, 0.0, 0.0), "_" + perk)
    # Sol et mur du fond.
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0.45, 5), rotation=(math.pi / 2, 0, 0))
    wm = bpy.data.materials.new("mur")
    wm.use_nodes = True
    wm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.05, 0.045, 1)
    for ob in sc.objects:
        if ob.name.startswith("Plane"):
            ob.data.materials.append(wm)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.02, 0.025, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = world
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 900
    key.data.size = 6
    key.location = (-2, -6, 4.5)
    key.rotation_euler = (math.radians(55), 0, math.radians(-18))
    sc.collection.objects.link(key)
    sc.render.resolution_x, sc.render.resolution_y = 1600, 700
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    span = step * len(perks)
    views = {
        "perks_front.png": ((0, -span * 1.25, 1.3), (math.radians(88), 0, 0), 40),
        "perks_three_quarter.png": ((-span * 0.75, -span * 1.0, 2.4), (math.radians(83), 0, math.radians(-35)), 40),
    }
    for fname, (loc, rot, lens) in views.items():
        cam.location = loc
        cam.rotation_euler = rot
        cam.data.lens = lens
        sc.render.filepath = os.path.join(PREVIEW_DIR, fname)
        bpy.ops.render.render(write_still=True)
        print("[perk_machines] aperçu -> %s" % sc.render.filepath)
    # Gros plans (deux par image) pour les détails.
    sc.render.resolution_x, sc.render.resolution_y = 900, 900
    target = bpy.data.objects.new("cible", None)
    sc.collection.objects.link(target)
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    for i, perk in enumerate(perks):
        x = x0 + i * step
        target.location = (x, 0.0, 1.15)
        cam.location = (x - 1.2, -2.8, 1.75)
        cam.data.lens = 32
        sc.render.filepath = os.path.join(PREVIEW_DIR, "perk_%s.png" % perk)
        bpy.ops.render.render(write_still=True)


perks = ONLY or list(BUILDERS.keys())
os.makedirs(OUT_DIR, exist_ok=True)
for perk in perks:
    export(perk)
if PREVIEW_DIR:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    preview(perks)
