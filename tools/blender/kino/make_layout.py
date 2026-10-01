# Génère assets/maps/kino/layout.json (KINO V2 : Kino der Toten à l'échelle 1).
#
#   sh tools/blender.sh tools/blender/kino/make_layout.py assets/maps/kino/layout.json
#
# Python pur (lancé par le Python de Blender, sans fenêtre). Les salles, portes,
# fenêtres et objets sont décrits ici en UNITÉS CoD (1 u = 1 pouce = 2,54 cm ;
# x = Est, y = Nord = vers la scène, z = haut), d'après les relevés de
# docs/reference/kino/layout_research.md (privé). Le script :
#   - rastérise chaque salle en cases de CELL unités ;
#   - pose un MUR entre une salle et le vide, ou entre deux salles non reliées ;
#     entre deux salles reliées (OPEN) : garde-corps au-dessus d'un vide
#     (balcon, mezzanine), contremarche pour un petit dénivelé (bord de scène) ;
#   - perce portes et fenêtres, crée la poche extérieure de chaque fenêtre ;
#   - plaque les objets muraux contre le mur le plus proche ;
#   - convertit tout en mètres, repère Godot : (x, y, z) CoD -> (x*K + OX, z*K, -y*K + OZ).
# Formes des murs : [PROBABLE] (les relevés donnent des volumes englobants) ;
# positions des objets : [SÛR].
import json, math, sys

K = 0.0254
OX, OZ = 75.0, 72.0   # décalage : x, z >= 0 (NetCodec)
CELL = 10             # u
WALL_T = 16           # épaisseur des murs (u)
DROP = 60             # au-delà : vide sous un balcon (garde-corps) ; en deçà : contremarche
OUT = sys.argv[sys.argv.index("--") + 1]


def G(x, y, z):
    return [round(x * K + OX, 3), round(z * K, 3), round(-y * K + OZ, 3)]


def GXZ(x, y):
    return [round(x * K + OX, 3), round(-y * K + OZ, 3)]


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# ---------------------------------------------------------------- salles
# id, zone, contour (CoD), sol (z ou pente [(x,y,z) x3]), plafond,
# mats (sol, murs, plafond), slab = sol en dalle (quelque chose dessous ou vide),
# box = plafond en dalle (salle posée dans le volume d'une autre), sky = pas de plafond.
ROOMS = [
    # Hall d'entrée (départ) : rdc, bande nord sous le balcon, balcon.
    dict(id="hall", zone="a", poly=rect(-400, -1500, 550, -770), floor=80, ceil=500,
         mats=("marble", "wall_lobby", "ceiling_theater")),
    dict(id="hall_nord", zone="a", poly=rect(-580, -770, 210, -510), floor=80, ceil=254,
         mats=("marble", "wall_lobby", "ceiling_theater"), no_ceiling=True),
    dict(id="balcon", zone="a", poly=rect(-580, -820, 400, -510), floor=266, ceil=500, slab=True,
         mats=("carpet_red", "wall_lobby", "ceiling_theater")),
    dict(id="balcon_marches", zone="a", poly=rect(400, -820, 480, -510), floor=266, ceil=500, slab=True,
         mats=("carpet_red", "wall_lobby", "ceiling_theater")),
    dict(id="balcon_est", zone="a", poly=rect(480, -820, 580, -510), floor=320, ceil=500, slab=True,
         mats=("carpet_red", "wall_lobby", "ceiling_theater")),
    # Couloir hall -> théâtre (sous la salle de projection), en pente.
    dict(id="couloir", zone="t", poly=rect(-80, -510, 80, -190),
         slope=[(-80, -510, 80), (80, -510, 80), (-80, -190, 0)], ceil=300,
         mats=("carpet_red", "wall_theater", "ceiling_theater")),
    # Salle basse (fosse à feu).
    dict(id="salle_basse", zone="b",
         poly=[(-1350, -960), (-1130, -960), (-1130, -1190), (-790, -1190), (-790, -960), (-580, -960),
               (-580, -320), (-1350, -320)], floor=80, ceil=300,
         mats=("concrete_dark", "brick", "ceiling")),
    # Ruelle (dehors) et niche de l'AK74u.
    dict(id="ruelle", zone="c", poly=rect(-1760, -590, -1350, 810), floor=0, ceil=520, sky=True,
         mats=("cobble", "brick", "ceiling")),
    dict(id="ruelle_niche", zone="c", poly=rect(-1350, 200, -1130, 400), floor=0, ceil=300,
         mats=("cobble", "brick", "ceiling")),
    # Zone grillagée (bas), escalier ouest, arrière-salle (haut, au-dessus du grillage).
    dict(id="grillage", zone="d", poly=rect(-1650, 810, -1330, 1160), floor=0, ceil=163, no_ceiling=True,
         mats=("concrete", "brick", "ceiling")),
    dict(id="arriere_escalier", zone="d", poly=rect(-1760, 930, -1650, 1250), floor=0, ceil=420,
         mats=("concrete", "brick", "ceiling")),
    dict(id="arriere_palier", zone="d", poly=rect(-1760, 810, -1650, 930), floor=0, ceil=163, no_ceiling=True,
         mats=("concrete", "brick", "ceiling")),
    dict(id="arriere_salle", zone="d",
         poly=[(-1760, 810), (-1090, 810), (-1090, 1640), (-1760, 1640), (-1760, 1250), (-1650, 1250),
               (-1650, 930), (-1760, 930)], floor=175, ceil=420, slab=True,
         mats=("wood", "wall", "ceiling")),
    # Escalier de l'arrière-salle vers les coulisses (portes liées).
    dict(id="cage_coulisses", zone="h", poly=rect(-1090, 1390, -840, 1470), floor=0, ceil=420,
         mats=("wood", "wall", "ceiling")),
    # Salle haute : partie ouest + galerie sur la salle de théâtre, partie est (portraits).
    dict(id="salle_haute", zone="e",
         poly=[(580, -1100), (960, -1100), (960, -320), (810, -320), (810, -240), (440, -240),
               (440, -510), (580, -510)], floor=320, ceil=480, slab=True, box=True,
         mats=("carpet_red", "wall_foyer", "ceiling_theater")),
    dict(id="salle_portraits", zone="e", poly=rect(960, -1100, 1680, -320), floor=320, ceil=520, slab=True,
         mats=("carpet_red", "wall_foyer", "ceiling_theater")),
    dict(id="escalier_foyer", zone="e", poly=rect(1350, -320, 1470, -30), floor=160, ceil=480,
         mats=("wood", "wall_foyer", "ceiling_theater")),
    # Foyer : mezzanine en L et rez-de-chaussée (bout nord-est arrondi).
    dict(id="foyer_mezz", zone="f",
         poly=[(780, -30), (1750, -30), (1750, 100), (990, 100), (990, 430), (780, 430)],
         floor=165, ceil=460, slab=True, mats=("parquet", "wall_foyer", "ceiling_theater")),
    dict(id="foyer", zone="f",
         poly=[(990, 100), (1890, 100), (1890, 690), (1860, 770), (1800, 840), (1720, 890), (1640, 905),
               (990, 905)], floor=0, ceil=460, mats=("parquet", "wall_foyer", "ceiling_theater")),
    # Loges : partie sud-ouest, passage piégé vers les coulisses, salle principale.
    dict(id="loges_so", zone="g", poly=rect(800, 905, 1045, 1440), floor=0, ceil=200,
         mats=("wood", "wall_loges", "ceiling")),
    dict(id="loges_passage", zone="g", poly=rect(750, 1440, 1045, 1620), floor=0, ceil=200,
         mats=("wood", "wall_loges", "ceiling")),
    dict(id="loges", zone="g", poly=rect(1045, 905, 1540, 1665), floor=0, ceil=200,
         mats=("wood", "wall_loges", "ceiling")),
    # Salle de théâtre (parterre en pente, bloc du couloir au sud), avant-scène.
    dict(id="parterre", zone="t",
         poly=[(-770, -510), (-190, -510), (-190, -190), (190, -190), (190, -510), (770, -510),
               (770, 920), (-770, 920)],
         slope=[(-770, -190, 0), (770, -190, 0), (-770, 900, -45)], ceil=900,
         mats=("carpet_theater", "plaster_theater", "vault_theater")),
    dict(id="avant_scene", zone="t", poly=rect(-770, 920, 770, 1220), floor=0, ceil=900,
         mats=("stage_wood", "plaster_theater", "vault_theater")),
    # Scène / coulisses et aile ouest.
    dict(id="coulisses", zone="h", poly=rect(-520, 1220, 750, 1910), floor=0, ceil=580,
         mats=("stage_wood", "wall", "ceiling")),
    dict(id="aile_ouest", zone="h", poly=rect(-840, 1220, -520, 1650), floor=0, ceil=580,
         mats=("stage_wood", "wall", "ceiling")),
    # Salle de projection (Pack-a-Punch), au-dessus du couloir, dans la salle.
    dict(id="projection", zone="p", poly=rect(-180, -510, 180, -90), floor=320, ceil=460,
         slab=True, box=True, mats=("dark_wood", "plaster_theater", "vault_theater")),
]
ROOM = {r["id"]: r for r in ROOMS}

OPEN = [("hall", "hall_nord"), ("hall", "balcon"), ("hall", "balcon_marches"), ("hall", "balcon_est"),
        ("balcon", "balcon_marches"), ("balcon_marches", "balcon_est"),
        ("ruelle", "ruelle_niche"), ("grillage", "arriere_escalier"), ("grillage", "arriere_palier"),
        ("arriere_palier", "arriere_escalier"),
        ("arriere_escalier", "arriere_salle"),
        ("salle_haute", "parterre"), ("foyer", "foyer_mezz"),
        ("loges_so", "loges_passage"), ("loges_passage", "loges"),
        ("parterre", "avant_scene"), ("coulisses", "aile_ouest")]
OPEN = {frozenset(p) for p in OPEN}

# Escaliers : a = bas (milieu), b = haut (milieu), w = largeur (u).
STAIRS = [
    dict(room="hall", a=(-330, -1200, 80), b=(-330, -820, 266), w=90, mat="carpet_red"),
    dict(room="hall", a=(260, -1200, 80), b=(260, -820, 266), w=100, mat="carpet_red"),
    dict(room="balcon_marches", a=(402, -660, 266), b=(478, -660, 320), w=110, mat="carpet_red"),
    dict(room="ruelle", a=(-1470, -384, 0), b=(-1360, -384, 80), w=80, mat="concrete"),
    dict(room="arriere_escalier", a=(-1705, 935, 0), b=(-1705, 1248, 175), w=100, mat="wood"),
    dict(room="cage_coulisses", a=(-850, 1430, 0), b=(-1088, 1430, 168), w=75, mat="wood"),
    dict(room="escalier_foyer", a=(1410, -35, 160), b=(1410, -315, 320), w=110, mat="wood"),
    dict(room="foyer", a=(1260, 380, 0), b=(995, 380, 165), w=100, mat="wood"),
    dict(room="foyer", a=(1650, 370, 0), b=(1650, 105, 165), w=100, mat="wood"),
    # Larges escaliers de scène (BO1) : à gauche devant la tour du téléporteur, à droite
    # près de l'estrade de la tourelle.
    dict(room="parterre", a=(-330, 840, -42), b=(-330, 918, 0), w=200, mat="stage_wood"),
    dict(room="parterre", a=(400, 840, -42), b=(400, 918, 0), w=200, mat="stage_wood"),
]

# Portes (milieu de l'ouverture, au sol) : id, x, y, z, largeur w, hauteur h (u),
# prix, zones ; power = ouverte à l'allumage du courant (non achetable) ;
# link = porte liée (un seul achat ouvre les deux).
DOORS = [
    dict(id="1", x=-580, y=-640, z=80, w=125, h=100, cost=750, zones=["a", "b"]),
    dict(id="2", x=580, y=-660, z=320, w=110, h=100, cost=750, zones=["a", "e"]),
    dict(id="3", x=-1350, y=-384, z=80, w=60, h=96, cost=1000, zones=["b", "c"]),
    dict(id="4", x=-1550, y=810, z=0, w=100, h=100, cost=1250, zones=["c", "d"]),
    dict(id="5", x=-1090, y=1430, z=175, w=60, h=96, cost=1250, zones=["d", "h"], link="5b"),
    dict(id="5b", x=-840, y=1430, z=0, w=60, h=96, cost=1250, zones=["d", "h"], link="5"),
    dict(id="6", x=1410, y=-320, z=320, w=120, h=100, cost=1000, zones=["e", "f"], link="6b"),
    dict(id="6b", x=1410, y=-30, z=165, w=120, h=100, cost=1000, zones=["e", "f"], link="6"),
    dict(id="7", x=1444, y=905, z=0, w=108, h=100, cost=1250, zones=["f", "g"]),
    dict(id="8", x=750, y=1540, z=0, w=150, h=110, cost=1250, zones=["g", "h"]),
    dict(id="courant_hall", x=0, y=-510, z=80, w=120, h=110, power=True, zones=["a", "t"]),
    dict(id="courant_salle", x=0, y=-190, z=0, w=120, h=110, power=True, zones=["a", "t"]),
    dict(id="rideau", x=0, y=1220, z=0, w=674, h=325, power=True, zones=["t", "h"], curtain=True),
]

# Fenêtres (point du mur, au sol de la salle) : x, y, z.
WINDOWS = [
    (-400, -1400, 80), (160, -1500, 80), (210, -700, 80), (-580, -640, 266),       # hall
    (-672, -960, 80), (-962, -320, 80),                                             # salle basse
    (-1657, -590, 0), (-1760, 546, 0),                                              # ruelle
    (-1090, 1121, 175), (-1760, 880, 175), (-1446, 1160, 0),                        # arrière-salle
    (657, -1100, 320), (1680, -644, 320),                                           # salle haute
    (854, 430, 165), (1890, 577, 0), (1404, 100, 0),                                # Foyer
    (978, 905, 0), (1540, 1297, 0),                                                 # loges
    (418, 1910, 0), (-772, 1650, 0),                                                # coulisses
    (-770, 830, -40), (770, 833, -40),                                              # salle de théâtre
]

# Objets muraux : position relevée (plaquée ensuite contre le mur le plus proche).
WALL_BUYS = [
    ("V", "olympia", -390, -1265, 80), ("R", "m14", 301, -510, 266), ("B", "mpl", -842, -325, 80),
    ("K", "ak74u", -1128, 303, 0), ("<", "pm63", 810, -321, 320), ("M", "mp40", 1887, 423, 0),
    (">", "stakeout", 782, 83, 165), ("U", "mp5k", 1040, 1104, 0), ("/", "m16", -630, 1225, 0),
    ("%", "bowie", -194, -361, 5),
]
GRENADES = [("proj", -182, -211, 320)]
PERKS = [("Q", "lazarus", 527, -1261, 80), ("J", "titan", -328, -492, 5), ("S", "rapid", 1268, 141, 0),
         ("D", "twin", -1732, -378, 0)]
# Neuf emplacements de la boîte, ordre du jeu (index 1 = balcon du hall, exclu du départ).
BOXES = [(901, -620, 320), (-1, -775, 266, "S"), (-1288, -635, 80), (-1500, 226, 0, "E"),
         (-1385, 1016, 175, "S"), (1, 1842, 0), (1343, 1313, 0, "E"), (1657, 714, 0, "N"), (49, 136, -10, "N")]
# Tableaux à la craie indiquant la boîte (positions [ESTIMÉ] : balcon du hall
# d'après les captures, puis une par grande salle).
BOX_BOARDS = [(-150, -510, 266), (150, 912, -45, "S"), (1200, 905, 0), (-1350, 0, 0), (-300, 1910, 0)]
POWER = (-488, 1246, 0)
PAP = (6, -487, 320)
TRAPS = [
    dict(id="trap", area=(-80, -390, 20, 80, -310, 250), lever=(96, -530, 80), lever2=(-92, -175, 0)),
    dict(id="trap_2", area=(900, -825, 320, 1030, -712, 440), lever=(951, -877, 320), lever2=(1091, -713, 320)),
    dict(id="trap_3", area=(-1636, 1224, 175, -1316, 1355, 300), lever=(-1626, 1241, 175), lever2=(-1691, 1627, 175)),
    dict(id="trap_4", area=(987, 1439, 0, 1044, 1618, 130), lever=(1299, 1524, 0), lever2=(933, 1646, 0)),
    dict(id="trap_5", area=(-1014, -720, 70, -833, -556, 200), lever=(-825, -943, 80, "S"), lever2=(-1087, -334, 80), fire=True),
]
# Sur le disque du poste central (dessus à ~0,3 m du sol du hall), face à la scène.
PLAYER_SPAWNS = [(-45, -1245, 94), (-40, -1300, 94), (40, -1300, 94), (45, -1245, 94)]
RISERS = [(-606, -239, 0), (-574, -447, 0), (390, -395, 0), (670, -339, 0), (-581, 197, 0),
          (-605, 532, 0), (444, 425, 0)]
TELEPORTER = dict(pad=(-306, 1116, 0), exit=(0, -436, 322), mainframe=(2, -1266, 80))


# ---------------------------------------------------------------- géométrie
def inside(poly, x, y):
    c = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def floor_at(r, x, y):
    if "slope" in r:
        (x1, y1, z1), (x2, y2, z2), (x3, y3, z3) = r["slope"]
        det = (x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3)
        a = ((z1 - z3) * (y2 - y3) - (z2 - z3) * (y1 - y3)) / det
        b = ((x1 - x3) * (z2 - z3) - (x2 - x3) * (z1 - z3)) / det
        return a * (x - x3) + b * (y - y3) + z3
    return r["floor"]


def span(r, x, y):
    """Intervalle vertical occupé par la salle en (x, y) : du dessous du sol au plafond."""
    f = floor_at(r, x, y)
    return (f - (12 if r.get("slab") else 10), r["ceil"])


cells = {}   # (i, j) -> [salles]
for r in ROOMS:
    xs = [p[0] for p in r["poly"]]
    ys = [p[1] for p in r["poly"]]
    r["cells"] = set()
    for i in range(int(min(xs)) // CELL, int(max(xs)) // CELL + 1):
        for j in range(int(min(ys)) // CELL, int(max(ys)) // CELL + 1):
            if inside(r["poly"], (i + 0.5) * CELL, (j + 0.5) * CELL):
                r["cells"].add((i, j))
                cells.setdefault((i, j), []).append(r["id"])


def overlaps(a, b):
    return min(a[1], b[1]) - max(a[0], b[0]) > 1


def subtract(iv, cuts):
    out = [iv]
    for c in cuts:
        nxt = []
        for s in out:
            if c[1] <= s[0] or c[0] >= s[1]:
                nxt.append(s)
                continue
            if c[0] > s[0]:
                nxt.append((s[0], c[0]))
            if c[1] < s[1]:
                nxt.append((c[1], s[1]))
        out = nxt
    return [s for s in out if s[1] - s[0] > 2]


walls = {}   # (orientation, ligne, y0, y1, mat, salle) -> [(début, fin)]
rails = {}   # (orientation, ligne, z, salle) -> [(début, fin)]
# Façades sous le bord d'un balcon (ôtées à l'arrivée des escaliers, comme les garde-corps).
facades = {}
DIRS = [((1, 0), "v", 1), ((-1, 0), "v", 0), ((0, 1), "h", 1), ((0, -1), "h", 0)]


def add_edge(store, key, s0, s1):
    store.setdefault(key, []).append((s0, s1))


for r in ROOMS:
    for (i, j) in r["cells"]:
        cx, cy = (i + 0.5) * CELL, (j + 0.5) * CELL
        my = span(r, cx, cy)
        # Salle close (box) nichée dans celle-ci (cabine de projection dans la salle de
        # théâtre) : son volume n'appartient pas à la grande salle, qui n'y pose pas de mur.
        inner = []
        for q in cells.get((i, j), []):
            qs = span(ROOM[q], cx, cy)
            if ROOM[q].get("box") and q != r["id"] and qs[0] > my[0] and qs[1] < my[1]:
                inner.append(qs)
        for my in subtract(my, inner):
            for (di, dj), ori, side in DIRS:
                n = (i + di, j + dj)
                if n in r["cells"]:
                    continue
                # Arête de la case (segment sur la grille).
                if ori == "v":
                    line = (i + side) * CELL
                    s0, s1 = j * CELL, (j + 1) * CELL
                else:
                    line = (j + side) * CELL
                    s0, s1 = i * CELL, (i + 1) * CELL
                nx, ny = (n[0] + 0.5) * CELL, (n[1] + 0.5) * CELL
                covered = []
                for oid in cells.get(n, []):
                    o = ROOM[oid]
                    osp = span(o, nx, ny)
                    if not overlaps(my, osp):
                        continue
                    lo, hi = max(my[0], osp[0]), min(my[1], osp[1])
                    covered.append((lo, hi))
                    if frozenset((r["id"], oid)) in OPEN:
                        fr, fo = floor_at(r, cx, cy), floor_at(o, nx, ny)
                        if fr - fo > DROP:
                            # Balcon : garde-corps ; façade pleine seulement si rien dessous.
                            add_edge(rails, (ori, line, round(fr), r["id"]), s0, s1)
                            # Une salle plus basse sous cette case (hall sous le balcon...) : vide dessous.
                            below = [q for q in cells.get((i, j), []) if q != r["id"] and floor_at(ROOM[q], cx, cy) < fr - 10]
                            if not below and not r.get("box"):
                                add_edge(facades, (ori, line, round(fo - 10), round(fr), r["mats"][1], r["id"]), s0, s1)
                        elif fr - fo > 3:
                            add_edge(walls, (ori, line, round(fo - 5), round(fr), r["mats"][1], r["id"]), s0, s1)
                    elif r["id"] < oid or (r.get("box") and oid in cells.get((i, j), [])):
                        # (une salle close nichée dans une autre pose elle-même ses murs)
                        add_edge(walls, (ori, line, round(lo), round(hi), r["mats"][1], r["id"]), s0, s1)
                for lo, hi in subtract(my, covered):
                    add_edge(walls, (ori, line, round(lo), round(hi), r["mats"][1], r["id"]), s0, s1)


def merge(runs):
    runs = sorted(runs)
    out = []
    for a, b in runs:
        if out and a <= out[-1][1] + 0.01:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


def stair_cuts(ori, line, z, pieces):
    """Retire des morceaux d'arête l'arrivée d'un escalier (en haut, au même niveau)."""
    for st in STAIRS:
        ax, ay, _az = st["a"]
        bx, by, bz = st["b"]
        if abs(bz - z) > 20:
            continue
        # Seul le bord que l'escalier traverse (perpendiculaire à sa montée).
        along_y = abs(by - ay) > abs(bx - ax)
        if (ori == "h") != along_y:
            continue
        along = by if ori == "v" else bx
        across = bx if ori == "v" else by
        if abs(across - line) < 60:
            cut = (along - st["w"] / 2 - 5, along + st["w"] / 2 + 5)
            pieces = [q for p in pieces for q in subtract(p, [cut])]
    return pieces


for (ori, line, y0, y1, mat, room), runs in facades.items():
    for s0, s1 in merge(runs):
        for p0, p1 in stair_cuts(ori, line, y1, [(s0, s1)]):
            for s in range(int(p0), int(p1), CELL):
                add_edge(walls, (ori, line, y0, y1, mat, room), s, min(s + CELL, p1))


# ---------------------------------------------------------------- ouvertures
OPENINGS = []  # (x, y, z0, z1, largeur)
for d in DOORS:
    OPENINGS.append((d["x"], d["y"], d["z"] - 20, d["z"] + d["h"], d["w"]))
SILL, LINTEL = 0.95 / K, 2.35 / K
for (x, y, z) in WINDOWS:
    OPENINGS.append((x, y, z + SILL, z + LINTEL, 42))
# Passage piégé entre la salle haute et la salle des portraits (piège n° 2).
OPENINGS.append((960, -768, 310, 440, 113))
# Baie de la cabine vers la salle : fente sur 85 % de la largeur du mur (360 u),
# 1 m de haut centrée sur les yeux du joueur debout (sol 320 u + 1,62 m) : on voit
# la scène et on tire dans la salle ; pavé barrière : on ne saute pas.
BAIE_W = 0.85 * 360
BAIE_Z = (320 + 1.62 / K - 0.5 / K, 320 + 1.62 / K + 0.5 / K)
OPENINGS.append((0, -90, BAIE_Z[0], BAIE_Z[1], BAIE_W))

wall_list = []
for (ori, line, y0, y1, mat, room), runs in walls.items():
    for s0, s1 in merge(runs):
        if ori == "v":
            a, b = (line, s0), (line, s1)
        else:
            a, b = (s0, line), (s1, line)
        ops = []
        for (ox, oy, oz0, oz1, ow) in OPENINGS:
            along = oy if ori == "v" else ox
            across = ox if ori == "v" else oy
            if abs(across - line) <= WALL_T and s0 - ow / 2 < along < s1 + ow / 2 and oz0 < y1 and oz1 > y0:
                t = (along - s0) * K
                ops.append({"seg": 0, "t": round(t, 3), "w": round(ow * K, 3),
                            "y0": round(max(oz0, y0) * K, 3), "y1": round(min(oz1, y1) * K, 3)})
        wall_list.append({"room": room, "path": [GXZ(*a), GXZ(*b)], "y0": round(y0 * K, 3),
                          "y1": round(y1 * K, 3), "thick": round(WALL_T * K, 3), "mat": mat, "openings": ops})
        wall_list[-1]["_ori"], wall_list[-1]["_line"], wall_list[-1]["_s"] = ori, line, (s0, s1)

# Garde-corps, interrompus en haut des escaliers.
rail_list = []
for (ori, line, z, room), runs in rails.items():
    for s0, s1 in merge(runs):
        for p0, p1 in stair_cuts(ori, line, z, [(s0, s1)]):
            a = (line, p0) if ori == "v" else (p0, line)
            b = (line, p1) if ori == "v" else (p1, line)
            rail_list.append({"room": room, "path": [GXZ(*a), GXZ(*b)], "y": round(z * K, 3), "h": 1.0,
                              "mat": "dark_wood"})


# ---------------------------------------------------------------- poches des fenêtres
def room_at(x, y, z):
    best = None
    for r in ROOMS:
        if inside(r["poly"], x, y):
            f = floor_at(r, x, y)
            if f - 40 <= z <= r["ceil"] and (best is None or abs(f - z) < abs(floor_at(best, x, y) - z)):
                best = r
    return best


windows = []
pockets = []
for k, (x, y, z) in enumerate(WINDOWS):
    # Côté intérieur : la direction où l'on trouve la salle à 40 u.
    inward = None
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        r = room_at(x + dx * 40, y + dy * 40, z + 50)
        if r is not None and room_at(x - dx * 40, y - dy * 40, z + 50) is None:
            inward = (dx, dy, r)
            break
    if inward is None:
        print("[kino] fenêtre %d (%d, %d) : côté intérieur introuvable" % (k, x, y))
        continue
    dx, dy, r = inward
    # Poche extérieure 110 x 90 u, sol au niveau de la salle.
    ox, oy = x - dx * 55, y - dy * 55
    px0, px1 = (ox - 45, ox + 45) if dx else (ox - 55, ox + 55)
    py0, py1 = (oy - 55, oy + 55) if dx else (oy - 45, oy + 45)
    zf = floor_at(r, x + dx * 40, y + dy * 40)
    pockets.append({"id": "dehors_%d" % k, "outline": [GXZ(px0, py0), GXZ(px1, py0), GXZ(px1, py1), GXZ(px0, py1)],
                    "floor": round(zf * K, 3), "ceiling": round((zf + 130) * K, 3), "floor_mat": "cobble"})
    windows.append({"p": G(x, y, zf), "in": [dx, 0, -dy], "h": 2.35, "zone": r["zone"],
                    "spawns": [G(x - dx * 70, y - dy * 70, zf)]})

# Murs des poches (hors zone, simples) — trois côtés, le quatrième est le mur percé.
for pk in pockets:
    o = pk["outline"]
    wall_list.append({"room": pk["id"], "path": [o[0], o[1], o[2], o[3]], "closed": True,
                      "y0": pk["floor"] - 0.25, "y1": pk["ceiling"], "thick": 0.3, "mat": "brick", "openings": []})


# ---------------------------------------------------------------- objets muraux
def nearest_wall(x, y, z):
    """Point de la face du mur le plus proche (u) et direction vers ce mur (Godot)."""
    best = None
    for w in wall_list:
        if "_ori" not in w:
            continue
        if not (w["y0"] / K - 30 <= z <= w["y1"] / K):
            continue
        ori, line, (s0, s1) = w["_ori"], w["_line"], w["_s"]
        along, across = (y, x) if ori == "v" else (x, y)
        if not (s0 - 5 <= along <= s1 + 5):
            continue
        d = abs(across - line)
        if best is None or d < best[0]:
            best = (d, ori, line, across)
    if best is None or best[0] > 160:
        return None
    d, ori, line, across = best
    # Côté de la salle : celui où l'on trouve une salle au niveau de l'objet
    # (un objet relevé pile sur la ligne du mur reste dans sa pièce).
    sgn = 1 if line > across else -1
    if abs(line - across) < WALL_T:
        for s in (sgn, -sgn):
            px, py = (line - s * 30, y) if ori == "v" else (x, line - s * 30)
            rr = room_at(px, py, z)
            if rr is not None and abs(floor_at(rr, px, py) - (z - 40)) < 30:
                sgn = s
                break
    face = line - sgn * WALL_T / 2
    if ori == "v":
        return (face, y), [sgn, 0, 0]
    return (x, face), [0, 0, -sgn]


def wall_item(x, y, z, forced=None):
    if forced:
        v = {"N": [0, 0, -1], "S": [0, 0, 1], "E": [1, 0, 0], "W": [-1, 0, 0]}[forced]
        return {"p": G(x, y, z), "wall": v}
    hit = nearest_wall(x, y, z + 40)
    if hit is None:
        print("[kino] objet (%d, %d) : aucun mur proche" % (x, y))
        return {"p": G(x, y, z), "wall": [0, 0, -1]}
    (fx, fy), v = hit
    return {"p": G(fx, fy, z), "wall": v}


# ---------------------------------------------------------------- décor : salle de théâtre
# D'après les captures de BO1 (docs/reference/kino/images/theater_bo1/INDEX.md) :
# - un seul balcon en fer à cheval à ~4,8 m (ailes latérales, deux ailes au
#   fond de part et d'autre du bloc central : couloir en bas, cabine de
#   projection et ses baies en haut), porté par des colonnes ;
# - coin de l'atout rouge exigu sous le balcon du fond (plafond bas, cloison) ;
# - parterre : dix rangées de chaque côté de l'allée centrale, la moitié des
#   fauteuils ensevelis ou renversés ; grand tas de gravats au centre-droit
#   (vu des sièges) avec le lustre tombé ; nappes de débris sur les côtés ;
# - scène : cadre, rideaux, écran suspendu, tour du téléporteur, estrade de la
#   tourelle, pupitre et chaises pliantes.
# Les zones infranchissables sont des CollisionBox (clé « blockers »).
# Modèles : tools/blender/props/kino_theater.py.
import random
RNG = random.Random(115)
FACE = {"N": math.pi, "S": 0.0, "E": math.pi / 2, "W": -math.pi / 2}
PAR = ROOM["parterre"]
BALC_Z = 190  # dessus du balcon (u), ~4,8 m au-dessus du fond de la salle
props, blocks_decor, screens, beams, theater_lamps = [], [], [], [], []
inst = {}


def prop(model, x, y, z, yaw=0.0, scale=1.0, tilt=0.0, pid=None, remap=None):
    d = {"model": model, "p": G(x, y, z), "yaw": round(yaw, 4)}
    if remap:
        d["remap"] = remap
    if scale != 1.0:
        d["scale"] = scale
    if tilt:
        d["tilt"] = round(tilt, 4)
    if pid:
        d["id"] = pid
    props.append(d)


def seat(model, x, y, yaw, tilt=0.0, dz=0.0):
    z = floor_at(PAR, x, y) + dz
    g = G(x, y, z)
    inst.setdefault(model, []).append([g[0], g[1], g[2], round(yaw, 4), round(tilt, 4)])


def gbox(x0, y0, z0, x1, y1, z1):
    a, b = G(x0, y0, z0), G(x1, y1, z1)
    return [min(a[0], b[0]), min(a[1], b[1]), min(a[2], b[2]), max(a[0], b[0]), max(a[1], b[1]), max(a[2], b[2])]


blockers = []


def invisible(x0, y0, x1, y1, z0, z1, barrier=True, surface="concrete"):
    """Pavé de collision invisible (CollisionBox côté jeu, jamais un modèle Blender)."""
    b = gbox(x0, y0, z0, x1, y1, z1)
    blockers.append({"center": [round((b[0] + b[3]) / 2, 3), round((b[1] + b[4]) / 2, 3), round((b[2] + b[5]) / 2, 3)],
                     "size": [round(b[3] - b[0], 3), round(b[4] - b[1], 3), round(b[5] - b[2], 3)],
                     "yaw": 0.0, "barrier": barrier, "surface": surface})


def fz(x, y):
    return floor_at(PAR, x, y)


SEAT_W = 22  # u (0,55 m)


def column(x, y):
    """Colonne du balcon (modèle de 4,8 m) mise à l'échelle du sol en pente au dessous de la dalle."""
    f = fz(x, y)
    prop("column_balcony", x, y, f, 0.0, scale=round((BALC_Z - 14 - f) * K / 4.8, 3))


# --- balcon en fer à cheval : dalle (bloc visible) sur colonnes, garde-corps, gradins
for x0, y0, x1, y1 in ((-770, -330, -590, 880), (590, -330, 770, 880),
                       (-770, -510, -190, -330), (190, -510, 770, -330)):
    blocks_decor.append({"room": "parterre", "box": gbox(x0, y0, BALC_Z - 14, x1, y1, BALC_Z), "mat": "dark_wood"})
for side in (-1, 1):
    y = -250
    while y < 880:
        prop("balcony_front", side * 590, y + 78, BALC_Z, FACE["E"] if side < 0 else FACE["W"])
        column(side * 598, y)
        y += 157
    for x in (side * 470, side * 290):
        column(x, -338)
# Balcon du fond : gradins (modèle de 6 m de profondeur ramené aux 4,6 m de l'aile).
for x0, x1 in ((-770, -190), (190, 770)):
    x = x0 + 61
    while x < x1 - 30:
        prop("balcony_back", x, -330, BALC_Z, FACE["N"], scale=0.77)
        x += 122
# --- coin de l'atout rouge : exigu, sous le balcon du fond, cloison à l'ouest
blocks_decor.append({"room": "parterre", "box": gbox(-482, -510, -10, -466, -345, BALC_Z - 14), "mat": "plaster_theater"})
invisible(-770, -510, -466, -110, -60, BALC_Z - 14)  # derrière la cloison : ruines sous le balcon
for (x, y, yaw) in ((-445, -445, 1.2), (-430, -372, 2.6), (-238, -466, 4.1)):
    seat("seat_broken_" + RNG.choice("ab"), x, y, yaw, tilt=RNG.uniform(-0.8, 0.8))
prop("debris_planks", -410, -420, fz(-410, -420), 0.4)
prop("debris_scatter", -300, -250, fz(-300, -250), 1.3)
prop("rubble_heap_b", -560, -250, fz(-560, -250), 2.2)
theater_lamps.append({"p": G(-330, -420, 150), "range": 7.0, "energy": 1.4})
# Rangées courbes et concentriques (BO1) : arcs centrés loin derrière la scène,
# les bouts de rang avancent vers la scène ; chaque fauteuil regarde ce centre.
ROW_C = 4200


def row_y(y0, x):
    r = ROW_C - y0
    return ROW_C - math.sqrt(r * r - x * x)


def row_yaw(x, y):
    return math.atan2(-x, -(ROW_C - y))


def invisible_chord(xa, xb, y0, half, z0, z1):
    """Pavé barrière le long de la corde d'un rang courbe (tourné comme elle)."""
    ya, yb = row_y(y0, xa), row_y(y0, xb)
    a, b = G(xa, ya, z0), G(xb, yb, z1)
    ln = math.hypot(xb - xa, yb - ya) * K
    blockers.append({"center": [round((a[0] + b[0]) / 2, 3), round((a[1] + b[1]) / 2, 3), round((a[2] + b[2]) / 2, 3)],
                     "size": [round(ln, 3), round(b[1] - a[1], 3), round(2 * half * K, 3)],
                     "yaw": round(math.atan2(yb - ya, xb - xa), 4), "barrier": True, "surface": "concrete"})


# --- dix rangées de chaque côté de l'allée, la moitié ensevelies ou renversées
for y0 in range(-40, 660, 70):
    for side in (-1, 1):
        x = 175 + SEAT_W / 2
        while x < 380:
            r = RNG.random()
            xs_, ys_ = side * x, row_y(y0, x)
            yaw = row_yaw(xs_, ys_)
            if r < 0.45:
                seat("seat", xs_, ys_, yaw + RNG.uniform(-0.05, 0.05), tilt=RNG.uniform(-0.08, 0.12))
            elif r < 0.85:
                seat("seat_broken_" + RNG.choice("ab"), xs_, ys_, yaw + RNG.uniform(-0.7, 0.7),
                     tilt=RNG.uniform(-0.6, 0.5), dz=RNG.uniform(-10, 4))
            x += SEAT_W
# Trois rangées intactes devant la scène, avec une allée transversale.
for y0 in (690, 745, 800):
    for side in (-1, 1):
        for x0, x1 in ((175, 390), (440, 570)):
            x = x0 + SEAT_W / 2
            while x <= x1:
                xs_, ys_ = side * x, row_y(y0, x)
                seat("seat" if RNG.random() > 0.15 else "seat_broken_a", xs_, ys_, row_yaw(xs_, ys_),
                     tilt=RNG.uniform(-0.05, 0.05))
                x += SEAT_W
            xa, xb = sorted((side * x0, side * x1))
            invisible_chord(xa, xb, y0, 14, fz(0, y0) - 5, fz(0, y0) + 45)
# --- gravats : grand tas au centre-droit (vu des sièges : x > 0) avec le lustre
# tombé, nappes de débris et fauteuils arrachés sur les côtés.
prop("rubble_mound_big", 390, 410, fz(390, 410), 0.25)
prop("chandelier_fallen", 330, 560, fz(330, 560) + 40, 0.5)
for (m, x, y, yaw) in (("rubble_field_a", -520, 60, 0.3), ("rubble_field_b", -560, 430, 1.57),
                       ("rubble_field_a", 560, -200, 2.8), ("rubble_field_b", 600, 575, 0.1),
                       ("rubble_heap_a", -420, 250, 0.9), ("rubble_heap_c", -640, -60, 1.4),
                       ("rubble_heap_c", 640, 60, 1.4), ("rubble_heap_b", -300, 560, -0.6),
                       ("rubble_heap_a", 300, -250, 0.2)):
    prop(m, x, y, fz(x, y), yaw)
prop("debris_beam", -470, 330, fz(-470, 330), 0.9)
prop("debris_beam", 310, 80, fz(310, 80), -2.3)
for (x, y) in ((-250, 600), (300, -150), (-620, 280), (560, 560), (-420, -60), (250, 620), (-690, 620)):
    prop("debris_planks", x, y, fz(x, y), RNG.uniform(0, 6.28))
for (x, y) in ((-100, 620), (110, 300), (-60, -120), (90, 840), (-300, 860), (330, 870), (-130, 200)):
    prop("debris_scatter", x, y, fz(x, y), RNG.uniform(0, 6.28))
for i in range(60):
    side = RNG.choice((-1, 1))
    x = side * RNG.uniform(400, 740)
    y = RNG.uniform(-100 if side < 0 else -320, 630)
    seat("seat_broken_" + RNG.choice("ab"), x, y, RNG.uniform(0, 6.28), tilt=RNG.uniform(-1.3, 1.3), dz=RNG.uniform(0, 25))
# Côtés infranchissables (rangées et ruines).
invisible(-770, -110, -165, 640, -60, 110)
invisible(165, -510, 770, 640, -60, 110)
# --- lustre central, appliques au-dessus et au-dessous du balcon
prop("chandelier", -1, 414, 840, 0.0, pid="lustre")
theater_lamps.append({"p": G(-1, 414, 700), "range": 28.0, "energy": 3.6})
# Lumière d'appoint au-dessus des côtés effondrés et de la bande de scène
# (la salle de BO1 est sombre mais on y lit les gravats et les fauteuils).
for x in (-450, 450):
    for y in (50, 450, 800):
        theater_lamps.append({"p": G(x, y, 420), "range": 17.0, "energy": 1.7})
for side in (-1, 1):
    for y in (-150, 250, 650):
        prop("sconce", side * 762, y, BALC_Z + 130, FACE["E"] if side < 0 else FACE["W"])
        theater_lamps.append({"p": G(side * 730, y, BALC_Z + 130), "range": 10.0, "energy": 1.9})
    for y in (100, 500):
        prop("sconce", side * 590, y, 120, FACE["W"] if side < 0 else FACE["E"])
        theater_lamps.append({"p": G(side * 560, y, 120), "range": 8.0, "energy": 1.3})
# --- arcades au-dessus du balcon, sur les murs latéraux et le fond
for side in (-1, 1):
    y = -300
    while y < 860:
        prop("wall_arch_panel", side * 762, y, BALC_Z + 10, FACE["E"] if side < 0 else FACE["W"])
        y += 230
for x in (-560, -360, 360, 560):
    prop("wall_arch_panel", x, -502, BALC_Z + 10, FACE["N"])
# --- coupole (sous le plafond plat de la salle)
prop("dome", 0, 205, 680, 0.0)
# --- scène : cadre, rideaux, lambrequin, bannières, écran suspendu dans son cadre
PROSC = 0.75  # modèle : ouverture 22,8 × 11 m -> 17,1 × 8,25 m (captures)
prop("proscenium", 0, 1210, 0, FACE["S"], scale=PROSC)
# Rideau noué à droite seulement (à gauche, la tour du téléporteur cache le jambage).
prop("curtain_drape", 285, 1205, 0, FACE["S"], scale=PROSC)
prop("valance", 0, 1200, 330, FACE["S"], scale=PROSC)
# Bannières contre le mur de part et d'autre du cadre, une sur chaque mur latéral.
for x in (-470, 470):
    prop("banner", x, 1212, 410, FACE["S"])
prop("banner", -762, 700, 540, FACE["E"])
prop("banner", 762, 700, 540, FACE["W"])
# Coulisses : grand bloc central qui porte l'écran de cinéma (face à y = 1425, relevé
# de BO1), entouré d'un passage de 3 m (côtés et fond) ; la boîte (1, 1842) est
# contre le mur du fond, derrière l'écran.
SB = (-517 + 118, 1425, 747 - 118, 1907 - 118)
blocks_decor.append({"room": "coulisses", "box": gbox(SB[0], SB[1], -10, SB[2], SB[3], 580), "mat": "dark_wood"})
prop("screen_block_face", 0, SB[1], 0, FACE["S"])
screens.append({"p": G(0, 1410, 199), "w": 9.8, "h": 6.3, "yaw": 0.0})
prop("screen_frame", 0, 1411, 199, FACE["S"], scale=round(9.8 / 6.5, 3))
beams.append({"from": G(-62, -92, 384), "to": G(0, 1408, 199), "radius": 2.4})
# Rais de lumière froide tombant des trous de la voûte : fins, obliques (même
# direction pour tous, comme un soleil bas), toujours visibles.
SUN = (250, -400)
shafts = [{"from": G(x, y, 870), "to": G(x + SUN[0], y + SUN[1], fz(x + SUN[0], y + SUN[1])),
           "top": 0.35, "radius": 0.75, "shaft": True}
          for (x, y) in ((-420, 600), (150, 250), (380, 700), (-560, 150), (0, 500))]
theater_lamps.append({"p": G(-300, 1000, 420), "range": 14.0, "energy": 2.2})
theater_lamps.append({"p": G(300, 1000, 420), "range": 14.0, "energy": 2.2})
# Tour du téléporteur derrière son pad, estrade de la tourelle au bord de scène,
# pupitre et chaises pliantes.
# Tour : origine au bord avant du socle (Ø 3 m), juste derrière le pad (Ø 3 m).
# Tour : origine au bord avant du socle ; le socle mord un peu sur le pad (captures).
prop("mdt_tower", -306, 1150, 0, FACE["S"], pid="tour_teleporteur")
prop("mdt_arcs", -306, 1150, 0, FACE["S"])
prop("turret_podium", 230, 1040, 0, FACE["S"], pid="estrade_tourelle")
# Pupitre au bord de scène, deux chaises pliantes au pied de la scène (captures).
prop("lectern", 0, 950, 0, FACE["S"])
for (x, y, yaw) in ((-70, 895, 0.3), (-28, 898, -0.2)):
    prop("folding_chair", x, y, fz(x, y), yaw)
# --- habillage d'après les photos de référence
# Nez de scène sculpté (panneaux de 4 m), entre les deux escaliers et sur les côtés.
LIP = 4.0 / K
for x0, x1 in ((-770, -430), (-230, 300), (500, 770)):
    x = x0 + LIP / 2
    while True:
        cx = min(x, x1 - LIP / 2)
        prop("stage_lip", cx, 920, fz(cx, 919), FACE["S"])
        if cx >= x1 - LIP / 2:
            break
        x += LIP
# Gros câbles bleus : de la tour au bord de scène, puis le long de l'allée.
prop("cable_run_b", -250, 1010, 0, 1.0)
prop("cable_drop", -200, 920, 0, FACE["S"])
for (m, x, y, yaw) in (("cable_run_a", -150, 760, 1.35), ("cable_run_b", -95, 470, 1.7), ("cable_run_a", -60, 170, 1.5)):
    prop(m, x, y, fz(x, y), yaw)
# Bidons bleus : sous le balcon à gauche près de la scène, et en coulisses à droite.
prop("blue_barrel_group", -700, 720, fz(-700, 720), 0.4)
prop("blue_barrel_group", 660, 1300, 0, -0.6)
# Coulisses devant le bloc de l'écran : caisses de transport, échafaudage à escalier.
prop("stage_crates", -180, 1320, 0, 0.2)
prop("stage_crates", 240, 1330, 0, -0.3)
prop("scaffold_stairs", 520, 1320, 0, FACE["S"])
# Frises à losanges et corniches : au-dessus des arcades et en haut des murs ;
# bande plus claire que le mur (captures), losanges sombres.
FR = 6.0 / K
FRIEZE = {"vault_theater": "fabric"}
for z in (560, 800):
    for side in (-1, 1):
        y = -480 + FR / 2
        while y < 1200:
            prop("wall_frieze", side * 762, y, z, FACE["E"] if side < 0 else FACE["W"], remap=FRIEZE)
            y += FR
    for x in (-590, -354, -118, 118, 354, 590):
        prop("wall_frieze", x, -502, z, FACE["N"], remap=FRIEZE)
        prop("wall_frieze", x, 1212, z, FACE["S"], remap=FRIEZE)
# --- salle de projection : projecteur face à sa baie, deuxième baie
# d'observation, étagère à bobines, bureau, horloge au-dessus de la machine
# d'amélioration, bobines au sol.
prop("projector", -62, -140, 320, FACE["N"])
prop("reel_shelf", -160, -330, 320, FACE["E"])
prop("desk", 160, -300, 320, FACE["W"])
prop("wall_clock", 3, -506, 432, FACE["N"])
for (x, y) in ((-40, -260), (90, -380), (-120, -420)):
    prop("film_reel", x, y, 320, RNG.uniform(0, 6.28))
theater_lamps.append({"p": G(0, -300, 440), "range": 9.0, "energy": 1.8})

instances = [{"model": m, "items": items} for m, items in sorted(inst.items())]
# Zombies qui sortent des gravats : au pied des tas, côté allée et bande de scène.
# (415, 693) : dans l'allée latérale au pied du grand tas ; à (440, 630) le zombie
# sortait dans le bord bas du tas (pavé barrière de 0,2 m flottant au-dessus de la
# pente) et restait coincé entre le tas et le rang de fauteuils.
RISERS = [(-180, -120, 0), (-185, 240, 0), (185, 10, 0), (182, 400, 0), (-420, 630, 0), (415, 693, 0),
          (-420, -200, 0)]

markers = {
    "player_spawns": [G(*p) for p in PLAYER_SPAWNS],
    "zombie_spawns": [{"p": w["spawns"][0], "zone": w["zone"]} for w in windows]
    + [{"p": G(*p), "zone": "t"} for p in RISERS],
    "doors": [],
    "wall_buys": [], "perks": [], "grenade_buys": [], "box": [], "traps": [], "windows": windows,
}
for d in DOORS:
    ori_v = any(w.get("_ori") == "v" and abs(w["_line"] - d["x"]) <= 10 and w["_s"][0] <= d["y"] <= w["_s"][1] for w in wall_list)
    m = {"id": d["id"], "p": G(d["x"], d["y"], d["z"]), "yaw": round(math.pi / 2, 4) if ori_v else 0.0,
         "w": round(d["w"] * K, 3), "h": round(d["h"] * K, 3), "depth": round(2 * WALL_T * K, 3),
         "cost": d.get("cost", 0), "zones": d["zones"]}
    for key in ("power", "link", "curtain"):
        if key in d:
            m[key] = d[key]
    markers["doors"].append(m)
for mid, weapon, x, y, z in WALL_BUYS:
    it = wall_item(x, y, z)
    it.update({"id": mid, "weapon": weapon})
    markers["wall_buys"].append(it)
for gid, x, y, z in GRENADES:
    it = wall_item(x, y, z)
    it["id"] = gid
    markers["grenade_buys"].append(it)
for mid, perk, x, y, z in PERKS:
    it = wall_item(x, y, z)
    it.update({"id": mid, "perk": perk})
    markers["perks"].append(it)
for b in BOXES:
    markers["box"].append(wall_item(b[0], b[1], b[2], b[3] if len(b) > 3 else None))
markers["box_boards"] = [wall_item(*b) for b in BOX_BOARDS]
markers["power"] = wall_item(*POWER)
markers["pap"] = wall_item(*PAP)
for t in TRAPS:
    x0, y0, z0, x1, y1, z1 = t["area"]
    a, b = G(x0, y0, z0), G(x1, y1, z1)
    lv = wall_item(*t["lever"])
    # BO1 : 1000 points, actifs 40 s, recharge 60 s, un levier à chaque bout.
    markers["traps"].append({"id": t["id"], "lever": lv, "lever2": wall_item(*t["lever2"]), "fire": t.get("fire", False),
                             "active": 40.0, "cooldown": 60.0,
                             "area": [min(a[0], b[0]), a[1], min(a[2], b[2]), max(a[0], b[0]), b[1], max(a[2], b[2])]})
tp = TELEPORTER
markers["teleporter"] = {"pad": G(*tp["pad"]), "exit": G(*tp["exit"]), "exit_zone": "p",
                         "mainframe": {"p": G(*tp["mainframe"]), "wall": [0, 0, -1], "floor": True}}
markers["player_yaw"] = 0.0

# Lampes : une grille par salle (gris : l'éclairage final viendra à la passe artistique).
lamps = list(theater_lamps)
# Coulisses : autour du bloc de l'écran (aucune lampe dans le bloc).
for (x, y) in ((-300, 1320), (0, 1320), (300, 1320), (620, 1320), (-458, 1560), (-458, 1840),
               (-200, 1848), (200, 1848), (500, 1848), (688, 1560)):
    lamps.append({"p": G(x, y, 220), "range": 10.0, "energy": 2.2})
for r in ROOMS:
    if r["id"] in ("parterre", "avant_scene", "coulisses"):
        continue  # éclairage propre (lustre, appliques, scène, coulisses : voir le décor)
    xs = [p[0] for p in r["poly"]]
    ys = [p[1] for p in r["poly"]]
    step = 420 if r["ceil"] - floor_at(r, xs[0], ys[0]) > 300 else 320
    x = min(xs) + step / 2
    while x < max(xs):
        y = min(ys) + step / 2
        while y < max(ys):
            if inside(r["poly"], x, y):
                f = floor_at(r, x, y)
                h = min(r["ceil"] - 30, f + 330)
                lamps.append({"p": G(x, y, h), "range": round(min(16.0, (h - f) * K * 2.4 + 4), 1),
                              "energy": 2.0 if r.get("sky") else 2.4})
            y += step
        x += step
markers["lamps"] = lamps

# ---------------------------------------------------------------- zones
zones = {}
for r in ROOMS:
    xs = [p[0] for p in r["poly"]]
    ys = [p[1] for p in r["poly"]]
    fmin = min(floor_at(r, x, y) for x in (min(xs), max(xs)) for y in (min(ys), max(ys)))
    a, b = G(min(xs), min(ys), fmin - 30), G(max(xs), max(ys), r["ceil"])
    box = [min(a[0], b[0]), a[1], min(a[2], b[2]), max(a[0], b[0]), b[1], max(a[2], b[2])]
    vol = (box[3] - box[0]) * (box[4] - box[1]) * (box[5] - box[2])
    zones.setdefault(r["zone"], []).append((vol, box))
# Les plus petites boîtes d'abord (balcons, galeries, salle de projection avant la grande salle).
ordered = sorted(((vol, zid, box) for zid, lst in zones.items() for vol, box in lst))
zone_json = {}
for vol, zid, box in ordered:
    zone_json.setdefault(zid, {"boxes": []})["boxes"].append(box)
zone_order = []
for vol, zid, box in ordered:
    zone_order.append({"zone": zid, "box": box})

# ---------------------------------------------------------------- sortie
rooms_json = []
for r in ROOMS:
    fm, wm, cm = r["mats"]
    rj = {"id": r["id"], "outline": [GXZ(*p) for p in r["poly"]], "ceiling": round(r["ceil"] * K, 3),
          "floor_mat": fm, "ceiling_mat": cm}
    if "slope" in r:
        rj["slope"] = [G(*p) for p in r["slope"]]
    else:
        rj["floor"] = round(r["floor"] * K, 3)
    if r.get("slab"):
        rj["floor_slab"] = 0.3
    if r.get("box"):
        rj["ceiling_slab"] = 0.3
    if r.get("sky") or r.get("no_ceiling"):
        rj["no_ceiling"] = True
    rooms_json.append(rj)
rooms_json += pockets

stairs_json = [{"room": s["room"], "a": G(*s["a"]), "b": G(*s["b"]), "w": round(s["w"] * K, 3), "mat": s["mat"]}
               for s in STAIRS]
# Baie de la cabine : pavé barrière invisible (on ne saute pas dans la salle, les
# balles passent) ; fin cadre sombre autour de la fente (décor, sans collision).
blocks = []
invisible(-BAIE_W / 2, -96, BAIE_W / 2, -84, BAIE_Z[0] - 5, BAIE_Z[1] + 5, surface="wood")
for z0, z1 in ((BAIE_Z[0] - 3, BAIE_Z[0]), (BAIE_Z[1], BAIE_Z[1] + 3)):
    blocks.append({"room": "projection", "box": gbox(-BAIE_W / 2 - 3, -101, z0, BAIE_W / 2 + 3, -79, z1),
                   "mat": "dark_wood", "nocollide": True})
for x in (-BAIE_W / 2 - 3, BAIE_W / 2):
    blocks.append({"room": "projection", "box": gbox(x, -101, BAIE_Z[0], x + 3, -79, BAIE_Z[1]),
                   "mat": "dark_wood", "nocollide": True})

# Haut des escaliers qui arrivent contre un mur : l'ouverture (porte ou passage)
# descend sous le palier (z - 20 pour les portes) et l'escalier s'arrête avant le
# mur ; il restait une fente de 0,1 à 0,25 m creusée jusqu'à 0,5 m sous le palier,
# plus étroite que la capsule d'un zombie : son rayon de sol l'y faisait
# retomber à chaque pas, coincé contre le bord du palier. Pavé plein (couche du
# décor, invisible, au ras du haut des marches) de la fin des marches à l'autre
# face du mur.
for st in STAIRS:
    (ax, ay, _az), (bx, by, bz) = st["a"], st["b"]
    along_y = abs(by - ay) > abs(bx - ax)
    rise = (by - ay) if along_y else (bx - ax)
    sgn = 1 if rise > 0 else -1
    top, mid = (by, bx) if along_y else (bx, by)
    near = [w for w in wall_list
            if w.get("_ori") == ("h" if along_y else "v") and 0 <= (w["_line"] - top) * sgn < 30
            and w["_s"][0] < mid < w["_s"][1] and w["y0"] < (bz + 1) * K and w["y1"] > (bz - 30) * K]
    # Fente : dessus du mur ou bas d'une ouverture sous le palier.
    lo, hi = (bz - 30) * K, bz * K - 0.05
    lines = [w["_line"] for w in near
             if lo <= w["y1"] < hi or any(lo <= o["y0"] < hi for o in w["openings"])]
    if not lines:
        continue
    end = min(lines, key=lambda ln: abs(ln - top)) + sgn * (WALL_T / 2 + 4)
    u0, u1 = sorted((top, end))
    v0, v1 = mid - st["w"] / 2, mid + st["w"] / 2
    if along_y:
        invisible(v0, u0, v1, u1, bz - 30, bz, barrier=False, surface="wood" if st["mat"] == "wood" else "concrete")
    else:
        invisible(u0, v0, u1, v1, bz - 30, bz, barrier=False, surface="wood" if st["mat"] == "wood" else "concrete")

for w in wall_list:
    for k in ("_ori", "_line", "_s"):
        w.pop(k, None)

layout = {"id": "kino", "note": "Généré par tools/blender/kino/make_layout.py - ne pas modifier à la main.",
          "rooms": rooms_json, "walls": wall_list, "rails": rail_list, "stairs": stairs_json,
          "blocks": blocks + blocks_decor, "props": props, "instances": instances, "screens": screens, "beams": beams, "shafts": shafts, "blockers": blockers,
          # Objets de la salle : plâtre gris-vert et voûte grise (BO1) au lieu du rouge.
          "prop_materials": {"wall_theater": "plaster_theater", "ceiling_theater": "vault_theater"},
          "zones": zone_json, "zone_order": zone_order, "markers": markers}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(layout, f, ensure_ascii=False, indent=1)
print("[kino] %d salles, %d murs, %d garde-corps, %d fenêtres, %d lampes -> %s" % (
    len(rooms_json), len(wall_list), len(rail_list), len(windows), len(lamps), OUT))
