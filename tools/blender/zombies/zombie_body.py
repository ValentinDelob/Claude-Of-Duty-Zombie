# Corps de base COMMUN à tous les zombies (Kino der Toten, Black Ops 1) :
# humain maigre et décharné, bras longs, mains crochues, visage creusé à la
# mâchoire pendante. Un seul corps pour toutes les tenues : les zombies d'une
# carte restent cohérents entre eux.
#
# Étapes : graphe de sommets + modificateur Skin (volumes), subdivision,
# remaillage voxel (surface unique, sans fissure), « sculpture » par code
# (pinceaux gaussiens le long des normales : orbites, pommettes, côtes,
# clavicules, rotules...), puis décimation au budget du jeu.
# Articulations calées sur RigBuilder.BONES (repère Blender : Z en haut, face
# avant vers -Y, gauche du personnage vers +X).
import bpy, bmesh, math
from mathutils import Vector
from mathutils.kdtree import KDTree

# Positions globales des os (RigBuilder.BONES, godot (x, y, z) -> blender
# (x, -z, y)) : début de chaque os.
JOINTS = {
    "hips": (0.0, 0.0, 0.95),
    "spine": (0.0, 0.0, 1.07),
    "chest": (0.0, 0.0, 1.32),
    "neck": (0.0, 0.0, 1.57),
    "head": (0.0, 0.0, 1.65),
    "jaw": (0.0, -0.01, 1.72),
    "arm_l": (0.23, 0.0, 1.52),
    "forearm_l": (0.23, 0.0, 1.22),
    "arm_r": (-0.23, 0.0, 1.52),
    "forearm_r": (-0.23, 0.0, 1.22),
    "thigh_l": (0.1, 0.0, 0.93),
    "shin_l": (0.1, 0.0, 0.48),
    "thigh_r": (-0.1, 0.0, 0.93),
    "shin_r": (-0.1, 0.0, 0.48),
}


def _graph():
    """Sommets [position, rayon x, rayon y] et arêtes du squelette de peau."""
    v = []
    e = []

    def add(p, rx, ry=None):
        v.append((Vector(p), rx, ry if ry is not None else rx))
        return len(v) - 1

    def chain(pts, start=None):
        idx = [] if start is None else [start]
        for p in pts:
            idx.append(add(*p))
        for a, b in zip(idx, idx[1:]):
            e.append((a, b))
        return idx

    # Tronc : bassin -> cou (maigre, ventre creux, cage thoracique large).
    trunk = chain([
        ((0, 0.0, 0.9), 0.14, 0.1),
        ((0, 0.0, 0.99), 0.128, 0.088),
        ((0, 0.008, 1.08), 0.112, 0.075),
        ((0, 0.0, 1.18), 0.128, 0.086),
        ((0, -0.006, 1.28), 0.148, 0.097),
        ((0, 0.0, 1.38), 0.162, 0.1),
        ((0, 0.006, 1.47), 0.158, 0.094),
        ((0, 0.012, 1.535), 0.1, 0.07),
    ])
    neck = chain([
        ((0, 0.01, 1.6), 0.042, 0.046),
        ((0, 0.0, 1.655), 0.045, 0.05),
    ], trunk[-1])
    # Tête : volume à part (_head), relié au cou au remaillage.
    chain([((0, -0.005, 1.7), 0.04, 0.045)], neck[-1])

    for s in (1, -1):
        sh = chain([
            ((s * 0.12, 0.008, 1.5), 0.055, 0.05),
            ((s * 0.205, 0.012, 1.5), 0.048, 0.048),
        ], trunk[-2])
        arm = chain([
            ((s * 0.232, 0.012, 1.44), 0.04, 0.043),
            ((s * 0.234, 0.006, 1.33), 0.032, 0.034),
            ((s * 0.232, 0.004, 1.225), 0.027, 0.029),
            ((s * 0.232, -0.004, 1.13), 0.03, 0.027),
            ((s * 0.23, -0.01, 1.0), 0.021, 0.016),
        ], sh[-1])
        hand = chain([((s * 0.23, -0.013, 0.945), 0.034, 0.014)], arm[-1])
        for k, dx in enumerate((-0.022, -0.008, 0.007, 0.021)):
            ln = 1.0 - abs(k - 1.5) * 0.08
            chain([
                ((s * (0.23 + dx * 0.9), -0.02, 0.9), 0.0075),
                ((s * (0.23 + dx), -0.034, 0.862 + (1 - ln) * 0.03), 0.0068),
                ((s * (0.23 + dx), -0.05, 0.838 + (1 - ln) * 0.03), 0.0058),
            ], hand[-1])
        chain([
            ((s * 0.206, -0.03, 0.93), 0.0078),
            ((s * 0.2, -0.05, 0.9), 0.0068),
        ], hand[-1])
        leg = chain([
            ((s * 0.1, 0.0, 0.84), 0.074, 0.078),
            ((s * 0.1, -0.004, 0.66), 0.056, 0.058),
            ((s * 0.1, -0.01, 0.48), 0.043, 0.045),
            ((s * 0.1, 0.004, 0.38), 0.046, 0.05),
            ((s * 0.1, 0.006, 0.2), 0.033, 0.034),
            ((s * 0.1, 0.01, 0.08), 0.029, 0.031),
        ], trunk[0])
        chain([
            ((s * 0.1, -0.02, 0.04), 0.04, 0.034),
            ((s * 0.1, -0.1, 0.03), 0.042, 0.027),
            ((s * 0.1, -0.16, 0.025), 0.037, 0.021),
        ], leg[-1])
    return v, e


# Pinceaux (centre, rayons (x, y, z), déplacement le long de la normale en
# mètres ; négatif = creuse). Symétriques si sym=True (miroir en X).
BRUSHES = [
    # --- Visage ---
    ((0.032, -0.085, 1.79), (0.024, 0.03, 0.017), -0.02, True),     # orbites
    ((0.032, -0.09, 1.806), (0.03, 0.02, 0.008), 0.009, True),      # arcade sourcilière
    ((0.0, -0.1, 1.805), (0.03, 0.02, 0.01), 0.006, False),         # front bas
    ((0.052, -0.07, 1.755), (0.018, 0.02, 0.012), 0.011, True),     # pommettes
    ((0.045, -0.075, 1.73), (0.022, 0.025, 0.022), -0.014, True),   # joues creuses
    ((0.0, -0.105, 1.765), (0.009, 0.015, 0.022), 0.017, False),    # nez
    ((0.0, -0.095, 1.745), (0.018, 0.012, 0.008), -0.006, False),   # base du nez
    ((0.07, -0.02, 1.78), (0.01, 0.02, 0.022), 0.012, True),        # oreilles
    ((0.066, -0.004, 1.84), (0.03, 0.04, 0.03), -0.006, True),      # tempes
    ((0.0, -0.085, 1.7), (0.03, 0.025, 0.018), 0.008, False),       # menton
    ((0.035, -0.06, 1.705), (0.012, 0.03, 0.01), 0.008, True),      # angle de la mâchoire
    ((0.0, 0.01, 1.855), (0.07, 0.08, 0.04), 0.01, False),          # voûte du crâne
    ((0.0, 0.07, 1.8), (0.05, 0.03, 0.05), 0.008, False),           # occiput
    # --- Cou décharné : tendons ---
    ((0.02, -0.035, 1.6), (0.008, 0.012, 0.05), 0.008, True),
    ((0.0, -0.05, 1.62), (0.01, 0.01, 0.012), 0.006, False),        # pomme d'Adam
    # --- Tronc ---
    ((0.07, -0.075, 1.505), (0.06, 0.02, 0.009), 0.011, True),      # clavicules
    ((0.07, -0.075, 1.48), (0.05, 0.03, 0.012), -0.008, True),      # creux sous-claviculaire
    ((0.0, -0.1, 1.3), (0.012, 0.02, 0.12), -0.006, False),         # sternum creux
    ((0.0, -0.075, 1.12), (0.08, 0.05, 0.06), -0.012, False),       # ventre creusé
    ((0.12, -0.02, 1.02), (0.02, 0.06, 0.05), 0.008, True),         # crêtes iliaques
    ((0.05, 0.08, 1.4), (0.04, 0.02, 0.07), 0.01, True),            # omoplates
    ((0.0, 0.09, 1.25), (0.01, 0.02, 0.25), -0.006, False),         # sillon vertébral
    # --- Membres ---
    ((0.235, 0.02, 1.225), (0.02, 0.02, 0.02), 0.009, True),        # coudes
    ((0.1, -0.05, 0.48), (0.03, 0.02, 0.03), 0.01, True),           # rotules
    ((0.235, -0.01, 1.47), (0.03, 0.03, 0.03), 0.008, True),        # deltoïdes secs
    ((0.1, 0.03, 0.08), (0.015, 0.02, 0.02), 0.006, True),          # talons
    ((0.13, 0.0, 0.085), (0.01, 0.01, 0.015), 0.006, True),         # malléoles
]


def _ribs(co, n):
    """Côtes saillantes sur le devant et les flancs de la cage thoracique."""
    if co.z < 1.16 or co.z > 1.46 or n.y > 0.35:
        return 0.0
    ax = abs(co.x)
    if ax < 0.025 or ax > 0.165:
        return 0.0
    # Les côtes descendent vers l'avant et les flancs.
    t = co.z + ax * 0.35
    band = 0.5 + 0.5 * math.cos((t - 1.16) / 0.045 * 2.0 * math.pi)
    fade = min(1.0, (co.z - 1.16) / 0.05) * min(1.0, (1.46 - co.z) / 0.06)
    return (band ** 3 - 0.35) * 0.007 * fade


def _sculpt(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    moves = []
    for vert in bm.verts:
        co, n = vert.co, vert.normal
        d = _ribs(co, n)
        for c, r, amt, sym in BRUSHES:
            for sx in ((1, -1) if sym else (1,)):
                q = Vector(((co.x - c[0] * sx) / r[0], (co.y - c[1]) / r[1], (co.z - c[2]) / r[2]))
                k = q.length_squared
                if k < 9.0:
                    d += amt * math.exp(-k)
        moves.append(n * d)
    for vert, m in zip(bm.verts, moves):
        vert.co += m
    bm.to_mesh(me)
    bm.free()


def _head_shape(p):
    """Déforme une sphère unité en crâne décharné (repère de la tête)."""
    x, y, z = p.x, p.y, p.z
    # Crâne : plus profond que large, arrière arrondi, front fuyant.
    sx, sy, sz = 0.074, 0.098, 0.112
    if y < 0.0:
        # Visage plus étroit vers le bas (mâchoire), front plat.
        narrow = 1.0 - 0.28 * max(0.0, -z) ** 1.3
        sx *= narrow
        sy *= 0.93 - 0.05 * max(0.0, z)
    if z < -0.2:
        # Mâchoire tombante : le bas du visage avance et descend.
        y -= 0.12 * (-z - 0.2)
        z -= 0.06 * (-z - 0.2)
    return Vector((x * sx, y * sy, z * sz))


def _head(name):
    me = bpy.data.meshes.new(name + "_head")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=32, radius=1.0)
    for vert in bm.verts:
        vert.co = _head_shape(vert.co) + Vector((0.0, -0.012, 1.765))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name + "_head", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build(name="zombie_body", voxel=0.0045, target_tris=6000):
    v, e = _graph()
    me = bpy.data.meshes.new(name)
    me.from_pydata([p for p, _, _ in v], e, [])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    sk = ob.modifiers.new("Skin", "SKIN")
    sk.branch_smoothing = 0.4
    for i, (_, rx, ry) in enumerate(v):
        me.skin_vertices[0].data[i].radius = (rx, ry)
    me.skin_vertices[0].data[0].use_root = True
    sub = ob.modifiers.new("Subdiv", "SUBSURF")
    sub.levels = 2
    _apply_all(ob)
    # Tête fusionnée au corps (le remaillage voxel soude les deux volumes).
    head = _head(name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.from_mesh(head.data)
    bm.to_mesh(ob.data)
    bm.free()
    bpy.data.meshes.remove(head.data)
    rem = ob.modifiers.new("Remesh", "REMESH")
    rem.mode = "VOXEL"
    rem.voxel_size = voxel
    rem.adaptivity = 0.0
    _apply_all(ob)
    _sculpt(ob.data)
    # Lissage léger puis décimation au budget.
    sm = ob.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 2
    _apply_all(ob)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dec = ob.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = min(1.0, target_tris / max(1, tris))
    _apply_all(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def _apply_all(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
