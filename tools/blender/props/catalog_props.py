# Décors NON CUBIQUES du catalogue de l'éditeur de cartes (fauteuils, gravats,
# lustre, applique, bureau…), en cours de remplacement par des modèles en cubes de 5 cm
# (tools/blender/voxel_props/, docs/VOXEL_DECOR_PLAN.md) : modèles low poly
# ORIGINAUX, sans aucun asset ni logo d'Activision. Hérités de l'ancienne
# carte KINO (retirée) ; seuls les modèles encore utilisés par le jeu et
# l'éditeur restent ici. Sans fenêtre :
#
#   sh tools/blender.sh tools/blender/props/catalog_props.py <dossier .glb> [dossier aperçus] [noms...]
#
# Sans liste de noms : tous les modèles de BUILDERS. Avec un dossier
# d'aperçus : un rendu PNG de trois quarts par modèle (lumière neutre).
#
# Conventions (lues par le chargeur du jeu) :
#   - Blender Z en haut, mètres ; origine au centre de l'empreinte, au sol
#     (sauf mention contraire dans le modèle) ; face avant vers -Y (+Z Godot).
#   - un objet par matériau et par type : <mat>__<modèle>__solid (projette
#     une ombre) ou <mat>__<modèle>__ns (petits détails, sans ombre) ; le
#     matériau Blender porte la même clé <mat> (le jeu la remplace par son
#     shader procédural).
#   - AUCUN objet de collision dans le .glb : les collisions sont des boîtes
#     écrites à côté, dans <modèle>.collision.json, en repère Godot local
#     (Y en haut, godot = (bx, bz, -by)) :
#       {"boxes": [{"center": [x, y, z], "size": [sx, sy, sz], "yaw": rad, "barrier": false}]}
#     barrier = true : bloque joueurs et zombies mais pas les balles.
import bpy, bmesh, json, math, os, random, sys
from contextlib import contextmanager
from mathutils import Vector, Matrix, Euler

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(args[0] if args else "assets/models/props")
PREVIEW_DIR = os.path.abspath(args[1]) if len(args) > 1 else ""
ONLY = args[2:]

# Couleurs d'aperçu (linéaires, reprises de WorldLook.SURFACES quand la clé
# y existe), rugosité, métal, émission.
MATS = {
    "velvet": ((0.46, 0.035, 0.045), 0.8, 0.0, 0.0),
    "carpet_red": ((0.3, 0.035, 0.04), 0.9, 0.0, 0.0),
    "brass": ((0.5, 0.36, 0.13), 0.35, 0.85, 0.0),
    "dark_wood": ((0.13, 0.07, 0.035), 0.6, 0.0, 0.0),
    "wood": ((0.24, 0.15, 0.09), 0.8, 0.0, 0.0),
    "stage_wood": ((0.27, 0.16, 0.08), 0.7, 0.0, 0.0),
    "parquet": ((0.25, 0.15, 0.08), 0.6, 0.0, 0.0),
    "crate": ((0.3, 0.2, 0.11), 0.9, 0.0, 0.0),
    "steel": ((0.25, 0.26, 0.27), 0.5, 0.6, 0.0),
    "metal": ((0.2, 0.21, 0.22), 0.6, 0.5, 0.0),
    "door": ((0.22, 0.23, 0.22), 0.55, 0.6, 0.0),
    "barrel": ((0.28, 0.08, 0.05), 0.6, 0.4, 0.0),
    "concrete": ((0.25, 0.24, 0.22), 0.95, 0.0, 0.0),
    "concrete_dark": ((0.17, 0.17, 0.16), 0.95, 0.0, 0.0),
    "stone": ((0.12, 0.1, 0.1), 0.9, 0.0, 0.0),
    "marble": ((0.46, 0.41, 0.34), 0.4, 0.0, 0.0),
    "fabric": ((0.36, 0.33, 0.27), 1.0, 0.0, 0.0),
    "wall_theater": ((0.3, 0.05, 0.06), 0.85, 0.0, 0.0),
    "wall_lobby": ((0.34, 0.25, 0.14), 0.85, 0.0, 0.0),
    "ceiling_theater": ((0.16, 0.1, 0.07), 1.0, 0.0, 0.0),
    "cobble": ((0.2, 0.2, 0.21), 0.9, 0.0, 0.0),
    "plank": ((0.3, 0.2, 0.12), 0.9, 0.0, 0.0),
    "glass": ((0.6, 0.7, 0.72), 0.05, 0.0, 0.0),
    "bulb": ((1.0, 0.75, 0.42), 0.3, 0.0, 4.0),
    "glow_blue": ((0.25, 0.5, 1.0), 0.3, 0.0, 6.0),
    "crystal": ((0.8, 0.86, 0.92), 0.08, 0.0, 0.35),
    "chalk": ((0.8, 0.78, 0.72), 0.9, 0.0, 0.0),
    "paper": ((0.62, 0.58, 0.48), 0.9, 0.0, 0.0),
    "paint_teal": ((0.22, 0.45, 0.43), 0.5, 0.1, 0.0),
    "paint_red": ((0.5, 0.06, 0.05), 0.5, 0.1, 0.0),
    "rubber": ((0.02, 0.02, 0.02), 0.8, 0.0, 0.0),
    "paint_blue": ((0.08, 0.18, 0.45), 0.5, 0.3, 0.0),
    "cable_blue": ((0.03, 0.05, 0.15), 0.6, 0.0, 0.0),
    "plaster_theater": ((0.33, 0.34, 0.30), 0.9, 0.0, 0.0),
    "vault_theater": ((0.24, 0.25, 0.23), 0.95, 0.0, 0.0),
    "carpet_theater": ((0.15, 0.16, 0.17), 0.9, 0.0, 0.0),
}

# ------------------------------------------------------------------ état
_parts = {}          # (matériau, type) -> bmesh fusionné
_boxes = []          # boîtes de collision (repère Blender) : (centre, taille, yaw, barrier)
_M = [Matrix.Identity(4)]
_KIND = ["solid"]
I4 = Matrix.Identity(4)


def reset():
    global _parts, _boxes
    for bm in _parts.values():
        bm.free()
    _parts = {}
    _boxes = []
    _M[:] = [Matrix.Identity(4)]
    _KIND[:] = ["solid"]


@contextmanager
def xf(m):
    """Transformation locale (empilée) appliquée à toutes les pièces."""
    _M.append(_M[-1] @ m)
    try:
        yield
    finally:
        _M.pop()


@contextmanager
def ns():
    """Pièces sans ombre (petits détails)."""
    _KIND.append("ns")
    try:
        yield
    finally:
        _KIND.pop()


@contextmanager


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def R(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(x, y, z):
    return Matrix.Diagonal((x, y, z, 1.0))


def about(p, m):
    """Transformation m autour du point p."""
    return T(*p) @ m @ T(-p[0], -p[1], -p[2])


def add(mat, bm, bevel=0.0, seg=1, recalc=True, smooth=False, kind=None):
    """Ajoute une pièce (bmesh) au maillage du matériau (repère courant)."""
    assert mat in MATS, mat
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=seg,
                        affect="EDGES", profile=0.5, clamp_overlap=True)
    if smooth:
        for f in bm.faces:
            f.smooth = True
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    m = _M[-1]
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    if m.determinant() < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("tmp")
    bm.to_mesh(me)
    bm.free()
    dst = _parts.setdefault((mat, kind or _KIND[-1]), bmesh.new())
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)


def colbox(c, size, yaw=0.0, barrier=False):
    """Boîte de collision (centre et taille Blender, rotation autour de Z en
    radians), dans le repère courant (qui ne doit contenir qu'un lacet)."""
    m = _M[-1]
    cw = m @ Vector(c)
    ax = m.to_3x3() @ Vector((1, 0, 0))
    _boxes.append((cw, tuple(size), yaw + math.atan2(ax.y, ax.x), barrier))


def colbox_mm(x0, x1, y0, y1, z0, z1, barrier=False):
    colbox(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), 0.0, barrier)


# ------------------------------------------------------------------ primitives
def prism(mat, pts, plane, a0, a1, **kw):
    """Profil 2D extrudé : plane "xz" (profil (x, z), profondeur y), "yz"
    (profil (y, z), largeur x) ou "xy" (profil (x, y), hauteur z)."""
    def P(u, v, w):
        if plane == "xz":
            return (u, w, v)
        if plane == "yz":
            return (w, u, v)
        return (u, v, w)
    bm = bmesh.new()
    a = [bm.verts.new(P(u, v, a0)) for u, v in pts]
    b = [bm.verts.new(P(u, v, a1)) for u, v in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    add(mat, bm, **kw)


def box(mat, x0, x1, y0, y1, z0, z1, **kw):
    prism(mat, [(x0, z0), (x1, z0), (x1, z1), (x0, z1)], "xz", y0, y1, **kw)


def basis(p0, p1, up=(0, 0, 1)):
    """Matrice : X local de p0 vers p1, Z local proche de up, centre au milieu."""
    p0, p1 = Vector(p0), Vector(p1)
    x = (p1 - p0).normalized()
    u = Vector(up)
    if abs(x.dot(u.normalized())) > 0.98:
        u = Vector((0, 1, 0)) if abs(x.y) < 0.9 else Vector((1, 0, 0))
    z = (u - x * u.dot(x)).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    return m, (p1 - p0).length


def beam(mat, p0, p1, w, h, up=(0, 0, 1), **kw):
    """Poutre de section w x h entre deux points."""
    m, L = basis(p0, p1, up)
    with xf(m):
        box(mat, -L / 2, L / 2, -w / 2, w / 2, -h / 2, h / 2, **kw)


def cyl(mat, c, r, h, axis="Z", segs=12, r2=None, smooth=True, **kw):
    """Cylindre (ou tronc de cône si r2) centré en c, de longueur h."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    if smooth:
        for f in bm.faces:
            f.smooth = abs(f.normal.z) < 0.98
    rot = {"Z": I4, "Y": R(90, "X"), "X": R(90, "Y")}[axis]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot, verts=bm.verts[:])
    add(mat, bm, **kw)


def rod(mat, p0, p1, r, segs=6, **kw):
    m, L = basis(p0, p1)
    with xf(m @ R(90, "Y")):
        cyl(mat, (0, 0, 0), r, L, "Z", segs, **kw)


def sphere(mat, c, r, segs=12, rings=6, scale=(1, 1, 1), smooth=True, **kw):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ S(*scale), verts=bm.verts[:])
    add(mat, bm, smooth=smooth, **kw)


def octa(mat, c, r, h):
    """Pendeloque de cristal (octaèdre allongé, pointe en bas)."""
    bm = bmesh.new()
    top = bm.verts.new((c[0], c[1], c[2] + h * 0.35))
    bot = bm.verts.new((c[0], c[1], c[2] - h * 0.65))
    ring = [bm.verts.new((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r, c[2])) for a in
            (0, math.pi / 2, math.pi, 1.5 * math.pi)]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((top, ring[i], ring[j]))
        bm.faces.new((bot, ring[j], ring[i]))
    add(mat, bm)


def torus(mat, c, R_, r, useg=24, vseg=4, scale=(1, 1, 1), **kw):
    """Tore d'axe Z (anneau de laiton, maillon de chaîne)."""
    bm = bmesh.new()
    vs = []
    for i in range(useg):
        a = 2 * math.pi * i / useg
        row = []
        for k in range(vseg):
            b = 2 * math.pi * k / vseg
            rr = R_ + math.cos(b) * r
            row.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, math.sin(b) * r)))
        vs.append(row)
    for i in range(useg):
        for k in range(vseg):
            f = bm.faces.new((vs[i][k], vs[(i + 1) % useg][k], vs[(i + 1) % useg][(k + 1) % vseg], vs[i][(k + 1) % vseg]))
            f.smooth = True
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ S(*scale), verts=bm.verts[:])
    add(mat, bm, **kw)


def lathe(mat, prof, segs=12, loop=False, smooth=False, **kw):
    """Profil (r, z) tourné autour de Z. loop : profil fermé (anneau) ; sinon
    le solide est refermé sur l'axe aux deux bouts. smooth = "sides" : seules
    les bandes plus hautes que larges sont lissées (flancs), les autres restent
    à facettes (fonds, couvercles)."""
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        if r < 1e-5 and not loop:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((math.cos(2 * math.pi * i / segs) * r,
                                        math.sin(2 * math.pi * i / segs) * r, z)) for i in range(segs)])
    n = len(rings)
    for k in range(n if loop else n - 1):
        A, B = rings[k], rings[(k + 1) % n]
        for i in range(segs):
            j = (i + 1) % segs
            if len(A) == 1 and len(B) == 1:
                continue
            if len(A) == 1:
                f = bm.faces.new((A[0], B[j], B[i]))
            elif len(B) == 1:
                f = bm.faces.new((A[i], A[j], B[0]))
            else:
                f = bm.faces.new((A[i], A[j], B[j], B[i]))
            if smooth == "sides":
                (r0, z0), (r1, z1) = prof[k], prof[(k + 1) % n]
                f.smooth = abs(z1 - z0) > abs(r1 - r0)
            else:
                f.smooth = smooth
    if not loop:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    add(mat, bm, **kw)


def tube(mat, pts, r, segs=6, caps=True, closed=False, smooth=True, **kw):
    """Tube le long d'une polyligne (câbles, bras, chaînes de perles) ; r :
    rayon ou liste de rayons par point."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    rs = list(r) if isinstance(r, (list, tuple)) else [r] * n
    tans = []
    for i in range(n):
        if closed:
            t = pts[(i + 1) % n] - pts[i - 1]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        tans.append(t.normalized())
    up = Vector((0, 0, 1)) if abs(tans[0].z) < 0.9 else Vector((1, 0, 0))
    nrm = tans[0].cross(up).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        t = tans[i]
        nrm = nrm - t * nrm.dot(t)
        if nrm.length < 1e-6:
            nrm = t.orthogonal()
        nrm.normalize()
        b = t.cross(nrm)
        rings.append([bm.verts.new(pts[i] + (nrm * math.cos(2 * math.pi * k / segs) + b * math.sin(2 * math.pi * k / segs)) * rs[i])
                      for k in range(segs)])
    for i in range(n if closed else n - 1):
        A, B = rings[i], rings[(i + 1) % n]
        for k in range(segs):
            f = bm.faces.new((A[k], A[(k + 1) % segs], B[(k + 1) % segs], B[k]))
            f.smooth = smooth
    if caps and not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    add(mat, bm, recalc=caps or closed, **kw)


def hull(mat, pts, **kw):
    """Enveloppe convexe d'un nuage de points (morceaux de gravats)."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    res = bmesh.ops.convex_hull(bm, input=vs)
    loose = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    add(mat, bm, **kw)


def chunk(mat, c, s, rng, n=8):
    """Morceau irrégulier (plâtre, béton) de taille s = (sx, sy, sz)."""
    rot = Euler((rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3))).to_matrix()
    pts = []
    for _ in range(n):
        v = Vector((rng.uniform(-0.5, 0.5) * s[0], rng.uniform(-0.5, 0.5) * s[1], rng.uniform(-0.5, 0.5) * s[2]))
        pts.append(Vector(c) + rot @ v)
    hull(mat, pts)


def sheet(mat, F, Bk, smooth=True, **kw):
    """Étoffe épaisse : grille de points avant F[ligne][colonne] et arrière
    Bk (même forme), refermée sur les bords (rideaux, bannières)."""
    bm = bmesh.new()
    fv = [[bm.verts.new(p) for p in row] for row in F]
    bv = [[bm.verts.new(p) for p in row] for row in Bk]
    nr, nc = len(F), len(F[0])
    for r in range(nr - 1):
        for c in range(nc - 1):
            f = bm.faces.new((fv[r][c], fv[r][c + 1], fv[r + 1][c + 1], fv[r + 1][c]))
            f.smooth = smooth
            f = bm.faces.new((bv[r][c], bv[r + 1][c], bv[r + 1][c + 1], bv[r][c + 1]))
            f.smooth = smooth
    for c in range(nc - 1):
        bm.faces.new((fv[0][c + 1], fv[0][c], bv[0][c], bv[0][c + 1]))
        bm.faces.new((fv[-1][c], fv[-1][c + 1], bv[-1][c + 1], bv[-1][c]))
    for r in range(nr - 1):
        bm.faces.new((fv[r][0], fv[r + 1][0], bv[r + 1][0], bv[r][0]))
        bm.faces.new((fv[r + 1][-1], fv[r][-1], bv[r][-1], bv[r + 1][-1]))
    add(mat, bm, **kw)


def circle(r, n=24, cx=0.0, cz=0.0, a0=0.0):
    return [(cx + math.cos(a0 + 2 * math.pi * i / n) * r, cz + math.sin(a0 + 2 * math.pi * i / n) * r) for i in range(n)]


def rounded_poly(corners, cut, n=4):
    """Polygone aux coins arrondis (courbe de Bézier quadratique par coin)."""
    out = []
    m = len(corners)
    for i in range(m):
        p, a, b = Vector(corners[i]), Vector(corners[i - 1]), Vector(corners[(i + 1) % m])
        p0 = p + (a - p).normalized() * cut
        p2 = p + (b - p).normalized() * cut
        for k in range(n + 1):
            t = k / n
            q = p0 * (1 - t) ** 2 + p * 2 * t * (1 - t) + p2 * t * t
            out.append((q.x, q.y))
    return out


def em_star(points=8, r1=0.48, r2=0.2):
    pts = []
    for i in range(points * 2):
        t = math.pi * i / points + math.pi / 2
        r = r1 if i % 2 == 0 else r2
        pts.append((math.cos(t) * r, math.sin(t) * r))
    return pts


def flat(mat, pts, cx, cz, y_front, size=1.0, depth=0.006):
    """Motif plat (u, v) posé face à -Y sur le plan y = y_front."""
    prism(mat, [(cx + u * size, cz + v * size) for u, v in pts], "xz", y_front - depth, y_front + 0.001)


def bezier(p0, p1, p2, p3, n):
    p0, p1, p2, p3 = (Vector(p) for p in (p0, p1, p2, p3))
    out = []
    for i in range(n):
        t = i / (n - 1)
        u = 1 - t
        out.append(p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3)
    return out


def sag(a, b, s, n):
    """Courbe pendante (parabole) de a à b, flèche s."""
    a, b = Vector(a), Vector(b)
    return [a.lerp(b, i / (n - 1)) - Vector((0, 0, s * 4 * (i / (n - 1)) * (1 - i / (n - 1)))) for i in range(n)]


def deform(fn, mats=None):
    """Applique fn(Vector) -> Vector à tous les sommets déjà construits."""
    for (mat, kind), bm in _parts.items():
        if mats and mat not in mats:
            continue
        for v in bm.verts:
            v.co = fn(v.co.copy())


def bounds(keys=None):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for key, bm in _parts.items():
        if keys and key not in keys:
            continue
        for v in bm.verts:
            lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
            hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    return lo, hi


# ------------------------------------------------------------------ motifs
def reel_emblem(cx, cz, y_front, size, light="velvet", dark="brass", disc=False):
    """Emblème ORIGINAL : bobine de film stylisée dorée (disque, cinq trous, moyeu)
    et amorce de pellicule. Jamais de disque blanc sur fond rouge (trop proche de la
    mise en page d'un drapeau politique) : or sur rouge, sans disque par défaut."""
    if disc:
        flat(light, circle(0.5, 32), cx, cz, y_front, size, 0.004)
    flat(dark, circle(0.36, 28), cx, cz, y_front - 0.004, size, 0.004)
    for k in range(5):
        a = math.pi / 2 + 2 * math.pi * k / 5
        flat(light, circle(0.085, 12, math.cos(a) * 0.2, math.sin(a) * 0.2), cx, cz, y_front - 0.008, size, 0.004)
    flat(light, circle(0.045, 10), cx, cz, y_front - 0.008, size, 0.004)
    # Amorce de pellicule qui se déroule en bas à droite (perforations).
    strip = [(0.2, -0.3), (0.3, -0.24), (0.47, -0.4), (0.5, -0.47), (0.36, -0.45), (0.26, -0.37)]
    flat(dark, strip, cx, cz, y_front - 0.004, size, 0.004)


def reel(c, r=0.175, thick=0.05, orient=I4, detail=True, film=0.72, mat="steel"):
    """Bobine de film (axe Z local) : joues ajourées, pellicule enroulée."""
    with xf(T(*c) @ orient):
        if detail:
            for zc in (-thick / 2 + 0.005, thick / 2 - 0.005):
                lathe(mat, [(r - 0.02, zc - 0.004), (r, zc - 0.004), (r, zc + 0.004), (r - 0.02, zc + 0.004)], 16, loop=True)
                cyl(mat, (0, 0, zc), r * 0.26, 0.008, "Z", 10)
                for k in range(5):
                    a = 2 * math.pi * k / 5
                    with xf(R(math.degrees(a), "Z")):
                        box(mat, r * 0.22, r - 0.015, -r * 0.07, r * 0.07, zc - 0.004, zc + 0.004)
            cyl("rubber", (0, 0, 0), r * film, thick - 0.018, "Z", 14)
            cyl(mat, (0, 0, 0), r * 0.1, thick, "Z", 8)
        else:
            cyl(mat, (0, 0, 0), r, thick, "Z", 10, smooth=False)
            # Trous et moyeu : simples faces sombres posées sur chaque joue.
            bm = bmesh.new()
            for sgn in (-1, 1):
                zc = sgn * (thick / 2 + 0.002)
                discs = [(0.0, 0.0, r * 0.1, 6)] + [(math.cos(a) * r * 0.55, math.sin(a) * r * 0.55, r * 0.22, 6)
                                                   for a in [2 * math.pi * k / 3 + 0.4 for k in range(3)]]
                for x, y, rr, n in discs:
                    vs = [bm.verts.new((x + math.cos(2 * math.pi * i / n) * rr, y + math.sin(2 * math.pi * i / n) * rr, zc))
                          for i in range(n)]
                    bm.faces.new(vs if sgn > 0 else list(reversed(vs)))
            add("rubber", bm, recalc=False)


# ------------------------------------------------------------------ fauteuils
def seat_geo(back="full", arm_broken=None, tilt=0.0, simple=False, arms=True):
    """Fauteuil de théâtre : flancs en fonte, accoudoirs en bois sombre,
    coussin et dossier de velours rouge. back : full, torn, none."""
    bv = 0.0 if simple else 0.022
    prof = [(-0.26, 0.0), (0.26, 0.0), (0.25, 0.05), (0.13, 0.11), (0.17, 0.6), (0.13, 0.63),
            (-0.2, 0.63), (-0.23, 0.58), (-0.19, 0.11), (-0.25, 0.05)]
    if simple:
        prof = [(-0.24, 0.0), (0.2, 0.0), (0.16, 0.6), (-0.2, 0.62)]
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.275, sx * 0.24))
        prism("steel", prof, "yz", x0, x1)
        if not arms:
            continue
        ax0, ax1 = sorted((sx * 0.278, sx * 0.215))
        side = "L" if sx < 0 else "R"
        if arm_broken == side:
            # Accoudoir cassé : moitié avant pendante, écharde de bois.
            box("dark_wood", ax0, ax1, 0.02, 0.2, 0.62, 0.66, bevel=bv * 0.5)
            with xf(about((0, 0.02, 0.64), R(38, "X"))):
                prism("dark_wood", [(-0.2, 0.62), (0.02, 0.62), (0.0, 0.66), (-0.12, 0.665), (-0.24, 0.655)], "yz", ax0, ax1)
        else:
            box("dark_wood", ax0, ax1, -0.25, 0.2, 0.62, 0.665, bevel=bv * 0.5)
    with xf(about((0, 0.1, 0.42), R(tilt, "X"))):
        box("velvet", -0.225, 0.225, -0.27, 0.1, 0.4, 0.5, bevel=bv)
        box("dark_wood", -0.22, 0.22, -0.24, 0.08, 0.36, 0.4)
    # Dossier haut (1,1 m) en bois sombre au sommet chantourné « en chapeau
    # de gendarme », garniture de velours rouge usé.
    with xf(about((0, 0.13, 0.47), R(-10, "X"))):
        if back == "full":
            prism("dark_wood", seat_back_profile(0.24, 0.47, 0.94, 1.12, 5 if simple else 8), "xz", 0.15, 0.2)
            prism("velvet", seat_back_profile(0.2, 0.52, 0.9, 1.04, 4 if simple else 7), "xz", 0.1 if simple else 0.105, 0.15)
        elif back == "torn":
            prism("dark_wood", [(-0.24, 0.47), (0.24, 0.47), (0.24, 0.66), (0.15, 0.76), (0.08, 0.68), (0.0, 0.84),
                                (-0.1, 0.72), (-0.17, 0.8), (-0.24, 0.64)], "xz", 0.15, 0.2)
            prism("velvet", [(-0.2, 0.52), (0.2, 0.52), (0.2, 0.62), (0.12, 0.7), (0.05, 0.6), (-0.06, 0.68),
                             (-0.14, 0.6), (-0.2, 0.66)], "xz", 0.105, 0.15)
            chunk("fabric", (0.02, 0.11, 0.66), (0.14, 0.08, 0.1), random.Random(3))
        else:
            box("steel", -0.2, -0.16, 0.16, 0.2, 0.44, 0.56)
            box("steel", 0.16, 0.2, 0.16, 0.2, 0.44, 0.56)


def seat_back_profile(hw, z0, zs, zt, n):
    """Profil (x, z) du dossier : flancs droits jusqu'à zs, puis sommet en
    doucine qui monte vers le milieu (zt)."""
    pts = [(-hw, z0), (hw, z0)]
    for i in range(n + 1):
        u = 1 - i / n                        # 1 au bord droit, 0 au milieu
        pts.append((hw * u, zs + (zt - zs) * (1 - u * u * (3 - 2 * u)) ** 0.8))
    for i in range(1, n + 1):
        u = i / n
        pts.append((-hw * u, zs + (zt - zs) * (1 - u * u * (3 - 2 * u)) ** 0.8))
    return pts


def m_seat():
    seat_geo()


def m_seat_broken_b():
    # Renversé sur le dos, sans dossier, accoudoir gauche cassé ; recentré.
    with xf(R(12, "Z") @ about((0, 0.28, 0), R(-78, "X"))):
        seat_geo(back="full", arm_broken="L", tilt=8)
    lo, hi = bounds()
    c = (lo + hi) / 2
    deform(lambda v: v - Vector((c.x, c.y, lo.z)))


# ------------------------------------------------------------------ gravats
def plank_jag(mat, p0, p1, w, t, rng, up=(0, 0, 1)):
    """Planche aux bouts cassés (dents) entre deux points."""
    m, L = basis(p0, p1, up)
    h = L / 2
    j = [rng.uniform(0.02, 0.12) for _ in range(4)]
    pts = [(-h + j[0], -w / 2), (h - j[1], -w / 2), (h, -w * 0.15), (h - 0.05, w * 0.1), (h - j[2] * 0.3, w / 2),
           (-h, w / 2), (-h + 0.06, w * 0.05), (-h + j[3] * 0.4, -w * 0.3)]
    with xf(m):
        prism(mat, pts, "xy", -t / 2, t / 2)


def heap(a, b, H, seed, peaks, n_chunks, n_planks, n_seats, n_slabs, nx=18, ny=14, square=False, n_beams=1,
         n_backs=0, slab_size=1.0):
    """Tas de gravats sur une empreinte 2a x 2b (elliptique, ou presque
    rectangulaire si square) ; peaks : bosses (x, y, sx, sy, poids)."""
    rng = random.Random(seed)

    def base(x, y):
        if square:
            d2 = ((x / a) ** 4 + (y / b) ** 4) ** 0.5
        else:
            d2 = (x / a) ** 2 + (y / b) ** 2
        if d2 >= 1.0:
            return 0.0
        v = 0.0
        for px, py, sx, sy, w in peaks:
            v = max(v, w * math.exp(-(((x - px) / sx) ** 2 + ((y - py) / sy) ** 2)))
        return v * (1.0 - d2) ** 0.55

    mx = max(base(-a + 2 * a * i / 60, -b + 2 * b * j / 60) for i in range(61) for j in range(61))
    k = H * 0.84 / mx

    def h(x, y):
        v = base(x, y)
        if v <= 0:
            return 0.0
        n = 1.0 + 0.07 * math.sin(3.1 * x + 1.7 * y + seed) + 0.06 * math.sin(-2.3 * x + 4.1 * y + 2 * seed)
        return v * k * n

    # Tertre : grille déformée (faces vers le haut), bords sous le sol.
    bm = bmesh.new()
    g = []
    for i in range(nx + 1):
        row = []
        for j in range(ny + 1):
            x = -a + 2 * a * i / nx + (rng.uniform(-0.3, 0.3) * a / nx if 0 < i < nx else 0)
            y = -b + 2 * b * j / ny + (rng.uniform(-0.3, 0.3) * b / ny if 0 < j < ny else 0)
            row.append(bm.verts.new((x, y, h(x, y) - 0.03)))
        g.append(row)
    for i in range(nx):
        for j in range(ny):
            q = (g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1])
            if max(v.co.z for v in q) > 0.0:
                bm.faces.new(q)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    add("concrete_dark", bm, recalc=False)

    def spot(dmax):
        while True:
            x, y = rng.uniform(-a, a), rng.uniform(-b, b)
            d2 = ((x / a) ** 4 + (y / b) ** 4) ** 0.5 if square else (x / a) ** 2 + (y / b) ** 2
            if d2 < dmax * dmax:
                return x, y

    mats = ["concrete"] * 6 + ["stone"] * 2 + ["wall_theater"] * 2 + ["ceiling_theater"]
    for _ in range(int(n_chunks * 1.8)):
        x, y = spot(0.93)
        z = h(x, y)
        s = rng.uniform(0.16, 0.62) * (0.5 + 0.8 * z / H)
        chunk(rng.choice(mats), (x, y, z + s * 0.12), (s * rng.uniform(0.8, 1.6), s, s * rng.uniform(0.5, 1.0)), rng)
    # Plaques de plâtre peint (morceaux de plafond) posées de biais.
    for _ in range(n_slabs):
        x, y = spot(0.75)
        z = h(x, y)
        with xf(T(x, y, z + 0.02) @ R(rng.uniform(0, 360), "Z") @ R(rng.uniform(-35, 35), "X") @ R(rng.uniform(-25, 25), "Y") @ S(slab_size, slab_size, 1.0)):
            prism(rng.choice(["ceiling_theater", "wall_theater"]),
                  [(-0.45, -0.3), (0.4, -0.35), (0.5, 0.05), (0.3, 0.32), (-0.2, 0.36), (-0.5, 0.1)], "xy", -0.04, 0.04)
    # Planches et lattes.
    for _ in range(n_planks):
        x, y = spot(0.8)
        L = rng.uniform(0.9, 2.2) * min(1.0, a / 1.8)
        # Posée à peu près le long des courbes de niveau (pas de planche
        # dressée au sommet).
        gx = h(x + 0.05, y) - h(x - 0.05, y)
        gy = h(x, y + 0.05) - h(x, y - 0.05)
        yaw = math.atan2(gx, -gy) + rng.uniform(-0.5, 0.5)
        d = Vector((math.cos(yaw), math.sin(yaw), 0)) * L / 2
        e1, e2 = Vector((x, y, 0)) - d, Vector((x, y, 0)) + d
        z1, z2 = h(e1.x, e1.y) + 0.03, h(e2.x, e2.y) + 0.03
        need = h(x, y) + 0.05 - (z1 + z2) / 2
        if need > 0:
            z1 += need
            z2 += need
        plank_jag(rng.choice(["plank", "plank", "wood"]), (e1.x, e1.y, z1), (e2.x, e2.y, z2),
                  rng.uniform(0.12, 0.22), 0.03, rng)
    # Poutres cassées en travers du tas.
    for ib in range(n_beams):
        L = (1.7 * a) if ib == 0 else rng.uniform(2.5, 4.0)
        yaw = rng.uniform(-0.4, 0.4) + (0 if ib == 0 else rng.uniform(0.5, 2.6))
        d = Vector((math.cos(yaw), math.sin(yaw), 0)) * L / 2
        y0 = rng.uniform(-0.3, 0.3) * b
        x0 = 0.0 if ib == 0 else rng.uniform(-0.5, 0.5) * a
        e1, e2 = Vector((x0, y0, 0)) - d, Vector((x0, y0, 0)) + d
        zc = h(x0, y0) * 0.75
        beam("dark_wood", (e1.x, e1.y, max(h(e1.x, e1.y), 0.1) + 0.1), (e2.x, e2.y, zc + 0.25), 0.28, 0.32)
        chunk("dark_wood", (e1.x, e1.y, max(h(e1.x, e1.y), 0.1) + 0.12), (0.34, 0.3, 0.34), rng)
    # Fauteuils écrasés, à moitié enfouis.
    for s in range(n_seats):
        x, y = spot(0.6)
        with xf(T(x, y, h(x, y) - 0.3) @ R(rng.uniform(0, 360), "Z") @ R(rng.uniform(-60, 60), "X") @ R(rng.uniform(-35, 35), "Y")):
            seat_geo(back=rng.choice(["torn", "full", "none"]), arm_broken=rng.choice(["L", "R", None]),
                     tilt=rng.uniform(-20, 10))
    # Fers à béton tordus.
    for _ in range(4):
        x, y = spot(0.6)
        z = h(x, y)
        p0 = Vector((x, y, z - 0.1))
        dirv = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.3, 1.0))).normalized()
        p1 = p0 + dirv * rng.uniform(0.5, 0.9)
        p2 = p1 + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), -0.15))
        tube("steel", [p0, p1, p2], 0.012, 4)
    # Dossiers arrachés et coussins qui dépassent des gravats.
    for _ in range(n_backs):
        x, y = spot(0.85)
        with xf(T(x, y, h(x, y) - 0.45) @ R(rng.uniform(0, 360), "Z") @ R(rng.uniform(-50, 50), "X") @ R(rng.uniform(-30, 30), "Y")):
            prism("dark_wood", seat_back_profile(0.24, 0.47, 0.94, 1.12, 5), "xz", 0.15, 0.2)
            prism("velvet", seat_back_profile(0.2, 0.52, 0.9, 1.04, 4), "xz", 0.1, 0.15)
        x, y = spot(0.85)
        with xf(T(x, y, h(x, y) + 0.02) @ R(rng.uniform(0, 360), "Z") @ R(rng.uniform(-40, 40), "X")):
            box("velvet", -0.22, 0.22, -0.18, 0.18, -0.05, 0.05)
    return h


def fit(a, b, H):
    """Remet le modèle aux dimensions visées (empreinte 2a x 2b, hauteur H)
    et renvoie le facteur appliqué en hauteur."""
    lo, hi = bounds()
    kx, ky = min(1.0, a / max(-lo.x, hi.x)), min(1.0, b / max(-lo.y, hi.y))
    kz = H / hi.z
    deform(lambda v: Vector((v.x * kx, v.y * ky, v.z * kz)))
    return kz


def heap_boxes(h, a, b, bands, kz=1.0):
    """Boîtes de collision étagées approchant le tertre (bloquent tout)."""
    for (x0, x1, y0, y1) in bands:
        # Hauteur : moyenne du tertre sur la boîte (un peu relevée, bornée
        # sous le sommet) : les boîtes emboîtées forment des gradins.
        hs = [h(x0 + (x1 - x0) * i / 12, y0 + (y1 - y0) * j / 12) for i in range(13) for j in range(13)]
        top = min(max(hs) * 0.92, sum(hs) / len(hs) * 1.15)
        colbox_mm(x0, x1, y0, y1, 0.0, top * kz)


def m_rubble_heap_a():
    a, b, H = 2.5, 2.0, 2.2
    h = heap(a, b, H, 11, [(-0.3, 0.2, 1.4, 1.1, 1.0), (1.0, -0.5, 0.9, 0.8, 0.7)], 95, 10, 2, 5)
    heap_boxes(h, a, b, [(-2.1, 2.1, -1.5, 1.5), (-1.3, 1.3, -1.0, 1.1), (-0.9, 0.5, -0.5, 0.8)], fit(a, b, H))


def m_rubble_heap_b():
    a, b, H = 1.5, 1.5, 1.4
    h = heap(a, b, H, 23, [(0.1, 0.0, 0.8, 0.8, 1.0)], 60, 6, 1, 3, 14, 14)
    heap_boxes(h, a, b, [(-1.2, 1.2, -1.2, 1.2), (-0.7, 0.7, -0.7, 0.7)], fit(a, b, H))


def m_rubble_heap_c():
    a, b, H = 3.0, 1.5, 2.8
    h = heap(a, b, H, 37, [(-1.0, 0.1, 1.2, 0.8, 1.0), (1.3, -0.2, 0.9, 0.7, 0.75)], 110, 12, 2, 6, 22, 12)
    heap_boxes(h, a, b, [(-2.6, 2.6, -1.1, 1.1), (-1.9, -0.1, -0.7, 0.8), (0.6, 2.0, -0.7, 0.4), (-1.4, -0.6, -0.4, 0.5)], fit(a, b, H))


def m_debris_beam():
    # Poutre ornée de 6 m tombée du plafond : un bout au sol, l'autre posé
    # à 1,2 m sur un petit tas de gravats (+X).
    rng = random.Random(5)
    L = 6.0
    p = math.degrees(math.asin(1.2 / L))
    hor = L * math.cos(math.radians(p))
    with xf(T(-hor / 2, 0, 0) @ R(-p, "Y")):
        box("ceiling_theater", 0.25, 5.75, -0.2, 0.2, 0.02, 0.5)
        for sy in (-1, 1):
            y0, y1 = sorted((sy * 0.2, sy * 0.225))
            box("brass", 0.25, 5.75, y0, y1, 0.02, 0.09)
            box("brass", 0.25, 5.75, y0, y1, 0.43, 0.47)
            for i in range(27):
                x = 0.35 + i * 0.2
                box("brass", x, x + 0.08, *sorted((sy * 0.2, sy * 0.235)), 0.34, 0.41)
            for i in range(5):
                cyl("brass", (1.0 + i * 1.0, sy * 0.215, 0.22), 0.075, 0.03, "Y", 10)
        # Bouts cassés : plâtre arraché, âme en acier qui dépasse, fers tordus.
        for x in (0.15, 5.85):
            for _ in range(5):
                chunk(rng.choice(["ceiling_theater", "concrete"]), (x + rng.uniform(-0.1, 0.1), rng.uniform(-0.12, 0.12),
                      rng.uniform(0.1, 0.42)), (0.25, 0.22, 0.2), rng)
        box("steel", 5.5, 6.0, -0.02, 0.02, 0.12, 0.4)
        box("steel", 5.5, 6.0, -0.12, 0.12, 0.08, 0.12)
        box("steel", 5.5, 6.0, -0.12, 0.12, 0.4, 0.44)
        for k in range(3):
            y = -0.12 + k * 0.12
            tube("steel", [(0.3, y, 0.25), (0.02, y + 0.03, 0.28), (-0.05, y + 0.1, 0.4)], 0.012, 4)
    # Tas qui soutient le bout levé.
    cx = hor / 2 - 0.35
    hull("concrete_dark", [Vector((cx + math.cos(a) * rng.uniform(1.0, 1.15), math.sin(a) * rng.uniform(0.8, 0.95), 0.0))
                           for a in [i * 0.628 for i in range(10)]]
         + [Vector((cx + math.cos(a) * 0.75, math.sin(a) * 0.62, rng.uniform(0.45, 0.6))) for a in [i * 1.05 + 0.3 for i in range(6)]]
         + [Vector((cx + math.cos(a) * 0.4, math.sin(a) * 0.3, 1.05)) for a in [i * 1.57 for i in range(4)]])
    for _ in range(40):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.2, 1.1)
        z = max(0.05, min(1.05, 1.05 * (1.1 - r) / 0.65))
        s = rng.uniform(0.2, 0.45)
        chunk(rng.choice(["concrete", "stone", "wall_theater"]), (cx + math.cos(a) * r, math.sin(a) * r * 0.85, z), (s, s, s * 0.7), rng)
    # Collision : poutre en trois tronçons étagés + tas.
    for i in range(3):
        x0 = -hor / 2 + hor * i / 3
        x1 = x0 + hor / 3
        zt = 1.2 * (i + 1) / 3 + 0.5
        colbox_mm(x0, x1, -0.22, 0.22, 0.0 if i == 0 else 1.2 * i / 3, zt)
    colbox_mm(cx - 0.7, cx + 0.7, -0.6, 0.6, 0.0, 1.1)
    # Origine au centre de l'empreinte (le tas dépasse un peu du bout levé).
    lo, hi = bounds()
    dx = (lo.x + hi.x) / 2
    deform(lambda v: v - Vector((dx, 0, 0)))
    _boxes[:] = [(c - Vector((dx, 0, 0)), s, yw, br) for c, s, yw, br in _boxes]


def m_debris_planks():
    rng = random.Random(8)
    lim = Vector((0.98, 0.72))

    def put(c, yaw, L, z1, z2, mat):
        d = Vector((math.cos(yaw), math.sin(yaw))) * L / 2
        e1, e2 = Vector(c) - d, Vector(c) + d
        for e in (e1, e2):
            e.x = max(-lim.x, min(lim.x, e.x))
            e.y = max(-lim.y, min(lim.y, e.y))
        plank_jag(mat, (e1.x, e1.y, z1), (e2.x, e2.y, z2), rng.uniform(0.1, 0.2), 0.025, rng)

    for i in range(7):
        put((rng.uniform(-0.5, 0.5), rng.uniform(-0.4, 0.4)), rng.uniform(0, math.pi), rng.uniform(1.0, 1.8),
            0.013, 0.013, rng.choice(["plank", "wood"]))
    for i in range(6):
        put((rng.uniform(-0.4, 0.4), rng.uniform(-0.3, 0.3)), rng.uniform(0, math.pi), rng.uniform(0.9, 1.6),
            rng.uniform(0.04, 0.1), rng.uniform(0.05, 0.16), rng.choice(["plank", "wood", "dark_wood"]))
    for i in range(3):
        put((rng.uniform(-0.3, 0.3), rng.uniform(-0.25, 0.25)), rng.uniform(0, math.pi), rng.uniform(1.2, 1.7),
            0.02, rng.uniform(0.3, 0.38), "plank")
    # Côté de caisse cassé (lattes clouées sur deux traverses).
    with xf(T(0.35, 0.2, 0.12) @ R(25, "Z") @ R(14, "X")):
        for k in range(4):
            box("crate", -0.4, 0.4 - k * 0.07, -0.3 + k * 0.155, -0.16 + k * 0.155, 0.0, 0.02)
        for x in (-0.3, 0.2):
            box("crate", x, x + 0.08, -0.3, 0.32, -0.025, 0.0)
    colbox_mm(-0.95, 0.95, -0.7, 0.7, 0.0, 0.3, barrier=True)


def m_debris_scatter():
    rng = random.Random(13)
    with ns():
        for _ in range(48):
            x, y = rng.uniform(-1.45, 1.45), rng.uniform(-1.45, 1.45)
            s = rng.uniform(0.04, 0.2)
            chunk(rng.choice(["concrete", "concrete", "stone", "wall_theater", "ceiling_theater"]), (x, y, s * 0.2),
                  (s * 1.3, s, s * 0.55), rng, 7)
        for _ in range(14):
            x, y = rng.uniform(-1.3, 1.3), rng.uniform(-1.3, 1.3)
            with xf(T(x, y, 0.004) @ R(rng.uniform(0, 360), "Z") @ R(rng.uniform(-6, 6), "X")):
                box("paper", -0.105, 0.105, -0.148, 0.148, -0.0015, 0.0015)
        for c in ((-0.8, 0.6), (0.9, -0.4)):
            reel((c[0], c[1], 0.026), 0.175, 0.05, R(rng.uniform(0, 90), "Z"), True)
        reel((0.2, 0.9, 0.03), 0.15, 0.045, R(35, "Z") @ R(12, "X"), True)
        # Pellicule déroulée qui serpente au sol.
        path = [Vector((0.75 - 0.12 * i, -0.3 - 0.35 * math.sin(i * 0.5) + 0.05 * i, 0.003)) for i in range(14)]
        for i in range(len(path) - 1):
            beam("rubber", path[i], path[i + 1], 0.035, 0.002)
        for _ in range(8):
            x, y = rng.uniform(-1.3, 1.3), rng.uniform(-1.3, 1.3)
            yaw = rng.uniform(0, math.pi)
            L = rng.uniform(0.25, 0.6)
            d = Vector((math.cos(yaw), math.sin(yaw), 0)) * L / 2
            plank_jag("plank", Vector((x, y, 0.012)) - d, Vector((x, y, 0.012)) + d, rng.uniform(0.04, 0.08), 0.02, rng)


# ------------------------------------------------------------------ lustres
def chandelier_body(chain=True):
    """Lustre à pampilles : origine au point d'accroche, pend vers -Z.
    Chaîne de 2 m, corps de 3,5 m (z -2 à -5,5), diamètre 3,2 m."""
    if chain:
        for i in range(14):
            z = -0.07 - i * 0.138
            with xf(T(0, 0, z) @ R(90 * (i % 2), "Z") @ R(90, "X")):
                torus("brass", (0, 0, 0), 0.05, 0.012, 6, 3, (1.0, 1.6, 1.0))
        cyl("brass", (0, 0, -0.02), 0.12, 0.04, "Z", 10)
    # Fût central (vases et boules), couronne haute.
    lathe("brass", [(0.0, -1.98), (0.22, -2.0), (0.22, -2.08), (0.06, -2.25), (0.05, -2.8), (0.15, -2.9), (0.15, -3.0),
                    (0.05, -3.1), (0.05, -3.5), (0.2, -3.7), (0.28, -3.95), (0.3, -4.15), (0.22, -4.35), (0.08, -4.5),
                    (0.1, -4.7), (0.14, -4.85), (0.06, -5.05), (0.02, -5.22), (0.0, -5.26)], 10)
    with ns():
        octa("crystal", (0, 0, -5.28), 0.06, 0.3)
    torus("brass", (0, 0, -2.95), 0.85, 0.022, 28, 4)
    torus("brass", (0, 0, -4.3), 1.2, 0.028, 36, 4)
    tips = []
    for k in range(12):
        a = 2 * math.pi * k / 12
        c, s = math.cos(a), math.sin(a)

        def P(r, z):
            return Vector((c * r, s * r, z))
        arm = bezier(P(0.25, -4.1), P(0.75, -4.75), P(1.45, -4.6), P(1.5, -4.0), 12)
        # Petite volute sous la bobèche.
        curl = [P(1.5 - 0.1 * math.sin(t), -4.0 - 0.1 + 0.1 * math.cos(t)) for t in [i * 0.9 for i in range(1, 6)]]
        tube("brass", arm, 0.024, 4)
        tube("brass", [arm[-2]] + curl, 0.014, 4)
        cyl("brass", P(1.5, -3.97), 0.06, 0.05, "Z", 6, r2=0.035)
        tips.append(P(1.46, -4.02))
        with ns():
            cyl("chalk", P(1.5, -3.86), 0.025, 0.17, "Z", 5)
            octa("bulb", P(1.5, -3.72), 0.03, 0.12)
            octa("crystal", P(1.48, -4.12), 0.035, 0.16)
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        c, s = math.cos(a), math.sin(a)

        def P(r, z):
            return Vector((c * r, s * r, z))
        tube("brass", bezier(P(0.12, -3.05), P(0.5, -3.3), P(0.85, -3.2), P(0.88, -2.85), 8), 0.018, 4)
        cyl("brass", P(0.88, -2.83), 0.045, 0.04, "Z", 6, r2=0.03)
        with ns():
            cyl("chalk", P(0.88, -2.74), 0.02, 0.14, "Z", 5)
            octa("bulb", P(0.88, -2.62), 0.025, 0.1)
    # Guirlandes de pampilles : entre les bras, corbeille sous le fût,
    # et descentes de la couronne haute vers l'anneau principal.
    with ns():
        def beads(pts):
            tube("crystal", pts, [0.03 if i % 2 else 0.012 for i in range(len(pts))], 3)
        for k in range(12):
            beads(sag(tips[k], tips[(k + 1) % 12], 0.42, 11))
        for k in range(8):
            a = 2 * math.pi * k / 8
            beads(sag((math.cos(a) * 1.2, math.sin(a) * 1.2, -4.32), (math.cos(a) * 0.12, math.sin(a) * 0.12, -4.95), 0.35, 9))
        for k in range(8):
            a = 2 * math.pi * k / 8 + math.pi / 8
            beads(sag((math.cos(a) * 0.86, math.sin(a) * 0.86, -2.97), (math.cos(a) * 1.2, math.sin(a) * 1.2, -4.28), 0.3, 9))


def m_chandelier_fallen():
    # Le même lustre effondré sur le flanc et écrasé : 3,5 x 3 m, 1,5 m.
    chandelier_body(False)
    lo, hi = bounds()
    c = (lo + hi) / 2
    rot = (R(-72, "Y") @ R(14, "X")).to_3x3()
    deform(lambda v: rot @ (v - c))
    lo, hi = bounds()
    sx, sy, sz = 3.5 / (hi.x - lo.x), 3.0 / (hi.y - lo.y), 1.0 / (hi.z - lo.z)
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2

    def crush(v):
        x, y = (v.x - cx) * sx, (v.y - cy) * sy
        t = (v.z - lo.z) * sz
        z = 1.5 * t ** 1.2 * (1.0 - 0.18 * math.exp(-(x * x + y * y) / 1.5))
        z += 0.06 * math.sin(x * 2.3 + y * 1.3) * t
        return Vector((x, y, max(0.0, z)))
    deform(crush)
    kz = 1.5 / bounds()[1].z
    deform(lambda v: Vector((v.x, v.y, v.z * kz)))
    rng = random.Random(17)
    with ns():
        for _ in range(26):
            a = rng.uniform(0, 6.28)
            r = rng.uniform(0.3, 1.0)
            with xf(T(math.cos(a) * r * 1.55, math.sin(a) * r * 1.3, 0.02) @ R(rng.uniform(0, 360), "Z") @ R(90, "X")):
                octa("crystal", (0, 0, 0), 0.03, 0.14)
        for i in range(8):
            with xf(T(-1.2 + i * 0.1, -1.1 + 0.03 * i * i, 0.015) @ R(20 + 12 * i, "Z") @ R(90 * (i % 2), "X")):
                torus("brass", (0, 0, 0), 0.05, 0.012, 8, 3, (1.6, 1.0, 1.0))
    colbox_mm(-1.6, 1.6, -1.3, 1.3, 0.0, 1.0, barrier=True)


# ------------------------------------------------------------------ cabine de projection
def m_projector():
    # Grand projecteur de cinéma sur piédestal conique : 1,9 m, 1,4 m de long,
    # objectif vers -Y.
    oct8 = [(math.cos(math.pi / 8 + i * math.pi / 4) * 0.52, math.sin(math.pi / 8 + i * math.pi / 4) * 0.52) for i in range(8)]
    prism("steel", oct8, "xy", 0.0, 0.05)
    with xf(R(22.5, "Z")):
        lathe("steel", [(0.0, 0.05), (0.44, 0.05), (0.3, 0.9), (0.34, 0.92), (0.34, 0.98), (0.0, 0.98)], 8)
    for i in range(8):
        a = math.pi / 8 * 0 + i * math.pi / 4
        with ns():
            for k in range(4):
                t = 0.15 + k * 0.2
                r = 0.44 + (0.3 - 0.44) * (t - 0.05) / 0.85
                sphere("steel", (math.cos(a) * r, math.sin(a) * r, t), 0.018, 6, 3)
    box("metal", -0.26, 0.26, -0.42, 0.42, 0.98, 1.04, bevel=0.01)
    box("metal", -0.22, 0.22, -0.45, 0.35, 1.04, 1.45, bevel=0.02)
    for i in range(7):
        box("steel", -0.2, 0.2, -0.4 + i * 0.1, -0.36 + i * 0.1, 1.45, 1.47)
    cyl("steel", (0, -0.52, 1.22), 0.1, 0.14, "Y", 12)
    cyl("steel", (0, -0.63, 1.22), 0.085, 0.1, "Y", 12)
    with ns():
        cyl("glass", (0, -0.69, 1.22), 0.07, 0.02, "Y", 12)
    # Lanterne ronde à l'arrière et sa cheminée.
    cyl("metal", (0, 0.45, 1.24), 0.26, 0.5, "X", 16)
    for x in (-0.25, 0.25):
        cyl("steel", (x, 0.45, 1.24), 0.28, 0.03, "X", 16)
    cyl("steel", (0, 0.68, 1.24), 0.12, 0.04, "Y", 12)
    cyl("steel", (0, 0.45, 1.58), 0.07, 0.2, "Z", 8)
    # Carter de bobine au-dessus.
    cyl("metal", (0, -0.1, 1.56), 0.32, 0.14, "X", 18)
    with ns():
        cyl("steel", (-0.075, -0.1, 1.56), 0.06, 0.02, "X", 8)
        for sx in (-1, 1):
            rod("steel", (sx * 0.23, -0.2, 1.2), (sx * 0.3, -0.2, 1.2), 0.03, 6)
        tube("steel", [(0.23, 0.1, 1.15), (0.34, 0.1, 1.15), (0.34, 0.2, 1.05)], 0.015, 4)
        sphere("rubber", (0.34, 0.2, 1.03), 0.03, 6, 3)
    colbox_mm(-0.45, 0.45, -0.45, 0.45, 0.0, 1.0)
    colbox_mm(-0.3, 0.3, -0.7, 0.7, 1.0, 1.9)


def m_reel_shelf():
    # Étagère métallique à bobines (1,2 x 0,4 x 1,8 m).
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.585, sy * 0.185
            box("steel", *sorted((x, x - sx * 0.035)), *sorted((y + sy * 0.015, y - sy * 0.015)), 0.0, 1.8)
            box("steel", *sorted((x + sx * 0.015, x - sx * 0.015)), *sorted((y, y - sy * 0.035)), 0.0, 1.8)
        rod("steel", (sx * 0.585, -0.185, 0.12), (sx * 0.585, 0.185, 1.7), 0.01, 4)
        rod("steel", (sx * 0.585, 0.185, 0.12), (sx * 0.585, -0.185, 1.7), 0.01, 4)
    for z in (0.1, 0.55, 1.0, 1.45, 1.78):
        box("steel", -0.6, 0.6, -0.2, 0.2, z - 0.015, z)
        box("steel", -0.6, 0.6, -0.205, -0.19, z - 0.05, z)
    rng = random.Random(21)
    with ns():
        for z in (0.1, 0.55, 1.0, 1.45):
            x = -0.52
            rmax = 0.15 if z > 1.4 else 0.18
            while x < 0.5:
                pick = rng.random()
                if pick < 0.55:
                    # Rangée de bobines debout sur la tranche, comme des livres.
                    for k in range(rng.randint(2, 3)):
                        if x > 0.54:
                            break
                        r = rng.uniform(0.14, rmax)
                        reel((x + 0.025, rng.uniform(-0.02, 0.02), z + r), r, 0.045, R(90, "Y"), False)
                        x += 0.052
                    x += 0.05
                elif pick < 0.85 and x < 0.2:
                    # Pile de bobines à plat.
                    for k in range(rng.randint(1, 3)):
                        reel((x + 0.17, rng.uniform(-0.01, 0.01), z + 0.025 + k * 0.047), 0.16, 0.045,
                             R(rng.uniform(0, 60), "Z"), False)
                    x += 0.38
                else:
                    x += 0.2
    colbox_mm(-0.6, 0.6, -0.2, 0.2, 0.0, 1.8)


def m_desk():
    # Vieux bureau en bois (1,4 x 0,7 x 0,78 m) couvert de papiers.
    box("dark_wood", -0.7, 0.7, -0.35, 0.35, 0.74, 0.78, bevel=0.008)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.68, sx * 0.3))
        box("wood", x0, x1, -0.32, 0.32, 0.05, 0.74)
        box("dark_wood", x0 - 0.01, x1 + 0.01, -0.33, 0.33, 0.0, 0.05)
        for k in range(3):
            z0 = 0.09 + k * 0.215
            box("dark_wood", x0 + 0.02, x1 - 0.02, -0.335, -0.32, z0, z0 + 0.19)
            with ns():
                box("brass", (x0 + x1) / 2 - 0.05, (x0 + x1) / 2 + 0.05, -0.35, -0.335, z0 + 0.09, z0 + 0.11)
    box("wood", -0.3, 0.3, 0.28, 0.31, 0.3, 0.74)
    box("dark_wood", -0.3, 0.3, -0.335, -0.31, 0.64, 0.72)
    rng = random.Random(4)
    with ns():
        for _ in range(7):
            with xf(T(rng.uniform(-0.5, 0.5), rng.uniform(-0.2, 0.2), 0.782) @ R(rng.uniform(-40, 40), "Z")):
                box("paper", -0.105, 0.105, -0.148, 0.148, 0.0, 0.002)
        box("paper", 0.35, 0.56, 0.02, 0.3, 0.78, 0.83)
        reel((-0.45, 0.12, 0.806), 0.15, 0.045, I4, True)
        cyl("rubber", (0.15, 0.18, 0.84), 0.04, 0.11, "Z", 8)
        box("paper", -0.2, 0.18, -0.25, -0.1, 0.782, 0.788)
    colbox_mm(-0.7, 0.7, -0.35, 0.35, 0.0, 0.78)


def m_folding_chair():
    # Chaise pliante en bois à lattes (0,45 x 0,5 x 0,85 m), sans ombre.
    with ns():
        for sx in (-0.2, 0.2):
            beam("wood", (sx, -0.22, 0.0), (sx, 0.12, 0.85), 0.03, 0.035, up=(0, -1, 0))
            beam("wood", (sx, 0.2, 0.0), (sx, -0.1, 0.46), 0.03, 0.035, up=(0, 1, 0))
        rod("steel", (-0.22, 0.0, 0.3), (0.22, 0.0, 0.3), 0.01, 4)
        for k in range(5):
            y = -0.17 + k * 0.07
            box("wood", -0.2, 0.2, y, y + 0.055, 0.44, 0.46)
        for k in range(3):
            z = 0.58 + k * 0.1
            y = -0.22 + (0.34 * (z / 0.85))
            box("wood", -0.2, 0.2, y - 0.01, y + 0.01, z, z + 0.075)


def m_lectern():
    # Pupitre de l'orateur (1,2 m) au petit drapeau ORIGINAL (bobine).
    box("dark_wood", -0.34, 0.34, -0.28, 0.28, 0.0, 0.1, bevel=0.01)
    prism("wood", [(-0.25, 0.1), (0.25, 0.1), (0.21, 1.02), (-0.21, 1.02)], "xz", -0.2, 0.2)
    box("dark_wood", -0.24, 0.24, -0.23, 0.23, 1.0, 1.05)
    prism("dark_wood", [(-0.26, 1.05), (0.28, 1.05), (0.28, 1.1), (-0.26, 1.2)], "yz", -0.32, 0.32)
    box("dark_wood", -0.32, 0.32, -0.3, -0.26, 1.16, 1.21)
    cyl("brass", (0, -0.23, 1.02), 0.012, 0.56, "X", 6)
    F, Bk = [], []
    for r in range(6):
        z = 1.0 - r * 0.15
        row, rowb = [], []
        for c in range(7):
            x = -0.2 + 0.4 * c / 6
            y = -0.235 - 0.012 * math.sin(math.pi * c / 3) * (r / 5)
            row.append(Vector((x, y, z)))
            rowb.append(Vector((x, y + 0.01, z)))
        F.append(row)
        Bk.append(rowb)
    sheet("velvet", F, Bk)
    with ns():
        reel_emblem(0.0, 0.64, -0.25, 0.3)
        tube("brass", [(-0.2, -0.24, 0.24), (0.2, -0.24, 0.24)], 0.012, 4)
    colbox_mm(-0.34, 0.34, -0.3, 0.3, 0.0, 1.2)


# ------------------------------------------------------------------ scène et coulisses
# Aucune peinture bleue côté jeu (WorldLook.SURFACES et clés spéciales) : les
# bidons « bleus » de BO1 prennent la peinture sarcelle, les gros câbles bleu
# foncé le caoutchouc noir. À changer ici si une clé bleue apparaît.
BARREL_MAT = "paint_blue"
CABLE_MAT = "cable_blue"


def recenter():
    """Recentre l'empreinte (x, y) sur l'origine, boîtes comprises ; le sol
    (z) ne bouge pas. Renvoie le décalage appliqué."""
    lo, hi = bounds()
    d = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0.0))
    deform(lambda v: v - d)
    _boxes[:] = [(c - d, s, yw, br) for c, s, yw, br in _boxes]
    return d


def drum(c, yaw=0.0, lying=False):
    """Bidon de 200 l (Ø 0,58 m, h 0,88 m) : bords sertis, deux cerclages de
    roulement, couvercle en creux, deux bouchons. c : centre du fond (debout)
    ou point au sol sous le milieu (couché, axe le long de X local)."""
    if lying:
        m = T(c[0], c[1], c[2] + 0.303) @ R(yaw, "Z") @ R(90, "Y") @ T(0, 0, -0.44)
    else:
        m = T(*c) @ R(yaw, "Z")
    with xf(m):
        lathe(BARREL_MAT, [(0.0, 0.0), (0.275, 0.0), (0.29, 0.015), (0.29, 0.285), (0.303, 0.3), (0.29, 0.315),
                           (0.29, 0.565), (0.303, 0.58), (0.29, 0.595), (0.29, 0.865), (0.296, 0.88), (0.27, 0.88),
                           (0.27, 0.868), (0.0, 0.868)], 12, smooth="sides")
        with ns():
            cyl("steel", (0.16, 0.0, 0.88), 0.032, 0.03, "Z", 6)
            cyl("steel", (-0.17, 0.06, 0.876), 0.02, 0.02, "Z", 6)


def m_blue_barrel_group():
    # Bidons bleus du pied de scène et des coulisses : quatre debout, deux
    # empilés sur ceux du fond, un couché devant ; 2,1 x 1,7 m, 1,76 m.
    rng = random.Random(61)
    back = [(-0.55, 0.25), (0.08, 0.32)]
    for x, y in back + [(0.68, 0.08), (-0.2, -0.3)]:
        drum((x, y, 0.0), rng.uniform(0, 360))
    for x, y in back:
        drum((x + rng.uniform(-0.03, 0.03), y + rng.uniform(-0.03, 0.03), 0.88), rng.uniform(0, 360))
    drum((0.62, -0.6, 0.0), -20, lying=True)
    # Barrières (les balles passent) : rang du fond avec la pile, puis le reste.
    colbox_mm(-0.86, 0.4, -0.06, 0.64, 0.0, 1.76, barrier=True)
    colbox_mm(-0.5, 1.14, -1.03, 0.38, 0.0, 0.9, barrier=True)
    recenter()


# Modèles NON CUBIQUES encore utilisés, rangés par lot de conversion en cubes
# de 5 cm (docs/VOXEL_DECOR_PLAN.md) : chaque lot retire ses lignes (et ses
# fonctions m_*) une fois ses décors remplacés ; le dernier supprime ce script.
BUILDERS = {
    # Lot 1 : gravats et ruines.
    "rubble_heap_a": m_rubble_heap_a,
    "rubble_heap_b": m_rubble_heap_b,
    "rubble_heap_c": m_rubble_heap_c,
    "debris_beam": m_debris_beam,
    "debris_planks": m_debris_planks,
    "debris_scatter": m_debris_scatter,
    "chandelier_fallen": m_chandelier_fallen,

    # Lot 2 : mobilier et stockage.
    "seat": m_seat,
    "seat_broken_b": m_seat_broken_b,
    "projector": m_projector,
    "reel_shelf": m_reel_shelf,
    "desk": m_desk,
    "folding_chair": m_folding_chair,
    "lectern": m_lectern,
    "blue_barrel_group": m_blue_barrel_group,
}

# Modèles suspendus ou muraux : pas de sol dans l'aperçu.
NO_FLOOR = set()


# ------------------------------------------------------------------ export
def material(key, preview=False):
    m = bpy.data.materials.get(key)
    if m:
        return m
    m = bpy.data.materials.new(key)
    c, rough, metal, emit = MATS[key]
    m.use_nodes = True
    m.use_backface_culling = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*c, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit > 0:
        p.inputs["Emission Color"].default_value = (*c, 1.0)
        p.inputs["Emission Strength"].default_value = emit
    if key == "glass":
        p.inputs["Alpha"].default_value = 0.25
    m.diffuse_color = (*c, 1.0)
    return m


def build(name):
    reset()
    BUILDERS[name]()
    obs = []
    tris = 0
    for (mat, kind), bm in sorted(_parts.items()):
        oname = "%s__%s__%s" % (mat, name, kind)
        me = bpy.data.meshes.new(oname)
        bm.to_mesh(me)
        me.materials.append(material(mat))
        ob = bpy.data.objects.new(oname, me)
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
        tris += len(me.polygons)
    for bm in _parts.values():
        bm.free()
    _parts.clear()
    return obs, tris


def write_collision(name):
    path = os.path.join(OUT_DIR, name + ".collision.json")
    if not _boxes:
        if os.path.exists(path):
            os.remove(path)
        return 0
    out = []
    for c, s, yaw, barrier in _boxes:
        # Blender (x, y, z) -> Godot (x, z, -y) ; taille (sx, sz, sy) ; le
        # lacet autour de Z Blender est le même angle autour de Y Godot.
        def r4(v):
            return round(v, 4) + 0.0
        out.append({"center": [r4(c.x), r4(c.z), r4(-c.y)], "size": [r4(s[0]), r4(s[2]), r4(s[1])],
                    "yaw": r4(yaw), "barrier": bool(barrier)})
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write('{"boxes": [\n' + ",\n".join("  " + json.dumps(b) for b in out) + "\n]}\n")
    return len(out)


def preview(name, obs):
    sc = bpy.context.scene
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for ob in obs:
        for v in ob.data.vertices:
            lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
            hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    c = (lo + hi) / 2
    rad = (hi - lo).length / 2
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.2, 0.21, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = world
    if name not in NO_FLOOR:
        bpy.ops.mesh.primitive_plane_add(size=max(40, rad * 6), location=(c.x, c.y, lo.z - 0.001))
        fl = bpy.context.active_object
        fm = bpy.data.materials.new("sol")
        fm.use_nodes = True
        fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1)
        fl.data.materials.append(fm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.clip_end = 500
    sc.collection.objects.link(cam)
    sc.camera = cam
    target = bpy.data.objects.new("cible", None)
    sc.collection.objects.link(target)
    tr = cam.constraints.new("TRACK_TO")
    tr.target = target
    tr.track_axis = "TRACK_NEGATIVE_Z"
    tr.up_axis = "UP_Y"
    sc.render.resolution_x, sc.render.resolution_y = 900, 760
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    views = []
    az, el = math.radians(35), math.radians(22)
    dist = rad / math.sin(math.radians(17.5)) * 1.02
    d = Vector((-math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    views.append(("", c, c + d * dist, 50))
    for suffix, tgt, loc, lens in views:
        target.location = tgt
        cam.location = loc
        cam.data.lens = lens
        sc.render.filepath = os.path.join(PREVIEW_DIR, name + suffix + ".png")
        bpy.ops.render.render(write_still=True)


names = ONLY or list(BUILDERS.keys())
os.makedirs(OUT_DIR, exist_ok=True)
if PREVIEW_DIR:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
report = []
for name in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs, tris = build(name)
    for ob in obs:
        ob.select_set(True)
    out = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    nb = write_collision(name)
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for ob in obs:
        for v in ob.data.vertices:
            lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
            hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    line = "[catalog_props] %-18s %6d tri  %d obj  %d boîtes  x[%.2f %.2f] y[%.2f %.2f] z[%.2f %.2f]" % (
        name, tris, len(obs), nb, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z)
    print(line)
    report.append(line)
    if PREVIEW_DIR:
        preview(name, obs)
print("\n".join(report))
