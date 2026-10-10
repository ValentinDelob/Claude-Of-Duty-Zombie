# Chien errant contaminé CUBIQUE (GAME_CONCEPT.md § 4.19 : personnages et mobs
# en cubes de 2,5 cm ; § 4.4 : meute errante, échantillons croc / touffe de
# poils / collier). Gros chien d'environ 0,75 m au garrot (30 cubes), échappé
# d'un laboratoire d'hôpital : pelage galeux gris-brun, plaques pelées, flanc
# ouvert sur les côtes, morsure à la cuisse, oreille déchirée, bague
# d'identification jaune de laboratoire à l'oreille, collier de cuir à
# médaille, babines retroussées sur les crocs, yeux qui luisent.
#
#   sh tools/blender.sh tools/blender/dogs/dog_voxel.py [--glb FICHIER] [--sheet FICHIER.png] [--cache]
#
# Aucune planche de référence : les formes sont DÉCRITES ici, tranche par
# tranche (profils du tronc, du cou et de la tête en escaliers de cubes),
# les couleurs viennent d'une palette et d'un bruit par cube
# (voxel_lib.noise : texture « un pixel = un cube » reproductible).
# Construit avec tools/blender/voxel/voxel_lib.py, ossature du jeu
# (RigBuilder.BONES) replacée en quadrupède, comme l'animation procédurale
# des chiens (scripts/game/dogs/hellhound.gd) l'attend :
#   hips = bassin (arrière) > spine > chest (avant) > neck > head > jaw
#   arm_* / forearm_* = pattes avant ; thigh_* / shin_* = pattes arrière
# Os droits, repos « pattes pendantes », pondération rigide (chaque cube à
# 100 % sur un os). La queue est sur le bassin (pas d'os de queue).
# CACHE : cellules et couleurs de faces dans dog_voxel_cells.json (suivi par
# git, à côté du script) ; avec --cache, le modèle est relu depuis ce
# fichier, à l'identique (sans --cache, il est reconstruit et le cache
# réécrit).
#
# Repère : Z en haut, avant (museau) vers -Y, gauche du chien vers +X. Dans
# ce script, « f » est la position vers l'AVANT, en cubes, depuis l'arrière
# de la croupe (f = 0) : la cellule (x, f, z) est la cellule
# (x, y = -(f - F0) - 1, z) du modèle. F0 recentre le chien sur l'origine
# (capsule de déplacement du jeu centrée sur le tronc).
import bpy, math, os, sys
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_CHAR
CACHE = os.path.join(HERE, "dog_voxel_cells.json")
F0 = 24

# ---------------------------------------------------------------------------
# Palette (sRGB).
# ---------------------------------------------------------------------------
FUR = (0.43, 0.37, 0.30)        # gris-brun
FUR_DARK = (0.24, 0.21, 0.18)   # selle du dos, crête
FUR_LIGHT = (0.58, 0.53, 0.45)  # ventre, gorge
FUR_GREY = (0.47, 0.46, 0.43)   # mèches grises
LEG_DARK = (0.30, 0.26, 0.22)   # bas des pattes crottés
MANGE = (0.66, 0.50, 0.47)      # peau pelée (gale)
MANGE_DARK = (0.50, 0.33, 0.31)
SCAB = (0.27, 0.12, 0.09)       # croûtes
FLESH = (0.50, 0.12, 0.10)      # plaie à vif
FLESH_DARK = (0.34, 0.05, 0.05)
BONE = (0.76, 0.69, 0.56)       # côtes, crocs
TOOTH = (0.92, 0.88, 0.70)
CLAW = (0.20, 0.18, 0.16)
NOSE = (0.08, 0.07, 0.07)
GUM = (0.36, 0.10, 0.11)
TONGUE = (0.66, 0.30, 0.32)
EAR_IN = (0.62, 0.42, 0.40)
COLLAR = (0.40, 0.12, 0.08)     # cuir rouge sang usé
COLLAR_WORN = (0.30, 0.10, 0.07)
STUD = (0.66, 0.66, 0.60)
TAG = (0.74, 0.70, 0.52)        # médaille en laiton terni
LAB_TAG = (0.95, 0.78, 0.12)    # bague d'identification du laboratoire
EYE = (1.0, 0.74, 0.20)         # lueur ambre (infection)
STITCH = (0.10, 0.09, 0.08)


def cell(x, f, z):
    return (x, -(f - F0) - 1, z)


def mirror(x):
    """Cellule symétrique (gauche +X <-> droite -X)."""
    return -x - 1


# ---------------------------------------------------------------------------
# Peinture des poils : bruit par cube et grandes plaques (gale, crasse).
# ---------------------------------------------------------------------------

def _patch(x, f, z, seed, size=3):
    return vx.noise((x // size, f // size, z // size), seed)


def fur(x, f, z, base=FUR, dark=0.0, light=0.0):
    """Couleur d'un cube de poil : base, assombrie (dos) ou éclaircie
    (ventre), mèches grises et variation par cube."""
    c = base
    if dark > 0:
        c = tuple(a + (b - a) * dark for a, b in zip(c, FUR_DARK))
    if light > 0:
        c = tuple(a + (b - a) * light for a, b in zip(c, FUR_LIGHT))
    if _patch(x, f, z, 11, 2) > 0.8:
        c = tuple(a * 0.5 + b * 0.5 for a, b in zip(c, FUR_GREY))
    # Variation par blocs de 2 cubes (mèches) plus un léger grain par cube :
    # des faces voisines de même teinte se fusionnent (budget de triangles).
    k = 0.86 + 0.22 * vx.noise((x // 2, f // 2, z // 2), 3)
    if vx.noise((x, f, z), 4) > 0.82:
        k *= 0.9
    return vx.tone(c, k)


class Dog:
    """Grille du chien ; `off` (f, z) décale ce qui est décrit (tête)."""

    def __init__(self):
        self.m = vx.Model(CUBE)
        self.off = (0, 0)

    def _c(self, x, f, z):
        return cell(x, f + self.off[0], z + self.off[1])

    def put(self, x, f, z, mat, bone, part, color):
        self.m.set(*self._c(x, f, z), mat, bone, part, color)

    def get(self, x, f, z):
        return self.m.vox.get(self._c(x, f, z))

    def drop(self, x, f, z):
        self.m.vox.pop(self._c(x, f, z), None)

    def face(self, x, f, z, d, color, mat=None):
        c = self._c(x, f, z)
        self.m.face_color[(c[0], c[1], c[2], d)] = color
        if mat:
            self.m.face_mat[(c[0], c[1], c[2], d)] = mat


# ---------------------------------------------------------------------------
# Tronc : profils par tranche (f), section arrondie en escalier.
# ---------------------------------------------------------------------------

TORSO_LEN = 34


def top_z(f):
    """Dessus du dos (exclu) : croupe 27, rein un peu creusé, garrot 30."""
    if f <= 7:
        return 27
    if f <= 15:
        return 26 if 10 <= f <= 13 else 27
    if f <= 21:
        return 28 if f <= 18 else 29
    if f <= 29:
        return 30
    return {30: 29, 31: 28, 32: 27, 33: 25}[f]


def bottom_z(f):
    """Dessous : fesses, ventre levretté (rentré), poitrail profond."""
    if f <= 2:
        return 19
    if f <= 8:
        return 18
    if f <= 15:
        return [20, 21, 21, 21, 20, 19, 18][f - 9]
    if f <= 22:
        return [17, 16, 15, 15, 14, 14, 14][f - 16]
    if f <= 30:
        return 14
    return {31: 15, 32: 16, 33: 18}[f]


def half_w(f):
    """Demi-largeur (cubes) : croupe 5, rein 4, côtes 6, poitrail 5."""
    if f <= 6:
        return 5
    if f <= 14:
        return 4
    if f <= 29:
        return 6
    return 5


def torso_bone(f):
    return "hips" if f < 13 else ("spine" if f < 23 else "chest")


def build_torso(d):
    for f in range(0, TORSO_LEN):
        lo, hi, hw = bottom_z(f), top_z(f), half_w(f)
        for z in range(lo, hi):
            e = min(z - lo, hi - 1 - z)
            w = hw - (2 if e == 0 else (1 if e == 1 else 0))
            if f in (0, TORSO_LEN - 1) and w > 2:
                w -= 1
            for x in range(-w, w):
                ax = x if x >= 0 else mirror(x)
                # Selle sombre sur le dos, ventre clair dessous.
                dark = max(0.0, min(1.0, (z - (hi - 4)) / 3.0))
                light = max(0.0, min(1.0, (lo + 3 - z) / 3.0)) if f >= 15 else 0.0
                d.put(x, f, z, "cloth", torso_bone(f), "fur", fur(ax, f, z, FUR, dark * 0.9, light * 0.8))
    # Crête hérissée (poils dressés le long de l'échine, du garrot au rein).
    for f in range(13, 31, 2):
        z = top_z(f)
        for x in (-1, 0):
            if vx.noise((x, f, z), 5) > 0.25:
                d.put(x, f, z, "cloth", torso_bone(f), "fur", vx.tone(FUR_DARK, 0.9 + 0.2 * vx.noise((x, f, 0), 6)))


# ---------------------------------------------------------------------------
# Cou, tête, mâchoire.
# ---------------------------------------------------------------------------

NECK_F = range(28, 40)
# Décalage (f, z) de la tête décrite plus bas (crâne f 35..43, z 33..43 avant
# décalage) : tête portée bas et en avant, en chien qui charge.
HEAD_OFF = (3, -4)


def neck_z(f):
    """Bas et haut (exclu) du cou à la tranche f : monte à ~45°."""
    k = f - 28
    return 19 + k, 29 + k


def build_neck(d):
    for f in NECK_F:
        lo, hi = neck_z(f)
        for z in range(lo, hi):
            e = min(z - lo, hi - 1 - z)
            w = 4 - (1 if e == 0 else 0)
            for x in range(-w, w):
                if d.get(x, f, z) is not None and (f < TORSO_LEN and z < top_z(f) - 1):
                    continue  # poitrail déjà là
                ax = x if x >= 0 else mirror(x)
                dark = max(0.0, min(1.0, (z - (hi - 3)) / 2.0))
                light = max(0.0, min(1.0, (lo + 3 - z) / 3.0))
                d.put(x, f, z, "cloth", "neck", "fur", fur(ax, f, z, FUR, dark * 0.8, light * 0.7))


COLLAR_F = (34, 35)


def build_collar(d):
    """Collier de cuir épais (une rangée de cubes plus large que le cou), deux
    clous de chaque côté et médaille pendante sous la gorge."""
    for f in COLLAR_F:
        lo, hi = neck_z(f)
        for z in range(lo - 1, hi + 1):
            for x in range(-5, 5):
                inside = lo <= z < hi and -4 <= x < 4
                edge_z = z in (lo - 1, hi)
                if edge_z and not (-3 <= x < 3):
                    continue
                if not inside and not edge_z and x not in (-5, 4):
                    continue
                if inside and not (x in (-4, 3) or z in (lo, hi - 1)):
                    continue
                stud = x in (-5, 4) and f == COLLAR_F[0] and z in (lo + 3, lo + 6)
                col = STUD if stud else (COLLAR if vx.noise((x // 2, f, z // 2), 9) > 0.3 else COLLAR_WORN)
                d.put(x, f, z, "metal" if stud else "leather", "neck", "collar", col)
    # Anneau et médaille sous la gorge.
    lo, _ = neck_z(COLLAR_F[1])
    d.put(-1, COLLAR_F[1], lo - 2, "metal", "neck", "collar", STUD)
    for z in range(lo - 5, lo - 2):
        for x in (-2, -1, 0) if z < lo - 3 else (-1,):
            d.put(x, COLLAR_F[1], z, "metal", "neck", "collar", TAG if z > lo - 5 else vx.tone(TAG, 0.8))


SKULL_F = range(35, 44)


def build_head(d):
    # Crâne : f 35..43, z 33..44 ; arrondi en escalier en haut et en bas.
    for f in SKULL_F:
        lo, hi = 33, 44
        if f == 35:
            lo, hi = 35, 43
        if f >= 42:
            hi = 43
        for z in range(lo, hi):
            e_top = hi - 1 - z
            w = 5
            if e_top == 0:
                w = 3
            elif e_top == 1:
                w = 4
            if z == lo:
                w = 4
            for x in range(-w, w):
                ax = x if x >= 0 else mirror(x)
                dark = max(0.0, min(1.0, (z - 40) / 3.0))
                light = 0.6 if z <= 34 else 0.0
                d.put(x, f, z, "cloth", "head", "fur", fur(ax, f, z, FUR, dark * 0.7, light))
    # Joues (bas de la face, sous les yeux).
    for f in range(41, 44):
        for z in range(34, 37):
            for x in (-5, 4):
                d.put(x, f, z, "cloth", "head", "fur", fur(x if x >= 0 else mirror(x), f, z, FUR, 0, 0.3))
    # Museau : f 44..51, z 35..41, plus étroit au bout.
    for f in range(44, 52):
        hi = 41 if f < 47 else 40
        w = 3 if f < 50 else 2
        for z in range(35, hi):
            ww = w - (1 if z == hi - 1 else 0)
            for x in range(-ww, ww):
                ax = x if x >= 0 else mirror(x)
                d.put(x, f, z, "cloth", "head", "fur", fur(ax, f, z, FUR, 0.3 if z >= hi - 1 else 0.0, 0.35 if z == 35 else 0.0))
    # Truffe (bout du museau, un cube en saillie) et narines.
    for z in (38, 39):
        for x in range(-2, 2):
            d.put(x, 52, z, "leather", "head", "nose", NOSE)
    for x in range(-2, 2):
        d.put(x, 51, 39, "leather", "head", "nose", NOSE)
    d.face(-2, 52, 38, "-y", (0.02, 0.02, 0.02))
    d.face(1, 52, 38, "-y", (0.02, 0.02, 0.02))
    # Arcades sourcilières en saillie, yeux qui luisent dans l'ombre.
    for x in list(range(-5, -2)) + list(range(2, 5)):
        d.put(x, 44, 42, "cloth", "head", "fur", vx.tone(FUR_DARK, 0.95))
    for x in (2, 3, -4, -3):
        for z in (40, 41):
            d.put(x, 43, z, "eye", "head", "eye", EYE)
    # Babines retroussées : gencive et rangée de dents sous le museau.
    for f in range(44, 52):
        w = 3 if f < 50 else 2
        for x in (-w, w - 1):
            d.put(x, f, 34, "bone", "head", "teeth", TOOTH if (f % 2 == 0) else vx.tone(TOOTH, 0.82))
        if f >= 50:
            for x in range(-w + 1, w - 1):
                d.put(x, f, 34, "bone", "head", "teeth", TOOTH)
        for x in (-w, w - 1):
            d.put(x, f, 35, "wound", "head", "gum", GUM)
    # Crocs (canines) qui descendent le long de la mâchoire.
    for x in (-3, 2):
        for z in (32, 33):
            d.put(x, 49, z, "bone", "head", "teeth", TOOTH if z == 33 else BONE)


def build_jaw(d):
    """Mâchoire inférieure (os jaw : pivot à l'arrière, sous le crâne)."""
    for f in range(38, 51):
        w = 3 if f < 44 else 2
        for z in range(31, 34):
            for x in range(-w, w):
                ax = x if x >= 0 else mirror(x)
                inner = z == 33 and -w < x < w - 1 and f >= 42
                if inner:
                    col = TONGUE if -1 <= x < 1 else GUM
                    d.put(x, f, z, "wound", "jaw", "mouth", col)
                else:
                    d.put(x, f, z, "cloth", "jaw", "fur", fur(ax, f, z, FUR, 0.0, 0.7 if z == 31 else 0.3))
    # Dents du bas (crocs inférieurs pointés vers le haut, devant).
    for x in (-2, 1):
        d.put(x, 48, 34, "bone", "jaw", "teeth", TOOTH)
    for x in range(-1, 1):
        d.put(x, 50, 33, "bone", "jaw", "teeth", TOOTH)
    # Langue qui pend un peu sur le côté.
    d.put(0, 50, 32, "wound", "jaw", "mouth", TONGUE)
    d.put(0, 51, 32, "wound", "jaw", "mouth", vx.tone(TONGUE, 0.9))
    d.put(0, 51, 31, "wound", "jaw", "mouth", vx.tone(TONGUE, 0.8))


def build_ears(d):
    # Oreille gauche (+X) dressée, pointue, bague jaune de laboratoire.
    rows = [(44, 46, range(2, 5), range(37, 40)), (46, 48, range(2, 4), range(37, 40)),
            (48, 50, range(3, 4), range(38, 39))]
    for z0, z1, xs, fs in rows:
        for z in range(z0, z1):
            for x in xs:
                for f in fs:
                    d.put(x, f, z, "cloth", "head", "ear", fur(x, f, z, FUR, 0.6))
    for z in range(44, 48):
        for x in (2, 3):
            if z < 46 or x == 2:
                d.face(x, 39, z, "-y", EAR_IN, "skin")
    d.put(4, 38, 45, "leather", "head", "labtag", LAB_TAG)
    d.put(5, 38, 45, "leather", "head", "labtag", LAB_TAG)
    d.put(5, 38, 44, "leather", "head", "labtag", vx.tone(LAB_TAG, 0.85))
    # Oreille droite (-X) déchirée, retombée sur le côté (encoche mordue).
    for z in range(44, 46):
        for x in range(-5, -2):
            for f in range(37, 40):
                d.put(x, f, z, "cloth", "head", "ear", fur(mirror(x), f, z, FUR, 0.6))
    for z in range(40, 44):
        for f in range(37, 40):
            if z == 41 and f == 38:
                continue  # encoche
            d.put(-6, f, z, "cloth", "head", "ear", fur(5, f, z, FUR, 0.5))
    d.put(-6, 37, 40, "wound", "head", "ear", SCAB)
    d.put(-6, 39, 41, "wound", "head", "ear", FLESH_DARK)


# ---------------------------------------------------------------------------
# Pattes (gauche : +X ; droite : miroir).
# ---------------------------------------------------------------------------

def leg_color(x, f, z, lo_dark=8):
    ax = x if x >= 0 else mirror(x)
    k = max(0.0, min(1.0, (lo_dark - z) / 5.0))
    base = tuple(a + (b - a) * k for a, b in zip(FUR, LEG_DARK))
    return fur(ax, f, z, base)


def build_front_leg(d, side):
    s = "l" if side > 0 else "r"

    def X(x):
        return x if side > 0 else mirror(x)

    # Épaule et bras (os arm) : plaque d'épaule sur le flanc, coude sous le poitrail.
    for z in range(12, 25):
        if z >= 20:
            fs, xs = range(25, 32), range(4, 6)
        elif z >= 16:
            fs, xs = range(26, 32), range(4, 6) if z >= 17 else range(2, 6)
        else:
            fs, xs = range(27, 31), range(2, 6)
        for f in fs:
            for x in xs:
                d.put(X(x), f, z, "cloth", "arm_" + s, "fur", fur(x, f, z, FUR, 0.0, 0.15))
    # Coude en saillie vers l'arrière.
    for z in (12, 13):
        d.put(X(4), 26, z, "cloth", "arm_" + s, "fur", fur(4, 26, z, FUR_DARK))
    # Avant-bras (os forearm) : patte fine, carpe, paturon, pied griffu.
    for z in range(3, 12):
        for f in range(28, 31):
            for x in range(2 if z >= 8 else 3, 6):
                d.put(X(x), f, z, "cloth", "forearm_" + s, "fur", leg_color(x, f, z))
    for f in range(28, 32):
        for x in range(3, 6):
            d.put(X(x), f, 2, "cloth", "forearm_" + s, "fur", leg_color(x, f, 2))
    for f in range(28, 33):
        for x in range(2, 6):
            for z in (0, 1):
                if z == 1 and f == 32:
                    continue
                d.put(X(x), f, z, "cloth", "forearm_" + s, "paw", vx.tone(LEG_DARK, 0.85 + 0.2 * vx.noise((x // 2, f // 2, z), 4)))
    for x in range(2, 6):
        d.put(X(x), 33, 0, "bone", "forearm_" + s, "claw", CLAW)


def build_hind_leg(d, side):
    s = "l" if side > 0 else "r"

    def X(x):
        return x if side > 0 else mirror(x)

    # Cuisse (os thigh) : jambon musclé, fesse au ras de la croupe.
    for z in range(13, 26):
        if z >= 19:
            fs, xs = range(0, 10), range(3, 6)
        elif z >= 15:
            fs, xs = range(1, 10), range(1, 6)
        else:
            fs, xs = range(4, 10), range(2, 6)
        for f in fs:
            for x in xs:
                # Arêtes extérieures de la cuisse arrondies en escalier.
                if x == 5 and (z in (13, 25) or f in (fs[0], fs[-1])):
                    continue
                if x == 5 and z == 24 and f in (fs[1], fs[-2]):
                    continue
                d.put(X(x), f, z, "cloth", "thigh_" + s, "fur", fur(x, f, z, FUR, 0.15, 0.0))
    # Jambe (os shin) : tibia vers l'arrière, jarret pointu, canon, pied.
    for z in range(9, 13):
        for f in range(5, 9):
            for x in range(2, 5):
                d.put(X(x), f, z, "cloth", "shin_" + s, "fur", leg_color(x, f, z))
    for z in range(6, 9):
        for f in range(2, 6):
            for x in range(2, 5):
                d.put(X(x), f, z, "cloth", "shin_" + s, "fur", leg_color(x, f, z))
    d.put(X(3), 1, 7, "cloth", "shin_" + s, "fur", leg_color(3, 1, 7))  # pointe du jarret
    for z in range(2, 6):
        for f in range(3, 6):
            for x in range(2, 5):
                d.put(X(x), f, z, "cloth", "shin_" + s, "fur", leg_color(x, f, z))
    for f in range(3, 9):
        for x in range(2, 6):
            for z in (0, 1):
                if z == 1 and f == 8:
                    continue
                d.put(X(x), f, z, "cloth", "shin_" + s, "paw", vx.tone(LEG_DARK, 0.85 + 0.2 * vx.noise((x // 2, f // 2, z), 4)))
    for x in range(2, 6):
        d.put(X(x), 9, 0, "bone", "shin_" + s, "claw", CLAW)


def build_tail(d):
    """Queue pendante et pelée (liée au bassin)."""
    path = [(-1, 24, 27), (-2, 23, 26), (-3, 22, 25), (-4, 21, 24), (-5, 19, 23), (-6, 17, 21),
            (-7, 15, 19)]
    for f, z0, z1 in path:
        for z in range(z0, z1):
            for x in (-1, 0):
                bald = (f == -7 and z < 17) or (f == -4 and x == 0)
                col = vx.tone(MANGE, 0.85 + 0.2 * vx.noise((x, f, z), 8)) if bald else fur(x if x >= 0 else 0, f, z, FUR, 0.5)
                d.put(x, f, z, "skin" if bald else "cloth", "hips", "tail", col)


# ---------------------------------------------------------------------------
# Plaies, gale, cicatrices.
# ---------------------------------------------------------------------------

def outer_cells(d, parts=("fur",)):
    """Cubes de poil en surface (au moins un voisin vide)."""
    out = []
    for c, v in d.m.vox.items():
        if v.part not in parts:
            continue
        for n in vx.DIRS.values():
            if (c[0] + n[0], c[1] + n[1], c[2] + n[2]) not in d.m.vox:
                out.append(c)
                break
    return out


def build_wounds(d):
    def blob(f, z, cf, cz, rf, rz, seed, tilt=0.0):
        """Tache irrégulière : ellipse (inclinée de `tilt`) au bord rongé par
        le bruit."""
        a, b = f - cf, z - cz
        a, b = a + tilt * b, b - tilt * a
        q = (a / rf) ** 2 + (b / rz) ** 2
        return q + 0.5 * (vx.noise((f, z, seed), seed) - 0.5) < 1.0

    # Flanc gauche ouvert sur les côtes (x = 5 : couche extérieure du thorax) :
    # bord déchiré en croûtes, chair à vif au fond, côtes de longueurs inégales
    # (une cassée).
    ribs = {17: range(20, 26), 19: range(19, 25), 21: range(22, 25)}
    for f in range(14, 26):
        for z in range(17, 28):
            if not blob(f, z, 19.5, 22.5, 4.4, 2.9, 31, 0.45):
                continue
            v = d.get(5, f, z)
            if v is None:
                continue
            inner = all(blob(f + a, z + b, 19.5, 22.5, 4.4, 2.9, 31, 0.45) for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if not inner:
                d.put(5, f, z, "wound", v.bone, "wound", SCAB if vx.noise((f, z, 0), 2) > 0.45 else FLESH_DARK)
                continue
            d.drop(5, f, z)
            w = d.get(4, f, z)
            if w is not None:
                d.put(4, f, z, "wound", w.bone, "wound", FLESH if vx.noise((f, z, 1), 12) > 0.4 else FLESH_DARK)
            if f in ribs and z in ribs[f]:
                d.put(5, f, z, "bone", v.bone, "ribs", BONE if z != ribs[f][0] else vx.tone(BONE, 0.85))
    # Morsure à la cuisse droite (x = -6 : extérieur de la cuisse).
    for f in range(1, 10):
        for z in range(18, 26):
            v = d.get(-6, f, z)
            if v is None or not blob(f, z, 5.0, 21.5, 2.8, 2.4, 41):
                continue
            if blob(f, z, 5.0, 21.5, 1.7, 1.4, 42):
                d.drop(-6, f, z)
                d.put(-5, f, z, "wound", v.bone, "wound", FLESH if vx.noise((f, z, 2), 5) > 0.45 else FLESH_DARK)
            else:
                d.put(-6, f, z, "wound", v.bone, "wound", SCAB if vx.noise((f, z, 3), 6) > 0.3 else FLESH_DARK)
    # Épaule rasée et recousue (incision de laboratoire) sur l'épaule droite.
    for f in range(26, 32):
        for z in range(19, 25):
            v = d.get(-6, f, z)
            if v is None:
                continue
            stitch = f == 28 or (z in (20, 22) and f in (27, 29))
            d.put(-6, f, z, "skin", v.bone, "shaved", STITCH if stitch else vx.tone(MANGE, 0.95 + 0.1 * vx.noise((f, z, 0), 1)))
    # Gale : plaques pelées sur le pelage (grandes taches du bruit), et quelques
    # touffes arrachées (un cube en creux).
    for c in outer_cells(d):
        v = d.m.vox[c]
        x, y, z = c
        f = -(y + 1) + F0
        if v.bone in ("head", "jaw") or v.bone.startswith(("forearm", "shin")):
            continue
        # Deux échelles de bruit décalées : taches aux bords irréguliers.
        p = 0.55 * _patch(x, f, z, 21, 3) + 0.45 * _patch(x + 1, f + 1, z, 22, 2)
        if p > 0.74:
            col = MANGE if vx.noise(c, 13) > 0.3 else MANGE_DARK
            if vx.noise(c, 14) > 0.85:
                col = SCAB
            v.mat, v.part, v.color = "skin", "mange", vx.tone(col, 0.9 + 0.15 * vx.noise(c, 15))
        elif p < 0.06:
            v.color = vx.tone(v.color, 0.7)


# ---------------------------------------------------------------------------
# Modèle complet, ossature.
# ---------------------------------------------------------------------------

def build_model():
    d = Dog()
    build_torso(d)
    build_neck(d)
    d.off = HEAD_OFF
    build_head(d)
    build_jaw(d)
    build_ears(d)
    d.off = (0, 0)
    for side in (1, -1):
        build_front_leg(d, side)
        build_hind_leg(d, side)
    build_tail(d)
    build_collar(d)
    build_wounds(d)
    m = d.m
    # Faces des yeux et de la truffe : couleur pure, émissive (yeux).
    vx.shade(m, {"+z": 1.07, "-z": 0.6, "+x": 0.88, "-x": 0.88, "-y": 1.0, "+y": 0.93}, skip_mats=("eye",))
    vx.quantize(m, {"cloth": 18, "skin": 8, "wound": 6})
    return m


def B(x, f, z):
    """Point d'articulation (coordonnées de bord de cube) -> repère du modèle."""
    return (x, -(f - F0), z)


BONES = [
    ("hips", None, B(0, 6, 23), B(0, 13, 23)),
    ("spine", "hips", B(0, 13, 23), B(0, 23, 23)),
    ("chest", "spine", B(0, 23, 23), B(0, 31, 23)),
    ("neck", "chest", B(0, 31, 26), B(0, 31, 33)),
    ("head", "neck", B(0, 39, 32), B(0, 39, 40)),
    ("arm_l", "chest", B(4, 29, 22), B(4, 29, 12)),
    ("forearm_l", "arm_l", B(4, 29, 12), B(4, 29, 0)),
    ("arm_r", "chest", B(-4, 29, 22), B(-4, 29, 12)),
    ("forearm_r", "arm_r", B(-4, 29, 12), B(-4, 29, 0)),
    ("thigh_l", "hips", B(3.5, 6, 22), B(3.5, 6, 13)),
    ("shin_l", "thigh_l", B(3.5, 7, 13), B(3.5, 7, 0)),
    ("thigh_r", "hips", B(-3.5, 6, 22), B(-3.5, 6, 13)),
    ("shin_r", "thigh_r", B(-3.5, 7, 13), B(-3.5, 7, 0)),
    # Mâchoire : charnière en haut à l'arrière de la mâchoire ; ouverture vers le bas.
    ("jaw", "head", B(0, 41, 30), B(0, 47, 30)),
]


def build(use_cache=False):
    info = {}
    if use_cache and os.path.exists(CACHE):
        m = vx.load_cache(CACHE)
        info["from_cache"] = True
    else:
        m = build_model()
        vx.save_cache(m, CACHE)
    ob, mi = vx.build_mesh(m, "dog_voxel")
    info.update(mi)
    rig = vx.build_armature("dog_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    by_part = {}
    for v in m.vox.values():
        by_part[v.part] = by_part.get(v.part, 0) + 1
    info["cells_by_part"] = by_part
    return m, ob, rig, info


# ---------------------------------------------------------------------------
# Poses et planche de validation (face, profil, trois-quarts, course, bond).
# ---------------------------------------------------------------------------

def _rot(rig, name, axis, deg):
    pb = rig.pose.bones[name]
    bpy.context.view_layer.update()
    mw = pb.matrix.copy()
    loc = mw.translation.copy()
    r = Matrix.Rotation(math.radians(deg), 4, axis) @ mw
    r.translation = loc
    pb.matrix = r
    bpy.context.view_layer.update()


def pose(rig, rots):
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for name, axis, deg in rots:
        _rot(rig, name, axis, deg)
    bpy.ops.object.mode_set(mode="OBJECT")


def rest_pose(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


# Galop (temps de suspension, pattes rassemblées) et bond de morsure ; angles
# en degrés autour de l'axe latéral X (positif : vers l'arrière).
RUN = [("hips", "X", -4), ("arm_l", "X", -38), ("forearm_l", "X", 12), ("arm_r", "X", 30),
       ("forearm_r", "X", 55), ("thigh_l", "X", 36), ("shin_l", "X", 10), ("thigh_r", "X", -30),
       ("shin_r", "X", 25), ("neck", "X", -12), ("head", "X", 10)]
LUNGE = [("hips", "X", 22), ("arm_l", "X", -70), ("forearm_l", "X", 20), ("arm_r", "X", -62),
         ("forearm_r", "X", 25), ("thigh_l", "X", 45), ("shin_l", "X", -10), ("thigh_r", "X", 40),
         ("shin_r", "X", -8), ("neck", "X", -20), ("head", "X", 12), ("jaw", "X", 30)]


def render_sheet(m, rig, path):
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    vx.add_outline(m, "dog_voxel_outline", rig)
    TW, TH = 520, 440
    vx.setup_render((TW, TH))
    hm = 1.6
    tz = 0.55
    shots = [("front", 0, 0), ("left", 90, 0), ("right", -90, 0), ("34", 35, 12), ("back34", 150, 12)]
    tiles = []
    for name, az, el in shots:
        tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, (0, -0.09, tz), hm, el)))
    pose(rig, RUN)
    tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, "run.png"), 90, (0, -0.09, tz), hm, 0)))
    tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, "run34.png"), 35, (0, -0.09, tz), hm, 12)))
    rest_pose(rig)
    pose(rig, LUNGE)
    tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, "lunge.png"), 60, (0, -0.2, tz + 0.1), hm, 8)))
    rest_pose(rig)
    # Gros plan de la tête (trois-quarts face).
    tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, "head.png"), 25, (0, -0.58, 0.86), 0.55, 10)))
    rows = [tiles[0:3], tiles[3:6], tiles[6:9]]
    vx.save_png(vx.sheet(rows, TW, TH), path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "dogs", "dog_voxel.glb")
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
    print("[dog_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(m, rig, os.path.abspath(sheet))
        print("[dog_voxel] planche -> %s" % sheet)
