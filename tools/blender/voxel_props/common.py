# Outils communs des DÉCORS CUBIQUES de l'éditeur de cartes (cubes de 5 cm,
# GAME_CONCEPT.md § 4.19, docs/VOXEL_DECOR_PLAN.md « Marche à suivre ») :
# chaque script de famille (mobilier.py, effets.py...) décrit ses décors en
# cellules avec tools/blender/voxel/voxel_lib.py et appelle main(BUILDERS).
#
#   sh tools/blender.sh tools/blender/voxel_props/<famille>.py [ids...] [--sheet DOSSIER] [--before DOSSIER] [--no-check]
#
#   ids        décors à construire (défaut : tous ceux de la famille)
#   --sheet    planche de validation par décor : <DOSSIER>/<id>.png
#              (trois-quarts et face, contour noir ; rangée « avant » si
#              l'ancien modèle est donné par --before)
#   --before   dossier des anciens .glb (non cubiques) : <DOSSIER>/<ancien>.glb
#              (clé BEFORE de la famille : id -> nom de l'ancien modèle)
#   --no-check ne lance pas tools/voxel_check.gd (Godot) après l'export
#
# Conventions (lues par le jeu, MeshMapBuilder) :
#   - .glb dans assets/models/props/voxel/<id>.glb, <id> = identifiant du
#     catalogue (MapCatalog.PREFABS / LIGHTS) ; le catalogue le cite
#     « model »: "voxel/<id>" ;
#   - un seul objet « voxel__<id>__<type> » (type « block » : projette une
#     ombre ; « ns » : sans ombre), matériau du jeu « voxel » (couleur de
#     face, faces « glow » émissives) ;
#   - repère Blender : Z en haut, avant vers -Y (= +Z Godot), origine AU MÊME
#     ENDROIT que l'ancien modèle (centre de l'emprise, au sol ; décor mural :
#     face du mur ; plafond : sous le plafond), pour que les collisions du
#     catalogue ou de <id>.collision.json (repère Godot : x, y = z Blender,
#     z = -y Blender) restent justes ;
#   - AUCUNE collision dans le .glb (CollisionBox du catalogue ou
#     <id>.collision.json, jamais modifiées par la conversion).
import math, os, sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_DECOR
OUT_DIR = os.path.join(ROOT, "assets", "models", "props", "voxel")
PAL = vx.DECOR_PALETTE


def col(name, f=1.0):
    """Teinte de la palette du décor (sRGB), multipliée par `f`."""
    return vx.tone(PAL[name], f)


def grain(c, base, seed=0, amp=0.07, levels=3):
    """Texture « un pixel = un cube » : la teinte `base` éclaircie ou
    assombrie par cube (bruit déterministe, `levels` paliers de ±amp) ; peu
    de paliers : les faces voisines identiques restent fusionnées."""
    k = min(levels - 1, int(vx.noise(c, seed) * levels))
    f = 1.0 + amp * (2.0 * k / max(1, levels - 1) - 1.0)
    return vx.tone(base, f)


def fill(m, x0, x1, y0, y1, z0, z1, mat, base, seed=0, amp=0.07, levels=3, keep=None):
    """Pavé [x0, x1) × [y0, y1) × [z0, z1) de cellules texturées (grain).
    `keep(x, y, z)` : filtre facultatif (formes arrondies en escalier)."""
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                if keep is None or keep(x, y, z):
                    m.set(x, y, z, mat, color=grain((x, y, z), base, seed, amp, levels))


def paint(m, cells_dirs, color):
    """Couleur d'une face de cube pour chaque (cellule, direction) donnée
    (étiquettes, bandes peintes) : aucune géométrie ajoutée."""
    for c, d in cells_dirs:
        if c in m.vox:
            m.face_color[(c[0], c[1], c[2], d)] = color


def export_prop(m, pid, kind="block", shade=True):
    """Ombrage peint, maillage, auto-vérification et export du décor `pid` :
    assets/models/props/voxel/<pid>.glb. Renvoie (objet, infos)."""
    if shade:
        vx.shade(m)
    ob, info = vx.build_mesh(m, "voxel__%s__%s" % (pid, kind))
    path = os.path.join(OUT_DIR, pid + ".glb")
    vx.export_glb(path, [ob], CUBE)
    lo, hi = m.bounds()
    info["size_m"] = tuple(round(float(h - l) * CUBE, 3) for l, h in zip(lo, hi))
    info["min_m"] = tuple(round(float(l) * CUBE, 3) for l in lo)
    print("[voxel_props] %-16s %5d cellules %5d triangles %3d teintes  taille %s m (x, y, z Blender)  coin %s"
          % (pid, info["cells"], info["tris"], info["colors"], info["size_m"], info["min_m"]))
    return ob, info


def _frame(objs):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    c = tuple((a + b) / 2 for a, b in zip(lo, hi))
    size = max(hi[i] - lo[i] for i in range(3))
    return c, size


VIEWS = (("trois-quarts", 35.0, 28.0), ("face", 0.0, 0.0))


def _render_set(objs, tmp, tag, frame):
    c, size = frame
    out = []
    for name, az, el in VIEWS:
        p = os.path.join(tmp, "%s_%s.png" % (tag, name))
        vx.render_view(p, az, c, size * 1.35, elev=el, dist=20.0)
        out.append(vx.load_png(p))
    return out


def board(pid, m, ob, sheet_dir, before_glb=None):
    """Planche de validation <sheet_dir>/<pid>.png : rangée « après » (le
    modèle cubique, contour noir), et rangée « avant » (ancien .glb) si
    `before_glb` est donné ; trois-quarts et face, même cadrage."""
    tmp = os.path.join(sheet_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    vx.setup_render((520, 520))
    outline = vx.add_outline(m, pid + "_outline", thickness=0.006)
    frame = _frame([ob])
    rows = [_render_set([ob], tmp, pid + "_apres", frame)]
    if before_glb and os.path.exists(before_glb):
        ob.hide_render = True
        outline.hide_render = True
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=before_glb)
        olds = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        rows.insert(0, _render_set(olds, tmp, pid + "_avant", frame))
        for o in olds:
            bpy.data.objects.remove(o)
        ob.hide_render = False
        outline.hide_render = False
    bpy.data.objects.remove(outline)
    path = os.path.join(sheet_dir, pid + ".png")
    vx.save_png(vx.sheet(rows, 520, 520), path)
    print("[voxel_props] planche : " + path)
    return path


def main(builders, before=None):
    """Point d'entrée d'un script de famille : `builders` {id: fonction() ->
    Model}, `before` {id: nom de l'ancien .glb} (planches avant / après)."""
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir = before_dir = ""
    check = True
    ids = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sheet":
            sheet_dir = os.path.abspath(args[i + 1])
            i += 1
        elif a == "--before":
            before_dir = os.path.abspath(args[i + 1])
            i += 1
        elif a == "--no-check":
            check = False
        else:
            ids.append(a)
        i += 1
    ids = ids or list(builders)
    bad = []
    for pid in ids:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        m = builders[pid]()
        ob, _info = export_prop(m, pid, kind=getattr(builders[pid], "kind", "block"))
        if sheet_dir:
            old = (before or {}).get(pid)
            board(pid, m, ob, sheet_dir, os.path.join(before_dir, old + ".glb") if (before_dir and old) else None)
        if check and not vx.godot_check(os.path.join(OUT_DIR, pid + ".glb"), animated=False):
            bad.append(pid)
    if bad:
        print("[voxel_props] NON CONFORMES : " + ", ".join(bad))
        sys.exit(1)
