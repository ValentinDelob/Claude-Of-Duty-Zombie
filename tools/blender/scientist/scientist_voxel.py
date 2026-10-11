# LE SCIENTIFIQUE CUBIQUE (GAME_CONCEPT.md § 3 : le virologue qui cherche le
# vaccin et l'antidote et paie les joueurs pour des échantillons ; § 4.19 :
# personnages en cubes de 2,5 cm). PROVISOIRE (à valider).
#
# Silhouette : grand et maigre (1,84 m au sommet du crâne, ~1,95 m avec la
# tignasse), épaules étroites, jambes fines dans des bottes de caoutchouc ;
# longue BLOUSE blanc cassé jusqu'aux genoux (ouverte, ourlet roussi et
# déchiré en marches, taches de produits jaune-vert, quelques gouttes de
# sang), TABLIER de caoutchouc moutarde dessous (couleur des bandes de
# danger), GANTS de caoutchouc noirs à revers, BOTTES vert sombre à bande
# jaune ; MASQUE À GAZ pendu au cou (deux hublots, cartouche filtrante
# olive) ; tête longue et creusée, nez crochu, sourire de travers, cernes
# violets, tignasse grise ÉBOURIFFÉE sur les côtés et l'arrière (front
# dégarni) ; bandeau de cuir et LOUPE d'horloger en laiton sur l'œil
# GAUCHE (montre un œil énorme), œil droit écarquillé ; stylos dans la
# poche de poitrine, badge de QUARANTAINE au revers, brassard rayé de
# danger ; dans le poing droit, la FIOLE d'antidote expérimental (liquide
# sarcelle lumineux, matière « glow »).
#
#   sh tools/blender.sh tools/blender/scientist/scientist_voxel.py [--glb FICHIER]
#
# Repère : Z en haut, avant vers -Y, gauche du personnage vers +X. Comme les
# autres personnages, « f » est la profondeur vers l'AVANT : la cellule
# (x, f, z) est la cellule (x, y = -f - 1, z) du modèle.
import bpy, math, os, sys
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_CHAR

# ---------------------------------------------------------------------------
# Palette (sRGB), accordée à DECOR_PALETTE (paint_white, hazard_yellow,
# brass, paint_olive) et à l'interface (blanc os, jaune danger, menthe).
# ---------------------------------------------------------------------------
COAT = (0.84, 0.84, 0.79)
COAT_SHADE = (0.75, 0.75, 0.70)
COAT_SEAM = (0.70, 0.70, 0.65)
STAIN_CHEM = (0.72, 0.74, 0.40)
STAIN_OLD = (0.62, 0.57, 0.40)
SCORCH = (0.22, 0.18, 0.14)
SCORCH_EDGE = (0.48, 0.40, 0.30)
BLOOD = (0.50, 0.07, 0.06)
BLOOD_DRY = (0.34, 0.08, 0.06)
APRON = (0.78, 0.60, 0.14)
APRON_DARK = (0.60, 0.45, 0.10)
APRON_SPLASH = (0.30, 0.62, 0.52)
SHIRT = (0.52, 0.60, 0.66)
SHIRT_DARK = (0.40, 0.46, 0.52)
PANTS = (0.20, 0.21, 0.24)
PANTS_DARK = (0.14, 0.15, 0.17)
BOOT = (0.17, 0.24, 0.18)
BOOT_DARK = (0.10, 0.14, 0.11)
BOOT_BAND = (0.86, 0.68, 0.14)
GLOVE = (0.10, 0.11, 0.11)
GLOVE_HI = (0.18, 0.19, 0.20)
SKIN = (0.84, 0.64, 0.52)
SKIN_SHADE = (0.72, 0.53, 0.45)
SKIN_HOLLOW = (0.62, 0.45, 0.42)
EYEBAG = (0.66, 0.48, 0.50)
STUBBLE = (0.74, 0.64, 0.58)
LIP = (0.54, 0.32, 0.30)
MOUTH = (0.16, 0.06, 0.06)
TOOTH = (0.92, 0.88, 0.74)
EYE_WHITE = (0.95, 0.94, 0.90)
IRIS = (0.16, 0.50, 0.34)
PUPIL = (0.06, 0.06, 0.07)
HAIR = (0.84, 0.85, 0.86)
HAIR_DARK = (0.60, 0.61, 0.64)
HAIR_TIP = (0.95, 0.95, 0.96)
BROW = (0.46, 0.46, 0.50)
WIRE = (0.18, 0.18, 0.20)
BRASS = (0.70, 0.52, 0.22)
BRASS_DARK = (0.46, 0.33, 0.13)
LENS = (0.62, 0.80, 0.84)
MASK = (0.17, 0.19, 0.17)
MASK_HI = (0.26, 0.28, 0.26)
MASK_GLASS = (0.22, 0.42, 0.44)
FILTER = (0.38, 0.42, 0.31)
FILTER_DARK = (0.26, 0.29, 0.21)
STEEL = (0.62, 0.64, 0.66)
LEATHER = (0.30, 0.20, 0.13)
GLOW = (0.32, 1.0, 0.80)
GLOW_CORE = (0.70, 1.0, 0.92)
GLOW_DARK = (0.10, 0.60, 0.48)
GLASS = (0.72, 0.88, 0.90)
STOPPER = (0.55, 0.12, 0.10)
PAPER = (0.92, 0.90, 0.82)
RED = (0.78, 0.12, 0.10)
BLUE = (0.16, 0.28, 0.62)
BLACK = (0.06, 0.06, 0.07)
HAZARD = (0.90, 0.72, 0.12)


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
        bfn = bone if callable(bone) else (lambda z, _b=bone: _b)
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
                    self.put(x, f, z, mat, bfn(z), part, colfn(x, f, z))

    def face(self, x, f, z, d, color, mat=None):
        c = cell(x, f, z)
        if c not in self.m.vox:
            return False
        self.m.face_color[(c[0], c[1], c[2], d)] = color
        if mat:
            self.m.face_mat[(c[0], c[1], c[2], d)] = mat
        return True

    def front(self, x, z, parts=None):
        best = None
        for f in range(20, -20, -1):
            v = self.get(x, f, z)
            if v is not None and (parts is None or v.part in parts):
                return f
        return best

    def paint_front(self, x, z, color, mat=None, parts=None):
        f = self.front(x, z, parts)
        if f is not None:
            self.face(x, f, z, "-y", color, mat)
        return f


def blocks(base, seed, size=3, amp=0.10):
    def fn(x, f, z):
        return vx.tone(base, 1.0 - amp / 2 + amp * vx.noise((x // size, f // size, z // size), seed))
    return fn


def solid(color):
    return lambda x, f, z: color


def torso_bone(z):
    return "hips" if z < 40 else ("spine" if z < 48 else "chest")


# ---------------------------------------------------------------------------
# Jambes : bottes (z 0..14), pantalon fin (z 14..38).
# ---------------------------------------------------------------------------

def build_legs(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):
            return (a, c) if s > 0 else (-c, -a)
        shin, thigh = "shin_" + side, "thigh_" + side
        x0, x1 = X(1, 6)
        # Semelle, pied (bout rond vers l'avant), tige de botte.
        b.slab(x0, x1, -3, 6, 0, 1, "rubber", shin, "boot", solid(BOOT_DARK), round_xy=2)
        b.slab(x0, x1, -3, 6, 1, 4, "rubber", shin, "boot", blocks(BOOT, 11 + s, 2, 0.12), round_xy=2, round_top=1)
        b.slab(x0, x1, -3, 3, 4, 13, "rubber", shin, "boot", blocks(BOOT, 13 + s, 2, 0.12), round_xy=1)
        # Revers à bande jaune (z 12..14), un cube plus large.
        xa, xb = X(0, 7)
        b.slab(xa, xb, -4, 4, 12, 14, "rubber", shin, "boot",
               lambda x, f, z: BOOT_BAND if z == 13 else vx.tone(BOOT_BAND, 0.82), round_xy=2)
        # Pantalon.
        xa, xb = X(1, 5)
        b.slab(xa, xb, -2, 2, 14, 38, "cloth", lambda z: thigh if z >= 21 else shin, "pants",
               blocks(PANTS, 17 + s, 3, 0.12), round_xy=0)
        # Pli du genou.
        for x in range(xa, xb):
            b.face(x, 1, 21, "-y", PANTS_DARK)


# ---------------------------------------------------------------------------
# Torse : chemise, ceinture, tablier de caoutchouc, blouse ouverte.
# ---------------------------------------------------------------------------

def coat_col(x, f, z):
    n = vx.noise((x // 2, f // 2, z // 2), 41)
    c = vx.tone(COAT, 0.95 + 0.07 * vx.noise((x // 3, f // 3, z // 4), 40))
    if n > 0.965:
        c = mix(c, STAIN_CHEM, 0.75)
    elif n < 0.0:
        c = mix(c, STAIN_OLD, 0.35)
    if z < 25:  # bas de la blouse sali
        c = mix(c, STAIN_OLD, 0.15 * (25 - z) / 5.0)
    return c


def build_torso(b):
    # Bassin et ceinture.
    b.slab(-5, 5, -3, 3, 36, 40, "cloth", "hips", "pants", blocks(PANTS, 21), round_xy=1)
    b.slab(-6, 6, -3, 3, 38, 40, "leather", "hips", "belt", solid(LEATHER), round_xy=1)
    # Chemise (torse étroit, poitrine creuse).
    b.slab(-6, 6, -3, 3, 40, 55, "cloth", torso_bone, "shirt", blocks(SHIRT, 23), round_xy=1)
    b.slab(-7, 7, -3, 3, 50, 55, "cloth", "chest", "shirt", blocks(SHIRT, 24), round_xy=2)
    b.slab(-6, 6, -3, 3, 55, 57, "cloth", "chest", "shirt", blocks(SHIRT, 25), round_xy=2)
    # Col de chemise.
    for x in range(-3, 3):
        b.put(x, 2, 57, "cloth", "chest", "shirt", SHIRT_DARK if x in (-1, 0) else SHIRT)
    # Blouse : coque d'un cube autour du torse, z 20..57, devant ouvert.
    for z in range(20, 58):
        if z >= 40:
            x0, x1, f0, f1 = -7, 7, -4, 4
            if z >= 50:
                x0, x1 = -8, 8
        elif z >= 28:
            x0, x1, f0, f1 = -8, 8, -5, 4
        else:
            x0, x1, f0, f1 = -9, 9, -6, 4
        for x in range(x0, x1):
            for f in range(f0, f1):
                edge = x in (x0, x1 - 1) or f in (f0, f1 - 1)
                if not edge:
                    if b.get(x, f, z) is None:
                        b.put(x, f, z, "cloth", torso_bone(z), "lining", (0.50, 0.50, 0.47))
                    continue
                if (x in (x0, x1 - 1)) and (f in (f0, f1 - 1)) and z < 55:
                    continue  # coins arrondis
                if f == f1 - 1 and -4 <= x < 4:
                    continue  # devant ouvert
                if z >= 55 and (x in (x0, x1 - 1)) and (f in (f0, f1 - 1)):
                    continue
                b.put(x, f, z, "cloth", torso_bone(z), "coat", coat_col(x, f, z))
    # Épaules : dessus de la blouse (z 57) en marche.
    for x in range(-7, 7):
        for f in range(-4, 3):
            if abs(x) <= 2 and f >= -2:
                continue
            b.put(x, f, 57, "cloth", "chest", "coat", coat_col(x, f, 57))
    # Ourlet déchiré et roussi : marches irrégulières, bord brûlé.
    for x in range(-9, 9):
        for f in range(-6, 4):
            v = b.get(x, f, 20)
            if v is None or v.part not in ("coat", "lining"):
                continue
            cut = int(2.4 * vx.noise((x // 2, f // 2, 0), 77))
            for k in range(cut):
                b.drop(x, f, 20 + k)
            top = 20 + cut
            if b.get(x, f, top) is not None and b.get(x, f, top).part == "coat":
                v2 = b.get(x, f, top)
                v2.color = SCORCH if vx.noise((x, f, 1), 78) > 0.75 else mix(SCORCH_EDGE, COAT, 0.45)
            if b.get(x, f, top + 1) is not None and b.get(x, f, top + 1).part == "coat" and vx.noise((x, f, 2), 79) > 0.8:
                b.get(x, f, top + 1).color = mix(SCORCH_EDGE, COAT, 0.4)
    # Brûlure plus large sur le pan droit.
    for x, z in ((-8, 23), (-7, 23), (-7, 22)):
        v = b.get(x, 3, z)
        if v is not None:
            v.color = SCORCH
    # Taches voulues : grande éclaboussure jaune-vert sur le pan gauche,
    # coulures de sang sous la poche.
    for x, z in ((4, 28), (5, 28), (5, 29), (6, 29), (4, 30), (5, 30), (6, 30), (7, 31), (5, 31), (6, 27), (4, 26)):
        v = b.get(x, 3, z)
        if v is not None and v.part == "coat":
            v.color = STAIN_CHEM if (x + z) % 3 else mix(STAIN_CHEM, (0.55, 0.62, 0.20), 0.5)
    for x, z in ((5, 41), (5, 40), (5, 39), (6, 40), (5, 37), (4, 41)):
        v = b.get(x, 3, z)
        if v is not None and v.part == "coat":
            v.color = BLOOD if z > 38 else BLOOD_DRY
    # Revers (z 48..57) : col en V, un cube en avant, liseré.
    for z in range(48, 58):
        inner = 4 + (z - 48) // 3
        for s in (1, -1):
            for k in range(2):
                x = inner + k if s > 0 else -inner - 1 - k
                col = COAT_SHADE if k == 0 else COAT
                b.put(x, 4, z, "cloth", "chest", "lapel", col)
    # Col montant derrière le cou.
    for x in range(-5, 5):
        for z in (58, 59):
            b.put(x, -4, z, "cloth", "chest", "coat", COAT if z == 58 else COAT_SHADE)
    for s in (1, -1):
        for f in range(-4, 1):
            x = 4 if s > 0 else -5
            b.put(x, f, 58, "cloth", "chest", "coat", COAT)
    # Couture du dos, fente arrière.
    for z in range(22, 52):
        b.face(0, -5 if z < 40 else -4, z, "+y", COAT_SEAM)
    # Tablier de caoutchouc (f = 3), bavette, plis verticaux, éclaboussures.
    for z in range(23, 55):
        xs = range(-5, 5) if z < 46 else range(-3, 3)
        for x in xs:
            col = APRON
            if x in (-3, 2) and z < 46:
                col = APRON_DARK
            n = vx.noise((x // 2, 3, z // 2), 55)
            if n > 0.95:
                col = mix(APRON, APRON_SPLASH, 0.8)
            elif n < 0.04:
                col = mix(APRON, BLOOD_DRY, 0.6)
            b.put(x, 3, z, "rubber", torso_bone(z), "apron", vx.tone(col, 0.96 + 0.06 * vx.noise((x, 0, z // 3), 56)))
    for x in range(-5, 5):  # ourlet du tablier
        b.face(x, 3, 23, "-y", APRON_DARK)
    # Bretelles du tablier autour du cou.
    for z in range(55, 58):
        for x in (-3, 2):
            b.put(x, 3, z, "rubber", "chest", "apron", APRON_DARK)
    for f in range(-2, 3):
        for x in (-3, 2):
            b.put(x, f, 58, "rubber", "chest", "apron", APRON_DARK)
    # Poche de poitrine gauche et stylos (rouge, bleu, thermomètre).
    for x in range(4, 7):
        for z in range(42, 47):
            b.put(x, 4, z, "cloth", "spine" if z < 48 else "chest", "pocket", COAT_SHADE if z == 46 else coat_col(x, 4, z))
    for x, col, top in ((4, RED, 49), (5, BLUE, 48), (6, PAPER, 50)):
        for z in range(46, top):
            c = col if z >= top - 1 else (BLACK if col != PAPER else STEEL)
            b.put(x, 5, z, "metal" if col == PAPER else "cloth", "chest" if z >= 48 else "spine", "pens", c)
    b.put(6, 5, 49, "cloth", "chest", "pens", RED)  # bout du thermomètre
    # Badge de quarantaine au revers droit : carte, bande rouge, photo,
    # code-barres, pince d'acier.
    for x in range(-7, -3):
        for z in range(42, 48):
            col = PAPER
            if z == 47:
                col = RED
            elif z in (45, 46) and x in (-7, -6):
                col = HAIR if z == 46 else SKIN
            elif z == 42:
                col = BLACK if x % 2 == 0 else PAPER
            elif z == 44 and x in (-5, -4):
                col = HAZARD
            b.put(x, 5, z, "cloth", "spine", "badge", col)
    b.put(-6, 5, 48, "metal", "chest", "badge", STEEL)
    b.put(-5, 5, 48, "metal", "chest", "badge", STEEL)
    # Seringue dans la poche basse droite de la blouse.
    for x in range(-8, -4):
        for z in range(28, 33):
            b.put(x, 4, z, "cloth", "hips", "pocket", COAT_SHADE if z == 32 else coat_col(x, 4, z))
    for z in range(32, 37):
        b.put(-6, 5, z, "glass", "hips" if z < 40 else "spine", "syringe", GLASS if z < 35 else (STEEL if z < 36 else RED))
    b.put(-6, 5, 37, "metal", "hips", "syringe", STEEL)
    # Ceinture visible sur les côtés, tubes à essai sur la hanche gauche.
    for z in range(30, 36):
        for f in (-2, -1, 0, 1):
            pass
    for i, col in enumerate((GLOW, (0.95, 0.45, 0.15), (0.62, 0.30, 0.80))):
        f = -2 + 2 * i
        for z in range(31, 36):
            mat = "glow" if z < 34 else "glass"
            b.put(9, f, z, mat, "hips", "tubes", col if z < 34 else GLASS)
        b.put(9, f, 36, "rubber", "hips", "tubes", BLACK)
    for f in range(-3, 4):
        b.put(9, f, 32, "leather", "hips", "tubes", LEATHER)


# ---------------------------------------------------------------------------
# Gaz : masque pendu au cou.
# ---------------------------------------------------------------------------

def build_mask(b):
    # Masque pendu un peu de travers sous le menton (côté gauche plus bas).
    for x in range(-3, 3):
        for z in range(50, 56):
            for f in range(4, 6):
                ex = min(x + 3, 2 - x)
                ez = min(z - 50, 55 - z)
                if ex == 0 and ez == 0:
                    continue
                if f == 5 and (ex == 0 or ez == 0):
                    continue
                b.put(x, f, z, "rubber", "chest", "mask", MASK if (x + z) % 3 else MASK_HI)
    # Hublots 2 × 2 (verre sarcelle sombre) en saillie.
    for x0 in (-3, 1):
        for x in range(x0, x0 + 2):
            for z in (53, 54):
                b.put(x, 6, z, "glass", "chest", "mask", MASK_GLASS)
    for x in (-3, -2, 1, 2):
        b.put(x, 6, 55, "metal", "chest", "mask", STEEL)
    # Cartouche filtrante olive sous la bouche.
    for x in (-1, 0):
        for z in (50, 51, 52):
            for f in (6, 7):
                col = FILTER if z != 51 else FILTER_DARK
                b.put(x, f, z, "metal", "chest", "mask", col)
        b.face(x, 7, 51, "-y", BLACK)
    # Sangles autour du cou.
    for s in (1, -1):
        x = 3 if s > 0 else -4
        for f in range(-1, 5):
            b.put(x, f, 56, "rubber", "chest", "mask", MASK)


# ---------------------------------------------------------------------------
# Bras : manches de blouse, brassard rayé, gants de caoutchouc, fiole.
# ---------------------------------------------------------------------------

def build_arms(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):
            return (a, c) if s > 0 else (-c, -a)
        arm, fore = "arm_" + side, "forearm_" + side
        x0, x1 = X(7, 12)
        b.slab(x0, x1, -3, 2, 44, 57, "cloth", arm, "sleeve", coat_col, round_xy=1, round_top=1)
        b.slab(x0, x1, -3, 2, 37, 44, "cloth", fore, "sleeve", coat_col, round_xy=1)
        # Manche retroussée (bord replié).
        b.slab(x0, x1, -3, 2, 37, 39, "cloth", fore, "sleeve", solid(COAT_SHADE), round_xy=0)
        # Gant : revers évasé, avant-bras, main.
        xa, xb = X(8, 11)
        b.slab(xa, xb, -2, 1, 31, 37, "rubber", fore, "glove", blocks(GLOVE, 61 + s, 2, 0.3), round_xy=0)
        b.slab(*X(7, 12), -3, 2, 35, 37, "rubber", fore, "glove", solid(GLOVE_HI), round_xy=1)
        b.slab(*X(7, 12), -3, 3, 26, 31, "rubber", fore, "glove", blocks(GLOVE, 63 + s, 2, 0.3), round_xy=1)
        # Pouce (vers l'avant) et jointures.
        tx = 8 if s > 0 else -9
        for z in (28, 29):
            b.put(tx, 3, z, "rubber", fore, "glove", GLOVE_HI)
        for xx in range(*X(8, 11)):
            b.face(xx, 2, 27, "-y", GLOVE_HI)
    # Brassard de danger sur le bras gauche (rayures jaunes et noires).
    for z in range(49, 53):
        for x in range(6, 13):
            for f in range(-4, 3):
                if not (x in (6, 12) or f in (-4, 2)):
                    continue
                if (x in (6, 12)) and (f in (-4, 2)):
                    continue
                col = HAZARD if ((x + f + z) // 2) % 2 == 0 else BLACK
                b.put(x, f, z, "cloth", "arm_l", "band", col)
    # Fiole d'antidote dans le poing droit : 3 × 3 cubes, prolonge l'avant-
    # bras (au repos vers le bas, levée vers le haut dans la pose du héros).
    x0, x1, f0, f1 = -11, -8, -1, 2
    for z in range(12, 27):
        for x in range(x0, x1):
            for f in range(f0, f1):
                corner = x in (x0, x1 - 1) and f in (f0, f1 - 1)
                edge = x in (x0, x1 - 1) or f in (f0, f1 - 1)
                if z >= 25:  # fond de verre dans le poing
                    if not b.get(x, f, z):
                        b.put(x, f, z, "glass", "forearm_r", "vial", GLASS)
                elif z >= 16:  # liquide lumineux (coins plus sombres)
                    col = GLOW_DARK if corner else GLOW
                    if (x, f) == (-10, 0) or (z == 16 and not corner):
                        col = GLOW_CORE
                    b.put(x, f, z, "glow", "forearm_r", "vial", col)
                elif z == 15:  # col de verre
                    if not corner:
                        b.put(x, f, z, "glass", "forearm_r", "vial", GLASS)
                elif z >= 13:  # bouchon de caoutchouc
                    if not corner:
                        b.put(x, f, z, "rubber", "forearm_r", "vial", STOPPER)
                elif not edge:
                    b.put(x, f, z, "rubber", "forearm_r", "vial", vx.tone(STOPPER, 0.8))
    # Étiquette de papier sur le devant, croix rouge.
    for x in range(x0, x1):
        for z in (19, 20, 21):
            col = RED if (x == -10 and z == 20) or (x == -10 and z in (19, 21) and False) else PAPER
            b.face(x, f1 - 1, z, "-y", col, "cloth")
    b.face(-10, f1 - 1, 19, "-y", RED, "cloth")
    b.face(-10, f1 - 1, 21, "-y", RED, "cloth")
    b.face(-11, f1 - 1, 20, "-y", RED, "cloth")
    b.face(-9, f1 - 1, 20, "-y", RED, "cloth")


# ---------------------------------------------------------------------------
# Tête : longue, creusée, nez crochu, lunettes et loupe, tignasse.
# ---------------------------------------------------------------------------

HEAD_SHAPE = {  # z : (demi-largeur, f arrière, f avant) ; visage long
    58: (3, -3, 4), 59: (4, -4, 5), 60: (5, -5, 5),
    72: (5, -5, 4), 73: (4, -4, 3),
}


def head_cells(z):
    hw, fb, ff = HEAD_SHAPE.get(z, (6, -6, 5))
    out = []
    for x in range(-hw, hw):
        for f in range(fb, ff):
            ex = min(x + hw, hw - 1 - x)
            ef = min(f - fb, ff - 1 - f)
            if ex + ef < (2 if z in (58, 73) else 1):
                continue
            out.append((x, f))
    return out


class Mirror:
    """Vue en miroir (x -> -1 - x) d'un Body pour les traits du visage."""
    SW = {"+x": "-x", "-x": "+x"}

    def __init__(self, b):
        self.b = b

    def put(self, x, *a):
        self.b.put(-1 - x, *a)

    def paint_front(self, x, *a, **k):
        return self.b.paint_front(-1 - x, *a, **k)

    def face(self, x, f, z, d, *a):
        return self.b.face(-1 - x, f, z, self.SW.get(d, d), *a)


def build_head(b):
    b.slab(-2, 2, -2, 2, 57, 58, "skin", "neck", "neck", solid(SKIN_SHADE), round_xy=0)
    for z in range(58, 74):
        for x, f in head_cells(z):
            col = vx.tone(SKIN, 0.985 + 0.03 * vx.noise((x // 2, f // 2, z // 2), 71))
            if z <= 60 and vx.noise((x, f, z), 72) > 2.0:
                col = STUBBLE
            b.put(x, f, z, "skin", "head", "head", col)
    # Joues creuses sous des pommettes saillantes.
    for s in (1, -1):
        for z in (60, 61, 62):
            for x in ((3, 4) if s > 0 else (-4, -5)):
                b.paint_front(x, z, SKIN_HOLLOW, parts=("head",))
            for f in range(0, 4):
                b.face(5 if s > 0 else -6, f, z, "+x" if s > 0 else "-x", SKIN_HOLLOW)
        for x in ((3, 4) if s > 0 else (-5, -4)):
            b.paint_front(x, 63, vx.tone(SKIN, 1.05), parts=("head",))
    # Menton pointu en avant.
    for x in (-1, 0):
        b.paint_front(x, 58, SKIN_SHADE, parts=("head",))
    # Oreilles décollées.
    for x in (6, -7):
        for z in (63, 64, 65, 66):
            for f in (-1, 0):
                b.put(x, f, z, "skin", "head", "ear", SKIN_SHADE if z == 63 else SKIN)
        b.put(7 if x > 0 else -8, -1, 65, "skin", "head", "ear", SKIN_SHADE)
    # Nez long et crochu : arête f 5 (z 62..67), bout f 6, crochet f 7.
    for z in range(62, 68):
        for x in (-1, 0):
            b.put(x, 5, z, "skin", "head", "nose", SKIN)
    for x in (-1, 0):
        for z in (62, 63, 64, 65):
            b.put(x, 6, z, "skin", "head", "nose", SKIN if z > 62 else SKIN_SHADE)
        b.put(x, 7, 63, "skin", "head", "nose", vx.tone(SKIN, 1.04))
        b.put(x, 7, 62, "skin", "head", "nose", SKIN_SHADE)
        b.face(x, 7, 62, "-z", MOUTH)
        b.face(x, 6, 62, "-z", MOUTH)
    # Bouche : rictus de travers, ouverte (dents du haut, fond sombre), coin
    # gauche relevé, une dent manquante.
    mb = Mirror(b)  # traits du visage en miroir : loupe sur l'œil GAUCHE,
    # œil ouvert et rictus côté droit (tourné vers la fiole et la caméra).
    for x in range(-3, 4):
        mb.paint_front(x, 61, TOOTH if -2 <= x <= 2 else MOUTH, "bone", parts=("head",))
    mb.paint_front(1, 61, MOUTH, "wound", parts=("head",))
    for x in range(-2, 4):
        mb.paint_front(x, 60, MOUTH, "wound", parts=("head",))
    mb.paint_front(4, 62, MOUTH, "wound", parts=("head",))
    mb.paint_front(4, 61, MOUTH, "wound", parts=("head",))
    mb.paint_front(-3, 60, LIP, parts=("head",))
    for x in range(-2, 4):
        mb.paint_front(x, 59, LIP, parts=("head",))
    for x in range(-2, 4):
        mb.paint_front(x, 62, SKIN_SHADE, parts=("head",))
    # Œil gauche grand ouvert (3 × 2), regard en coin vers la fiole (-X),
    # cerne violet, sourcil haussé en accent circonflexe.
    for x in (1, 2, 3):
        for z in (65, 66):
            col = EYE_WHITE
            if x == 3:
                col = PUPIL if z == 65 else IRIS
            mb.paint_front(x, z, col, "bone", parts=("head",))
        mb.paint_front(x, 64, EYEBAG, parts=("head",))
        mb.paint_front(x, 67, (0.20, 0.12, 0.10), "wound", parts=("head",))  # trait de paupière
    for x, z in ((0, 67), (1, 68), (2, 69), (3, 69), (4, 68)):
        mb.put(x, 5, z, "fabric", "head", "brow", BROW)
    mb.put(5, 5, 67, "fabric", "head", "brow", BROW)
    # Rides du front.
    for x in range(-3, 5):
        mb.paint_front(x, 71, SKIN_SHADE, parts=("head",))
    # Loupe d'horloger en laiton sur l'œil droit : tube 5 × 5 (coins coupés),
    # lèvre en avant, lentille en retrait qui montre un ŒIL ÉNORME.
    lx0, lx1, lz0, lz1 = -6, -1, 63, 68
    for x in range(lx0, lx1):
        for z in range(lz0, lz1):
            ex = min(x - lx0, lx1 - 1 - x)
            ez = min(z - lz0, lz1 - 1 - z)
            if ex == 0 and ez == 0:
                continue
            rim = ex == 0 or ez == 0
            for f in range(5, 8 if rim else 6):
                col = BRASS if (f + x + z) % 3 else BRASS_DARK
                if f == 7:
                    col = vx.tone(BRASS, 1.18)
                mb.put(x, f, z, "metal", "head", "loupe", col)
            if not rim:
                k = (x - lx0, z - lz0)
                col = EYE_WHITE
                if k == (2, 2):
                    col = PUPIL
                elif k in ((1, 2), (3, 2), (2, 1), (2, 3)):
                    col = IRIS
                elif k == (1, 3):
                    col = (1.0, 1.0, 1.0)
                mb.face(x, 5, z, "-y", col, "glass")
    # Sourcil droit froncé, très bas, sur la loupe.
    for x, z in ((-6, 69), (-5, 69), (-4, 68), (-3, 68), (-2, 68)):
        mb.put(x, 5, z, "fabric", "head", "brow", BROW)
    # Molette de la loupe.
    mb.put(-7, 6, 65, "metal", "head", "loupe", BRASS_DARK)
    mb.put(-7, 7, 65, "metal", "head", "loupe", BRASS)
    # Tignasse grise ébouriffée : masses en blocs de 2 cubes sur les côtés et
    # l'arrière, gonflées vers le haut ; front et sommet dégarnis.
    build_hair(b)
    # Bandeau de cuir de la loupe sur le front (z 70), caché par la tignasse
    # sur les côtés ; bras de laiton jusqu'à la loupe.
    for x, fz in head_cells(70):
        v = b.get(x, fz, 70)
        if v is not None and v.part == "head" and (b.get(x, fz + 1, 70) is None or abs(x) >= 5):
            b.put(x, fz, 70, "leather", "head", "strap", LEATHER if (x % 3) else vx.tone(LEATHER, 0.8))
    for z in (68, 69, 70):
        mb.put(-6, 5, z, "metal", "head", "loupe", BRASS_DARK)
    mb.put(-6, 5, 70, "metal", "head", "loupe", BRASS)

def hair_col(x, f, z):
    n = vx.noise((x // 2, f // 2, z // 2), 83)
    m = vx.noise((x, f, z), 84)
    if m > 0.85:
        return HAIR_TIP
    if n < 0.3:
        return HAIR_DARK if m < 0.5 else HAIR
    return HAIR


def build_hair(b):
    def hput(x, f, z):
        v = b.get(x, f, z)
        if v is not None and v.part not in ("head", "hair"):
            return
        b.put(x, f, z, "fabric", "head", "hair", hair_col(x, f, z))
    # Couche collée au crâne (arrière, côtés au-dessus des oreilles).
    for z in range(63, 74):
        for x, f in head_cells(z):
            back = f <= -3
            side = (x >= 4 or x <= -5) and f <= 0 and z >= 67
            if back or side:
                hput(x, f, z)
    # Masses : pour chaque bloc 2 × 2 de la surface, une épaisseur
    # variable vers l'extérieur.
    for z0 in range(62, 76, 2):
        for f0 in range(-12, 2, 2):
            for x0 in range(-12, 12, 2):
                cx, cf = x0 + 1, f0 + 1
                # Distance au crâne (ellipse) et poussée vers le haut/côtés.
                side_d = abs(cx + 0.5) - 6.5
                back_d = -6.5 - cf
                n = vx.noise((x0 // 2, f0 // 2, z0 // 2), 85)
                if z0 < 64 and cf > -6:
                    continue
                if cf > 2:
                    continue
                reach = 0.6 + 3.2 * n * n + (z0 - 64) * 0.2
                if z0 >= 72:
                    reach += 1.0
                ok = False
                if side_d > -1 and side_d < reach and cf <= 1 and z0 >= 66:
                    ok = True
                if back_d > -1 and back_d < reach * 0.8 and abs(cx) < 9:
                    ok = True
                if side_d > -1 and back_d > -1 and side_d + back_d < reach:
                    ok = True
                # Couronne autour du sommet dégarni (z 72..75).
                if z0 >= 72 and (abs(cx + 0.5) > 3.5 or cf < -2) and abs(cx) < 9 and cf > -10 and n > 0.3:
                    ok = True
                if z0 >= 74 and n < 0.55:
                    ok = False
                if not ok:
                    continue
                for x in (x0, x0 + 1):
                    for f in (f0, f0 + 1):
                        for z in (z0, z0 + 1):
                            hput(x, f, z)
    # Épis : pointes de 2 cubes en marches vers l'extérieur et le haut.
    spikes = [((8, -3, 74), (1, 0, 1), 3), ((-9, -2, 74), (-1, 0, 1), 3),
              ((10, -1, 70), (1, 1, 0), 2), ((-11, 0, 70), (-1, 1, 0), 2),
              ((2, -9, 74), (0, -1, 1), 3), ((-4, -9, 73), (-1, -1, 1), 2),
              ((6, -8, 72), (1, -1, 1), 2), ((-6, -4, 76), (0, 0, 1), 2), ((4, -5, 76), (1, 0, 1), 2)]
    for (x, f, z), (dx, df, dz), n in spikes:
        for i in range(n):
            for a in (0, 1):
                for c in (0, 1):
                    if i == n - 1 and (a or c):
                        continue
                    px = x + dx * i + (a if dx == 0 else 0)
                    pf = f + df * i + (c if df == 0 else 0)
                    pz = z + dz * i + (a if dx != 0 and dz == 0 else 0)
                    hput(px, pf, pz)


# ---------------------------------------------------------------------------
# Ossature (cubes de 2,5 cm). Repère du modèle : y = -f - 1.
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, 0, 36), (0, 0, 42)),
    ("spine", "hips", (0, 0, 42), (0, 0, 50)),
    ("chest", "spine", (0, 0, 50), (0, 0, 57)),
    ("neck", "chest", (0, 0, 57), (0, 0, 58)),
    ("head", "neck", (0, 0.5, 58), (0, 0.5, 73)),
    ("arm_l", "chest", (9.5, 0.5, 56), (9.5, 0.5, 44)),
    ("forearm_l", "arm_l", (9.5, 0.5, 44), (9.5, 0.5, 31)),
    ("arm_r", "chest", (-9.5, 0.5, 56), (-9.5, 0.5, 44)),
    ("forearm_r", "arm_r", (-9.5, 0.5, 44), (-9.5, 0.5, 31)),
    ("thigh_l", "hips", (3, 0, 38), (3, 0, 21)),
    ("shin_l", "thigh_l", (3, 0, 21), (3, 0, 1)),
    ("thigh_r", "hips", (-3, 0, 38), (-3, 0, 21)),
    ("shin_r", "thigh_r", (-3, 0, 21), (-3, 0, 1)),
]


def describe():
    b = Body()
    build_legs(b)
    build_torso(b)
    build_mask(b)
    build_arms(b)
    build_head(b)
    m = b.m
    for k in [k for k in m.face_color if k[:3] not in m.vox]:
        del m.face_color[k]
    for k in [k for k in m.face_mat if k[:3] not in m.vox]:
        del m.face_mat[k]
    vx.shade(m, {"+z": 1.04, "-z": 0.75, "+x": 0.94, "-x": 0.94, "-y": 1.0, "+y": 0.96},
             skip_mats=("eye", "glow", "bone", "glass"))
    return m


def build():
    m = describe()
    ob, info = vx.build_mesh(m, "scientist_voxel")
    rig = vx.build_armature("scientist_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    return m, ob, rig, info


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


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m, ob, rig, info = build()
    print("[scientist_voxel] %s" % info)
    if "--glb" in args:
        glb = args[args.index("--glb") + 1]
        vx.export_glb(os.path.abspath(glb), [ob, rig], CUBE)
        print("[scientist_voxel] -> %s" % glb)
