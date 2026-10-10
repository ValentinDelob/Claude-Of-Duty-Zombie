# Décors CUBIQUES, famille LUMINAIRES (lot 3 de docs/VOXEL_DECOR_PLAN.md) :
# objets des luminaires de l'éditeur de cartes (MapCatalog.LIGHTS), cubes de
# 5 cm, tools/blender/voxel_props/common.py (conventions, export, planches).
# La lumière elle-même (OmniLight3D, courant, grésillement) reste posée par
# le jeu (MeshMapBuilder._fixture_lamp) au même endroit ; le modèle n'en est
# que le support, ses parties lumineuses en matière « glow » (faces
# émissives). Aucune ombre (type « ns ») : l'abat-jour ne masque pas sa lampe.
#
# Origines (EditorPrefabs.fixture, MapLayoutExport._fixture) :
#   - plafond : sous le plafond, le modèle descend (cellules z < 0) ; la
#     lumière est à `drop` sous le plafond ;
#   - mur : sur la face du mur à la hauteur de la lumière (cellules y < 0 :
#     vers la pièce) ; la lumière est à 0,2 m du mur ;
#   - sol : au sol (ou sur le meuble), la lumière à `y` au-dessus.
#
#   sh tools/blender.sh tools/blender/voxel_props/luminaires.py [ids...] [--sheet DOSSIER] [--before DOSSIER]
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import voxel_lib as vx  # noqa: E402
from effets import ellipse, ring_xy  # noqa: E402


def square(m, x0, x1, y0, y1, z, mat, base, seed, amp=0.03, cut=False, hollow=False):
    """Couche z du rectangle [x0, x1) × [y0, y1) : pleine, coins abattus
    (`cut`) ou creuse (`hollow` : bord d'un cube seulement)."""
    for x in range(x0, x1):
        for y in range(y0, y1):
            corner = x in (x0, x1 - 1) and y in (y0, y1 - 1)
            if cut and corner:
                continue
            if hollow and not (x in (x0, x1 - 1) or y in (y0, y1 - 1)):
                continue
            m.set(x, y, z, mat, color=C.grain((x, y, z), base, seed, amp, 2))


def paint_inside(m, cells, inside, color):
    """Peint en `color` les faces des cellules tournées vers une cellule
    vide de `inside` (intérieur d'un abat-jour)."""
    for c in cells:
        for d, n in vx.DIRS.items():
            nb = (c[0] + n[0], c[1] + n[1], c[2] + n[2])
            if nb in inside and nb not in m.vox:
                m.face_color[(c[0], c[1], c[2], d)] = color


def rose(m, z=-1, half=1):
    """Rosace au plafond (porcelaine), (2·half)² cubes."""
    square(m, -half, half, -half, half, z, "stone", C.col("porcelain"), 300)


def cord(m, z0, z1, x=0, y=-1):
    """Fil d'alimentation (un cube) de z0 à z1 (exclu)."""
    for z in range(z0, z1):
        m.set(x, y, z, "rubber", color=C.col("rubber", 1.5 if z % 2 else 1.3))


# ------------------------------------------------------------------ plafond

def ampoule():
    """Ampoule nue au bout de son fil (drop 0,75 m) : rosace, fil, douille
    de laiton, ampoule de 0,1 m (glow) centrée à 0,75 m sous le plafond."""
    m = vx.Model(C.CUBE)
    rose(m)
    cord(m, -13, -1)
    square(m, -1, 1, -1, 1, -14, "metal", C.col("brass", 0.9), 301)
    for z in (-16, -15):
        square(m, -1, 1, -1, 1, z, "glow", C.col("bulb"), 302, amp=0.0)
    # Culot plus clair sous la douille, bas de l'ampoule plus chaud.
    for x in (-1, 0):
        for y in (-1, 0):
            m.face_color[(x, y, -16, "-z")] = C.col("flame_core")
    return m
ampoule.kind = "ns"


def suspension():
    """Suspension d'hôpital (drop 0,7 m) : rosace, fil, abat-jour d'émail
    vert en escalier (0,4 m de large, intérieur blanc), ampoule (glow)
    centrée à 0,7 m sous le plafond."""
    m = vx.Model(C.CUBE)
    rose(m)
    cord(m, -11, -1)
    enamel = C.col("enamel_green")
    square(m, -1, 1, -1, 1, -11, "metal", enamel, 310)
    square(m, -2, 2, -2, 2, -12, "metal", enamel, 311)
    square(m, -3, 3, -3, 3, -13, "metal", enamel, 312, hollow=True)
    square(m, -4, 4, -4, 4, -14, "metal", enamel, 313, hollow=True)
    square(m, -4, 4, -4, 4, -15, "metal", enamel, 314, hollow=True)
    # Douille et ampoule.
    square(m, -1, 1, -1, 1, -13, "metal", C.col("brass", 0.8), 315)
    for z in (-15, -14):
        square(m, -1, 1, -1, 1, z, "glow", C.col("bulb"), 316, amp=0.0)
    # Intérieur blanc, bord bas cerclé de métal sombre.
    shade = [c for c, v in m.vox.items() if v.mat == "metal" and c[2] <= -12]
    # Creux de l'abat-jour (sous la couche pleine, dans chaque anneau).
    inside = {(x, y, -13) for x in range(-2, 2) for y in range(-2, 2)}
    inside |= {(x, y, z) for x in range(-3, 3) for y in range(-3, 3) for z in (-15, -14)}
    paint_inside(m, shade, inside, C.col("paint_white", 0.95))
    for x, y in ring_xy(-4, 4, -4, 4):
        m.face_color[(x, y, -15, "-z")] = C.col("metal_dark", 1.2)
    return m
suspension.kind = "ns"


def neon():
    """Réglette néon (drop 0,15 m) : boîtier blanc de 1,3 × 0,2 m contre le
    plafond, deux tubes fluorescents de 1,2 m (glow), embouts gris."""
    m = vx.Model(C.CUBE)
    square(m, -13, 13, -2, 2, -1, "metal", C.col("paint_white", 0.92), 320, amp=0.02)
    for x in (-13, 12):
        square(m, x, x + 1, -2, 2, -2, "metal", C.col("steel", 0.8), 321)
    for y in (-2, 1):
        for x in range(-12, 12):
            m.set(x, y, -2, "glow", color=C.col("neon_white"))
    # Tôle entre les tubes : réflecteur.
    for x in range(-12, 12):
        for y in (-1, 0):
            m.face_color[(x, y, -1, "-z")] = C.col("paint_white", 1.05)
    return m
neon.kind = "ns"


def _rot90(c, k):
    """Cellule (x, y) tournée de k quarts de tour autour de l'axe (0, 0)
    (coin de la grille)."""
    x, y = c
    for _ in range(k % 4):
        x, y = -y - 1, x
    return x, y


def lustre():
    """Lustre de laiton (drop 1,1 m, à sa taille finale) : rosace, chaîne
    de 0,6 m, fût à vases, couronne haute à 4 bougies, anneau de 0,7 m à
    8 bougies (flammes glow), pampilles de verre ; 0,7 m de large, 1,5 m."""
    m = vx.Model(C.CUBE)
    brass = C.col("brass")
    square(m, -2, 2, -2, 2, -1, "metal", brass, 330, cut=True)
    # Chaîne (2 × 2), maillons alternés clair / sombre.
    for z in range(-10, -1):
        square(m, -1, 1, -1, 1, z, "metal", C.col("brass", 1.1 if z % 2 else 0.7), 331, amp=0.0)
    # Fût : chapiteau, vase, nœud, culot en escalier.
    square(m, -2, 2, -2, 2, -11, "metal", brass, 332, cut=True)
    for z in range(-26, -11):
        square(m, -1, 1, -1, 1, z, "metal", brass, 333)
    for z in (-14, -15):
        square(m, -2, 2, -2, 2, z, "metal", brass, 334, cut=True)
    for z in range(-20, -17):
        square(m, -2, 2, -2, 2, z, "metal", C.col("brass", 0.9), 335)
    square(m, -3, 3, -3, 3, -21, "metal", brass, 336, cut=True)
    for z in (-23, -24):
        square(m, -2, 2, -2, 2, z, "metal", brass, 337, cut=True)
    # Couronne haute (z -15) : rayons sur les axes, 4 bougies.
    for k in range(4):
        for r in range(1, 4):
            m.set(*_rot90((r, 0), k), -15, "metal", color=brass)
            m.set(*_rot90((r, -1), k), -15, "metal", color=brass)
        x, y = _rot90((4, 0), k)
        m.set(x, y, -15, "metal", color=C.col("brass", 0.85))
        m.set(x, y, -14, "stone", color=C.col("wax"))
        m.set(x, y, -13, "glow", color=C.col("flame_core"))
    # Anneau principal (z -21) : rayon 6 à 7 cubes, 4 rayons, 8 bougies.
    for x, y in ellipse(7.2, 7.2):
        if math.hypot(x + 0.5, y + 0.5) >= 5.6:
            m.set(x, y, -21, "metal", color=C.grain((x, y, -21), brass, 338, 0.04, 2))
    for k in range(4):
        for r in range(3, 6):
            m.set(*_rot90((r, 0), k), -21, "metal", color=brass)
            m.set(*_rot90((r, -1), k), -21, "metal", color=brass)
    for k in range(4):
        for cell in ((6, 0), (4, 4)):
            x, y = _rot90(cell, k)
            m.set(x, y, -21, "metal", color=C.col("brass", 0.85))
            m.set(x, y, -20, "metal", color=C.col("brass", 1.1))
            m.set(x, y, -19, "stone", color=C.col("wax"))
            m.set(x, y, -18, "glow", color=C.col("flame_core" if (k + cell[1]) % 2 else "bulb"))
    # Pampilles de verre sous l'anneau, entre les bougies.
    for k in range(4):
        for cell in ((6, 2), (2, 6)):
            x, y = _rot90(cell, k)
            if (x, y, -21) not in m.vox:
                m.set(x, y, -21, "metal", color=brass)
            m.set(x, y, -22, "glass", color=C.col("paint_white", 1.05))
            m.set(x, y, -23, "glass", color=C.col("water_glint", 1.4))
    # Goutte de cristal sous le fût.
    square(m, -1, 1, -1, 1, -27, "glass", C.col("water_glint", 1.4), 339, amp=0.0)
    m.set(0, 0, -28, "glass", color=C.col("paint_white", 1.05))
    # Chaîne rallongée de 0,1 m : flammes de l'anneau à 0,95-1,0 m sous le
    # plafond, juste au-dessus de la lumière (1,1 m).
    assert not m.face_color
    m.vox = {((c[0], c[1], c[2] - 2) if c[2] < -1 else c): v for c, v in m.vox.items()}
    for z in (-3, -2):
        square(m, -1, 1, -1, 1, z, "metal", C.col("brass", 1.1 if z % 2 else 0.7), 331, amp=0.0)
    return m
lustre.kind = "ns"


# ------------------------------------------------------------------ mur

def applique():
    """Applique murale de laiton à deux lampes (y 2,0 m) : platine contre le
    mur, bras et traverse, deux tulipes de verre dépoli éclairé (glow) à
    ±0,2 m et 0,2 m du mur, à la hauteur de la lumière ; origine sur la face
    du mur."""
    m = vx.Model(C.CUBE)
    brass = C.col("brass")
    # Platine (0,2 × 0,3 m), bord plus sombre.
    C.fill(m, -2, 2, -1, 0, -4, 2, "metal", brass, seed=340, amp=0.03, levels=2)
    for x in range(-2, 2):
        for z in range(-4, 2):
            if x in (-2, 1) or z in (-4, 1):
                m.face_color[(x, -1, z, "-y")] = C.col("brass", 0.75)
    # Bras (2 × 2) vers la pièce, traverse le long du mur.
    C.fill(m, -1, 1, -4, -1, -2, -1, "metal", brass, seed=341, amp=0.03, levels=2)
    C.fill(m, -4, 4, -5, -3, -2, -1, "metal", brass, seed=342, amp=0.03, levels=2)
    for sx in (-5, 3):
        # Coupelle, ampoule, tulipe de verre dépoli (ouverte en haut).
        square(m, sx, sx + 2, -5, -3, -1, "metal", C.col("brass", 0.85), 343)
        for z in (0, 1):
            square(m, sx, sx + 2, -5, -3, z, "glow", C.col("bulb"), 344, amp=0.0)
        for z in (1, 2):
            for x, y in ring_xy(sx - 1, sx + 3, -6, -2):
                if (x, y) in ((sx - 1, -6), (sx + 2, -6), (sx - 1, -3), (sx + 2, -3)) and z == 1:
                    continue
                m.set(x, y, z, "glow", color=C.col("glass_frost", 0.95 if z == 1 else 1.0))
    return m
applique.kind = "ns"


# ------------------------------------------------------------------ sol

def lampe_bureau():
    """Lampe de bureau d'infirmerie (y 0,45 m) : socle de laiton, tige,
    bras, abat-jour d'émail vert (intérieur blanc), ampoule (glow) à 0,45 m
    au-dessus du point de pose ; tient dans 0,25 × 0,2 m."""
    m = vx.Model(C.CUBE)
    brass = C.col("brass", 0.85)
    square(m, -3, 1, -2, 2, 0, "metal", brass, 350, cut=True)
    for z in range(1, 9):
        m.set(-2, -1, z, "metal", color=C.grain((-2, -1, z), brass, 351, 0.03, 2))
        m.set(-2, 0, z, "metal", color=C.grain((-2, 0, z), brass, 351, 0.03, 2))
    # Bras horizontal jusqu'à l'abat-jour.
    for x in (-2, -1):
        m.set(x, -1, 9, "metal", color=brass)
        m.set(x, 0, 9, "metal", color=brass)
    enamel = C.col("enamel_green")
    square(m, 0, 4, -2, 2, 10, "metal", enamel, 352, cut=True)
    square(m, 0, 4, -2, 2, 9, "metal", enamel, 353, hollow=True)
    square(m, 0, 4, -2, 2, 8, "metal", enamel, 354, hollow=True)
    square(m, 1, 3, -1, 1, 9, "metal", C.col("brass", 0.8), 355)
    square(m, 1, 3, -1, 1, 8, "glow", C.col("bulb"), 356, amp=0.0)
    shade = [c for c, v in m.vox.items() if v.mat == "metal" and c[2] >= 8 and c[0] >= 0]
    inside = {(x, y, z) for x in range(0, 4) for y in range(-2, 2) for z in range(8, 10)}
    paint_inside(m, shade, inside, C.col("paint_white", 0.95))
    return m
lampe_bureau.kind = "ns"


def projecteur():
    """Projecteur de chantier (y 1,7 m) : mât de 1,45 m sur quatre pieds en
    escalier (0,35 m), étrier, phare jaune de 0,4 × 0,3 m dont la vitre
    (glow) regarde vers la pièce (+Z Godot), ailettes ; dans le pavé de
    collision du catalogue (0,7 × 1,7 × 0,7 m)."""
    m = vx.Model(C.CUBE)
    dark = C.col("metal_dark", 1.2)
    # Mât (2 × 2) de 0 à 1,45 m, collier de réglage.
    for z in range(0, 29):
        square(m, -1, 1, -1, 1, z, "metal", C.col("steel", 0.9), 360)
    square(m, -2, 2, -2, 2, 14, "metal", dark, 361)
    # Pieds en escalier sur les axes, patins de caoutchouc.
    for k in range(4):
        for i in range(1, 7):
            z0 = max(0, 12 - 2 * i)
            for z in range(z0, z0 + 3):
                for cell in ((i, 0), (i, -1)):
                    x, y = _rot90(cell, k)
                    m.set(x, y, z, "metal", color=C.grain((x, y, z), dark, 362, 0.03, 2))
        for cell in ((6, 0), (6, -1)):
            x, y = _rot90(cell, k)
            m.set(x, y, 0, "rubber", color=C.col("rubber", 1.3))
    # Étrier : traverse et bras de part et d'autre du phare.
    square(m, -5, 5, -1, 1, 29, "metal", dark, 363)
    for x in (-5, 4):
        for z in range(30, 35):
            square(m, x, x + 1, -1, 1, z, "metal", dark, 364)
    # Phare : 8 × 3 × 6 cubes (1,55 à 1,85 m), vitre à l'avant (-Y).
    yellow = C.col("hazard_yellow", 0.95)
    for z in range(31, 37):
        square(m, -4, 4, -2, 1, z, "metal", yellow, 365)
    for x in range(-3, 3):
        for z in range(32, 36):
            m.set(x, -2, z, "glow", color=C.col("bulb", 1.0 if (x + z) % 3 else 0.92))
    # Ailettes de refroidissement à l'arrière et sur le dessus.
    for x in range(-4, 4):
        if x % 2 == 0:
            for z in range(31, 37):
                m.face_color[(x, 0, z, "+y")] = C.col("metal_dark")
            for y in range(-2, 1):
                m.face_color[(x, y, 36, "+z")] = C.col("metal_dark", 1.3)
    return m
projecteur.kind = "ns"


def bougies():
    """Trois bougies sur un haricot d'infirmerie en acier (y 0,25 m) :
    cire, coulures, flammes d'un cube (glow), la plus haute à 0,2-0,25 m."""
    m = vx.Model(C.CUBE)
    # Haricot (plateau en acier, coins abattus), un cube.
    for x, y in ellipse(4.2, 3.2):
        m.set(x, y, 0, "metal", color=C.grain((x, y, 0), C.col("steel", 1.05), 370, 0.03, 2))
    for (x, y), h in (((-2, 0), 3), ((1, 1), 2), ((0, -2), 1)):
        for z in range(1, 1 + h):
            m.set(x, y, z, "stone", color=C.grain((x, y, z), C.col("wax"), 371, 0.04, 2))
        m.set(x, y, 1 + h, "glow", color=C.col("flame_core" if h != 2 else "flame"))
    # Coulures de cire sur le plateau.
    for c in ((-3, 0), (-2, 1), (2, 1), (0, -3), (-1, -2)):
        m.set(c[0], c[1], 1, "stone", color=C.col("wax", 0.92))
    return m
bougies.kind = "ns"


def feu():
    """Brasero : fût d'acier rouillé de 0,6 m (rond en escalier), 0,9 m de
    haut, cerclages, trous d'aération où rougeoie le feu, braises dedans,
    flammes en escalier (glow) jusqu'à 1,2 m ; la lumière à 1,15 m ; dans
    le pavé de collision du catalogue (0,62 × 0,9 × 0,62 m)."""
    m = vx.Model(C.CUBE)
    disc = ellipse(6.0, 6.0)
    inner = set(ellipse(4.9, 4.9))
    rust = C.col("rust")
    for x, y in disc:
        for z in range(0, 18):
            if z > 0 and z < 16 and (x, y) in inner:
                continue
            c = (x, y, z)
            if (x, y) in inner and z > 0:
                # Lit de braises et de bois calciné au sommet du fût.
                if vx.noise(c, 380) < 0.45:
                    m.set(*c, "glow", color=C.col("ember", 0.8 + 0.2 * vx.noise(c, 381)))
                else:
                    m.set(*c, "wood", color=C.grain(c, C.col("charred"), 382, 0.25, 2))
                continue
            band = z in (1, 6, 11, 17)
            m.set(*c, "metal", color=C.grain(c, C.col("rust", 0.7 if band else 1.0), 383, 0.08, 2))
    # Rebord : rien au-dessus du lit de braises sauf la paroi (z 16, 17).
    for z in (16, 17):
        for x, y in inner:
            m.vox.pop((x, y, z), None)
    for x, y in inner:
        c = (x, y, 15)
        if vx.noise(c, 384) < 0.5:
            m.set(*c, "glow", color=C.col("ember", 0.85 + 0.15 * vx.noise(c, 385)))
        else:
            m.set(*c, "wood", color=C.grain(c, C.col("charred"), 386, 0.25, 2))
    # Trous d'aération (le feu se voit au travers) : faces glow sur la paroi.
    for k in range(4):
        for cell in ((5, 0), (5, -1)):
            x, y = _rot90(cell, k)
            for z in (3, 4):
                if (x, y, z) in m.vox:
                    m.set(x, y, z, "glow", color=C.col("ember", 0.75))
    # Flammes en escalier (glow) : du rebord à 1,2 m, cœur plus clair.
    for x, y in ellipse(4.4, 4.4):
        r = math.hypot(x + 0.5, y + 0.5)
        top = 16 + int((1.0 - r / 4.6) * 7.0 * (0.65 + 0.35 * vx.noise((x, y, 0), 387)))
        for z in range(16, top + 1):
            col = "flame_core" if (z > 18 and r < 2.2) or z >= top - 0 and r < 1.6 else "flame"
            m.set(x, y, z, "glow", color=C.col(col, 0.9 + 0.1 * vx.noise((x, y, z), 388)))
    return m
feu.kind = "ns"


BUILDERS = {
    "ampoule": ampoule,
    "suspension": suspension,
    "neon": neon,
    "lustre": lustre,
    "applique": applique,
    "lampe_bureau": lampe_bureau,
    "projecteur": projecteur,
    "bougies": bougies,
    "feu": feu,
}
# Anciens modèles (planches « avant ») : le lustre est l'ancien chandelier
# ramené à l'échelle 0,25 du jeu.
BEFORE = {"lustre": "chandelier", "applique": "sconce"}

if __name__ == "__main__":
    C.main(BUILDERS, BEFORE)
