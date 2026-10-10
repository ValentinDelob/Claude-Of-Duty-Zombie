# Décors CUBIQUES, famille DÉCORS DES EFFETS (lot 3 de
# docs/VOXEL_DECOR_PLAN.md) : foyer de pierres, bûches, électrodes...
# Cubes de 5 cm, tools/blender/voxel_props/common.py (conventions, export,
# planches). Les effets (flammes, arcs...) restent des particules posées à
# part (MapEffects) : ces modèles n'en sont que le support.
#
#   sh tools/blender.sh tools/blender/voxel_props/effets.py [ids...] [--sheet DOSSIER]
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import voxel_lib as vx  # noqa: E402


def ember_wood(m, x0, x1, y0, y1, z0, z1, seed, glow_rate=0.18):
    """Bûche calcinée (pavé) : bois noirci, quelques cubes de braise
    (« glow », émissifs dans le jeu), bouts couleur de bois à cœur rougeoyant."""
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                c = (x, y, z)
                if vx.noise(c, seed) < glow_rate:
                    m.set(x, y, z, "glow", color=C.col("ember", 0.75 + 0.25 * vx.noise(c, seed + 1)))
                else:
                    m.set(x, y, z, "wood", color=C.grain(c, C.col("charred"), seed + 2, 0.25))


def stone(m, cx, cy, w, d, h, seed):
    """Pierre du foyer : pavé w × d × h cubes autour de (cx, cy), dessus en
    coins abattus (arrondi en escalier), gris varié, faces tournées vers
    le feu noircies de suie."""
    x0, y0 = cx - w // 2, cy - d // 2
    base = C.col("stone", 0.8 + 0.35 * vx.noise((cx, cy, 0), seed))

    def keep(x, y, z):
        if z == h - 1:
            return not (x in (x0, x0 + w - 1) and y in (y0, y0 + d - 1))
        return True

    C.fill(m, x0, x0 + w, y0, y0 + d, 0, h, "stone", base, seed=seed, amp=0.1, keep=keep)
    soot = C.col("charred", 1.6)
    inward = "-x" if cx > 0 else "+x"
    inward_y = "-y" if cy > 0 else "+y"
    for x in range(x0, x0 + w):
        for y in range(y0, y0 + d):
            for z in range(h):
                for dd in ((inward,) if abs(cx) >= abs(cy) else ()) + ((inward_y,) if abs(cy) >= abs(cx) else ()):
                    if (x, y, z) in m.vox and vx.noise((x, y, z), seed + 9) < 0.6:
                        m.face_color[(x, y, z, dd)] = vx.tone(soot, 1.0 + 0.4 * vx.noise((x, y, z), seed))


def foyer_pierres():
    """Foyer de pierres (ancien décor construit par le jeu, support de
    l'effet « Grand feu ») : dix pierres en cercle de 0,52 m de rayon, lit de
    cendres et de braises, quatre bûches croisées en carré ; 1,3 m de côté,
    0,25 m de haut."""
    import math
    m = vx.Model(C.CUBE)
    # Lit de cendres (une couche, disque de 7 cubes de rayon), braises au centre.
    for x in range(-8, 8):
        for y in range(-8, 8):
            r = math.hypot(x + 0.5, y + 0.5)
            if r > 7.6:
                continue
            c = (x, y, 0)
            if r < 4.5 and vx.noise(c, 31) < 0.35:
                m.set(x, y, 0, "glow", color=C.col("ember", 0.7 + 0.3 * vx.noise(c, 32)))
            else:
                m.set(x, y, 0, "stone", color=C.grain(c, C.col("ash", 0.75 if r < 5 else 1.0), 33, 0.15))
    # Bûches : deux le long de X, deux le long de Y posées dessus (en carré).
    ember_wood(m, -7, 7, -4, -2, 1, 3, 41)
    ember_wood(m, -7, 7, 2, 4, 1, 3, 42)
    ember_wood(m, -4, -2, -7, 7, 3, 5, 43, 0.12)
    ember_wood(m, 2, 4, -7, 7, 3, 5, 44, 0.12)
    # Bouts des bûches : bois à cœur.
    for x0, x1, y0, y1, z0, z1, axis in ((-7, 7, -4, -2, 1, 3, "x"), (-7, 7, 2, 4, 1, 3, "x"),
                                         (-4, -2, -7, 7, 3, 5, "y"), (2, 4, -7, 7, 3, 5, "y")):
        if axis == "x":
            cells = [((x0, y, z), "-x") for y in range(y0, y1) for z in range(z0, z1)]
            cells += [((x1 - 1, y, z), "+x") for y in range(y0, y1) for z in range(z0, z1)]
        else:
            cells = [((x, y0, z), "-y") for x in range(x0, x1) for z in range(z0, z1)]
            cells += [((x, y1 - 1, z), "+y") for x in range(x0, x1) for z in range(z0, z1)]
        for c, d in cells:
            if c in m.vox and m.vox[c].mat != "glow":
                m.face_color[(c[0], c[1], c[2], d)] = C.grain(c, C.col("wood", 0.75), 45, 0.12)
    # Dix pierres en cercle (rayon 0,52 m = 10,4 cubes).
    for i in range(10):
        a = i * 2 * math.pi / 10
        cx = int(round(math.cos(a) * 10.4))
        cy = int(round(math.sin(a) * 10.4))
        w = 3 + (i % 2)
        d = 4 - (i % 3 == 0)
        h = 2 + (i % 3 == 1) + (i % 4 == 2)
        stone(m, cx, cy, w, d, h, 50 + i)
    return m


# ------------------------------------------------------------------ outils du lot 3
# Repères : décor au sol, origine au centre de l'emprise ; décor MURAL,
# origine sur la face du mur (cellules y < 0 : vers la pièce, +Z Godot ;
# z : hauteur autour du point de pose) ; décor au PLAFOND, origine sous le
# plafond (cellules z < 0 : vers le bas).

def ellipse(rx, ry, cx=0.0, cy=0.0):
    """Cellules (x, y) d'une ellipse en escalier de demi-axes rx, ry (cubes),
    centrée en (cx, cy) (coordonnées de cubes, coins de la grille)."""
    out = []
    for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                out.append((x, y))
    return out


def faces_out(m, cells, d, color):
    """Peint la face `d` des cellules données qui existent (étiquettes, bandes)."""
    C.paint(m, [(c, d) for c in cells], color)


def ring_xy(x0, x1, y0, y1):
    """Bord (un cube d'épaisseur) du rectangle [x0, x1) × [y0, y1)."""
    return [(x, y) for x in range(x0, x1) for y in range(y0, y1)
            if x in (x0, x1 - 1) or y in (y0, y1 - 1)]


# ------------------------------------------------------------------ feu

def buches():
    """Bûches d'un petit feu de bois (support de l'effet « Petit feu ») :
    quatre bûches calcinées croisées en carré (deux rangs), lit de cendres et
    braises au centre ; 0,45 m de côté, 0,15 m de haut."""
    m = vx.Model(C.CUBE)
    # Lit de cendres (une couche sous le rang du bas), braises au cœur.
    for x, y in ellipse(3.6, 3.6):
        c = (x, y, 0)
        if abs(x + 0.5) < 2 and abs(y + 0.5) < 2 and vx.noise(c, 61) < 0.55:
            m.set(x, y, 0, "glow", color=C.col("ember", 0.75 + 0.25 * vx.noise(c, 62)))
        else:
            m.set(x, y, 0, "stone", color=C.grain(c, C.col("ash", 0.85), 63, 0.12, 2))
    # Rang du bas : deux bûches le long de X ; rang du haut : le long de Y.
    ember_wood(m, -4, 5, -3, -1, 0, 1, 64, 0.15)
    ember_wood(m, -5, 4, 1, 3, 0, 1, 65, 0.15)
    ember_wood(m, -3, -1, -5, 4, 1, 2, 66, 0.2)
    ember_wood(m, 1, 3, -4, 5, 1, 2, 67, 0.2)
    # Bouts des bûches : bois à cœur.
    for (x0, x1, y0, y1, z, ax) in ((-4, 5, -3, -1, 0, "x"), (-5, 4, 1, 3, 0, "x"),
                                     (-3, -1, -5, 4, 1, "y"), (1, 3, -4, 5, 1, "y")):
        if ax == "x":
            ends = [((x0, y, z), "-x") for y in range(y0, y1)] + [((x1 - 1, y, z), "+x") for y in range(y0, y1)]
        else:
            ends = [((x, y0, z), "-y") for x in range(x0, x1)] + [((x, y1 - 1, z), "+y") for x in range(x0, x1)]
        for c, d in ends:
            if c in m.vox and m.vox[c].mat != "glow":
                m.face_color[(c[0], c[1], c[2], d)] = C.grain(c, C.col("wood", 0.8), 68, 0.1, 2)
    # Petite bûche en travers sur le dessus.
    ember_wood(m, -3, 3, -1, 1, 2, 3, 69, 0.25)
    return m


def planches_brulees():
    """Planches calcinées sous un incendie : cinq planches de 0,9 × 0,15 m
    (cubes d'un rang), en quarts de tour, deux posées en travers des autres,
    bouts rongés, braises dans le bois ; 2,5 × 1 m, 0,1 m de haut."""
    m = vx.Model(C.CUBE)
    # (x0, x1, y0, y1, z) : planches d'un cube d'épaisseur.
    planks = ((-24, -21, -9, 9, 0), (-19, -1, -7, -4, 0), (4, 7, -9, 9, 0),
              (-7, 11, 2, 5, 1), (8, 24, -5, -2, 1))
    for i, (x0, x1, y0, y1, z) in enumerate(planks):
        along_x = (x1 - x0) > (y1 - y0)
        n = (x1 - x0) if along_x else (y1 - y0)
        for x in range(x0, x1):
            for y in range(y0, y1):
                c = (x, y, z)
                k = (x - x0) if along_x else (y - y0)
                w = (y - y0) if along_x else (x - x0)
                # Bouts rongés par le feu (dentelés, un cube de moins).
                if (k == 0 or k == n - 1) and vx.noise(c, 70 + i) < 0.5:
                    continue
                if k == 1 and w != 1 and vx.noise(c, 75 + i) < 0.3:
                    continue
                r = vx.noise(c, 80 + i)
                if r < 0.12:
                    m.set(*c, "glow", color=C.col("ember", 0.7 + 0.3 * vx.noise(c, 81)))
                elif i == 2 and k > n - 6:
                    # Une planche pas encore toute brûlée : bois roussi au bout.
                    m.set(*c, "wood", color=C.grain(c, C.col("wood_dark", 0.8), 82, 0.12, 2))
                else:
                    m.set(*c, "wood", color=C.grain(c, C.col("charred"), 83, 0.3, 3))
        # Fil du bois : une rainure plus sombre au milieu de la planche.
        for x in range(x0, x1):
            for y in range(y0, y1):
                w = (y - y0) if along_x else (x - x0)
                c = (x, y, z)
                if w == 1 and c in m.vox and m.vox[c].mat == "wood" and vx.noise(c, 84) < 0.5:
                    m.face_color[(x, y, z, "+z")] = C.col("charred", 0.6)
    # Cendres au pied des planches (cellules vides voisines d'une planche au sol).
    ash = set()
    for (x, y, z) in list(m.vox):
        if z != 0:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c = (x + dx, y + dy, 0)
            if c not in m.vox and abs(c[0] + 0.5) < 25 and abs(c[1] + 0.5) < 10 and vx.noise(c, 90) < 0.1:
                ash.add(c)
    for c in ash:
        m.set(*c, "stone", color=C.grain(c, C.col("ash"), 91, 0.15, 2))
    return m


def torche_murale():
    """Torche murale (support de l'effet « Flamme de torche ») : patte fixée
    au mur, bras et collier d'acier, manche de bois droit à 0,25 m du mur,
    tête goudronnée à braises en haut (0,15 à 0,25 m au-dessus du point de
    pose) ; origine sur la face du mur."""
    m = vx.Model(C.CUBE)
    steel = C.col("metal_dark", 1.1)
    # Patte au mur : plaque 0,2 × 0,25 m, rivets.
    C.fill(m, -2, 2, -1, 0, -5, 0, "metal", steel, seed=101, amp=0.06, levels=2)
    faces_out(m, [(-2, -1, -1), (1, -1, -1), (-2, -1, -5), (1, -1, -5)], "-y", C.col("steel", 0.9))
    # Bras horizontal jusqu'au manche, collier autour du manche.
    C.fill(m, -1, 1, -4, -1, -3, -2, "metal", steel, seed=102, amp=0.05, levels=2)
    for x, y in ring_xy(-2, 2, -7, -3):
        m.set(x, y, -3, "metal", color=C.grain((x, y, -3), steel, 103, 0.06, 2))
    # Manche de bois (2 × 2 cubes), de -0,25 à +0,15 m.
    C.fill(m, -1, 1, -6, -4, -5, 3, "wood", C.col("wood_dark"), seed=104, amp=0.08, levels=3)
    # Tête : chiffons goudronnés (4 × 4), braises sur le dessus.
    for x in range(-2, 2):
        for y in range(-7, -3):
            for z in (3, 4):
                c = (x, y, z)
                if z == 4 and (x in (-2, 1) and y in (-7, -4)):
                    continue
                m.set(x, y, z, "fabric", color=C.grain(c, C.col("tar"), 105, 0.25, 3))
    # Liens de chiffon plus clairs autour de la tête.
    for x in range(-2, 2):
        for y in range(-7, -3):
            for d in ("-y", "+y", "-x", "+x"):
                c = (x, y, 3)
                if c in m.vox:
                    m.face_color[(x, y, 3, d)] = C.grain(c, C.col("burlap", 0.45), 106, 0.1, 2)
    for x in range(-1, 1):
        for y in range(-6, -4):
            m.set(x, y, 4, "glow", color=C.col("ember", 0.85 + 0.15 * vx.noise((x, y, 4), 107)))
    return m


# ------------------------------------------------------------------ électricité

def _electrode(m, x0, seed):
    """Une électrode : socle d'acier (bande de danger), tige, deux
    isolateurs de porcelaine, boule de cuivre en escalier au sommet."""
    # Socle 4 × 4, un cube, puis un collet 2 × 2.
    C.fill(m, x0 - 2, x0 + 2, -2, 2, 0, 1, "metal", C.col("metal_dark"), seed=seed, amp=0.06, levels=2)
    for x in range(x0 - 2, x0 + 2):
        for y in range(-2, 2):
            for d in ("-x", "+x", "-y", "+y"):
                if ((x + y) % 2) == 0:
                    m.face_color[(x, y, 0, d)] = C.col("hazard_yellow", 0.9)
                else:
                    m.face_color[(x, y, 0, d)] = C.col("rubber", 1.5)
    # Tige d'acier (2 × 2) de 0,05 à 0,95 m.
    C.fill(m, x0 - 1, x0 + 1, -1, 1, 1, 19, "metal", C.col("steel"), seed=seed + 1, amp=0.025, levels=2)
    # Isolateurs (disques 4 × 4 coins abattus).
    for z in (13, 15, 17):
        for x in range(x0 - 2, x0 + 2):
            for y in range(-2, 2):
                if x in (x0 - 2, x0 + 1) and y in (-2, 1):
                    continue
                m.set(x, y, z, "stone", color=C.grain((x, y, z), C.col("porcelain"), seed + 2, 0.04, 2))
    # Boule de cuivre en escalier (0,95 à 1,1 m).
    for z, half, cut in ((19, 1, False), (20, 2, True), (21, 1, False)):
        for x in range(x0 - half, x0 + half):
            for y in range(-half, half):
                if cut and x in (x0 - half, x0 + half - 1) and y in (-half, half - 1):
                    continue
                m.set(x, y, z, "metal", color=C.grain((x, y, z), C.col("copper"), seed + 3, 0.08, 3))


def electrodes():
    """Deux électrodes (support de l'effet « Arc électrique ») à ±0,6 m,
    1,1 m de haut, sur les pavés de collision du catalogue (±0,62 m)."""
    m = vx.Model(C.CUBE)
    _electrode(m, 12, 120)
    _electrode(m, -12, 130)
    return m


def bobine_tesla():
    """Bobine Tesla (support de l'effet « Arcs en boule ») : socle à bande
    de danger, colonne d'acier, bobinage de cuivre (spires plus sombres),
    tore d'acier en escalier au sommet ; 0,4 m de côté, 1,55 m de haut."""
    m = vx.Model(C.CUBE)
    # Socle : 8 × 8 puis 6 × 6.
    C.fill(m, -4, 4, -4, 4, 0, 1, "metal", C.col("metal_dark"), seed=140, amp=0.06, levels=2)
    for x in range(-4, 4):
        for y in range(-4, 4):
            for d in ("-x", "+x", "-y", "+y"):
                m.face_color[(x, y, 0, d)] = C.col("hazard_yellow", 0.9) if (x + y) % 2 == 0 else C.col("rubber", 1.5)
    C.fill(m, -3, 3, -3, 3, 1, 2, "metal", C.col("metal_dark", 1.2), seed=141, amp=0.05, levels=2)
    # Colonne (2 × 2) de 0,1 à 0,75 m, isolateur de porcelaine au milieu.
    C.fill(m, -1, 1, -1, 1, 2, 15, "metal", C.col("steel"), seed=142, amp=0.025, levels=2)
    for x, y in ring_xy(-2, 2, -2, 2):
        m.set(x, y, 7, "stone", color=C.col("porcelain"))
    # Bobinage (4 × 4 coins abattus) de 0,75 à 1,25 m : spires alternées.
    for z in range(15, 25):
        for x in range(-2, 2):
            for y in range(-2, 2):
                if x in (-2, 1) and y in (-2, 1):
                    continue
                f = 1.0 if z % 2 else 0.72
                m.set(x, y, z, "metal", color=C.grain((x, y, z), C.col("copper", f), 143, 0.05, 2))
    # Tore au sommet (1,25 à 1,55 m) : 4 × 4, 6 × 6 (coins abattus), 4 × 4.
    for z, half in ((25, 2), (26, 3), (27, 3), (28, 3), (29, 3), (30, 2)):
        for x in range(-half, half):
            for y in range(-half, half):
                if x in (-half, half - 1) and y in (-half, half - 1):
                    continue
                m.set(x, y, z, "metal", color=C.grain((x, y, z), C.col("steel", 1.1), 144, 0.025, 2))
    return m


def boitier_electrique():
    """Boîtier électrique ouvert (support de l'effet « Court-circuit ») :
    caisson olive de 0,3 × 0,4 × 0,1 m, intérieur noir (disjoncteurs, barre
    de cuivre, trace de brûlé), porte ouverte à angle droit sur la gauche,
    trois fils qui pendent dessous ; origine sur la face du mur."""
    m = vx.Model(C.CUBE)
    olive = C.col("paint_olive")
    # Fond (contre le mur) et cadre du caisson.
    C.fill(m, -3, 3, -1, 0, -4, 4, "metal", olive, seed=160, amp=0.06, levels=2)
    for x, z in [(x, z) for x in range(-3, 3) for z in range(-4, 4) if x in (-3, 2) or z in (-4, 3)]:
        m.set(x, -2, z, "metal", color=C.grain((x, -2, z), olive, 161, 0.06, 2))
    # Intérieur : plaque de fond noire, traces de brûlé.
    for x in range(-2, 2):
        for z in range(-3, 3):
            col = C.col("rubber", 1.6) if vx.noise((x, 0, z), 162) > 0.25 else C.col("charred", 0.7)
            m.face_color[(x, -1, z, "-y")] = col
    # Disjoncteurs (une rangée), barre de cuivre.
    for x in range(-2, 2):
        m.set(x, -2, 1, "metal", color=C.col("case_black"))
        m.face_color[(x, -2, 1, "-y")] = C.col("paint_white", 0.9) if x != 0 else C.col("medic_red")
    for x in range(-2, 2):
        m.set(x, -2, -2, "metal", color=C.grain((x, -2, -2), C.col("copper"), 163, 0.08, 2))
    # Porte ouverte à 90° sur la gauche (charnière en x = -3).
    C.fill(m, -4, -3, -7, -1, -4, 4, "metal", olive, seed=164, amp=0.06, levels=2)
    # Face intérieure de la porte : pictogramme de danger (jaune, éclair noir).
    for y in range(-7, -3):
        for z in range(-2, 2):
            m.face_color[(-4, y, z, "+x")] = C.col("hazard_yellow")
    for y, z in ((-5, 1), (-6, 0), (-5, 0), (-5, -1), (-4, -2)):
        m.face_color[(-4, y, z, "+x")] = C.col("rubber", 1.2)
    # Trois fils qui pendent sous le caisson, bouts de cuivre.
    wires = ((-2, "cable_blue", 2), (0, "medic_red", 1), (1, "rubber", 3))
    for x, colname, n in wires:
        for k in range(n):
            m.set(x, -2, -5 - k, "rubber", color=C.col(colname, 0.9 if colname != "rubber" else 1.4))
        m.set(x, -2, -5 - n, "metal", color=C.col("copper", 1.1))
    return m


def cable_suspendu():
    """Câble arraché qui pend du plafond (support des effets d'étincelles) :
    boîte de dérivation, câble noir de 0,6 m qui se décale d'un cube vers la
    pièce à mi-hauteur, brins de cuivre écartés au bout ; origine sous le
    plafond (le modèle descend)."""
    m = vx.Model(C.CUBE)
    C.fill(m, -1, 1, -1, 1, -1, 0, "metal", C.col("metal_dark", 1.2), seed=180, amp=0.05, levels=2)
    for z in range(-7, -1):
        m.set(0, -1, z, "rubber", color=C.grain((0, -1, z), C.col("rubber", 1.6), 181, 0.15, 2))
    for z in range(-12, -6):
        m.set(0, -2, z, "rubber", color=C.grain((0, -2, z), C.col("rubber", 1.6), 182, 0.15, 2))
    # Gaine dénudée puis brins de cuivre écartés.
    m.set(0, -2, -12, "metal", color=C.col("copper", 0.9))
    m.set(0, -2, -13, "metal", color=C.col("copper", 0.95))
    m.set(-1, -2, -13, "metal", color=C.col("copper", 1.1))
    m.set(1, -2, -13, "metal", color=C.col("copper", 1.0))
    return m
cable_suspendu.kind = "ns"


# ------------------------------------------------------------------ eau

def tuyau_vapeur():
    """Tuyau à vapeur qui sort du mur (support de l'effet « Jet de
    vapeur ») : bride boulonnée, tuyau de 0,1 m, raccord au bout (trou noir),
    petite vanne rouge dessus ; 0,2 m de long ; origine sur la face du mur."""
    m = vx.Model(C.CUBE)
    steel = C.col("steel", 0.9)
    C.fill(m, -2, 2, -1, 0, -2, 2, "metal", C.col("metal_dark", 1.2), seed=200, amp=0.05, levels=2)
    faces_out(m, [(-2, -1, -2), (1, -1, -2), (-2, -1, 1), (1, -1, 1)], "-y", C.col("steel", 1.15))
    C.fill(m, -1, 1, -3, -1, -1, 1, "metal", steel, seed=201, amp=0.05, levels=2)
    # Raccord au bout : 4 × 4, trou sombre au centre.
    for x in range(-2, 2):
        for z in range(-2, 2):
            m.set(x, -4, z, "metal", color=C.grain((x, -4, z), C.col("metal_dark", 1.4), 202, 0.05, 2))
    for x in range(-1, 1):
        for z in range(-1, 1):
            m.face_color[(x, -4, z, "-y")] = C.col("rubber")
    # Vanne : tige et volant rouge sur le dessus.
    m.set(0, -2, 1, "metal", color=steel)
    for x in range(-2, 2):
        m.set(x, -2, 2, "metal", color=C.col("medic_red", 0.9))
    return m


def tuyau_fuite():
    """Tuyau rouillé qui fuit (support de l'effet « Filet d'eau ») : 1 m le
    long du mur, section en croix (rond en escalier), deux manchons, deux
    colliers fixés au mur, fissure et coulure humide au milieu ; origine
    sur la face du mur, axe du tuyau à la hauteur de pose."""
    m = vx.Model(C.CUBE)
    rust = C.col("rust")
    for x in range(-10, 10):
        for y, z in [(-2, -1), (-2, 0), (-2, 1), (-3, 0), (-1, 0)]:
            m.set(x, y, z, "metal", color=C.grain((x, y, z), rust, 220, 0.08, 2))
    # Manchons : carrés pleins, un cube plus larges vers la pièce et en hauteur.
    for x0 in (-10, 8):
        for x in range(x0, x0 + 2):
            for y in range(-4, 0):
                for z in range(-2, 3):
                    m.set(x, y, z, "metal", color=C.grain((x, y, z), C.col("rust", 0.8), 221, 0.08, 2))
    # Colliers (en C) à ±0,42 m, vissés au mur.
    for x in (5, -6):
        for z in range(-2, 3):
            m.set(x, -4, z, "metal", color=C.col("metal_dark", 1.3))
        for y in range(-4, 0):
            m.set(x, y, 2, "metal", color=C.col("metal_dark", 1.3))
            m.set(x, y, -2, "metal", color=C.col("metal_dark", 1.3))
    # Fissure au milieu (dessous et devant), coulure d'eau.
    for x in (-1, 0):
        m.face_color[(x, -2, -1, "-z")] = C.col("rubber", 1.5)
        m.face_color[(x, -3, 0, "-y")] = C.col("rubber", 1.5)
    for x in range(-3, 3):
        for d in ("-y", "-z"):
            c = (x, -2, -1) if d == "-z" else (x, -3, 0)
            if x not in (-1, 0) and c in m.vox:
                m.face_color[(c[0], c[1], c[2], d)] = C.col("water", 1.1)
    return m


def _puddle(m, cells, seed):
    """Flaque : une couche d'eau sombre (cubes de 5 cm), reflets plus clairs
    par endroits, bord un peu plus sombre (sol mouillé)."""
    cs = set(cells)
    for x, y in cells:
        c = (x, y, 0)
        edge = any((x + dx, y + dy) not in cs for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge:
            col = C.col("water", 0.75)
        elif vx.noise(c, seed) < 0.05:
            col = C.col("water_glint")
        else:
            col = C.grain(c, C.col("water"), seed + 1, 0.05, 2)
        m.set(x, y, 0, "glass", color=col)


def flaque_eau():
    """Flaque d'eau (support de l'effet « Ronds dans l'eau ») : plaque au
    sol d'un cube (5 cm), grande ellipse de 1,3 × 1 m et une petite flaque
    accolée ; posée sur la grille, sans ombre."""
    m = vx.Model(C.CUBE)
    cells = set(ellipse(13, 10)) | set(ellipse(6, 3.6, 11, -5.6))
    cells = {c for c in cells if abs(c[0] + 0.5) < 15 and abs(c[1] + 0.5) < 15}
    _puddle(m, sorted(cells), 240)
    return m
flaque_eau.kind = "ns"


def petite_flaque():
    """Petite flaque (gouttes, filet d'eau) : plaque au sol d'un cube,
    ellipse de 1 × 0,8 m ; posée sur la grille, sans ombre."""
    m = vx.Model(C.CUBE)
    cells = set(ellipse(10, 8)) | set(ellipse(3, 2, 8, 6))
    cells = {c for c in cells if abs(c[0] + 0.5) < 10 and abs(c[1] + 0.5) < 10}
    _puddle(m, sorted(cells), 250)
    return m
petite_flaque.kind = "ns"


BUILDERS = {
    "foyer_pierres": foyer_pierres,
    "buches": buches,
    "planches_brulees": planches_brulees,
    "electrodes": electrodes,
    "bobine_tesla": bobine_tesla,
    "flaque_eau": flaque_eau,
    "petite_flaque": petite_flaque,
    "torche_murale": torche_murale,
    "tuyau_vapeur": tuyau_vapeur,
    "boitier_electrique": boitier_electrique,
    "tuyau_fuite": tuyau_fuite,
    "cable_suspendu": cable_suspendu,
}
BEFORE = {}

if __name__ == "__main__":
    C.main(BUILDERS, BEFORE)
