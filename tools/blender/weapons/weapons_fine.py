# ARMES FINES EN CUBES DE 1,25 CM (refonte des armes, une par une) :
# chaque arme reprend une ARME RÉELLE de référence (fiche docs/weapons/<id>.md,
# nom affiché proche du vrai), en cubes DEUX FOIS PLUS PETITS que les
# personnages (exception validée le 2026-10-12 : 1,25 cm, sous-multiple
# exact de 2,5 cm ; les mains de la vue FPS restent en 2,5 cm).
#
#   sh tools/blender.sh tools/blender/weapons/weapons_fine.py [ids...] [--sheet DOSSIER] [--export] [--no-check]
#
#   ids        armes à construire (défaut : toutes celles de BUILDERS)
#   --sheet    planches de validation <DOSSIER>/<id>.png (profil gauche,
#              trois-quarts, vue du tireur, dessus, profil droit ; contour noir)
#   --export   écrit assets/models/weapons/voxel/<id>.glb et l'entrée de
#              weapons_voxel.json (sans --export : planches seulement, le jeu
#              n'est pas touché)
#   --no-check ne lance pas tools/voxel_check.gd après l'export
#
# Repère (le même que weapons_voxel.py, lu par WeaponModels / ViewHands) :
# repère Godot de l'arme, -Z = avant, origine à la détente ; la colonne i = 0
# est centrée sur l'axe du canon (décalage d'un demi-cube) ; points
# remarquables en mètres.
#
# Description : un PROFIL en texte (une chaîne par rangée, du haut vers le
# bas ; un caractère par cube, de la bouche vers l'arrière) dont chaque
# caractère donne une couleur et une LARGEUR (colonnes i occupées), puis des
# retouches (fenêtre d'éjection, plaquettes, organes de visée...).
import bpy, json, math, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

FINE = vx.CUBE_CHAR / 2.0  # 1,25 cm
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapons", "voxel")
SPEC_JSON = os.path.join(OUT_DIR, "weapons_voxel.json")

# Palette (sRGB) : clé -> (matière voxel_lib, couleur).
PAL = {
    "gun_black": ("metal", (0.15, 0.155, 0.165)),
    "gun_dark": ("metal", (0.25, 0.26, 0.27)),
    "parker": ("metal", (0.29, 0.30, 0.28)),      # phosphatation grise (parkérisé)
    "parker_dark": ("metal", (0.21, 0.22, 0.20)),
    "steel": ("metal", (0.47, 0.49, 0.51)),
    "steel_light": ("metal", (0.64, 0.65, 0.64)),
    "brass": ("metal", (0.74, 0.57, 0.25)),
    "rust": ("metal", (0.46, 0.27, 0.15)),
    "rust_dark": ("metal", (0.33, 0.19, 0.11)),
    "bore": ("metal", (0.03, 0.03, 0.035)),
    "walnut": ("wood", (0.40, 0.22, 0.11)),
    "walnut_dark": ("wood", (0.27, 0.14, 0.07)),
    "walnut_light": ("wood", (0.52, 0.31, 0.16)),
    "tape": ("rubber", (0.56, 0.57, 0.54)),
    "blood": ("rubber", (0.36, 0.06, 0.05)),
}

SHADE_G = {"+y": 1.05, "-y": 0.70, "+x": 0.90, "-x": 0.90, "+z": 1.0, "-z": 0.95}
GDIR = {"+x": "+x", "-x": "-x", "+y": "+z", "-y": "-z", "+z": "-y", "-z": "+y"}
GN = {"+x": (1, 0, 0), "-x": (-1, 0, 0), "+y": (0, 1, 0), "-y": (0, -1, 0), "+z": (0, 0, 1), "-z": (0, 0, -1)}


class Piece:
    def __init__(self, offset=(-0.5, 0.0, 0.0)):
        self.offset = tuple(offset)
        self.cells = {}  # (i, j, k) -> (matière, couleur)
        self.faces = {}  # (i, j, k, dir Godot) -> couleur


class Item:
    def __init__(self, iid, family, cube=FINE):
        self.id, self.family, self.cube = iid, family, cube
        self.pieces, self.anchors, self.info = {}, {}, {}

    def piece(self, g):
        if g not in self.pieces:
            self.pieces[g] = Piece()
        return self.pieces[g]

    def put(self, i, j, k, key, g="body", f=None, amp=0.04):
        mat, base = PAL[key]
        if f is None:
            # Texture « un pixel = un cube » : deux paliers de teinte.
            f = 1.0 + amp * (1 if vx.noise((i, j, k), len(key)) > 0.5 else -1)
        self.piece(g).cells[(i, j, k)] = (mat, vx.tone(base, f))

    def drop(self, i, j, k, g="body"):
        self.piece(g).cells.pop((i, j, k), None)

    def has(self, i, j, k, g="body"):
        return g in self.pieces and (i, j, k) in self.pieces[g].cells

    def paint(self, i, j, k, d, key, g="body", f=1.0):
        p = self.piece(g)
        if (i, j, k) in p.cells:
            p.faces[(i, j, k, d)] = vx.tone(PAL[key][1], f)

    def profile(self, rows, top, k0, legend):
        """rows : chaînes du haut (j = top) vers le bas ; caractère n° c à
        k = k0 + c. legend : caractère -> (clé de couleur, colonnes i, groupe)."""
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch in legend:
                    key, cols, g = legend[ch]
                    for i in cols:
                        self.put(i, top - r, k0 + c, key, g)

    def a(self, name, x, y, z):
        self.anchors[name] = [round(x * self.cube, 5), round(y * self.cube, 5), round(z * self.cube, 5)]


W3 = (-1, 0, 1)
W1 = (0,)


# ---------------------------------------------------------------------------
# M1911 (pistolet de départ, id interne « m1911 ») : Colt M1911A1 réel,
# 216 × 135 mm -> 18 × 11 cubes. Glissière d'acier usé (rouille), carcasse
# parkérisée, plaquettes de noyer quadrillées, détente pleine, chien à
# crête, queue de castor courte, poignée inclinée (escalier d'un cube toutes
# les trois rangées).
# ---------------------------------------------------------------------------

def b_m1911():
    it = Item("m1911", "pistol")
    #        k = -11 ......................... 6
    rows = [
        ".o............r...",   # j =  3 : guidon (k = -10), hausse (k = 3)
        "SSSSSSSSSSSSSSSSH.",   # j =  2 : glissière (k = -11 à 4), crête du chien
        "SSSSSSSSSSSSSSSSH.",   # j =  1 : glissière, chien
        "...FFFFFFFFFFFFFGG",   # j =  0 : carcasse (cache-poussière), sûreté de poignée
        ".......f.T.PwwwB..",   # j = -1 : pontet, détente (k = -2), poignée (k = 0 à 4)
        ".......f...PwwwB..",   # j = -2
        ".......ffffPPwwwB.",   # j = -3 : fond du pontet ; poignée inclinée d'un cube
        "............PwwwB.",   # j = -4
        "............PwwwB.",   # j = -5
        ".............PwwwB",   # j = -6 : inclinée de deux cubes
        ".............PmmmB",   # j = -7 : semelle du chargeur
    ]
    assert all(len(r) == 18 for r in rows)
    legend = {
        "S": ("steel", W3, "slide"), "o": ("steel", W1, "slide"), "r": ("gun_black", (-1, 1), "slide"),
        "H": ("gun_black", W1, "body"), "G": ("parker", W3, "body"),
        "F": ("parker", W3, "body"), "f": ("parker", W1, "body"), "T": ("gun_black", W1, "body"),
        "P": ("parker", W3, "body"), "B": ("parker_dark", W3, "body"),
        "w": ("walnut", W3, "body"), "m": ("steel", W3, "mag"),
    }
    it.profile(rows, 3, -11, legend)
    # Poignée : le cœur (i = 0) des colonnes « w » est le CHARGEUR (pièce
    # « mag », caché) ; les flancs (i = ±1) sont les plaquettes de noyer.
    for (i, j, k), _v in list(it.piece("body").cells.items()):
        if i == 0 and it.piece("body").cells[(i, j, k)][0] == "wood":
            it.drop(i, j, k)
            it.put(0, j, k, "gun_black", g="mag")
    # Quadrillage des plaquettes (losanges : damier de deux bruns) et vis.
    for (i, j, k), (mat, _c) in list(it.piece("body").cells.items()):
        if mat == "wood" and i != 0:
            d = "+x" if i > 0 else "-x"
            it.paint(i, j, k, d, "walnut", f=0.88 if (j + k) % 2 else 1.06)
    for j, k in ((-2, 1), (-5, 3)):
        for i, d in ((1, "+x"), (-1, "-x")):
            it.paint(i, j, k, d, "steel_light")
    # Bouche : canon en haut (bague), bouchon du ressort dessous.
    it.paint(0, 2, -11, "-z", "bore")
    for i in (-1, 1):
        it.paint(i, 2, -11, "-z", "steel_light")
    it.paint(0, 1, -11, "-z", "steel_light")
    # Fenêtre d'éjection (flanc droit) : creux d'un cube, canon de laiton
    # visible au fond.
    for k in (-4, -3, -2):
        it.drop(1, 2, k, g="slide")
        it.put(0, 2, k, "brass", g="slide")
    # Stries arrière de la glissière (une sur deux) et stries avant absentes
    # (modèle militaire).
    for k in (1, 3):
        for j in (1, 2):
            it.paint(1, j, k, "+x", "steel", g="slide", f=0.72)
            it.paint(-1, j, k, "-x", "steel", g="slide", f=0.72)
    # Arrêtoir de culasse et sûreté manuelle (flanc gauche), peints.
    for k in (-5, -4):
        it.paint(-1, 0, k, "-x", "gun_black")
    it.paint(-1, 0, 2, "-x", "gun_black")
    it.paint(-1, 0, 3, "-x", "gun_black")
    # Usure : rouille sur la glissière, éclats d'acier clair sur les arêtes.
    for c in ((-1, 2, -8), (1, 1, -6), (0, 2, 0)):
        if it.has(*c, g="slide"):
            it.put(*c, "rust", g="slide")
    for c in ((-1, 2, -10), (1, 2, -9), (0, 2, 4)):
        if it.has(*c, g="slide"):
            it.put(*c, "steel_light", g="slide")
    # Points remarquables (cubes ; ligne de mire au sommet des organes de visée).
    line = 4
    it.a("sight", 0, line, 3.5)
    it.a("front", 0, line, -9.5)
    it.a("muzzle", 0, 2.5, -11)
    it.a("eject", 1.0, 2.5, -3)
    it.a("grip", 0, 0, 2.5)
    it.a("support", 0, -2, 1)
    it.a("pivot_slide", 0, 2.0, 0)
    it.a("pivot_mag", 0, 0, 2.5)
    d = (0.0, -7.0, 2.0)
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    # Vue FPS : le poing droit (cubes de 2,5 cm, ViewHands) suit l'inclinaison
    # de la poignée (même axe que la sortie du chargeur, environ 16°).
    it.info["grip_angle"] = -round(math.degrees(math.atan2(d[2], -d[1])), 1)
    it.info["slide_travel"] = 0.03
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.4]
    it.anchors["hold"] = [-0.06, 0.15, 0.35]
    it.anchors["hold_rot"] = [0.0, 0.32, -0.08]
    # Points d'attache des pièces visibles (docs/weapons/m1911.md).
    it.a("att_muzzle", 0, 2.5, -11)
    it.a("att_optic", 0, 3, 1.5)
    it.a("att_mag", 0, -7, 4.5)
    it.a("att_grip_l", -1.5, -3, 3.5)
    it.a("att_grip_r", 1.5, -3, 3.5)
    return it


BUILDERS = {"m1911": b_m1911}


# ---------------------------------------------------------------------------
# Conversion, export, planches
# ---------------------------------------------------------------------------

def to_model(p, cube):
    m = vx.Model(cube)
    for (i, j, k), (mat, c) in p.cells.items():
        m.vox[(i, -k - 1, j)] = vx.Voxel(mat, None, mat, c)
    for (i, j, k, d), c in p.faces.items():
        m.face_color[(i, -k - 1, j, GDIR[d])] = c
    inv = {v: k for k, v in GDIR.items()}
    for c, d in m.exposed():
        if m.mat_of(c, d) == "glow":
            continue
        m.face_color[(c[0], c[1], c[2], d)] = tuple(min(1.0, x * SHADE_G[inv[d]]) for x in m.color_of(c, d))
    return m


def boxes(p, cube):
    """Pavés (repère Godot, m) couvrant les cellules, par matière."""
    left = {c: v[0] for c, v in p.cells.items()}
    out = []
    ox, oy, oz = p.offset
    for c in sorted(p.cells):
        if c not in left:
            continue
        mat = left[c]
        i0, j0, k0 = c
        i1 = i0 + 1
        while left.get((i1, j0, k0)) == mat:
            i1 += 1
        j1 = j0 + 1
        while all(left.get((i, j1, k0)) == mat for i in range(i0, i1)):
            j1 += 1
        k1 = k0 + 1
        while all(left.get((i, j, k1)) == mat for i in range(i0, i1) for j in range(j0, j1)):
            k1 += 1
        for i in range(i0, i1):
            for j in range(j0, j1):
                for k in range(k0, k1):
                    left.pop((i, j, k), None)
        out.append([mat] + [round(v, 5) for v in (
            ((i0 + i1) / 2.0 + ox) * cube, ((j0 + j1) / 2.0 + oy) * cube, ((k0 + k1) / 2.0 + oz) * cube,
            (i1 - i0) * cube, (j1 - j0) * cube, (k1 - k0) * cube)])
    return out


def build(it):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs, tris, models = [], 0, {}
    for g, p in it.pieces.items():
        m = to_model(p, it.cube)
        ob, info = vx.build_mesh(m, "wpn__%s__%s" % (it.id, g))
        ox, oy, oz = p.offset
        ob.location = (ox * it.cube, -oz * it.cube, oy * it.cube)
        obs.append(ob)
        models[g] = (m, ob)
        tris += info["tris"]
    print("[weapons_fine] %-10s %4d triangles  %s" % (it.id, tris, ", ".join(
        "%s %d" % (g, len(p.cells)) for g, p in it.pieces.items())))
    return obs, models, tris


VIEWS = (("profil", -90.0, 0.0), ("trois-quarts", -140.0, 22.0), ("tireur", -20.0, 20.0),
         ("dessus", -90.0, 88.0), ("profil droit", 90.0, 0.0))


def _frame(obs):
    lo, hi = [1e9] * 3, [-1e9] * 3
    for o in obs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], p[i]), max(hi[i], p[i])
    return tuple((a + b) / 2 for a, b in zip(lo, hi)), max(hi[i] - lo[i] for i in range(3))


def board(it, models, sheet_dir):
    tmp = os.path.join(sheet_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    vx.setup_render((640, 640))
    for g, (m, ob) in models.items():
        o = vx.add_outline(m, ob.name + "_outline", thickness=0.0015)
        o.location = ob.location
    bpy.context.view_layer.update()
    c, s = _frame([ob for _, ob in models.values()])
    imgs = []
    for name, az, el in VIEWS:
        p = os.path.join(tmp, "%s_%s.png" % (it.id, name.replace(" ", "_")))
        vx.render_view(p, az, c, s * 1.2, elev=el, dist=10.0)
        imgs.append(vx.load_png(p))
    path = os.path.join(sheet_dir, it.id + ".png")
    vx.save_png(vx.sheet([imgs[:3], imgs[3:]], 640, 640), path)
    print("[weapons_fine] planche : " + path)
    return path


def export(it, obs, tris):
    path = os.path.join(OUT_DIR, it.id + ".glb")
    vx.export_glb(path, obs, it.cube)
    specs = {}
    if os.path.exists(SPEC_JSON):
        with open(SPEC_JSON, encoding="utf-8") as f:
            specs = json.load(f)
    spec = {"family": it.family, "anchors": it.anchors, "info": it.info, "tris": tris, "boxes": [],
            "groups": sorted(it.pieces)}
    for g, p in it.pieces.items():
        for b in boxes(p, it.cube):
            spec["boxes"].append([g] + b)
    specs[it.id] = spec
    with open(SPEC_JSON, "w", encoding="utf-8") as f:
        f.write("{\n")
        keys = sorted(specs)
        for n, k in enumerate(keys):
            f.write("%s: %s%s\n" % (json.dumps(k), json.dumps(specs[k], ensure_ascii=False), "," if n < len(keys) - 1 else ""))
        f.write("}\n")
    return path


def godot_check(paths):
    import shutil
    exe = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot.exe")
    if not exe:
        print("[weapons_fine] Godot introuvable (variable GODOT) : vérification non faite")
        return False
    rels = ["res://" + os.path.relpath(p, ROOT).replace("\\", "/") for p in paths]
    cmd = [exe, "--headless", "--path", ROOT, "-s", "res://tools/voxel_check.gd", "--"] + rels + [
        "--statique", "--pas=%g" % (FINE * 100.0)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    print("\n".join(l for l in r.stdout.splitlines() if "voxel_check" in l or l.startswith("  ")))
    return r.returncode == 0


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir, do_export, check, ids = "", False, True, []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sheet":
            sheet_dir = os.path.abspath(args[i + 1])
            i += 1
        elif a == "--export":
            do_export = True
        elif a == "--no-check":
            check = False
        else:
            ids.append(a)
        i += 1
    paths = []
    for iid in ids or list(BUILDERS):
        it = BUILDERS[iid]()
        obs, models, tris = build(it)
        if do_export:
            paths.append(export(it, obs, tris))
        if sheet_dir:
            board(it, models, sheet_dir)
    if paths and check and not godot_check(paths):
        print("[weapons_fine] NON CONFORMES")
        sys.exit(1)


main()
