# Décors CUBIQUES, famille MOBILIER ET STOCKAGE (lot 2 de
# docs/VOXEL_DECOR_PLAN.md) : caisses, sacs de sable... Cubes de 5 cm,
# tools/blender/voxel_props/common.py (conventions, export, planches).
#
#   sh tools/blender.sh tools/blender/voxel_props/mobilier.py [ids...] [--sheet DOSSIER] [--before DOSSIER]
#
# Chaque décor garde l'origine, l'emprise et les collisions de l'ancien
# (MapCatalog.PREFABS : « boxes », ou voxel/<id>.collision.json).
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import voxel_lib as vx  # noqa: E402


# ------------------------------------------------------------------ caisses

def road_case(m, x0, x1, y0, y1, z0, z1, body, seed, label=None):
    """Caisse de transport (matériel de laboratoire) : corps texturé,
    cornières d'acier sur les arêtes verticales, cerclages en bas, en haut et
    au joint du couvercle, coins renforcés, poignées sur les petits côtés,
    deux fermetures en façade (-Y), étiquette peinte facultative."""
    C.fill(m, x0, x1, y0, y1, z0, z1, "rubber", body, seed=seed, amp=0.035, levels=2)
    steel = C.col("steel")
    dark = C.col("metal_dark")
    lid = z1 - 4
    for x in range(x0, x1):
        for y in range(y0, y1):
            edge_x = x in (x0, x1 - 1)
            edge_y = y in (y0, y1 - 1)
            if not (edge_x or edge_y):
                continue
            for z in range(z0, z1):
                if edge_x and edge_y:
                    # Cornière verticale ; coins emboutis plus clairs.
                    corner = z < z0 + 2 or z >= z1 - 2
                    m.set(x, y, z, "metal", color=C.grain((x, y, z), C.col("steel", 1.12 if corner else 1.0), seed + 1, 0.05, 2))
                elif z in (z0, z1 - 1):
                    m.set(x, y, z, "metal", color=C.grain((x, y, z), steel, seed + 2, 0.05, 2))
                elif z == lid:
                    m.set(x, y, z, "metal", color=dark)
    # Poignées encastrées sur les petits côtés (±X) : cuvette sombre, barre d'acier.
    zc = z0 + (z1 - z0) * 55 // 100
    yc = (y0 + y1) // 2
    for x, d in ((x0, "-x"), (x1 - 1, "+x")):
        C.paint(m, [((x, y, z), d) for y in range(yc - 3, yc + 3) for z in (zc - 1, zc + 1)], C.col("rubber"))
        C.paint(m, [((x, y, zc), d) for y in range(yc - 3, yc + 3)], steel)
    # Fermetures : deux cubes d'acier en saillie sous le couvercle.
    w = x1 - x0
    for fx in (x0 + w // 4, x1 - 1 - w // 4):
        m.set(fx, y0 - 1, lid, "metal", color=C.col("steel", 1.1))
        m.set(fx, y0 - 1, lid - 1, "metal", color=C.col("steel", 0.9))
    if label:
        label(m, x0, x1, y0, z0, lid)


def label_cross(m, x0, x1, y0, z0, z1):
    """Plaque blanche à croix rouge (matériel médical) peinte en façade."""
    cx, cz = (x0 + x1) // 2, (z0 + z1) // 2
    for x in range(cx - 4, cx + 4):
        for z in range(cz - 3, cz + 4):
            arm = (cx - 1 <= x <= cx) or (cz - 1 <= z <= cz + 0)
            inner = cx - 3 <= x <= cx + 2 and cz - 2 <= z <= cz + 2
            c = C.col("medic_red") if (arm and inner) else C.col("paint_white")
            C.paint(m, [((x, y0, z), "-y")], c)


def label_hazard(m, x0, x1, y0, z0, z1):
    """Bande de danger jaune et noire en façade (produits du laboratoire)."""
    zb = (z0 + z1) // 2
    for x in range(x0 + 2, x1 - 2):
        for z in range(zb - 2, zb + 2):
            c = C.col("hazard_yellow") if (x + z) % 4 < 2 else C.col("rubber")
            C.paint(m, [((x, y0, z), "-y")], c)


def label_arrows(m, x0, x1, y0, z0, z1):
    """Deux flèches « haut » au pochoir blanc (sens de la caisse)."""
    white = C.col("paint_white", 0.92)
    zb = z0 + 3
    for ax in (x0 + (x1 - x0) // 3, x0 + 2 * (x1 - x0) // 3):
        cells = [((ax, y0, z), "-y") for z in range(zb, zb + 5)]
        cells += [((ax - 1, y0, zb + 3), "-y"), ((ax + 1, y0, zb + 3), "-y"),
                  ((ax - 2, y0, zb + 2), "-y"), ((ax + 2, y0, zb + 2), "-y")]
        C.paint(m, cells, white)


def caisses():
    """Pile de caisses de transport (ancien stage_crates) : cinq caisses aux
    pavés de stage_crates.collision.json arrondis à 5 cm et remis d'aplomb
    (les collisions, légèrement tournées, restent celles d'avant)."""
    m = vx.Model(C.CUBE)
    # Godot (x, z) -> Blender (x, y = -z), en cubes : [x0, x1) [y0, y1) [z0, z1).
    road_case(m, -24, 0, 1, 17, 0, 16, C.col("case_black"), 1, label_cross)
    road_case(m, 5, 25, 0, 18, 0, 18, C.col("case_grey"), 2, label_hazard)
    road_case(m, 0, 22, -17, -3, 0, 14, C.col("case_black", 1.15), 3, label_arrows)
    road_case(m, -24, -6, -17, -5, 0, 12, C.col("paint_olive", 0.8), 4)
    road_case(m, -20, -2, 2, 16, 16, 30, C.col("steel", 0.62), 5, label_cross)
    return m


# ------------------------------------------------------------------ sacs de sable

def sandbag(m, x0, yc, z0, seed):
    """Sac de sable de 10 × 14 × 6 cubes (0,5 × 0,7 × 0,3 m), long côté en
    profondeur : bords arrondis en escalier, bouts pincés (liens), couture
    sur le dessus, toile de jute un peu différente par sac."""
    base = C.col("burlap", 0.88 + 0.22 * vx.noise((x0, yc, z0), 77))
    x1 = x0 + 10
    y0, y1 = yc - 7, yc + 7

    def keep(x, y, z):
        dz = z - z0
        end = x in (x0, x1 - 1)
        if end:
            # Bout pincé : plus étroit (liens) ; le sillon entre deux sacs reste fermé.
            return y0 + 2 <= y < y1 - 2
        if dz == 0 or dz == 5:
            return x0 < x < x1 - 1 and y0 + 1 <= y < y1 - 1
        return not ((x in (x0 + 1, x1 - 2)) and (y in (y0, y1 - 1)))

    C.fill(m, x0, x1, y0, y1, z0, z0 + 6, "fabric", base, seed=seed, amp=0.06, keep=keep)
    # Liens aux deux bouts, couture sur le dessus.
    tie = C.col("burlap", 0.55)
    for x in (x0, x1 - 1):
        for y in (y0 + 2, y1 - 3):
            for z in range(z0 + 1, z0 + 5):
                if (x, y, z) in m.vox:
                    m.set(x, y, z, "fabric", color=tie)
    seam = vx.tone(base, 0.8)
    C.paint(m, [((x, yc, z0 + 5), "+z") for x in range(x0 + 2, x1 - 2)], seam)


def sacs_sable():
    """Muret de sacs de sable (ancien décor construit par le jeu) : trois rangs
    décalés (4, 3 et 2 sacs), 2 m × 0,7 m, 0,9 m de haut."""
    m = vx.Model(C.CUBE)
    rows = ((0, (-20, -10, 0, 10)), (6, (-15, -5, 5)), (12, (-10, 0)))
    for z0, xs in rows:
        for i, x0 in enumerate(xs):
            jit = int(vx.noise((x0, i, z0), 5) * 3) - 1   # -1, 0 ou +1 cube
            sandbag(m, x0, jit, z0, seed=10 + z0 + i)
    return m


# ------------------------------------------------------------------ outils du lot 2

def round_ok(u, v, cu, cv, r):
    """Cellule (u, v) dans le disque de centre (cu, cv) (coin de cellule) et
    de rayon r (cubes) : les cylindres deviennent des prismes en escalier."""
    return (u + 0.5 - cu) ** 2 + (v + 0.5 - cv) ** 2 <= r * r


def front_cells(m, x0, x1, z0, z1, d="-y"):
    """Premières cellules vues depuis la direction `d` (« -y » : façade)
    pour chaque colonne (x, z) du rectangle : [(cellule, d)] à peindre."""
    out = []
    ys = sorted({c[1] for c in m.vox})
    order = ys if d == "-y" else list(reversed(ys))
    for x in range(x0, x1):
        for z in range(z0, z1):
            for y in order:
                if (x, y, z) in m.vox:
                    out.append(((x, y, z), d))
                    break
    return out


def turned_back(m, c):
    """Copie de `m` basculée sur le dos (quart de tour autour de X, l'arrière
    (+Y) vers le sol) : (x, y, z) -> (x, z, c - y) ; couleurs de faces
    suivies (+y -> -z, -y -> +z, +z -> +y, -z -> -y)."""
    dmap = {"+x": "+x", "-x": "-x", "+y": "-z", "-y": "+z", "+z": "+y", "-z": "-y"}
    out = vx.Model(m.cube)
    for (x, y, z), v in m.vox.items():
        out.vox[(x, z, c - y)] = v
    for (x, y, z, d), col in m.face_color.items():
        out.face_color[(x, z, c - y, dmap[d])] = col
    return out


def shifted(m, dx, dy, dz):
    """Copie de `m` décalée de (dx, dy, dz) cubes (recentrage)."""
    out = vx.Model(m.cube)
    for (x, y, z), v in m.vox.items():
        out.vox[(x + dx, y + dy, z + dz)] = v
    for (x, y, z, d), col in m.face_color.items():
        out.face_color[(x + dx, y + dy, z + dz, d)] = col
    return out


# ------------------------------------------------------------------ tonneaux

def drum(m, place, seed, label=None):
    """Bidon de 200 l (Ø 0,6 m, 0,9 m : disque de 12 cubes, 18 cubes de
    long) : `place(du, dv, w)` -> cellule (du, dv : disque de -6 à 5 ; w :
    axe, 0 = fond). Bords sertis et deux cerclages plus sombres, couvercle
    en creux à deux bouchons, coulures de rouille en bas ; `label` = (signe,
    face) : étiquette de danger sur le côté du disque où dv est extrême."""
    base = C.col("drum_blue", 0.88 + 0.24 * vx.noise(place(0, 0, 0), seed))
    r = 6.2
    disc = [(du, dv) for du in range(-6, 6) for dv in range(-6, 6) if round_ok(du, dv, 0, 0, r)]
    rim = {d for d in disc if not round_ok(d[0], d[1], 0, 0, r - 1.3)}
    for du, dv in disc:
        edge = (du, dv) in rim
        for w in range(18):
            if w == 17 and not edge:
                continue                       # couvercle en creux
            c = place(du, dv, w)
            if edge and w in (0, 17):
                col = vx.tone(base, 0.74)       # bord serti
            elif edge and w in (6, 11):
                col = vx.tone(base, 0.8)        # cerclage de roulement
            elif edge and vx.noise(c, seed + 3) < (0.2 if w < 3 else 0.02):
                col = C.grain(c, C.col("rust"), seed + 4, 0.1, 2)
            else:
                col = C.grain(c, base, seed + 5, 0.04, 2)
            m.set(*c, "metal", color=col)
    # Bouchons du couvercle.
    for du, dv in ((2, 1), (-3, -2)):
        m.set(*place(du, dv, 17), "metal", color=C.col("steel", 0.95))
    if label:
        sign, face = label
        for du in range(-2, 2):
            dvs = [dv for (u, dv) in disc if u == du]
            dv = min(dvs) if sign < 0 else max(dvs)
            for w in range(7, 12):
                inner = -1 <= du <= 0 and 8 <= w <= 10
                col = C.col("hazard_yellow") if inner else C.col("paint_white", 0.95)
                if inner and w == 9:
                    col = C.col("rubber")
                C.paint(m, [(place(du, dv, w), face)], col)


def tonneaux():
    """Bidons de produits chimiques (ancien blue_barrel_group) : quatre
    debout, deux empilés sur ceux du fond, un couché devant ; aux places de
    l'ancien groupe (recentré), remis d'aplomb ; 1,8 m de haut."""
    m = vx.Model(C.CUBE)

    def up(cx, cy, z0):
        return lambda du, dv, w: (cx + du, cy + dv, z0 + w)

    for i, (cx, cy) in enumerate(((-14, 9), (-1, 10))):
        drum(m, up(cx, cy, 0), 70 + i)
        drum(m, up(cx, cy, 18), 72 + i, label=(-1, "-y") if i == 1 else None)
    drum(m, up(11, 6, 0), 74, label=(-1, "-y"))
    drum(m, up(-6, -2, 0), 75, label=(-1, "-y"))
    # Couché, axe le long de X, étiquette sur le dessus.
    drum(m, lambda du, dv, w: (w, -9 + du, 6 + dv), 76, label=(1, "+z"))
    return m


# ------------------------------------------------------------------ table et chaises

def table_renversee():
    """Table renversée en barricade (ancien décor construit par le jeu) :
    plateau de bois dressé face à l'avant (1,6 × 0,85 m), ceinture et quatre
    pieds vers l'arrière (un pied cassé), impacts de balles sur le plateau."""
    m = vx.Model(C.CUBE)
    wood, dark = C.col("wood"), C.col("wood_dark")
    C.fill(m, -16, 16, -6, -5, 0, 17, "wood", wood, seed=21, amp=0.05, levels=3)
    # Chant du plateau plus sombre ; joints des planches (dessus du plateau, face avant).
    for x in range(-16, 16):
        for z in range(17):
            c = (x, -6, z)
            if x in (-16, 15) or z in (0, 16):
                m.set(*c, "wood", color=C.grain(c, dark, 22, 0.05, 2))
    C.paint(m, [((x, -6, z), "-y") for x in (-8, 0, 8) for z in range(1, 16)], vx.tone(wood, 0.62))
    # Ceinture sous le plateau.
    for x in range(-15, 15):
        for z in range(1, 16):
            if x in (-15, 14) or z in (1, 15):
                for y in (-5, -4):
                    m.set(x, y, z, "wood", color=C.grain((x, y, z), dark, 23, 0.05, 2))
    # Pieds (2 × 2 cubes) vers l'arrière ; le pied du haut à droite est cassé.
    for x0 in (-15, 13):
        for z0 in (1, 13):
            y1 = 4 if (x0, z0) == (13, 13) else 9
            C.fill(m, x0, x0 + 2, -5, y1, z0, z0 + 2, "wood", dark, seed=24 + x0 + z0, amp=0.06, levels=2)
            if y1 == 4:
                m.set(x0, 4, z0, "wood", color=C.col("wood", 1.1))        # écharde claire
            else:
                C.paint(m, [((x, y1 - 1, z), "+y") for x in (x0, x0 + 1) for z in (z0, z0 + 1)], C.col("rubber", 2.0))
    # Impacts de balles et rayures sur le plateau.
    for x, z in ((-11, 11), (-4, 6), (5, 12), (9, 4), (12, 9)):
        C.paint(m, [((x, -6, z), "-y")], C.col("charred", 0.8))
        C.paint(m, [((x + 1, -6, z), "-y"), ((x, -6, z + 1), "-y")], C.col("wood", 1.25))
    return m


def chair(m, x0, y0, z0, seed):
    """Chaise de collectivité DEBOUT (assise de contreplaqué, pieds en tube
    d'acier) : 8 × 9 cubes au sol, assise à 0,45 m, dossier à 0,85 m ;
    coin (x0, y0, z0), avant vers -Y. Sert aussi à la chaise renversée."""
    ply, tube = C.col("wood", 1.08), C.col("metal_dark", 1.2)
    # Pieds avant (jusqu'à l'assise) et arrière (montent jusqu'au dossier).
    for x in (x0, x0 + 7):
        for z in range(z0, z0 + 8):
            m.set(x, y0, z, "metal", color=tube)
        for z in range(z0, z0 + 17):
            m.set(x, y0 + 8, z, "metal", color=tube)
        # Traverse latérale basse.
        for y in range(y0 + 1, y0 + 8):
            m.set(x, y, z0 + 3, "metal", color=tube)
    # Assise : lattes de contreplaqué (une rangée sur deux, fentes d'un cube).
    for y in range(y0, y0 + 9):
        for x in range(x0, x0 + 8):
            if (y - y0) % 2 == 0 or x in (x0, x0 + 7):
                m.set(x, y, z0 + 8, "wood", color=C.grain((x, y, z0), ply, seed, 0.06, 2))
    # Dossier : deux lattes larges.
    for z in (z0 + 11, z0 + 12, z0 + 14, z0 + 15, z0 + 16):
        for x in range(x0, x0 + 8):
            m.set(x, y0 + 8, z, "wood", color=C.grain((x, z, 0), ply, seed + 1, 0.06, 2))
    # Charnières d'acier (pliage) peintes sur les pieds, sous l'assise.
    for x, d in ((x0, "-x"), (x0 + 7, "+x")):
        C.paint(m, [((x, y0, z0 + 7), d), ((x, y0 + 8, z0 + 7), d)], C.col("steel", 1.1))


def chaise():
    """Chaise pliante (ancienne folding_chair) : lattes de contreplaqué,
    pieds en tube d'acier remis d'aplomb ; 0,4 × 0,45 m, 0,85 m de haut."""
    m = vx.Model(C.CUBE)
    chair(m, -4, -5, 0, 31)
    return m


def chaise_renversee():
    """Chaise renversée sur le dos (ancien décor construit par le jeu) : la
    chaise de chaise() basculée d'un quart de tour, dossier au sol, assise
    debout, pieds pointés vers l'avant ; 0,45 m de haut, centrée."""
    up = vx.Model(C.CUBE)
    chair(up, -4, -5, 0, 32)
    m = turned_back(up, 3)
    lo, hi = m.bounds()
    # Couchée : dossier vers -Y ; on remet la longueur le long de X (quart de tour en Z).
    out = vx.Model(C.CUBE)
    dmap = {"+x": "-y", "-x": "+y", "+y": "+x", "-y": "-x", "+z": "+z", "-z": "-z"}
    for (x, y, z), v in m.vox.items():
        out.vox[(y, -x - 1, z - int(lo[2]))] = v
    for (x, y, z, d), col in m.face_color.items():
        out.face_color[(y, -x - 1, z - int(lo[2]), dmap[d])] = col
    lo, hi = out.bounds()
    return shifted(out, -int(lo[0] + hi[0]) // 2, -int(lo[1] + hi[1]) // 2, 0)


# ------------------------------------------------------------------ bureau

def bureau():
    """Bureau de médecin (ancien desk, 1,4 × 0,7 m) : plateau de bois sombre
    (dessus à 0,8 m ; « support » 0,78 m reste celui du catalogue), deux
    caissons à trois tiroirs (poignées d'acier), voile de fond, dossiers
    médicaux, feuilles, pot à crayons."""
    m = vx.Model(C.CUBE)
    dark, wood = C.col("wood_dark"), C.col("wood_dark", 1.25)
    C.fill(m, -14, 14, -7, 7, 15, 16, "wood", dark, seed=41, amp=0.05, levels=2)
    for x0, x1 in ((-14, -6), (6, 14)):
        C.fill(m, x0, x1, -6, 6, 0, 1, "wood", C.col("wood_dark", 0.7), seed=42, amp=0.04, levels=2)
        C.fill(m, x0, x1, -6, 6, 1, 15, "wood", wood, seed=43, amp=0.05, levels=2)
        # Trois tiroirs peints en façade (joints sombres), poignée en saillie.
        for k in range(3):
            zb = (1, 6, 10)[k]
            zt = (5, 9, 14)[k]
            C.paint(m, [((x, -6, zt), "-y") for x in range(x0, x1)], C.col("wood_dark", 0.55))
            xc = (x0 + x1) // 2
            m.set(xc - 1, -7, (zb + zt) // 2, "metal", color=C.col("steel", 1.1))
            m.set(xc, -7, (zb + zt) // 2, "metal", color=C.col("steel", 1.1))
        C.paint(m, [((x, -6, z), "-y") for x in (x0, x1 - 1) for z in range(1, 15)], C.col("wood_dark", 0.8))
    # Voile de fond et tiroir central.
    C.fill(m, -6, 6, 5, 6, 6, 15, "wood", wood, seed=44, amp=0.05, levels=2)
    C.fill(m, -6, 6, -6, -5, 13, 15, "wood", wood, seed=45, amp=0.05, levels=2)
    m.set(-1, -7, 13, "metal", color=C.col("steel", 1.1))
    m.set(0, -7, 13, "metal", color=C.col("steel", 1.1))
    # Feuilles éparses peintes sur le plateau.
    paper = C.col("paper")
    for x0, y0, w, d in ((-11, -5, 4, 5), (-6, -2, 4, 5), (2, -6, 5, 4), (-2, 1, 3, 4)):
        C.paint(m, [((x, y, 15), "+z") for x in range(x0, x0 + w) for y in range(y0, y0 + d)],
                vx.tone(paper, 0.95 + 0.08 * vx.noise((x0, y0, 0), 46)))
    # Pile de dossiers (chemises beiges et vertes, feuilles entre elles).
    for k, colr in enumerate((C.col("cardboard", 1.3), C.col("paper"), C.col("fabric_green", 1.1), C.col("cardboard", 1.2))):
        sx = k % 2
        C.fill(m, 6 + sx, 12 + sx, 0, 5, 16 + k, 17 + k, "fabric", colr, seed=47 + k, amp=0.03, levels=2)
    # Pot à crayons et deux crayons.
    m.set(-10, 3, 16, "metal", color=C.col("metal_dark"))
    m.set(-10, 3, 17, "metal", color=C.col("metal_dark"))
    m.set(-10, 3, 18, "wood", color=C.col("hazard_yellow"))
    # Tampon et carnet rouge.
    C.fill(m, -3, 0, -6, -4, 16, 17, "fabric", C.col("medic_red", 0.8), seed=48, amp=0.03, levels=2)
    return m


# ------------------------------------------------------------------ étagère

def etagere():
    """Étagère métallique de réserve (ancienne reel_shelf, 1,2 × 0,4 ×
    1,8 m) : montants d'angle, cinq tablettes, et du matériel de laboratoire
    rangé : boîtes de soins à croix rouge, cartons, classeurs, flacons."""
    m = vx.Model(C.CUBE)
    steel = C.col("steel", 0.9)
    for x in (-12, 11):
        for y in (-4, 3):
            for z in range(36):
                m.set(x, y, z, "metal", color=C.grain((x, y, z), steel, 51, 0.04, 2))
    levels = (1, 10, 19, 28, 35)
    for z in levels:
        for x in range(-12, 12):
            for y in range(-4, 4):
                m.set(x, y, z, "metal", color=C.grain((x, y, z), steel, 52, 0.02, 2))
        # Rebord avant plus sombre, porte-étiquettes blancs.
        C.paint(m, [((x, -4, z), "-y") for x in range(-12, 12)], C.col("steel", 0.68))
        C.paint(m, [((x, -4, z), "-y") for x in (-8, -7, 4, 5)], C.col("paint_white", 0.9))
    # Contenu des quatre étages (déterministe).
    for li, z0 in enumerate(l + 1 for l in levels[:4]):
        x = -11
        k = 0
        while x < 10:
            pick = vx.noise((li, k, 7), 53)
            room = 11 - x
            if pick < 0.3 and room >= 4:
                # Boîte de soins blanche à croix rouge.
                w, h = min(room, 5), 4 + (k % 2)
                C.fill(m, x, x + w, -3, 3, z0, z0 + h, "fabric", C.col("paint_white", 0.92), seed=54 + k, amp=0.03, levels=2)
                cx, cz = x + w // 2, z0 + h // 2
                C.paint(m, [((cx, -3, cz), "-y"), ((cx - 1, -3, cz), "-y"), ((cx + 1, -3, cz), "-y"),
                            ((cx, -3, cz - 1), "-y"), ((cx, -3, cz + 1), "-y")], C.col("medic_red"))
                x += w + 1
            elif pick < 0.55 and room >= 5:
                # Carton d'archives.
                w, h = min(room, 6), 5 + (k % 3 == 0)
                C.fill(m, x, x + w, -3, 3, z0, z0 + h, "fabric", C.col("cardboard", 0.9 + 0.2 * pick), seed=55 + k, amp=0.05, levels=2)
                C.paint(m, [((xx, -3, z0 + h - 2), "-y") for xx in range(x + 1, x + w - 1)], C.col("paper", 0.9))
                x += w + 1
            elif pick < 0.8:
                # Rangée de classeurs (dos colorés, étiquette blanche).
                n = min(room, 3 + k % 3)
                for i in range(n):
                    colr = (C.col("vinyl_teal"), C.col("medic_red", 0.8), C.col("case_grey", 1.4), C.col("paint_olive"))[(i + k + li) % 4]
                    C.fill(m, x + i, x + i + 1, -3, 2, z0, z0 + 6, "fabric", colr, seed=56 + i, amp=0.04, levels=2)
                    C.paint(m, [((x + i, -3, z0 + 4), "-y")], C.col("paper"))
                x += n + 1
            else:
                # Flacons (verre brun, bouchon blanc).
                for i in range(0, min(room, 4), 2):
                    for z in range(z0, z0 + 2):
                        m.set(x + i, -1, z, "glass", color=C.col("rust", 0.8))
                    m.set(x + i, -1, z0 + 2, "fabric", color=C.col("paint_white"))
                x += 5
            k += 1
    return m


# ------------------------------------------------------------------ fauteuils

def seat(m, broken=False):
    """Fauteuil d'auditorium (rangée de l'amphithéâtre de l'institut) DEBOUT,
    10 cubes de large (0,5 m : les copies du catalogue sont à 0,56 m) :
    flancs de fonte, accoudoirs de bois sombre, assise et dossier en skaï
    sarcelle, dossier « en chapeau » de 1,1 m incliné d'un cube vers l'arrière.
    `broken` : accoudoir gauche cassé, skaï du dossier déchiré (mousse)."""
    iron, arm = C.col("metal_dark", 1.1), C.col("wood_dark")
    vinyl = C.col("vinyl_teal")
    # Dossier : coque de bois et garniture, haut en escalier.
    for x in range(-5, 5):
        top = 19 + (abs(x + 0.5) < 4) + (abs(x + 0.5) < 3) + (abs(x + 0.5) < 1.5)
        for z in range(9, top):
            back = 1 if z >= 16 else 0
            m.set(x, 4 + back, z, "wood", color=C.grain((x, 4, z), arm, 61, 0.05, 2))
            if -4 <= x < 4 and 10 <= z < top - 1:
                m.set(x, 3 + back, z, "fabric", color=C.grain((x, 3, z), vinyl, 62, 0.03, 2))
                if z < 16:
                    m.set(x, 2, z, "fabric", color=C.grain((x, 2, z), vinyl, 62, 0.03, 2))
    # Coutures horizontales du dossier.
    for z in (13, 17):
        yy = 2 if z < 16 else 4
        C.paint(m, [((x, yy, z), "-y") for x in range(-4, 4)], vx.tone(vinyl, 0.7))
    # Assise (relevée à plat) sur son cadre.
    C.fill(m, -4, 4, -5, 2, 8, 10, "fabric", vinyl, seed=63, amp=0.03, levels=2)
    C.fill(m, -4, 4, -4, 2, 7, 8, "metal", iron, seed=64, amp=0.03, levels=2)
    # Flancs de fonte (pied large, montant, haut évasé) et accoudoirs.
    for x in (-5, 4):
        for y in range(-5, 4):
            m.set(x, y, 0, "metal", color=iron)
        for z in range(1, 12):
            ys = range(-2, 2) if z < 4 else range(-3, 3)
            for y in ys:
                m.set(x, y, z, "metal", color=C.grain((x, y, z), iron, 65, 0.05, 2))
        for y in range(-5, 4):
            if broken and x == -5 and y < 0:
                continue
            m.set(x, y, 12, "wood", color=C.grain((x, y, 12), arm, 66, 0.06, 2))
        # Bouton de fonte décoratif (peint) sur le flanc.
        C.paint(m, [((x, 0, 8), "-x" if x < 0 else "+x"), ((x, -1, 8), "-x" if x < 0 else "+x")], C.col("steel", 0.75))
    # Plaque numérotée (laiton) en haut du dos.
    C.paint(m, [((x, 5, 19), "+y") for x in (-1, 0)], C.col("brass"))
    if broken:
        # Bout d'accoudoir arraché qui pend, écharde claire.
        for y, z in ((-1, 11), (-2, 10), (-3, 9)):
            m.set(-6, y, z, "wood", color=C.grain((-6, y, z), arm, 67, 0.06, 2))
        m.set(-5, -1, 12, "wood", color=C.col("wood", 1.15))
        # Skaï du dossier déchiré : mousse apparente, trous.
        for x, z in ((-3, 12), (-2, 12), (-2, 13), (-1, 13), (1, 15), (2, 15), (2, 14), (0, 11)):
            if (x, 2, z) in m.vox:
                m.vox.pop((x, 2, z))
                m.set(x, 3, z, "fabric", color=C.grain((x, 3, z), C.col("foam"), 68, 0.08, 2))
        for x, z in ((1, 18), (-2, 17), (-1, 17)):
            m.set(x, 4, z, "fabric", color=C.col("foam", 0.9))


def fauteuils_siege():
    """UN fauteuil de la rangée « fauteuils » (ancien seat) : le catalogue le
    répète (« copies », 4 fauteuils à 0,56 m d'écart) ; 0,5 × 0,55 m, 1,1 m."""
    m = vx.Model(C.CUBE)
    seat(m)
    return m


def fauteuil_casse():
    """Fauteuil arraché renversé sur le dos (ancien seat_broken_b) : le
    fauteuil de seat(), accoudoir gauche cassé et dossier déchiré, basculé
    d'un quart de tour (dossier au sol vers l'arrière), remis d'aplomb ;
    0,5 × 1,15 m, 0,55 m de haut (pavé du catalogue : 0,7 × 1,2 × 0,63)."""
    up = vx.Model(C.CUBE)
    seat(up, broken=True)
    m = turned_back(up, 5)
    # Demi-tour (lacet) : le haut du dossier déchiré vers l'avant (-Y).
    out = vx.Model(C.CUBE)
    dmap = {"+x": "-x", "-x": "+x", "+y": "-y", "-y": "+y", "+z": "+z", "-z": "-z"}
    for (x, y, z), v in m.vox.items():
        out.vox[(-x - 1, -y - 1, z)] = v
    for (x, y, z, d), col in m.face_color.items():
        out.face_color[(-x - 1, -y - 1, z, dmap[d])] = col
    lo, hi = out.bounds()
    return shifted(out, 0, -int(lo[1] + hi[1]) // 2, -int(lo[2]))


# ------------------------------------------------------------------ pupitre

def pupitre():
    """Pupitre de conférence de l'institut (ancien lectern, 0,7 × 0,6 m,
    1,2 m) : socle, fût évasé en escalier, tablette inclinée en marches
    (haute côté salle, -Y), rebord côté orateur, bannière sarcelle à croix
    blanche sur sa tringle de laiton, micro."""
    m = vx.Model(C.CUBE)
    dark, wood = C.col("wood_dark"), C.col("wood_dark", 1.3)
    C.fill(m, -7, 7, -6, 6, 0, 2, "wood", dark, seed=71, amp=0.05, levels=2)
    C.fill(m, -5, 5, -4, 4, 2, 11, "wood", wood, seed=72, amp=0.05, levels=2)
    C.fill(m, -4, 4, -4, 4, 11, 20, "wood", wood, seed=73, amp=0.05, levels=2)
    C.fill(m, -5, 5, -5, 5, 20, 21, "wood", dark, seed=74, amp=0.05, levels=2)
    # Tablette inclinée : de 1,2 m (avant) à 1,1 m (arrière), en marches.
    for y in range(-6, 6):
        top = 24 - (y + 6) // 5
        C.fill(m, -6, 6, y, y + 1, 21, top, "wood", dark, seed=75, amp=0.05, levels=2)
    C.fill(m, -6, 6, 5, 6, 22, 23, "wood", C.col("wood_dark", 0.8), seed=76, amp=0.03, levels=2)
    # Moulures peintes du fût.
    C.paint(m, [((x, -4, z), "-y") for x in range(-5, 5) for z in (2, 10) if (x, -4, z) in m.vox], vx.tone(dark, 0.8))
    # Bannière sur sa tringle : sarcelle, croix blanche, bas en dents.
    for x in range(-5, 5):
        m.set(x, -5, 19, "metal", color=C.col("brass"))
    for x in range(-4, 4):
        bottom = 8 if x % 2 == 0 else 9
        for z in range(bottom, 19):
            m.set(x, -5, z, "fabric", color=C.grain((x, -5, z), C.col("vinyl_teal", 0.9), 77, 0.04, 2))
    cross = [((x, -5, z), "-y") for x in (-1, 0) for z in range(11, 17)]
    cross += [((x, -5, z), "-y") for x in (-3, -2, 1, 2) for z in (14, 15)]
    C.paint(m, cross, C.col("paint_white"))
    C.paint(m, [((x, -5, 18), "-y") for x in range(-4, 4)], C.col("brass", 0.9))
    # Micro sur col (côté orateur).
    for z in (23, 24):
        m.set(3, 1, z, "metal", color=C.col("metal_dark"))
    m.set(3, 0, 25, "metal", color=C.col("metal_dark", 1.2))
    m.set(3, -1, 25, "rubber", color=C.col("rubber", 1.5))
    return m


# ------------------------------------------------------------------ projecteur

def projecteur_film():
    """Projecteur de cinéma (ancien projector, 1,9 m) gardé pour la salle de
    projection de l'institut : socle en octogone et fût à gradins, carter
    gris martelé à ouïes, objectif vers -Y (vitre), lanterne à l'arrière et
    sa cheminée, carter de bobine au-dessus, boutons et câble."""
    m = vx.Model(C.CUBE)
    steel, body, dark = C.col("steel", 0.85), C.col("case_grey", 1.25), C.col("metal_dark")
    # Socle et fût en escalier (anciens cônes).
    for z0, z1, r, col in ((0, 1, 10.3, steel), (1, 5, 8.6, body), (5, 10, 7.6, body),
                           (10, 15, 6.6, body), (15, 18, 5.6, body), (18, 20, 7.2, steel)):
        for x in range(-11, 11):
            for y in range(-11, 11):
                if round_ok(x, y, 0, 0, r):
                    for z in range(z0, z1):
                        m.set(x, y, z, "metal", color=C.grain((x, y, z), col, 81, 0.03, 2))
    # Rivets peints sur le fût.
    for z in (3, 8, 13):
        C.paint(m, front_cells(m, -1, 1, z, z + 1), C.col("steel", 1.1))
    # Plaque d'appui, carter (ouïes sur le dessus).
    C.fill(m, -5, 5, -8, 8, 20, 21, "metal", steel, seed=82, amp=0.04, levels=2)
    C.fill(m, -4, 4, -9, 7, 21, 29, "metal", body, seed=83, amp=0.03, levels=2)
    C.paint(m, [((x, y, 28), "+z") for x in range(-3, 3) for y in range(-8, 6, 2)], dark)
    # Objectif (deux bagues en escalier), vitre sur la face avant.
    for y0, y1, r in ((-11, -9, 2.6), (-13, -11, 1.7)):
        for x in range(-3, 3):
            for z in range(22, 28):
                if round_ok(x, z, 0, 25, r):
                    for y in range(y0, y1):
                        m.set(x, y, z, "metal", color=C.grain((x, y, z), dark if r > 2 else steel, 84, 0.04, 2))
    C.paint(m, [((x, -13, z), "-y") for x in (-1, 0) for z in (24, 25)], C.col("glass", 1.3))
    # Lanterne à l'arrière (cylindre le long de X) et cheminée.
    for x in range(-6, 6):
        r = 5.6 if x in (-6, 5) else 5.0
        for y in range(3, 15):
            for z in range(19, 31):
                if round_ok(y, z, 9, 25, r):
                    col = steel if x in (-6, 5) else dark
                    m.set(x, y, z, "metal", color=C.grain((x, y, z), col, 85, 0.05, 2))
    C.fill(m, -1, 1, 8, 10, 30, 34, "metal", steel, seed=86, amp=0.04, levels=2)
    C.fill(m, -2, 2, 7, 11, 34, 35, "metal", dark, seed=87, amp=0.04, levels=2)
    # Carter de bobine au-dessus (disque le long de X) : flasques peintes en
    # bobine (bord sombre, cinq jours autour du moyeu).
    import math
    holes = [(-2 + 3.4 * math.cos(a), 32 + 3.4 * math.sin(a)) for a in [i * 2 * math.pi / 5 + 0.3 for i in range(5)]]
    for x in range(-3, 3):
        for y in range(-9, 5):
            for z in range(25, 38):
                if round_ok(y, z, -2, 32, 6.2) and (x, y, z) not in m.vox:
                    m.set(x, y, z, "metal", color=C.grain((x, y, z), C.col("steel", 0.8), 88, 0.03, 2))
    for d, x in (("-x", -3), ("+x", 2)):
        cells = []
        for y in range(-9, 5):
            for z in range(25, 38):
                if (x, y, z) not in m.vox:
                    continue
                if not round_ok(y, z, -2, 32, 5.2):
                    cells.append((((x, y, z), d), dark))
                elif round_ok(y, z, -2, 32, 1.2):
                    cells.append((((x, y, z), d), C.col("steel", 1.15)))
                elif any((y + 0.5 - hy) ** 2 + (z + 0.5 - hz) ** 2 <= 1.3 for hy, hz in holes):
                    cells.append((((x, y, z), d), C.col("rubber", 1.6)))
        for cd, colr in cells:
            C.paint(m, [cd], colr)
    # Boutons sur le flanc droit.
    for y, z in ((-6, 26), (-3, 26), (-6, 23)):
        m.set(4, y, z, "metal", color=C.col("steel", 1.15))
    return m


# ------------------------------------------------------------------ chariot

def chariot():
    """Chariot de soins (ancien décor construit par le jeu, 1,25 × 0,7 m) :
    châssis en tube d'acier, deux plateaux émaillés (dessus à 0,85 m =
    « support » du catalogue), rebord sur trois côtés, poignée, roulettes ;
    mallette de soins, plateau d'instruments, draps pliés, carton."""
    m = vx.Model(C.CUBE)
    steel, enamel = C.col("steel", 1.05), C.col("paint_white", 0.9)
    for z in (5, 16):
        C.fill(m, -12, 12, -7, 7, z, z + 1, "metal", enamel, seed=91 + z, amp=0.04, levels=2)
    for x in (-12, 11):
        for y in (-7, 6):
            for z in range(3, 17):
                m.set(x, y, z, "metal", color=steel)
            m.set(x, y, 2, "metal", color=C.col("steel", 0.8))          # chape
            for z in (0, 1):
                for yy in (y, y + (1 if y < 0 else -1)):
                    m.set(x, yy, z, "rubber", color=C.col("rubber", 1.6))
    # Rebord du plateau du haut (pas côté poignée).
    for x in range(-12, 12):
        for y in (-7, 6):
            m.set(x, y, 17, "metal", color=steel)
    for y in range(-7, 7):
        m.set(-12, y, 17, "metal", color=steel)
    # Poignée (+X), gaine de caoutchouc.
    for y in (-6, 5):
        for z in range(16, 20):
            m.set(12, y, z, "metal", color=steel)
    for y in range(-6, 6):
        m.set(12, y, 19, "rubber", color=C.col("rubber", 1.7))
    # Mallette de soins blanche à croix rouge.
    C.fill(m, -10, -1, -5, 3, 17, 20, "fabric", C.col("paint_white"), seed=93, amp=0.03, levels=2)
    cross = [((x, -5, z), "-y") for x in (-6, -5) for z in (17, 18, 19)]
    cross += [((x, -5, 18), "-y") for x in (-7, -4)]
    cross += [((x, y, 19), "+z") for x in (-6, -5) for y in range(-3, 2)]
    cross += [((x, y, 19), "+z") for x in range(-8, -2) for y in (-1, 0)]
    C.paint(m, cross, C.col("medic_red"))
    # Plateau d'instruments (peints) et flacon.
    C.fill(m, 1, 9, -5, 1, 17, 18, "metal", C.col("steel", 1.2), seed=94, amp=0.03, levels=2)
    C.paint(m, [((x, y, 17), "+z") for x, y in ((2, -4), (3, -4), (4, -4), (2, -2), (3, -2), (5, -2), (6, -2), (7, -4))],
            C.col("steel", 0.7))
    m.set(6, 3, 17, "glass", color=C.col("rust", 0.8))
    m.set(6, 3, 18, "fabric", color=C.col("paint_white"))
    # Plateau du bas : draps verts pliés, carton.
    C.fill(m, -10, -2, -5, 5, 6, 9, "fabric", C.col("fabric_green"), seed=95, amp=0.05, levels=2)
    C.paint(m, [((x, -5, 7), "-y") for x in range(-10, -2)], vx.tone(C.col("fabric_green"), 0.7))
    C.fill(m, 1, 9, -4, 4, 6, 11, "fabric", C.col("cardboard"), seed=96, amp=0.05, levels=2)
    return m


# ------------------------------------------------------------------ épave

def epave_voiture():
    """Épave de berline des années 60 (ancien décor construit par le jeu),
    4,3 × 1,75 m, 1,4 m : caisse vert d'eau rongée de rouille, avant affaissé
    d'un cube sur ses pneus crevés, habitacle en escalier (pare-brise et
    lunette en marches, vitres peintes, une fêlée), pare-chocs, phares,
    calandre, feux, plaque, poignées."""
    m = vx.Model(C.CUBE)
    paint_c = C.col("car_paint")
    rust = C.col("rust")

    def body_col(c):
        # Rouille en plaques irrégulières, surtout en bas de caisse.
        patch = vx.noise((c[0] // 3, c[1] // 3, c[2] // 3), 101)
        if patch < (0.3 if c[2] < 9 else 0.09) and vx.noise(c, 108) < 0.8:
            return C.grain(c, rust, 102, 0.1, 2)
        return C.grain(c, paint_c, 103, 0.04, 2)

    def sag(x):
        return 1 if x >= 17 else 0           # avant affaissé d'un cube

    # Caisse (plan aux coins arrondis en escalier), passages de roues.
    for x in range(-42, 42):
        cut = 2 if x in (-42, 41) else (1 if x in (-41, 40) else 0)
        for y in range(-17 + cut, 17 - cut):
            for z in range(5 - sag(x), 17 - sag(x)):
                m.set(x, y, z, "metal", color=body_col((x, y, z)))
    for wx in (-27, 27):
        wz = 6 - sag(wx)
        for x in range(wx - 8, wx + 8):
            for z in range(0, 14):
                if round_ok(x, z, wx, wz, 7.4):
                    for y in list(range(-17, -12)) + list(range(12, 17)):
                        m.vox.pop((x, y, z), None)
    # Bas de caisse sombre et passages de roues noircis (peints).
    for c, d in [(c, d) for c, d in m.exposed() if d == "-z"]:
        m.face_color[(c[0], c[1], c[2], d)] = C.col("metal_dark", 0.7)
    # Pneus (disques le long de Y), jantes ; pneus avant crevés (aplatis au sol).
    for wx in (-27, 27):
        wz = 6 - sag(wx)
        for x in range(wx - 6, wx + 6):
            for z in range(0, 13):
                if round_ok(x, z, wx, wz, 6.2):
                    for y in list(range(-16, -13)) + list(range(13, 16)):
                        m.set(x, y, z, "rubber", color=C.grain((x, y, z), C.col("rubber", 1.5), 104, 0.08, 2))
        for x in range(wx - 2, wx + 2):
            for z in range(wz - 2, wz + 2):
                rim = C.col("steel", 0.75) if (x + z) % 3 else C.grain((x, 0, z), rust, 105, 0.1, 2)
                C.paint(m, [((x, -16, z), "-y"), ((x, 15, z), "+y")], rim)
    # Habitacle en escalier : pare-brise (avant, +X), lunette (arrière).
    glass = C.col("glass")
    for z in range(17, 28):
        k = z - 17
        xf = 16 - (k * 8) // 10
        xb = -27 + (k * 6) // 10
        hw = 15 if z < 24 else 14
        for x in range(xb, xf):
            for y in range(-hw, hw):
                m.set(x, y, z, "metal", color=body_col((x, y, z)))
    # Vitres : pare-brise et lunette (faces ±X et dessus des marches), vitres latérales.
    win = []
    for (x, y, z) in list(m.vox):
        if 18 <= z <= 26 and abs(y + 0.5) < 13:
            if (x + 1, y, z) not in m.vox and x >= 8:
                win += [((x, y, z), "+x")]
                if (x, y, z + 1) not in m.vox:
                    win += [((x, y, z), "+z")]
            if (x - 1, y, z) not in m.vox and x <= -20:
                win += [((x, y, z), "-x")]
                if (x, y, z + 1) not in m.vox:
                    win += [((x, y, z), "+z")]
    for z in range(19, 26):
        k = z - 17
        xf = 16 - (k * 8) // 10
        xb = -27 + (k * 6) // 10
        for x in range(xb + 2, xf - 2):
            if x in (-6, -5):
                continue                      # montant central
            for ys, d in (((-15, -14), "-y"), ((14, 13), "+y")):
                y = next((y for y in ys if (x, y, z) in m.vox), None)
                if y is not None:
                    win.append(((x, y, z), d))
    for c, d in win:
        m.face_color[(c[0], c[1], c[2], d)] = vx.tone(glass, 0.9 + 0.2 * vx.noise(c, 106))
    # Vitre fêlée (côté gauche) : éclats clairs.
    C.paint(m, [((x, -15, z), "-y") for x, z in ((-2, 22), (-1, 23), (0, 22), (-1, 21), (1, 24), (-3, 21))],
            C.col("glass", 2.2))
    # Pare-chocs, calandre, phares (un cassé), feux, plaque.
    for x0 in (42, -43):
        for y in range(-16, 16):
            for z in (7 - sag(x0), 8 - sag(x0)):
                m.set(x0, y, z, "metal", color=C.grain((x0, y, z), C.col("steel", 0.9), 107, 0.1, 2))
    C.paint(m, [((41, y, z), "+x") for y in range(-7, 7) for z in range(9, 13) if (41, y, z) in m.vox],
            C.col("metal_dark"))
    C.paint(m, [((41, y, z), "+x") for y in range(-7, 7) for z in (10, 12) if (41, y, z) in m.vox], C.col("steel"))
    C.paint(m, [((41, y, z), "+x") for y in (-13, -12, -11) for z in (11, 12, 13)], C.col("paint_white", 0.95))
    C.paint(m, [((41, y, z), "+x") for y in (10, 11, 12) for z in (11, 12, 13)], C.col("rubber", 1.5))
    C.paint(m, [((-42, y, z), "-x") for y in (-13, -12, 11, 12) for z in (12, 13, 14)], C.col("medic_red", 0.9))
    C.paint(m, [((-42, y, z), "-x") for y in range(-3, 3) for z in (10, 11)], C.col("paint_white", 0.9))
    # Baguette chromée, joints de portières et poignées (flancs).
    for y, d in ((-17, "-y"), (16, "+y")):
        C.paint(m, [((x, y, 12 - sag(x)), d) for x in range(-41, 41) if (x, y, 12 - sag(x)) in m.vox],
                C.col("steel", 0.95))
        C.paint(m, [((x, y, z), d) for x in (-6, 13) for z in range(6, 17) if (x, y, z) in m.vox], C.col("metal_dark"))
        C.paint(m, [((x, y, 15), d) for x in (-9, -8, 9, 10) if (x, y, 15) in m.vox], C.col("steel", 1.1))
    return m


BUILDERS = {
    "caisses": caisses,
    "sacs_sable": sacs_sable,
    # Lot 2 : mobilier et stockage.
    "tonneaux": tonneaux,
    "table_renversee": table_renversee,
    "chaise_renversee": chaise_renversee,
    "chaise": chaise,
    "bureau": bureau,
    "etagere": etagere,
    "fauteuils_siege": fauteuils_siege,
    "fauteuil_casse": fauteuil_casse,
    "pupitre": pupitre,
    "projecteur_film": projecteur_film,
    "chariot": chariot,
    "epave_voiture": epave_voiture,
}
# Anciens modèles .glb (planches avant / après, --before).
BEFORE = {
    "caisses": "stage_crates",
    "tonneaux": "blue_barrel_group",
    "chaise": "folding_chair",
    "bureau": "desk",
    "etagere": "reel_shelf",
    "fauteuils_siege": "seat",
    "fauteuil_casse": "seat_broken_b",
    "pupitre": "lectern",
    "projecteur_film": "projector",
}

if __name__ == "__main__":
    C.main(BUILDERS, BEFORE)
