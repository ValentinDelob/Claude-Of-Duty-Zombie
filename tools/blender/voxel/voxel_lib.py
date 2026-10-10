# Bibliothèque de la direction artistique CUBIQUE (GAME_CONCEPT.md § 4.19,
# docs/ART_DIRECTION.md « Chaîne de production cubique ») : construit dans
# Blender des modèles faits UNIQUEMENT de cubes de 5 cm, à partir d'une
# description simple, et les exporte en .glb conformes à VoxelCheck.
#
#   import sys, os; sys.path.insert(0, "<dépôt>/tools/blender/voxel")
#   import voxel_lib as vx
#   m = vx.Model()
#   m.box(-2, 2, -1, 1, 0, 8, "metal", color=(0.4, 0.4, 0.42))   # pavé, en cubes
#   m.layers([["##", "##"], ["#.", ".."]], (0, 0, 8), {"#": ("cloth", (0.8, 0.8, 0.7))})
#   m.face_color[(0, 0, 8, "+z")] = (0.9, 0.2, 0.1)              # une face de cube
#   ob, info = vx.build_mesh(m, "caisse")                        # faces fusionnées
#   vx.export_glb("assets/models/props/caisse.glb", [ob])        # vérifié avant écriture
#   vx.godot_check("assets/models/props/caisse.glb", animated=False)
#
# Unités : la description est en CUBES (entiers), repère Blender (Z en haut,
# face avant vers -Y, gauche d'un personnage vers +X). Une cellule (x, y, z)
# occupe [x, x+1] × [y, y+1] × [z, z+1] cubes, soit 5 cm de côté.
#
# Maillage :
#   - seules les faces visibles sont créées (voisin vide), plus les faces entre
#     deux os différents (une articulation qui tourne ne montre pas de trou) ;
#   - couleur PAR FACE DE CUBE : attribut de couleur « Col » (octets sRGB, par
#     coin), aucun sommet partagé entre deux rectangles : la couleur et la
#     normale (plate, alignée sur un axe) ne bavent jamais ;
#   - les faces coplanaires voisines de même couleur, même matière et même os
#     sont fusionnées en rectangles (balayage glouton) : moins de triangles ;
#   - matériaux nommés comme ZombieGlb.MATS : skin, eye, cloth, leather, metal,
#     wound, bone (la matière du shader des zombies) ; l'œil est émissif.
# Personnages : chaque cellule porte un os ; pondération RIGIDE (100 % sur
# cet os), squelette build_armature (os droits, alignés sur les axes).
# Objets statiques : aucun os, aucun squelette.
# Auto-vérification (self_check) avant toute écriture : chaque sommet sur la
# grille de 5 cm, chaque normale alignée sur un axe ; godot_check lance
# ensuite tools/voxel_check.gd sur le .glb écrit (vérificateur du jeu).
import bpy, math, os, subprocess
import numpy as np
from mathutils import Vector

CUBE = 0.05
MATERIALS = ("skin", "eye", "cloth", "leather", "metal", "wound", "bone")
# Normales des six faces d'un cube.
DIRS = {
    "+x": (1, 0, 0), "-x": (-1, 0, 0),
    "+y": (0, 1, 0), "-y": (0, -1, 0),
    "+z": (0, 0, 1), "-z": (0, 0, -1),
}
# Ombrage peint par défaut (shade) : dessus clair, côtés un peu plus sombres,
# dessous dans l'ombre (comme une planche en cubes éclairée de face).
SHADE = {"+z": 1.06, "-z": 0.62, "+x": 0.86, "-x": 0.86, "-y": 1.0, "+y": 0.94}


class Voxel:
    __slots__ = ("mat", "bone", "part", "color")

    def __init__(self, mat, bone, part, color):
        self.mat, self.bone, self.part, self.color = mat, bone, part, color


class Model:
    """Grille de voxels : cellule (x, y, z) -> Voxel(matière, os, partie,
    couleur sRGB). `part` : nom libre (zone de peinture et de comblement)."""

    def __init__(self):
        self.vox = {}
        # Surcharges par face : (x, y, z, dir) -> couleur sRGB / matière.
        self.face_color = {}
        self.face_mat = {}

    # --- description ------------------------------------------------------
    def set(self, x, y, z, mat, bone=None, part=None, color=(0.5, 0.5, 0.5)):
        assert mat in MATERIALS, mat
        self.vox[(int(x), int(y), int(z))] = Voxel(mat, bone, part or mat, tuple(color))

    def box(self, x0, x1, y0, y1, z0, z1, mat, bone=None, part=None, color=(0.5, 0.5, 0.5)):
        """Pavé de cellules [x0, x1) × [y0, y1) × [z0, z1) (cubes entiers) ;
        écrase les cellules déjà là."""
        for x in range(int(x0), int(x1)):
            for y in range(int(y0), int(y1)):
                for z in range(int(z0), int(z1)):
                    self.set(x, y, z, mat, bone, part, color)

    def clear(self, x0, x1, y0, y1, z0, z1):
        for x in range(int(x0), int(x1)):
            for y in range(int(y0), int(y1)):
                for z in range(int(z0), int(z1)):
                    self.vox.pop((x, y, z), None)

    def layers(self, rows, origin, legend, bone=None, part=None):
        """Grilles colorées par couche : rows[k] = couche z = origin.z + k,
        liste de chaînes (une par Y, de origin.y vers +Y), un caractère par
        X ; legend : caractère -> (matière, couleur) ; « . » ou espace = vide."""
        ox, oy, oz = origin
        for k, layer in enumerate(rows):
            for j, line in enumerate(layer):
                for i, ch in enumerate(line):
                    if ch in legend:
                        mat, col = legend[ch]
                        self.set(ox + i, oy + j, oz + k, mat, bone, part, col)

    def bounds(self):
        a = np.array(list(self.vox.keys()))
        return a.min(0), a.max(0) + 1

    # --- faces --------------------------------------------------------------
    def exposed(self, between_bones=True):
        """Faces à créer : [(cellule, dir)] (voisin vide, ou d'un autre os)."""
        out = []
        for c, v in self.vox.items():
            for d, n in DIRS.items():
                nb = self.vox.get((c[0] + n[0], c[1] + n[1], c[2] + n[2]))
                if nb is None or (between_bones and nb.bone != v.bone):
                    out.append((c, d))
        return out

    def blocker(self, c, d, reach=64):
        """Premier voxel rencontré depuis la face (c, d) dans sa direction
        (ce qui la cache à une caméra placée de ce côté), ou None."""
        n = DIRS[d]
        for k in range(1, reach):
            v = self.vox.get((c[0] + n[0] * k, c[1] + n[1] * k, c[2] + n[2] * k))
            if v is not None:
                return v
        return None

    def color_of(self, c, d):
        return self.face_color.get((c[0], c[1], c[2], d), self.vox[c].color)

    def mat_of(self, c, d):
        return self.face_mat.get((c[0], c[1], c[2], d), self.vox[c].mat)


# ---------------------------------------------------------------------------
# Peinture : projection depuis des vues de référence, comblement, ombrage,
# réduction de palette.
# ---------------------------------------------------------------------------

class View:
    """Vue orthographique d'une planche de référence : image (H, W, 3) en
    sRGB 0..1, direction de la caméra (« -y » : caméra devant le modèle),
    axe horizontal de l'écran (vecteur en cubes), échelle (pixels par cube),
    pixel du point (0, 0, 0) du modèle (u0, v0 ; v vers le bas)."""

    def __init__(self, name, img, cam_dir, right, scale, u0, v0, ok=None):
        self.name, self.img, self.cam_dir = name, img, cam_dir
        self.right = np.array(right, float)
        self.s, self.u0, self.v0 = scale, u0, v0
        # Masque des pixels prélevables (None : tous).
        self.ok = ok if ok is not None else np.ones(img.shape[:2], bool)

    def proj(self, p):
        p = np.asarray(p, float)
        return self.u0 + self.s * float(p @ self.right), self.v0 - self.s * float(p[2])


def silhouette(model, view, shape):
    """Masque (H, W) de la projection du modèle dans la vue (cellules)."""
    h, w = shape
    m = np.zeros((h, w), bool)
    corners = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    for c in model.vox:
        pts = [view.proj((c[0] + a, c[1] + b, c[2] + e)) for a, b, e in corners]
        us, vs = [p[0] for p in pts], [p[1] for p in pts]
        u0, u1 = int(round(min(us))), int(round(max(us)))
        v0, v1 = int(round(min(vs))), int(round(max(vs)))
        m[max(0, v0):max(0, v1), max(0, u0):max(0, u1)] = True
    return m


def register(model, view, mask, du=40, dv=6):
    """Décale la vue (pixels) pour que la silhouette du modèle recouvre au
    mieux le masque de la planche (IoU) ; renvoie l'IoU."""
    m = silhouette(model, view, mask.shape)
    best = (-1.0, 0, 0)
    for dy in range(-dv, dv + 1):
        mv = np.roll(m, dy, axis=0)
        for dx in range(-du, du + 1):
            mm = np.roll(mv, dx, axis=1)
            iou = (mm & mask).sum() / max(1, (mm | mask).sum())
            if iou > best[0]:
                best = (iou, dx, dy)
    view.u0 += best[1]
    view.v0 += best[2]
    return best[0]


def _dominant(px):
    """Couleur dominante : teinte la plus fréquente (pas de 1/12), moyennée."""
    keys = np.round(px * 12).astype(np.int32)
    _, inv, counts = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
    return px[inv.ravel() == int(np.argmax(counts))].mean(axis=0)


def paint_from_views(model, views, accept=None, inset=0.2, min_ok=0.3):
    """Chaque face tournée vers une vue (même direction que sa caméra) et que
    rien ne cache prend la couleur dominante de sa case de 5 cm projetée
    (rétrécie de `inset` de chaque côté). `accept(view, cell, dir, pixels
    (N, 3)) -> masque booléen (N)` filtre les pixels (matière...). Renvoie
    l'ensemble des faces peintes."""
    by_dir = {v.cam_dir: v for v in views}
    painted = set()
    for c, d in model.exposed(between_bones=False):
        view = by_dir.get(d)
        if view is None or model.blocker(c, d) is not None:
            continue
        n = np.array(DIRS[d])
        a = [i for i in range(3) if n[i] == 0]
        us, vs = [], []
        for s0 in (inset, 1 - inset):
            for s1 in (inset, 1 - inset):
                p = np.array(c, float) + np.where(n > 0, 1.0, 0.0)
                p[a[0]] = c[a[0]] + s0
                p[a[1]] = c[a[1]] + s1
                u, v = view.proj(p)
                us.append(u)
                vs.append(v)
        h, w = view.img.shape[:2]
        u0, u1 = max(0, int(min(us))), min(w, int(math.ceil(max(us))))
        v0, v1 = max(0, int(min(vs))), min(h, int(math.ceil(max(vs))))
        if u1 <= u0 or v1 <= v0:
            continue
        px = view.img[v0:v1, u0:u1].reshape(-1, 3)
        ok = view.ok[v0:v1, u0:u1].ravel()
        if accept is not None:
            ok = ok & accept(view, c, d, px)
        if ok.sum() < max(1, min_ok * ok.size):
            continue
        model.face_color[(c[0], c[1], c[2], d)] = tuple(float(x) for x in _dominant(px[ok]))
        painted.add((c, d))
    return painted


def fill_unpainted(model, painted, interior=0.55, reach=3.0):
    """Faces non peintes (dessus, dessous, faces cachées) : couleur de la
    face peinte la plus proche de la même partie (même direction d'abord,
    jusqu'à `reach` cubes, puis n'importe laquelle) ; faces cachées par leur
    propre partie (intérieur d'une jupe...) : teinte médiane assombrie."""
    from mathutils.kdtree import KDTree
    parts = {}
    for c, d in model.exposed():
        parts.setdefault(model.vox[c].part, []).append((c, d))
    for part, faces in parts.items():
        done = [(c, d) for c, d in faces if (c, d) in painted]
        if not done:
            continue
        cols = np.array([model.face_color[(c[0], c[1], c[2], d)] for c, d in done])
        med = tuple(np.median(cols, axis=0))

        def centre(c, d):
            n = DIRS[d]
            return Vector((c[0] + 0.5 + 0.5 * n[0], c[1] + 0.5 + 0.5 * n[1], c[2] + 0.5 + 0.5 * n[2]))

        trees = {}
        for key in list(DIRS) + ["*"]:
            sel = [i for i, (c, d) in enumerate(done) if key == "*" or d == key]
            if not sel:
                continue
            kd = KDTree(len(sel))
            for k, i in enumerate(sel):
                kd.insert(centre(*done[i]), k)
            kd.balance()
            trees[key] = (kd, sel)
        for c, d in faces:
            if (c, d) in painted:
                continue
            b = model.blocker(c, d, reach=16)
            if b is not None and b.part == part and d[1] != "z":
                model.face_color[(c[0], c[1], c[2], d)] = tuple(x * interior for x in med)
                continue
            p = centre(c, d)
            col = None
            if d in trees:
                kd, sel = trees[d]
                _, k, dist = kd.find(p)
                if dist <= reach:
                    col = model.face_color[(done[sel[k]][0] + (done[sel[k]][1],))]
            if col is None:
                kd, sel = trees["*"]
                _, k, dist = kd.find(p)
                col = model.face_color[(done[sel[k]][0] + (done[sel[k]][1],))]
            model.face_color[(c[0], c[1], c[2], d)] = col


def shade(model, factors=None, skip_mats=("eye",)):
    """Ombrage peint : multiplie la couleur de chaque face selon sa direction."""
    f = factors or SHADE
    for c, d in model.exposed():
        if model.mat_of(c, d) in skip_mats:
            continue
        col = model.color_of(c, d)
        model.face_color[(c[0], c[1], c[2], d)] = tuple(min(1.0, x * f[d]) for x in col)


def quantize(model, k_per_mat, iters=12, seed=1):
    """Réduit les couleurs des faces à `k` teintes par matière (k-moyennes) :
    plus de faces voisines identiques, donc fusionnées. {matière: k}."""
    rng = np.random.default_rng(seed)
    faces = model.exposed()
    by_mat = {}
    for c, d in faces:
        by_mat.setdefault(model.mat_of(c, d), []).append((c, d))
    for mat, fs in by_mat.items():
        k = k_per_mat.get(mat)
        if not k:
            continue
        X = np.array([model.color_of(c, d) for c, d in fs], float)
        uniq = np.unique(np.round(X, 4), axis=0)
        if len(uniq) <= k:
            continue
        cent = uniq[rng.choice(len(uniq), k, replace=False)]
        for _ in range(iters):
            lab = np.argmin(((X[:, None, :] - cent[None]) ** 2).sum(2), axis=1)
            for j in range(k):
                if (lab == j).any():
                    cent[j] = X[lab == j].mean(0)
        lab = np.argmin(((X[:, None, :] - cent[None]) ** 2).sum(2), axis=1)
        for (c, d), j in zip(fs, lab):
            model.face_color[(c[0], c[1], c[2], d)] = tuple(float(x) for x in cent[j])


# ---------------------------------------------------------------------------
# Maillage.
# ---------------------------------------------------------------------------

def _quad(d, plane, a0, a1, b0, b1):
    """Coins (en cubes) d'un rectangle de la face `d` au plan `plane`,
    [a0, a1] × [b0, b1] sur les deux autres axes, ordre sortant."""
    n = DIRS[d]
    ax = [i for i in range(3) if n[i] == 0]
    pts = []
    for a, b in ((a0, b0), (a1, b0), (a1, b1), (a0, b1)):
        p = [0, 0, 0]
        p[ax[0]], p[ax[1]] = a, b
        p[[i for i in range(3) if n[i] != 0][0]] = plane
        pts.append(Vector(p))
    nn = (pts[1] - pts[0]).cross(pts[3] - pts[0])
    if nn.dot(Vector(n)) < 0:
        pts.reverse()
    return pts


def merge_faces(model, merge=True):
    """Rectangles [(dir, coins, os, matière, couleur)] : faces exposées
    regroupées par plan, os, matière et couleur, fusionnées en rectangles."""
    groups = {}
    for c, d in model.exposed():
        n = DIRS[d]
        k = [i for i in range(3) if n[i] != 0][0]
        ax = [i for i in range(3) if n[i] == 0]
        plane = c[k] + (1 if n[k] > 0 else 0)
        col = tuple(round(x, 4) for x in model.color_of(c, d))
        key = (d, plane, model.vox[c].bone, model.mat_of(c, d), col)
        groups.setdefault(key, set()).add((c[ax[0]], c[ax[1]]))
    rects = []
    for (d, plane, bone, mat, col), cells in groups.items():
        left = set(cells)
        for a, b in sorted(cells):
            if (a, b) not in left:
                continue
            a1 = a + 1
            if merge:
                while (a1, b) in left:
                    a1 += 1
            b1 = b + 1
            if merge:
                while all((i, b1) in left for i in range(a, a1)):
                    b1 += 1
            for i in range(a, a1):
                for j in range(b, b1):
                    left.discard((i, j))
            rects.append((d, _quad(d, plane, a, a1, b, b1), bone, mat, col))
    return rects


def _material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    if name == "eye":
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


def build_mesh(model, name, merge=True):
    """Objet Blender du modèle (mètres) : un maillage, couleurs « Col » par
    coin, matériaux nommés, groupes de sommets par os (poids 1). Renvoie
    (objet, infos)."""
    rects = merge_faces(model, merge)
    verts, polys, mats, bones, cols = [], [], [], [], []
    used = [m for m in MATERIALS if any(r[3] == m for r in rects)]
    for d, quad, bone, mat, col in rects:
        polys.append(tuple(range(len(verts), len(verts) + 4)))
        verts += [p * CUBE for p in quad]
        mats.append(used.index(mat))
        bones.append(bone)
        cols.append(col)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], polys)
    me.validate()
    for m in used:
        me.materials.append(_material(m))
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = 0
    for p, mi, col in zip(me.polygons, mats, cols):
        p.material_index = mi
        p.use_smooth = False
        for li in p.loop_indices:
            ca.data[li].color_srgb = (col[0], col[1], col[2], 1.0)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if any(b is not None for b in bones):
        vg = {}
        for p, b in zip(me.polygons, bones):
            assert b is not None, "cellule sans os dans un modèle animé"
            if b not in vg:
                vg[b] = ob.vertex_groups.new(name=b)
            vg[b].add(list(p.vertices), 1.0, "REPLACE")
    info = {"cells": len(model.vox), "faces": len(model.exposed()), "rects": len(rects),
            "tris": 2 * len(rects), "colors": len(set(cols)), "materials": used}
    return ob, info


def build_armature(name, bones):
    """Squelette : bones = [(nom, parent, tête, bout)] en cubes (os droits
    conseillés : bout aligné sur un axe)."""
    arm = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for b, parent, head, tail in bones:
        eb = arm.edit_bones.new(b)
        eb.head = Vector(head) * CUBE
        eb.tail = Vector(tail) * CUBE
        eb.roll = 0.0
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def bind(ob, rig):
    """Lie le maillage au squelette (groupes de sommets = noms des os)."""
    ob.parent = rig
    ob.modifiers.new("Armature", "ARMATURE").object = rig


def self_check(ob, tol=1e-4):
    """Vérification avant écriture : sommets sur la grille de 5 cm (repère de
    l'objet, au repos), normales de faces alignées sur un axe, poids rigides.
    Lève AssertionError avec le premier défaut."""
    me = ob.data
    for v in me.vertices:
        for x in v.co:
            q = x / CUBE
            assert abs(q - round(q)) * CUBE < tol, "sommet hors grille : %s" % tuple(v.co)
    for p in me.polygons:
        n = p.normal
        assert max(abs(n.x), abs(n.y), abs(n.z)) > 0.9999, "face oblique : %s" % tuple(n)
    if ob.vertex_groups:
        for v in me.vertices:
            ws = [g.weight for g in v.groups if g.weight > 0]
            assert len(ws) == 1 and abs(ws[0] - 1.0) < 1e-6, "poids non rigide (sommet %d)" % v.index
    return True


def export_glb(path, objects):
    """Exporte en .glb (Y en haut, peau si squelette, couleurs par sommet),
    après self_check de chaque maillage."""
    for o in objects:
        if o.type == "MESH":
            self_check(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
              export_skins=True, export_animations=False, export_morph=False,
              export_materials="EXPORT", export_normals=True, export_texcoords=False,
              export_apply=False)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw, export_colors=True)
    return path


def godot_check(path, animated, godot=None, root=None):
    """Lance tools/voxel_check.gd (Godot sans fenêtre) sur le .glb : True si
    conforme. `godot` : exécutable (défaut : variable GODOT, sinon « godot »)."""
    root = root or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    exe = godot or os.environ.get("GODOT", "godot")
    rel = os.path.relpath(os.path.abspath(path), root).replace("\\", "/")
    cmd = [exe, "--headless", "--path", root, "-s", "res://tools/voxel_check.gd", "--",
           "res://" + rel, "--anime" if animated else "--statique"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    out = "\n".join(l for l in r.stdout.splitlines() if "voxel_check" in l or l.startswith("  "))
    print(out)
    return r.returncode == 0


# ---------------------------------------------------------------------------
# Rendus de contrôle (planches de validation).
# ---------------------------------------------------------------------------

def setup_render(size=(360, 640)):
    """Scène de rendu neutre : EEVEE, fond gris, deux soleils, caméra
    orthographique « VoxCam »."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = size
    # Fond posé après coup (load_png) : le monde éclaire peu, les côtés des
    # cubes restent lisibles.
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bgn = sc.world.node_tree.nodes.get("Background")
    bgn.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bgn.inputs["Strength"].default_value = 0.35
    cam = bpy.data.objects.get("VoxCam")
    if cam is None:
        cam = bpy.data.objects.new("VoxCam", bpy.data.cameras.new("VoxCam"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    for name, rot, energy in (("VoxKey", (45, 0, 30), 3.2), ("VoxFill", (75, 0, -140), 0.9)):
        lt = bpy.data.objects.get(name)
        if lt is None:
            lt = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
            sc.collection.objects.link(lt)
        lt.data.energy = energy
        lt.rotation_euler = [math.radians(a) for a in rot]
    sc.camera = cam
    return sc, cam


def render_view(path, azimuth, target, ortho, elev=0.0, dist=6.0):
    """Rendu orthographique : `azimuth` en degrés (0 = de face, caméra en -Y ;
    90 = côté gauche du personnage, caméra en +X), `target` (m), `ortho`
    (hauteur visible, m)."""
    sc, cam = bpy.context.scene, bpy.data.objects["VoxCam"]
    a, e = math.radians(azimuth), math.radians(elev)
    t = Vector(target)
    pos = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.location = pos
    cam.rotation_euler = (t - pos).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = ortho * max(1.0, sc.render.resolution_x / sc.render.resolution_y)
    # Lumières attachées à la caméra (chaque vue éclairée comme une planche
    # dessinée : clé en haut à gauche de la caméra, débouchage à droite).
    for name, rx, dz in (("VoxKey", 45, 30), ("VoxFill", 75, -140)):
        lt = bpy.data.objects.get(name)
        if lt is not None:
            lt.rotation_euler = (math.radians(rx), 0.0, a + math.radians(dz))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def load_png(path, bg=(0.56, 0.56, 0.56)):
    """Image PNG -> tableau (H, W, 3) sRGB 0..1, ligne 0 en haut ; la
    transparence est remplie par le fond `bg`."""
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1].copy()
    bpy.data.images.remove(im)
    al = a[..., 3:4]
    return a[..., :3] * al + np.array(bg, np.float32) * (1 - al)


def save_png(a, path):
    """Tableau (H, W, 3) sRGB 0..1 (ligne 0 en haut) -> PNG."""
    h, w = a.shape[:2]
    im = bpy.data.images.new("vx_out", w, h, alpha=False)
    px = np.ones((h, w, 4), np.float32)
    px[..., :3] = np.clip(a[::-1], 0, 1)
    im.pixels = px.ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    im.save()
    bpy.data.images.remove(im)
    return path


def fit(a, w, h, bg=(0.56, 0.56, 0.56)):
    """Redimensionne (au plus proche) en gardant les proportions, centré
    dans une case w × h."""
    ih, iw = a.shape[:2]
    s = min(w / iw, h / ih)
    nw, nh = max(1, int(iw * s)), max(1, int(ih * s))
    ys = np.minimum((np.arange(nh) / s).astype(int), ih - 1)
    xs = np.minimum((np.arange(nw) / s).astype(int), iw - 1)
    out = np.empty((h, w, 3), np.float32)
    out[:] = bg
    oy, ox = (h - nh) // 2, (w - nw) // 2
    out[oy:oy + nh, ox:ox + nw] = a[ys][:, xs]
    return out


def sheet(rows, w, h, gap=8, bg=(0.3, 0.3, 0.3)):
    """Planche : rows = [[image (H, W, 3)...]...], chaque image dans une case."""
    nr, nc = len(rows), max(len(r) for r in rows)
    out = np.empty((nr * h + (nr + 1) * gap, nc * w + (nc + 1) * gap, 3), np.float32)
    out[:] = bg
    for i, r in enumerate(rows):
        for j, im in enumerate(r):
            y, x = gap + i * (h + gap), gap + j * (w + gap)
            out[y:y + h, x:x + w] = fit(im, w, h)
    return out
