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




# Modèles NON CUBIQUES encore utilisés, rangés par lot de conversion en cubes
# de 5 cm (docs/VOXEL_DECOR_PLAN.md) : chaque lot retire ses lignes (et ses
# fonctions m_*) une fois ses décors remplacés ; le dernier supprime ce script.
BUILDERS = {
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
