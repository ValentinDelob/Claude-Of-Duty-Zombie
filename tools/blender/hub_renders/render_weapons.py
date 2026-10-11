# Rendus des armes en cubes pour le hub (ARSENAL, ÉQUIPEMENT, butin) : un PNG
# transparent 560 × 280 par modèle de assets/models/weapons/voxel/ (armes à
# feu, batte, couteau, grenade, peluche leurre), vue de profil droit
# légèrement de 3/4 et du dessus, CANON VERS LA DROITE, contour noir, même
# éclairage pour toute la série (clé chaude, débouchage froid, contre-jour
# sarcelle de l'interface).
#
#   sh tools/blender.sh tools/blender/hub_renders/render_weapons.py --out DIR [--only id,id]
#
# Ignorés : hands.glb (mains de la vue FPS), round_*.glb (projectiles).
import bpy, json, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hub_common as hc  # noqa: E402

W, H = 560, 280
SRC = os.path.join("assets", "models", "weapons", "voxel")
SKIP = ("hands",)
SKIP_PREFIX = ("round_",)
MARGIN = 0.10          # marge autour de l'arme (part du cadre)
OUTLINE = 0.010        # épaisseur du contour (part de la longueur de l'arme)
# Objets qui ne sont pas des armes longues : vus de 3/4 FACE (part de l'avant
# dans la direction de vue ; armes : 0,28 = profil à peine tourné).
FRONT = {"teddy": -1.3, "frag": 0.9}  # la peluche regarde -Y (Blender)


def weapon_ids():
    ids = []
    for f in sorted(os.listdir(SRC)):
        if not f.endswith(".glb"):
            continue
        n = f[:-4]
        if n in SKIP or n.startswith(SKIP_PREFIX):
            continue
        ids.append(n)
    return ids


def muzzle_sign(spec):
    """+1 si la bouche du canon est vers -Z de Godot (= +Y de Blender)."""
    m = spec.get("anchors", {}).get("muzzle")
    if m is None:
        return 1.0
    return 1.0 if m[2] <= 0.0 else -1.0


def render_one(n, spec, out_dir):
    sc = hc.reset(W, H, 0.6)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, n + ".glb"))
    hc.drop_helpers(min_verts=0)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    lo, hi, pts = hc.bounds(meshes)
    center, size = (lo + hi) / 2, hi - lo
    for o in sc.objects:
        if o.parent is None:
            o.location -= center
    pts = [p - center for p in pts]
    length = max(size.x, size.y)
    # Le canon suit l'axe Y de Blender (-Z de Godot) ; la caméra regarde le
    # flanc droit (+X), donc +Y apparaît à droite de l'image.
    s = muzzle_sign(spec)
    side = Vector((s, 0, 0))
    fwd = Vector((0, s, 0))
    dirv = (side + fwd * FRONT.get(n, 0.28) + Vector((0, 0, 0.32))).normalized()
    cam = hc.ortho_camera(sc, (0, 0, 0), dirv, length * 4, length)
    bpy.context.view_layer.update()
    hc.fit_ortho(cam, pts, W, H, MARGIN)
    hc.outline(meshes, length * OUTLINE)
    L = length
    hc.light("key", tuple(dirv * L * 2 + Vector((0, 0, L * 1.5)) + fwd * L), (0, 0, 0),
             260 * L * L, L * 1.5, (1.0, 0.96, 0.9))
    hc.light("fill", tuple(dirv * L * 2 - fwd * L * 1.5), (0, 0, 0), 120 * L * L, L * 2, (0.75, 0.85, 1.0))
    hc.light("rim", tuple(-side * L * 2 + Vector((0, 0, L))), (0, 0, 0), 500 * L * L, L, (0.6, 1.0, 0.95))
    hc.render(sc, os.path.join(out_dir, n + ".png"))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[args.index("--out") + 1])
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(SRC, "weapons_voxel.json"), encoding="utf-8") as f:
        specs = json.load(f)
    for n in weapon_ids():
        if only and n not in only:
            continue
        render_one(n, specs.get(n, {}), out_dir)


main()
