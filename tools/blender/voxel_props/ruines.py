# Décors CUBIQUES, famille GRAVATS ET RUINES (lot 1 de
# docs/VOXEL_DECOR_PLAN.md) : tas de gravats, mur effondré, débris épars,
# planches, poutre tombée, lustre tombé. Cubes de 5 cm,
# tools/blender/voxel_props/common.py (conventions, export, planches).
#
#   sh tools/blender.sh tools/blender/voxel_props/ruines.py [ids...] [--sheet DOSSIER] [--before DOSSIER]
#
# Chaque décor garde l'origine (centre de l'emprise, au sol), l'emprise et
# les collisions de l'ancien modèle (voxel/<id>.collision.json, déplacé tel
# quel). Les tas sont faits de BLOCS (béton, carrelage, plâtre peint) aux
# dessus plats : peu de teintes par bloc, faces fusionnées, pentes en marches.
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import voxel_lib as vx  # noqa: E402


# ------------------------------------------------------------------ outils

def spot(c, base, seed=0, amp=0.06, p=0.22):
    """Texture « un pixel = un cube » sobre : la plupart des cubes gardent la
    teinte `base`, une part `p` est un peu plus claire ou plus sombre (les
    grands aplats restent fusionnés : peu de triangles sur les gros tas)."""
    r = vx.noise(c, seed)
    if r >= p:
        return base
    return vx.tone(base, 1.0 - amp if r < p / 2 else 1.0 + amp)


def line3(a, b):
    """Cellules d'un trait de cubes de `a` à `b` (entiers), reliées par
    leurs FACES (un pas sur un seul axe à la fois) : bras, guirlandes."""
    x, y, z = a
    out = [(x, y, z)]
    while (x, y, z) != tuple(b):
        # Avance sur l'axe le plus en retard par rapport à la droite.
        dx, dy, dz = b[0] - x, b[1] - y, b[2] - z
        ax = max(((abs(dx), 0), (abs(dy), 1), (abs(dz), 2)))[1]
        if ax == 0:
            x += 1 if dx > 0 else -1
        elif ax == 1:
            y += 1 if dy > 0 else -1
        else:
            z += 1 if dz > 0 else -1
        out.append((x, y, z))
    return out


def bumps(spec):
    """Hauteur (en cubes) d'un tertre : maximum de cônes arrondis
    (cx, cy, rx, ry, h) en cubes ; 0 hors de tous les cônes."""
    def h(x, y):
        v = 0.0
        for cx, cy, rx, ry, hh in spec:
            d = math.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
            if d < 1.0:
                v = max(v, hh * (1.0 - d) ** 0.85)
        return v
    return h


# Sortes de blocs : (proportion cumulée, sorte).
KINDS = ((0.46, "beton"), (0.62, "beton_sombre"), (0.76, "carrelage"), (0.88, "peint"), (1.0, "pierre"))


def block_kind(i, seed):
    r = vx.noise((i, 3, 7), seed)
    for p, k in KINDS:
        if r <= p:
            return k
    return "beton"


def block_base(kind, i, seed):
    """Teinte du corps d'un bloc de gravats (une par bloc, un peu variée)."""
    f = 0.88 + 0.22 * vx.noise((i, 1, 2), seed)
    if kind == "beton_sombre":
        return "concrete", C.col("concrete", 0.70 * f)
    if kind == "pierre":
        return "stone", C.col("stone", f)
    return "concrete", C.col("concrete", f)


def rubble(m, x0, x1, y0, y1, height, seed, sp=7, hmax=None, slope=3, q=1, speck=0.22):
    """Tas de gravats en BLOCS : l'aire [x0, x1) × [y0, y1) est découpée en
    blocs rectangulaires irréguliers (cellules de Voronoï en distance
    « max », graines sur une grille de pas `sp` ±) ; chaque bloc a un dessus
    plat à la hauteur du tertre `height(x, y)` à sa graine (± 2 cubes),
    rabattu près des bords (au plus `slope` cubes au-dessus du tertre local).
    Le dessus des blocs « carrelage » est une couche de faïence blanche à
    joints gris, celui des blocs « peint » un enduit vert d'eau d'hôpital.
    `q` : colonnes groupées par carrés de q × q (gros tas : bords moins
    dentelés) ; `speck` : part des cubes d'une teinte voisine (grain).
    Renvoie {colonne (x, y): (indice du bloc, hauteur)}."""
    seeds = []
    for gx in range(x0 - sp, x1 + sp, sp):
        for gy in range(y0 - sp, y1 + sp, sp):
            i = len(seeds)
            jx = int(vx.noise((gx, gy, 0), seed) * sp)
            jy = int(vx.noise((gx, gy, 1), seed) * sp)
            wx = 0.7 + 0.7 * vx.noise((gx, gy, 2), seed)
            seeds.append((gx + jx, gy + jy, wx, 1.4 - wx + 0.7))
    tops = {}
    cols = {}
    macro = {}
    for x in range(x0, x1):
        for y in range(y0, y1):
            # Colonnes groupées par carrés de q × q (bords de blocs moins
            # dentelés : moins de faces sur les gros tas).
            key = (x // q, y // q)
            if key not in macro:
                px, py = key[0] * q + q / 2.0, key[1] * q + q / 2.0
                hl = height(px, py)
                if hl < 0.6:
                    macro[key] = None
                    continue
                best, bi = 1e9, 0
                for i, (sx, sy, wx, wy) in enumerate(seeds):
                    d = max(abs(px - 0.5 - sx) * wx, abs(py - 0.5 - sy) * wy)
                    if d < best:
                        best, bi = d, i
                if bi not in tops:
                    sx, sy, _wx, _wy = seeds[bi]
                    tops[bi] = height(sx + 0.5, sy + 0.5) + 4.0 * vx.noise((bi, 0, 0), seed) - 2.0
                h = int(round(min(tops[bi], hl + slope)))
                h = max(1, h)
                if hmax:
                    h = min(h, hmax)
                macro[key] = (bi, h)
            if macro[key] is not None:
                cols[(x, y)] = macro[key]
    joint = C.col("concrete", 0.62)
    for (x, y), (bi, h) in cols.items():
        kind = block_kind(bi, seed)
        mat, base = block_base(kind, bi, seed)
        for z in range(h):
            m.set(x, y, z, mat, color=spot((x, y, z), base, seed + 5, 0.06, speck))
        if kind == "carrelage":
            tile = C.col("plaster", 0.96 + 0.06 * vx.noise((bi, 5, 5), seed))
            m.set(x, y, h - 1, "stone", color=joint if (x % 4 == 0 or y % 4 == 0) else tile)
        elif kind == "peint":
            m.set(x, y, h - 1, "concrete", color=spot((x, y, h), C.col("tile_green"), seed + 6, 0.04))
    return cols


def top_at(m, x, y, zmax=200):
    """Première cellule vide au-dessus de la colonne (x, y)."""
    z = zmax
    while z > 0 and (x, y, z - 1) not in m.vox:
        z -= 1
    return z


def rebar(m, x, y, z, up, bend=None, seed=0, zmax=None):
    """Fer à béton rouillé qui sort des gravats : `up` cubes vers le haut
    depuis (x, y, z), puis `bend` (dx, dy, n) : coude d'un quart de tour ;
    `zmax` : plafond (hauteur `h` du catalogue, en cubes)."""
    if zmax is not None:
        up = min(up, zmax - z)
        if up <= 0:
            return
    rust = C.col("rust")
    for k in range(up):
        m.set(x, y, z + k, "metal", color=vx.tone(rust, 0.85 + 0.3 * vx.noise((x, y, z + k), seed)))
    if bend:
        dx, dy, n = bend
        for k in range(1, n + 1):
            m.set(x + dx * k, y + dy * k, z + up - 1, "metal", color=vx.tone(rust, 0.8 + 0.3 * vx.noise((k, x, y), seed)))


def board_piece(m, x0, x1, y0, y1, z, seed, base=None, nails=True):
    """Planche (pavé d'un cube d'épaisseur) : veinage le long de la planche
    (deux teintes par rangée), clous sombres aux bouts, bouts cassés (un
    coin manquant)."""
    base = base or C.col("wood", 0.8 + 0.35 * vx.noise((x0, y0, z), seed))
    along_x = (x1 - x0) >= (y1 - y0)
    for x in range(x0, x1):
        for y in range(y0, y1):
            # Bout cassé : un coin en moins à chaque extrémité.
            if along_x and ((x == x0 and y == y0) or (x == x1 - 1 and y == y1 - 1)):
                continue
            if not along_x and ((y == y0 and x == x1 - 1) or (y == y1 - 1 and x == x0)):
                continue
            row = y if along_x else x
            f = 1.0 + 0.07 * (1 if vx.noise((row, z, 1), seed) > 0.5 else -1)
            m.set(x, y, z, "wood", color=vx.tone(base, f))
    if nails:
        nail = C.col("metal_dark")
        if along_x:
            pts = [(x0 + 1, (y0 + y1) // 2), (x1 - 2, (y0 + y1) // 2)]
        else:
            pts = [((x0 + x1) // 2, y0 + 1), ((x0 + x1) // 2, y1 - 2)]
        C.paint(m, [((px, py, z), "+z") for px, py in pts], nail)


def plank_on(m, x0, x1, y0, y1, seed, base=None):
    """Planche rigide posée sur ce qu'il y a dessous (son point le plus
    haut) : à placer sur un replat (pied du tas), pour ne pas pendre dans
    le vide."""
    z = max(top_at(m, x, y) for x in range(x0, x1) for y in range(y0, y1))
    board_piece(m, x0, x1, y0, y1, z, seed, base)
    return z


def slab(m, x0, x1, y0, y1, seed, kind="carrelage"):
    """Morceau de dalle (2 cubes) posé sur les gravats : béton, dessus de
    faïence blanche à joints ou d'enduit vert d'eau."""
    z = max(top_at(m, x, y) for x in range(x0, x1) for y in range(y0, y1)) - 1
    z = max(0, z)
    base = C.col("concrete", 0.85 + 0.2 * vx.noise((x0, y0, 9), seed))
    for x in range(x0, x1):
        for y in range(y0, y1):
            # Bord cassé en escalier.
            if (x in (x0, x1 - 1) or y in (y0, y1 - 1)) and vx.noise((x, y, 4), seed) < 0.35:
                continue
            m.set(x, y, z, "concrete", color=C.grain((x, y, z), base, seed, 0.04, 2))
            if kind == "carrelage":
                c = C.col("concrete", 0.62) if (x % 4 == 0 or y % 4 == 0) else C.col("plaster")
            else:
                c = C.col("tile_green", 0.95 + 0.08 * vx.noise((x, y, 3), seed))
            m.set(x, y, z + 1, "stone", color=c)


def scatter_bits(m, x0, x1, y0, y1, n, seed, hmax=3, near=None):
    """Petits éclats posés au sol autour d'un tas (1 à 3 cubes de haut) ;
    `near(x, y)` : seulement là où il est vrai (au pied du tas)."""
    for i in range(n):
        x = x0 + int(vx.noise((i, 0, 1), seed) * (x1 - x0))
        y = y0 + int(vx.noise((i, 0, 2), seed) * (y1 - y0))
        if near is not None and not near(x, y):
            continue
        w = 1 + int(vx.noise((i, 0, 3), seed) * 3)
        d = 1 + int(vx.noise((i, 0, 4), seed) * 3)
        h = 1 + int(vx.noise((i, 0, 5), seed) * hmax)
        r = vx.noise((i, 0, 6), seed)
        if r < 0.6:
            base = C.col("concrete", 0.8 + 0.3 * vx.noise((i, 1, 1), seed))
            mat = "concrete"
        elif r < 0.8:
            base = C.col("plaster")
            mat = "stone"
        else:
            base = C.col("stone", 0.9)
            mat = "stone"
        for xx in range(x, x + w):
            for yy in range(y, y + d):
                for zz in range(h):
                    if (xx, yy, zz) not in m.vox:
                        m.set(xx, yy, zz, mat, color=base)


# ------------------------------------------------------------------ tas

def gravats():
    """Tas de gravats (ancien rubble_heap_b) : 3 × 3 m, 1,4 m de haut ;
    blocs de béton, de faïence et d'enduit, deux fers, une planche."""
    m = vx.Model(C.CUBE)
    h = bumps(((0, 0, 29, 29, 12), (2, 0, 19, 18, 26)))
    rubble(m, -30, 30, -30, 30, h, seed=11, sp=7, hmax=26)
    slab(m, -14, -3, 6, 14, 12)
    plank_on(m, -22, -6, -24, -22, 13)
    rebar(m, 3, 2, top_at(m, 3, 2), 5, (1, 0, 3), 14, zmax=30)
    rebar(m, -8, -6, top_at(m, -8, -6), 4, None, 15, zmax=30)
    scatter_bits(m, -30, 30, -30, 30, 18, 16, near=lambda x, y: 0 < h(x, y) < 4 or h(x * 0.9, y * 0.9) > 0)
    return m


def gros_gravats():
    """Gros éboulement (ancien rubble_heap_a) : 5 × 4 m, 2,2 m de haut, deux
    sommets ; dalles, fers tordus, planches, tuyau d'acier."""
    m = vx.Model(C.CUBE)
    h = bumps(((0, 0, 49, 39, 16), (-6, 4, 30, 24, 40), (20, -10, 20, 18, 30)))
    rubble(m, -50, 50, -40, 40, h, seed=21, sp=9, hmax=40, q=2, speck=0.1)
    slab(m, -30, -16, -18, -8, 22)
    slab(m, 18, 30, 8, 18, 23, kind="peint")
    plank_on(m, -42, -24, 20, 22, 24)
    plank_on(m, 32, 34, -36, -22, 25, C.col("wood_dark"))
    # Tuyau d'acier (2 × 2 cubes) qui dépasse du tas.
    z = top_at(m, 10, 2) - 2
    for x in range(4, 34):
        for y in (1, 2):
            for zz in (z, z + 1):
                m.set(x, y, zz, "metal", color=C.col("steel", 0.9 if zz == z else 1.05))
    rebar(m, -6, 4, top_at(m, -6, 4), 6, (0, 1, 3), 26, zmax=46)
    rebar(m, -2, 1, top_at(m, -2, 1), 5, None, 27, zmax=46)
    rebar(m, 20, -10, top_at(m, 20, -10), 6, (-1, 0, 2), 28, zmax=46)
    scatter_bits(m, -50, 50, -40, 40, 26, 29, near=lambda x, y: 0 < h(x, y) < 4 or h(x * 0.9, y * 0.9) > 0)
    return m


def wall_piece(m, x0, x1, y0, y1, tops, seed):
    """Pan de mur d'hôpital resté debout : âme de béton, enduit vert d'eau
    en bas (soubassement, liseré foncé) et blanc en haut sur la face -Y,
    plâtre blanc derrière, bord supérieur cassé en marches (`tops(x)`), fers
    qui dépassent."""
    for x in range(x0, x1):
        top = tops(x)
        for y in range(y0, y1):
            for z in range(top):
                face = y in (y0, y1 - 1)
                if face and y == y0:
                    if z < 24:
                        c = C.grain((x, y, z), C.col("tile_green"), seed, 0.04, 2)
                    elif z < 26:
                        c = C.col("tile_green", 0.6)
                    else:
                        c = C.grain((x, y, z), C.col("plaster"), seed, 0.03, 2)
                    mat = "concrete"
                elif face:
                    c = C.grain((x, y, z), C.col("plaster", 0.95), seed, 0.03, 2)
                    mat = "concrete"
                else:
                    c = C.grain((x, y, z), C.col("concrete", 0.9), seed + 1, 0.05, 2)
                    mat = "concrete"
                m.set(x, y, z, mat, color=c)
    # Cassure : le béton apparaît sur le dessus cassé et les bouts.
    for x in range(x0, x1):
        top = tops(x)
        for y in range(y0, y1):
            if (x, y, top - 1) in m.vox:
                C.paint(m, [((x, y, top - 1), "+z")], C.grain((x, y, top), C.col("concrete", 0.85), seed + 2, 0.05, 2))


def eboulis():
    """Mur effondré (ancien rubble_heap_c) : 6 × 3 m ; pan de mur d'hôpital
    resté debout (2,8 m) au-dessus d'un éboulement en blocs, dalle de
    plafond, fers, planches."""
    m = vx.Model(C.CUBE)
    h = bumps(((0, 0, 59, 30, 12), (-20, 1, 26, 18, 30), (26, -3, 20, 16, 24)))
    rubble(m, -60, 60, -30, 30, h, seed=31, sp=8, hmax=40, q=2, speck=0.1)

    # Pan de mur : x -1,9 .. -0,2 m, 0,3 m d'épaisseur ; bord supérieur
    # cassé en marches irrégulières (haut à gauche, brèche, retombée à droite).
    prof = (46, 50, 52, 54, 54, 55, 55, 52, 52, 53, 53, 53, 49, 49, 46, 46, 46, 50, 50, 47, 44, 44,
            40, 37, 37, 33, 30, 30, 26, 22, 18, 14, 12, 10)

    def tops(x):
        i = x + 38
        return prof[i] if 0 <= i < len(prof) else 0
    wall_piece(m, -38, -38 + len(prof), -2, 4, tops, 32)
    # Panneau d'hôpital à croix rouge peint sur la face avant (-Y), à moitié
    # arraché (coin manquant).
    for x in range(-30, -22):
        for z in range(34, 42):
            if x >= -24 and z >= 40:
                continue
            arm = (-27 <= x <= -26 and 35 <= z <= 40) or (-29 <= x <= -24 and 37 <= z <= 38)
            C.paint(m, [((x, -2, z), "-y")], C.col("medic_red") if arm else C.col("paint_white"))
    for x, up in ((-31, 3), (-27, 2), (-22, 3), (-15, 2), (-10, 3)):
        for y in (-1, 2):
            rebar(m, x, y, tops(x), up, None, 33 + x, zmax=58)
    slab(m, 6, 22, -8, 4, 34, kind="peint")
    slab(m, -50, -40, -12, -2, 35)
    plank_on(m, 36, 52, 16, 18, 36)
    plank_on(m, -8, -6, -28, -16, 37, C.col("wood_dark"))
    rebar(m, 26, -3, top_at(m, 26, -3), 6, (1, 0, 3), 38, zmax=58)
    scatter_bits(m, -60, 60, -30, 30, 30, 39, near=lambda x, y: 0 < h(x, y) < 4 or h(x * 0.92, y * 0.9) > 0)
    return m


def debris_epars():
    """Débris épars au sol (ancien debris_scatter) : 3 × 3 m, 0,25 m au
    plus ; éclats de béton et de faïence, morceaux de verre, bouts de
    planches, fers, une plaque de faux plafond. Sans ombre portée."""
    m = vx.Model(C.CUBE)
    seed = 41
    for i in range(46):
        x = -28 + int(vx.noise((i, 0, 1), seed) * 54)
        y = -28 + int(vx.noise((i, 0, 2), seed) * 54)
        w = 2 + int(vx.noise((i, 0, 3), seed) * 4)
        d = 2 + int(vx.noise((i, 0, 4), seed) * 4)
        # Éclats plats pour la plupart (1 cube), quelques morceaux de 2 ou 3.
        h = 1 + int(vx.noise((i, 0, 5), seed) * 1.6) + (1 if vx.noise((i, 0, 7), seed) > 0.85 else 0)
        r = vx.noise((i, 0, 6), seed)
        for xx in range(x, x + w):
            for yy in range(y, y + d):
                if (xx in (x, x + w - 1)) and (yy in (y, y + d - 1)) and w > 2 and d > 2:
                    continue      # coins abattus
                for zz in range(h):
                    if r < 0.55:
                        c, mat = C.col("concrete", 0.78 + 0.3 * vx.noise((i, 1, 1), seed)), "concrete"
                    elif r < 0.75:
                        c, mat = (C.col("plaster") if zz == h - 1 else C.col("concrete", 0.9)), "stone"
                    elif r < 0.85:
                        c, mat = C.col("tile_green", 0.95), "concrete"
                    else:
                        c, mat = C.col("stone", 0.9 + 0.2 * vx.noise((i, 2, 1), seed)), "stone"
                    m.set(xx, yy, zz, mat, color=c)
    # Éclats de verre (fenêtres, vitres de laboratoire).
    for i in range(16):
        x = -27 + int(vx.noise((i, 3, 1), seed) * 54)
        y = -27 + int(vx.noise((i, 3, 2), seed) * 54)
        for dx, dy in ((0, 0), (1, 0), (0, 1))[:1 + i % 3]:
            if (x + dx, y + dy, 0) not in m.vox:
                m.set(x + dx, y + dy, 0, "glass", color=C.col("crystal", 0.95 + 0.1 * vx.noise((i, 3, 3), seed)))
    # Bouts de planches et de fers.
    board_piece(m, -24, -12, 10, 12, 0, seed + 1)
    board_piece(m, 8, 10, -26, -14, 0, seed + 2, C.col("wood_dark"))
    board_piece(m, 14, 26, 18, 20, 0, seed + 3)
    for x0, y0, n, ax in ((-20, -18, 8, "x"), (16, 2, 7, "y"), (-6, 22, 6, "x")):
        for k in range(n):
            x, y = (x0 + k, y0) if ax == "x" else (x0, y0 + k)
            m.set(x, y, 0, "metal", color=vx.tone(C.col("rust"), 0.85 + 0.3 * vx.noise((k, x0, y0), seed)))
    # Plaque de faux plafond cassée (blanche, trame grise).
    for x in range(-6, 6):
        for y in range(-8, 2):
            if (x + y) % 7 == 0 and vx.noise((x, y, 0), seed) < 0.5:
                continue
            c = C.col("plaster", 0.92) if (x % 3 and y % 3) else C.col("plaster", 0.78)
            m.set(x, y, 0, "stone", color=c)
    return m


debris_epars.kind = "ns"


# ------------------------------------------------------------------ planches

def planches():
    """Planches au sol (ancien debris_planks) : 1,9 × 1,4 m, 0,4 m au plus ;
    planches croisées sur trois rangs, deux appuyées (en marches), un côté
    de caisse (lattes sur deux traverses)."""
    m = vx.Model(C.CUBE)
    s = 51
    # Rang du bas, à plat.
    board_piece(m, -18, 16, -12, -9, 0, s)
    board_piece(m, -16, 14, 4, 7, 0, s + 1)
    board_piece(m, -10, -7, -13, 13, 0, s + 2, C.col("wood_dark"))
    board_piece(m, 6, 9, -14, 12, 0, s + 3)
    # Rang du milieu, en travers (planches rigides : posées sur le point le
    # plus haut de ce qu'elles croisent).
    for x0, x1, y0, y1, k, base in ((-19, 12, -4, -1, 4, None), (-2, 1, -12, 14, 5, C.col("wood", 0.75)),
                                    (-14, 18, 9, 12, 6, C.col("wood_dark", 1.1))):
        z = max(top_at(m, x, y) for x in range(x0, x1) for y in range(y0, y1))
        board_piece(m, x0, x1, y0, y1, z, s + k, base)
    # Côté de caisse cassé : 4 lattes sur 2 traverses (pochoir rouge).
    crate = C.col("wood", 1.12)
    zc = max(top_at(m, x, y) for x in range(8, 19) for y in range(-12, -1))
    # Planche appuyée sur le côté de caisse : pente en marches (un cube de
    # montée tous les 5), marches reliées par leurs faces.
    base = C.col("wood", 0.95)
    zt = zc + 2
    for x in range(-16, 14):
        z = min(zt, max(0, (x + 16) // 5))
        zp = min(zt, max(0, (x + 15) // 5))
        for y in range(-8, -5):
            for zz in range(min(z, zp), max(z, zp) + 1):
                m.set(x, y, zz, "wood", color=vx.tone(base, 1.0 + 0.07 * (1 if vx.noise((y, 0, 1), s + 7) > 0.5 else -1)))
    for x in (9, 16):
        for y in range(-12, -1):
            m.set(x, y, zc, "wood", color=C.col("wood", 0.8))
    for k in range(4):
        y0 = -12 + k * 3
        for x in range(8 + (k == 3), 19 - (k == 0)):
            for y in range(y0, y0 + 2):
                m.set(x, y, zc + 1, "wood", color=C.grain((x, y, zc), crate, s + 9, 0.05, 2))
    C.paint(m, [((x, y, zc + 1), "+z") for x in (12, 13, 14) for y in (-7,)] +
            [((13, y, zc + 1), "+z") for y in (-9, -8, -6)], C.col("medic_red", 0.85))
    return m


# ------------------------------------------------------------------ poutre

def poutre():
    """Poutre tombée (ancien debris_beam) : poutre de béton du plafond (6 m,
    0,4 × 0,5 m), sous-face enduite, chemin de câbles d'acier sur le flanc ;
    un bout au sol, l'autre posé à 1,2 m sur un tas de gravats (+X) ; la
    pente devient des marches de 2 cubes. Bouts cassés, fers qui dépassent."""
    m = vx.Model(C.CUBE)
    # Tas qui soutient le bout levé (pavé de collision : x 1,6 .. 3,0 m).
    h = bumps(((46, 0, 17, 13, 30),))
    rubble(m, 28, 64, -14, 14, h, seed=61, sp=6, hmax=26)
    xs, xe = -65, 53
    body = C.col("concrete", 0.95)
    for x in range(xs, xe):
        zb = 2 * ((x - xs) * 24 // (xe - xs) // 2)
        for y in range(-4, 4):
            for z in range(zb, zb + 10):
                # Bouts cassés : arêtes ébréchées.
                if x in (xs, xs + 1, xe - 2, xe - 1) and vx.noise((x, y, z), 62) < 0.45 and not (-2 <= y < 2 and zb + 3 <= z < zb + 7):
                    continue
                if z == zb:
                    c = C.grain((x, y, z), C.col("plaster", 0.95), 63, 0.03, 2)
                else:
                    c = C.grain((x, y, z), body, 64, 0.04, 2)
                m.set(x, y, z, "concrete", color=c)
        # Liseré d'enduit vert d'eau sur les flancs (haut de la poutre).
        for y, d in ((-4, "-y"), (3, "+y")):
            C.paint(m, [((x, y, zb + 8), d), ((x, y, zb + 9), d)], C.col("tile_green", 0.95))
        # Chemin de câbles (acier) le long du flanc -Y, câbles noirs dessus.
        if xs + 4 <= x < xe - 4:
            m.set(x, -5, zb + 5, "metal", color=C.col("steel", 1.0 if x % 6 else 0.8))
            m.set(x, -5, zb + 6, "rubber", color=C.col("rubber", 2.5))
    # Fers qui sortent des deux bouts cassés.
    for y in (-3, 0, 2):
        for k in range(1, 4 + (y == 0)):
            m.set(xs - k, y, 2 + (y == 0), "metal", color=vx.tone(C.col("rust"), 0.85 + 0.3 * vx.noise((k, y, 0), 65)))
        zb = 22
        for k in range(1, 4 + (y == 2)):
            m.set(xe - 1 + k, y, zb + 6, "metal", color=vx.tone(C.col("rust"), 0.85 + 0.3 * vx.noise((k, y, 1), 65)))
    # Éclats au pied du tas et sous le bout tombé au sol.
    scatter_bits(m, -68, 64, -14, 14, 30, 66, near=lambda x, y: x > 26 or x < -54)
    return m


# ------------------------------------------------------------------ lustre

def ring_cells(rx, ry, w):
    """Cellules (x, y) d'un anneau elliptique en escalier, `w` cubes de
    large, autour de (0, 0)."""
    out = []
    for x in range(-rx - 1, rx + 1):
        for y in range(-ry - 1, ry + 1):
            d = math.sqrt(((x + 0.5) / rx) ** 2 + ((y + 0.5) / ry) ** 2)
            if 1.0 - w / min(rx, ry) <= d < 1.0:
                out.append((x, y))
    return out


def lustre_tombe():
    """Lustre tombé (ancien chandelier_fallen) : lustre à pampilles du hall
    écrasé au sol, 3,5 × 3 m, 1,5 m ; grande couronne de laiton à plat,
    douze bras en marches jusqu'aux bobèches (bougies debout ou renversées),
    fût central debout cassé en haut, petite couronne affaissée, guirlandes
    de pampilles de verre, pampilles éparpillées, chaîne au sol."""
    m = vx.Model(C.CUBE)
    s = 71
    brass = C.col("brass")

    def b(c, f=1.0):
        m.set(*c, "metal", color=spot(c, vx.tone(brass, f), s, 0.08, 0.18))

    def crystal(c, f=1.0):
        m.set(*c, "glass", color=C.col("crystal", f))

    # Grande couronne : anneau de 2 cubes de large, 2 de haut, au sol.
    for x, y in ring_cells(28, 23, 2):
        for z in range(2):
            b((x, y, z))
    # Liseré sombre sur le dessus de la couronne (gorge du laiton).
    C.paint(m, [((x, y, 1), "+z") for x, y in ring_cells(27, 22, 1)], C.col("brass", 0.7))
    # Fût central debout : profil de vase en paliers, cassé en haut.
    prof = ((0, 2, 5), (2, 6, 3), (6, 7, 4), (7, 12, 5), (12, 14, 3), (14, 16, 4), (16, 22, 2), (22, 24, 3), (24, 29, 1))
    for z0, z1, r in prof:
        for x in range(-r, r):
            for y in range(-r, r):
                for z in range(z0, z1):
                    b((x, y, z), 1.12 if (z1 - z0) <= 2 else 1.0)
    # Bout de chaîne cassé au sommet (maillons de deux teintes).
    for z in range(29, 30):
        b((0, 0, z), 0.75)
    # Douze bras : du fût (z 9) à la couronne (z 2), traits reliés par faces.
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        ca, sa = math.cos(a), math.sin(a)
        p0 = (int(math.floor(ca * 5)), int(math.floor(sa * 5)), 9)
        p1 = (int(math.floor(ca * 26.5)), int(math.floor(sa * 21.5)), 2)
        for c in line3(p0, p1):
            b(c)
        x, y, _z = p1
        # Bobèche (2 × 2) sur la couronne, bougie blanche et ampoule de verre.
        for dx in (0, -1):
            for dy in (0, -1):
                b((x + dx, y + dy, 2), 1.18)
        if k % 4 == 1:
            # Bougie renversée au sol, vers l'extérieur.
            sx = 1 if ca > 0 else -1
            for i in range(2, 5):
                if (x + sx * i, y, 0) not in m.vox:
                    m.set(x + sx * i, y, 0, "stone", color=C.col("paint_white", 0.95))
        else:
            for z in range(3, 6):
                m.set(x, y, z, "stone", color=C.col("paint_white", 0.97))
            crystal((x, y, 6), 1.05)
    # Petite couronne (anneau d'un cube), affaissée en marches : z 13 à 17.
    def zr(x):
        return 13 + (x + 15) * 5 // 31
    for x, y in ring_cells(15, 13, 1):
        b((x, y, zr(x)), 1.05)
    # Huit bras courts du fût à la petite couronne.
    for k in range(8):
        a = 2 * math.pi * k / 8
        p1 = (int(math.floor(math.cos(a) * 14.5)), int(math.floor(math.sin(a) * 12.5)), 0)
        p1 = (p1[0], p1[1], zr(p1[0]))
        p0 = (int(math.floor(math.cos(a) * 2.5)), int(math.floor(math.sin(a) * 2.5)), 18)
        for c in line3(p0, p1):
            b(c)
    # Guirlandes de pampilles : de la petite couronne à la grande (traits
    # reliés par faces, un maillon de laiton tous les quatre cubes).
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        p0 = (int(math.floor(math.cos(a) * 14.5)), int(math.floor(math.sin(a) * 12.5)), 0)
        p0 = (p0[0], p0[1], zr(p0[0]) - 1)
        p1 = (int(math.floor(math.cos(a) * 26.5)), int(math.floor(math.sin(a) * 21.5)), 2)
        for i, c in enumerate(line3(p0, p1)[:-1]):
            if c in m.vox:
                continue
            if i % 4 == 3:
                b(c, 1.15)
            else:
                crystal(c, 0.95 if i % 2 else 1.05)
    # Pampilles éparpillées au sol (gouttes de 1 ou 2 cubes).
    for i in range(30):
        r = 0.4 + 0.6 * vx.noise((i, 0, 1), s)
        a = 6.283 * vx.noise((i, 0, 2), s)
        x, y = int(math.floor(math.cos(a) * r * 33)), int(math.floor(math.sin(a) * r * 28))
        if (x, y, 0) in m.vox or (x + 1, y, 0) in m.vox:
            continue
        crystal((x, y, 0), 0.95 + 0.1 * vx.noise((i, 0, 3), s))
        if i % 3 == 0:
            crystal((x + 1, y, 0), 0.9)
    # Chaîne tombée au sol (maillons alternés), de la couronne vers -X -Y.
    for i, c in enumerate(line3((-22, -14, 0), (-33, -24, 0))):
        if c not in m.vox:
            b(c, 1.15 if i % 2 else 0.8)
    return m


BUILDERS = {
    "gravats": gravats,
    "gros_gravats": gros_gravats,
    "eboulis": eboulis,
    "debris_epars": debris_epars,
    "planches": planches,
    "poutre": poutre,
    "lustre_tombe": lustre_tombe,
}
# Anciens modèles .glb (planches avant / après, --before).
BEFORE = {
    "gravats": "rubble_heap_b",
    "gros_gravats": "rubble_heap_a",
    "eboulis": "rubble_heap_c",
    "debris_epars": "debris_scatter",
    "planches": "debris_planks",
    "poutre": "debris_beam",
    "lustre_tombe": "chandelier_fallen",
}

if __name__ == "__main__":
    C.main(BUILDERS, BEFORE)
