# Décharnement : la peau d'un corps humain est « rétractée » vers le
# squelette anatomique qu'il contient (côtes, clavicules, bassin, orbites,
# pommettes et arcades apparaissent d'elles-mêmes).
#
# Pour chaque sommet, l'épaisseur de chair est mesurée par un rayon lancé
# vers l'intérieur (le long de -normale) jusqu'au premier os ; le retrait vaut
# (épaisseur - tmin) * (1 - f), plafonné à `cap`, et se fait le long de la
# normale : champ continu, pas de pli ni de couture entre deux os. Réglages
# fondus selon la hauteur (visage, cou, tronc, jambes) et la distance à l'axe
# du corps (bras).
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# (tmin, f, cap) : épaisseur minimale gardée, part de chair conservée,
# retrait maximal (mètres).
HEAD = (0.004, 0.55, 0.01)
NECK = (0.004, 0.45, 0.015)
TORSO = (0.004, 0.4, 0.03)
ARM = (0.004, 0.5, 0.02)
LEG = (0.005, 0.6, 0.02)
EXTREMITY = (0.004, 0.85, 0.004)
MISS = 0.03   # épaisseur supposée quand le rayon ne touche aucun os

# Zones du visage protégées (centre, rayons) : lèvres, nez, paupières gardent
# leur forme (sinon aspirées contre les dents et les orbites).
PROTECT = []


def skeleton_bvh(objects):
    """BVH des os (maillages ÉVALUÉS : certains os ne sont modélisés que d'un
    côté et complétés par un modificateur miroir)."""
    import bpy
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for o in objects:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        base = len(verts)
        verts += [(mw @ v.co)[:] for v in me.vertices]
        polys += [[base + i for i in p.vertices] for p in me.polygons]
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def _smooth(a, b, t):
    t = min(1.0, max(0.0, t))
    t = t * t * (3 - 2 * t)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def params(p, height):
    """Réglages fondus d'un point (pose en A, pieds à z = 0)."""
    h = p[2] / height
    ax = abs(p[0]) / height
    body = _smooth(LEG, TORSO, (h - 0.47) / 0.06)
    body = _smooth(body, NECK, (h - 0.8) / 0.03)
    body = _smooth(body, HEAD, (h - 0.855) / 0.02)
    if h > 0.45 and h < 0.85:
        body = _smooth(body, ARM, (ax - 0.1) / 0.02)
    # Mains et pieds : déjà fins, à peine touchés (doigts intacts).
    body = _smooth(body, EXTREMITY, (ax - 0.2) / 0.02 * (1.0 if h < 0.6 else 0.0))
    body = _smooth(body, EXTREMITY, (0.07 - h) / 0.02)
    return body


def _protect(p):
    k = 0.0
    for c, r in PROTECT:
        q = ((p[0] - c[0]) / r[0]) ** 2 + ((p[1] - c[1]) / r[1]) ** 2 + ((p[2] - c[2]) / r[2]) ** 2
        k = max(k, float(np.exp(-q * 1.5)))
    return 1.0 - k


def _edges(me):
    ne = len(me.edges)
    ed = np.empty(ne * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ed)
    return ed.reshape(ne, 2)


def _laplace(val, ed, n, iters):
    deg = np.bincount(ed.ravel(), minlength=n).astype(float)
    deg[deg == 0] = 1.0
    for _ in range(iters):
        acc = np.zeros_like(val)
        np.add.at(acc, ed[:, 0], val[ed[:, 1]])
        np.add.at(acc, ed[:, 1], val[ed[:, 0]])
        val = 0.5 * val + 0.5 * acc / (deg[:, None] if val.ndim == 2 else deg)
    return val


def emaciate(me, bvh, height, strength=1.0, smooth_iter=8):
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    nor = np.empty(n * 3)
    me.vertices.foreach_get("normal", nor)
    nor = nor.reshape(n, 3)
    move = np.zeros(n)
    for i in range(n):
        p = Vector(co[i])
        d = -Vector(nor[i])
        hit, _, _, t = bvh.ray_cast(p + d * 0.0005, d, 0.3)
        t = MISS if hit is None else t
        tmin, f, cap = params(co[i], height)
        m = min(cap, max(0.0, (t - tmin) * (1.0 - f))) * strength
        if PROTECT and co[i][2] > 0.85 * height:
            m *= _protect(co[i])
        move[i] = m
    ed = _edges(me)
    move = _laplace(move, ed, n, smooth_iter)
    co -= nor * move[:, None]
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    return float(move.max())
