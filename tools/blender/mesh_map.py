# Construit l'architecture d'une carte en maillage à partir de sa description
# JSON (assets/maps/<id>/layout.json) et l'exporte en .glb pour Godot.
#
#   sh tools/blender.sh tools/blender/mesh_map.py assets/maps/<id>/layout.json assets/maps/<id>/<id>.glb [aperçu.png]
#
# Coordonnées du JSON : repère Godot, en mètres (x à droite, y en haut, z vers
# le joueur). Blender est en Z vers le haut : (x, y, z) Godot -> (x, -z, y).
#
# Sorties (noms d'objets lus par MeshMapBuilder côté Godot) :
#   <matériau>__<salle>            maillage visible (matériau = clé de WorldLook.SURFACES)
#   <matériau>__<salle>__col-colonly  collision (Godot en fait un StaticBody3D)
# Les escaliers ont des marches visibles et une RAMPE de collision invisible
# (le joueur n'a pas de logique de montée de marche).
#
# Éléments du JSON utilisés ici :
#   rooms  : {id, outline [[x,z]...], floor (y) ou slope [[x,y,z] x3], ceiling,
#             floor_mat, ceiling_mat, no_ceiling}
#   walls  : {room, path [[x,z]...], closed, y0, y1, thick, mat,
#             openings [{seg, t (distance du début du segment au centre), w, y0, y1}]}
#   slabs  : {room, outline, y (dessus), thick, mat}   balcons, mezzanines
#   stairs : {room, a [x,y,z] (bas, milieu), b [x,y,z] (haut, milieu), w, mat}
#   rails  : {room, path [[x,z]...], y, h, mat}         garde-corps
import bpy, bmesh, json, math, sys
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREVIEW = args[2] if len(args) > 2 else ""
L = json.load(open(SRC, encoding="utf-8"))

# Couleurs d'aperçu seulement (Godot remplace par WorldLook.surface).
PALETTE = {
    "floor": (0.24, 0.23, 0.21), "wall": (0.36, 0.35, 0.32), "ceiling": (0.12, 0.12, 0.12),
    "concrete": (0.25, 0.24, 0.22), "wood": (0.24, 0.15, 0.09), "metal": (0.2, 0.21, 0.22),
    "carpet_red": (0.3, 0.035, 0.04), "marble": (0.46, 0.41, 0.34), "stage_wood": (0.27, 0.16, 0.08),
    "wall_theater": (0.3, 0.05, 0.06), "wall_lobby": (0.34, 0.25, 0.14), "brick": (0.3, 0.13, 0.08),
    "cobble": (0.2, 0.2, 0.21), "dark_wood": (0.13, 0.07, 0.035), "brass": (0.5, 0.36, 0.13),
}


def B(x, y, z):
    return Vector((x, -z, y))


_meshes = {}  # nom d'objet -> bmesh
# Type des objets en cours (floor, ceil, wall, slab, stair, rail) : sols et
# plafonds ne projettent pas d'ombre (MeshMapBuilder).
KIND = "wall"
_mats = {}


def material(name):
    if name not in _mats:
        m = bpy.data.materials.new(name)
        c = PALETTE.get(name, (0.4, 0.4, 0.4))
        m.diffuse_color = (*c, 1.0)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*c, 1.0)
        _mats[name] = m
    return _mats[name]


def bm_for(mat, room, col=False):
    key = "%s__%s__%s%s" % (mat, room, KIND, "__col-colonly" if col else "")
    if key not in _meshes:
        _meshes[key] = (bmesh.new(), mat)
    return _meshes[key][0]


def face(bm, pts):
    """Face (points Blender) ; renvoie la face créée."""
    vs = [bm.verts.new(p) for p in pts]
    return bm.faces.new(vs)


def box(bm, center, size, yaw):
    """Boîte orientée : center (Godot), size (longueur x, hauteur y, épaisseur z), yaw autour de y."""
    c, s = math.cos(yaw), math.sin(yaw)
    ux = Vector((c, 0, -s))   # axe « longueur » dans le plan (Godot)
    uz = Vector((s, 0, c))    # axe « épaisseur »
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    corners = []
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                g = Vector(center) + ux * (dx * hx) + Vector((0, dy * hy, 0)) + uz * (dz * hz)
                corners.append(B(g.x, g.y, g.z))
    v = [bm.verts.new(p) for p in corners]
    # index = (dx, dy, dz) en binaire
    def idx(dx, dy, dz):
        return ((dx > 0) << 2) | ((dy > 0) << 1) | (dz > 0)
    quads = [
        (idx(-1, -1, -1), idx(-1, -1, 1), idx(-1, 1, 1), idx(-1, 1, -1)),
        (idx(1, -1, -1), idx(1, 1, -1), idx(1, 1, 1), idx(1, -1, 1)),
        (idx(-1, -1, -1), idx(1, -1, -1), idx(1, -1, 1), idx(-1, -1, 1)),
        (idx(-1, 1, -1), idx(-1, 1, 1), idx(1, 1, 1), idx(1, 1, -1)),
        (idx(-1, -1, -1), idx(-1, 1, -1), idx(1, 1, -1), idx(1, -1, -1)),
        (idx(-1, -1, 1), idx(1, -1, 1), idx(1, 1, 1), idx(-1, 1, 1)),
    ]
    for q in quads:
        bm.faces.new([v[i] for i in q])


def both(mat, room, fn, *a):
    """Même géométrie en visible et en collision."""
    fn(bm_for(mat, room), *a)
    fn(bm_for(mat, room, True), *a)


def floor_height(room, x, z):
    if "slope" in room:
        (x1, y1, z1), (x2, y2, z2), (x3, y3, z3) = room["slope"]
        # Plan y = a x + b z + c passant par les trois points.
        det = (x1 - x3) * (z2 - z3) - (x2 - x3) * (z1 - z3)
        a = ((y1 - y3) * (z2 - z3) - (y2 - y3) * (z1 - z3)) / det
        b = ((x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3)) / det
        return a * (x - x3) + b * (z - z3) + y3
    return room.get("floor", 0.0)


def polygon(bm, outline, height_fn, up=True):
    f = face(bm, [B(x, height_fn(x, z), z) for x, z in outline])
    f.normal_update()
    if (f.normal.z > 0) != up:
        f.normal_flip()
    bmesh.ops.triangulate(bm, faces=[f])


# --------------------------------------------------------------------- salles
for r in L.get("rooms", []):
    KIND = "floor"
    fm = r.get("floor_mat", "floor")
    both(fm, r["id"], polygon, r["outline"], lambda x, z, r=r: floor_height(r, x, z), True)
    if not r.get("no_ceiling", False):
        KIND = "ceil"
        cm = r.get("ceiling_mat", "ceiling")
        polygon(bm_for(cm, r["id"]), r["outline"], lambda x, z, r=r: r["ceiling"], False)
        polygon(bm_for(cm, r["id"], True), r["outline"], lambda x, z, r=r: r["ceiling"], False)

# --------------------------------------------------------------------- murs
KIND = "wall"
for w in L.get("walls", []):
    pts = w["path"] + ([w["path"][0]] if w.get("closed") else [])
    t = w.get("thick", 0.3)
    y0, y1 = w["y0"], w["y1"]
    for si in range(len(pts) - 1):
        ax, az = pts[si]
        bx, bz = pts[si + 1]
        seg = Vector((bx - ax, 0, bz - az))
        length = seg.length
        d = seg / length
        yaw = math.atan2(-d.z, d.x)
        # Bouts prolongés d'une demi-épaisseur : angles fermés.
        cuts = sorted([o for o in w.get("openings", []) if o["seg"] == si], key=lambda o: o["t"])
        pieces = []  # (s0, s1, y0, y1)
        s = -t / 2
        for o in cuts:
            o0, o1 = o["t"] - o["w"] / 2, o["t"] + o["w"] / 2
            if o0 > s:
                pieces.append((s, o0, y0, y1))
            if o["y0"] > y0:
                pieces.append((o0, o1, y0, o["y0"]))
            if o["y1"] < y1:
                pieces.append((o0, o1, o["y1"], y1))
            s = o1
        pieces.append((s, length + t / 2, y0, y1))
        for s0, s1, py0, py1 in pieces:
            if s1 - s0 < 0.001 or py1 - py0 < 0.001:
                continue
            mid = (s0 + s1) / 2
            c = Vector((ax, (py0 + py1) / 2, az)) + d * mid
            both(w.get("mat", "wall"), w.get("room", "x"), box, (c.x, c.y, c.z), (s1 - s0, py1 - py0, t), yaw)

# --------------------------------------------------------------------- dalles
KIND = "slab"
for sl in L.get("slabs", []):
    th = sl.get("thick", 0.25)
    for bm in (bm_for(sl.get("mat", "wood"), sl["room"]), bm_for(sl.get("mat", "wood"), sl["room"], True)):
        top = [bm.verts.new(B(x, sl["y"], z)) for x, z in sl["outline"]]
        bot = [bm.verts.new(B(x, sl["y"] - th, z)) for x, z in sl["outline"]]
        ft = bm.faces.new(top)
        ft.normal_update()
        if ft.normal.z < 0:
            ft.normal_flip()
        fb = bm.faces.new(list(reversed(bot)))
        fb.normal_update()
        if fb.normal.z > 0:
            fb.normal_flip()
        n = len(top)
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new([bot[i], bot[j], top[j], top[i]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

# --------------------------------------------------------------------- escaliers
KIND = "stair"
for st in L.get("stairs", []):
    a, b, w = Vector(st["a"]), Vector(st["b"]), st.get("w", 1.5)
    run = Vector((b.x - a.x, 0, b.z - a.z))
    rise = b.y - a.y
    n = max(1, round(abs(rise) / 0.18))
    d = run.normalized()
    yaw = math.atan2(-d.z, d.x)
    side = Vector((d.z, 0, -d.x))
    mat, room = st.get("mat", "wood"), st["room"]
    step_run = run.length / n
    for i in range(n):
        top = a.y + rise * (i + 1) / n
        c = a + d * (step_run * (i + 0.5))
        # Marche pleine jusqu'au sol du bas : pas de vide sous l'escalier.
        box(bm_for(mat, room), (c.x, (a.y + top) / 2, c.z), (step_run, top - a.y, w), yaw)
    # Collision : coin plein (rampe du nez de la première marche au palier du
    # haut, dessous fermé) ; le joueur monte la pente sans logique de marche.
    col = bm_for(mat, room, True)
    lo = Vector((b.x, a.y, b.z))
    pts = [a - side * (w / 2), a + side * (w / 2), b + side * (w / 2), b - side * (w / 2),
           lo + side * (w / 2), lo - side * (w / 2)]
    v = [col.verts.new(B(p.x, p.y, p.z)) for p in pts]
    for q in ((0, 1, 2, 3), (3, 2, 4, 5), (0, 5, 4, 1), (0, 3, 5), (1, 4, 2)):
        col.faces.new([v[i] for i in q])
    bmesh.ops.recalc_face_normals(col, faces=col.faces[:])

# --------------------------------------------------------------------- garde-corps
KIND = "rail"
for rl in L.get("rails", []):
    pts = rl["path"]
    h = rl.get("h", 1.0)
    for i in range(len(pts) - 1):
        ax, az = pts[i]
        bx, bz = pts[i + 1]
        seg = Vector((bx - ax, 0, bz - az))
        d = seg.normalized()
        yaw = math.atan2(-d.z, d.x)
        c = Vector((ax, 0, az)) + seg / 2
        mat, room = rl.get("mat", "dark_wood"), rl["room"]
        # Main courante, lisse du bas, et un bloc de collision plein.
        box(bm_for(mat, room), (c.x, rl["y"] + h, c.z), (seg.length, 0.08, 0.1), yaw)
        box(bm_for(mat, room), (c.x, rl["y"] + 0.1, c.z), (seg.length, 0.08, 0.1), yaw)
        nb = max(1, int(seg.length / 0.3))
        for k in range(nb + 1):
            p = Vector((ax, 0, az)) + seg * (k / nb)
            box(bm_for(mat, room), (p.x, rl["y"] + h / 2, p.z), (0.05, h, 0.05), yaw)
        box(bm_for(mat, room, True), (c.x, rl["y"] + h / 2, c.z), (seg.length, h, 0.1), yaw)

# --------------------------------------------------------------------- export
bpy.ops.wm.read_factory_settings(use_empty=True)
for key, (bm, mat) in sorted(_meshes.items()):
    me = bpy.data.meshes.new(key)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(mat))
    ob = bpy.data.objects.new(key, me)
    bpy.context.scene.collection.objects.link(ob)
for ob in bpy.context.scene.objects:
    ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True)
print("[mesh_map] %d objets exportés -> %s" % (len(_meshes), OUT))

if PREVIEW:
    # Vue plongeante d'aperçu (contrôle rapide de la forme).
    xs = [p[0] for r in L.get("rooms", []) for p in r["outline"]]
    zs = [p[1] for r in L.get("rooms", []) for p in r["outline"]]
    cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    span = max(max(xs) - min(xs), max(zs) - min(zs))
    for ob in list(bpy.context.scene.objects):
        if ob.name.endswith("-colonly") or ob.name.startswith("ceiling"):
            bpy.data.objects.remove(ob)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.location = B(cx - span * 0.6, span * 0.9, cz + span * 0.9)
    cam.rotation_euler = (math.radians(50), 0, math.radians(-35))
    cam.data.lens = 24
    bpy.context.scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(35), math.radians(15), 0)
    bpy.context.scene.collection.objects.link(sun)
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = 960, 640
    sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("[mesh_map] aperçu -> %s" % PREVIEW)
