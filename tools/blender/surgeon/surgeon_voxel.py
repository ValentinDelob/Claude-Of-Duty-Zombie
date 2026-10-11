# Le CHIRURGIEN CUBIQUE (GAME_CONCEPT.md : premier BOSS ; § 4.19 : personnages
# et mobs en cubes de 2,5 cm). Ancien chef du service de chirurgie de
# l'hôpital devenu un zombie boss : grand (2,30 m au sommet du crâne), maigre,
# un peu voûté, bras et jambes interminables (à l'opposé de la brute du
# Brancardier) ; peau verdâtre des zombies du jeu marbrée de veines violettes,
# yeux qui luisent sous des arcades creuses ; CALOT de bloc sarcelle à pois,
# LOUPES binoculaires relevées sur le front, MASQUE chirurgical bleu pâle
# (élastiques jusqu'aux oreilles) déchiré d'un côté sur les dents ; longue
# BLOUSE de bloc vert menthe (jusqu'à mi-tibia, manches à mi-avant-bras,
# nouée dans le dos, ourlet déchiré en marches) au devant trempé de sang en
# forme de tablier ; pantalon de bloc sarcelle, SUR-CHAUSSURES bleues ;
# GANTS de latex bleu-violet aux longs doigts ; SCALPEL GÉANT dans le poing
# droit (lame d'acier de 55 cm pointée vers l'avant, fil plus clair, manche
# strié derrière le poing) ; ceinture et trousse de scalpels de rechange sur
# la hanche gauche, pince clampée à la poche de poitrine. POINT FAIBLE : la
# blouse et la cage thoracique ouvertes à gauche de la poitrine sur le CŒUR
# MUTANT (matière « heart » : lueur rouge pulsée en jeu), encadré de côtes et
# de chair à vif.
#
#   sh tools/blender.sh tools/blender/surgeon/surgeon_voxel.py [--glb FICHIER] [--sheet FICHIER.png] [--cache]
#
# Pas de planche de référence : formes DÉCRITES ici par pavés de cubes aux
# arêtes arrondies d'un cube (comme le Brancardier), couleurs d'une palette
# et d'un bruit par blocs de 2 ou 3 cubes (voxel_lib.noise : texture « un
# pixel = un cube » reproductible, faces voisines de même teinte fusionnées :
# budget de triangles).
# Ossature : RigBuilder.BONES (hips > spine > chest > neck > head > jaw, bras,
# avant-bras, cuisses, tibias), os droits, repos membres pendants, pondération
# rigide (chaque cube à 100 % sur un os) ; gants, mains et scalpel sur
# l'avant-bras, sur-chaussures sur le tibia ; le pan de blouse sous le bassin
# est fendu comme une redingote : moitié gauche sur thigh_l, moitié droite
# sur thigh_r ; ceinture et trousse sur le bassin ; cœur, côtes, poche et
# pince sur la poitrine.
# Animation : procédurale dans le jeu.
# CACHE : cellules et couleurs de faces dans surgeon_voxel_cells.json (suivi
# par git, à côté du script) ; --cache relit ce fichier (modèle identique).
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
CACHE = os.path.join(HERE, "surgeon_voxel_cells.json")

# ---------------------------------------------------------------------------
# Palette (sRGB).
# ---------------------------------------------------------------------------
SKIN = (0.42, 0.50, 0.38)        # peau des zombies du jeu (zombie_voxel.py)
SKIN_DARK = (0.33, 0.40, 0.31)
SKIN_LIGHT = (0.50, 0.57, 0.44)
VEIN = (0.38, 0.30, 0.42)        # veines violettes (infection)
BRUISE = (0.30, 0.27, 0.33)
GOWN = (0.62, 0.80, 0.70)        # blouse de bloc vert menthe
GOWN_DARK = (0.48, 0.65, 0.57)
GOWN_SEAM = (0.54, 0.71, 0.62)
PANTS = (0.22, 0.42, 0.46)       # pantalon de bloc sarcelle
CAP = (0.15, 0.36, 0.42)         # calot sarcelle foncé
CAP_DOT = (0.55, 0.78, 0.80)
MASK = (0.68, 0.84, 0.94)        # masque chirurgical bleu pâle
MASK_DARK = (0.54, 0.70, 0.82)
GLOVE = (0.62, 0.62, 0.90)       # latex bleu-violet
GLOVE_DARK = (0.47, 0.47, 0.74)
BOOTIE = (0.34, 0.52, 0.84)      # sur-chaussures bleues
BOOTIE_DARK = (0.24, 0.38, 0.66)
SOLE = (0.20, 0.22, 0.26)
LEATHER = (0.30, 0.20, 0.13)     # ceinture, trousse
LEATHER_DARK = (0.20, 0.13, 0.08)
STEEL = (0.76, 0.79, 0.82)       # lame du scalpel
STEEL_DARK = (0.42, 0.44, 0.48)
EDGE = (0.96, 0.98, 1.0)         # fil de la lame
LENS = (0.06, 0.08, 0.10)
BLOOD = (0.48, 0.05, 0.05)
BLOOD_DRY = (0.32, 0.06, 0.05)
BLOOD_WET = (0.60, 0.07, 0.06)
FLESH = (0.52, 0.14, 0.12)
WOUND_DARK = (0.22, 0.04, 0.04)
RIB = (0.88, 0.84, 0.70)
HEART = (0.96, 0.22, 0.30)       # cœur mutant (point faible)
HEART_LIGHT = (1.0, 0.50, 0.55)
HEART_DARK = (0.74, 0.10, 0.20)
EYE = (1.0, 0.88, 0.30)          # lueur des yeux (zombies du jeu)
TOOTH = (0.86, 0.80, 0.58)
MOUTH = (0.14, 0.04, 0.04)


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

    def fronts(self, parts=None):
        """(x, z) -> profondeur f de la cellule la plus en avant (parties
        `parts` seulement si donné), en un seul passage."""
        out = {}
        for c, v in self.m.vox.items():
            if parts is not None and v.part not in parts:
                continue
            f = -c[1] - 1
            k = (c[0], c[2])
            if k not in out or f > out[k]:
                out[k] = f
        return out

    def backs(self, parts=None):
        out = {}
        for c, v in self.m.vox.items():
            if parts is not None and v.part not in parts:
                continue
            f = -c[1] - 1
            k = (c[0], c[2])
            if k not in out or f < out[k]:
                out[k] = f
        return out

    def front(self, x, z, part=None):
        fs = [-c[1] - 1 for c, v in self.m.vox.items() if c[0] == x and c[2] == z and (part is None or v.part == part)]
        return max(fs) if fs else None

    def paint_front(self, x, z, color, mat=None, part=None):
        f = self.front(x, z, part)
        if f is not None:
            self.face(x, f, z, "-y", color, mat)
        return f


# ---------------------------------------------------------------------------
# Texture : variation par blocs (tissu : 3 cubes, peau : 2), salissures.
# ---------------------------------------------------------------------------

def gown(seed, base=GOWN):
    def fn(x, f, z):
        k = 0.93 + 0.10 * vx.noise((x // 3, f // 3, z // 3), seed)
        c = vx.tone(base, k)
        if vx.noise((x // 3, f // 3, z // 4), seed + 5) > 0.95:
            c = mix(c, GOWN_DARK, 0.4)
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


def glove(seed):
    def fn(x, f, z):
        return vx.tone(GLOVE, 0.94 + 0.08 * vx.noise((x // 2, f // 2, z // 2), seed))
    return fn


def solid(color):
    return lambda x, f, z: color


def blood_col(x, z, seed=0):
    n = vx.noise((x // 2, 0, z // 3), 301 + seed)
    return BLOOD_DRY if n > 0.66 else (BLOOD_WET if n < 0.2 else BLOOD)


GOWN_PARTS = ("gown", "skirt_l", "skirt_r", "sleeve_l", "sleeve_r")

# ---------------------------------------------------------------------------
# Jambes : sur-chaussures (z 0..5), pantalon (tibia z 5..24), cuisses (z
# 24..44) noyées dans les pans de blouse fendue (anneau ouvert jusqu'à
# l'ourlet z ~15).
# ---------------------------------------------------------------------------

def build_legs(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):  # intervalle [a, c) côté gauche -> côté du personnage
            return (a, c) if s > 0 else (-c, -a)
        shin, thigh = "shin_" + side, "thigh_" + side
        # Sur-chaussures : semelle sombre, toile bleue bouffante, élastique.
        x0, x1 = X(1, 8)
        b.slab(x0, x1, -4, 9, 0, 1, "cloth", shin, "bootie_" + side, solid(SOLE), round_xy=2)
        b.slab(x0, x1, -4, 9, 1, 5, "cloth", shin, "bootie_" + side,
               lambda x, f, z: vx.tone(BOOTIE, 0.93 + 0.1 * vx.noise((x // 2, f // 2, z // 2), 21 + s)),
               round_xy=2, round_top=1)
        for x in range(x0, x1):
            for f in range(-4, 9):
                if b.get(x, f, 4) is not None:
                    b.face(x, f, 4, "+z", BOOTIE_DARK, "cloth")
        # Plis de la toile (fentes sur le dessus du pied).
        for x in range(x0 + 1, x1 - 1, 2):
            b.face(x, 8, 2, "-y", BOOTIE_DARK, "cloth")
            b.face(x, 7, 3, "+z", BOOTIE_DARK, "cloth")
        # Tibia : pantalon de bloc sarcelle (mince).
        x0, x1 = X(2, 7)
        b.slab(x0, x1, -3, 4, 5, 24, "cloth", shin, "pants_" + side, gown(31 + s, PANTS), round_xy=1)
        # Cuisse : bloc de blouse (pan fendu) z 24..44.
        x0, x1 = X(0, 9)
        b.slab(x0, x1, -6, 7, 24, 44, "cloth", thigh, "skirt_" + side, gown(33 + s), round_xy=1)
        # Pan sous le genou : anneau d'un cube d'épaisseur autour du tibia,
        # ourlet déchiré en marches (z 15..18 selon la colonne).
        for x in range(x0, x1):
            for f in range(-6, 7):
                ex = min(x - x0, x1 - 1 - x)
                ef = min(f + 6, 6 - f)
                if ex + ef < 1 or (ex > 0 and ef > 0):
                    continue
                zb = 15 + int(3.99 * vx.noise(((x + 20) // 2, (f + 20) // 2, 0), 35 + s))
                for z in range(zb, 24):
                    b.put(x, f, z, "cloth", thigh, "skirt_" + side, gown(33 + s)(x, f, z))
                # Bord de l'ourlet effiloché plus sombre.
                b.face(x, f, zb, "-z", GOWN_DARK, "cloth")
        # Plis verticaux du pan (devant, dos, côté extérieur).
        for z in range(15, 44):
            for xf in ((3, 7) if s > 0 else (-4, -8)):
                b.face(xf, 6, z, "-y", GOWN_SEAM, "cloth")
                b.face(xf, -6, z, "+y", GOWN_SEAM, "cloth")
            b.face(8 if s > 0 else -9, 2 if z % 2 else 1, z, "+x" if s > 0 else "-x", GOWN_SEAM, "cloth")


# ---------------------------------------------------------------------------
# Bassin, ventre, poitrine (blouse), ceinture et trousse, dos noué.
# ---------------------------------------------------------------------------

def build_torso(b):
    b.slab(-9, 9, -6, 7, 44, 51, "cloth", "hips", "gown", gown(41), round_xy=2)
    # Ventre creux (spine), poitrine étroite, dos voûté (bosse en escalier).
    b.slab(-8, 8, -5, 6, 51, 60, "cloth", "spine", "gown", gown(43), round_xy=2)
    b.slab(-9, 9, -5, 7, 60, 74, "cloth", "chest", "gown", gown(45), round_xy=2)
    b.slab(-8, 8, -7, -5, 63, 75, "cloth", "chest", "gown", gown(45), round_xy=2)
    b.slab(-6, 6, -8, -7, 67, 75, "cloth", "chest", "gown", gown(45), round_xy=1, round_top=1)
    b.slab(-9, 9, -5, 6, 74, 76, "cloth", "chest", "gown", gown(45), round_xy=3)
    # Base du cou (peau) et encolure ronde de la blouse.
    b.slab(-4, 4, -3, 4, 75, 77, "skin", "chest", "neckbase", skin(47), round_xy=1)
    for z, xs in ((73, range(-3, 3)), (74, range(-4, 4)), (75, range(-4, 4))):
        for x in xs:
            for f in (5, 6):
                if b.get(x, f, z) is not None:
                    b.drop(x, f, z)
            b.put(x, 4, z, "skin", "chest", "neckbase", skin(47)(x, 4, z))
    for x, z in ((-4, 73), (3, 73), (-5, 74), (4, 74), (-5, 75), (4, 75), (-3, 72), (-2, 72), (-1, 72), (0, 72), (1, 72), (2, 72)):
        b.paint_front(x, z, GOWN_SEAM, "cloth", part="gown")
    # Ceinture (cuir sombre) z 48..50, boucle d'acier devant.
    b.slab(-10, 10, -7, 8, 48, 50, "leather", "hips", "belt",
           lambda x, f, z: vx.tone(LEATHER, 0.9 + 0.1 * vx.noise((x // 2, f // 2, z), 49)), round_xy=2)
    for x in (-2, -1, 0, 1):
        for z in (48, 49):
            b.put(x, 8, z, "metal", "hips", "belt", STEEL if (x in (-2, 1) or z == 49) else STEEL_DARK)
    # Trousse de scalpels de rechange (hanche gauche, devant) : rabat sombre,
    # trois lames d'argent qui dépassent.
    b.slab(3, 9, 8, 11, 43, 49, "leather", "hips", "pouch",
           lambda x, f, z: vx.tone(LEATHER if z < 47 else LEATHER_DARK, 0.92 + 0.08 * vx.noise((x, f, z), 51)),
           round_xy=1, round_bottom=1)
    for x in (4, 6, 8):
        top = 53 if x == 6 else 52
        for z in range(49, top):
            b.put(x, 9, z, "metal", "hips", "pouch", STEEL if z < top - 1 else EDGE)
        b.put(x, 10, 49, "metal", "hips", "pouch", STEEL_DARK)
    for x in range(3, 9):
        b.face(x, 10, 46, "-y", STEEL_DARK if x in (5, 6) else LEATHER_DARK, "leather")
    # Dos : blouse ouverte (peau entre les pans), trois nœuds de liens.
    bk = b.backs(("gown",))
    for z in range(52, 75):
        for x in (-1, 0):
            f = bk.get((x, z))
            if f is not None:
                b.face(x, f, z, "+y", skin(53)(x, f, z), "skin")
    for z in (55, 64, 71):
        for x in range(-3, 3):
            f = bk.get((x, z))
            if f is None:
                continue
            b.put(x, f - 1, z, "cloth", b.get(x, f, z).bone, "ties", GOWN_DARK if x in (-1, 0) else GOWN_SEAM)
        for x, dz in ((-3, 1), (-3, 2), (2, 1), (2, 2), (2, 3)):
            f = bk.get((x, z - dz))
            if f is not None:
                b.put(x, f - 1, z - dz, "cloth", b.get(x, f, z - dz).bone, "ties", GOWN_SEAM)
    # Coutures latérales.
    for z in range(44, 74):
        for x, d in ((8, "+x"), (-9, "-x")):
            for f in (0,):
                b.face(x, f, z, d, GOWN_SEAM, "cloth")


def build_pocket(b):
    # Poche de poitrine (côté droit) et pince clampée au bord.
    for x in range(-8, -2):
        for z in range(63, 69):
            edge = x in (-8, -3) or z == 68
            b.paint_front(x, z, GOWN_SEAM if edge else vx.tone(GOWN, 0.95), "cloth", part="gown")
    for x in (-6, -4):
        for z in range(66, 72):
            b.put(x, 7, z, "metal", "chest", "forceps", STEEL if z < 70 else STEEL_DARK)
    for x in (-7, -6, -4, -3):
        b.put(x, 7, 72, "metal", "chest", "forceps", STEEL)
    b.put(-7, 7, 73, "metal", "chest", "forceps", STEEL)
    b.put(-3, 7, 73, "metal", "chest", "forceps", STEEL)
    b.put(-5, 7, 68, "metal", "chest", "forceps", STEEL_DARK)


def build_blood(b):
    """Tablier de sang : devant de la blouse trempé du haut de la poitrine
    jusqu'aux genoux, bord déchiqueté ; quelques coulures plus bas."""
    fr = b.fronts(GOWN_PARTS + ("belt",))
    for (x, z), f in fr.items():
        if z < 20 or z > 70:
            continue
        if z < 26:
            continue
        if z >= 60:
            w = 2.5 + (70 - z) * 0.3
        elif z >= 44:
            w = 5.5 + (60 - z) * 0.03
        else:
            w = 6.0 - max(0, 32 - z) * 0.35
        w += 1.4 * (vx.noise((x // 2, 0, z // 3), 303) - 0.5)
        xc = 0.6 * math.sin(z * 0.3)
        if abs(x + 0.5 - xc) > w:
            continue
        v = b.get(x, f, z)
        mat = "leather" if v.part == "belt" else "cloth"
        col = blood_col(x, z)
        if v.part == "belt":
            col = mix(v.color, BLOOD_DRY, 0.5)
        b.face(x, f, z, "-y", col, mat)
    # Coulures sous l'ourlet du tablier et éclaboussures éparses.
    for x, z0, n in ((-6, 22, 4), (-2, 21, 3), (3, 22, 5), (6, 24, 3), (-8, 40, 3), (8, 46, 2)):
        for z in range(z0 - n, z0):
            f = fr.get((x, z))
            if f is not None:
                b.face(x, f, z, "-y", BLOOD_DRY if z == z0 - n else BLOOD, "cloth")
    for x, z in ((-8, 68), (-7, 69), (8, 70), (7, 71), (-9, 56), (8, 33), (-7, 30)):
        f = fr.get((x, z))
        if f is not None:
            b.face(x, f, z, "-y", BLOOD_DRY, "cloth")
    # Manches : éclaboussures sur le devant, sang sur les poignets.
    for side, xs in (("l", range(9, 15)), ("r", range(-15, -9))):
        for x in xs:
            for z in range(44, 52):
                if vx.noise((x, 0, z // 2), 305 + len(side)) > 0.62:
                    f = fr.get((x, z))
                    if f is not None:
                        b.face(x, f, z, "-y", blood_col(x, z, 7), "cloth")


# ---------------------------------------------------------------------------
# Point faible : la cage thoracique ouverte et le CŒUR MUTANT (os chest),
# à gauche du centre, z 62..69 (centre ~1,64 m), en saillie de deux cubes.
# ---------------------------------------------------------------------------

def build_heart(b):
    # Plaie : blouse et poitrine arrachées sur x -2..8, z 60..71 (bord
    # irrégulier) jusqu'à f 4 ; fond de chair sombre.
    for x in range(-2, 9):
        for z in range(60, 72):
            ex = min(x + 2, 8 - x)
            ez = min(z - 60, 71 - z)
            if ex + ez == 0 or (ex + ez == 1 and vx.noise((x, 0, z), 311) > 0.4):
                continue
            for f in (5, 6):
                b.drop(x, f, z)
            if b.get(x, 4, z) is not None:
                b.put(x, 4, z, "wound", "chest", "cavity",
                      WOUND_DARK if vx.noise((x // 2, 0, z // 2), 312) > 0.45 else FLESH)
    # Bords de la plaie : blouse déchirée imbibée, chair à vif sur la tranche.
    fr = b.fronts(("gown",))
    for x in range(-4, 11):
        for z in range(58, 74):
            if -2 <= x <= 8 and 60 <= z <= 71:
                continue
            f = fr.get((x, z))
            if f is None:
                continue
            d = max(-3 - x if x < -2 else (x - 9 if x > 8 else -1), 59 - z if z < 60 else (z - 72 if z > 71 else -1))
            if d <= 0:
                b.face(x, f, z, "-y", BLOOD_WET if vx.noise((x, 1, z), 313) > 0.5 else BLOOD, "wound")
            elif vx.noise((x, 2, z), 314) > 0.55:
                b.face(x, f, z, "-y", BLOOD, "cloth")
    # Côtes : barres d'os qui partent des bords, cassées au milieu.
    for z in (61, 63, 66, 69):
        for x in (-2, -1, 0) if z != 66 else (-2, -1):
            b.put(x, 5, z, "bone", "chest", "ribs", RIB if x != 0 else vx.tone(RIB, 0.85))
        for x in (6, 7, 8) if z != 63 else (7, 8):
            b.put(x, 5, z, "bone", "chest", "ribs", RIB if x != 6 else vx.tone(RIB, 0.85))
    for x, z in ((-1, 70), (7, 70), (0, 61), (6, 61)):
        b.put(x, 6, z, "bone", "chest", "ribs", vx.tone(RIB, 0.92))  # éclats en saillie
    # Le cœur : 7 × 8 cubes, 4 de profondeur (f 5..8), bombé au centre.
    rows = {62: (2, 5), 63: (1, 6), 64: (0, 7), 65: (0, 7), 66: (0, 7), 67: (0, 7), 68: (0, 7), 69: (1, 3)}
    for z, (xa, xb) in rows.items():
        for x in range(xa, xb):
            if z == 69 and x not in (1, 2, 5):
                continue
            for f in (5, 6, 7):
                col = HEART
                if vx.noise((x // 2, f, z // 2), 321) > 0.7:
                    col = HEART_DARK
                b.put(x, f, z, "heart", "chest", "heart", col)
            if 1 <= x <= 5 and 63 <= z <= 68:
                b.put(x, 8, z, "heart", "chest", "heart",
                      HEART_LIGHT if (x, z) in ((2, 67), (3, 67), (2, 66)) else HEART)
    b.put(5, 7, 69, "heart", "chest", "heart", HEART)
    b.put(5, 6, 69, "heart", "chest", "heart", HEART)
    # Vaisseaux : aorte (2 × 2) qui monte, veine plus fine vers la droite.
    for z in (69, 70, 71):
        for x in (1, 2):
            for f in (5, 6):
                b.put(x, f, z, "heart", "chest", "heart", HEART_DARK if z == 71 else HEART)
    for x, f, z in ((5, 6, 70), (6, 6, 70), (6, 6, 71)):
        b.put(x, f, z, "heart", "chest", "heart", HEART_DARK)
    # Veines sombres en surface (même matière : la lueur reste).
    for x, z in ((4, 65), (4, 64), (3, 64), (5, 66), (1, 66), (2, 65)):
        b.face(x, 8, z, "-y", HEART_DARK, "heart")


# ---------------------------------------------------------------------------
# Bras : longues manches (jusqu'à mi-avant-bras), avant-bras décharnés,
# gants de latex, longs doigts ; scalpel géant dans le poing droit.
# ---------------------------------------------------------------------------

def build_arms(b):
    for s, side in ((1, "l"), (-1, "r")):
        def X(a, c):
            return (a, c) if s > 0 else (-c, -a)
        arm, fore = "arm_" + side, "forearm_" + side
        x0, x1 = X(9, 15)
        b.slab(x0, x1, -4, 4, 54, 76, "cloth", arm, "sleeve_" + side, gown(61 + s), round_xy=1, round_top=1)
        b.slab(x0, x1, -4, 4, 44, 54, "cloth", fore, "sleeve_" + side, gown(63 + s), round_xy=1)
        # Ourlet de manche déchiré (marches), plus sombre dessous.
        for x in range(x0, x1):
            for f in range(-4, 4):
                if b.get(x, f, 44) is None:
                    continue
                if vx.noise((x, f // 2, 0), 65 + s) > 0.6:
                    b.drop(x, f, 44)
                    if b.get(x, f, 45) is not None:
                        b.face(x, f, 45, "-z", GOWN_DARK, "cloth")
                else:
                    b.face(x, f, 44, "-z", GOWN_DARK, "cloth")
        # Avant-bras décharné (peau) z 37..44, veines.
        xs0, xs1 = X(10, 14)
        b.slab(xs0, xs1, -3, 3, 37, 44, "skin", fore, "forearm_" + side, skin(67 + s), round_xy=1)
        xo = xs1 - 1 if s > 0 else xs0
        d = "+x" if s > 0 else "-x"
        for z in range(37, 44):
            b.face(xo, int(0.5 + 1.5 * math.sin(z * 0.9 + s)), z, d, VEIN, "skin")
        # Manchette du gant roulée, z 34..37.
        b.slab(x0, x1, -4, 4, 34, 37, "leather", fore, "glove_" + side, glove(69 + s), round_xy=1)
        for x in range(x0, x1):
            for f in range(-4, 4):
                if b.get(x, f, 36) is not None:
                    b.face(x, f, 36, "+z", vx.tone(GLOVE, 1.08), "leather")
    # Main gauche ouverte : paume z 28..34, quatre longs doigts z 22..28
    # séparés (fentes vides), pouce devant ; bouts ensanglantés.
    b.slab(10, 14, -3, 4, 28, 34, "leather", "forearm_l", "glove_l", glove(71), round_xy=1)
    for i, f in enumerate((-3, -1, 1, 3)):
        zb = 22 if f in (-1, 1) else 23
        for x in range(10, 14):
            for z in range(zb, 28):
                col = vx.tone(GLOVE, 0.92 + 0.06 * ((z // 2) % 2)) if z > zb + 1 else BLOOD
                b.put(x, f, z, "leather", "forearm_l", "glove_l", col)
            b.face(x, f, zb + 3, "-y", GLOVE_DARK, "leather")
    for z in range(27, 32):
        for x in (10, 11):
            b.put(x, 4, z, "leather", "forearm_l", "glove_l", glove(73)(x, 4, z) if z > 27 else BLOOD)
    # Poing droit serré sur le manche (x -15..-9, z 26..34), doigts en
    # fentes sur la face extérieure, pouce sur le dessus.
    b.slab(-15, -9, -3, 4, 26, 34, "leather", "forearm_r", "glove_r", glove(75), round_xy=1, round_bottom=1)
    for f in (-2, 0, 2):
        for z in range(27, 33):
            b.face(-15, f, z, "-x", GLOVE_DARK, "leather")
            b.face(-10, f, z, "+x", GLOVE_DARK, "leather")
    for f in (-2, 0, 2):
        b.face(-12, 3, 27 + f + 2, "-y", GLOVE_DARK, "leather")
    for x in (-13, -12, -11):
        for f in (1, 2, 3):
            b.put(x, f, 34, "leather", "forearm_r", "glove_r", glove(77)(x, f, 34))
    for x, f, z in ((-14, 3, 26), (-13, 3, 26), (-15, 1, 27), (-10, 3, 27)):
        if b.get(x, f, z) is not None:
            b.face(x, f, z, "-y", BLOOD, "leather")
    build_scalpel(b)


def build_scalpel(b):
    """Scalpel géant (forearm_r) : manche strié derrière le poing (f -9..-4),
    soie, lame de 22 cubes vers l'avant (f 4..25), 2 cubes d'épaisseur,
    jusqu'à 6 de haut, ventre qui remonte en marches vers la pointe."""
    bone = "forearm_r"
    xs = (-13, -12)
    # Manche plat, stries plus claires, embout.
    for f in range(-10, -3):
        for z in range(28, 32):
            col = STEEL_DARK
            if f % 2 == 0 and z in (29, 30):
                col = vx.tone(STEEL, 0.85)
            if f == -10:
                col = vx.tone(STEEL_DARK, 0.8)
            for x in xs:
                b.put(x, f, z, "metal", bone, "scalpel", col)
    # Soie qui sort du poing.
    for f in (4, 5):
        for z in (29, 30, 31):
            for x in xs:
                b.put(x, f, z, "metal", bone, "scalpel", STEEL_DARK)
    # Lame : (bas, haut) inclus par colonne.
    # Fil droit (rangée claire continue), dos qui descend en marches vers la
    # pointe : silhouette de couteau, lisible de profil.
    prof = []
    for k in range(20):
        top = 32 if k < 9 else 32 - (k - 7) // 2
        prof.append((27, max(27, top)))
    for k, (zlo, zhi) in enumerate(prof):
        f = 6 + k
        for z in range(zlo, zhi + 1):
            if z == zlo:
                col = EDGE
            elif z == zhi:
                col = vx.tone(STEEL, 0.72)
            else:
                col = STEEL
            for x in xs:
                b.put(x, f, z, "metal", bone, "scalpel", col)
    # Sang sur le fil, près du poing, et une goutte vers la pointe.
    for f, z in ((8, 27), (9, 27), (10, 27), (9, 28), (14, 27), (21, 27)):
        for x in xs:
            for d in ("-x", "+x", "-z"):
                b.face(x, f, z, d, BLOOD, "wound")
    # Gorge de la lame (ligne plus sombre le long du dos).
    for f in range(7, 18):
        for x, d in ((-13, "-x"), (-12, "+x")):
            b.face(x, f, 31, d, vx.tone(STEEL, 0.78), "metal")


# ---------------------------------------------------------------------------
# Cou, tête : visage creusé, masque déchiré, calot à pois, loupes.
# ---------------------------------------------------------------------------

def build_head(b):
    # Cou mince et long, un peu en avant (dos voûté), z 76..82.
    b.slab(-3, 3, -1, 5, 76, 82, "skin", "neck", "neck", skin(81, SKIN_DARK), round_xy=1)
    for z in range(76, 82):
        b.face(2, int(1 + math.sin(z)), z, "+x", VEIN, "skin")
    # Mâchoire (os jaw) z 78..82, menton pointu.
    b.slab(-5, 5, 4, 11, 78, 82, "skin", "jaw", "jaw", skin(83, SKIN_DARK), round_xy=2, round_bottom=1)
    # Tête (os head) z 82..91 : crâne étroit et long, visage à f = 10.
    b.slab(-6, 6, -1, 11, 82, 91, "skin", "head", "head", skin(85), round_xy=2, round_top=1)
    # Joues creuses : faces sombres sous les pommettes.
    for x in (-5, -4, 3, 4):
        for z in (82, 83):
            b.paint_front(x, z, SKIN_DARK, "skin", part="head")
    # Yeux 3 × 2 émissifs, enfoncés d'un cube sous des arcades saillantes.
    for xs in ((1, 2, 3), (-4, -3, -2)):
        for x in xs:
            for z in (86, 87):
                b.drop(x, 10, z)
                b.put(x, 9, z, "eye", "head", "eye", EYE)
    for x in list(range(0, 5)) + list(range(-5, 0)):
        b.put(x, 11, 88, "skin", "head", "brow", skin(87, SKIN_DARK)(x, 11, 88))
    for x in (-5, 4):
        b.put(x, 10, 86, "skin", "head", "head", SKIN_DARK)  # orbites creuses
        b.put(x, 10, 87, "skin", "head", "head", vx.tone(SKIN_DARK, 0.8))
    for x in (-1, 0):
        for z in (86, 87):
            b.face(x, 10, z, "-y", SKIN_LIGHT, "skin")
    # Oreilles.
    for z in (84, 85, 86):
        for f in (3, 4):
            b.put(6, f, z, "skin", "head", "ear", SKIN_DARK)
            b.put(-7, f, z, "skin", "head", "ear", SKIN_DARK)
    # Masque chirurgical (f 11) : partie haute sur la tête (nez, z 83..86),
    # partie basse sur la mâchoire (z 79..82) ; déchiré à droite (x < 0) :
    # dents du haut et du bas, bouche sombre.
    for x in range(-6, 6):
        for z in range(83, 86):
            torn = x <= -3 and z == 83
            if torn:
                continue
            col = MASK_DARK if z == 84 else vx.tone(MASK, 0.96 + 0.04 * vx.noise((x, 0, z), 89))
            b.put(x, 11, z, "cloth", "head", "mask", col)
        for z in range(79, 82):
            if x <= -2 + (82 - z) // 2 - 1 or (x == -1 and z == 81):
                continue
            col = MASK_DARK if z == 80 else vx.tone(MASK, 0.96 + 0.04 * vx.noise((x, 1, z), 89))
            b.put(x, 11, z, "cloth", "jaw", "mask", col)
    for x in (-1, 0):
        b.put(x, 12, 84, "cloth", "head", "mask", MASK)
        b.put(x, 12, 85, "cloth", "head", "mask", MASK)
    # Bords déchirés pendants.
    for x, z in ((-3, 82), (-2, 82)):
        b.put(x, 11, z, "cloth", "head", "mask", MASK_DARK)
    # Bouche déchirée : fond sombre, dents (haut : tête ; bas : mâchoire).
    for x in range(-5, 0):
        b.face(x, 10, 82, "-y", MOUTH, "wound")
        b.face(x, 10, 81, "-y", MOUTH, "wound")
        if x % 2 == 0 or x == -5:
            b.put(x, 11, 82 if x != -2 else 83, "bone", "head", "teeth", TOOTH)
        if x % 2 != 0:
            b.put(x, 11, 81, "bone", "jaw", "teeth", vx.tone(TOOTH, 0.9))
    b.put(-4, 11, 80, "bone", "jaw", "teeth", TOOTH)
    for x in (-5, -4, -3):
        b.face(x, 10, 80, "-y", FLESH, "wound")
    # Élastiques du masque jusqu'aux oreilles (faces latérales).
    for f in range(5, 11):
        for z, bone_x in ((85, (5, -6)), (82, (5, -6))):
            b.face(bone_x[0], f, z, "+x", MASK, "cloth")
            b.face(bone_x[1], f, z, "-x", MASK, "cloth")
    for f in range(5, 11):
        b.face(4, f, 81, "+x", MASK, "cloth")
    # Calot (z 88..93) : coque d'un cube autour du crâne, motif à pois.
    def cap(x, f, z):
        if (x + 2 * f + 3 * z) % 6 == 0:
            return CAP_DOT
        return vx.tone(CAP, 0.94 + 0.08 * vx.noise((x // 3, f // 3, z // 3), 91))
    b.slab(-7, 7, -2, 12, 89, 92, "cloth", "head", "cap", cap, round_xy=2)
    b.slab(-6, 6, -1, 11, 92, 93, "cloth", "head", "cap", cap, round_xy=2)
    b.slab(-7, 7, -2, 9, 87, 89, "cloth", "head", "cap", cap, round_xy=2)
    for x in range(-7, 7):
        b.face(x, 11, 89, "-z", vx.tone(CAP, 0.7), "cloth")
    # Liens du calot noués derrière.
    for x, z in ((-1, 88), (0, 88), (-1, 87), (0, 86), (-2, 86)):
        b.put(x, -3, z, "cloth", "head", "cap", CAP)
    # Loupes binoculaires relevées sur le front : bandeau d'acier, deux
    # tubes sombres en saillie.
    for x in range(-7, 7):
        if b.get(x, 11, 90) is not None and x not in (-7, 6):
            b.put(x, 12, 90, "metal", "head", "loupe", STEEL_DARK)
    for x, f in ((-7, 10), (-7, 9), (6, 10), (6, 9)):
        b.put(x - (1 if x < 0 else -1), f, 90, "metal", "head", "loupe", STEEL_DARK)
    for xs in ((1, 2, 3), (-4, -3, -2)):
        for x in xs:
            for z in (89, 90, 91):
                for f in (13, 14):
                    rim = x in (xs[0], xs[2]) or z in (89, 91)
                    b.put(x, f, z, "metal", "head", "loupe", STEEL if rim else STEEL_DARK)
            b.face(x, 14, 90, "-y", LENS, "metal")
        b.face(xs[1], 14, 90, "-y", (0.30, 0.55, 0.65), "metal")


# ---------------------------------------------------------------------------
# Ossature (RigBuilder.BONES) en cubes de 2,5 cm. Repère du modèle : y = -f - 1.
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, -0.5, 44), (0, -0.5, 51)),
    ("spine", "hips", (0, -0.5, 51), (0, -0.5, 60)),
    ("chest", "spine", (0, -0.5, 60), (0, -0.5, 76)),
    ("neck", "chest", (0, -2, 76), (0, -2, 82)),
    ("head", "neck", (0, -3, 82), (0, -3, 93)),
    ("arm_l", "chest", (12, 0, 74), (12, 0, 54)),
    ("forearm_l", "arm_l", (12, 0, 54), (12, 0, 24)),
    ("arm_r", "chest", (-12, 0, 74), (-12, 0, 54)),
    ("forearm_r", "arm_r", (-12, 0, 54), (-12, 0, 24)),
    ("thigh_l", "hips", (4.5, -0.5, 44), (4.5, -0.5, 24)),
    ("shin_l", "thigh_l", (4.5, -0.5, 24), (4.5, -0.5, 1)),
    ("thigh_r", "hips", (-4.5, -0.5, 44), (-4.5, -0.5, 24)),
    ("shin_r", "thigh_r", (-4.5, -0.5, 24), (-4.5, -0.5, 1)),
    ("jaw", "head", (0, -4.5, 81), (0, -12.5, 81)),
]


def describe():
    b = Body()
    build_legs(b)
    build_torso(b)
    build_arms(b)
    build_head(b)
    build_pocket(b)
    build_blood(b)
    build_heart(b)
    m = b.m
    for k in [k for k in m.face_color if k[:3] not in m.vox]:
        del m.face_color[k]
    for k in [k for k in m.face_mat if k[:3] not in m.vox]:
        del m.face_mat[k]
    vx.shade(m, {"+z": 1.06, "-z": 0.64, "+x": 0.88, "-x": 0.88, "-y": 1.0, "+y": 0.93}, skip_mats=("eye", "heart"))
    vx.quantize(m, {"cloth": 28, "skin": 16, "leather": 10, "metal": 8, "wound": 6, "bone": 4})
    return m


def build(use_cache=False):
    info = {}
    if use_cache and os.path.exists(CACHE):
        m = vx.load_cache(CACHE)
        info["from_cache"] = True
    else:
        m = describe()
        vx.save_cache(m, CACHE)
    ob, mi = vx.build_mesh(m, "surgeon_voxel")
    info.update(mi)
    rig = vx.build_armature("surgeon_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    info["z_range"] = (int(lo[2]), int(hi[2]))
    return m, ob, rig, info


# ---------------------------------------------------------------------------
# Planche de validation : vues, gros plans (tête, cœur), poses (armé du coup
# de scalpel, taillade, armé du lancer, opération, rugissement, mort).
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


# Repère Blender : avant -Y ; rotation +X d'un membre pendant = vers l'avant ;
# rotation +Z = le devant tourne vers la gauche du personnage (+X).
SLASH_WINDUP = [("spine", "Z", -20), ("chest", "Z", -10), ("chest", "X", -5),
                ("arm_r", "X", 150), ("arm_r", "Y", 30), ("forearm_r", "X", 50),
                ("arm_l", "X", 30), ("arm_l", "Y", -25), ("forearm_l", "X", 40), ("jaw", "X", 15)]
SLASH = [("spine", "Z", 25), ("chest", "Z", 15), ("spine", "X", 12),
         ("arm_r", "X", 85), ("arm_r", "Z", 60), ("forearm_r", "X", 15),
         ("arm_l", "X", -25), ("arm_l", "Y", -20), ("jaw", "X", 20),
         ("thigh_r", "X", 25), ("shin_r", "X", -20)]
THROW_WINDUP = [("spine", "Z", -25), ("spine", "X", -8), ("arm_r", "X", 160), ("arm_r", "Y", 20),
                ("forearm_r", "X", 110), ("arm_l", "X", 80), ("arm_l", "Z", -15), ("forearm_l", "X", 15),
                ("thigh_l", "X", 30), ("shin_l", "X", -15)]
SURGERY = [("spine", "X", 22), ("chest", "X", 15), ("neck", "X", -10), ("head", "X", 10),
           ("arm_l", "X", 55), ("arm_r", "X", 55), ("arm_l", "Z", -12), ("arm_r", "Z", 12),
           ("forearm_l", "X", 30), ("forearm_r", "X", 25)]
ROAR = [("spine", "X", -10), ("chest", "X", -8), ("neck", "X", -20), ("head", "X", -25), ("jaw", "X", 40),
        ("arm_l", "Y", -110), ("arm_r", "Y", 110), ("forearm_l", "Y", -25), ("forearm_r", "Y", 25)]
DEATH = [("spine", "X", -25), ("chest", "X", -15), ("neck", "X", -20), ("head", "X", -10), ("jaw", "X", 35),
         ("arm_l", "X", -30), ("arm_l", "Y", -35), ("arm_r", "X", -30), ("arm_r", "Y", 35),
         ("thigh_l", "X", 20), ("shin_l", "X", -35), ("thigh_r", "X", 5)]


def render_sheet(m, ob, rig, path):
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    vx.add_outline(m, "surgeon_voxel_outline", rig)
    TW, TH = 380, 560
    vx.setup_render((TW, TH))
    hm, tz = 2.7, 1.2

    def shot(name, az, el, target=(0, 0, tz), h=hm):
        return vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, target, h, el))

    row1 = [shot("front", 0, 0), shot("back", 180, 0), shot("left", 90, 0), shot("right", -90, 0),
            shot("34", 35, 10), shot("back34", 145, 10)]
    row2 = [shot("head", 25, 6, (0, -0.12, 2.15), 0.6), shot("heart", 20, 4, (0.05, -0.1, 1.64), 0.55),
            shot("scalpel", -60, 10, (-0.3, -0.3, 0.75), 0.8)]
    pose(rig, SLASH_WINDUP)
    row2.append(shot("slash_windup", -50, 6, (0, 0, 1.35), 3.0))
    rest_pose(rig)
    pose(rig, SLASH)
    row2.append(shot("slash", 20, 6))
    rest_pose(rig)
    pose(rig, THROW_WINDUP)
    row2.append(shot("throw_windup", -70, 6, (0, 0, 1.35), 3.0))
    rest_pose(rig)
    pose(rig, SURGERY)
    row3 = [shot("surgery", 60, 6)]
    rest_pose(rig)
    pose(rig, ROAR)
    row3.append(shot("roar", 15, 6, (0, 0, 1.25), 2.8))
    rest_pose(rig)
    pose(rig, DEATH)
    row3.append(shot("death", 70, 6))
    rest_pose(rig)
    row3.append(shot("34_right", -35, 10))
    row3.append(shot("top", 0, 70, (0, 0, 1.2), 2.4))
    vx.save_png(vx.sheet([row1, row2, row3], TW, TH), path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "surgeon", "surgeon_voxel.glb")
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
    print("[surgeon_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(m, ob, rig, os.path.abspath(sheet))
        print("[surgeon_voxel] planche -> %s" % sheet)
