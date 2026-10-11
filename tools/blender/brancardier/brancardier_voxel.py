# Le BRANCARDIER CUBIQUE (GAME_CONCEPT.md § 4.4 : mini-boss « gros zombie qui
# charge », échantillons sangle de cuir et bracelet d'identification ; § 4.19 :
# personnages et mobs en cubes de 2,5 cm). Ancien brancardier de l'hôpital
# devenu une brute massive : tenue de bloc bleu-vert déchirée, sabots blancs
# crottés, peau verdâtre des zombies du jeu marbrée de veines violettes,
# crâne rasé recousu, mâchoire prognathe aux dents qui dépassent, yeux qui
# luisent ; son BRANCARD (cadre d'acier, toile verte d'hôpital, roulettes)
# sanglé sur le dos par des SANGLES DE CUIR à boucles (une en bandoulière sur
# la poitrine), des sangles de contention arrachées autour des avant-bras
# (un bout pend au poignet droit) et le BRACELET D'IDENTIFICATION blanc à
# étiquette bleue au poignet gauche (ses deux échantillons) ; masque
# chirurgical arraché pendu au cou ; poings énormes.
#
#   sh tools/blender.sh tools/blender/brancardier/brancardier_voxel.py [--glb FICHIER] [--sheet FICHIER.png] [--cache]
#
# Pas de planche de référence : formes DÉCRITES ici par pavés de cubes aux
# arêtes arrondies d'un cube (comme le chien et le joueur), couleurs d'une
# palette et d'un bruit par blocs de 2 ou 3 cubes (voxel_lib.noise : texture
# « un pixel = un cube » reproductible, faces voisines de même teinte
# fusionnées : budget de triangles).
# Ossature : RigBuilder.BONES (hips > spine > chest > neck > head > jaw, bras,
# avant-bras, cuisses, tibias), os droits, repos membres pendants, pondération
# rigide (chaque cube à 100 % sur un os) ; poings sur l'avant-bras, sabots sur
# le tibia ; le brancard et ses sangles sur la poitrine (il suit le buste).
# Animation : procédurale dans le jeu (scripts/game/brancardier/
# brancardier_anim.gd).
# CACHE : cellules et couleurs de faces dans brancardier_voxel_cells.json
# (suivi par git, à côté du script) ; --cache relit ce fichier (modèle
# identique).
#
# Repère : Z en haut, avant vers -Y, gauche du personnage vers +X. Dans ce
# script, « f » est la profondeur vers l'AVANT : la cellule (x, f, z) est la
# cellule (x, y = -f - 1, z) du modèle.
import bpy, math, os, sys
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_CHAR
CACHE = os.path.join(HERE, "brancardier_voxel_cells.json")

# ---------------------------------------------------------------------------
# Palette (sRGB).
# ---------------------------------------------------------------------------
SKIN = (0.42, 0.50, 0.38)        # peau des zombies du jeu (zombie_voxel.py)
SKIN_DARK = (0.33, 0.40, 0.31)
SKIN_LIGHT = (0.50, 0.57, 0.44)
VEIN = (0.38, 0.30, 0.42)        # veines violettes (infection)
BRUISE = (0.30, 0.27, 0.33)
SCRUB = (0.36, 0.56, 0.56)       # tenue de bloc bleu-vert
SCRUB_DARK = (0.26, 0.42, 0.43)
SCRUB_SEAM = (0.30, 0.48, 0.49)
CLOG = (0.82, 0.82, 0.77)        # sabots blancs
CLOG_SOLE = (0.48, 0.48, 0.46)
DIRT = (0.40, 0.32, 0.22)
BLOOD = (0.40, 0.06, 0.05)
BLOOD_DRY = (0.29, 0.08, 0.06)
FLESH = (0.52, 0.14, 0.12)
LEATHER = (0.40, 0.24, 0.13)     # sangles de cuir
LEATHER_DARK = (0.27, 0.15, 0.08)
BUCKLE = (0.70, 0.68, 0.60)
STEEL = (0.62, 0.64, 0.66)       # cadre du brancard
STEEL_DARK = (0.42, 0.44, 0.46)
CANVAS = (0.56, 0.50, 0.36)      # toile kaki usée
CANVAS_DARK = (0.44, 0.38, 0.27)
RUBBER = (0.10, 0.10, 0.11)      # roulettes
BAND = (0.93, 0.92, 0.88)        # bracelet d'identification
TAG = (0.24, 0.42, 0.78)         # étiquette bleue
MASK = (0.62, 0.80, 0.84)        # masque chirurgical
STITCH = (0.12, 0.10, 0.09)
EYE = (1.0, 0.88, 0.30)          # lueur des yeux (zombies du jeu)
TOOTH = (0.86, 0.80, 0.58)
MOUTH = (0.14, 0.04, 0.04)
NAIL = (0.30, 0.30, 0.24)


def cell(x, f, z):
    return (x, -f - 1, z)


def mix(a, b, k):
    return tuple(x + (y - x) * k for x, y in zip(a, b))


class Body:
    def __init__(self):
        self.m = vx.Model(CUBE)

    def put(self, x, f, z, mat, bone, part, color):
        self.m.set(*cell(x, f, z), mat, bone, part, color)

    def get(self, x, f, z):
        return self.m.vox.get(cell(x, f, z))

    def drop(self, x, f, z):
        self.m.vox.pop(cell(x, f, z), None)

    def slab(self, x0, x1, f0, f1, z0, z1, mat, bone, part, colfn, round_xy=1, round_top=0, round_bottom=0):
        """Pavé [x0, x1) × [f0, f1) × [z0, z1) aux arêtes verticales arrondies
        de `round_xy` cubes (marche d'escalier), au bord du dessus ou du
        dessous arrondi d'un cube (round_top / round_bottom)."""
        for x in range(x0, x1):
            for f in range(f0, f1):
                ex = min(x - x0, x1 - 1 - x)
                ef = min(f - f0, f1 - 1 - f)
                if round_xy and ex + ef < round_xy:
                    continue
                for z in range(z0, z1):
                    if round_top and z == z1 - 1 and (ex == 0 or ef == 0):
                        continue
                    if round_bottom and z == z0 and (ex == 0 or ef == 0):
                        continue
                    self.put(x, f, z, mat, bone, part, colfn(x, f, z))

    def face(self, x, f, z, d, color, mat=None):
        c = cell(x, f, z)
        if c not in self.m.vox:
            return False
        self.m.face_color[(c[0], c[1], c[2], d)] = color
        if mat:
            self.m.face_mat[(c[0], c[1], c[2], d)] = mat
        return True

    def front(self, x, z, part=None):
        fs = [-c[1] - 1 for c, v in self.m.vox.items() if c[0] == x and c[2] == z and (part is None or v.part == part)]
        return max(fs) if fs else None

    def back(self, x, z, part=None):
        fs = [-c[1] - 1 for c, v in self.m.vox.items() if c[0] == x and c[2] == z and (part is None or v.part == part)]
        return min(fs) if fs else None

    def paint_front(self, x, z, color, mat=None, part=None):
        f = self.front(x, z, part)
        if f is not None:
            self.face(x, f, z, "-y", color, mat)
        return f

    def paint_back(self, x, z, color, mat=None, part=None):
        f = self.back(x, z, part)
        if f is not None:
            self.face(x, f, z, "+y", color, mat)
        return f


# ---------------------------------------------------------------------------
# Texture : variation par blocs (tissu : 3 cubes, peau : 2), salissures.
# ---------------------------------------------------------------------------

def scrub(seed, base=SCRUB):
    def fn(x, f, z):
        k = 0.92 + 0.12 * vx.noise((x // 3, f // 3, z // 3), seed)
        c = vx.tone(base, k)
        if vx.noise((x // 3, f // 3, z // 4), seed + 5) > 0.9:
            c = mix(c, DIRT, 0.35)
        if vx.noise((x // 3, f // 3, z // 3), seed + 9) > 0.975:
            c = BLOOD_DRY
        return c
    return fn


def skin(seed, base=SKIN):
    def fn(x, f, z):
        k = 0.93 + 0.12 * vx.noise((x // 2, f // 2, z // 2), seed)
        c = vx.tone(base, k)
        if vx.noise((x // 3, f // 3, z // 3), seed + 3) > 0.88:
            c = mix(c, BRUISE, 0.45)
        return c
    return fn


def solid(color):
    return lambda x, f, z: color


# ---------------------------------------------------------------------------
# Jambes : sabots, pantalon de bloc (tibia z 4..20, cuisse z 20..40).
# ---------------------------------------------------------------------------

def build_legs(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):  # intervalle [a, c) côté gauche -> côté du personnage
            return (a, c) if s > 0 else (-c, -a)
        shin, thigh = "shin_" + side, "thigh_" + side
        # Sabots : semelle épaisse, bout arrondi, crasse.
        x0, x1 = X(2, 12)
        b.slab(x0, x1, -5, 9, 0, 1, "leather", shin, "clog_" + side, solid(CLOG_SOLE), round_xy=2)
        b.slab(x0, x1, -5, 9, 1, 5, "leather", shin, "clog_" + side,
               lambda x, f, z: mix(CLOG, DIRT, 0.5) if vx.noise((x // 2, f // 2, z), 41) > 0.72 or z == 1 else vx.tone(CLOG, 0.96 + 0.05 * vx.noise((x // 2, f // 2, 0), 42)),
               round_xy=2, round_top=1)
        # Ouverture du sabot (cheville) : dessus creusé derrière le cou-de-pied.
        # Tibia (pantalon), ourlet effiloché, cuisse plus épaisse.
        x0, x1 = X(2, 11)
        b.slab(x0, x1, -4, 5, 5, 20, "cloth", shin, "pants_" + side, scrub(11 + s, SCRUB_DARK), round_xy=1)
        x0, x1 = X(1, 12)
        b.slab(x0, x1, -5, 6, 20, 41, "cloth", thigh, "pants_" + side, scrub(13 + s, SCRUB_DARK), round_xy=1)
        # Ourlet déchiré : peau du mollet visible par endroits (bas du tibia).
        for x in range(*X(2, 11)):
            if vx.noise((x, 0, 5), 17 + s) > 0.55:
                b.paint_front(x, 5, mix(SKIN, BRUISE, 0.3), "skin")
            if vx.noise((x, 1, 5), 18 + s) > 0.5:
                b.paint_back(x, 5, SKIN_DARK, "skin")
        # Genoux râpés : sang séché, toile élimée.
        for x in range(*X(3, 10)):
            for z in (19, 20, 21):
                if vx.noise((x, z, s), 19) > 0.35:
                    b.paint_front(x, z, mix(SCRUB_DARK, BLOOD_DRY, 0.55 + 0.2 * vx.noise((x, z, 0), 20)), "cloth")
        # Couture latérale.
        xo = (X(1, 12)[1] - 1) if s > 0 else X(1, 12)[0]
        for z in range(20, 41):
            f = 0
            b.face(xo, f, z, "+x" if s > 0 else "-x", SCRUB_SEAM, "cloth")


# ---------------------------------------------------------------------------
# Bassin, ventre, poitrine, épaules (tunique de bloc à encolure en V).
# ---------------------------------------------------------------------------

def build_torso(b):
    # Bassin (cordon du pantalon z 44, bas de la tunique qui retombe).
    b.slab(-13, 13, -7, 8, 39, 46, "cloth", "hips", "pants_hips", scrub(21, SCRUB_DARK), round_xy=2)
    for x in range(-13, 13):
        b.paint_front(x, 44, vx.tone(SCRUB_DARK, 0.8), "cloth")
    for x in (-1, 0):
        for z in (40, 41, 42, 43):
            b.paint_front(x, z, BAND if z > 41 else vx.tone(BAND, 0.85), "cloth")  # cordon noué
    # Ventre (spine) : tunique, gros ventre en avant.
    b.slab(-14, 14, -8, 9, 46, 57, "cloth", "spine", "tunic", scrub(23), round_xy=2)
    b.slab(-11, 11, 9, 11, 47, 56, "cloth", "spine", "tunic", scrub(23), round_xy=2, round_top=1, round_bottom=1)
    # Bas de la tunique qui recouvre le haut du bassin (ourlet sur le bassin).
    b.slab(-14, 14, -8, 9, 44, 46, "cloth", "hips", "tunic", scrub(23), round_xy=2)
    # Poitrine (chest) : très large, pectoraux en avant, dos voûté.
    b.slab(-16, 16, -9, 9, 57, 70, "cloth", "chest", "tunic", scrub(25), round_xy=2)
    b.slab(-13, 13, 9, 10, 60, 69, "cloth", "chest", "tunic", scrub(25), round_xy=2)
    b.slab(-15, 15, -10, -9, 59, 69, "cloth", "chest", "tunic", scrub(25), round_xy=2)
    # Épaules et trapèzes en escalier (cou enfoncé).
    b.slab(-15, 15, -9, 8, 70, 72, "cloth", "chest", "tunic", scrub(25), round_xy=3)
    b.slab(-10, 10, -6, 4, 72, 74, "skin", "chest", "traps", skin(27), round_xy=2)
    # Encolure en V : peau de la poitrine (marches de cubes), poils... de zombie.
    for z, xs in ((69, range(-5, 5)), (68, range(-4, 4)), (67, range(-3, 3)), (66, range(-2, 2)), (65, range(-1, 1))):
        for x in xs:
            f = b.front(x, z)
            if f is not None:
                b.drop(x, f, z)
                b.put(x, f - 1, z, "skin", "chest", "neckline", skin(29)(x, f, z))
    # Liseré plus sombre au bord du V et coutures d'épaules.
    for z, xs in ((69, (-6, 5)), (68, (-5, 4)), (67, (-4, 3)), (66, (-3, 2)), (65, (-2, 1)), (64, (-1, 0))):
        for x in xs:
            b.paint_front(x, z, SCRUB_SEAM, "cloth")
    # Poche de poitrine (gauche) avec un stylo, déchirure au flanc droit
    # (chair à vif), éclaboussures de sang.
    for x in range(4, 10):
        for z in range(60, 64):
            b.paint_front(x, z, vx.tone(SCRUB, 0.86 if z == 63 else 0.93), "cloth")
    for z in (63, 64, 65):
        b.paint_front(6, z, TAG if z < 65 else BAND, "metal")
    for x in range(-13, -7):
        for z in range(49, 54):
            edge = x in (-13, -8) or z in (49, 53)
            if edge and (x, z) in ((-13, 53), (-8, 49)):
                continue
            col = vx.tone(SCRUB, 1.1) if edge else (FLESH if (x + z) % 3 else BLOOD)
            b.paint_front(x, z, col, "cloth" if edge else "wound")
    for x, z in ((2, 58), (3, 58), (3, 57), (-4, 61), (-5, 61), (-5, 60), (10, 52), (11, 51), (0, 50)):
        b.paint_front(x, z, BLOOD, "wound")
    # Dos : coulures et sang.
    for x, z in ((-3, 62), (-3, 61), (-2, 61), (5, 55), (6, 54)):
        b.paint_back(x, z, BLOOD_DRY, "wound")


# ---------------------------------------------------------------------------
# Bras : manches courtes, avant-bras énormes veinés, sangles de contention,
# poings ; bracelet d'identification au poignet gauche.
# ---------------------------------------------------------------------------

def build_arms(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):
            return (a, c) if s > 0 else (-c, -a)
        arm, fore = "arm_" + side, "forearm_" + side
        # Haut du bras (peau) z 52..62, manche courte z 62..72 (plus large).
        x0, x1 = X(17, 25)
        b.slab(x0, x1, -4, 5, 52, 63, "skin", arm, "upper_" + side, skin(31 + s), round_xy=2)
        x0, x1 = X(15, 26)
        b.slab(x0 + (1 if s > 0 else 0), x1 - (0 if s > 0 else 1), -5, 6, 62, 72, "cloth", arm, "sleeve_" + side, scrub(33 + s), round_xy=2, round_top=1)
        # Ourlet de la manche (plus sombre), déchiré sur le dessus du bras droit.
        for x in range(*X(15, 26)):
            for f in range(-5, 6):
                if b.get(x, f, 62) is not None:
                    b.face(x, f, 62, "-z", SCRUB_DARK, "cloth")
        # Avant-bras z 36..52 (épais), poing z 26..36.
        x0, x1 = X(16, 25)
        b.slab(x0, x1, -4, 6, 36, 52, "skin", fore, "forearm_" + side, skin(35 + s), round_xy=2)
        x0, x1 = X(15, 26)
        b.slab(x0, x1, -5, 7, 26, 36, "skin", fore, "fist_" + side, skin(37 + s, SKIN_LIGHT), round_xy=2, round_bottom=1)
        # Phalanges (fentes sombres sur le devant et le dessous), ongles.
        for x in range(*X(15, 26)):
            if (x - X(15, 26)[0]) % 3 == 2:
                for z in (27, 28, 29):
                    b.face(x, 6, z, "-y", vx.tone(SKIN_LIGHT, 0.6), "skin")
            for z in (26,):
                b.face(x, 6, z, "-y", NAIL, "bone")
        # Pouce côté intérieur, devant.
        xi = X(15, 26)[0] - 1 if s > 0 else X(15, 26)[1]
        for z in (31, 32, 33):
            for f in (3, 4, 5):
                b.put(xi, f, z, "skin", fore, "fist_" + side, skin(39)(xi, f, z))
        # Veines violettes sur l'avant-bras (côté extérieur et devant).
        xo = X(16, 25)[1] - 1 if s > 0 else X(16, 25)[0]
        d = "+x" if s > 0 else "-x"
        for z in range(37, 51):
            fv = int(2 + 2 * math.sin(z * 0.7 + s))
            b.face(xo, fv, z, d, VEIN, "skin")
            if z % 4 == 0:
                b.face(xo, fv + 1, z, d, VEIN, "skin")
        for z in range(54, 61):
            b.face(xo, int(1 + math.sin(z * 0.9)), z, d, VEIN, "skin")
        # Sangles de contention arrachées (cuir, boucle d'acier) z 41..42 et 47.
        for z in (41, 42, 47):
            for x in range(X(15, 26)[0], X(15, 26)[1]):
                for f in range(-5, 7):
                    inner = X(16, 25)[0] <= x < X(16, 25)[1] and -4 <= f < 6
                    if inner:
                        continue
                    if x in (X(15, 26)[0], X(15, 26)[1] - 1) and f in (-5, 6):
                        continue
                    col = vx.tone(LEATHER if z != 47 else LEATHER_DARK, 0.92 + 0.08 * vx.noise((x, f, z), 43))
                    b.put(x, f, z, "leather", fore, "strap_" + side, col)
        bx = X(15, 26)[1] if s > 0 else X(15, 26)[0] - 1
        for z in (41, 42):
            b.put(bx, 1, z, "metal", fore, "strap_" + side, BUCKLE)
        b.put(bx, 0, 41, "metal", fore, "strap_" + side, STEEL_DARK)
    # Bout de sangle qui pend du poignet droit (côté extérieur).
    for z in range(31, 41):
        b.put(-27, 0, z, "leather", "forearm_r", "strap_r", vx.tone(LEATHER, 0.9 + 0.1 * vx.noise((0, 0, z), 44)))
        b.put(-27, 1, z, "leather", "forearm_r", "strap_r", vx.tone(LEATHER_DARK, 1.0))
    b.put(-27, 0, 30, "metal", "forearm_r", "strap_r", BUCKLE)
    b.put(-27, 1, 30, "metal", "forearm_r", "strap_r", BUCKLE)
    # Bracelet d'identification au poignet gauche (z 36..37) : bande blanche,
    # étiquette bleue sur le dessus du poignet (côté extérieur).
    for z in (36, 37):
        for x in range(15, 26):
            for f in range(-5, 7):
                inner = 16 <= x < 25 and -4 <= f < 6
                if inner or ((x in (15, 25)) and f in (-5, 6)):
                    continue
                b.put(x, f, z, "cloth", "forearm_l", "bracelet", vx.tone(BAND, 0.95 + 0.05 * vx.noise((x, f, z), 45)))
    for f in (-1, 0, 1, 2):
        for z in (36, 37):
            b.put(26, f, z, "metal", "forearm_l", "bracelet", TAG)
    b.face(26, 0, 37, "+x", BAND, "cloth")
    b.face(26, 1, 36, "+x", BAND, "cloth")


# ---------------------------------------------------------------------------
# Cou, tête : crâne rasé recousu, arcades lourdes, mâchoire prognathe.
# ---------------------------------------------------------------------------

def build_head(b):
    # Cou épais enfoncé entre les trapèzes (z 72..77), un peu en arrière de
    # la mâchoire ; masque chirurgical arraché qui pend devant (z 72..73).
    b.slab(-6, 6, -4, 3, 72, 78, "skin", "neck", "neck", skin(51, SKIN_DARK), round_xy=1)
    for x in range(-6, 6):
        for z in (72, 73):
            b.put(x, 3, z, "cloth", "neck", "mask", vx.tone(MASK, 0.92 + 0.08 * vx.noise((x, 0, z), 52)))
    for x in range(-4, 4):
        b.put(x, 4, 72, "cloth", "neck", "mask", vx.tone(MASK, 0.85))
    for x in (-7, 6):
        for z in (73, 74, 75):
            b.put(x, 1, z, "cloth", "neck", "mask", vx.tone(MASK, 0.7))  # élastiques
    # Mâchoire inférieure (os jaw, z 75..77) : prognathe, menton carré qui
    # avance d'un cube devant le visage.
    b.slab(-6, 6, 0, 10, 75, 78, "skin", "jaw", "jaw", skin(55, SKIN_DARK), round_xy=2)
    # Tête (os head) : joues et haut de la mâchoire z 78..79, crâne z 80..88,
    # calotte z 89 ; visage à f = 8.
    b.slab(-7, 7, -2, 9, 78, 80, "skin", "head", "head", skin(53), round_xy=2)
    b.slab(-7, 7, -3, 9, 80, 89, "skin", "head", "head", skin(53), round_xy=2, round_top=1)
    b.slab(-5, 5, -1, 7, 89, 90, "skin", "head", "head", skin(53), round_xy=1)
    # Bouche : dents du bas (mâchoire) qui dépassent devant la lèvre du haut,
    # une sur deux (les vides montrent le fond sombre), crocs aux coins ;
    # dents du haut peintes sur la lèvre.
    for x in range(-5, 5):
        b.face(x, 8, 78, "-y", MOUTH, "wound")
        if x in (-5, 4) or x % 2 == 0:
            b.put(x, 9, 78, "bone", "jaw", "teeth", TOOTH if x in (-5, 4) else vx.tone(TOOTH, 0.88))
    for x in (-5, 4):
        b.put(x, 9, 79, "bone", "jaw", "teeth", TOOTH)
    for x in range(-4, 4):
        b.face(x, 8, 79, "-y", TOOTH if x % 2 else vx.tone(TOOTH, 0.8), "bone")
    # Yeux 3 × 2 émissifs, enfoncés d'un cube sous des arcades lourdes.
    for s in (1, -1):
        xs = (2, 3, 4) if s > 0 else (-5, -4, -3)
        for x in xs:
            for z in (83, 84):
                b.drop(x, 8, z)
                b.put(x, 7, z, "eye", "head", "eye", EYE)
        for x in range(1, 7) if s > 0 else range(-7, -1):
            b.put(x, 9, 85, "skin", "head", "brow", skin(57, SKIN_DARK)(x, 9, 85))
    # Nez écrasé (deux cubes de large, narines sombres).
    for x in (-1, 0):
        b.put(x, 9, 81, "skin", "head", "nose", SKIN_DARK)
        b.put(x, 9, 82, "skin", "head", "nose", SKIN)
        b.face(x, 9, 81, "-y", vx.tone(SKIN_DARK, 0.5), "skin")
    # Oreilles (la droite à moitié arrachée, à vif).
    for z in (81, 82, 83, 84):
        for f in (1, 2):
            b.put(7, f, z, "skin", "head", "ear", SKIN_DARK)
    for z in (81, 82):
        b.put(-8, 1, z, "skin", "head", "ear", FLESH)
    # Cicatrice recousue sur le crâne (de l'avant vers l'arrière) et veines.
    for f in range(-2, 8):
        z = 89 if -1 <= f < 7 else 88
        b.face(0, f, z, "+z", FLESH if f % 2 else STITCH, "wound")
        if f % 2 == 0:
            b.face(-1, f, z, "+z", STITCH, "wound")
            b.face(1, f, z, "+z", STITCH, "wound")
    for z in range(80, 87):
        b.face(-7, int(4 + 2 * math.sin(z)), z, "-x", VEIN, "skin")
    # Plaie à la joue gauche.
    for x, z in ((5, 79), (6, 79), (5, 80)):
        b.paint_front(x, z, FLESH, "wound", part="head")


# ---------------------------------------------------------------------------
# Brancard sanglé dans le dos (os chest) : cadre d'acier, toile verte,
# roulettes en haut, sangles de cuir (bandoulière sur la poitrine).
# ---------------------------------------------------------------------------

def build_stretcher(b):
    bone = "chest"
    z0, z1 = 30, 91
    xl, xr = 11, -12
    # Montants (2 × 2 cubes) et traverses.
    for x in (xl, xr):
        for f in (-14, -13):
            for z in range(z0, z1):
                col = vx.tone(STEEL, 0.9 + 0.12 * vx.noise((x, f, z // 4), 61))
                b.put(x, f, z, "metal", bone, "stretcher", col)
    for z in (z0, 63, z1 - 3):
        for x in range(xr + 1, xl):
            for f in (-14, -13):
                b.put(x, f, z, "metal", bone, "stretcher", STEEL_DARK if z == 63 else STEEL)
    # Toile tendue (un cube), sale et tachée, rivets.
    for x in range(xr + 1, xl):
        for z in range(z0 + 1, z1 - 3):
            if z == 63:
                continue
            k = 0.92 + 0.12 * vx.noise((x // 3, 0, z // 3), 62)
            col = vx.tone(CANVAS, k)
            if vx.noise((x // 4, 1, z // 5), 63) > 0.9:
                col = mix(col, BLOOD_DRY, 0.6)
            elif vx.noise((x // 2, 2, z // 2), 64) > 0.9:
                col = CANVAS_DARK
            b.put(x, -13, z, "cloth", bone, "canvas", col)
    # Toile déchirée en bas à droite (trou, bords effilochés).
    for x in range(-8, -3):
        for z in range(36, 41):
            if (x, z) not in ((-8, 36), (-4, 40)):
                b.drop(x, -13, z)
    # Poignées au-dessus (prolongent les montants) et roulettes.
    for x in (xl, xr):
        for z in range(z1, z1 + 2):
            b.put(x, -13, z, "leather", bone, "stretcher", vx.tone(RUBBER, 1.6))
        for f in (-16, -15):
            for z in (z1 - 4, z1 - 3, z1 - 2):
                b.put(x, f, z, "leather", bone, "wheel", RUBBER)
        b.put(x, -15, z1 - 3, "metal", bone, "wheel", STEEL_DARK)
    # Pieds repliés du brancard (barre en travers, en bas).
    for x in range(xr, xl + 1):
        for f in (-16, -15):
            b.put(x, f, z0 + 2, "metal", bone, "stretcher", STEEL_DARK)
    # Sangles horizontales qui tiennent le brancard au dos (entre le dos f -9
    # et la toile f -12), et bandoulière : épaule gauche -> hanche droite.
    for z in (66, 67, 50, 51):
        for x in range(-12, 12):
            for f in (-12, -11, -10):
                if b.get(x, f, z) is None:
                    b.put(x, f, z, "leather", bone, "strap", vx.tone(LEATHER, 0.9 + 0.1 * vx.noise((x // 2, f, z), 65)))
    for z in (66, 67):
        b.put(0, -15, z, "metal", bone, "strap", BUCKLE)
    # Bandoulière en escalier sur la poitrine : 3 cubes de large, en saillie
    # d'un cube devant la tunique.
    for z in range(48, 72):
        xc = round(13 - (71 - z) * 24.0 / 23.0)
        for x in range(xc - 1, xc + 2):
            f = b.front(x, z)
            if f is None or x < -14 or x > 15:
                continue
            bone_c = b.get(x, f, z).bone
            if bone_c not in ("chest", "spine"):
                continue
            b.put(x, f + 1, z, "leather", bone_c, "strap_front",
                  vx.tone(LEATHER, 0.88 + 0.12 * vx.noise((x // 2, 0, z // 2), 66)))
    # Boucle d'acier au milieu de la bandoulière.
    for z in (59, 60, 61):
        xc = round(13 - (71 - z) * 24.0 / 23.0)
        for x in (xc - 1, xc, xc + 1):
            f = b.front(x, z)
            if f is not None:
                b.face(x, f, z, "-y", BUCKLE if z != 60 or x == xc else STEEL_DARK, "metal")


# ---------------------------------------------------------------------------
# Ossature (RigBuilder.BONES) en cubes de 2,5 cm. Repère du modèle : y = -f - 1.
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, 0, 42), (0, 0, 46)),
    ("spine", "hips", (0, 0, 46), (0, 0, 57)),
    ("chest", "spine", (0, 0, 57), (0, 0, 72)),
    ("neck", "chest", (0, -1, 72), (0, -1, 78)),
    ("head", "neck", (0, -1, 78), (0, -1, 90)),
    ("arm_l", "chest", (20.5, -0.5, 69), (20.5, -0.5, 52)),
    ("forearm_l", "arm_l", (20.5, -0.5, 52), (20.5, -0.5, 30)),
    ("arm_r", "chest", (-20.5, -0.5, 69), (-20.5, -0.5, 52)),
    ("forearm_r", "arm_r", (-20.5, -0.5, 52), (-20.5, -0.5, 30)),
    ("thigh_l", "hips", (6.5, -0.5, 40), (6.5, -0.5, 20)),
    ("shin_l", "thigh_l", (6.5, -0.5, 20), (6.5, -0.5, 1)),
    ("thigh_r", "hips", (-6.5, -0.5, 40), (-6.5, -0.5, 20)),
    ("shin_r", "thigh_r", (-6.5, -0.5, 20), (-6.5, -0.5, 1)),
    ("jaw", "head", (0, -1, 78), (0, -11, 78)),
]


def describe():
    b = Body()
    build_legs(b)
    build_torso(b)
    build_arms(b)
    build_head(b)
    build_stretcher(b)
    m = b.m
    for k in [k for k in m.face_color if k[:3] not in m.vox]:
        del m.face_color[k]
    for k in [k for k in m.face_mat if k[:3] not in m.vox]:
        del m.face_mat[k]
    vx.shade(m, {"+z": 1.06, "-z": 0.64, "+x": 0.88, "-x": 0.88, "-y": 1.0, "+y": 0.93}, skip_mats=("eye",))
    vx.quantize(m, {"cloth": 24, "skin": 16, "leather": 8, "metal": 6})
    return m


def build(use_cache=False):
    info = {}
    if use_cache and os.path.exists(CACHE):
        m = vx.load_cache(CACHE)
        info["from_cache"] = True
    else:
        m = describe()
        vx.save_cache(m, CACHE)
    ob, mi = vx.build_mesh(m, "brancardier_voxel")
    info.update(mi)
    rig = vx.build_armature("brancardier_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    info["z_range"] = (int(lo[2]), int(hi[2]))
    return m, ob, rig, info


# ---------------------------------------------------------------------------
# Planche de validation : vues, poses (marche lourde, préparation de charge,
# charge, étourdi, coup, mort) et gros plans.
# ---------------------------------------------------------------------------

def pose(rig, rots):
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for name, axis, deg in rots:
        pb = rig.pose.bones[name]
        bpy.context.view_layer.update()
        mw = pb.matrix.copy()
        loc = mw.translation.copy()
        r = Matrix.Rotation(math.radians(deg), 4, axis) @ mw
        r.translation = loc
        pb.matrix = r
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")


def rest_pose(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


# Repère Blender : avant -Y ; rotation +X d'un membre pendant = vers l'avant.
WINDUP = [("spine", "X", 18), ("chest", "X", 10), ("neck", "X", -20), ("head", "X", -8), ("jaw", "X", 30),
          ("arm_l", "X", -40), ("arm_r", "X", -40), ("arm_l", "Y", 30), ("arm_r", "Y", -30),
          ("forearm_l", "X", 60), ("forearm_r", "X", 60), ("thigh_r", "X", 35), ("shin_r", "X", -40)]
CHARGE = [("spine", "X", 28), ("chest", "X", 12), ("neck", "X", -25), ("head", "X", -12),
          ("arm_l", "X", 40), ("arm_r", "X", 55), ("forearm_l", "X", 50), ("forearm_r", "X", 40),
          ("thigh_l", "X", 50), ("shin_l", "X", -60), ("thigh_r", "X", -30), ("shin_r", "X", -20)]
STUN = [("spine", "X", -8), ("neck", "X", 25), ("head", "Z", 18), ("jaw", "X", 25),
        ("arm_l", "X", -15), ("arm_l", "Y", 25), ("arm_r", "X", -10), ("arm_r", "Y", -20),
        ("thigh_l", "X", 10), ("shin_l", "X", -15)]
SMASH = [("spine", "X", 10), ("arm_l", "X", 150), ("arm_r", "X", 150), ("forearm_l", "X", 30),
         ("forearm_r", "X", 30), ("jaw", "X", 25)]


def render_sheet(m, ob, rig, path):
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    vx.add_outline(m, "brancardier_voxel_outline", rig)
    TW, TH = 380, 560
    vx.setup_render((TW, TH))
    hm, tz = 2.7, 1.2

    def shot(name, az, el, target=(0, 0, tz), h=hm):
        return vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, target, h, el))

    row1 = [shot("front", 0, 0), shot("back", 180, 0), shot("left", 90, 0), shot("right", -90, 0),
            shot("34", 35, 10), shot("back34", 145, 10)]
    row2 = [shot("head", 20, 6, (0, -0.1, 2.05), 0.7), shot("face", 0, 0, (0, -0.1, 2.05), 0.55),
            shot("wrist_l", 60, 10, (0.5, 0, 0.85), 0.6), shot("wrist_r", -60, 10, (-0.5, 0, 0.85), 0.6)]
    pose(rig, WINDUP)
    row2.append(shot("windup", 60, 6))
    rest_pose(rig)
    pose(rig, CHARGE)
    row2.append(shot("charge", 90, 0))
    rest_pose(rig)
    pose(rig, STUN)
    row3 = [shot("stun", 25, 8)]
    rest_pose(rig)
    pose(rig, SMASH)
    row3.append(shot("smash", 70, 6, (0, 0, 1.4), 3.2))
    rest_pose(rig)
    row3.append(shot("top", 0, 70, (0, 0, 1.2), 2.4))
    vx.save_png(vx.sheet([row1, row2, row3], TW, TH), path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "brancardier", "brancardier_voxel.glb")
    sheet = None
    use_cache = "--cache" in args
    i = 0
    while i < len(args):
        if args[i] == "--glb":
            glb = args[i + 1]
            i += 1
        elif args[i] == "--sheet":
            sheet = args[i + 1]
            i += 1
        i += 1
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m, ob, rig, info = build(use_cache)
    vx.export_glb(os.path.abspath(glb), [ob, rig], CUBE)
    print("[brancardier_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(m, ob, rig, os.path.abspath(sheet))
        print("[brancardier_voxel] planche -> %s" % sheet)
