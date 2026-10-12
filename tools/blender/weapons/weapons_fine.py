# ARMES FINES EN CUBES DE 1,25 CM (refonte des armes, une par une) :
# chaque arme reprend une ARME RÉELLE de référence (fiche docs/weapons/<id>.md,
# nom affiché proche du vrai), en cubes DEUX FOIS PLUS PETITS que les
# personnages (exception validée le 2026-10-12 : 1,25 cm, sous-multiple
# exact de 2,5 cm ; les mains de la vue FPS aussi, hands_fine.py).
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
    "laminate": ("wood", (0.47, 0.22, 0.12)),     # bois lamellé-collé rougeâtre (AK)
    "plum": ("rubber", (0.36, 0.17, 0.13)),       # polymère « prune » (chargeur, poignée AK-74)
    "plum_dark": ("rubber", (0.25, 0.12, 0.09)),
    "bakelite": ("rubber", (0.47, 0.21, 0.11)),   # chargeur de 30 orangé-brun
    "bakelite_dark": ("rubber", (0.32, 0.14, 0.08)),
    "ak_wood": ("wood", (0.56, 0.29, 0.14)),      # bois verni rouge-brun (AK-47)
    "ak_wood_dark": ("wood", (0.40, 0.20, 0.10)),
    "blued": ("metal", (0.13, 0.14, 0.17)),       # acier bronzé bleu-noir (boîtier usiné)
    "poly": ("rubber", (0.15, 0.15, 0.155)),       # polymère noir
    "poly_dark": ("rubber", (0.20, 0.205, 0.21)),  # polymère gris anthracite
    "rubber_black": ("rubber", (0.08, 0.08, 0.085)),
    "maroon": ("rubber", (0.30, 0.13, 0.10)),     # bakélite brun-rouge (MP40)
    "maroon_dark": ("rubber", (0.20, 0.08, 0.06)),
    "red": ("rubber", (0.66, 0.10, 0.08)),          # repère rouge du sélecteur
    "brown": ("rubber", (0.30, 0.21, 0.15)),        # plaquettes en polymère brun (PM-63)
    "g11_body": ("rubber", (0.20, 0.22, 0.18)),     # polymère vert-noir (G11)
    "g11_mag": ("rubber", (0.14, 0.15, 0.13)),
    "lens": ("glass", (0.20, 0.40, 0.52)),          # objectif de lunette
    "galil_wood": ("wood", (0.66, 0.46, 0.27)),     # bois clair (Galil)
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
    def __init__(self, iid, family, cube=FINE, even=False):
        """even : largeurs PAIRES, l'axe du canon passe ENTRE les colonnes
        i = -1 et 0 (pièces sans décalage) ; sinon l'axe est au milieu de la
        colonne i = 0 (décalage d'un demi-cube)."""
        self.id, self.family, self.cube = iid, family, cube
        self.pieces, self.anchors, self.info = {}, {}, {}
        self.offset = (0.0, 0.0, 0.0) if even else (-0.5, 0.0, 0.0)

    def piece(self, g):
        if g not in self.pieces:
            self.pieces[g] = Piece(self.offset)
        return self.pieces[g]

    def put(self, i, j, k, key, g="body", f=None, amp=0.04):
        mat, base = PAL[key]
        if f is None:
            # Texture « un pixel = un cube » : deux paliers de teinte.
            f = 1.0 + amp * (1 if vx.noise((i, j, k), len(key)) > 0.5 else -1)
        self.piece(g).cells[(i, j, k)] = (mat, vx.tone(base, f))

    def fill(self, i0, i1, j0, j1, k0, k1, key, g="body", f=None):
        """Pavé de cellules, bornes INCLUSES."""
        for i in range(i0, i1 + 1):
            for j in range(j0, j1 + 1):
                for k in range(k0, k1 + 1):
                    self.put(i, j, k, key, g, f=f)

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
    # Vue FPS : le poing droit (hands_fine.py, ViewHands) suit l'inclinaison
    # de la poignée (même axe que la sortie du chargeur, environ 16°).
    it.info["grip_angle"] = -round(math.degrees(math.atan2(d[2], -d[1])), 1)
    it.info["slide_travel"] = 0.03
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.4]
    it.anchors["hold"] = [-0.06, 0.12, 0.25]
    it.anchors["hold_rot"] = [0.0, 0.32, -0.08]
    # Points d'attache des pièces visibles (docs/weapons/m1911.md).
    it.a("att_muzzle", 0, 2.5, -11)
    it.a("att_optic", 0, 3, 1.5)
    it.a("att_mag", 0, -7, 4.5)
    it.a("att_grip_l", -1.5, -3, 3.5)
    it.a("att_grip_r", 1.5, -3, 3.5)
    return it


# ---------------------------------------------------------------------------
# AK-74U (id interne « ak74u ») : AKS-74U réel, 730 mm crosse dépliée ->
# 58 cubes. Cache-flamme « booster » en cloche, bloc de guidon, garde-main en
# lamellé-collé, boîtier embouti noir (rivets, fenêtre d'éjection, levier
# d'armement et grand levier de sélecteur à droite), hausse sur la charnière
# du couvercle, chargeur de 30 courbe et poignée en polymère prune, crosse
# triangulaire repliable en tôle.
# ---------------------------------------------------------------------------

def b_ak74u():
    it = Item("ak74u", "smg")

    def box(i0, i1, j0, j1, k0, k1, key, g="body", f=None):
        for i in range(i0, i1 + 1):
            for j in range(j0, j1 + 1):
                for k in range(k0, k1 + 1):
                    it.put(i, j, k, key, g, f=f)

    # Boîtier (k = -11 à 7) : corps embouti, couvercle (rangée 3).
    box(-1, 1, 0, 2, -11, 7, "gun_dark")
    box(-1, 1, 3, 3, -11, 7, "gun_black")
    it.put(0, 3, 8, "gun_black")  # bouton du couvercle
    # Hausse sur la charnière du couvercle : deux oreilles, cran d'un cube.
    for i in (-1, 1):
        for k in (-11, -10):
            it.put(i, 4, k, "gun_black")
    # Garde-main en lamellé-collé (k = -20 à -12) : bas (canon) et haut (tube
    # à gaz), veinage en couches (une rangée sur deux plus claire).
    for j in range(0, 4):
        f = (1.06 if j % 2 else 0.94) * (0.9 if j >= 2 else 1.0)
        box(-1, 1, j, j, -20, -12, "laminate", f=f)
    for i, d in ((1, "+x"), (-1, "-x")):
        it.paint(i, 1, -12, d, "gun_black")  # joint garde-main / boîtier
        it.paint(i, 2, -20, d, "gun_black")
    # Bloc de guidon et guidon (lame d'un cube, ligne de mire à j = 5).
    box(-1, 1, 0, 3, -23, -21, "gun_black")
    it.put(0, 4, -22, "gun_black")
    # « Booster » : cylindre (croix 3 × 3) puis cloche pleine à l'avant.
    for k in range(-27, -23):
        for (i, j) in ((0, 0), (0, 1), (0, 2), (-1, 1), (1, 1)):
            it.put(i, j, k, "gun_black")
    box(-1, 1, 0, 2, -29, -28, "gun_black")
    it.paint(0, 1, -29, "-z", "bore")
    # Chargeur de 30 (pièce « mag ») : 5 cubes de profondeur, courbe vers
    # l'avant d'un cube toutes les trois rangées, semelle sombre, ergots.
    for r in range(12):
        s = -(r // 3)
        box(-1, 1, -1 - r, -1 - r, -7 + s, -3 + s, "bakelite", g="mag")
    box(-1, 1, -13, -13, -11, -7, "bakelite_dark", g="mag")
    it.put(0, -1, -8, "gun_dark", g="mag")  # ergot avant
    for i, d in ((1, "+x"), (-1, "-x")):
        for k in range(-7, -2):
            it.paint(i, -2, k, d, "bakelite_dark", g="mag")  # nervure de renfort
    # Pontet embouti et détente.
    for j in (-1, -2):
        it.put(0, j, -2, "gun_black")
    for k in range(-2, 2):
        it.put(0, -3, k, "gun_black")
    it.put(0, -1, 0, "gun_black")
    # Poignée prune inclinée (un cube toutes les trois rangées), culot sombre.
    for r in range(8):
        s = r // 3
        box(-1, 1, -1 - r, -1 - r, 1 + s, 3 + s, "plum_dark" if r == 7 else "plum")
    # Crosse triangulaire repliable : charnière, bras haut droit, bras bas
    # en escalier, plaque de couche.
    box(-1, 1, 0, 3, 8, 9, "gun_black")
    for k in range(10, 27):
        it.put(0, 3, k, "gun_black")
    prev = 0
    for k in range(10, 27):
        j = -round((k - 10) * 6 / 16.0)
        for jj in range(j, prev + 1):
            it.put(0, jj, k, "gun_black")
        prev = j
    box(-1, 1, -7, 3, 27, 27, "gun_black")
    box(0, 0, -7, 3, 26, 26, "gun_black")
    # Flanc droit : fenêtre d'éjection (porte-culasse clair au fond), levier
    # d'armement (pièce « slide »), grand levier de sélecteur peint.
    for k in range(-5, -1):
        it.drop(1, 2, k)
        it.put(0, 2, k, "steel_light")
    it.drop(1, 2, -6)
    it.put(1, 2, -6, "steel", g="slide")
    it.put(2, 2, -6, "steel", g="slide")
    for k in range(-1, 7):
        it.paint(1, 2, k, "+x", "gun_black")
    it.paint(1, 1, 6, "+x", "gun_black")
    # Rivets (tourillons avant et arrière, puits du chargeur), deux flancs.
    for i, d in ((1, "+x"), (-1, "-x")):
        for (j, k) in ((1, -10), (0, -8), (0, -4), (1, 6)):
            it.paint(i, j, k, d, "steel")
    # Points remarquables.
    line = 5
    it.a("sight", 0, line, -10.0)
    it.a("front", 0, line, -21.5)
    it.a("muzzle", 0, 1.5, -29)
    it.a("eject", 1.0, 2.5, -3.5)
    it.a("grip", 0, 0, 2.5)
    it.a("support", 0, 0, -16)
    it.a("pivot_slide", 2, 2.5, -5.5)
    it.a("pivot_mag", 0, 0, -4.5)
    d = (0.0, -13.0, -4.0)
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    # Vue FPS : le poing droit suit la poignée (un cube toutes les trois
    # rangées).
    it.info["grip_angle"] = -round(math.degrees(math.atan2(1.0, 3.0)), 1)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/ak74u.md).
    it.a("att_muzzle", 0, 1.5, -29)
    it.a("att_optic", 0, 4, -2)
    it.a("att_mag", 0, -1, -4.5)
    it.a("att_stock", 0, 1.5, 8)
    it.a("att_rail", 0, 0, -16)
    return it


# ---------------------------------------------------------------------------
# AK-47 (id interne « ak47 », arme nouvelle) : AK-47 type 3 réel (boîtier
# usiné), 880 mm -> 70 cubes. Bloc de guidon à oreilles au bout du canon,
# baguette de nettoyage sous le canon nu, bloc d'emprunt de gaz, garde-mains
# en bois verni, hausse à planchette, boîtier bronzé à évidements usinés,
# chargeur d'acier de 30 très courbé, poignée et crosse fixe en bois.
# ---------------------------------------------------------------------------

def b_ak47():
    it = Item("ak47", "rifle")
    F = it.fill
    # Boîtier (k = -11 à 7) et couvercle.
    F(-1, 1, 0, 2, -11, 7, "blued")
    F(-1, 1, 3, 3, -10, 7, "gun_black")
    it.put(0, 3, 8, "gun_black")  # bouton du couvercle
    # Évidements usinés au-dessus du puits du chargeur (deux flancs), peints.
    for i, d in ((1, "+x"), (-1, "-x")):
        for k in range(-9, -4):
            it.paint(i, 1, k, d, "bore", f=3.0)
    # Hausse à planchette (bloc sur l'arrière du tube à gaz, deux oreilles).
    F(-1, 1, 3, 3, -14, -11, "gun_black")
    for i in (-1, 1):
        F(i, i, 4, 4, -12, -11, "gun_black")
    # Garde-mains en bois : bas (k = -26 à -12), haut sur le tube à gaz
    # (k = -24 à -15), tube à gaz nu devant.
    F(-1, 1, 0, 1, -26, -12, "ak_wood")
    F(-1, 1, 2, 3, -24, -15, "ak_wood", f=0.92)
    F(0, 0, 2, 3, -26, -25, "blued")
    for i, d in ((1, "+x"), (-1, "-x")):
        it.paint(i, 0, -12, d, "blued")    # frette arrière du garde-main
        it.paint(i, 1, -12, d, "blued")
    # Bloc d'emprunt de gaz (tour à 45° simplifiée).
    F(-1, 1, 0, 3, -29, -27, "blued")
    # Canon nu et baguette de nettoyage dessous (jour d'un cube entre eux).
    F(0, 0, 1, 1, -42, -30, "gun_black")
    F(0, 0, -1, -1, -43, -27, "steel")
    F(0, 0, -1, 0, -26, -26, "blued")       # tenon de la baguette
    # Bloc de guidon : base, guidon d'un cube (ligne de mire à j = 5),
    # oreilles de protection plus hautes de part et d'autre, tenon de baïonnette.
    F(-1, 1, 0, 2, -45, -43, "blued")
    F(0, 0, 3, 4, -44, -44, "gun_black")
    for i in (-1, 1):
        F(i, i, 3, 5, -44, -44, "blued")
    it.put(0, -1, -44, "blued")
    it.put(0, 1, -46, "gun_black")           # écrou de bouche
    it.paint(0, 1, -46, "-z", "bore")
    # Chargeur d'acier de 30 (pièce « mag ») : 6 cubes de profondeur, très
    # courbé (un cube vers l'avant toutes les deux rangées et demie),
    # nervures embouties sur les flancs, semelle.
    last = 0
    for r in range(14):
        s = -((r * 2) // 5)
        F(-1, 1, -1 - r, -1 - r, -8 + s, -3 + s, "gun_dark", g="mag")
        for i, d in ((1, "+x"), (-1, "-x")):
            it.paint(i, -1 - r, -6 + s, d, "gun_black", g="mag")
        last = s
    F(-1, 1, -15, -15, -8 + last, -3 + last, "gun_black", g="mag")
    it.put(0, -1, -9, "steel", g="mag")      # ergot avant
    # Pontet, détente.
    for j in (-1, -2):
        it.put(0, j, -2, "gun_black")
    for k in range(-2, 2):
        it.put(0, -3, k, "gun_black")
    it.put(0, -1, 0, "gun_black")
    # Poignée en bois inclinée.
    for r in range(8):
        s = r // 3
        F(-1, 1, -1 - r, -1 - r, 1 + s, 3 + s, "ak_wood_dark" if r == 7 else "ak_wood")
    # Crosse fixe en bois : poignet sous la ligne du boîtier, dessus qui
    # descend de deux rangées, dessous qui plonge vers la plaque de couche.
    for k in range(8, 23):
        t = (k - 8) / 14.0
        top = 3 - round(2 * t)
        bot = 0 - round(7 * t)
        F(-1, 1, bot, top, k, k, "ak_wood")
    F(-1, 1, -7, 1, 23, 23, "blued")          # plaque de couche
    for i, d in ((1, "+x"), (-1, "-x")):
        it.paint(i, -2, 22, d, "steel")      # vis de la plaque
    # Flanc droit : fenêtre d'éjection, levier d'armement (« slide »),
    # levier de sélecteur peint.
    for k in range(-5, -1):
        it.drop(1, 2, k)
        it.put(0, 2, k, "steel_light")
    it.drop(1, 2, -6)
    it.put(1, 2, -6, "steel", g="slide")
    it.put(2, 2, -6, "steel", g="slide")
    for k in range(-1, 7):
        it.paint(1, 2, k, "+x", "gun_black")
    it.paint(1, 1, 6, "+x", "gun_black")
    # Points remarquables.
    line = 5
    it.a("sight", 0, line, -11.0)
    it.a("front", 0, line, -43.5)
    it.a("muzzle", 0, 1.5, -46)
    it.a("eject", 1.0, 2.5, -3.5)
    it.a("grip", 0, 0, 2.5)
    it.a("support", 0, 0, -19)
    it.a("pivot_slide", 2, 2.5, -5.5)
    it.a("pivot_mag", 0, 0, -5)
    d = (0.0, -15.0, float(last))
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    # Vue FPS : le poing droit suit la poignée (un cube toutes les trois
    # rangées).
    it.info["grip_angle"] = -round(math.degrees(math.atan2(1.0, 3.0)), 1)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/ak47.md).
    it.a("att_muzzle", 0, 1.5, -46)
    it.a("att_optic", 0, 4, -3)
    it.a("att_mag", 0, -1, -5)
    it.a("att_stock", 0, 1.5, 8)
    it.a("att_rail", 0, 0, -19)
    return it


# ---------------------------------------------------------------------------
# FAMAS (id interne « famas ») : FAMAS F1 réel, bullpup, 757 mm -> 61 cubes.
# Manchon lance-grenades à bagues au bout du canon, garde-main en polymère
# ajouré, bipied replié le long des flancs, poignée de transport en pont
# qui porte les organes de visée (gouttière au milieu), levier d'armement
# dessous, pontet intégral qui couvre toute la main, chargeur droit de 25
# derrière la poignée, fenêtre d'éjection à droite, plaque de couche.
# ---------------------------------------------------------------------------

def b_famas():
    it = Item("famas", "rifle")
    F = it.fill
    # Corps (k = -20 à 29), 6 rangées ; avant du garde-main chanfreiné.
    F(-1, 1, 0, 5, -18, 29, "poly_dark")
    F(-1, 1, 1, 4, -20, -19, "poly_dark")
    # Garde-main (k = -20 à -7) un peu plus sombre, fentes d'aération.
    for (i, j, k), (mat, _c) in list(it.piece("body").cells.items()):
        if k <= -7:
            it.put(i, j, k, "poly")
    for i, d in ((1, "+x"), (-1, "-x")):
        for k in (-16, -14, -12, -10):
            it.paint(i, 4, k, d, "rubber_black")
    # Crosse : le dessous plonge vers l'arrière, plaque de couche en caoutchouc.
    for k in range(14, 30):
        bot = -round((k - 14) * 3 / 15.0)
        F(-1, 1, bot, -1, k, k, "poly_dark")
    F(-1, 1, -3, 5, 30, 30, "rubber_black")
    # Canon et manchon lance-grenades (section en croix, deux bagues pleines,
    # cache-flamme au bout).
    F(0, 0, 2, 2, -22, -21, "gun_black")
    for k in range(-30, -22):
        for (i, j) in ((0, 1), (0, 2), (0, 3), (-1, 2), (1, 2)):
            it.put(i, j, k, "gun_black")
    for k in (-28, -24):
        F(-1, 1, 1, 3, k, k, "gun_dark")
    it.paint(0, 2, -30, "-z", "bore")
    # Bipied replié le long des flancs (pivot à l'avant).
    for i in (-2, 2):
        F(i, i, 2, 3, -19, -19, "gun_black")
        F(i, i, 2, 2, -18, -7, "steel", f=0.8)
        it.put(i, 1, -7, "rubber_black")          # patin
    # Poignée de transport : montants avant (k = -14 à -12) et arrière
    # (k = 8 à 11), pont à deux ailes (gouttière d'un cube au milieu).
    F(-1, 1, 6, 7, -14, -12, "gun_black")
    F(-1, 1, 6, 7, 8, 11, "gun_black")
    for k in range(-14, 12):
        it.put(0, 8, k, "gun_black")
        for i in (-1, 1):
            F(i, i, 8, 9, k, k, "gun_black")
    # Guidon (lame d'un cube) entre deux oreilles plus hautes, hausse à deux
    # oreilles au bout arrière : ligne de mire à j = 11.
    F(0, 0, 9, 10, -13, -13, "gun_black")
    for i in (-1, 1):
        F(i, i, 10, 11, -13, -13, "gun_black")
        F(i, i, 10, 10, 9, 10, "gun_black")
    # Levier d'armement sous la poignée de transport (pièce « slide »).
    F(0, 0, 6, 6, -10, -9, "steel", g="slide")
    # Poignée (légèrement inclinée), détente, pontet intégral.
    for r in range(8):
        s = r // 4
        F(-1, 1, -1 - r, -1 - r, 1 + s, 3 + s, "poly")
    for j in range(-8, 0):
        it.put(0, j, -2, "poly_dark")
    for k in range(-2, 5):
        it.put(0, -9, k, "poly_dark")
    F(0, 0, -2, -1, 0, 0, "gun_black")
    # Chargeur droit de 25 derrière la poignée (pièce « mag »).
    F(-1, 1, -10, -1, 5, 9, "parker", g="mag")
    F(-1, 1, -11, -11, 5, 9, "parker_dark", g="mag")
    for i, d in ((1, "+x"), (-1, "-x")):
        for j in range(-9, -1):
            it.paint(i, j, 7, d, "parker_dark", g="mag")
    # Fenêtre d'éjection (flanc droit), arrêtoir de joue (flanc gauche).
    for k in range(10, 15):
        it.paint(1, 4, k, "+x", "bore", f=3.0)
    for k in range(10, 16):
        it.paint(-1, 4, k, "-x", "poly")
        it.paint(-1, 3, k, "-x", "poly")
    # Points remarquables.
    line = 11
    it.a("sight", 0, line, 10.0)
    it.a("front", 0, line, -12.5)
    it.a("muzzle", 0, 2.5, -30)
    it.a("eject", 1.5, 4.5, 12)
    it.a("grip", 0, 0, 2.5)
    it.a("support", 0, 0, -12)
    it.a("pivot_slide", 0, 6.5, -9.5)
    it.a("pivot_mag", 0, 0, 7.5)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = round(11 * FINE, 4)
    # Vue FPS : le poing droit suit la poignée (un cube toutes les quatre rangées).
    it.info["grip_angle"] = -round(math.degrees(math.atan2(1.0, 4.0)), 1)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/famas.md).
    it.a("att_muzzle", 0, 2.5, -30)
    it.a("att_optic", 0, 10, -2)
    it.a("att_mag", 0, -1, 7.5)
    it.a("att_stock", 0, 2.5, 30)
    it.a("att_rail", 0, 0, -12)
    return it



# ---------------------------------------------------------------------------
# MP40 (id interne « mp40 ») : MP40 réel, 833 mm crosse dépliée -> 67 cubes.
# Largeurs PAIRES (axe du canon entre deux colonnes, i = -1 et 0 ; pièces
# sans décalage) : canon de 2 × 2, boîtier rond de 4 × 4 (coins abattus),
# guidon et cran de 2 cubes. Guidon à oreilles, arrêtoir d'appui sous le
# canon, écrou de canon, levier d'armement à gauche dans sa longue fente,
# fenêtre d'éjection à droite, long puits de chargeur nervuré, chargeur droit
# de 32, carcasse avant en bakélite brun-rouge, carcasse de poignée d'acier à
# plaquettes de bakélite nervurées, crosse repliable à deux bras emboutis et
# plaque de couche en U. Aucun marquage.
# ---------------------------------------------------------------------------

def b_mp40():
    it = Item("mp40", "smg", even=True)
    F = it.fill
    W = (-2, 1)  # colonnes extérieures (largeur 4 : i = -2 à 1)

    def octo(j0, k0, k1, key):
        """Tube de 4 × 4 aux coins abattus, rangées j0 à j0 + 3."""
        for i in range(-2, 2):
            for j in range(j0, j0 + 4):
                if i in W and j in (j0, j0 + 3):
                    continue
                for k in range(k0, k1 + 1):
                    it.put(i, j, k, key)

    # Boîtier (k = -21 à 5) et bouchon arrière plein.
    octo(0, -21, 5, "blued")
    F(-2, 1, 0, 3, 6, 6, "gun_black")
    # Écrou de canon, canon de 2 × 2 (axe y = 2), arrêtoir d'appui.
    F(-2, 1, 0, 3, -23, -22, "gun_black")
    F(-1, 0, 1, 2, -37, -24, "gun_dark")
    F(-1, 0, -1, 0, -32, -28, "gun_dark")
    for i in (-1, 0):
        for j in (1, 2):
            it.paint(i, j, -37, "-z", "bore")
    # Guidon (2 cubes, ligne de mire à j = 5) : bague autour du canon, deux
    # oreilles de protection plus hautes de part et d'autre.
    for (i, j) in [(i, j) for i in range(-2, 2) for j in range(0, 4) if not (i in W and j in (0, 3))]:
        F(i, i, j, j, -36, -35, "gun_black")
    F(-1, 0, 4, 4, -36, -36, "gun_black")
    for i in W:
        F(i, i, 3, 5, -36, -36, "gun_black")
    # Hausse : socle sur le boîtier (coins comblés), deux oreilles, cran de 2.
    F(-2, 1, 3, 3, -7, -5, "gun_black")
    for i in W:
        F(i, i, 4, 4, -6, -5, "gun_black")
    # Flanc gauche : longue fente et levier d'armement (pièce « slide »).
    for k in range(-16, -1):
        it.paint(-2, 2, k, "-x", "bore", f=3.0)
    it.paint(-2, 2, -1, "-x", "bore", f=3.0)
    it.paint(-2, 3 - 1, 0, "-x", "gun_black")
    F(-4, -3, 2, 2, -9, -8, "steel", g="slide")
    # Flanc droit : fenêtre d'éjection.
    for k in range(-15, -11):
        it.paint(1, 2, k, "+x", "bore", f=3.0)
    # Puits du chargeur (k = -18 à -14, 8 rangées), nervuré, bouton de
    # déverrouillage à gauche ; creux pour le chargeur.
    F(-2, 1, -8, -1, -18, -14, "gun_dark")
    for i, d in ((1, "+x"), (-2, "-x")):
        for j in (-2, -4, -6):
            for k in range(-18, -13):
                it.paint(i, j, k, d, "gun_black")
    it.paint(-2, -2, -14, "-x", "steel")
    for i in (-1, 0):
        for j in range(-8, 0):
            for k in range(-17, -14):
                it.drop(i, j, k)
    # Chargeur droit de 32 (pièce « mag ») : 2 × 3 cubes, 20 rangées.
    F(-1, 0, -20, -1, -17, -15, "gun_black", g="mag")
    F(-2, 1, -21, -21, -18, -14, "gun_dark", g="mag")
    # Carcasse sous le boîtier : avant en bakélite brun-rouge (k = -12 à -1),
    # arrière en acier (k = 0 à 5).
    F(-2, 1, -3, -1, -12, -1, "maroon")
    F(-2, 1, -3, -1, 0, 5, "gun_dark")
    for i, d in ((1, "+x"), (-2, "-x")):
        for k in range(-11, -1, 2):
            it.paint(i, -2, k, d, "maroon_dark")
    # Pontet et détente.
    F(-1, 0, -6, -4, -3, -3, "gun_black")
    F(-1, 0, -6, -6, -2, 0, "gun_black")
    F(-1, 0, -5, -4, 0, 0, "gun_black")
    # Poignée (k = 1 à 4, 10 rangées, légèrement inclinée) : carcasse d'acier
    # au milieu, plaquettes de bakélite nervurées sur les flancs.
    for r in range(10):
        s = r // 5
        j = -4 - r
        F(-1, 0, j, j, 1 + s, 4 + s, "gun_dark")
        for i in W:
            F(i, i, j, j, 1 + s, 4 + s, "maroon_dark" if r % 2 else "maroon")
    F(-2, 1, -14, -14, 2, 5, "gun_black")
    # Crosse dépliée : charnière sous le bouchon, deux bras emboutis de deux
    # rangées qui descendent vers une plaque de couche en U.
    F(-2, 1, -3, -1, 6, 7, "gun_black")
    for k in range(8, 28):
        j0 = -1 - round((k - 8) * 3 / 19.0)
        for i in W:
            F(i, i, j0 - 1, j0, k, k, "gun_dark")
    F(-2, 1, -9, 1, 29, 29, "gun_black")
    for i in W:
        F(i, i, -9, 1, 28, 28, "gun_black")
    # Points remarquables (axe du canon : x = 0 entre les colonnes -1 et 0).
    line = 5
    it.a("sight", 0, line, -6.0)
    it.a("front", 0, line, -35.5)
    it.a("muzzle", 0, 2.0, -37)
    it.a("eject", 2.0, 2.5, -13)
    it.a("grip", 0, -3, 2.5)
    it.a("support", 0, -1, -15.5)  # poing en haut du puits du chargeur
    it.a("pivot_slide", -4, 2.5, -8)
    it.a("pivot_mag", 0, -1, -15.5)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = round(21 * FINE, 4)
    # Vue FPS : le poing droit suit la poignée (un cube toutes les cinq
    # rangées) ; la main gauche serre le puits du chargeur, comme sur le vrai
    # MP40 (poing vertical « foregrip », creux de 3,75 cm autour du puits).
    it.info["grip_angle"] = -round(math.degrees(math.atan2(1.0, 5.0)), 1)
    it.info["front_grip"] = True
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.22]
    # Points d'attache des pièces visibles (docs/weapons/mp40.md).
    it.a("att_muzzle", 0, 2.0, -37)
    it.a("att_optic", 0, 4, -14)
    it.a("att_mag", 0, -8, -15.5)
    it.a("att_stock", 0, -2, 7)
    return it

# ---------------------------------------------------------------------------
# Fusil à deux canons juxtaposés (id interne « olympia ») : IJ-43 (IZh-43) réel
# (calibre 12, canons de 510 mm), 960 mm -> 77 cubes. Largeurs PAIRES : deux
# canons de 2 × 2 côte à côte (axe entre eux), bande de visée dans leur
# creux et guidon-bille au bout ; bascule d'acier gris gravée, clé
# d'ouverture sur le dessus, deux détentes dans un pontet ; longuesse et
# crosse à demi-poignée pistolet en noyer, plaque de couche en caoutchouc.
# Les canons, la bande et la longuesse forment la pièce « barrels » qui
# bascule autour de la charnière (rechargement « break »).
# ---------------------------------------------------------------------------

def b_olympia():
    it = Item("olympia", "shotgun", even=True)
    F = it.fill
    B = "barrels"
    # Canons (k = -46 à -6), rangées 1 et 2 : gauche i = -2..-1, droit 0..1.
    F(-2, 1, 1, 2, -46, -6, "blued", g=B)
    for i in range(-2, 2):
        for j in (1, 2):
            it.paint(i, j, -46, "-z", "bore", g=B)
    # Bagues de bouche un peu plus claires.
    for i, d in ((1, "+x"), (-2, "-x")):
        for j in (1, 2):
            it.paint(i, j, -46, d, "gun_dark", g=B)
    # Bande de visée dans le creux des canons, guidon-bille au bout.
    F(-1, 0, 3, 3, -46, -6, "gun_black", g=B)
    F(-1, 0, 4, 4, -45, -45, "brass", g=B)
    # Tenons sous les canons et longuesse en noyer (k = -22 à -6).
    F(-1, 0, 0, 0, -24, -6, "blued", g=B)
    F(-2, 1, -1, 0, -21, -6, "walnut", g=B)
    F(-1, 0, -2, -2, -19, -7, "walnut", g=B)
    for i, d in ((1, "+x"), (-2, "-x")):
        for k in range(-19, -8, 2):
            it.paint(i, -1, k, d, "walnut", g=B, f=0.82)  # quadrillage
    it.paint(-1, -2, -7, "-z", "steel", g=B)              # verrou de longuesse
    # Bascule (k = -5 à 1), acier gris gravé ; clé d'ouverture sur le dessus.
    F(-2, 1, -1, 3, -5, 1, "steel")
    for (j, k) in ((1, -4), (2, -3), (1, -2), (0, -1), (1, 0)):
        for i, d in ((1, "+x"), (-2, "-x")):
            it.paint(i, j, k, d, "steel", f=0.8)  # gravure
    F(-1, 0, 4, 4, -1, 2, "blued")
    it.put(1, 4, 2, "blued")                            # aile de la clé
    it.put(-1, 4, 3, "steel_light")                      # sûreté sur la queue
    # Pontet et deux détentes.
    F(-1, 0, -4, -2, -4, -4, "blued")
    F(-1, 0, -4, -4, -3, 3, "blued")
    F(-1, 0, -2, -3, -2, -2, "gun_black")
    F(-1, 0, -2, -2, 0, 0, "gun_black")
    # Crosse en noyer : dessus de -1 rangée à 3 du talon, demi-poignée
    # pistolet sous la queue de détente, plaque de couche en caoutchouc.
    for k in range(2, 29):
        t = (k - 2) / 26.0
        top = 3 - round(4 * t)
        if k <= 4:
            bot = -1
        elif k <= 8:
            bot = -3                                    # demi-poignée pistolet
        else:
            bot = -2 - round((k - 9) * 9 / 19.0)       # vers le talon
        F(-2, 1, bot, top, k, k, "walnut")
    for k in range(4, 9):                               # quadrillage de la poignée
        for i, d in ((1, "+x"), (-2, "-x")):
            for j in range(-3, 2):
                if (j + k) % 2 and it.has(i, j, k):
                    it.paint(i, j, k, d, "walnut", f=0.84)
    F(-2, 1, -11, -1, 29, 30, "rubber_black")
    # Points remarquables (axe : x = 0 entre les deux canons).
    line = 5
    it.a("sight", 0, line, -5.5)
    it.a("front", 0, line, -44.5)
    it.a("muzzle", 0, 2.0, -46)
    it.a("eject", 0.0, 3.0, -5)
    it.a("grip", 0, -1, 5.5)
    it.a("support", 0, -2, -14)
    it.a("pivot_barrels", 0, -1, -5)
    it.a("pivot_mag", 0, 2, -5)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/olympia.md).
    it.a("att_muzzle", 0, 2.0, -46)
    it.a("att_optic", 0, 4, -10)
    it.a("att_stock", 0, -5, 29)
    it.a("att_rail", 0, -2, -14)
    return it


# ---------------------------------------------------------------------------
# Fusil à pompe court sans crosse (id interne « stakeout ») : Ithaca 37
# « Stakeout » réel (calibre 12, canon de 337 mm, poignée pistolet, 4 + 1
# coups), 590 mm -> 47 cubes. Largeurs PAIRES : canon de 2 × 2 au-dessus du
# tube magasin de 2 × 2, collier qui les relie, guidon-bille ; pompe en bois
# rainuré autour du tube (pièce « pump ») ; boîtier bronzé de 4 cubes au dessus
# strié, ÉJECTION PAR LE DESSOUS (signature de l'Ithaca 37 : aucune fenêtre
# sur les flancs) ; pontet, sûreté transversale ; poignée pistolet en noyer
# très inclinée, quadrillée, calotte d'acier.
# ---------------------------------------------------------------------------

def b_stakeout():
    it = Item("stakeout", "shotgun", even=True)
    F = it.fill
    # Boîtier (k = -10 à 3), 5 rangées, dessus strié.
    F(-2, 1, 0, 4, -10, 3, "blued")
    for k in range(-9, 3, 2):
        for i in (-1, 0):
            it.paint(i, 4, k, "+y", "gun_black")
    # Dessous : fenêtre d'éjection et de chargement (peinte, sombre).
    for i in (-1, 0):
        for k in range(-8, -2):
            it.paint(i, 0, k, "-y", "bore", f=3.0)
    # Sûreté transversale dans l'avant du pontet, arrêtoir de pompe à gauche.
    it.paint(-2, 1, -1, "-x", "steel")
    # Canon (rangées 3 et 4, k = -37 à -11), tube magasin dessous (rangées 1
    # et 2, k = -33 à -11), bouchon et collier de canon.
    F(-1, 0, 3, 4, -37, -11, "blued")
    for i in (-1, 0):
        for j in (3, 4):
            it.paint(i, j, -37, "-z", "bore")
    F(-1, 0, 1, 2, -33, -11, "gun_dark")
    F(-1, 0, 1, 2, -34, -34, "steel")
    F(-2, 1, 1, 4, -32, -32, "gun_black")
    # Guidon-bille en laiton (ligne de mire au-dessus du boîtier, j = 6).
    F(-1, 0, 5, 5, -36, -36, "brass")
    # Pompe en bois rainuré autour du tube (pièce « pump »).
    for k in range(-27, -14):
        key = "walnut" if k % 2 else "walnut_dark"
        F(-2, 1, 0, 2, k, k, key, g="pump")
    # Pontet et détente.
    F(-1, 0, -3, -1, -2, -2, "blued")
    F(-1, 0, -3, -3, -1, 2, "blued")
    F(-1, 0, -2, -1, 0, 0, "gun_black")
    # Poignée pistolet en noyer inclinée d'environ 30° (deux cubes vers
    # l'arrière toutes les trois rangées), 4 cubes d'épaisseur, quadrillée,
    # calotte d'acier.
    for r in range(10):
        j = 2 - r
        s = (r * 2) // 3
        F(-2, 1, j, j, 4 + s, 7 + s, "walnut" if r < 9 else "steel")
        if 2 <= r <= 7:
            for i, d in ((1, "+x"), (-2, "-x")):
                for kk in (5 + s, 6 + s):
                    if (j + kk) % 2:
                        it.paint(i, j, kk, d, "walnut", f=0.84)
    F(-2, 1, 0, 4, 4, 4, "walnut")              # talon contre le boîtier
    # Points remarquables (axe : x = 0 entre les colonnes -1 et 0).
    line = 6
    it.a("sight", 0, line, 3.5)
    it.a("front", 0, line, -35.5)
    it.a("muzzle", 0, 4.0, -37)
    it.a("eject", 0.0, -0.5, -5)
    it.a("grip", 0, -1, 6.0)
    it.a("support", 0, 0, -21)
    it.a("pivot_pump", 0, 1.5, -21)
    it.a("pivot_mag", 0, 0, -5)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["cube"] = FINE
    it.info["grip_angle"] = -31.0
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/stakeout.md).
    it.a("att_muzzle", 0, 4.0, -37)
    it.a("att_optic", 0, 5, -4)
    it.a("att_stock", 0, -2, 8)
    it.a("att_rail", 0, 0, -21)
    return it


# ---------------------------------------------------------------------------
# Fusil semi-automatique (id interne « m14 ») : M14 réel (7,62 × 51 mm,
# chargeur de 20, canon de 559 mm), 1 118 mm -> 90 cubes. Largeurs PAIRES :
# canon de 2 × 2 (axe y = 5) ; cache-flamme à cinq branches qui porte le
# guidon entre deux oreilles ; cylindre de gaz et tenon de baïonnette sous le
# canon ; crosse en noyer d'un seul tenant (fût, demi-poignée pistolet,
# plaque de couche d'acier), garde-main supérieur ajouré ; boîtier parkérisé,
# porte-culasse visible sur le dessus, levier de manœuvre en bosse sur le
# flanc droit (pièce « slide »), hausse à œilleton et ses deux molettes ;
# chargeur droit de 20 parkérisé ; anneaux de grenadière.
# ---------------------------------------------------------------------------

def b_m14():
    it = Item("m14", "rifle", even=True)
    F = it.fill
    # Cache-flamme (k = -63 à -60) : tube 4 × 4 aux coins abattus autour de
    # l'axe (rangées 3 à 6), fentes entre les branches.
    for k in range(-63, -59):
        for i in range(-2, 2):
            for j in range(3, 7):
                if i in (-2, 1) and j in (3, 6):
                    continue
                if k in (-62, -61) and i in (-2, 1) and j in (4, 5):
                    continue  # fentes latérales du cache-flamme
                it.put(i, j, k, "parker_dark")
    for i in (-1, 0):
        for j in (4, 5):
            it.paint(i, j, -63, "-z", "bore")
    # Guidon (lame de 2 cubes, sommet à j = 10) sur un socle posé sur le
    # cache-flamme, entre deux oreilles plus hautes.
    F(-2, 1, 7, 7, -62, -61, "parker_dark")
    F(-1, 0, 8, 9, -62, -62, "parker_dark")
    for i in (-2, 1):
        F(i, i, 8, 10, -62, -61, "parker_dark")
    # Canon (rangées 4 et 5) jusqu'au boîtier.
    F(-1, 0, 4, 5, -59, -22, "parker_dark")
    # Cylindre de gaz, bouchon, tenon de baïonnette.
    F(-1, 0, 2, 3, -52, -47, "parker")
    F(-1, 0, 2, 3, -53, -53, "steel")
    F(-1, 0, 1, 1, -53, -51, "parker")
    # Fût de la crosse sous le canon (k = -46 à -9), garde-main ajouré dessus.
    F(-2, 1, 1, 3, -46, -9, "walnut")
    for i in (-2, 1):
        F(i, i, 4, 4, -46, -9, "walnut")          # flancs du fût contre le canon
    F(-2, 1, 6, 6, -45, -22, "walnut_dark")
    for k in range(-43, -24, 3):
        for i, d in ((1, "+x"), (-2, "-x")):
            it.paint(i, 6, k, d, "bore", f=3.0)
    for i in (-2, 1):
        F(i, i, 4, 5, -45, -22, "walnut_dark")     # flancs du garde-main
    F(-1, 0, 0, 0, -41, -40, "steel")                # anneau de grenadière avant, sous le fût
    # Boîtier parkérisé (k = -21 à 0, rangées 4 à 7), dessus ouvert : porte-
    # culasse clair visible.
    F(-2, 1, 4, 7, -21, 0, "parker")
    for i in (-1, 0):
        for k in range(-15, -7):
            it.paint(i, 7, k, "+y", "steel_light")
    # Levier de manœuvre (flanc droit, pièce « slide ») : bosse et poignée.
    F(2, 2, 5, 6, -14, -11, "parker", g="slide")
    F(3, 3, 6, 6, -13, -12, "parker", g="slide")
    # Hausse à œilleton à l'arrière du boîtier, deux molettes.
    F(-2, 1, 8, 8, -3, -1, "parker_dark")
    for i in (-2, 1):
        F(i, i, 9, 9, -2, -1, "parker_dark")
    it.put(2, 8, -2, "steel")
    it.put(-3, 8, -2, "steel")
    # Chargeur droit de 20 (pièce « mag »), légèrement courbé, semelle.
    for r in range(10):
        s = -(r // 5)
        F(-2, 1, -1 - r, -1 - r, -8 + s, -3 + s, "parker_dark", g="mag")
        for i, d in ((1, "+x"), (-2, "-x")):
            it.paint(i, -1 - r, -6 + s, d, "parker", g="mag")
    F(-2, 1, -11, -11, -10, -4, "parker", g="mag")
    # Crosse sous le boîtier, pontet et détente.
    F(-2, 1, 0, 3, -8, 0, "walnut")
    F(-1, 0, 4, 5, 1, 3, "parker")                    # talon du boîtier sur le poignet
    F(-1, 0, -3, -1, -2, -2, "parker")
    F(-1, 0, -3, -3, -1, 3, "parker")
    F(-1, 0, -2, -1, 0, 0, "gun_black")
    # Poignet, demi-poignée pistolet et talon de crosse (k = 1 à 25).
    for k in range(1, 26):
        top = 5                                       # busc droit, sous le boîtier
        if k <= 2:
            bot = 1
        elif k <= 8:
            bot = -2                                  # demi-poignée pistolet
        else:
            bot = -1 - round((k - 9) * 5 / 16.0)
        F(-2, 1, bot, top, k, k, "walnut")
    for k in range(4, 9):                             # quadrillage
        for j in range(-2, 2):
            for i, d in ((1, "+x"), (-2, "-x")):
                if (j + k) % 2:
                    it.paint(i, j, k, d, "walnut", f=0.84)
    F(-2, 1, -6, 5, 26, 26, "parker")                 # plaque de couche
    for k in (17, 18):                                # anneau de grenadière arrière,
        bot = -1 - round((k - 9) * 5 / 16.0)         # collé sous la crosse
        F(-1, 0, bot - 1, bot - 1, k, k, "steel")
    # Points remarquables (axe : x = 0 entre les colonnes -1 et 0).
    line = 10
    it.a("sight", 0, line, -1.0)
    it.a("front", 0, line, -61.5)
    it.a("muzzle", 0, 5.0, -63)
    it.a("eject", 0.0, 8.0, -11)
    it.a("grip", 0, 0, 6.0)
    it.info["grip_angle"] = -20.0
    it.a("support", 0, 0, -30)
    it.a("pivot_slide", 3, 6.5, -12.5)
    it.info["slide_travel"] = 0.06
    it.a("pivot_mag", 0, 0, -5.5)
    d = (0.0, -11.0, -2.0)
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/m14.md).
    it.a("att_muzzle", 0, 5.0, -63)
    it.a("att_optic", 0, 8, -12)
    it.a("att_mag", 0, -1, -5.5)
    it.a("att_stock", 0, 0, 26)
    it.a("att_rail", 0, 0, -30)
    return it


# ---------------------------------------------------------------------------
# Mitraillette compacte (id interne « mp5k ») : MP5K réel (9 × 19 mm,
# chargeur courbe de 30, sans crosse), 325 mm -> 26 cubes. Boîtier embouti
# noir de 3 cubes, tube d'armement arrondi sur le dessus avec le levier
# d'armement à gauche (pièce « slide »), guidon dans un anneau à l'avant,
# hausse à tambour à l'arrière ; canon court à ergots ; garde-main court
# et POIGNÉE AVANT VERTICALE avec sa butée ; chargeur très courbé ; carcasse
# et poignée en polymère, pontet ; bouchon arrière et anneau de sangle.
# ---------------------------------------------------------------------------

def b_mp5k():
    it = Item("mp5k", "smg")
    F = it.fill
    # Boîtier (k = -12 à 9, rangées 0 à 3), tube d'armement arrondi dessus.
    F(-1, 1, 0, 3, -12, 9, "gun_dark")
    F(-1, 1, 4, 4, -12, 9, "gun_dark", f=1.12)
    F(0, 0, 5, 5, -12, 9, "gun_dark", f=1.12)
    # Fenêtre d'éjection (flanc droit), sélecteur (flanc gauche).
    for k in range(-3, 1):
        it.paint(1, 2, k, "+x", "bore", f=3.0)
    it.paint(-1, 1, 3, "-x", "steel")
    it.paint(-1, 1, 4, "-x", "red")
    # Levier d'armement à gauche, à l'avant du tube (pièce « slide »).
    F(-2, -2, 4, 4, -10, -10, "steel", g="slide")
    F(-3, -3, 4, 4, -10, -10, "gun_black", g="slide")
    # Canon court à ergots, écrou avant.
    F(-1, 1, 1, 3, -13, -13, "gun_black")
    for (i, j) in ((0, 1), (0, 2), (0, 3), (-1, 2), (1, 2)):
        it.put(i, j, -14, "gun_dark")
    it.put(0, 2, -15, "gun_dark")
    it.paint(0, 2, -15, "-z", "bore")
    # Guidon bas (sommet : j = 7) entre deux oreilles posées sur le tube.
    F(0, 0, 6, 6, -12, -12, "gun_black")
    for i in (-1, 1):
        F(i, i, 5, 7, -12, -11, "gun_black")
    # Hausse à tambour, basse, à l'arrière du tube : socle, deux oreilles, cran.
    for i in (-1, 1):
        F(i, i, 5, 6, 6, 7, "gun_black")
    # Garde-main court en polymère sous le tube (k = -12 à -6).
    F(-1, 1, -1, 0, -12, -6, "poly")
    # Poignée avant verticale avec sa butée (k = -10 à -8).
    F(-1, 1, -9, -2, -12, -10, "poly")
    F(-1, 1, -3, -1, -13, -13, "poly")            # butée de main
    for j in range(-8, -2, 2):
        for i, d in ((1, "+x"), (-1, "-x")):
            for k in (-12, -11, -10):
                it.paint(i, j, k, d, "poly", f=0.8)  # stries
    # Puits du chargeur et chargeur courbe de 30 (pièce « mag »).
    F(-1, 1, -2, -1, -6, -2, "gun_dark")
    for i in (-1, 0, 1):
        for j in (-2, -1):
            for k in (-5, -4, -3):
                it.drop(i, j, k)
    for r in range(12):
        s = -(r // 4)
        F(-1, 1, -1 - r, -1 - r, -5 + s, -3 + s, "parker", g="mag")
        for i, d in ((1, "+x"), (-1, "-x")):
            it.paint(i, -1 - r, -4 + s, d, "parker_dark", g="mag")   # nervure
    F(-1, 1, -13, -13, -8, -5, "parker_dark", g="mag")
    # Carcasse en polymère, pontet, détente, poignée inclinée.
    F(-1, 1, -1, -1, -1, 8, "poly")
    F(0, 0, -3, -2, -1, -1, "poly")
    F(0, 0, -4, -4, -1, 1, "poly")
    F(0, 0, -2, -2, 0, 0, "gun_black")
    for r in range(9):
        s = r // 4
        F(-1, 1, -2 - r, -2 - r, 2 + s, 4 + s, "poly")
        if r % 2:
            for i, d in ((1, "+x"), (-1, "-x")):
                it.paint(i, -2 - r, 3 + s, d, "poly", f=0.8)
    # Bouchon arrière et anneau de sangle.
    F(-1, 1, 0, 4, 10, 10, "gun_black")
    F(0, 0, 1, 3, 11, 11, "steel")
    # Points remarquables.
    line = 7
    it.a("sight", 0, line, 7.0)
    it.a("front", 0, line, -11.5)
    it.a("muzzle", 0, 2.5, -15)
    it.a("eject", 1.5, 2.5, -1.5)
    it.a("grip", 0, -1, 3.5)
    it.info["grip_angle"] = -14.0
    it.a("support", 0, -2, -11)
    it.info["front_grip"] = True
    it.a("pivot_slide", -3, 4.5, -9.5)
    it.info["slide_travel"] = 0.04
    it.a("pivot_mag", 0, 0, -3.5)
    d = (0.0, -13.0, -3.0)
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.25]
    # Points d'attache des pièces visibles (docs/weapons/mp5k.md).
    it.a("att_muzzle", 0, 2.5, -15)
    it.a("att_optic", 0, 6, -2)
    it.a("att_mag", 0, -1, -3.5)
    it.a("att_stock", 0, 2, 11)
    it.a("att_rail", 0, -9, -11)
    return it


# ---------------------------------------------------------------------------
# Pistolet (id interne « cz75 ») : CZ 75 B réel (9 × 19 mm, chargeur de 16),
# 206 × 138 mm -> 17 × 11 cubes. Signature : la glissière coulisse DANS la
# carcasse (les rails de la carcasse montent sur les flancs jusqu'à mi-hauteur
# de la glissière, sur toute sa longueur) ; cache-poussière jusqu'à la
# bouche ; pontet arrondi ; chien à anneau ; longue queue de castor ;
# plaquettes de noyer quadrillées ; finition noire.
# ---------------------------------------------------------------------------

def b_cz75():
    it = Item("cz75", "pistol")
    F = it.fill
    # Glissière (pièce « slide ») : k = -11 à 4 ; rangée 2 pleine largeur,
    # rangée 1 au centre seulement (les flancs sont dans la carcasse).
    F(-1, 1, 2, 2, -11, 4, "gun_black", g="slide")
    F(0, 0, 1, 1, -11, 4, "gun_black", g="slide")
    F(-1, 1, 1, 1, -11, -10, "gun_black", g="slide")   # nez de la glissière
    # Stries arrière, fenêtre d'éjection (flanc droit), bouche.
    for k in (1, 3):
        for i, d in ((1, "+x"), (-1, "-x")):
            it.paint(i, 2, k, d, "gun_black", g="slide", f=0.6)
    for k in (-4, -3, -2):
        it.drop(1, 2, k, g="slide")
        it.put(0, 2, k, "brass", g="slide")
    it.paint(0, 1, -11, "-z", "bore", g="slide")
    # Guidon et hausse (ligne de mire à j = 4).
    it.put(0, 3, -10, "gun_black", g="slide")
    for i in (-1, 1):
        it.put(i, 3, 3, "gun_black", g="slide")
    # Carcasse : rails sur les flancs (rangée 1), cache-poussière (rangée 0)
    # jusqu'à un cube de la bouche, queue de castor.
    for i in (-1, 1):
        F(i, i, 1, 1, -9, 4, "gun_dark")
    F(-1, 1, 0, 0, -10, 4, "gun_dark")
    F(-1, 1, 0, 1, 5, 5, "gun_dark")
    F(-1, 1, 0, 0, 6, 6, "gun_dark")                    # queue de castor
    # Chien à anneau (cœur sombre) derrière la glissière, sous la hausse.
    F(0, 0, 1, 2, 5, 5, "gun_black")
    it.paint(0, 2, 5, "+x", "bore", f=3.0)
    it.paint(0, 2, 5, "-x", "bore", f=3.0)
    # Arrêtoir de culasse et sûreté (flanc gauche), peints.
    for k in (-4, -3):
        it.paint(-1, 1, k, "-x", "steel")
    it.paint(-1, 1, 3, "-x", "steel")
    # Pontet (raccordé au devant de la poignée) et détente.
    F(0, 0, -3, -1, -5, -5, "gun_dark")
    F(0, 0, -3, -3, -4, 0, "gun_dark")
    it.put(0, -1, -2, "gun_black")
    it.put(0, -2, -2, "gun_black")
    # Poignée (k = 0 à 4, 7 rangées, inclinée) : dos et devant de la carcasse,
    # plaquettes de noyer quadrillées sur les flancs, chargeur au cœur.
    for r in range(7):
        j = -1 - r
        s = (r + 1) // 3
        F(-1, 1, j, j, 0 + s, 0 + s, "gun_dark")        # devant de la carcasse
        F(-1, 1, j, j, 4 + s, 4 + s, "gun_dark")        # dos de la carcasse
        for i in (-1, 1):
            for k in range(1 + s, 4 + s):
                it.put(i, j, k, "walnut", f=0.88 if (j + k) % 2 else 1.06)
        F(0, 0, j, j, 1 + s, 3 + s, "gun_dark", g="mag")
    F(-1, 1, -8, -8, 3, 5, "gun_dark", g="mag")       # semelle du chargeur
    for i, d in ((1, "+x"), (-1, "-x")):
        it.paint(i, -2, 2, d, "steel_light")         # vis des plaquettes
        it.paint(i, -6, 4, d, "steel_light")
    # Points remarquables.
    line = 4
    it.a("sight", 0, line, 3.5)
    it.a("front", 0, line, -9.5)
    it.a("muzzle", 0, 1.5, -11)
    it.a("eject", 1.0, 2.5, -3)
    it.a("grip", 0, 0, 2.5)
    it.a("support", 0, -2, 1)
    it.a("pivot_slide", 0, 2.0, 0)
    it.info["slide_travel"] = 0.03
    it.a("pivot_mag", 0, 0, 2.0)
    d = (0.0, -8.0, 2.0)
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["grip_angle"] = -round(math.degrees(math.atan2(d[2], -d[1])), 1)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.4]
    it.anchors["hold"] = [-0.06, 0.15, 0.35]
    it.anchors["hold_rot"] = [0.0, 0.32, -0.08]
    # Points d'attache des pièces visibles (docs/weapons/cz75.md).
    it.a("att_muzzle", 0, 1.5, -11)
    it.a("att_optic", 0, 3, 0)
    it.a("att_mag", 0, -8, 4)
    it.a("att_grip_l", -1.5, -4, 3)
    it.a("att_grip_r", 1.5, -4, 3)
    it.a("att_rail", 0, 0, -7)
    return it


# ---------------------------------------------------------------------------
# Mitraillette-pistolet (id interne « pm63 ») : PM-63 RAK réel (9 × 18 mm,
# chargeur de 25 dans la poignée), 583 mm crosse dépliée -> 48 cubes. Un
# « gros pistolet » : GLISSIÈRE nue d'acier clair qui recule à chaque tir
# (pièce « slide »), terminée par le BEC compensateur sous la bouche ;
# carcasse noire ; poignée avant dépliée ; pontet arrondi ; chargeur long
# qui dépasse de la poignée ; crosse en fil à deux bras et plaque de couche.
# ---------------------------------------------------------------------------

def b_pm63():
    it = Item("pm63", "smg")
    F = it.fill
    # Glissière (k = -15 à 5, rangées 2 et 3) et bec compensateur devant.
    F(-1, 1, 2, 3, -15, 5, "steel", g="slide")
    F(-1, 1, 1, 1, -17, -15, "steel", g="slide")     # bec sous la bouche
    for i in (-1, 1):
        it.put(i, 2, -17, "steel", g="slide")        # rebords du bec
    it.paint(0, 2, -15, "-z", "bore", g="slide")
    for k in (2, 4):                                 # stries arrière
        for i, d in ((1, "+x"), (-1, "-x")):
            for j in (2, 3):
                it.paint(i, j, k, d, "steel", g="slide", f=0.7)
    for k in (-6, -5, -4):                           # fenêtre d'éjection
        it.paint(1, 3, k, "+x", "bore", g="slide", f=3.0)
    # Guidon et hausse sur la glissière (ligne de mire à j = 5).
    it.put(0, 4, -14, "gun_black", g="slide")
    for i in (-1, 1):
        it.put(i, 4, 4, "gun_black", g="slide")
    # Carcasse noire (k = -13 à 6, rangées 0 et 1).
    F(-1, 1, 0, 1, -13, 6, "gun_black")
    it.paint(-1, 1, 2, "-x", "steel")                # sélecteur
    # Pontet arrondi et détente.
    F(0, 0, -3, -1, -5, -5, "gun_black")
    F(0, 0, -3, -3, -4, 0, "gun_black")
    it.put(0, -1, -2, "gun_dark")
    # Poignée (k = 0 à 3 en haut, inclinée), plaquettes en polymère brun,
    # chargeur de 25 au cœur, qui dépasse de 3 rangées.
    for r in range(8):
        j = -1 - r
        s = (r + 1) // 3
        F(-1, 1, j, j, 0 + s, 0 + s, "gun_black")
        F(-1, 1, j, j, 3 + s, 3 + s, "gun_black")
        for i in (-1, 1):
            F(i, i, j, j, 1 + s, 2 + s, "brown")
        F(0, 0, j, j, 1 + s, 2 + s, "gun_dark", g="mag")
    for r in range(8, 11):
        j = -1 - r
        F(-1, 1, j, j, 3, 5, "gun_dark", g="mag")
    F(-1, 1, -12, -12, 3, 5, "gun_black", g="mag")
    # Poignée avant dépliée sous l'avant de la carcasse.
    F(-1, 1, -6, -1, -12, -10, "gun_black")
    for j in (-2, -4):
        for i, d in ((1, "+x"), (-1, "-x")):
            for k in (-12, -11, -10):
                it.paint(i, j, k, d, "brown")
    # Crosse en fil dépliée : charnière, deux bras de 2 rangées qui
    # descendent d'une rangée, plaque de couche.
    F(-1, 1, 0, 2, 7, 7, "gun_black")
    for k in range(8, 30):
        dj = -1 if k > 18 else 0
        for i in (-1, 1):
            F(i, i, 0 + dj, 1 + dj, k, k, "gun_dark")
    F(-1, 1, -7, 2, 30, 30, "gun_black")
    # Points remarquables.
    line = 5
    it.a("sight", 0, line, 4.5)
    it.a("front", 0, line, -13.5)
    it.a("muzzle", 0, 2.5, -15)
    it.a("eject", 1.0, 3.5, -5)
    it.a("grip", 0, 0, 2.0)
    it.a("support", 0, -1, -11)
    it.info["front_grip"] = True
    it.a("pivot_slide", 0, 3.0, 0)
    it.info["slide_travel"] = 0.045
    it.a("pivot_mag", 0, 0, 1.5)
    d = (0.0, -11.0, 3.0)
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["grip_angle"] = -round(math.degrees(math.atan2(d[2], -d[1])), 1)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/pm63.md).
    it.a("att_muzzle", 0, 2.5, -15)
    it.a("att_optic", 0, 4, -4)
    it.a("att_mag", 0, -12, 4)
    it.a("att_stock", 0, 1, 7)
    it.a("att_rail", 0, -6, -11)
    return it


# ---------------------------------------------------------------------------
# Mitraillette (id interne « mpl ») : Walther MPL réelle (9 × 19 mm, chargeur
# droit de 32, canon long), 746 mm crosse dépliée -> 61 cubes. Boîtier
# embouti haut : la culasse coulisse AU-DESSUS du canon, l'avant du boîtier
# est ouvert dessous (on voit le canon) ; évidements sur les flancs ; levier
# d'armement à gauche (pièce « slide ») ; guidon à oreilles et hausse sur le
# dessus ; puits du chargeur devant le pontet, chargeur droit ; poignée en
# polymère quadrillé ; crosse en tube coudé (bras haut et bas, plaque).
# ---------------------------------------------------------------------------

def b_mpl():
    it = Item("mpl", "smg")
    F = it.fill
    # Boîtier : partie haute (rangées 2 à 4) de k = -21 à 7, partie basse
    # (rangées 0 et 1) seulement de k = -12 à 7 : fenêtre sous l'avant.
    F(-1, 1, 2, 4, -21, 7, "gun_dark")
    F(-1, 1, 0, 1, -12, 7, "gun_dark")
    F(-1, 1, 1, 1, -21, -21, "gun_dark")             # nez du boîtier
    # Évidements emboutis sur les flancs (peints) et nervure du dessus.
    for k0 in (-19, -15):
        for k in range(k0, k0 + 3):
            for i, d in ((1, "+x"), (-1, "-x")):
                it.paint(i, 3, k, d, "bore", f=3.0)
    for k in range(-20, 7, 2):
        it.paint(0, 4, k, "+y", "gun_black")
    # Canon long (axe à la rangée 1, section en croix) : visible dans la
    # fenêtre et devant le boîtier, bague pleine à la bouche.
    for k in range(-30, -12):
        for (i, j) in ((0, 0), (0, 1), (0, 2), (-1, 1), (1, 1)):
            it.put(i, j, k, "gun_black")
    F(-1, 1, 0, 2, -30, -30, "gun_black")             # bague de bouche
    it.paint(0, 1, -30, "-z", "bore")
    # Fenêtre d'éjection (flanc droit), levier d'armement (flanc gauche).
    for k in (-9, -8, -7):
        it.paint(1, 3, k, "+x", "bore", f=3.0)
    F(-2, -2, 3, 3, -18, -17, "steel", g="slide")
    it.put(-3, 3, -18, "steel", g="slide")
    # Guidon à oreilles et hausse (ligne de mire à j = 7).
    F(-1, 1, 5, 5, -20, -19, "gun_black")
    it.put(0, 6, -20, "gun_black")
    for i in (-1, 1):
        F(i, i, 6, 7, -20, -19, "gun_black")
    F(-1, 1, 5, 5, 4, 6, "gun_black")
    for i in (-1, 1):
        F(i, i, 6, 6, 5, 6, "gun_black")
    # Puits du chargeur devant le pontet, chargeur droit de 32 (pièce « mag »).
    F(-1, 1, -5, -1, -9, -5, "gun_dark")
    for i in (-1, 0, 1):
        for j in range(-5, 0):
            for k in (-8, -7, -6):
                it.drop(i, j, k)
    F(-1, 1, -17, -1, -8, -6, "gun_black", g="mag")
    F(-1, 1, -18, -18, -9, -5, "gun_dark", g="mag")
    it.paint(-1, -4, -5, "-x", "steel")                # bouton de déverrouillage
    # Pontet, détente, poignée en polymère quadrillé.
    F(0, 0, -3, -1, -4, -4, "gun_dark")
    F(0, 0, -3, -3, -3, 0, "gun_dark")
    it.put(0, -1, -2, "gun_black")
    for r in range(9):
        j = -1 - r
        s = r // 4
        F(-1, 1, j, j, 1 + s, 4 + s, "poly")
        for i, d in ((1, "+x"), (-1, "-x")):
            for k in (2 + s, 3 + s):
                if (j + k) % 2:
                    it.paint(i, j, k, d, "poly", f=0.75)
    # Bouchon arrière, crosse en tube coudé dépliée : bras haut, bras bas qui
    # descend, plaque de couche.
    F(-1, 1, 0, 4, 8, 8, "gun_black")
    for k in range(9, 31):
        F(0, 0, 3, 4, k, k, "gun_dark")
        jb = -round((k - 9) * 5 / 21.0)
        F(0, 0, jb, jb + 1, k, k, "gun_dark")
    F(-1, 1, -6, 4, 31, 31, "gun_black")
    # Points remarquables.
    line = 7
    it.a("sight", 0, line, 5.5)
    it.a("front", 0, line, -19.5)
    it.a("muzzle", 0, 1.5, -30)
    it.a("eject", 1.0, 3.5, -8)
    it.a("grip", 0, 0, 2.5)
    it.info["grip_angle"] = -round(math.degrees(math.atan2(2.0, 9.0)), 1)
    it.a("support", 0, -5, -7)
    it.a("pivot_slide", -3, 3.5, -17.5)
    it.info["slide_travel"] = 0.05
    it.a("pivot_mag", 0, 0, -7)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = round(18 * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.25]
    # Points d'attache des pièces visibles (docs/weapons/mpl.md).
    it.a("att_muzzle", 0, 1.5, -30)
    it.a("att_optic", 0, 5, -6)
    it.a("att_mag", 0, -5, -7)
    it.a("att_stock", 0, 2, 8)
    it.a("att_rail", 0, 0, -16)
    return it


# ---------------------------------------------------------------------------
# Fusil d'assaut à rafales (id interne « m16 ») : M16A2 réel (5,56 × 45 mm,
# rafales de 3, chargeur courbe de 30), 1 006 mm -> 81 cubes. Largeurs
# PAIRES (axe y = 5 entre les colonnes -1 et 0). Cache-flamme « cage à
# oiseau » ; GUIDON EN TOUR TRIANGULAIRE (base large sur le canon, sommet
# étroit, oreilles de protection) ; garde-mains ronds nervurés (tube de 4 aux
# coins abattus) et bague « delta » ; boîtier supérieur et inférieur en alu
# anodisé gris très foncé ; POIGNÉE DE TRANSPORT avec la hausse à l'arrière ;
# levier d'armement en T (pièce « slide »), assistance de fermeture,
# déflecteur de douilles ; chargeur courbe gris ; poignée à ergot ; crosse
# fixe DANS L'AXE du canon, plaque de couche.
# ---------------------------------------------------------------------------

def b_m16():
    it = Item("m16", "rifle", even=True)
    F = it.fill
    W = (-2, 1)

    def octo(j0, k0, k1, key, f=None, g="body"):
        for i in range(-2, 2):
            for j in range(j0, j0 + 4):
                if i in W and j in (j0, j0 + 3):
                    continue
                for k in range(k0, k1 + 1):
                    it.put(i, j, k, key, g=g, f=f)

    # Cache-flamme cage à oiseau (k = -52 à -49) : fentes sur les flancs.
    octo(3, -52, -49, "gun_black")
    for k in (-51, -50):
        for i in W:
            for j in (4, 5):
                it.drop(i, j, k)
    for i in (-1, 0):
        for j in (4, 5):
            it.paint(i, j, -52, "-z", "bore")
    # Canon (rangées 4 et 5) jusqu'au boîtier.
    F(-1, 0, 4, 5, -48, -14, "gun_black")
    # Guidon en tour triangulaire (k = -46 à -42) : base large sur le canon,
    # sommet étroit ; lame de 2 cubes au sommet (j = 11) entre deux oreilles.
    for j in range(6, 11):
        n = (j - 6) // 2                       # se resserre en montant
        F(-1, 0, j, j, -46 + n, -42 - n, "gun_black")
    F(-1, 0, 11, 11, -44, -44, "gun_black")
    for i in W:
        F(i, i, 10, 12, -44, -44, "gun_black")  # oreilles au sommet de la tour
    F(-1, 0, 2, 3, -45, -43, "gun_black")      # tenon de baïonnette
    F(-1, 0, 1, 1, -44, -44, "steel")           # anneau de grenadière
    # Garde-mains ronds nervurés (k = -37 à -16), bague « delta ».
    for k in range(-37, -15):
        octo(3, k, k, "poly", f=0.86 if k % 2 else 1.0)
    F(-2, 1, 3, 6, -15, -14, "gun_dark")
    # Boîtier supérieur (k = -13 à 1, rangées 4 à 7) et inférieur (rangées 0
    # à 3), anodisés gris très foncé.
    F(-2, 1, 4, 7, -13, 1, "gun_dark")
    F(-2, 1, 0, 3, -12, 1, "gun_dark", f=0.92)
    for k in range(-9, -4):                    # fenêtre d'éjection
        it.paint(1, 5, k, "+x", "bore", f=3.0)
    F(2, 2, 5, 6, -3, -2, "gun_dark")           # assistance de fermeture
    F(2, 2, 7, 7, -5, -4, "gun_dark")           # déflecteur de douilles
    it.paint(-2, 2, -1, "-x", "steel")          # sélecteur
    it.paint(1, 2, -6, "+x", "steel")           # bouton du chargeur
    # Poignée de transport : montants, pont, hausse à l'arrière (ligne de mire
    # à j = 12 : deux oreilles, cran de 2 cubes au milieu).
    F(-1, 0, 8, 9, -12, -11, "gun_dark")
    F(-1, 0, 8, 10, -3, -1, "gun_dark")
    F(-1, 0, 10, 10, -12, -4, "gun_dark")
    for i in W:
        F(i, i, 10, 11, -2, -1, "gun_dark")
    it.put(2, 10, -2, "steel")                  # molette de dérive
    # Levier d'armement en T à l'arrière du boîtier (pièce « slide »).
    F(-3, 2, 7, 7, 2, 2, "gun_black", g="slide")
    # Puits du chargeur et chargeur courbe de 30 (pièce « mag »), 2 × 5.
    F(-2, 1, -1, -1, -12, -6, "gun_dark", f=0.92)
    for i in (-1, 0):
        for k in range(-11, -6):
            it.drop(i, -1, k)
    last = 0
    for r in range(14):
        s = -(r // 4)
        F(-1, 0, -1 - r, -1 - r, -11 + s, -7 + s, "parker", g="mag")
        last = s
    F(-2, 1, -15, -15, -11 + last, -7 + last, "parker_dark", g="mag")
    # Pontet, détente, poignée à ergot (2 cubes de large, inclinée).
    F(-1, 0, -3, -1, -4, -4, "gun_dark")
    F(-1, 0, -3, -3, -3, 1, "gun_dark")
    F(-1, 0, -2, -1, -1, -1, "gun_black")
    for r in range(9):
        j = -1 - r
        s = r // 3
        F(-1, 0, j, j, 2 + s, 4 + s, "poly")
        if r == 3:
            F(-1, 0, j, j, 1 + s, 1 + s, "poly")   # ergot entre deux doigts
    # Crosse fixe dans l'axe (dessus droit à j = 7), dessous qui descend,
    # plaque de couche avec sa trappe.
    for k in range(2, 28):
        bot = 2 - round((k - 2) * 5 / 25.0)
        F(-2, 1, bot, 7, k, k, "poly")
    F(-2, 1, -3, 7, 28, 28, "poly", f=0.7)
    it.paint(-1, 2, 28, "+z", "poly", f=0.5)
    for k in (20, 21):                          # anneau de grenadière arrière,
        bot = 2 - round((k - 2) * 5 / 25.0)     # collé sous la crosse
        F(-1, 0, bot - 1, bot - 1, k, k, "steel")
    # Points remarquables (axe : x = 0 entre les colonnes -1 et 0).
    line = 12
    it.a("sight", 0, line, -1.5)
    it.a("front", 0, line, -43.5)
    it.a("muzzle", 0, 5.0, -52)
    it.a("eject", 2.0, 5.5, -7)
    it.a("grip", 0, 0, 3.5)
    it.info["grip_angle"] = -18.0
    it.a("support", 0, 3, -26)
    it.a("pivot_slide", 0, 7.5, 2.5)
    it.info["slide_travel"] = 0.05
    it.a("pivot_mag", 0, 0, -9)
    d = (0.0, -15.0, float(last))
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/m16.md).
    it.a("att_muzzle", 0, 5.0, -52)
    it.a("att_optic", 0, 11, -8)
    it.a("att_mag", 0, -1, -9)
    it.a("att_stock", 0, 2, 28)
    it.a("att_rail", 0, 3, -26)
    return it


# ---------------------------------------------------------------------------
# Fusil à pompe de combat (id interne « spas12 ») : Franchi SPAS-12 réel
# (calibre 12, tube de 8, crosse en tôle repliable dépliée), 1 041 mm ->
# 83 cubes. Largeurs PAIRES (axe y = 5). MANCHON AJOURÉ autour du canon (tube
# de 4 aux coins abattus, percé sur les flancs et le dessus : on voit le
# canon), guidon au bout du manchon ; tube magasin dessous et son bouchon ;
# POMPE en polymère nervuré (pièce « pump ») ; boîtier noir haut, fenêtre
# d'éjection et levier d'armement à droite ; grosse poignée pistolet ;
# crosse en tôle : barre haute, plaque de couche et CROCHET d'avant-bras.
# ---------------------------------------------------------------------------

def b_spas12():
    it = Item("spas12", "shotgun", even=True)
    F = it.fill
    W = (-2, 1)

    def octo(j0, k0, k1, key, g="body"):
        for i in range(-2, 2):
            for j in range(j0, j0 + 4):
                if i in W and j in (j0, j0 + 3):
                    continue
                for k in range(k0, k1 + 1):
                    it.put(i, j, k, key, g=g)

    # Canon (rangées 4 et 5) de la bouche au boîtier.
    F(-1, 0, 4, 5, -55, -14, "gun_black")
    for i in (-1, 0):
        for j in (4, 5):
            it.paint(i, j, -55, "-z", "bore")
    # Manchon ajouré (k = -46 à -14) : trous sur les flancs et le dessus.
    octo(3, -46, -14, "parker")
    for k in range(-44, -15, 3):
        for i in W:
            for j in (4, 5):
                it.drop(i, j, k)
        if k % 2 == 0:
            for i in (-1, 0):
                it.drop(i, 6, k)
    # Guidon au bout du manchon (ligne de mire à j = 8).
    F(-1, 0, 7, 7, -45, -45, "gun_black")
    # Tube magasin (rangées 1 et 2, k = -50 à -14) et bouchon.
    F(-1, 0, 1, 2, -50, -14, "gun_dark")
    F(-1, 0, 1, 2, -51, -51, "steel")
    F(-2, 1, 1, 2, -48, -48, "gun_black")         # collier du tube
    F(-1, 0, 3, 3, -48, -48, "gun_black")
    # Pompe en polymère nervuré autour du tube (pièce « pump »).
    for k in range(-34, -17):
        F(-2, 1, 0, 3, k, k, "poly", g="pump", f=0.8 if k % 2 else 1.0)
    # Boîtier noir (k = -13 à 3, rangées 0 à 6).
    F(-2, 1, 0, 6, -13, 3, "gun_black")
    for k in range(-10, -5):
        it.paint(1, 4, k, "+x", "bore", f=3.0)     # fenêtre d'éjection
    F(2, 2, 4, 4, -9, -8, "steel", g="slide")      # levier d'armement
    for i in (-1, 0):                                # chargement par dessous
        for k in range(-11, -6):
            it.paint(i, 0, k, "-y", "bore", f=3.0)
    it.paint(-2, 2, -2, "-x", "red")                 # sûreté
    # Hausse à l'arrière du boîtier : deux oreilles, cran de 2 cubes.
    for i in W:
        F(i, i, 7, 7, 1, 2, "gun_black")
    # Pontet, détente, grosse poignée pistolet en polymère.
    F(-1, 0, -3, -1, -3, -3, "gun_black")
    F(-1, 0, -3, -3, -2, 1, "gun_black")
    F(-1, 0, -2, -1, -1, -1, "steel")
    for r in range(10):
        j = -1 - r
        s = r // 4
        F(-2, 1, j, j, 1 + s, 5 + s, "poly")
        if r % 2:
            for i, d in ((1, "+x"), (-2, "-x")):
                for kk in (2 + s, 3 + s, 4 + s):
                    it.paint(i, j, kk, d, "poly", f=0.75)
    # Crosse en tôle dépliée : charnière, barre haute, plaque de couche et
    # crochet d'avant-bras sous la plaque, pointe vers le haut.
    F(-2, 1, 4, 6, 4, 5, "gun_black")
    F(-1, 0, 5, 6, 6, 25, "gun_black")
    F(-2, 1, -4, 6, 26, 27, "gun_black")
    F(-1, 0, -4, -4, 20, 25, "gun_black")
    F(-1, 0, -3, -2, 20, 20, "gun_black")
    # Points remarquables (axe : x = 0 entre les colonnes -1 et 0).
    line = 8
    it.a("sight", 0, line, 2.0)
    it.a("front", 0, line, -44.5)
    it.a("muzzle", 0, 5.0, -55)
    it.a("eject", 2.0, 4.5, -8)
    it.a("grip", 0, 0, 3.0)
    it.info["grip_angle"] = -18.0
    it.a("support", 0, 0, -26)
    it.a("pivot_pump", 0, 1.5, -26)
    it.a("pivot_slide", 2, 4.5, -8.5)
    it.a("pivot_mag", 0, 0, -9)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/spas12.md).
    it.a("att_muzzle", 0, 5.0, -55)
    it.a("att_optic", 0, 7, -6)
    it.a("att_stock", 0, 1, 27)
    it.a("att_rail", 0, 0, -26)
    return it


# ---------------------------------------------------------------------------
# Fusil de bataille (id interne « fnfal ») : FN FAL réel (7,62 × 51 mm,
# semi-automatique, chargeur de 20, garnitures en polymère), 1 090 mm ->
# 87 cubes. Largeurs PAIRES (axe y = 5). Long cache-flamme à fentes ; bloc
# de guidon à oreilles et régulateur de gaz ; garde-main ajouré noir ;
# boîtier parkérisé gris (supérieur et inférieur), POIGNÉE DE TRANSPORT
# repliée sur le flanc gauche, levier d'armement à gauche (pièce « slide »),
# hausse à œilleton sur le couvercle ; chargeur droit de 20 ; poignée
# pistolet ; crosse fixe noire, plaque de couche.
# ---------------------------------------------------------------------------

def b_fnfal():
    it = Item("fnfal", "rifle", even=True)
    F = it.fill
    W = (-2, 1)

    def octo(j0, k0, k1, key):
        for i in range(-2, 2):
            for j in range(j0, j0 + 4):
                if i in W and j in (j0, j0 + 3):
                    continue
                for k in range(k0, k1 + 1):
                    it.put(i, j, k, key)

    # Long cache-flamme à fentes (k = -57 à -53).
    octo(3, -57, -53, "parker_dark")
    for k in (-56, -55, -54):
        for i in W:
            for j in (4, 5):
                it.drop(i, j, k)
    for i in (-1, 0):
        for j in (4, 5):
            it.paint(i, j, -57, "-z", "bore")
    # Bloc de guidon et de gaz (k = -52 à -49), oreilles, guidon (j = 9,
    # ligne de mire à 10), régulateur de gaz à gauche.
    F(-2, 1, 3, 6, -52, -49, "parker")
    F(-1, 0, 7, 9, -50, -50, "parker_dark")
    for i in W:
        F(i, i, 7, 10, -51, -50, "parker")
    F(-3, -3, 5, 5, -52, -51, "steel")
    # Canon nu (rangées 4 et 5) jusqu'au garde-main, puis jusqu'au boîtier.
    F(-1, 0, 4, 5, -48, -18, "parker_dark")
    # Garde-main ajouré en polymère noir (k = -40 à -18).
    octo(2, -40, -18, "poly")
    F(-1, 0, 6, 6, -40, -18, "poly")
    for k in range(-38, -19, 3):
        for i, d in ((1, "+x"), (-2, "-x")):
            it.paint(i, 4, k, d, "bore", f=3.0)
    # Boîtier supérieur (rangées 3 à 7) et inférieur (rangées 0 à 2),
    # parkérisés gris.
    F(-2, 1, 3, 7, -17, 3, "parker")
    F(-2, 1, 0, 2, -12, 3, "parker", f=0.9)
    for k in range(-9, -4):
        it.paint(1, 5, k, "+x", "bore", f=3.0)    # fenêtre d'éjection
    # Poignée de transport repliée à plat sur le flanc gauche.
    F(-3, -3, 6, 7, -13, -7, "parker_dark")
    # Levier d'armement à gauche, à l'avant (pièce « slide »).
    F(-3, -3, 4, 4, -16, -15, "steel", g="slide")
    it.put(-4, 4, -16, "steel", g="slide")
    # Hausse à œilleton sur le couvercle : socle, deux oreilles, cran de 2.
    F(-2, 1, 8, 8, 0, 2, "parker_dark")
    for i in W:
        F(i, i, 9, 9, 1, 2, "parker_dark")
    # Chargeur droit de 20 (pièce « mag »), à peine courbé, et levier de
    # déverrouillage derrière.
    F(-2, 1, -1, -1, -12, -6, "parker", f=0.9)
    for i in (-1, 0):
        for k in range(-11, -6):
            it.drop(i, -1, k)
    last = 0
    for r in range(12):
        s = -(r // 6)
        F(-1, 0, -1 - r, -1 - r, -11 + s, -7 + s, "parker_dark", g="mag")
        last = s
    F(-2, 1, -13, -13, -11 + last, -7 + last, "gun_black", g="mag")
    F(-1, 0, -2, -2, -6, -6, "steel")
    # Pontet, détente, poignée pistolet noire.
    F(-1, 0, -3, -1, -4, -4, "parker")
    F(-1, 0, -3, -3, -3, 1, "parker")
    F(-1, 0, -2, -1, -1, -1, "gun_black")
    for r in range(9):
        j = -1 - r
        s = r // 3
        F(-2, 1, j, j, 1 + s, 4 + s, "poly")
        if r % 2:
            for i, d in ((1, "+x"), (-2, "-x")):
                it.paint(i, j, 2 + s, d, "poly", f=0.75)
    # Crosse fixe noire : poignet fin derrière le boîtier (rangées 2 à 7),
    # dessus qui descend de deux rangées, dessous qui plonge vers le talon.
    for k in range(4, 29):
        t = (k - 4) / 24.0
        top = 7 - round(2 * t)
        bot = 2 - round(7 * t)
        F(-2, 1, bot, top, k, k, "poly")
    F(-2, 1, -5, 5, 29, 29, "gun_black")            # plaque de couche
    for k in (20, 21):                               # anneau de grenadière
        bot = 2 - round(7 * (k - 4) / 24.0)
        F(-1, 0, bot - 1, bot - 1, k, k, "steel")
    # Points remarquables (axe : x = 0 entre les colonnes -1 et 0).
    line = 10
    it.a("sight", 0, line, 2.0)
    it.a("front", 0, line, -49.5)
    it.a("muzzle", 0, 5.0, -57)
    it.a("eject", 2.0, 5.5, -7)
    it.a("grip", 0, 0, 3.0)
    it.info["grip_angle"] = -18.0
    it.a("support", 0, 2, -29)
    it.a("pivot_slide", -4, 4.5, -15.5)
    it.info["slide_travel"] = 0.06
    it.a("pivot_mag", 0, 0, -9)
    d = (0.0, -13.0, float(last))
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/fnfal.md).
    it.a("att_muzzle", 0, 5.0, -57)
    it.a("att_optic", 0, 8, -8)
    it.a("att_mag", 0, -1, -9)
    it.a("att_stock", 0, 0, 29)
    it.a("att_rail", 0, 2, -29)
    return it


# ---------------------------------------------------------------------------
# Mitraillette (id interne « spectre ») : SITES Spectre M4 réelle (Italie,
# 9 × 19 mm, CHARGEUR DE 50 À QUATRE RANGÉES, crosse en fil qui se replie
# par-dessus), 580 mm crosse dépliée -> 50 cubes. Boîtier gris très foncé ;
# manchon de canon ajouré devant (on voit le canon dans les trous) ; guidon
# à oreilles sur le manchon, hausse sur le boîtier ; bouton d'armement à
# gauche (pièce « slide ») ; chargeur très épais et très long ; poignée en
# polymère ; crosse en fil dépliée au ras du dessus et plaque de couche.
# ---------------------------------------------------------------------------

def b_spectre():
    it = Item("spectre", "smg")
    F = it.fill
    # Boîtier (k = -8 à 9, rangées 0 à 4).
    F(-1, 1, 0, 4, -8, 9, "gun_dark")
    for k in range(-4, 0):
        it.paint(1, 3, k, "+x", "bore", f=3.0)     # fenêtre d'éjection
    it.paint(-1, 1, 3, "-x", "steel")              # sélecteur
    # Manchon ajouré (k = -20 à -9, rangées 1 à 3) : trous sur les flancs et
    # le dessus, canon visible dedans.
    F(-1, 1, 1, 3, -20, -9, "gun_black")
    for k in range(-19, -9, 2):
        for i in (-1, 1):
            it.drop(i, 2, k)
        if k % 4 == 1:
            it.drop(0, 3, k)
    F(0, 0, 2, 2, -21, -9, "steel")                # canon
    it.paint(0, 2, -21, "-z", "bore")
    # Guidon à oreilles sur le manchon, hausse sur le boîtier (ligne à j = 6).
    F(0, 0, 4, 5, -19, -19, "gun_black")
    for i in (-1, 1):
        F(i, i, 4, 5, -19, -18, "gun_black")      # oreilles basses
    F(-1, 1, 5, 5, 6, 7, "gun_black")
    # Bouton d'armement à gauche, sur le dessus (pièce « slide »).
    F(-2, -2, 4, 4, -6, -5, "steel", g="slide")
    # Puits et chargeur de 50 à quatre rangées (pièce « mag ») : 3 de large,
    # 5 de profondeur, très long.
    F(-1, 1, -2, -1, -8, -3, "gun_dark")
    for i in (-1, 0, 1):
        for j in (-2, -1):
            for k in range(-7, -3):
                it.drop(i, j, k)
    F(-1, 1, -16, -1, -7, -4, "parker_dark", g="mag")
    for j in range(-15, -2, 3):
        for i, d in ((1, "+x"), (-1, "-x")):
            for k in range(-7, -3):
                it.paint(i, j, k, d, "gun_black", g="mag")   # nervures
    F(-1, 1, -17, -17, -8, -3, "gun_black", g="mag")
    # Pontet, détente, poignée en polymère inclinée.
    F(0, 0, -3, -1, -2, -2, "gun_dark")
    F(0, 0, -3, -3, -1, 2, "gun_dark")
    F(0, 0, -2, -1, 0, 0, "gun_black")
    for r in range(9):
        j = -1 - r
        s = r // 4
        F(-1, 1, j, j, 3 + s, 5 + s, "poly")
        if r % 2:
            for i, d in ((1, "+x"), (-1, "-x")):
                it.paint(i, j, 4 + s, d, "poly", f=0.75)
    # Crosse en fil dépliée au ras du dessus : charnière, deux bras de 2
    # rangées, plaque de couche.
    F(-1, 1, 3, 4, 10, 10, "gun_black")
    for i in (-1, 1):
        F(i, i, 3, 4, 11, 28, "gun_dark")
    F(-1, 1, -4, 4, 29, 29, "gun_black")
    # Points remarquables.
    line = 6
    it.a("sight", 0, line, 7.5)
    it.a("front", 0, line, -18.5)
    it.a("muzzle", 0, 2.5, -21)
    it.a("eject", 1.0, 3.5, -2)
    it.a("grip", 0, 0, 4.0)
    it.info["grip_angle"] = -14.0
    it.a("support", 0, 1, -14)
    it.a("pivot_slide", -2, 4.5, -5.5)
    it.info["slide_travel"] = 0.04
    it.a("pivot_mag", 0, 0, -5.5)
    it.anchors["mag_dir"] = [0.0, -1.0, 0.0]
    it.info["mag_len"] = round(17 * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.25]
    # Points d'attache des pièces visibles (docs/weapons/spectre.md).
    it.a("att_muzzle", 0, 2.5, -21)
    it.a("att_optic", 0, 5, -2)
    it.a("att_mag", 0, -17, -5.5)
    it.a("att_stock", 0, 4, 10)
    it.a("att_rail", 0, 1, -14)
    return it


# ---------------------------------------------------------------------------
# Revolver (id interne « python ») : Colt Python réel (.357 Magnum, 6 coups,
# canon de 6 pouces), 292 mm -> 26 cubes. Largeurs PAIRES (axe du canon
# y = 4). Signatures : BANDE VENTILÉE sur le canon (rib posé sur des
# piliers, jours entre eux) et TENON PLEIN sous le canon jusqu'à la bouche ;
# barillet cannelé de 4 × 4 aux coins abattus (pièce « cyl », bascule à
# gauche autour du pivot) ; carcasse bleu nuit ; chien à crête ; poignée en
# noyer quadrillée très inclinée.
# ---------------------------------------------------------------------------

def b_python():
    it = Item("python", "revolver", even=True)
    F = it.fill
    W = (-2, 1)
    # Canon à tenon plein (rangées 3 et 4, la rangée basse plus sombre : le
    # tenon jusqu'à la bouche).
    F(-1, 0, 4, 4, -18, -6, "blued")
    F(-1, 0, 3, 3, -18, -6, "blued", f=0.85)
    for i in (-1, 0):
        for j in (3, 4):
            it.paint(i, j, -18, "-z", "bore")
    # Bande ventilée posée sur le canon (rangée 5), fenêtres sombres sur les
    # flancs un cube sur deux.
    F(-1, 0, 5, 5, -18, 2, "blued")
    for k in range(-17, -6, 2):
        it.paint(-1, 5, k, "-x", "bore", f=3.0)
        it.paint(0, 5, k, "+x", "bore", f=3.0)
    # Guidon en rampe au bout de la bande (sommet : j = 7).
    F(-1, 0, 6, 6, -18, -16, "blued")
    it.paint(-1, 6, -17, "+y", "red")
    it.paint(0, 6, -17, "+y", "red")
    # Carcasse : avant (k = -5), pont supérieur, fond sous le barillet,
    # bouclier arrière ; hausse à deux oreilles sur le pont.
    F(-2, 1, 1, 5, -5, -5, "blued")
    F(-1, 0, 5, 5, -4, 2, "blued")
    F(-1, 0, 0, 0, -5, 2, "blued")
    F(-2, 1, 0, 5, 1, 2, "blued")
    for i in W:
        F(i, i, 6, 6, 1, 2, "blued")
    # Chien à crête derrière la hausse (sous la ligne de mire).
    F(-1, 0, 3, 5, 3, 3, "gun_black")
    F(-1, 0, 5, 5, 4, 4, "gun_black")
    # Barillet cannelé (pièce « cyl ») : 4 × 4 aux coins abattus, k = -4 à 0.
    for i in range(-2, 2):
        for j in range(1, 5):
            if i in W and j in (1, 4):
                continue
            F(i, i, j, j, -4, 0, "steel", g="cyl", f=0.75)
    for i, d in ((1, "+x"), (-2, "-x")):
        for k in range(-4, 1):
            it.paint(i, 2, k, d, "blued", g="cyl")  # cannelure sur la longueur
    for i in (-1, 0):
        for k in range(-4, 1):
            it.paint(i, 4, k, "+y", "blued", g="cyl")
            it.paint(i, 1, k, "-y", "blued", g="cyl")
    # Pontet arrondi, détente.
    F(-1, 0, -2, -1, -4, -4, "blued")
    F(-1, 0, -3, -3, -3, 0, "blued")
    F(-1, 0, -2, -1, -2, -2, "gun_black")
    # Poignée en noyer très inclinée (un cube vers l'arrière toutes les deux
    # rangées et demie), quadrillée, culot d'acier.
    for r in range(9):
        j = -1 - r
        s = (r * 2) // 5
        F(-2, 1, j, j, 1 + s, 4 + s, "walnut" if r < 8 else "blued")
        if 1 <= r <= 7:
            for i, d in ((1, "+x"), (-2, "-x")):
                for kk in (2 + s, 3 + s):
                    if (j + kk) % 2:
                        it.paint(i, j, kk, d, "walnut", f=0.84)
    F(-1, 0, 0, 0, 3, 4, "blued")                     # tenon de poignée
    # Points remarquables (axe : x = 0 entre les colonnes -1 et 0).
    line = 7
    it.a("sight", 0, line, 2.0)
    it.a("front", 0, line, -16.5)
    it.a("muzzle", 0, 4.0, -18)
    it.a("eject", 0.0, 4.0, -2)
    it.a("grip", 0, 0, 2.5)
    it.info["grip_angle"] = -round(math.degrees(math.atan2(3.0, 8.0)), 1)
    it.a("support", 0, -2, 1)
    it.a("pivot_cyl", -2, 1, -2)
    it.a("pivot_mag", 0, 3, 0)
    it.anchors["mag_dir"] = [0.0, 0.0, 1.0]
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.4]
    it.anchors["hold"] = [-0.06, 0.15, 0.33]
    it.anchors["hold_rot"] = [0.0, 0.32, -0.08]
    # Points d'attache des pièces visibles (docs/weapons/python.md).
    it.a("att_muzzle", 0, 4.0, -18)
    it.a("att_optic", 0, 6, -8)
    it.a("att_grip_l", -2.5, -4, 4)
    it.a("att_grip_r", 2.5, -4, 4)
    it.a("att_rail", 0, 1, -12)
    return it


# ---------------------------------------------------------------------------
# Fusil à munitions sans douille (id interne « g11 ») : HK G11 K2 réel
# (4,73 × 33 mm, chargeur de 50 couché au-dessus du canon, rafale ultra-
# rapide), 750 mm -> 59 cubes. Grand BOÎTIER FERMÉ en polymère vert-noir,
# avant chanfreiné, petit canon qui sort en bas ; trappe du chargeur sur le
# dessus avant (pièce « mag ») ; POIGNÉE DE TRANSPORT avec LUNETTE INTÉGRÉE
# (objectif bleu, œilleton caoutchouc) ; grosse MOLETTE D'ARMEMENT ronde sur
# le flanc gauche (pièce « slide ») ; poignée pistolet sous le milieu ;
# plaque de couche en caoutchouc.
# ---------------------------------------------------------------------------

def b_g11():
    it = Item("g11", "rifle")
    F = it.fill
    # Boîtier (5 de large, rangées 0 à 9), avant chanfreiné en escalier.
    F(-2, 2, 0, 6, -35, 21, "g11_body")
    F(-2, 2, 7, 7, -34, 21, "g11_body")
    F(-2, 2, 8, 8, -33, 21, "g11_body")
    F(-2, 2, 9, 9, -31, 21, "g11_body")
    F(-2, 2, 0, 9, 22, 22, "rubber_black")        # plaque de couche
    # Nervures et joints de coque sur les flancs.
    for i, d in ((2, "+x"), (-2, "-x")):
        for k in range(-30, 20):
            it.paint(i, 6, k, d, "g11_body", f=0.78)
        for k in (-20, -8, 12):
            for j in range(1, 6):
                it.paint(i, j, k, d, "g11_body", f=0.78)
    # Petit canon qui sort en bas de l'avant.
    for (i, j) in ((0, 1), (0, 2), (0, 3), (-1, 2), (1, 2)):
        it.put(i, j, -36, "gun_black")
    it.paint(0, 2, -36, "-z", "bore")
    # Trappe du chargeur couché (pièce « mag ») sur le dessus avant.
    F(-1, 1, 10, 10, -29, -9, "g11_mag", g="mag")
    F(-1, 1, 10, 10, -30, -30, "gun_black", g="mag")
    # Poignée de transport à lunette intégrée : deux montants, tube 3 × 3
    # aux coins abattus, objectif bleu devant, œilleton caoutchouc derrière.
    F(-1, 1, 10, 10, -6, -4, "g11_body")
    F(-1, 1, 10, 10, 10, 12, "g11_body")
    for k in range(-7, 15):
        for (i, j) in ((0, 11), (0, 12), (0, 13), (-1, 12), (1, 12)):
            it.put(i, j, k, "gun_black")
        for i in (-1, 1):
            for j in (11, 13):
                it.put(i, j, k, "gun_black")
    it.paint(0, 12, -7, "-z", "lens")
    for (i, j) in ((0, 11), (0, 13), (-1, 12), (1, 12)):
        it.paint(i, j, -7, "-z", "lens", f=0.7)
    F(-1, 1, 11, 13, 15, 16, "rubber_black")       # œilleton
    it.drop(0, 12, 16)
    it.drop(0, 12, 15)
    # Molette d'armement ronde sur le flanc gauche (pièce « slide »).
    for j in range(1, 6):
        for k in range(6, 11):
            if (j in (1, 5)) and (k in (6, 10)):
                continue                              # disque : coins abattus
            it.put(-3, j, k, "gun_black", g="slide")
    F(-4, -4, 2, 4, 7, 9, "gun_dark", g="slide")
    it.put(-5, 3, 8, "steel", g="slide")          # poignée de la molette
    # Sélecteur et détente.
    it.paint(2, 3, 2, "+x", "steel")
    F(0, 0, -3, -1, -4, -4, "g11_body")
    F(0, 0, -3, -3, -3, 0, "g11_body")
    F(0, 0, -2, -1, -2, -2, "gun_black")
    # Poignée pistolet (3 de large, inclinée).
    for r in range(9):
        j = -1 - r
        s = r // 3
        F(-1, 1, j, j, 1 + s, 4 + s, "g11_body")
        if r % 2:
            for i, d in ((1, "+x"), (-1, "-x")):
                it.paint(i, j, 2 + s, d, "g11_body", f=0.75)
    # Points remarquables : la ligne de visée passe dans l'axe de la lunette.
    line = 12.5
    it.a("sight", 0, line, 15.0)
    it.a("front", 0, line, -7.0)
    it.a("muzzle", 0, 2.5, -36)
    it.a("eject", 0.0, 0.0, 0)
    it.a("grip", 0, 0, 2.5)
    it.info["grip_angle"] = -18.0
    it.a("support", 0, 0, -22)
    it.a("pivot_slide", -4, 3.5, 8.5)  # molette : axe x, au centre du disque
    it.info["slide_travel"] = 0.0
    it.a("pivot_mag", 0, 10.5, -19)
    it.anchors["mag_dir"] = [0.0, 0.6, -0.8]
    it.info["mag_len"] = round(21 * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/g11.md).
    it.a("att_muzzle", 0, 2.5, -36)
    it.a("att_optic", 0, 14, 4)
    it.a("att_mag", 0, 11, -19)
    it.a("att_stock", 0, 4.5, 23)
    it.a("att_rail", 0, 0, -22)
    return it


# ---------------------------------------------------------------------------
# Fusil d'assaut (id interne « galil ») : IMI Galil ARM réel (5,56 × 45 mm,
# chargeur courbe de 35, bipied, crosse tubulaire repliable dépliée),
# 979 mm -> 79 cubes. Dérivé de la Kalachnikov : long cache-flamme, bloc de
# guidon à tunnel, BIPIED replié sous le canon, GARDE-MAIN EN BOIS CLAIR
# AJOURÉ, POIGNÉE DE TRANSPORT au-dessus du garde-main, boîtier bronzé,
# LEVIER D'ARMEMENT RELEVÉ à droite (pièce « slide »), chargeur courbe de
# 35, poignée noire, crosse tubulaire à deux tubes et plaque de couche.
# ---------------------------------------------------------------------------

def b_galil():
    it = Item("galil", "rifle")
    F = it.fill
    cross = ((0, 0), (0, 1), (0, 2), (-1, 1), (1, 1))
    # Boîtier (k = -11 à 7) et couvercle.
    F(-1, 1, 0, 2, -11, 7, "blued")
    F(-1, 1, 3, 3, -10, 7, "gun_black")
    it.put(0, 3, 8, "gun_black")
    for k in range(-4, -1):
        it.paint(1, 2, k, "+x", "bore", f=3.0)     # fenêtre d'éjection
    it.paint(-1, 1, 3, "-x", "steel")              # sélecteur
    # Hausse à l'arrière du couvercle (ligne de mire à j = 5).
    for i in (-1, 1):
        F(i, i, 4, 4, 5, 6, "gun_black")
    # Levier d'armement relevé à droite (pièce « slide »).
    F(2, 2, 2, 3, -6, -6, "steel", g="slide")
    it.put(2, 4, -6, "steel", g="slide")
    # Garde-main en bois clair ajouré (k = -29 à -12), poignée de transport.
    F(-1, 1, 0, 3, -29, -12, "galil_wood")
    for k in range(-27, -13, 3):
        for i, d in ((1, "+x"), (-1, "-x")):
            it.paint(i, 2, k, d, "bore", f=3.0)    # fentes d'aération
            it.paint(i, 1, k, d, "bore", f=3.0)
    F(0, 0, 4, 5, -21, -21, "gun_black")
    F(0, 0, 4, 5, -13, -13, "gun_black")
    F(0, 0, 6, 6, -21, -13, "gun_black")
    # Canon (section en croix) et bloc de gaz / guidon à tunnel.
    for k in range(-46, -29):
        for (i, j) in cross:
            it.put(i, j, k, "gun_black")
    F(-1, 1, 0, 3, -45, -43, "blued")
    F(0, 0, 4, 4, -44, -44, "gun_black")
    for i in (-1, 1):
        F(i, i, 4, 5, -44, -44, "gun_black")
    # Long cache-flamme à fentes.
    for k in range(-52, -46):
        for (i, j) in cross:
            it.put(i, j, k, "gun_dark")
    for k in (-51, -49):
        for i in (-1, 1):
            it.drop(i, 1, k)
    it.paint(0, 1, -52, "-z", "bore")
    # Bipied replié sous le canon (deux jambes, pivot sous le bloc de gaz).
    F(-1, 1, -1, -1, -43, -43, "gun_black")
    for i in (-1, 1):
        F(i, i, -1, -1, -42, -30, "gun_dark")
    # Chargeur courbe de 35 (pièce « mag »).
    last = 0
    for r in range(14):
        s = -(r // 3)
        F(-1, 1, -1 - r, -1 - r, -7 + s, -3 + s, "parker_dark", g="mag")
        last = s
    F(-1, 1, -15, -15, -7 + last, -3 + last, "gun_black", g="mag")
    # Pontet, détente, poignée noire inclinée.
    for j in (-1, -2):
        it.put(0, j, -2, "gun_black")
    for k in range(-2, 2):
        it.put(0, -3, k, "gun_black")
    it.put(0, -1, 0, "gun_black")
    for r in range(8):
        s = r // 3
        F(-1, 1, -1 - r, -1 - r, 1 + s, 3 + s, "poly")
    # Crosse tubulaire dépliée : charnière, tube haut, tube bas qui descend,
    # plaque de couche.
    F(-1, 1, 0, 3, 8, 9, "gun_black")
    F(0, 0, 3, 3, 10, 30, "gun_dark")
    prev = 0
    for k in range(10, 31):
        j = -round((k - 10) * 5 / 20.0)
        for jj in range(j, prev + 1):
            it.put(0, jj, k, "gun_dark")
        prev = j
    F(-1, 1, -6, 3, 31, 31, "rubber_black")
    # Points remarquables.
    line = 5
    it.a("sight", 0, line, 6.0)
    it.a("front", 0, line, -43.5)
    it.a("muzzle", 0, 1.5, -52)
    it.a("eject", 1.0, 2.5, -3)
    it.a("grip", 0, 0, 2.5)
    it.info["grip_angle"] = -18.0
    it.a("support", 0, 0, -21)
    it.a("pivot_slide", 2, 3.0, -5.5)
    it.info["slide_travel"] = 0.06
    it.a("pivot_mag", 0, 0, -4.5)
    d = (0.0, -15.0, float(last))
    n = math.sqrt(sum(x * x for x in d))
    it.anchors["mag_dir"] = [0.0, round(d[1] / n, 4), round(d[2] / n, 4)]
    it.info["mag_len"] = round(n * FINE, 4)
    it.info["cube"] = FINE
    it.anchors["ads"] = [0.0, 0.0, 0.3]
    # Points d'attache des pièces visibles (docs/weapons/galil.md).
    it.a("att_muzzle", 0, 1.5, -52)
    it.a("att_optic", 0, 4, -2)
    it.a("att_mag", 0, -1, -4.5)
    it.a("att_stock", 0, 1.5, 8)
    it.a("att_rail", 0, 0, -21)
    return it


BUILDERS = {"m1911": b_m1911, "ak74u": b_ak74u, "ak47": b_ak47, "famas": b_famas, "mp40": b_mp40, "olympia": b_olympia, "stakeout": b_stakeout, "m14": b_m14, "mp5k": b_mp5k, "cz75": b_cz75, "pm63": b_pm63, "mpl": b_mpl, "m16": b_m16, "spas12": b_spas12, "fnfal": b_fnfal, "spectre": b_spectre, "python": b_python, "g11": b_g11, "galil": b_galil}


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


def floating(it):
    """Blocs détachés : pour chaque pièce, les cellules hors de sa plus grande
    composante (voisinage par les faces). Une pièce doit être d'un seul
    tenant (un anneau ou une vis qui « flotte » sous la crosse est un défaut)."""
    out = {}
    for g, p in it.pieces.items():
        left = set(p.cells)
        comps = []
        while left:
            stack = [left.pop()]
            comp = set(stack)
            while stack:
                i, j, k = stack.pop()
                for n in ((i + 1, j, k), (i - 1, j, k), (i, j + 1, k), (i, j - 1, k), (i, j, k + 1), (i, j, k - 1)):
                    if n in left:
                        left.discard(n)
                        comp.add(n)
                        stack.append(n)
            comps.append(comp)
        comps.sort(key=len, reverse=True)
        lost = [c for comp in comps[1:] for c in comp]
        if lost:
            out[g] = sorted(lost)
    return out


def build(it):
    bad = floating(it)
    for g, cells in bad.items():
        print("[weapons_fine] %s : %d cube(s) détaché(s) dans « %s » : %s" % (
            it.id, len(cells), g, ", ".join(str(c) for c in cells[:8])))
    if bad:
        raise SystemExit("[weapons_fine] %s : blocs détachés, modèle refusé" % it.id)
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


if __name__ == "__main__":
    main()
