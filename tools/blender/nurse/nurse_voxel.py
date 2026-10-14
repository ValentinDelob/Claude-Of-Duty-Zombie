# L'INFIRMIÈRE HURLANTE CUBIQUE (GAME_CONCEPT.md § 4.4 : mini-boss « cri qui
# attire et étourdit », échantillons cordes vocales, seringue cassée, badge ;
# § 4.19 : personnages et mobs en cubes de 2,5 cm). Infirmière de nuit de
# l'hôpital, grande et décharnée : blouse-robe blanche à col et ceinture bleu
# pâle, tachée de sang et de crasse, bas blancs filés, chaussures blanches,
# peau grise-verte des zombies du jeu, cheveux noirs filasse, COIFFE blanche
# d'infirmière (bande bleue, pas de croix), BOUCHE BÉANTE (mâchoire décrochée,
# dents, sang qui coule sur le menton et la poitrine), GORGE déchirée où
# luisent les cordes vocales (point faible, émissives comme les yeux), yeux
# qui luisent cernés de noir ; BADGE d'identification épinglé sur la poitrine
# et SERINGUE cassée (verre, liquide vert, aiguille tordue) dans la main
# droite ; main gauche aux ongles longs.
#
#   sh tools/blender.sh tools/blender/nurse/nurse_voxel.py [--glb FICHIER] [--sheet FICHIER.png] [--cache]
#
# Pas de planche de référence : formes DÉCRITES ici par pavés de cubes aux
# arêtes arrondies d'un cube (comme le Brancardier), couleurs d'une palette
# et d'un bruit par blocs de 2 ou 3 cubes (voxel_lib.noise).
# Ossature : RigBuilder.BONES, os droits, repos membres pendants, pondération
# rigide ; la jupe est partagée en deux moitiés portées par les cuisses (elle
# s'ouvre comme une fente quand elle marche), le haut de la jupe sur le
# bassin ; seringue sur l'avant-bras droit ; coiffe et cheveux sur la tête.
# Animation : procédurale dans le jeu (scripts/game/nurse/nurse_anim.gd).
# CACHE : nurse_voxel_cells.json (suivi par git) ; --cache le relit.
#
# Repère : Z en haut, avant vers -Y, gauche du personnage vers +X. « f » est
# la profondeur vers l'AVANT : la cellule (x, f, z) est la cellule
# (x, y = -f - 1, z) du modèle.
import bpy, math, os, sys
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_CHAR
CACHE = os.path.join(HERE, "nurse_voxel_cells.json")

# ---------------------------------------------------------------------------
# Palette (sRGB).
# ---------------------------------------------------------------------------
SKIN = (0.47, 0.53, 0.45)        # peau des zombies du jeu, plus pâle (nuit)
SKIN_DARK = (0.36, 0.41, 0.35)
SKIN_LIGHT = (0.55, 0.60, 0.52)
BRUISE = (0.33, 0.29, 0.36)
VEIN = (0.36, 0.30, 0.42)
EYE_RING = (0.16, 0.13, 0.15)    # cernes noirs
DRESS = (0.86, 0.85, 0.80)       # blouse blanche usée
DRESS_DARK = (0.70, 0.69, 0.64)
DRESS_SEAM = (0.76, 0.75, 0.70)
TRIM = (0.50, 0.66, 0.74)        # col, ceinture, bande de la coiffe (bleu pâle)
TRIM_DARK = (0.38, 0.52, 0.60)
BUTTON = (0.62, 0.62, 0.60)
STOCKING = (0.90, 0.89, 0.86)
SHOE = (0.92, 0.92, 0.89)
SHOE_SOLE = (0.50, 0.50, 0.48)
DIRT = (0.42, 0.36, 0.28)
BLOOD = (0.44, 0.05, 0.05)
BLOOD_DRY = (0.30, 0.07, 0.06)
FLESH = (0.56, 0.16, 0.15)
HAIR = (0.11, 0.09, 0.09)
HAIR_LIGHT = (0.19, 0.16, 0.15)
CAP = (0.95, 0.95, 0.92)
EYE = (1.0, 0.55, 0.60)          # lueur des yeux et de la gorge (émissifs)
TOOTH = (0.84, 0.80, 0.62)
MOUTH = (0.12, 0.03, 0.04)
NAIL = (0.24, 0.24, 0.20)
GLASS = (0.74, 0.86, 0.88)       # seringue
GLASS_DARK = (0.56, 0.68, 0.72)
OOZE = (0.50, 0.74, 0.20)        # liquide vert
PLUNGER = (0.86, 0.86, 0.84)
NEEDLE = (0.70, 0.72, 0.74)
BADGE = (0.96, 0.96, 0.94)       # badge : carte blanche, bande bleue, photo
BADGE_BAND = (0.22, 0.42, 0.74)
PHOTO = (0.62, 0.54, 0.46)
CLIP = (0.66, 0.66, 0.62)


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
        de `round_xy` cubes, bord du dessus ou du dessous arrondi d'un cube."""
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
# Texture : variation par blocs, salissures, sang.
# ---------------------------------------------------------------------------

def dress(seed, base=DRESS):
    def fn(x, f, z):
        k = 0.93 + 0.1 * vx.noise((x // 3, f // 3, z // 3), seed)
        c = vx.tone(base, k)
        if vx.noise((x // 3, f // 3, z // 4), seed + 5) > 0.86:
            c = mix(c, DIRT, 0.3)
        if vx.noise((x // 3, f // 3, z // 3), seed + 9) > 0.985:
            c = mix(c, BLOOD_DRY, 0.6)
        return c
    return fn


def skin(seed, base=SKIN):
    def fn(x, f, z):
        k = 0.93 + 0.12 * vx.noise((x // 2, f // 2, z // 2), seed)
        c = vx.tone(base, k)
        if vx.noise((x // 3, f // 3, z // 3), seed + 3) > 0.9:
            c = mix(c, BRUISE, 0.45)
        return c
    return fn


def hair(seed):
    def fn(x, f, z):
        return HAIR_LIGHT if vx.noise((x, f // 2, z // 3), seed) > 0.78 else vx.tone(HAIR, 0.9 + 0.2 * vx.noise((x, f, z), seed + 1))
    return fn


def solid(color):
    return lambda x, f, z: color


# ---------------------------------------------------------------------------
# Jambes : chaussures blanches, bas filés (tibia z 3..21).
# ---------------------------------------------------------------------------

def build_legs(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):  # intervalle [a, c) côté gauche -> côté du personnage
            return (a, c) if s > 0 else (-c, -a)
        shin = "shin_" + side
        # Chaussures d'infirmière : semelle, dessus blanc crotté.
        x0, x1 = X(1, 7)
        b.slab(x0, x1, -3, 6, 0, 1, "leather", shin, "shoe_" + side, solid(SHOE_SOLE), round_xy=1)
        b.slab(x0, x1, -3, 6, 1, 3, "leather", shin, "shoe_" + side,
               lambda x, f, z: mix(SHOE, DIRT, 0.4) if vx.noise((x, f // 2, z), 41 + s) > 0.75 else vx.tone(SHOE, 0.96 + 0.05 * vx.noise((x // 2, f // 2, 0), 42)),
               round_xy=2, round_top=1)
        # Bas blancs (tibia), mollet maigre.
        x0, x1 = X(2, 6)
        b.slab(x0, x1, -2, 2, 3, 22, "cloth", shin, "stocking_" + side,
               lambda x, f, z: vx.tone(STOCKING, 0.94 + 0.06 * vx.noise((x, f, z // 3), 12 + s)), round_xy=1)
        # Mailles filées : longues échelles de peau grise sur le devant et le côté.
        for x, z0, z1 in ((X(2, 6)[0] + (1 if s > 0 else 2), 6, 17), (X(2, 6)[0] + (2 if s > 0 else 1), 12, 21)):
            for z in range(z0, z1):
                if vx.noise((x, z, s), 13) > 0.25:
                    b.paint_front(x, z, mix(SKIN, BRUISE, 0.25), "skin")
        xo = X(2, 6)[1] - 1 if s > 0 else X(2, 6)[0]
        for z in range(8, 15):
            b.face(xo, 0, z, "+x" if s > 0 else "-x", SKIN_DARK, "skin")
        # Genou écorché (sous l'ourlet).
        for x in range(*X(2, 6)):
            if vx.noise((x, s, 0), 14) > 0.4:
                b.paint_front(x, 20, BLOOD_DRY, "wound")


# ---------------------------------------------------------------------------
# Robe : jupe en deux moitiés (cuisses) z 20..37, haut de jupe (bassin)
# z 37..43, ceinture, buste (spine, chest), col pointu, boutons, badge.
# ---------------------------------------------------------------------------

def build_dress(b):
    for s, side in ((1, "l"), (-1, "r")):
        thigh = "thigh_" + side
        x0, x1 = (0, 8) if s > 0 else (-8, 0)
        b.slab(x0, x1, -4, 4, 20, 37, "cloth", thigh, "skirt",
               dress(21 + s), round_xy=1)
        # Ourlet plus sombre, déchiré par endroits (dents de scie).
        for x in range(x0, x1):
            for f in range(-4, 4):
                if b.get(x, f, 20) is not None:
                    if vx.noise((x, f, 3), 23) > 0.6:
                        b.drop(x, f, 20)
                    else:
                        b.face(x, f, 20, "-z", DRESS_DARK, "cloth")
        # Fente de couture (milieu) un peu plus sombre devant et derrière.
        xm = 0 if s > 0 else -1
        for z in range(21, 37):
            b.paint_front(xm, z, DRESS_SEAM, "cloth")
            b.paint_back(xm, z, DRESS_SEAM, "cloth")
    # Haut de la jupe (bassin).
    b.slab(-8, 8, -4, 4, 37, 43, "cloth", "hips", "skirt", dress(25), round_xy=1)
    # Taille (spine) : mince, ceinture bleu pâle z 42..44.
    b.slab(-7, 7, -3, 4, 43, 51, "cloth", "spine", "dress", dress(27), round_xy=1)
    b.slab(-8, 8, -4, 5, 42, 44, "cloth", "spine", "belt",
           lambda x, f, z: vx.tone(TRIM, 0.92 + 0.08 * vx.noise((x // 2, f, z), 28)), round_xy=1)
    for z in (42, 43):
        b.put(1, 5, z, "metal", "spine", "belt", BUTTON)
        b.put(0, 5, z, "metal", "spine", "belt", vx.tone(BUTTON, 0.8))
    # Buste (chest) : épaules étroites et osseuses, poitrine discrète.
    b.slab(-8, 8, -4, 4, 51, 57, "cloth", "chest", "dress", dress(29), round_xy=1)
    b.slab(-6, 6, 4, 5, 52, 56, "cloth", "chest", "dress", dress(29), round_xy=1)
    b.slab(-9, 9, -3, 3, 55, 58, "cloth", "chest", "dress", dress(31), round_xy=2)
    # Col pointu bleu pâle (deux pointes sur la poitrine) et encolure.
    for z, xs in ((57, range(-5, 5)), (56, (-5, -4, -3, 2, 3, 4)), (55, (-4, -3, 2, 3)), (54, (-3, 2))):
        for x in xs:
            f = b.front(x, z)
            if f is not None:
                b.put(x, f + 1, z, "cloth", "chest", "collar", vx.tone(TRIM, 0.95 + 0.05 * vx.noise((x, 0, z), 32)))
    # Rangée de boutons (z 44..55), pas sous le col.
    for z in range(45, 54, 3):
        b.paint_front(-1, z, BUTTON, "metal")
    # Coulures de sang depuis la bouche : poitrine et ventre.
    for x, z0 in ((-1, 47), (0, 50), (1, 52), (-2, 53)):
        for z in range(z0, 58):
            b.paint_front(x, z, BLOOD if z > z0 + 2 else BLOOD_DRY, "wound")
    for x, z in ((-5, 52), (-4, 45), (5, 40), (-6, 33), (-3, 24)):
        b.paint_front(x, z, BLOOD_DRY, "wound")
    # Dos : traînée de crasse (elle a traîné par terre).
    for x in range(-4, 4):
        for z in range(28, 40):
            if vx.noise((x, z // 2, 0), 33) > 0.55:
                b.paint_back(x, z, mix(DRESS, DIRT, 0.55), "cloth")


def build_badge(b):
    """Badge d'identification (échantillon) épinglé au-dessus de la poitrine
    gauche, à la taille (os spine) : carte blanche 4 × 5 à bande bleue en
    haut, petite photo, lignes de texte, pince."""
    for x in range(3, 7):
        for z in range(45, 50):
            if z == 49:
                col = BADGE_BAND
            elif x in (3, 4) and z in (46, 47):
                col = PHOTO
            elif x >= 5 and z in (46, 47):
                col = vx.tone(BADGE_BAND, 0.75)  # lignes de texte
            else:
                col = BADGE
            b.put(x, 4, z, "metal", "spine", "badge", col)
    b.put(4, 4, 50, "metal", "spine", "badge", CLIP)
    b.put(5, 4, 50, "metal", "spine", "badge", CLIP)


# ---------------------------------------------------------------------------
# Bras : manches courtes, bras maigres, mains griffues ; seringue cassée
# dans la main droite (tenue à l'horizontale, aiguille vers l'avant).
# ---------------------------------------------------------------------------

def build_arms(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):
            return (a, c) if s > 0 else (-c, -a)
        arm, fore = "arm_" + side, "forearm_" + side
        # Manche courte z 51..58 (sur l'os du bras), revers bleu pâle.
        x0, x1 = X(8, 13)
        b.slab(x0, x1, -3, 3, 51, 58, "cloth", arm, "sleeve_" + side, dress(35 + s), round_xy=1, round_top=1)
        for x in range(x0, x1):
            for f in range(-3, 3):
                if b.get(x, f, 51) is not None:
                    b.put(x, f, 51, "cloth", arm, "sleeve_" + side, vx.tone(TRIM, 0.9))
        # Bras maigre z 46..51 et avant-bras z 34..46 (3 × 3 cubes).
        x0, x1 = X(9, 12)
        b.slab(x0, x1, -1, 2, 46, 51, "skin", arm, "arm_" + side, skin(37 + s), round_xy=0)
        b.slab(x0, x1, -1, 2, 34, 46, "skin", fore, "forearm_" + side, skin(39 + s), round_xy=0)
        # Veines violettes à l'intérieur du bras.
        xi = x0 if s > 0 else x1 - 1
        for z in range(36, 50, 2):
            b.face(xi, 0 if z % 4 else 1, z, "-x" if s > 0 else "+x", VEIN, "skin")
        # Main : paume z 30..34, doigts longs z 27..30 (griffes), ongles noirs.
        b.slab(x0, x1, -1, 3, 30, 34, "skin", fore, "hand_" + side, skin(41 + s, SKIN_LIGHT), round_xy=1)
        for x in range(x0, x1):
            for f in (0, 2):
                for z in (28, 29):
                    b.put(x, f, z, "skin", fore, "hand_" + side, skin(43)(x, f, z))
                b.put(x, f, 27, "bone", fore, "hand_" + side, NAIL)
    # Seringue cassée, main droite (x -12..-9) : corps de verre 2 × 2 de
    # f 3 à 10 (liquide vert dedans), collerette, piston qui ressort derrière
    # la main, aiguille cassée et tordue vers le bas.
    xs = (-11, -10)
    for x in xs:
        for z in (31, 32):
            for f in range(3, 11):
                edge = f in (3, 10)
                if edge:
                    col = GLASS_DARK
                elif z == 31 and 4 <= f <= 7:
                    col = OOZE  # liquide qui reste au fond
                else:
                    col = GLASS
                b.put(x, f, z, "metal", "forearm_r", "syringe", col)
        # Collerette (appui des doigts).
        b.put(x, 3, 30, "metal", "forearm_r", "syringe", PLUNGER)
        b.put(x, 3, 33, "metal", "forearm_r", "syringe", PLUNGER)
    for z in (30, 31, 32, 33):
        b.put(-12, 3, z, "metal", "forearm_r", "syringe", PLUNGER)
        b.put(-9, 3, z, "metal", "forearm_r", "syringe", PLUNGER)
    # Graduations (faces du dessus).
    for f in (5, 7, 9):
        b.face(-11, f, 32, "+z", GLASS_DARK, "metal")
    # Piston : tige qui ressort derrière la main, poussoir.
    for f in (-2, -3):
        b.put(-11, f, 32, "metal", "forearm_r", "syringe", PLUNGER)
    for x in (-12, -11, -10):
        for z in (31, 32, 33):
            b.put(x, -4, z, "metal", "forearm_r", "syringe", PLUNGER)
    # Embout et aiguille cassée (2 cubes), bout tordu vers le bas.
    b.put(-11, 11, 32, "metal", "forearm_r", "syringe", GLASS_DARK)
    b.put(-11, 12, 32, "metal", "forearm_r", "syringe", NEEDLE)
    b.put(-11, 13, 32, "metal", "forearm_r", "syringe", NEEDLE)
    b.put(-11, 13, 31, "metal", "forearm_r", "syringe", vx.tone(NEEDLE, 0.8))
    # Goutte verte au bout.
    b.put(-11, 13, 30, "wound", "forearm_r", "syringe", OOZE)


# ---------------------------------------------------------------------------
# Cou (gorge déchirée, cordes vocales qui luisent), tête, bouche béante,
# cheveux filasse, coiffe d'infirmière.
# ---------------------------------------------------------------------------

def build_head(b):
    # Cou maigre z 58..62 ; plaie de la gorge devant (f 1..2).
    b.slab(-3, 3, -2, 2, 58, 62, "skin", "neck", "neck", skin(51, SKIN_DARK), round_xy=0)
    # Gorge béante : chair à vif autour, cordes vocales émissives.
    for x in range(-3, 3):
        for z in (58, 59):
            inner = -2 <= x < 2
            if inner:
                b.put(x, 2, z, "eye", "neck", "vocal_cords", EYE)
            else:
                b.put(x, 2, z, "wound", "neck", "throat", FLESH if (x + z) % 2 else BLOOD)
    # Mâchoire (os jaw) z 60..63 : décrochée, pendante ; dents du bas qui
    # dépassent de la lèvre.
    b.slab(-4, 4, 0, 6, 60, 63, "skin", "jaw", "jaw", skin(55, SKIN_DARK), round_xy=1, round_bottom=1)
    for x in range(-3, 3):
        b.face(x, 5, 62, "+z", MOUTH, "wound")
        b.face(x, 4, 62, "+z", MOUTH, "wound")
        if x % 2 == 0 or x in (-3, 2):
            b.put(x, 5, 63, "bone", "jaw", "teeth", TOOTH if x in (-3, 2) else vx.tone(TOOTH, 0.88))
    # Menton taché de sang (coulures).
    for x, z in ((-1, 60), (-1, 61), (0, 60), (1, 61), (-2, 61)):
        b.paint_front(x, z, BLOOD, "wound", part="jaw")
    # Crâne (os head) z 64..72, nuque z 62..64 ; fond de la gorge (z 63).
    b.slab(-5, 5, -4, 5, 64, 72, "skin", "head", "head", skin(53), round_xy=2, round_top=1)
    b.slab(-4, 4, -4, 0, 62, 64, "skin", "head", "head", skin(53, SKIN_DARK), round_xy=1)
    for x in range(-3, 3):
        for f in (0, 1, 2):
            b.put(x, f, 63, "wound", "head", "mouth", MOUTH)
    # Bouche BÉANTE : cavité de 3 cubes de haut (z 63..65), fond sombre,
    # dents du haut qui pendent, commissures à vif.
    for x in range(-3, 3):
        for z in (64, 65):
            b.drop(x, 4, z)
            b.drop(x, 3, z)
            b.face(x, 2, z, "-y", MOUTH, "wound")
        b.face(x, 2, 63, "-y", MOUTH, "wound")
        b.face(x, 2, 63, "+z", MOUTH, "wound")
        if x % 2:
            b.put(x, 4, 65, "bone", "head", "teeth", vx.tone(TOOTH, 0.9))
        b.face(x, 3, 66, "-z", MOUTH, "wound")
        b.face(x, 4, 66, "-z", MOUTH, "wound")
    for x in (-4, 3):
        b.face(x, 4, 64, "-y", FLESH, "wound")
        b.face(x, 4, 65, "-y", BLOOD, "wound")
    # Nez fin (pointe), joues creuses (faces plus sombres).
    b.put(-1, 5, 67, "skin", "head", "nose", SKIN)
    b.put(0, 5, 67, "skin", "head", "nose", SKIN)
    b.put(-1, 5, 66, "skin", "head", "nose", SKIN_DARK)
    b.put(0, 5, 66, "skin", "head", "nose", SKIN_DARK)
    for x in (-4, -3, 2, 3):
        b.paint_front(x, 66, vx.tone(SKIN_DARK, 0.85), "skin", part="head")
    # Yeux 2 × 2 émissifs, enfoncés d'un cube dans de grands cernes noirs.
    for xs in ((1, 2), (-3, -2)):
        for x in xs:
            for z in (68, 69):
                b.drop(x, 4, z)
                b.put(x, 3, z, "eye", "head", "eye", EYE)
        for x in range(xs[0] - 1, xs[1] + 2):
            for z in (67, 70):
                b.paint_front(x, z, EYE_RING, "skin", part="head")
        for z in (68, 69):
            b.paint_front(xs[0] - 1, z, EYE_RING, "skin", part="head")
            b.paint_front(xs[1] + 1, z, EYE_RING, "skin", part="head")
    # Cheveux noirs filasse : calotte, frange en mèches, mèches qui pendent
    # sur les côtés et dans la nuque (jusqu'au cou).
    hf = hair(57)
    b.slab(-6, 6, -5, 4, 70, 73, "cloth", "head", "hair", hf, round_xy=2)
    # Côtés et nuque.
    for x in (-6, 5):
        for f in range(-5, 3):
            ztop = 70
            zlow = 61 + int(3 * vx.noise((x, f, 0), 58)) + (2 if f >= 1 else 0)
            for z in range(zlow, ztop):
                b.put(x, f, z, "cloth", "head", "hair", hf(x, f, z))
    for x in range(-5, 5):
        zlow = 60 + int(3 * vx.noise((x, 0, 1), 59))
        for z in range(zlow, 70):
            b.put(x, -5, z, "cloth", "head", "hair", hf(x, -5, z))
    # Frange : mèches inégales sur le front (pas sur les yeux).
    for x in range(-5, 5):
        drop = 1 + (1 if vx.noise((x, 1, 2), 60) > 0.5 else 0)
        if x in (-1, 0):
            drop = 0
        for z in range(72 - drop, 72):
            b.put(x, 5, z, "cloth", "head", "hair", hf(x, 5, z))
    # Coiffe d'infirmière blanche (z 73..76) posée sur le haut du crâne,
    # rabat dressé devant, bande bleue ; tachée de sang à gauche.
    b.slab(-5, 5, -3, 3, 73, 74, "cloth", "head", "cap", solid(CAP), round_xy=1)
    for x in range(-5, 5):
        for z in (74, 75, 76):
            if z == 76 and x in (-5, 4):
                continue
            col = vx.tone(CAP, 0.97 + 0.03 * vx.noise((x, 0, z), 61))
            if z == 75:
                col = TRIM
            b.put(x, 2, z, "cloth", "head", "cap", col)
            b.put(x, 1, z, "cloth", "head", "cap", vx.tone(CAP, 0.9))
    for x, z in ((2, 74), (3, 74), (3, 73)):
        b.paint_front(x, z, BLOOD_DRY, "wound", part="cap")
    # Oreille droite et gauche (sous les cheveux, un cube qui dépasse).
    b.put(-6, 0, 66, "skin", "head", "ear", SKIN_DARK)
    b.put(5, 0, 66, "skin", "head", "ear", SKIN_DARK)


# ---------------------------------------------------------------------------
# Ossature (RigBuilder.BONES) en cubes de 2,5 cm. Repère : y = -f - 1.
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, -0.5, 37), (0, -0.5, 43)),
    ("spine", "hips", (0, -0.5, 43), (0, -0.5, 51)),
    ("chest", "spine", (0, -0.5, 51), (0, -0.5, 58)),
    ("neck", "chest", (0, -0.5, 58), (0, -0.5, 62)),
    ("head", "neck", (0, -0.5, 62), (0, -0.5, 73)),
    ("arm_l", "chest", (10.5, -0.5, 57), (10.5, -0.5, 46)),
    ("forearm_l", "arm_l", (10.5, -0.5, 46), (10.5, -0.5, 30)),
    ("arm_r", "chest", (-10.5, -0.5, 57), (-10.5, -0.5, 46)),
    ("forearm_r", "arm_r", (-10.5, -0.5, 46), (-10.5, -0.5, 30)),
    ("thigh_l", "hips", (3.5, -0.5, 37), (3.5, -0.5, 21)),
    ("shin_l", "thigh_l", (3.5, -0.5, 21), (3.5, -0.5, 1)),
    ("thigh_r", "hips", (-3.5, -0.5, 37), (-3.5, -0.5, 21)),
    ("shin_r", "thigh_r", (-3.5, -0.5, 21), (-3.5, -0.5, 1)),
    ("jaw", "head", (0, -1, 63), (0, -7, 63)),
]


def describe():
    b = Body()
    build_legs(b)
    build_dress(b)
    build_badge(b)
    build_arms(b)
    build_head(b)
    m = b.m
    for k in [k for k in m.face_color if k[:3] not in m.vox]:
        del m.face_color[k]
    for k in [k for k in m.face_mat if k[:3] not in m.vox]:
        del m.face_mat[k]
    vx.shade(m, {"+z": 1.06, "-z": 0.64, "+x": 0.88, "-x": 0.88, "-y": 1.0, "+y": 0.93}, skip_mats=("eye",))
    vx.quantize(m, {"cloth": 24, "skin": 16, "leather": 6, "metal": 12, "wound": 8})
    return m


def build(use_cache=False):
    info = {}
    if use_cache and os.path.exists(CACHE):
        m = vx.load_cache(CACHE)
        info["from_cache"] = True
    else:
        m = describe()
        vx.save_cache(m, CACHE)
    # Orbites lisibles (lueur des yeux dans un creux sombre ; pas la gorge).
    info["sockets"] = vx.eye_sockets(m, skip_parts=("vocal_cords",))
    ob, mi = vx.build_mesh(m, "nurse_voxel")
    info.update(mi)
    rig = vx.build_armature("nurse_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    info["z_range"] = (int(lo[2]), int(hi[2]))
    return m, ob, rig, info


# ---------------------------------------------------------------------------
# Planche de validation : vues, poses (marche, préparation du cri, cri, coup
# de seringue, touchée, mort) et gros plans.
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
WINDUP = [("spine", "X", -10), ("chest", "X", -8), ("neck", "X", -20), ("head", "X", -25), ("jaw", "X", 15),
          ("arm_l", "Y", 55), ("arm_r", "Y", -55), ("forearm_l", "X", 20), ("forearm_r", "X", 20)]
SCREAM = [("spine", "X", 18), ("chest", "X", 10), ("neck", "X", 15), ("head", "X", 10), ("jaw", "X", 60),
          ("arm_l", "X", -35), ("arm_r", "X", -35), ("arm_l", "Y", 30), ("arm_r", "Y", -30)]
STAB = [("spine", "X", 10), ("arm_r", "X", 150), ("forearm_r", "X", 40), ("jaw", "X", 30)]
CHOKE = [("spine", "X", 25), ("neck", "X", 20), ("head", "X", 15), ("arm_l", "X", 110), ("arm_r", "X", 110),
         ("forearm_l", "X", 70), ("forearm_r", "X", 70), ("arm_l", "Y", -30), ("arm_r", "Y", 30)]


def render_sheet(m, ob, rig, path):
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles_nurse")
    os.makedirs(tmp, exist_ok=True)
    vx.add_outline(m, "nurse_voxel_outline", rig)
    TW, TH = 360, 560
    vx.setup_render((TW, TH))
    hm, tz = 2.2, 0.95

    def shot(name, az, el, target=(0, 0, tz), h=hm):
        return vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, target, h, el))

    row1 = [shot("front", 0, 0), shot("back", 180, 0), shot("left", 90, 0), shot("right", -90, 0),
            shot("34", 35, 10), shot("back34", 145, 10)]
    row2 = [shot("head", 20, 6, (0, -0.05, 1.65), 0.55), shot("face", 0, 0, (0, -0.05, 1.65), 0.45),
            shot("badge", 15, 5, (0.1, 0, 1.3), 0.5), shot("syringe", -50, 10, (-0.26, -0.15, 0.8), 0.55)]
    pose(rig, WINDUP)
    row2.append(shot("windup", 40, 6))
    rest_pose(rig)
    pose(rig, SCREAM)
    row2.append(shot("scream", 60, 4))
    rest_pose(rig)
    pose(rig, STAB)
    row3 = [shot("stab", 70, 6, (0, 0, 1.1), 2.6)]
    rest_pose(rig)
    pose(rig, CHOKE)
    row3.append(shot("choke", 30, 6))
    rest_pose(rig)
    pose(rig, SCREAM)
    row3.append(shot("scream_face", 10, 4, (0, -0.1, 1.55), 0.7))
    rest_pose(rig)
    row3.append(shot("top", 0, 70, (0, 0, 1.0), 2.0))
    vx.save_png(vx.sheet([row1, row2, row3], TW, TH), path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "nurse", "nurse_voxel.glb")
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
    os.makedirs(os.path.dirname(os.path.abspath(glb)), exist_ok=True)
    vx.export_glb(os.path.abspath(glb), [ob, rig], CUBE)
    print("[nurse_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(m, ob, rig, os.path.abspath(sheet))
        print("[nurse_voxel] planche -> %s" % sheet)
