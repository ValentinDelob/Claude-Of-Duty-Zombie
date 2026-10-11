# ARMES ET OBJETS TENUS CUBIQUES (GAME_CONCEPT.md § 4.19 : personnages, mobs
# et objets tenus en cubes de 2,5 cm ; § 6 : armes réelles renommées,
# silhouettes retravaillées ; docs/WEAPONS.md : liste des armes). Construit
# avec tools/blender/voxel/voxel_lib.py :
#   - les 27 armes à feu de WeaponDB, la batte de baseball et le couteau,
#     chacune avec une silhouette ORIGINALE inspirée de sa famille (aucune
#     copie d'une arme réelle reconnaissable) ;
#   - les mains et avant-bras de la vue FPS (gants de batteur, sous-maillot
#     et manche du maillot d'une équipe fictive, sans logo) ;
#   - la grenade, la peluche leurre, la cartouche et la grenade de 40 mm
#     tenues pendant les rechargements coup par coup.
#
#   sh tools/blender.sh tools/blender/weapons/weapons_voxel.py [ids...] [--cache] [--sheet DOSSIER] [--no-check]
#
#   ids        objets à exporter (défaut : tous)
#   --cache    relit les cellules et couleurs depuis weapons_voxel_cells.json
#              (suivi par git) au lieu de relancer les descriptions
#   --sheet    planches de validation : <DOSSIER>/<id>.png (profil gauche,
#              trois-quarts, vue du tireur, dessus ; contour noir) et
#              <DOSSIER>/_toutes.png (toutes les armes à la même échelle)
#   --no-check ne lance pas tools/voxel_check.gd (Godot) après l'export
#
# Sorties (lues par le jeu, WeaponModels / ViewHands / Throwable) :
#   assets/models/weapons/voxel/<id>.glb : un nœud par PIÈCE MOBILE
#     « wpn__<id>__<groupe> » (body, mag, slide, pump, barrels, cyl ; mains :
#     « hand__<pièce> »), cubes de 2,5 cm, couleur par face (COLOR_0),
#     matériaux voxel_lib (metal, wood, rubber, glass, glow, cloth, leather) ;
#   assets/models/weapons/voxel/weapons_voxel.json : par objet, points
#     remarquables (m, repère Godot : -Z = avant, origine à la détente),
#     données (info), boîtes des pièces (contrôles de la vue FPS), triangles.
#
# Description en CELLULES dans le REPÈRE GODOT de l'objet : cellule (i, j, k)
# = [i + ox, i + ox + 1] × [j + oy, …] × [k + oz, …] cubes, où (ox, oy, oz)
# est le décalage de la pièce (armes : ox = -0,5 : la colonne i = 0 est
# centrée sur l'axe du canon, les organes de visée sont donc centrés).
# Conversion vers Blender : cellule Blender (i, -k - 1, j), objet placé au
# décalage (ox, -oz, oy) cubes : les sommets restent sur la grille de l'objet.
import bpy, json, math, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

C = vx.CUBE_CHAR
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapons", "voxel")
SPEC_JSON = os.path.join(OUT_DIR, "weapons_voxel.json")
CACHE = os.path.join(HERE, "weapons_voxel_cells.json")

# ---------------------------------------------------------------------------
# Palette (sRGB) : clé -> (matière voxel_lib, couleur).
# ---------------------------------------------------------------------------
PAL = {
    # Métaux
    "gun_black": ("metal", (0.15, 0.155, 0.165)),
    "gun_dark": ("metal", (0.25, 0.26, 0.27)),
    "steel": ("metal", (0.47, 0.49, 0.51)),
    "steel_light": ("metal", (0.64, 0.65, 0.64)),
    "brass": ("metal", (0.74, 0.57, 0.25)),
    "brass_dark": ("metal", (0.52, 0.38, 0.16)),
    "rust": ("metal", (0.46, 0.27, 0.15)),
    "bore": ("metal", (0.03, 0.03, 0.035)),
    # Bois
    "wood": ("wood", (0.53, 0.32, 0.17)),
    "wood_dark": ("wood", (0.36, 0.21, 0.11)),
    "wood_light": ("wood", (0.69, 0.51, 0.31)),
    "bat_wood": ("wood", (0.80, 0.66, 0.46)),
    "bat_dark": ("wood", (0.62, 0.48, 0.31)),
    # Polymères, peintures, rubans (matière « rubber » : mat)
    "poly": ("rubber", (0.15, 0.15, 0.155)),
    "poly_grey": ("rubber", (0.33, 0.34, 0.34)),
    "olive": ("rubber", (0.34, 0.38, 0.24)),
    "olive_dark": ("rubber", (0.24, 0.27, 0.17)),
    "tan": ("rubber", (0.63, 0.55, 0.39)),
    "brown": ("rubber", (0.38, 0.27, 0.18)),
    "teal": ("rubber", (0.17, 0.45, 0.45)),
    "teal_dark": ("rubber", (0.11, 0.30, 0.31)),
    "orange": ("rubber", (0.88, 0.42, 0.12)),
    "yellow": ("rubber", (0.90, 0.72, 0.14)),
    "red": ("rubber", (0.66, 0.10, 0.08)),
    "white": ("rubber", (0.86, 0.86, 0.83)),
    "bone": ("rubber", (0.88, 0.84, 0.72)),
    "navy": ("rubber", (0.12, 0.16, 0.32)),
    "tape": ("rubber", (0.56, 0.57, 0.54)),
    "tape_black": ("rubber", (0.09, 0.09, 0.10)),
    "blood": ("rubber", (0.36, 0.06, 0.05)),
    "cork": ("wood", (0.66, 0.50, 0.33)),
    # Verres et voyants
    "lens": ("glass", (0.20, 0.40, 0.52)),
    "lens_dark": ("glass", (0.07, 0.11, 0.15)),
    "tube_glass": ("glass", (0.62, 0.78, 0.76)),
    "liquid": ("glass", (0.36, 0.70, 0.30)),
    "dot_red": ("glow", (1.0, 0.22, 0.15)),
    "glow_green": ("glow", (0.45, 1.0, 0.55)),
    "glow_orange": ("glow", (1.0, 0.55, 0.15)),
    # Mains : gants de batteur, sous-maillot, manche du maillot (équipe fictive)
    "glove": ("leather", (0.82, 0.81, 0.76)),
    "glove_palm": ("leather", (0.62, 0.62, 0.59)),
    "glove_knuckle": ("leather", (0.73, 0.72, 0.67)),
    "strap": ("leather", (0.70, 0.12, 0.11)),
    "undershirt": ("cloth", (0.13, 0.17, 0.34)),
    "jersey": ("cloth", (0.90, 0.87, 0.78)),
    "piping": ("cloth", (0.70, 0.12, 0.11)),
    # Peluche
    "fur": ("cloth", (0.45, 0.28, 0.14)),
    "fur_light": ("cloth", (0.75, 0.58, 0.39)),
    "fur_patch": ("cloth", (0.36, 0.33, 0.24)),
    "ribbon": ("cloth", (0.60, 0.07, 0.06)),
    "button": ("rubber", (0.04, 0.03, 0.03)),
    # Grenade
    "frag_olive": ("rubber", (0.27, 0.32, 0.17)),
    "frag_band": ("rubber", (0.18, 0.21, 0.11)),
    "hull_red": ("rubber", (0.62, 0.10, 0.07)),
}

# Ombrage peint par direction GODOT (dessus clair, dessous sombre ; doux :
# l'éclairage du jeu s'y ajoute).
SHADE_G = {"+y": 1.05, "-y": 0.70, "+x": 0.90, "-x": 0.90, "+z": 1.0, "-z": 0.95}
# Directions Godot -> Blender (Blender : x, y = -z Godot, z = y Godot).
GDIR = {"+x": "+x", "-x": "-x", "+y": "+z", "-y": "-z", "+z": "-y", "-z": "+y"}
GN = {"+x": (1, 0, 0), "-x": (-1, 0, 0), "+y": (0, 1, 0), "-y": (0, -1, 0), "+z": (0, 0, 1), "-z": (0, 0, -1)}


def col(key, f=1.0):
    return vx.tone(PAL[key][1], f)


class Piece:
    """Cellules d'une pièce (un nœud du .glb), repère Godot de l'objet."""

    def __init__(self, offset=(-0.5, 0.0, 0.0)):
        self.offset = tuple(offset)
        self.cells = {}  # (i, j, k) -> (matière, couleur)
        self.faces = {}  # (i, j, k, dir Godot) -> couleur

    def put(self, i, j, k, mat, color):
        self.cells[(int(i), int(j), int(k))] = (mat, tuple(color))


class Item:
    """Un objet exporté : pièces, points remarquables, données."""

    def __init__(self, iid, family, prefix="wpn"):
        self.id, self.family, self.prefix = iid, family, prefix
        self.pieces = {}
        self.anchors = {}
        self.info = {}

    def piece(self, g, offset=None):
        if g not in self.pieces:
            self.pieces[g] = Piece(offset if offset is not None else (-0.5, 0.0, 0.0))
        return self.pieces[g]

    def put(self, i, j, k, key, g="body", f=None, seed=0, amp=0.05):
        mat, base = PAL[key]
        if f is None:
            # Texture « un pixel = un cube » : deux paliers de teinte.
            f = 1.0 + amp * (1 if vx.noise((i, j, k), seed + len(key)) > 0.5 else -1)
        self.piece(g).put(i, j, k, mat, vx.tone(base, f))

    def box(self, x0, x1, y0, y1, z0, z1, key, g="body", keep=None, seed=0, amp=0.05):
        for i in range(x0, x1):
            for j in range(y0, y1):
                for k in range(z0, z1):
                    if keep is None or keep(i, j, k):
                        self.put(i, j, k, key, g, seed=seed, amp=amp)

    def clear(self, x0, x1, y0, y1, z0, z1, g="body"):
        p = self.piece(g)
        for i in range(x0, x1):
            for j in range(y0, y1):
                for k in range(z0, z1):
                    p.cells.pop((i, j, k), None)

    def has(self, i, j, k, g="body"):
        return g in self.pieces and (i, j, k) in self.pieces[g].cells

    def paint(self, i, j, k, d, key, g="body", f=1.0):
        p = self.piece(g)
        if (i, j, k) in p.cells:
            p.faces[(i, j, k, d)] = vx.tone(PAL[key][1], f)

    def paint_ring(self, k, key, g="body", dirs=("+x", "-x", "+y", "-y")):
        """Bande de couleur sur toutes les faces latérales visibles de la tranche k."""
        p = self.piece(g)
        for (i, j, kk) in list(p.cells):
            if kk == k:
                for d in dirs:
                    n = GN[d]
                    if (i + n[0], j + n[1], kk + n[2]) not in p.cells:
                        p.faces[(i, j, kk, d)] = vx.tone(PAL[key][1], 1.0)

    def recolor(self, key, sel, g="body"):
        """Change la couleur des cellules choisies par sel(i, j, k)."""
        p = self.piece(g)
        mat, base = PAL[key]
        for c in list(p.cells):
            if sel(*c):
                f = 1.0 + 0.05 * (1 if vx.noise(c, len(key)) > 0.5 else -1)
                p.cells[c] = (mat, vx.tone(base, f))

    def a(self, name, x, y, z, unit=C):
        self.anchors[name] = [round(x * unit, 5), round(y * unit, 5), round(z * unit, 5)]


# ---------------------------------------------------------------------------
# Éléments communs des armes (cubes ; i = 0 : axe du canon).
# ---------------------------------------------------------------------------

def handle(it, gz, gy=0, h=4, key="poly", mag=None, mag_ext=1, toe=True):
    """Poignée verticale de 1 × 2 cubes (cellules k = gz, gz + 1) sous la
    ligne gy, h rangées. `mag` : la colonne avant est le chargeur (groupe
    « mag », clé de couleur), qui dépasse de mag_ext rangées. Ancre « grip » :
    haut de la poignée, entre ses deux colonnes (repère du poing de ViewHands)."""
    for j in range(gy - h, gy):
        it.put(0, j, gz + 1, key)
        if mag is None:
            it.put(0, j, gz, key)
    if toe:
        # Talon de crosse un cube plus long en arrière (prise en main).
        it.put(0, gy - h, gz + 2, key)
    if mag is not None:
        for j in range(gy - h - mag_ext, gy):
            it.put(0, j, gz, mag, g="mag")
        it.put(0, gy - h - mag_ext, gz + 1, "steel", g="mag")
        it.a("pivot_mag", 0, gy, gz + 0.5)
        it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
        it.info["mag_len"] = round((h + mag_ext) * C, 4)
    it.a("grip", 0, gy, gz + 1)


def trigger(it, gz, gy=0, key="gun_black", guard=True):
    """Queue de détente devant la poignée et pontet (l'index s'y glisse)."""
    it.put(0, gy - 1, gz - 1, key)
    if guard:
        for c in ((0, gy - 1, gz - 3), (0, gy - 2, gz - 3), (0, gy - 2, gz - 2)):
            it.put(*c, key)


def iron(it, rear_k, front_k, top_rear, top_front, rear_key="gun_black", front_key="gun_black",
         g_rear="body", g_front="body", front_dot=None):
    """Hausse (deux oreilles d'un cube sur les coins du dessus : cran d'un
    cube au milieu ; flancs complétés sous les oreilles si le boîtier est
    plus étroit) et guidon (lame d'un cube) : leurs sommets sont sur la même
    ligne de mire, un cube au-dessus du boîtier."""
    line = top_rear + 1
    for i in (-1, 1):
        if not it.has(i, top_rear - 1, rear_k, g_rear) and not it.has(i, top_rear - 1, rear_k):
            it.put(i, top_rear - 1, rear_k, rear_key, g=g_rear)
        it.put(i, top_rear, rear_k, rear_key, g=g_rear)
    for j in range(top_front, line):
        it.put(0, j, front_k, front_key, g=g_front)
    if front_dot:
        it.paint(0, line - 1, front_k, "+z", front_dot, g=g_front)
    it.a("sight", 0, line, rear_k + 0.5)
    it.a("front", 0, line, front_k + 0.5)
    return line


def barrel(it, k0, k1, row=1, key="gun_dark", muzzle="plain", mkey="gun_black"):
    """Canon d'un cube de section, de k0 (bouche) à k1 ; frein ou cache-flamme
    devant. Renvoie la position de la bouche (k de la face avant)."""
    for k in range(k0, k1):
        it.put(0, row, k, key)
    mz = k0
    if muzzle == "brake":
        # Frein : bloc de 3 × 3 évidé sur les flancs.
        it.box(-1, 2, row - 1, row + 2, k0 - 3, k0, mkey)
        for kk in (k0 - 3, k0 - 1):
            it.clear(-1, 0, row, row + 1, kk, kk + 1)
            it.clear(1, 2, row, row + 1, kk, kk + 1)
        mz = k0 - 3
    elif muzzle == "cage":
        # Cache-flamme en croix (« plus »).
        it.box(-1, 2, row - 1, row + 2, k0 - 2, k0, mkey, keep=lambda i, j, k: i == 0 or j == row)
        mz = k0 - 2
    elif muzzle == "can":
        it.box(-1, 2, row - 1, row + 2, k0 - 5, k0, mkey)
        mz = k0 - 5
    elif muzzle == "nub":
        it.put(0, row, k0 - 1, mkey)
        mz = k0 - 1
    it.paint(0, row, mz, "-z", "bore")
    it.a("muzzle", 0, row + 0.5, mz)
    return mz


def curved_mag(it, mz, mlen, key, top=0, step=2, g="mag"):
    """Chargeur incurvé en escalier : avance d'un cube toutes les `step` rangées."""
    end = (0, 0)
    for r in range(mlen):
        j = top - 1 - r
        s = -(r // step)
        for k in (mz + s, mz + s + 1):
            it.put(0, j, k, key, g=g)
        end = (j, mz + s)
    it.put(0, end[0] - 1, end[1], "steel", g=g)
    it.put(0, end[0] - 1, end[1] + 1, "steel", g=g)
    it.a("pivot_mag", 0, top, mz + 1)
    d = (0.0, -float(mlen + 1), -float(mlen // step))
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * C, 4)


def box_mag(it, mz, mlen, key, top=0, depth=2, g="mag", base="steel"):
    for j in range(top - mlen, top):
        for k in range(mz, mz + depth):
            it.put(0, j, k, key, g=g)
    for k in range(mz, mz + depth):
        it.put(0, top - mlen - 1, k, base, g=g)
    it.a("pivot_mag", 0, top, mz + depth / 2.0)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = round((mlen + 1) * C, 4)


def drum_mag(it, zc, yc, r, shell, head, top=0, g="mag"):
    """Tambour : disque de rayon r (cubes) dans le plan (y, z), 3 cubes
    d'épaisseur (faces plates : peaux `head` ; tranche : fût `shell`), relié
    au boîtier par un col."""
    for j in range(int(math.floor(yc - r)) - 1, int(math.ceil(yc + r)) + 1):
        for k in range(int(math.floor(zc - r)) - 1, int(math.ceil(zc + r)) + 1):
            d = math.hypot(j + 0.5 - yc, k + 0.5 - zc)
            if d <= r:
                for i in (-1, 0, 1):
                    it.put(i, j, k, shell if (i == 0 or d > r - 1.0) else head, g=g)
    for j in range(int(math.floor(yc + r)), top):
        it.put(0, j, int(math.floor(zc)), "gun_black", g=g)
        it.put(0, j, int(math.floor(zc)) - 1, "gun_black", g=g)
    it.a("pivot_mag", 0, top, zc)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = round((top - (yc - r)) * C, 4)


def cradle_support(it, k_lo, k_hi, y_bottom):
    """Main d'appui (berceau) sous un garde-main de k_lo à k_hi (exclu)."""
    it.a("support", 0, y_bottom, (k_lo + k_hi) / 2.0)


def charge(it, i, j, k, key="gun_black", knob=True):
    """Levier d'armement (groupe « slide ») sur un flanc."""
    it.put(i, j, k, key, g="slide")
    if knob:
        it.put(i + (1 if i > 0 else -1), j, k, key, g="slide")
    it.a("pivot_slide", i, j + 0.5, k + 0.5)


def bipod(it, k, row, length=8, key="gun_black"):
    """Bipied replié sous le canon : deux jambes le long du garde-main."""
    for kk in range(k, k + length):
        it.put(-1, row - 1, kk, key)
        it.put(1, row - 1, kk, key)
    it.put(0, row - 1, k, key)


# ---------------------------------------------------------------------------
# Pistolets et revolver
# ---------------------------------------------------------------------------

def pistol(iid, slide_key, frame_key, grip_key, length=8, mag_ext=1, accent=None, front_dot=None):
    it = Item(iid, "pistol")
    # Glissière (groupe « slide ») : 1 cube de large, 2 de haut, de
    # k = 2 - length à 1.
    k0 = 2 - length
    for k in range(k0, 2):
        it.put(0, 1, k, slide_key, g="slide")
        it.put(0, 2, k, slide_key, g="slide")
    # Stries arrière, fenêtre d'éjection, bouche.
    for k in (0, 1):
        it.paint(0, 2, k, "+x", "gun_black", g="slide")
        it.paint(0, 2, k, "-x", "gun_black", g="slide")
    it.paint(0, 2, -2, "+x", "bore", g="slide")
    iron(it, 0, k0, 3, 3, rear_key="gun_black", front_key=slide_key, g_rear="slide", g_front="slide",
         front_dot=front_dot)
    it.a("muzzle", 0, 1.5, k0)
    it.paint(0, 1, k0, "-z", "bore", g="slide")
    # Carcasse sous la glissière, chien et queue de castor.
    for k in range(k0 + 1, 2):
        it.put(0, 0, k, frame_key)
    it.put(0, 2, 2, "gun_black")
    it.put(0, 1, 2, frame_key)
    it.put(0, 0, 2, frame_key)
    trigger(it, 0, 0, "gun_black")
    handle(it, 0, 0, 4, grip_key, mag="gun_black", mag_ext=mag_ext)
    if accent:
        for j in (-1, -3):
            it.paint(0, j, 1, "+x", accent)
            it.paint(0, j, 1, "-x", accent)
            it.paint(0, j, 1, "+z", accent)
    it.a("pivot_slide", 0, 2.0, 0)
    it.info["slide_travel"] = 0.03
    it.a("eject", 0.5, 2.5, -2)
    it.a("support", 0, -1, 0.5)
    it.anchors["ads"] = [0.0, 0.0, 0.4]
    it.anchors["hold"] = [-0.06, 0.15, 0.35]
    it.anchors["hold_rot"] = [0.0, 0.32, -0.08]
    return it


def b_m1911():
    # PÉTOIRE : pistolet de départ bon marché, glissière d'acier usé, plaquettes
    # de bois scotchées (ruban gris).
    it = pistol("m1911", "steel", "gun_dark", "wood_dark", accent="tape")
    it.recolor("rust", lambda i, j, k: (i, j, k) in ((0, 2, -4), (0, 1, -1), (0, 2, -3)), g="slide")
    return it


def b_cz75():
    # GUÊPE : pistolet fin et nerveux, carcasse rayée jaune et noir, chargeur
    # allongé, guidon jaune.
    it = pistol("cz75", "gun_black", "poly", "poly", length=9, mag_ext=2, accent="yellow", front_dot="yellow")
    for k in (-5, -3, -1, 1):
        it.paint(0, 0, k, "+x", "yellow")
        it.paint(0, 0, k, "-x", "yellow")
    return it


def b_python():
    # COUPERET : gros revolver à carénage de canon plat et haut comme une lame
    # de hachoir, barillet de 3 × 3 qui bascule à gauche.
    it = Item("python", "revolver")
    # Carcasse.
    it.box(0, 1, 0, 3, -2, 2, "steel")
    it.put(0, 3, 2, "gun_black")  # chien
    # Barillet (groupe « cyl »).
    it.box(-1, 2, 0, 3, -2, 1, "steel_light", g="cyl")
    for j in (0, 2):
        for i in (-1, 1):
            for d in ("-x" if i < 0 else "+x",):
                it.paint(i, j, -1, d, "gun_dark", g="cyl")
    for i in (-1, 1):
        for j in (0, 2):
            it.paint(i, j, -2, "-z", "bore", g="cyl")
    it.a("pivot_cyl", -1.5, 0, -0.5)
    # Carénage-lame : 1 cube de large, 3 de haut, évents peints.
    it.box(0, 1, 0, 3, -11, -2, "gun_dark")
    for k in range(-10, -3, 2):
        it.paint(0, 2, k, "+x", "gun_black")
        it.paint(0, 2, k, "-x", "gun_black")
    it.paint(0, 1, -11, "-z", "bore")
    it.a("muzzle", 0, 1.5, -11)
    iron(it, 0, -10, 3, 3, front_key="red")
    # Pontet, détente, crosse en bois (talon élargi) et rivets de laiton.
    trigger(it, 0, 0, "gun_black")
    handle(it, 0, 0, 4, "wood", toe=True)
    it.put(0, -4, 2, "wood")
    it.paint(0, -2, 1, "+x", "brass")
    it.paint(0, -2, 1, "-x", "brass")
    it.a("pivot_mag", 0, 1.5, 1.5)
    it.anchors["mag_dir"] = [0.0, 0.0, 1.0]
    it.a("eject", 0.5, 1.5, -1)
    it.a("support", 0, -1, 0.5)
    it.anchors["ads"] = [0.0, 0.0, 0.4]
    it.anchors["hold"] = [-0.06, 0.15, 0.33]
    it.anchors["hold_rot"] = [0.0, 0.32, -0.08]
    return it


# ---------------------------------------------------------------------------
# Armes longues : boîtier de 3 cubes de large (rangées 0 à rh), canon en
# rangée 1, poignée sous le boîtier (gz), hausse et guidon sur le dessus.
# ---------------------------------------------------------------------------

def receiver(it, rf, rb, key, rh=3, rw=1, y0=0):
    it.box(-rw, rw + 1, y0, rh, rf, rb, key)


def finish_long(it, rw=1, rh=3, ez=0, ads=0.3, hold=None):
    it.a("eject", rw + 0.5, rh - 1.5, ez)
    it.anchors["ads"] = [0.0, 0.0, ads]
    if hold is not None:
        it.anchors["hold"] = list(hold)
    return it


def b_mp40():
    # CRÉCELLE : vieille mitraillette à tube fin, bas de boîtier en bakélite,
    # manchon ajouré devant, crosse en fil d'acier repliée sur le flanc gauche.
    it = Item("mp40", "smg")
    it.box(0, 1, 0, 2, -5, 9, "gun_dark")
    it.box(0, 1, -1, 0, -2, 7, "brown")
    for k in (5, 6, 7):
        it.paint(0, 1, k, "+x", "gun_black")
        it.paint(0, 1, k, "-x", "gun_black")
    # Manchon ajouré (garde-main) autour du canon.
    it.box(-1, 2, 0, 2, -9, -5, "gun_black")
    for k in (-8, -6):
        it.clear(-1, 0, 1, 2, k, k + 1)
        it.clear(1, 2, 1, 2, k, k + 1)
    barrel(it, -12, -9, 1, "gun_dark", "nub")
    cradle_support(it, -9, -5, 0)
    # Chargeur droit long devant la détente.
    box_mag(it, -4, 7, "gun_black")
    trigger(it, 1, -1)
    handle(it, 1, -1, 4, "brown")
    # Crosse en fil repliée sur le flanc gauche, plaque de couche.
    it.box(-1, 0, 0, 1, 0, 10, "gun_black")
    it.box(-1, 0, -2, 1, 10, 11, "gun_black")
    charge(it, -1, 1, 2)
    iron(it, 7, -11, 2, 2)
    return finish_long(it, rw=0, rh=2, ez=-1, ads=0.22)


def b_mp5k():
    # MOUCHERON : mitraillette minuscule et carrée, poignée avant verticale à
    # ruban sarcelle, chargeur incurvé, embout carré sans crosse.
    it = Item("mp5k", "smg")
    receiver(it, -8, 6, "poly")
    it.box(-1, 2, 0, 1, 6, 7, "gun_black")
    barrel(it, -11, -8, 1, "gun_dark", "nub")
    curved_mag(it, -3, 6, "gun_black")
    trigger(it, 2, 0)
    handle(it, 2, 0, 4, "poly")
    # Poignée avant (main gauche en poing).
    for j in range(-5, 0):
        for k in (-7, -6):
            it.put(0, j, k, "teal" if j in (-2, -3) else "poly")
    it.a("support", 0, 0, -6)
    it.info["front_grip"] = True
    charge(it, -2, 2, -4)
    iron(it, 5, -7, 3, 3)
    return finish_long(it, ez=0, ads=0.2)


def b_pm63():
    # PUCE : mitraillette de poche, culasse apparente claire sur le dessus,
    # chargeur dans la poignée, petite poignée avant, crosse orange repliée
    # sur le flanc droit.
    it = Item("pm63", "smg")
    it.box(0, 1, 0, 1, -6, 4, "gun_black")
    it.box(0, 1, 1, 2, -4, 4, "steel_light", g="slide")
    it.a("pivot_slide", 0, 1.5, 0)
    it.info["slide_travel"] = 0.035
    barrel(it, -8, -6, 0, "gun_dark", "nub")
    trigger(it, 0, 0)
    handle(it, 0, 0, 4, "poly", mag="gun_black", mag_ext=2)
    for j in range(-3, 0):
        for k in (-6, -5):
            it.put(0, j, k, "poly")
    it.a("support", 0, 0, -5)
    it.info["front_grip"] = True
    it.box(1, 2, 0, 1, 0, 7, "orange")
    it.box(1, 2, -2, 0, 6, 7, "orange")
    iron(it, 3, -4, 2, 2, g_rear="slide", g_front="slide")
    return finish_long(it, rw=0, rh=2, ez=-1, ads=0.3)


def b_mpl():
    # AGRAFEUSE : mitraillette de laboratoire en forme d'agrafeuse géante :
    # bras supérieur sarcelle articulé à l'arrière, manchon ajouré, chargeur
    # dans la poignée, crosse repliée à gauche.
    it = Item("mpl", "smg")
    receiver(it, -6, 6, "poly_grey", rh=2)
    it.box(-1, 2, 2, 3, -7, 6, "teal")
    it.box(-1, 2, 2, 4, 6, 7, "teal_dark")
    it.paint(0, 2, -7, "-z", "steel")
    it.box(-1, 2, 0, 2, -10, -6, "gun_black")
    for k in (-9, -7):
        it.clear(-1, 0, 1, 2, k, k + 1)
        it.clear(1, 2, 1, 2, k, k + 1)
    barrel(it, -12, -10, 1, "gun_dark", "nub")
    cradle_support(it, -10, -6, 0)
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "poly", mag="gun_black", mag_ext=2)
    it.box(-2, -1, 0, 1, -1, 8, "gun_black")
    charge(it, 2, 1, -4)
    iron(it, 5, -7, 3, 3, front_key="steel")
    return finish_long(it, rh=2, ez=-2, ads=0.22)


def b_spectre():
    # FEU FOLLET : mitraillette sombre au manchon ajouré dont le cœur luit
    # (lueur verte entre les trous), chargeur droit, crosse sur le flanc droit.
    it = Item("spectre", "smg")
    receiver(it, -5, 6, "gun_black", rh=2)
    it.box(-1, 2, 0, 3, -11, -5, "gun_dark")
    for k in range(-10, -5, 2):
        for i in (-1, 1):
            it.put(i, 1, k, "glow_green")
    it.put(0, 2, -6, "glow_green")
    barrel(it, -12, -11, 1, "gun_black", "nub")
    cradle_support(it, -11, -5, 0)
    box_mag(it, -4, 7, "gun_black")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "poly")
    it.box(2, 3, 0, 1, -2, 8, "gun_black")
    it.box(2, 3, -2, 1, 8, 9, "gun_black")
    charge(it, -2, 1, -1)
    iron(it, 5, -10, 3, 3, front_key="glow_green")
    return finish_long(it, rh=2, ez=-2, ads=0.22)


def b_ak74u():
    # BRISE-OS : carabine courte, garde-main en bois clair, gros frein carré,
    # chargeur incurvé, poignée et crosse squelette entourées de ruban blanc.
    it = Item("ak74u", "smg")
    receiver(it, -5, 6, "gun_dark")
    it.box(-1, 2, 0, 2, -10, -5, "wood_light")
    it.box(0, 1, 2, 3, -9, -5, "wood")
    barrel(it, -11, -10, 1, "gun_dark", "brake", "gun_black")
    cradle_support(it, -10, -5, 0)
    curved_mag(it, -4, 7, "rust")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "bone")
    it.box(0, 1, 1, 2, 6, 14, "gun_black")
    it.box(0, 1, -1, 0, 6, 14, "gun_black")
    it.box(0, 1, -2, 3, 14, 15, "bone")
    charge(it, 2, 1, 3)
    iron(it, -3, -12, 3, 2)
    return finish_long(it, ez=-1, ads=0.3)


def b_m14():
    # MÉTRONOME : fusil en bois sur toute la longueur, deux bagues de laiton,
    # plaque de couche en laiton, chargeur court.
    it = Item("m14", "rifle")
    receiver(it, -2, 4, "steel")
    it.box(-1, 2, 0, 2, -14, -2, "wood")
    for k in (-12, -6):
        it.box(-1, 2, 0, 2, k, k + 1, "brass")
    barrel(it, -22, -14, 1, "gun_dark", "cage")
    cradle_support(it, -11, -6, 0)
    # Crosse : poignet, puis busc qui descend en escalier.
    it.box(-1, 2, -1, 2, 4, 8, "wood")
    it.box(-1, 2, -3, 2, 8, 15, "wood")
    it.box(-1, 2, -3, 2, 15, 16, "brass")
    box_mag(it, -1, 4, "gun_black")
    trigger(it, 4, -1)
    handle(it, 4, -1, 3, "wood", toe=False)
    charge(it, 2, 1, -1)
    iron(it, 2, -21, 3, 2)
    return finish_long(it, ez=0, ads=0.24)


def b_m16():
    # TRIPLETTE : fusil à rafale de trois, trois canons courts superposés
    # tenus par une bride, garde-main carré ajouré, crosse droite.
    it = Item("m16", "rifle")
    receiver(it, -5, 6, "poly")
    # « III » blanc sur le flanc gauche du boîtier (rafale de trois).
    for k in (-2, 0, 2):
        it.paint(-1, 1, k, "-x", "white")
        it.paint(-1, 2, k, "-x", "white")
    it.box(-1, 2, 0, 3, -12, -5, "poly_grey")
    for k in range(-11, -5, 2):
        it.paint(-1, 1, k, "-x", "gun_black")
        it.paint(1, 1, k, "+x", "gun_black")
    # Trois canons superposés qui dépassent du garde-main, deux brides,
    # bagues de couleur à la bouche (rouge, jaune, bleu de bas en haut).
    for row, key in ((0, "red"), (1, "yellow"), (2, "teal")):
        for k in range(-21, -12):
            it.put(0, row, k, "gun_dark")
        it.put(0, row, -21, key)
        it.paint(0, row, -21, "-z", "bore")
    for k in (-14, -18):
        it.box(-1, 2, 0, 3, k, k + 1, "gun_black")
    it.a("muzzle", 0, 1.5, -21)
    cradle_support(it, -11, -6, 0)
    box_mag(it, -4, 6, "gun_black")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "poly")
    it.box(-1, 2, -2, 3, 6, 16, "poly")
    it.box(-1, 2, -2, 3, 16, 17, "tape_black")
    it.clear(-1, 2, -2, 0, 6, 9)
    charge(it, -2, 2, 4)
    iron(it, 5, -18, 3, 3)
    return finish_long(it, ez=-1, ads=0.18)


def b_fnfal():
    # MASSE : fusil de combat lourd, garde-main olive épais, frein massif,
    # crosse fauve pleine, chargeur droit.
    it = Item("fnfal", "rifle")
    receiver(it, -4, 6, "gun_dark")
    it.box(-1, 2, -1, 2, -13, -4, "olive")
    for k in range(-12, -5, 3):
        it.paint(-1, 0, k, "-x", "olive_dark")
        it.paint(1, 0, k, "+x", "olive_dark")
    barrel(it, -17, -13, 1, "gun_dark", "brake", "steel")
    cradle_support(it, -12, -5, -1)
    box_mag(it, -4, 5, "gun_black")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "tan")
    it.box(-1, 2, -2, 3, 6, 17, "tan")
    it.box(-1, 2, -2, 3, 17, 18, "poly")
    it.clear(-1, 2, -2, 0, 6, 8)
    charge(it, -2, 2, -2)
    iron(it, 5, -16, 3, 2)
    return finish_long(it, ez=-1, ads=0.2)


def b_g11():
    # STROBOSCOPE : brique gris clair sans aspérité (tir en rafale très
    # rapide), viseur intégré sur toute la longueur, bande jaune, gyrophare
    # orange à l'avant. Poignée avancée (arme compacte).
    it = Item("g11", "rifle")
    it.box(-1, 2, -2, 3, -12, 9, "poly_grey")
    it.box(-1, 2, -2, 3, -10, -9, "yellow")
    it.box(-1, 2, -2, -1, -12, -11, "gun_black")
    # Viseur (lunette courte) : tube de 3 × 2 au-dessus, lentilles.
    it.box(-1, 2, 3, 5, -9, 6, "poly")
    it.paint(0, 3, 6, "+z", "lens_dark")
    it.paint(0, 4, 6, "+z", "lens_dark")
    it.paint(0, 4, -9, "-z", "lens")
    it.paint(0, 3, -9, "-z", "lens")
    it.a("sight", 0, 4, 5.5)
    it.a("front", 0, 4, -8.5)
    it.put(-1, 3, -11, "glow_orange")
    it.put(1, 3, -11, "glow_orange")
    it.paint(0, 1, -12, "-z", "bore")
    it.a("muzzle", 0, 1.5, -12)
    trigger(it, -3, -2)
    handle(it, -3, -2, 4, "poly")
    it.a("support", 0, -2, -9)
    it.a("pivot_mag", 0, -2, 4)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = 0.1
    return finish_long(it, rh=3, ez=2, ads=0.1, hold=[0.0, 0.0, -0.14])


def b_galil():
    # BOURRASQUE : fusil à ailettes de refroidissement crénelées au-dessus du
    # garde-main en bois clair, crosse squelette, bipied replié.
    it = Item("galil", "rifle")
    receiver(it, -5, 6, "gun_dark")
    it.box(-1, 2, 0, 2, -14, -5, "wood_light")
    for k in range(-14, -5, 2):
        it.box(-1, 2, 2, 3, k, k + 1, "steel")
    barrel(it, -19, -14, 1, "gun_dark", "cage")
    cradle_support(it, -13, -6, 0)
    bipod(it, -19, 1, 4)
    curved_mag(it, -4, 7, "gun_black")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "poly")
    it.box(0, 1, 2, 3, 6, 16, "gun_black")
    it.box(0, 1, -2, -1, 6, 16, "gun_black")
    it.box(0, 1, -2, 3, 16, 17, "poly")
    charge(it, 2, 1, -2)
    iron(it, 5, -18, 3, 2)
    return finish_long(it, ez=-1, ads=0.24)


def b_famas():
    # CIGALE : fusil compact à chargeur derrière la poignée, longues « ailes »
    # vertes translucides plaquées sur les flancs, crête de visée au dos.
    it = Item("famas", "rifle")
    it.box(-1, 2, -1, 3, -10, 9, "olive_dark")
    for i in (-2, 2):
        it.box(i, i + 1, 0, 3, -8, 7, "tube_glass")
        it.box(i, i + 1, 1, 2, -8, 7, "olive")
    it.box(-1, 2, 3, 4, -6, 9, "poly")
    barrel(it, -15, -10, 1, "gun_dark", "cage")
    trigger(it, -4, -1)
    handle(it, -4, -1, 4, "poly")
    box_mag(it, 2, 6, "gun_black", top=-1)
    it.a("support", 0, -1, -9)
    charge(it, -2, 3, -4)
    # Œilleton tout au bout de la crête (rien entre l'œil et le cran).
    iron(it, 8, -9, 4, 3)
    it.box(-1, 2, -3, 1, 9, 10, "poly")
    return finish_long(it, ez=2, ads=0.16, hold=[0.0, 0.0, -0.14])


def b_commando():
    # ÉPERVIER : carabine fauve et brune, frein en bec qui pique vers le bas,
    # crosse télescopique sur tube, garde-main court.
    it = Item("commando", "rifle")
    receiver(it, -5, 6, "tan")
    it.box(-1, 2, 0, 3, -11, -5, "brown")
    barrel(it, -14, -11, 1, "gun_dark", "plain")
    it.box(-1, 2, 0, 2, -16, -14, "gun_black")
    it.put(0, 0, -17, "gun_black")
    it.a("muzzle", 0, 1.5, -16)
    it.paint(0, 1, -16, "-z", "bore")
    cradle_support(it, -11, -5, 0)
    box_mag(it, -4, 6, "gun_black")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "brown")
    it.box(0, 1, 1, 2, 6, 11, "gun_black")
    it.box(-1, 2, -2, 3, 11, 15, "tan")
    it.box(-1, 2, -2, 3, 15, 16, "poly")
    charge(it, -2, 2, 4)
    iron(it, 5, -11, 3, 3)
    return finish_long(it, ez=-1, ads=0.2)


def b_aug():
    # VIGIE : fusil fauve à viseur perché très haut sur une tour (lunette
    # courte), garde-main long, crosse pleine.
    it = Item("aug", "rifle")
    receiver(it, -5, 6, "tan")
    it.box(-1, 2, 0, 3, -13, -5, "olive")
    barrel(it, -17, -13, 1, "gun_dark", "cage")
    cradle_support(it, -12, -6, 0)
    box_mag(it, -4, 6, "olive_dark")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "olive_dark")
    it.box(-1, 2, -2, 3, 6, 16, "tan")
    it.box(-1, 2, -2, 3, 16, 17, "poly")
    # Tour et viseur.
    it.box(0, 1, 3, 5, -2, 1, "gun_black")
    it.box(-1, 2, 5, 7, -5, 4, "olive_dark")
    it.paint(0, 5, 4, "+z", "lens_dark")
    it.paint(0, 6, 4, "+z", "lens_dark")
    it.paint(0, 5, -5, "-z", "lens")
    it.paint(0, 6, -5, "-z", "lens")
    it.a("sight", 0, 6, 3.5)
    it.a("front", 0, 6, -4.5)
    charge(it, -2, 2, -3)
    return finish_long(it, ez=-1, ads=0.1)


def b_rpk():
    # TAMBOUR : fusil-mitrailleur à gros tambour peint comme une caisse
    # claire (rouge, cerclage clair), crosse et garde-main en bois, bipied.
    it = Item("rpk", "lmg")
    receiver(it, -5, 6, "gun_dark")
    it.box(-1, 2, 0, 2, -14, -5, "wood")
    barrel(it, -22, -14, 1, "gun_dark", "cage")
    cradle_support(it, -14, -9, 0)
    bipod(it, -20, 1, 6)
    drum_mag(it, -5.0, -5.0, 3.4, "red", "white")
    trigger(it, 2, 0)
    handle(it, 2, 0, 4, "wood_dark")
    it.box(-1, 2, -1, 2, 6, 10, "wood")
    it.box(-1, 2, -3, 2, 10, 17, "wood")
    it.box(-1, 2, -3, 2, 17, 18, "gun_black")
    charge(it, 2, 1, 3)
    iron(it, -3, -20, 3, 2)
    it.info["slide_travel"] = 0.05
    return finish_long(it, ez=-1, ads=0.3)


def b_hk21():
    # BÉTONNEUSE : mitrailleuse lourde, caisse à munitions de chantier orange
    # à bandes jaunes sur le flanc droit, manchon ajouré, bipied, crosse pleine.
    it = Item("hk21", "lmg")
    receiver(it, -6, 7, "gun_dark", rh=3)
    it.box(-1, 2, 0, 3, -14, -6, "gun_black")
    for k in range(-13, -6, 2):
        it.clear(-1, 0, 1, 2, k, k + 1)
        it.clear(1, 2, 1, 2, k, k + 1)
    it.box(0, 1, 1, 2, -14, -6, "gun_dark")
    barrel(it, -21, -14, 1, "gun_dark", "cage")
    cradle_support(it, -13, -6, 0)
    bipod(it, -20, 1, 6)
    # Réservoir de bande (groupe « mag ») en cuve de bétonnière : cylindre
    # couché (axe X) sous le boîtier, débordant à droite, orange à spirale
    # jaune, bouche grise côté gauche.
    yc, zc, r = -3.0, -4.5, 2.6
    for i in range(-1, 4):
        for j in range(-6, 0):
            for k in range(-8, -1):
                d = math.hypot(j + 0.5 - yc, k + 0.5 - zc)
                rr = r - (0.8 if i in (-1, 3) else 0.0)
                if d <= rr:
                    key = "yellow" if (j + k + 2 * i) % 5 == 0 else "orange"
                    if i == -1 and d < 1.2:
                        key = "steel"
                    it.put(i, j, k, key, g="mag")
    it.a("pivot_mag", 0, 0, -4.5)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = 0.15
    trigger(it, 2, 0)
    handle(it, 2, 0, 4, "poly")
    it.box(-1, 2, -2, 3, 7, 17, "poly")
    it.box(-1, 2, -2, 3, 17, 18, "tape_black")
    it.clear(-1, 2, -2, 0, 7, 9)
    charge(it, -2, 2, -5)
    iron(it, 6, -20, 3, 2)
    return finish_long(it, ez=-2, ads=0.22)


# ---------------------------------------------------------------------------
# Fusils à pompe
# ---------------------------------------------------------------------------

def b_olympia():
    # GARDE-CHASSE : fusil à deux canons superposés qui basculent (groupe
    # « barrels »), longuesse et crosse en bois, bille de guidon en laiton.
    it = Item("olympia", "shotgun")
    it.box(-1, 2, 0, 3, -2, 3, "steel_light")
    for row in (1, 2):
        for k in range(-24, -2):
            it.put(0, row, k, "gun_dark", g="barrels")
        it.paint(0, row, -24, "-z", "bore", g="barrels")
    it.box(-1, 2, 0, 1, -12, -3, "wood", g="barrels")
    it.put(0, 3, -23, "brass", g="barrels")
    it.a("muzzle", 0, 2.5, -24)
    it.a("pivot_barrels", 0, 0, -2)
    # Hausse : simple cran de laiton sur la carcasse.
    for i in (-1, 1):
        it.put(i, 3, 1, "brass")
    it.a("sight", 0, 4, 1.5)
    it.a("front", 0, 4, -22.5)
    # Crosse anglaise : poignet puis talon en escalier.
    it.box(-1, 2, 0, 2, 3, 7, "wood")
    it.box(-1, 2, -2, 2, 7, 12, "wood")
    it.box(-1, 2, -3, 2, 12, 17, "wood")
    it.box(-1, 2, -3, 2, 17, 18, "wood_dark")
    trigger(it, 3, 0, guard=True)
    it.box(0, 1, -3, 0, 3, 5, "wood")
    it.a("grip", 0, 0, 4)
    it.a("support", 0, 0, -8)
    it.a("pivot_mag", 0, 0, -1)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    return finish_long(it, ez=0, ads=0.3)


def pump_gun(it, length, body_key, pump_key, barrel_key="gun_black", stock=None, shield=False, grip_key="poly"):
    receiver(it, -3, 3, body_key)
    k0 = -3 - length
    for k in range(k0, -3):
        it.put(0, 2, k, barrel_key)
    it.paint(0, 2, k0, "-z", "bore")
    it.a("muzzle", 0, 2.5, k0)
    # Tube magasin sous le canon, pompe autour.
    for k in range(k0 + 2, -3):
        it.put(0, 1, k, "gun_dark")
    if pump_key:
        it.box(-1, 2, 0, 2, -13, -6, pump_key, g="pump")
        it.a("pivot_pump", 0, 0, 0)
        it.a("support", 0, 0, -9.5)
    else:
        it.box(-1, 2, 0, 2, -12, -4, body_key)
        it.a("support", 0, 0, -8)
    if shield:
        it.box(-1, 2, 3, 4, k0 + 2, -4, "gun_dark")
        for k in range(k0 + 3, -4, 2):
            it.paint(-1, 3, k, "+y", "bore")
            it.paint(1, 3, k, "+y", "bore")
    # Bille de guidon au bout du canon, cran sur la carcasse : ligne de mire
    # en y = 4 cubes.
    iron(it, 2, k0 + 1, 3, 3, front_key="brass")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, grip_key)
    it.a("pivot_mag", 0, 0, -1)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    if stock == "skeleton":
        it.box(0, 1, 2, 3, 3, 14, "gun_black")
        it.box(0, 1, -2, -1, 4, 14, "gun_black")
        it.box(-1, 2, -2, 3, 14, 15, "poly")


def b_stakeout():
    # BALAI : fusil à pompe court sans crosse, pompe en bois clair cerclée de
    # ruban paille (un manche de balai).
    it = Item("stakeout", "shotgun")
    pump_gun(it, 14, "gun_dark", "wood_light", grip_key="wood")
    for k in (-12, -9, -7):
        it.paint_ring(k, "yellow", g="pump")
    it.put(0, 0, 3, "gun_black")
    return finish_long(it, ez=-1, ads=0.3)


def b_spas12():
    # CONCASSEUR : fusil à pompe industriel, pare-chaleur ajouré, pompe
    # orange carrée, crosse squelette.
    it = Item("spas12", "shotgun")
    pump_gun(it, 15, "gun_dark", "orange", stock="skeleton", shield=True)
    return finish_long(it, ez=-1, ads=0.3)


def b_hs10():
    # TOURNIQUET : fusil semi-automatique compact blanc, sangle noire à
    # boucle rouge serrée autour du corps.
    it = Item("hs10", "shotgun")
    pump_gun(it, 10, "white", None, grip_key="poly")
    it.box(-1, 2, -1, 4, -6, -5, "tape_black")
    it.put(2, 1, -6, "red")
    it.box(-1, 2, 0, 3, 3, 8, "white")
    it.box(-1, 2, -2, 3, 8, 9, "poly")
    return finish_long(it, ez=-1, ads=0.26)


# ---------------------------------------------------------------------------
# Précision
# ---------------------------------------------------------------------------

def scope(it, k0, k1, y0, body="gun_black", rings=None, objective=0, ring_key="brass"):
    """Lunette de 3 × 3 (sans les coins) de k0 (objectif) à k1 (oculaire)
    exclu, rangées y0 à y0 + 3 : axe au milieu de la rangée y0 + 1.
    `objective` : objectif élargi à 5 × 5 sur autant de tranches."""
    plus = lambda i, j, k: not (abs(i) == 1 and (j == y0 or j == y0 + 2))
    it.box(-1, 2, y0, y0 + 3, k0, k1, body, keep=plus)
    for k in range(k0, k0 + objective):
        it.box(-2, 3, y0 - 1, y0 + 4, k, k + 1, body,
               keep=lambda i, j, kk: not (abs(i) == 2 and (j == y0 - 1 or j == y0 + 3)))
    for k in rings or ():
        it.box(-1, 2, y0, y0 + 3, k, k + 1, ring_key, keep=plus)
    it.paint(0, y0 + 1, k0, "-z", "lens")
    it.paint(0, y0 + 1, k1 - 1, "+z", "lens_dark")
    it.a("sight", 0, y0 + 1.5, k1 - 0.5)
    it.a("front", 0, y0 + 1.5, k0 + 0.5)


def b_l96a1():
    # LONGUE-VUE : fusil à verrou, lunette en longue-vue de laiton à
    # bagues de cuir, fût et crosse en bois sombre, frein, bipied.
    it = Item("l96a1", "sniper")
    receiver(it, -4, 5, "steel")
    it.box(-1, 2, -1, 2, -15, -4, "wood_dark")
    barrel(it, -27, -15, 1, "gun_dark", "brake", "gun_black")
    cradle_support(it, -14, -6, -1)
    bipod(it, -22, 1, 7)
    box_mag(it, -2, 2, "gun_black")
    trigger(it, 5, -1)
    handle(it, 5, -1, 3, "wood_dark", toe=False)
    it.box(-1, 2, -1, 2, 5, 9, "wood_dark")
    it.box(-1, 2, -4, 2, 9, 17, "wood_dark")
    it.box(-1, 2, -4, 2, 17, 18, "poly")
    # Verrou (groupe « slide ») : levier coudé et boule à droite.
    it.put(0, 3, 2, "steel_light", g="slide")
    it.put(1, 3, 2, "steel_light", g="slide")
    it.put(2, 2, 2, "steel_light", g="slide")
    it.put(2, 1, 2, "gun_black", g="slide")
    it.a("pivot_slide", 0, 1.5, 2.5)
    it.info["slide_travel"] = 0.07
    it.info["bolt"] = True
    # Supports et longue-vue.
    for k in (-3, 3):
        it.put(0, 3, k, "gun_black")
    scope(it, -10, 7, 4, body="brass", rings=(-6, -1, 4), ring_key="brown")
    return finish_long(it, ez=1, ads=0.08)


def b_dragunov():
    # HIBOU : fusil de précision semi-automatique brun, lunette au gros
    # objectif rond (« œil de hibou »), crosse pleine à appui-joue, chargeur
    # court incurvé, long canon fin.
    it = Item("dragunov", "sniper")
    receiver(it, -5, 5, "gun_dark")
    it.box(-1, 2, 0, 2, -15, -5, "brown")
    barrel(it, -27, -15, 1, "gun_dark", "cage")
    cradle_support(it, -14, -6, 0)
    curved_mag(it, -4, 5, "gun_black")
    trigger(it, 1, 0)
    handle(it, 1, 0, 4, "brown")
    it.box(-1, 2, -1, 3, 5, 9, "brown")
    it.box(-1, 2, -3, 4, 9, 17, "brown")
    it.box(-1, 2, -3, 4, 17, 18, "poly")
    it.clear(-1, 2, -3, -1, 9, 12)
    for k in (-2, 2):
        it.put(0, 3, k, "gun_black")
    scope(it, -9, 5, 4, body="gun_black", objective=2, rings=(-4,), ring_key="olive_dark")
    charge(it, 2, 1, -1)
    return finish_long(it, ez=-1, ads=0.08)


# ---------------------------------------------------------------------------
# Explosifs
# ---------------------------------------------------------------------------

def b_china_lake():
    # TROMBONE : lance-grenades à pompe tout en laiton, coulisse de pompe
    # comme celle d'un trombone, pavillon évasé à la bouche, crosse en bois.
    it = Item("china_lake", "launcher")
    plus = lambda i, j, k: not (abs(i) == 1 and (j == 0 or j == 2))
    it.box(-1, 2, 0, 3, -20, 2, "brass", keep=plus)
    it.box(-2, 3, -1, 4, -22, -20, "brass", keep=lambda i, j, k: not (abs(i) == 2 and (j == -1 or j == 3)))
    it.paint(0, 1, -22, "-z", "bore")
    it.a("muzzle", 0, 1.5, -22)
    it.box(-1, 2, -1, 3, -2, 3, "brass_dark")
    for k in range(-18, -2):
        it.put(0, -1, k, "brass_dark")
    it.box(-1, 2, -3, -1, -14, -6, "brass", g="pump")
    it.box(0, 1, -2, 0, -15, -14, "brass_dark", g="pump")
    it.a("pivot_pump", 0, 0, 0)
    it.a("support", 0, -3, -10)
    for i in (-1, 1):
        it.put(i, 3, 0, "gun_black")
        it.put(i, 4, 0, "gun_black")
    it.put(0, 3, 0, "gun_black")
    it.a("sight", 0, 5, 0.5)
    it.box(0, 1, 3, 5, -19, -18, "gun_black")
    it.a("front", 0, 5, -18.5)
    trigger(it, 4, -1)
    handle(it, 4, -1, 4, "wood_dark")
    it.box(-1, 2, -1, 3, 3, 6, "wood")
    it.box(-1, 2, -3, 3, 6, 14, "wood")
    it.box(-1, 2, -3, 3, 14, 15, "wood_dark")
    it.a("pivot_mag", 0, -1, -1)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    return finish_long(it, ez=0, ads=0.28)


def b_law():
    # ÉPROUVETTE : lance-roquette en grosse éprouvette de laboratoire (tube de
    # verre de 5 cubes, coins abattus) à demi pleine d'un liquide vert,
    # graduée de blanc, bouchons de liège, bande orange de danger, visée
    # relevable, poignée de tir dessous.
    it = Item("law", "rocket")
    round5 = lambda i, j, k: not (abs(i) == 2 and (j == 0 or j == 4))
    it.box(-2, 3, 0, 5, -24, 12, "tube_glass", keep=round5)
    it.recolor("liquid", lambda i, j, k: j <= 1 and -23 <= k <= 6)
    for k in range(-21, 9, 3):
        it.paint(-2, 2, k, "-x", "white")
        it.paint(2, 2, k, "+x", "white")
    it.box(-2, 3, 0, 5, -25, -24, "cork", keep=round5)
    it.box(-2, 3, 0, 5, 12, 13, "cork", keep=round5)
    it.paint(0, 2, -25, "-z", "bore")
    it.box(-2, 3, 0, 5, -18, -17, "orange", keep=round5)
    it.a("muzzle", 0, 2.5, -25)
    iron(it, 8, -12, 5, 5)
    it.box(0, 1, -1, 0, -2, 3, "gun_black")
    trigger(it, 0, -1)
    handle(it, 0, -1, 4, "poly")
    it.a("support", 0, 0, -10)
    return finish_long(it, rw=2, rh=5, ez=0, ads=0.2)


# ---------------------------------------------------------------------------
# Corps à corps
# ---------------------------------------------------------------------------

def b_bat():
    # BATTE : batte de baseball en frêne clair, manche entouré de ruban aux
    # couleurs de l'équipe (bleu marine et blanc), pommeau, tête qui
    # s'élargit en escalier, quelques taches de sang de zombie. Pas de
    # barbelé, pas de marque.
    it = Item("bat", "melee")
    it.piece("body", (-0.5, -0.5, 0.0))
    plus = lambda i, j, k: i == 0 or j == 0
    it.box(-1, 2, -1, 2, 2, 3, "bat_dark", keep=plus)
    for k in range(-12, 2):
        it.put(0, 0, k, "navy" if (k % 3 == 0) else ("white" if k > -9 else "bat_wood"))
    it.box(-1, 2, -1, 2, -18, -12, "bat_wood", keep=plus)
    it.box(-1, 2, -1, 2, -31, -18, "bat_wood")
    it.box(-1, 2, -1, 2, -32, -31, "bat_dark", keep=plus)
    for c in ((1, 1, -27), (1, 0, -26), (0, 1, -24), (-1, 1, -29), (1, -1, -22)):
        it.recolor("blood", lambda i, j, k, c=c: (i, j, k) == c)
    it.a("grip", 0, 0, -2)
    it.a("support", 0, 0, -6)
    it.a("muzzle", 0, 0, -32)
    it.a("sight", 0, 0.5, 0)
    it.a("front", 0, 0.5, -30)
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    it.anchors["hold"] = [0.06, -0.12, 0.3]
    it.anchors["hold_rot"] = [1.15, 0.25, -0.35]
    it.info["no_sights"] = True
    it.info["grip_angle"] = -90.0
    it.info["support_fist"] = True
    it.info["elbows_cam"] = True
    return it


def b_knife():
    # COUTEAU : lame d'un cube d'épaisseur, fil clair en bas, garde en croix,
    # manche noir à bagues, pommeau d'acier. Origine : milieu du manche.
    it = Item("knife", "melee")
    it.piece("body", (-0.5, -0.5, 0.0))
    for k in range(-1, 3):
        it.put(0, 0, k, "poly" if k != 1 else "gun_dark")
    it.put(0, 0, 3, "steel")
    for j in (-1, 0, 1):
        it.put(0, j, -2, "gun_dark")
    for k in range(-7, -2):
        it.put(0, 0, k, "steel")
        it.put(0, -1, k, "steel_light")
    it.put(0, 0, -8, "steel")
    it.put(0, 0, -9, "steel_light")
    it.a("grip", 0, 0, -1)
    it.a("support", 0, 0, -1)
    it.a("muzzle", 0, 0, -9)
    it.a("sight", 0, 1.2, 0)
    it.info["no_sights"] = True
    return it


# ---------------------------------------------------------------------------
# Mains (ViewHands) : poings et avant-bras, chacun dans son repère.
# Poing : manche vertical (axe Y) en colonne i = 0, cellules k = -1 et 0,
# poing sous y = 0 ; dos de la main côté `side` (+1 : main droite).
# ---------------------------------------------------------------------------

def fist(it, g, side=1, index=False, fingers=4):
    p = it.piece(g, (-0.5, 0.0, 0.0))
    s = side
    for j in range(-4, 0):
        for k in (-1, 0, 1):
            it.put(s, j, k, "glove" if k != -1 else "glove_knuckle", g=g)
        it.put(0, j, 1, "glove_palm", g=g)
    rows = range(-4, -1) if index else range(-4, 0)
    for j in rows:
        for i in (-1, 0, 1):
            it.put(i, j, -2, "glove" if (j % 2) else "glove_knuckle", g=g)
        it.put(-s, j, -1, "glove_palm", g=g)
    if index:
        it.put(s, -1, -2, "glove", g=g)
        it.put(s, -1, -3, "glove", g=g)
        it.put(0, -1, -3, "glove_knuckle", g=g)
    # Pouce sur l'autre flanc, en haut.
    it.put(-s, -1 if index else 0, 0, "glove_knuckle", g=g)
    it.put(-s, -1 if index else 0, -1, "glove", g=g)
    # Poignet : sangle rouge du gant.
    for c in ((s, -5, 0), (s, -5, 1), (0, -5, 1)):
        it.put(*c, "strap", g=g)
    return p


def stick_fist(it, g, side):
    """Poing serré sur un manche fin d'un seul cube (batte) : pièce décalée
    d'un demi-cube en z pour centrer le trou du manche sur l'axe Y."""
    it.piece(g, (-0.5, 0.0, -0.5))
    s = side
    for j in range(-4, 0):
        for k in (-1, 0, 1):
            it.put(s, j, k, "glove" if k != -1 else "glove_knuckle", g=g)
        it.put(0, j, 1, "glove_palm", g=g)
        for i in (-1, 0):
            it.put(i * s, j, -1, "glove" if (j % 2) else "glove_knuckle", g=g)
        it.put(-s, j, 0, "glove_palm", g=g)
    it.put(-s, 0, 0, "glove_knuckle", g=g)
    it.put(-s, 0, 1, "glove", g=g)
    for c in ((s, -5, 0), (s, -5, 1), (0, -5, 1)):
        it.put(*c, "strap", g=g)


def b_hands():
    it = Item("hands", "hands", prefix="hand")
    fist(it, "grip", 1, index=True)
    fist(it, "foregrip", -1)
    fist(it, "knife", -1)
    stick_fist(it, "bat_r", 1)
    stick_fist(it, "bat_l", -1)
    # Main d'appui d'un pistolet : enveloppe le poing droit par la gauche et
    # par l'avant (doigts devant ceux de la main droite).
    g = "pistol_support"
    it.piece(g, (-0.5, 0.0, 0.0))
    for j in range(-4, -1):
        for k in (-2, -1, 0):
            it.put(-2, j, k, "glove", g=g)
        for i in (-2, -1, 0, 1):
            it.put(i, j, -3, "glove" if j % 2 else "glove_knuckle", g=g)
    it.put(-2, -1, -1, "glove_knuckle", g=g)
    it.put(-2, -1, 0, "glove", g=g)
    for c in ((-2, -5, -1), (-2, -5, 0)):
        it.put(*c, "strap", g=g)
    # Berceau : paume sous le garde-main, doigts sur le flanc droit, pouce à gauche.
    g = "cradle"
    it.piece(g, (-0.5, 0.0, 0.0))
    for i in (-1, 0, 1):
        for k in range(-2, 2):
            it.put(i, -1, k, "glove_palm", g=g)
    for k in range(-2, 2):
        for j in (-1, 0, 1):
            it.put(2, j, k, "glove" if k % 2 else "glove_knuckle", g=g)
    for c in ((-2, -1, 0), (-2, -1, 1), (-2, 0, -1), (-2, 0, 0)):
        it.put(*c, "glove", g=g)
    for c in ((-1, -2, 2), (0, -2, 2)):
        it.put(*c, "strap", g=g)
    # Lancer : main droite autour d'une grenade centrée (3 × 3 × 3).
    g = "throw_r"
    it.piece(g, (-0.5, -0.5, -0.5))
    for j in (-1, 0, 1):
        for k in (-1, 0, 1):
            it.put(2, j, k, "glove", g=g)
    for i in (-1, 0, 1):
        for k in (-1, 0, 1):
            it.put(i, -2, k, "glove_palm", g=g)
    for i in (-1, 0, 1):
        for j in (-1, 0):
            it.put(i, j, -2, "glove" if j else "glove_knuckle", g=g)
    it.put(-2, 0, -1, "glove", g=g)
    it.put(-2, 0, 0, "glove_knuckle", g=g)
    for c in ((2, -2, 0), (2, -2, 1)):
        it.put(*c, "strap", g=g)
    # Main gauche en pince (goupille).
    g = "throw_l"
    it.piece(g, (-0.5, 0.0, -0.5))
    it.box(0, 2, -3, -1, -1, 1, "glove", g=g)
    it.put(0, -1, -1, "glove_knuckle", g=g)
    it.put(-1, -1, -1, "glove", g=g)
    it.put(1, -1, 0, "glove", g=g)
    it.put(1, -4, 0, "strap", g=g)
    # Avant-bras : du coude (z = 0) au poignet (z = -12 cubes = 0,3 m), manche
    # du maillot derrière le coude ; section de 3 × 3 centrée sur l'axe.
    g = "forearm"
    it.piece(g, (-0.5, -0.5, 0.0))
    for k in range(-12, 1):
        key = "glove" if k == -12 else ("strap" if k == -11 else "undershirt")
        it.box(-1, 2, -1, 2, k, k + 1, key, g=g)
    for k in range(1, 12):
        key = "piping" if k in (3, 4) else "jersey"
        it.box(-2, 3, -2, 3, k, k + 1, key, g=g)
    it.box(-1, 2, -1, 2, 0, 1, "undershirt", g=g)
    # Poignets (repère de chaque pièce, cubes) : lus par ViewHands.
    it.a("wrist_grip", 1.0, -5.0, 1.5)
    it.a("wrist_foregrip", -1.0, -5.0, 1.5)
    it.a("wrist_bat_r", 1.0, -5.0, 0.75)
    it.a("wrist_bat_l", -1.0, -5.0, 0.75)
    it.a("wrist_knife", -1.0, -5.0, 1.5)
    it.a("wrist_pistol_support", -2.0, -5.0, -0.5)
    it.a("wrist_cradle", -0.5, -2.0, 2.5)
    it.a("wrist_throw_r", 2.0, -2.0, 1.0)
    it.a("wrist_throw_l", 1.0, -4.0, 0.5)
    return it


# ---------------------------------------------------------------------------
# Grenade, peluche leurre, cartouches
# ---------------------------------------------------------------------------

def b_frag():
    # Grenade : corps olive de 3 × 3 × 3 centré, bande sombre, bouchon
    # d'allumeur, cuillère ; goupille (anneau) dans un nœud à part « Pin ».
    it = Item("frag", "throwable", prefix="frag")
    it.piece("body", (-0.5, -0.5, -0.5))
    it.box(-1, 2, -1, 2, -1, 2, "frag_olive")
    it.box(-1, 2, 0, 1, -1, 2, "frag_band")
    it.put(0, 2, 0, "steel")
    it.put(0, 1, 2, "steel")
    it.put(0, 0, 2, "steel")
    it.piece("Pin", (0.0, -0.5, -0.5))
    it.put(0, 0, 0, "yellow", g="Pin")
    it.put(1, 0, 0, "yellow", g="Pin")
    return it


def b_teddy():
    # Peluche leurre : ours assis de ~24 cm (taille finale, sans mise à
    # l'échelle), face vers +Z, assis sur y = 0 : fourrure brune, museau et
    # coussinets clairs, yeux-boutons, nœud rouge, pièce rapiécée.
    it = Item("teddy", "throwable", prefix="teddy")
    it.piece("body", (-0.5, 0.0, -0.5))
    it.box(-2, 3, 1, 5, -1, 2, "fur")
    it.box(-1, 2, 1, 4, 2, 3, "fur_light")
    for i in (-2, 2):
        it.box(i, i + 1, 0, 2, 1, 4, "fur")
        it.put(i, 0, 4, "fur_light")
        it.put(i, 1, 4, "fur_light")
        it.box(i + (1 if i > 0 else -1), i + (2 if i > 0 else 0), 2, 4, 0, 2, "fur")
        it.put(i + (1 if i > 0 else -1), 2, 2, "fur_light")
    it.box(-1, 2, 0, 1, -1, 2, "fur")
    it.box(-1, 2, 5, 6, -1, 2, "ribbon")
    it.put(2, 5, 1, "ribbon")
    it.recolor("fur_patch", lambda i, j, k: (i, j, k) in ((-2, 3, 0), (-2, 4, 0)))
    # Tête (pièce « Head ») : crâne, oreilles, museau clair, truffe, yeux-boutons
    # (l'un recousu plus haut).
    h = "Head"
    it.piece(h, (-0.5, 0.0, -0.5))
    it.box(-2, 3, 6, 10, -2, 2, "fur", g=h)
    for i in (-2, 2):
        it.put(i, 10, 0, "fur", g=h)
        it.put(i, 10, -1, "fur_light", g=h)
    it.box(-1, 2, 6, 8, 2, 3, "fur_light", g=h)
    it.put(0, 7, 3, "button", g=h)
    it.paint(-1, 8, 1, "+z", "button", g=h)
    it.paint(1, 9, 1, "+z", "button", g=h)
    return it


def b_round_shell():
    it = Item("round_shell", "round")
    it.piece("body", (-0.5, -0.5, -1.5))
    it.put(0, 0, 2, "brass")
    it.put(0, 0, 1, "hull_red")
    it.put(0, 0, 0, "hull_red")
    it.info["no_sights"] = True
    return it


def b_round_40mm():
    it = Item("round_40mm", "round")
    it.piece("body", (-0.5, -0.5, -2.0))
    it.put(0, 0, 3, "brass")
    for k in (0, 1, 2):
        it.put(0, 0, k, "olive")
    it.info["no_sights"] = True
    return it


BUILDERS = {
    "m1911": b_m1911, "cz75": b_cz75, "python": b_python,
    "mp40": b_mp40, "mp5k": b_mp5k, "pm63": b_pm63, "mpl": b_mpl, "spectre": b_spectre, "ak74u": b_ak74u,
    "m14": b_m14, "m16": b_m16, "fnfal": b_fnfal, "g11": b_g11, "galil": b_galil, "famas": b_famas,
    "commando": b_commando, "aug": b_aug,
    "rpk": b_rpk, "hk21": b_hk21,
    "olympia": b_olympia, "stakeout": b_stakeout, "spas12": b_spas12, "hs10": b_hs10,
    "l96a1": b_l96a1, "dragunov": b_dragunov,
    "china_lake": b_china_lake, "law": b_law,
    "bat": b_bat, "knife": b_knife,
    "hands": b_hands, "frag": b_frag, "teddy": b_teddy,
    "round_shell": b_round_shell, "round_40mm": b_round_40mm,
}


# ---------------------------------------------------------------------------
# Cache, conversion, export
# ---------------------------------------------------------------------------

def save_cache(items, path):
    pal, pidx = [], {}

    def ci(c):
        k = tuple(round(float(x), 4) for x in c)
        if k not in pidx:
            pidx[k] = len(pal)
            pal.append(list(k))
        return pidx[k]

    data = {}
    for it in items:
        pieces = {}
        for g, p in it.pieces.items():
            cells = ["%d,%d,%d,%s,%d" % (c[0], c[1], c[2], v[0], ci(v[1])) for c, v in sorted(p.cells.items())]
            faces = ["%d,%d,%d,%s,%d" % (f[0], f[1], f[2], f[3], ci(v)) for f, v in sorted(p.faces.items())]
            pieces[g] = {"offset": list(p.offset), "cells": cells, "faces": faces}
        data[it.id] = {"family": it.family, "prefix": it.prefix, "anchors": it.anchors, "info": it.info, "pieces": pieces}
    old = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
    merged = old.get("items", {})
    merged.update(data)
    with open(path, "w", encoding="utf-8") as f:
        f.write('{\n"cube": %s,\n"palette": %s,\n"items": {\n' % (C, json.dumps(pal)))
        ids = sorted(merged)
        for n, iid in enumerate(ids):
            f.write("%s: %s%s\n" % (json.dumps(iid), json.dumps(merged[iid], ensure_ascii=False), "," if n < len(ids) - 1 else ""))
        f.write("}\n}\n")


def load_cache(path, ids):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    pal = [tuple(c) for c in data["palette"]]
    out = []
    for iid in ids:
        d = data["items"][iid]
        it = Item(iid, d["family"], d.get("prefix", "wpn"))
        it.anchors, it.info = d["anchors"], d["info"]
        for g, pd in d["pieces"].items():
            p = it.piece(g, tuple(pd["offset"]))
            for line in pd["cells"]:
                x, y, z, mat, c = line.split(",")
                p.cells[(int(x), int(y), int(z))] = (mat, pal[int(c)])
            for line in pd["faces"]:
                x, y, z, d2, c = line.split(",")
                p.faces[(int(x), int(y), int(z), d2)] = pal[int(c)]
        out.append(it)
    return out


def to_model(p):
    """Pièce (repère Godot) -> vx.Model (repère Blender), ombrage peint."""
    m = vx.Model(C)
    for (i, j, k), (mat, c) in p.cells.items():
        m.vox[(i, -k - 1, j)] = vx.Voxel(mat, None, mat, c)
    for (i, j, k, d), c in p.faces.items():
        m.face_color[(i, -k - 1, j, GDIR[d])] = c
    # Ombrage par direction Godot.
    inv = {v: k for k, v in GDIR.items()}
    for c, d in m.exposed():
        if m.mat_of(c, d) == "glow":
            continue
        m.face_color[(c[0], c[1], c[2], d)] = tuple(min(1.0, x * SHADE_G[inv[d]]) for x in m.color_of(c, d))
    return m


def boxes(p):
    """Pavés (repère Godot, m) couvrant les cellules de la pièce, par matière
    (fusion gloutonne) : [matière, centre x, y, z, taille x, y, z]."""
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
            ((i0 + i1) / 2.0 + ox) * C, ((j0 + j1) / 2.0 + oy) * C, ((k0 + k1) / 2.0 + oz) * C,
            (i1 - i0) * C, (j1 - j0) * C, (k1 - k0) * C)])
    return out


def export_item(it):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs, tris, models = [], 0, {}
    for g, p in it.pieces.items():
        m = to_model(p)
        ob, info = vx.build_mesh(m, "%s__%s__%s" % (it.prefix, it.id, g) if it.prefix == "wpn" else "%s__%s" % (it.prefix, g))
        ox, oy, oz = p.offset
        ob.location = (ox * C, -oz * C, oy * C)
        obs.append(ob)
        models[g] = (m, ob)
        tris += info["tris"]
    path = os.path.join(OUT_DIR, it.id + ".glb")
    vx.export_glb(path, obs, C)
    spec = {"family": it.family, "anchors": it.anchors, "info": it.info, "tris": tris, "boxes": [],
            "groups": sorted(it.pieces)}
    for g, p in it.pieces.items():
        for b in boxes(p):
            spec["boxes"].append([g] + b)
    print("[weapons_voxel] %-12s %3d triangles  %s" % (it.id, tris, ", ".join(
        "%s %d" % (g, len(p.cells)) for g, p in it.pieces.items())))
    return path, spec, models


# ---------------------------------------------------------------------------
# Planches de validation
# ---------------------------------------------------------------------------

# Vues : profil gauche, trois-quarts avant gauche, vue du tireur (derrière,
# un peu à gauche et au-dessus), dessus.
VIEWS = (("profil", -90.0, 0.0), ("trois-quarts", -140.0, 22.0), ("tireur", -20.0, 20.0), ("dessus", -90.0, 88.0))
# Planche d'ensemble : profil de chaque arme dans un cadre de 1,45 m.
SAME_SCALE = 1.45


def _frame(obs):
    lo, hi = [1e9] * 3, [-1e9] * 3
    for o in obs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], p[i]), max(hi[i], p[i])
    return tuple((a + b) / 2 for a, b in zip(lo, hi)), max(hi[i] - lo[i] for i in range(3))


def board(it, models, sheet_dir, same_scale=False):
    """Planche <sheet_dir>/<id>.png (VIEWS, contour noir). Renvoie le chemin
    et, si `same_scale`, le profil rendu dans un cadre de SAME_SCALE m."""
    tmp = os.path.join(sheet_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    vx.setup_render((480, 480))
    outl = []
    for g, (m, ob) in models.items():
        o = vx.add_outline(m, ob.name + "_outline", thickness=0.003)
        o.location = ob.location
        outl.append(o)
    bpy.context.view_layer.update()
    c, s = _frame([ob for _, ob in models.values()])
    imgs = []
    for name, az, el in VIEWS:
        p = os.path.join(tmp, "%s_%s.png" % (it.id, name))
        vx.render_view(p, az, c, s * 1.25, elev=el, dist=10.0)
        imgs.append(vx.load_png(p))
    path = os.path.join(sheet_dir, it.id + ".png")
    vx.save_png(vx.sheet([imgs], 480, 480), path)
    side = None
    if same_scale:
        p = os.path.join(tmp, "%s_echelle.png" % it.id)
        vx.render_view(p, -90.0, c, SAME_SCALE, elev=0.0, dist=10.0)
        side = vx.load_png(p)
    for o in outl:
        bpy.data.objects.remove(o)
    return path, side


def overview(sides, sheet_dir):
    """Toutes les armes de profil, à la même échelle (1,1 m de large)."""
    rows, row = [], []
    for iid, img in sides:
        row.append(img)
        if len(row) == 6:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    path = os.path.join(sheet_dir, "_toutes.png")
    vx.save_png(vx.sheet(rows, 300, 300), path)
    return path


# Objets aux pièces indépendantes (mains, grenade et goupille...) : chaque
# pièce est vérifiée dans le repère de son nœud (mode « animé » de
# voxel_check) ; les armes le sont d'un bloc (mode statique : toutes les
# pièces sur la même grille, pièces mobiles comprises).
ARTICULATED = ("hands", "frag", "teddy", "round_shell", "round_40mm")


def godot_check(paths):
    """Lance tools/voxel_check.gd (variable GODOT : exécutable de Godot, un
    vrai .exe sous Windows ; sinon « godot » s'il est trouvable)."""
    import shutil
    exe = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot.exe")
    if not exe:
        print("[weapons_voxel] Godot introuvable (variable GODOT) : vérification non faite")
        return False
    ok = True
    for anim in (False, True):
        sel = [p for p in paths if (os.path.splitext(os.path.basename(p))[0] in ARTICULATED) == anim]
        if not sel:
            continue
        rels = ["res://" + os.path.relpath(p, ROOT).replace("\\", "/") for p in sel]
        cmd = [exe, "--headless", "--path", ROOT, "-s", "res://tools/voxel_check.gd", "--"] + rels + [
            "--anime" if anim else "--statique", "--pas=2.5"]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
        print("\n".join(l for l in r.stdout.splitlines() if "voxel_check" in l or l.startswith("  ")))
        ok = ok and r.returncode == 0
    return ok


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir, check, use_cache, ids = "", True, False, []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sheet":
            sheet_dir = os.path.abspath(args[i + 1])
            i += 1
        elif a == "--no-check":
            check = False
        elif a == "--cache":
            use_cache = True
        else:
            ids.append(a)
        i += 1
    ids = ids or list(BUILDERS)
    items = load_cache(CACHE, ids) if use_cache else [BUILDERS[iid]() for iid in ids]
    if not use_cache:
        save_cache(items, CACHE)
    specs = {}
    if os.path.exists(SPEC_JSON):
        with open(SPEC_JSON, encoding="utf-8") as f:
            specs = json.load(f)
    paths, sides = [], []
    for it in items:
        path, spec, models = export_item(it)
        specs[it.id] = spec
        paths.append(path)
        if sheet_dir:
            weapon = it.family not in ("hands", "throwable", "round")
            _p, side = board(it, models, sheet_dir, same_scale=weapon)
            if weapon:
                sides.append((it.id, side))
    with open(SPEC_JSON, "w", encoding="utf-8") as f:
        f.write("{\n")
        keys = sorted(specs)
        for n, k in enumerate(keys):
            f.write("%s: %s%s\n" % (json.dumps(k), json.dumps(specs[k], ensure_ascii=False), "," if n < len(keys) - 1 else ""))
        f.write("}\n")
    if sheet_dir and sides:
        print("[weapons_voxel] planche d'ensemble : " + overview(sides, sheet_dir))
    if check and not godot_check(paths):
        print("[weapons_voxel] NON CONFORMES")
        sys.exit(1)


main()
