# Joueur de baseball CUBIQUE (GAME_CONCEPT.md § 3 : tous les joueurs
# incarnent le même personnage, un joueur de baseball, distingués par leur
# couleur ; § 4.19 : personnages en cubes de 2,5 cm, 72 cubes pour 1,80 m).
# Survivant d'une équipe FICTIVE (aucune ligue, équipe, logo ni marque
# réelle) : casquette, maillot boutonné crème à liserés, numéro 27 dans le
# dos, pantalon gris, chaussettes hautes, crampons, gants de frappe ; visage
# cubique lisible (traits noirs sous les yeux, sourcils froncés, barbe de
# trois jours) ; usure du survivant : terre, sang séché, déchirure au flanc,
# genou râpé, bandage à l'avant-bras gauche et pansement à la mâchoire.
#
#   sh tools/blender.sh tools/blender/player/player_voxel.py [--glb FICHIER] [--sheet FICHIER.png] [--cache]
#
# ZONE DE COULEUR D'ÉQUIPE : matière « team » (casquette, sous-maillot à
# manches longues, liserés du maillot et du pantalon, numéros, chaussettes,
# bracelets des gants), peinte en GRIS (TEAM = 0,8 pour la teinte pleine,
# variations d'ombrage et d'usure autour) ; en jeu, player_voxel.gdshader
# multiplie ce gris par la couleur du joueur (ambre, cyan, rose, vert anis :
# HudStyle.PLAYER_COLORS) : couleur affichée = couleur du joueur × gris / 0,8.
#
# Pas de planche de référence : formes DÉCRITES ici, par pavés de cubes
# (comme le chien), couleurs d'une palette et d'un bruit par cube
# (voxel_lib.noise : texture « un pixel = un cube » reproductible).
# Ossature : RigBuilder.BONES, os placés aux positions attendues par
# l'animation procédurale du joueur (PlayerModel : bassin à 0,95 m, cuisse et
# tibia de 0,45 m, bras et avant-bras de 0,30 m) ; os droits, repos membres
# pendants, pondération rigide (chaque cube à 100 % sur un os). La tête
# pivote à sa base (os head au menton), mains sur l'avant-bras, pieds sur le
# tibia. CACHE : cellules et couleurs de faces dans player_voxel_cells.json
# (suivi par git) ; --cache relit ce fichier (modèle identique).
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
CACHE = os.path.join(HERE, "player_voxel_cells.json")

# ---------------------------------------------------------------------------
# Palette (sRGB).
# ---------------------------------------------------------------------------
SKIN = (0.80, 0.58, 0.44)
SKIN_SHADE = (0.66, 0.46, 0.35)
STUBBLE = (0.69, 0.51, 0.40)
HAIR = (0.22, 0.15, 0.10)
LIP = (0.50, 0.27, 0.22)
EYE_WHITE = (0.93, 0.92, 0.88)
PUPIL = (0.10, 0.08, 0.07)
EYE_BLACK = (0.07, 0.07, 0.08)       # traits noirs sous les yeux (anti-reflet)
JERSEY = (0.88, 0.85, 0.76)          # maillot crème
JERSEY_SEAM = (0.74, 0.71, 0.63)     # patte de boutonnage, coutures
BUTTON = (0.60, 0.57, 0.50)
PANTS = (0.70, 0.70, 0.68)           # pantalon gris « extérieur »
BELT = (0.11, 0.10, 0.09)
BUCKLE = (0.68, 0.68, 0.64)
SHOE = (0.09, 0.09, 0.10)            # crampons noirs
SOLE = (0.20, 0.20, 0.21)
STUD = (0.58, 0.58, 0.56)
GLOVE = (0.17, 0.17, 0.19)           # gants de frappe
PALM = (0.56, 0.47, 0.34)            # paume de cuir
BANDAGE = (0.90, 0.88, 0.80)
TAPE = (0.78, 0.70, 0.56)
DIRT = (0.42, 0.33, 0.23)
BLOOD = (0.38, 0.06, 0.05)
BLOOD_DRY = (0.30, 0.10, 0.07)
SCRAPE = (0.70, 0.30, 0.25)
FRAY = (0.62, 0.59, 0.52)
# Zone d'équipe : gris (teinte pleine 0,8 ; plus sombre : visière, bouton).
TEAM = (0.80, 0.80, 0.80)
TEAM_DARK = (0.56, 0.56, 0.56)
WHITE = (0.94, 0.93, 0.89)           # losange de la casquette, rayure

# Couleurs des joueurs (HudStyle.PLAYER_COLORS) : planche de validation.
PLAYER_COLORS = [(1.0, 0.78, 0.28), (0.35, 0.85, 1.0), (1.0, 0.45, 0.72), (0.6, 0.95, 0.32)]


def cell(x, f, z):
    return (x, -f - 1, z)


def mix(a, b, k):
    return tuple(x + (y - x) * k for x, y in zip(a, b))


class Body:
    def __init__(self):
        self.m = vx.Model(CUBE)

    def put(self, x, f, z, mat, bone, part, color):
        self.m.set(*cell(x, f, z), mat, bone, part, color)

    def box(self, x0, x1, f0, f1, z0, z1, mat, bone, part, color):
        for x in range(x0, x1):
            for f in range(f0, f1):
                for z in range(z0, z1):
                    self.put(x, f, z, mat, bone, part, color)

    def get(self, x, f, z):
        return self.m.vox.get(cell(x, f, z))

    def drop(self, x, f, z):
        self.m.vox.pop(cell(x, f, z), None)

    def face(self, x, f, z, d, color, mat=None):
        c = cell(x, f, z)
        if c not in self.m.vox:
            return False
        self.m.face_color[(c[0], c[1], c[2], d)] = color
        if mat:
            self.m.face_mat[(c[0], c[1], c[2], d)] = mat
        return True

    def front(self, x, z, part=None):
        """Profondeur f de la cellule la plus en avant de la colonne (x, z)."""
        fs = [-c[1] - 1 for c, v in self.m.vox.items() if c[0] == x and c[2] == z and (part is None or v.part == part)]
        return max(fs) if fs else None

    def back(self, x, z, part=None):
        fs = [-c[1] - 1 for c, v in self.m.vox.items() if c[0] == x and c[2] == z and (part is None or v.part == part)]
        return min(fs) if fs else None

    def paint_front(self, x, z, color, mat=None, part=None):
        f = self.front(x, z, part)
        if f is not None:
            self.face(x, f, z, "-y", color, mat)

    def paint_back(self, x, z, color, mat=None, part=None):
        f = self.back(x, z, part)
        if f is not None:
            self.face(x, f, z, "+y", color, mat)


# ---------------------------------------------------------------------------
# Texture : variation par blocs de 2 cubes, terre et sang séché.
# ---------------------------------------------------------------------------

def cloth(x, f, z, base, seed, wear=1.0):
    """Tissu : base, variation par blocs (2 cubes), taches de terre et de
    sang séché (grandes plaques de 3 cubes, puis gouttes)."""
    k = 0.93 + 0.1 * vx.noise((x // 2, f // 2, z // 2), seed)
    c = vx.tone(base, k)
    if wear > 0 and vx.noise((x // 3, f // 3, z // 3), seed + 7) > 1.0 - 0.07 * wear:
        c = mix(c, DIRT, 0.45)
    if wear > 0 and vx.noise((x, f, z), seed + 11) > 1.0 - 0.004 * wear:
        c = BLOOD_DRY
    return c


def team(x, f, z, seed, base=TEAM, wear=1.0):
    """Zone d'équipe : gris (variation, usure plus sombre)."""
    k = 0.95 + 0.08 * vx.noise((x // 2, f // 2, z // 2), seed)
    c = vx.tone(base, k)
    if wear > 0 and vx.noise((x // 3, f // 3, z // 3), seed + 7) > 1.0 - 0.12 * wear:
        c = vx.tone(c, 0.82)
    return c


# ---------------------------------------------------------------------------
# Jambes : crampons, chaussettes hautes, pantalon (genou en dessous de z 19).
# ---------------------------------------------------------------------------

def build_legs(b):
    for s, side in ((1, "l"), (-1, "r")):
        x0, x1 = (1, 7) if s > 0 else (-7, -1)
        shin, thigh = "shin_" + side, "thigh_" + side
        # Crampons : semelle z 1, chaussure z 1..3, bout arrondi, crampons z 0.
        for x in range(x0, x1):
            for f in range(-3, 7):
                b.put(x, f, 1, "leather", shin, "shoe_" + side, SOLE)
                for z in (2, 3):
                    if z == 3 and f >= 5:
                        continue
                    if f == 6 and x in (x0, x1 - 1):
                        continue
                    b.put(x, f, z, "leather", shin, "shoe_" + side, vx.tone(SHOE, 0.95 + 0.1 * vx.noise((x, f, z), 3)))
            for f in (-2, 1, 4):
                if x in (x0, x1 - 1) or (f == 4 and x == (x0 + x1) // 2):
                    b.put(x, f, 0, "metal", shin, "stud_" + side, STUD)
        # Languette et lacets (dessus de l'avant du pied) : tissu sombre.
        for x in range(x0 + 1, x1 - 1):
            for f in (3, 4):
                b.put(x, f, 3, "leather", shin, "shoe_" + side, (0.2, 0.2, 0.21))
        # Chaussettes hautes (zone d'équipe), rayure claire en haut, mollet.
        for z in range(4, 14):
            for x in range(x0, x1):
                f0 = -3 if 6 <= z <= 11 else -2
                for f in range(f0, 3):
                    if z == 11:
                        b.put(x, f, z, "cloth", shin, "sock_" + side, vx.tone(WHITE, 0.95 + 0.05 * vx.noise((x, f, z), 4)))
                    else:
                        b.put(x, f, z, "team", shin, "sock_" + side, team(x, f, z, 21, wear=0.8))
        # Bas du pantalon (resserré au-dessus du mollet, un peu bouffant).
        for z in range(14, 19):
            for x in range(x0, x1):
                for f in range(-3, 4):
                    b.put(x, f, z, "cloth", shin, "pants_" + side, cloth(x, f, z, PANTS, 31))
        # Cuisse.
        for z in range(19, 37):
            for x in range(x0, x1):
                for f in range(-3, 4):
                    b.put(x, f, z, "cloth", thigh, "pants_" + side, cloth(x, f, z, PANTS, 31))
        # Liseré d'équipe sur le côté extérieur du pantalon.
        xo = x1 - 1 if s > 0 else x0
        d = "+x" if s > 0 else "-x"
        for z in range(14, 37):
            b.face(xo, 0, z, d, team(xo, 0, z, 22), "team")
        # Genou : terre de glissade.
        for x in range(x0, x1):
            for z in (18, 19, 20):
                b.paint_front(x, z, mix(cloth(x, 3, z, PANTS, 31, 0), DIRT, 0.55 + 0.15 * vx.noise((x, z, 0), 5)))
    # Genou droit déchiré : peau râpée au fond, bords effilochés.
    for x in range(-6, -2):
        for z in range(18, 22):
            edge = x in (-6, -3) or z in (18, 21)
            col = FRAY if edge else (SCRAPE if (x + z) % 3 == 0 else SKIN_SHADE)
            if not (edge and (x, z) in ((-6, 18), (-3, 21))):
                b.paint_front(x, z, col, "cloth" if edge else "skin")


# ---------------------------------------------------------------------------
# Bassin, ceinture, maillot (rentré dans le pantalon), torse.
# ---------------------------------------------------------------------------

def build_torso(b):
    # Bassin : entrejambe et taille du pantalon (z 34..39), ceinture z 39,
    # maillot rentré au-dessus (z 40..42).
    for z in range(33, 37):
        for x in (-1, 0):
            for f in range(-3, 4):
                b.put(x, f, z, "cloth", "hips", "pants_hips", cloth(x, f, z, PANTS, 31))
    for z in range(37, 43):
        for x in range(-7, 7):
            for f in range(-3, 4):
                if z < 39:
                    b.put(x, f, z, "cloth", "hips", "pants_hips", cloth(x, f, z, PANTS, 31))
                elif z == 39:
                    b.put(x, f, z, "leather", "hips", "belt", vx.tone(BELT, 0.95 + 0.1 * vx.noise((x, f, z), 6)))
                else:
                    b.put(x, f, z, "cloth", "hips", "jersey", cloth(x, f, z, JERSEY, 41))
    # Passants de ceinture, boucle.
    for x in (-5, 4):
        b.paint_front(x, 39, vx.tone(PANTS, 0.9), "cloth")
    for x in (-1, 0):
        b.paint_front(x, 39, BUCKLE, "metal")
    # Torse : taille (spine, z 43..52) puis poitrine (chest, z 53..58).
    for z in range(43, 59):
        bone = "spine" if z < 53 else "chest"
        w = 7 if z < 47 else 8
        for x in range(-w, w):
            f0, f1 = (-4, 4) if z < 47 else (-5, 5)
            for f in range(f0, f1):
                b.put(x, f, z, "cloth", bone, "jersey", cloth(x, f, z, JERSEY, 41))
    # Épaules : coins du haut arrondis d'un cube.
    for x in (-8, 7):
        for f in (-5, 4):
            b.drop(x, f, 58)
    # Patte de boutonnage : couture et liseré d'équipe, boutons.
    for z in range(40, 57):
        b.paint_front(0, z, team(0, 4, z, 23), "team")
        if z % 3 == 1:
            b.paint_front(-1, z, BUTTON, "cloth")
        else:
            b.paint_front(-1, z, cloth(-1, 4, z, JERSEY_SEAM, 42), "cloth")
    # Encolure en V : sous-maillot d'équipe visible (col rond).
    for z, xs in ((58, range(-3, 3)), (57, range(-2, 2)), (56, range(-1, 1))):
        for x in xs:
            f = b.front(x, z)
            if f is not None:
                b.drop(x, f, z)
                b.put(x, f - 1, z, "team", "chest", "undershirt", team(x, f, z, 24))
    # Liseré d'équipe autour de l'encolure (bord du V).
    for z, xs in ((58, (-4, 3)), (57, (-3, 2)), (56, (-2, 1)), (55, (-1, 0))):
        for x in xs:
            b.paint_front(x, z, team(x, 4, z, 23), "team")
    # Petit numéro 27 sur la poitrine gauche (x > 0), chiffres de 3 × 5.
    draw_number(b, "27", 1, 50, small=True, front=True)
    # Grand numéro 27 dans le dos, chiffres de 5 × 8.
    draw_number(b, "27", 5, 44, small=False, front=False)
    # Déchirure au flanc droit (avant) : peau et griffure, bords effilochés.
    for x in range(-7, -3):
        for z in range(43, 47):
            edge = x in (-7, -4) or z in (43, 46)
            if edge and (x, z) in ((-7, 46), (-4, 43)):
                continue
            col = FRAY if edge else (BLOOD if (x, z) == (-6, 45) else SKIN)
            b.paint_front(x, z, col, "cloth" if edge else ("wound" if col == BLOOD else "skin"))
    # Sang séché : coulure sur l'épaule gauche, taches sur le ventre.
    for x, z in ((5, 57), (5, 56), (6, 56), (5, 55), (4, 52), (2, 45), (3, 44)):
        b.paint_front(x, z, BLOOD_DRY, "wound")


DIGITS_SMALL = {
    "2": ["###", "..#", "###", "#..", "###"],
    "7": ["###", "..#", "..#", ".#.", ".#."],
}
DIGITS_BIG = {
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "7": ["#####", "....#", "...#.", "...#.", "..#..", "..#..", ".#...", ".#..."],
}


def draw_number(b, text, x0, z_bottom, small, front):
    """Numéro en cubes (zone d'équipe). De face, la droite de l'image est le
    côté +X du personnage : le texte avance vers +X depuis `x0` ; de dos,
    elle est le côté -X : le texte part de `x0` (bord +X) vers -X."""
    font = DIGITS_SMALL if small else DIGITS_BIG
    w = 3 if small else 5
    off = 0
    for ch in text:
        rows = font[ch]
        for r, line in enumerate(rows):
            z = z_bottom + len(rows) - 1 - r
            for i, px in enumerate(line):
                if px != "#":
                    continue
                if front:
                    xx = x0 + off + i
                    b.paint_front(xx, z, team(xx, 4, z, 25), "team")
                else:
                    xx = x0 - off - i
                    b.paint_back(xx, z, team(xx, -5, z, 25), "team")
        off += w + 1


# ---------------------------------------------------------------------------
# Bras : manche courte du maillot, sous-maillot d'équipe, bandage, gants.
# ---------------------------------------------------------------------------

def build_arms(b):
    for s, side in ((1, "l"), (-1, "r")):
        x0, x1 = (8, 13) if s > 0 else (-13, -8)
        arm, fore = "arm_" + side, "forearm_" + side
        for z in range(30, 59):
            for x in range(x0, x1):
                for f in range(-2, 3):
                    if z >= 53:
                        # Manche du maillot (un cube plus large vers l'avant
                        # et l'arrière), arrondie en haut à l'extérieur.
                        b.put(x, f, z, "cloth", arm, "sleeve_" + side, cloth(x, f, z, JERSEY, 43))
                    elif z >= 47:
                        b.put(x, f, z, "team", arm, "undershirt_" + side, team(x, f, z, 26))
                    elif z >= 38:
                        b.put(x, f, z, "team", fore, "undershirt_" + side, team(x, f, z, 26))
                    elif z >= 35:
                        b.put(x, f, z, "skin", fore, "wrist_" + side, SKIN)
                    else:
                        # Gant : bracelet d'équipe en haut, dos sombre, paume de
                        # cuir (côté intérieur), doigts repliés vers l'avant.
                        mat, col = "leather", GLOVE
                        if z == 34:
                            mat, col = "team", team(x, f, z, 27, base=TEAM_DARK, wear=0)
                        b.put(x, f, z, mat, fore, "glove_" + side, col)
            # Manche : plus large que le bras (avant et arrière).
            for z in range(53, 59):
                for x in range(x0, x1):
                    for f in (-3, 3):
                        if z == 58 and (x == (x1 - 1 if s > 0 else x0)):
                            continue
                        b.put(x, f, z, "cloth", arm, "sleeve_" + side, cloth(x, f, z, JERSEY, 43))
        # Ourlet de la manche : liseré d'équipe.
        for x in range(x0, x1):
            for f in range(-3, 4):
                c = b.get(x, f, 53)
                if c is not None:
                    b.face(x, f, 53, "-z", team(x, f, 53, 28), "team")
                    if f == 3:
                        b.face(x, f, 53, "-y", team(x, f, 53, 28), "team")
                    if f == -3:
                        b.face(x, f, 53, "+y", team(x, f, 53, 28), "team")
                    if x == x0:
                        b.face(x, f, 53, "-x", team(x, f, 53, 28), "team")
                    if x == x1 - 1:
                        b.face(x, f, 53, "+x", team(x, f, 53, 28), "team")
        # Pouce (côté intérieur, devant) et paume.
        xi = x0 if s > 0 else x1 - 1
        b.put(xi - s, 2, 32, "leather", fore, "glove_" + side, GLOVE)
        b.put(xi - s, 2, 33, "leather", fore, "glove_" + side, GLOVE)
        for z in range(30, 34):
            for f in range(-2, 3):
                b.face(xi, f, z, "-x" if s > 0 else "+x", vx.tone(PALM, 0.95 + 0.1 * vx.noise((f, z, 0), 7)))
        # Phalanges : fentes entre les doigts sur le devant.
        for z in (30, 31):
            for x in range(x0, x1):
                if (x - x0) % 2 == 1:
                    b.face(x, 2, z, "-y", vx.tone(GLOVE, 0.6))
    # Bandage à l'avant-bras gauche (par-dessus la manche), taché de sang.
    for z in range(40, 44):
        for x in range(7, 14):
            for f in range(-3, 4):
                inside = 8 <= x < 13 and -2 <= f < 3
                if inside:
                    continue
                if (x in (7, 13)) and (f in (-3, 3)):
                    continue
                col = vx.tone(BANDAGE, 0.92 + 0.08 * vx.noise((x, f, z), 8))
                if (x, f, z) in ((10, 3, 41), (11, 3, 41), (10, 3, 42)):
                    col = BLOOD_DRY
                elif z == 43 and vx.noise((x, f, 0), 9) > 0.6:
                    col = TAPE
                b.put(x, f, z, "cloth", "forearm_l", "bandage", col)


# ---------------------------------------------------------------------------
# Cou, tête, visage, casquette.
# ---------------------------------------------------------------------------

def build_head(b):
    for z in (59, 60):
        for x in range(-3, 3):
            for f in range(-2, 2):
                b.put(x, f, z, "skin", "neck", "neck", SKIN_SHADE if z == 59 else SKIN)
    # Crâne et visage z 61..67 : 12 × 11, menton et coins arrondis.
    for z in range(61, 68):
        for x in range(-6, 6):
            for f in range(-5, 6):
                if z == 61 and (x in (-6, 5) or f in (-5, 5)):
                    continue
                if z == 61 and f == -4:
                    continue
                if (x in (-6, 5)) and (f in (-5, 5)):
                    continue
                col = SKIN
                if z <= 62 and f >= -1:
                    col = STUBBLE  # barbe de trois jours (bas du visage)
                b.put(x, f, z, "skin", "head", "head", col)
    # Cheveux sous la casquette : nuque et tempes (z 65..67).
    for z in range(64, 68):
        for x in range(-6, 6):
            for f in range(-5, 6):
                v = b.get(x, f, z)
                if v is None:
                    continue
                back = f <= -3
                temple = (x in (-6, 5)) and f <= 1 and z >= 66
                if back and z >= 65 or temple:
                    v.color = vx.tone(HAIR, 0.95 + 0.1 * vx.noise((x, f, z), 10))
    # Oreilles.
    for x in (-7, 6):
        for z in (63, 64, 65):
            for f in (-1, 0):
                b.put(x, f, z, "skin", "head", "ear", SKIN_SHADE if z == 63 else SKIN)
    # Visage (faces avant, f = 5 ; nez en saillie f = 6).
    for x in (-1, 0):
        b.put(x, 6, 63, "skin", "head", "nose", SKIN_SHADE)
        b.put(x, 6, 64, "skin", "head", "nose", SKIN)
    for x in range(-2, 2):
        b.paint_front(x, 62, LIP if x in (-1, 0) else vx.tone(LIP, 0.85), part="head")
    for s in (1, -1):
        inner, outer = (1, 2) if s > 0 else (-2, -3)
        # Yeux 2 × 2 : blanc, pupille en bas côté intérieur (regard droit).
        for z in (64, 65):
            b.paint_front(outer, z, EYE_WHITE, "bone", part="head")
        b.paint_front(inner, 65, EYE_WHITE, "bone", part="head")
        b.paint_front(inner, 64, PUPIL, "bone", part="head")
        # Sourcils froncés (une rangée de peau au-dessus de l'œil), bout
        # intérieur plus bas.
        b.paint_front(inner, 66, HAIR, part="head")
        for x in ((2, 3) if s > 0 else (-3, -4)):
            b.paint_front(x, 67, HAIR, part="head")
    # Égratignure (pommette gauche) et pansement sur la mâchoire droite.
    b.paint_front(4, 64, BLOOD, "wound", part="head")
    b.paint_front(4, 63, SCRAPE, "wound", part="head")
    for x in (-6, -5):
        for z in (61, 62):
            b.paint_front(x, z, BANDAGE, "cloth", part="head")
    b.face(-6, 2, 62, "-x", BANDAGE, "cloth")
    b.face(-6, 1, 62, "-x", TAPE, "cloth")
    # Casquette (zone d'équipe) : calotte z 68..71 un cube plus large que la
    # tête, dôme en escalier, visière z 68, bouton, losange blanc devant.
    for z in range(68, 72):
        x0, x1, f0, f1 = (-7, 7, -6, 7) if z < 70 else ((-6, 6, -6, 6) if z == 70 else (-5, 5, -5, 5))
        for x in range(x0, x1):
            for f in range(f0, f1):
                if z < 71 and (x in (x0, x1 - 1)) and (f in (f0, f1 - 1)):
                    continue
                b.put(x, f, z, "team", "head", "cap", team(x, f, z, 29, wear=0.7))
    for x in (-1, 0):
        b.put(x, 0, 71, "team", "head", "cap", TEAM_DARK)
    # Ouverture de réglage à l'arrière (cheveux visibles).
    for x in (-1, 0):
        b.drop(x, -6, 68)
        b.face(x, -5, 68, "+y", HAIR)
    for f in range(7, 11):
        for x in range(-6, 6):
            if f == 10 and x in (-6, 5):
                continue
            b.put(x, f, 68, "team", "head", "brim", team(x, f, 68, 30, base=TEAM_DARK, wear=0))
    for f in range(7, 11):
        for x in range(-6, 6):
            b.face(x, f, 68, "-z", vx.tone(TEAM_DARK, 0.55), "team")
    # Losange de l'équipe fictive (un « diamant » de baseball) sur le devant.
    for z, xs in ((68, (-1, 0)), (69, (-2, -1, 0, 1)), (70, (-1, 0))):
        for x in xs:
            b.paint_front(x, z, WHITE, "cloth", part="cap")


# ---------------------------------------------------------------------------
# Ossature (RigBuilder.BONES) en cubes de 2,5 cm : positions attendues par
# PlayerModel (bassin 0,95 m ; tibia, cuisse 0,45 m ; bras, avant-bras 0,30 m).
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, 0, 38), (0, 0, 43)),
    ("spine", "hips", (0, 0, 43), (0, 0, 53)),
    ("chest", "spine", (0, 0, 53), (0, 0, 59)),
    ("neck", "chest", (0, 0, 59), (0, 0, 61)),
    ("head", "neck", (0, 0, 61), (0, 0, 72)),
    ("arm_l", "chest", (10.5, -0.5, 59), (10.5, -0.5, 47)),
    ("forearm_l", "arm_l", (10.5, -0.5, 47), (10.5, -0.5, 35)),
    ("arm_r", "chest", (-10.5, -0.5, 59), (-10.5, -0.5, 47)),
    ("forearm_r", "arm_r", (-10.5, -0.5, 47), (-10.5, -0.5, 35)),
    ("thigh_l", "hips", (4, -0.5, 37), (4, -0.5, 19)),
    ("shin_l", "thigh_l", (4, -0.5, 19), (4, -0.5, 1)),
    ("thigh_r", "hips", (-4, -0.5, 37), (-4, -0.5, 19)),
    ("shin_r", "thigh_r", (-4, -0.5, 19), (-4, -0.5, 1)),
    ("jaw", "head", (0, -3, 62), (0, -6, 62)),
]


def describe():
    b = Body()
    build_legs(b)
    build_torso(b)
    build_arms(b)
    build_head(b)
    m = b.m
    # Faces peintes de cellules retirées ensuite (encolure, casquette).
    for k in [k for k in m.face_color if k[:3] not in m.vox]:
        del m.face_color[k]
    for k in [k for k in m.face_mat if k[:3] not in m.vox]:
        del m.face_mat[k]
    vx.shade(m, {"+z": 1.06, "-z": 0.66, "+x": 0.88, "-x": 0.88, "-y": 1.0, "+y": 0.94}, skip_mats=())
    vx.quantize(m, {"cloth": 26, "skin": 12, "team": 8, "leather": 8})
    return m


def build(use_cache=False):
    info = {}
    if use_cache and os.path.exists(CACHE):
        m = vx.load_cache(CACHE)
        info["from_cache"] = True
    else:
        m = describe()
        vx.save_cache(m, CACHE)
    ob, mi = vx.build_mesh(m, "player_voxel")
    info.update(mi)
    rig = vx.build_armature("player_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    info["z_range"] = (int(lo[2]), int(hi[2]))
    return m, ob, rig, info


# ---------------------------------------------------------------------------
# Planche de validation : vues, poses et les quatre couleurs de joueur.
# ---------------------------------------------------------------------------

def tinted(m, rgb):
    """Copie du modèle dont la zone d'équipe prend la couleur `rgb` (même
    calcul que player_voxel.gdshader : couleur × gris / 0,8)."""
    t = vx.Model(m.cube)
    t.vox = {c: vx.Voxel("cloth" if v.mat == "team" else v.mat, v.bone, v.part,
                         tuple(min(1.0, a * g / TEAM[0]) for a, g in zip(rgb, v.color)) if v.mat == "team" else v.color)
             for c, v in m.vox.items()}
    for k, col in m.face_color.items():
        mat = m.face_mat.get(k, m.vox[k[:3]].mat)
        t.face_color[k] = tuple(min(1.0, a * g / TEAM[0]) for a, g in zip(rgb, col)) if mat == "team" else col
    for k, mat in m.face_mat.items():
        t.face_mat[k] = "cloth" if mat == "team" else mat
    return t


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


# Pose d'épaulement (arme en joue), comme PlayerModel en visée.
AIM = [("arm_r", "X", 80), ("arm_l", "X", 75), ("arm_l", "Z", -30), ("forearm_l", "X", 40),
       ("head", "X", -4), ("spine", "X", 4)]
RUN = [("thigh_l", "X", 40), ("shin_l", "X", -50), ("thigh_r", "X", -30), ("shin_r", "X", -30),
       ("spine", "X", 14), ("arm_r", "X", 40), ("arm_l", "X", -35), ("forearm_l", "X", 50), ("forearm_r", "X", 60)]


def render_sheet(m, ob, rig, path):
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    vx.add_outline(m, "player_voxel_outline", rig)
    TW, TH = 380, 640
    vx.setup_render((TW, TH))
    hm, tz = 2.0, 0.92
    variants = []
    for i, rgb in enumerate(PLAYER_COLORS):
        o, _ = vx.build_mesh(tinted(m, rgb), "player_voxel_c%d" % i)
        vx.bind(o, rig)
        o.hide_render = True
        variants.append(o)
    ob.hide_render = True

    def shot(o, name, az, el, target=(0, 0, tz), h=hm):
        for v in variants + [ob]:
            v.hide_render = v is not o
        return vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, target, h, el))

    main = variants[0]
    row1 = [shot(main, "front", 0, 0), shot(main, "back", 180, 0), shot(main, "left", 90, 0),
            shot(main, "right", -90, 0), shot(main, "34", 35, 10), shot(main, "back34", 145, 10)]
    row2 = [shot(variants[i], "c%d" % i, 30, 8) for i in range(4)]
    row2.append(shot(ob, "grey", 30, 8))
    row2.append(shot(main, "head", 20, 6, (0, -0.06, 1.62), 0.55))
    pose(rig, AIM)
    row3 = [shot(variants[1], "aim", 50, 6), shot(variants[2], "aim_side", 90, 0)]
    rest_pose(rig)
    pose(rig, RUN)
    row3 += [shot(variants[3], "run", 90, 0), shot(variants[0], "run34", 35, 8)]
    rest_pose(rig)
    row3.append(shot(main, "face", 0, 0, (0, -0.06, 1.63), 0.4))
    row3.append(shot(main, "backhead", 180, 0, (0, 0, 1.2), 0.9))
    vx.save_png(vx.sheet([row1, row2, row3], TW, TH), path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "player", "player_voxel.glb")
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
    print("[player_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(m, ob, rig, os.path.abspath(sheet))
        print("[player_voxel] planche -> %s" % sheet)
