# Échantillons d'ennemis (GAME_CONCEPT § 4.19, LootRules.SAMPLES) : un petit
# modèle CUBIQUE par sorte, à l'échelle des personnages et des objets tenus
# (1 cube = 2,5 cm, vx.CUBE_CHAR), pour les icônes de l'inventaire du hub
# (rendus : samples_render.py).
#
# Chaque fonction build_<id>() renvoie un Sample : liste de pièces
# (Model, genre) où genre vaut « solid » (opaque) ou « glass » (verre :
# rendu transmissif, contour visible seulement de face), et la rotation de
# présentation (degrés, XYZ) qui oriente l'objet devant la caméra 3/4.
# Les couleurs reprennent les palettes des ennemis (dog_voxel, nurse_voxel,
# brancardier_voxel, surgeon_voxel) et vx.DECOR_PALETTE.
import math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_CHAR
P = vx.DECOR_PALETTE

# --- palette commune ---------------------------------------------------------
BLOOD = (0.46, 0.05, 0.05)
BLOOD_DRY = (0.30, 0.07, 0.06)
BLOOD_WET = (0.62, 0.07, 0.07)
FLESH = (0.52, 0.14, 0.12)
GUM = (0.40, 0.11, 0.12)
TOOTH = (0.86, 0.80, 0.62)
TOOTH_TIP = (0.93, 0.90, 0.78)
DENTIN = (0.74, 0.62, 0.42)
FUR = (0.56, 0.44, 0.31)
FUR_DARK = (0.29, 0.21, 0.15)
FUR_LIGHT = (0.74, 0.64, 0.50)
FUR_GREY = (0.60, 0.56, 0.49)
MANGE = (0.66, 0.50, 0.47)
SCAB = (0.27, 0.12, 0.09)
COLLAR = (0.46, 0.13, 0.09)
COLLAR_WORN = (0.32, 0.10, 0.07)
STUD = (0.74, 0.74, 0.70)
TAG = P["brass"]
LEATHER = (0.34, 0.19, 0.09)
LEATHER_DARK = (0.20, 0.10, 0.05)
LEATHER_LIGHT = (0.46, 0.28, 0.14)
BUCKLE = (0.72, 0.70, 0.62)
BAND = (0.86, 0.86, 0.82)
BAND_DARK = (0.74, 0.74, 0.70)
TAG_BLUE = (0.24, 0.42, 0.78)
INK = (0.12, 0.13, 0.16)
OOZE = (0.50, 0.78, 0.20)
PLUNGER = (0.88, 0.88, 0.86)
NEEDLE = (0.74, 0.76, 0.78)
BADGE = (0.96, 0.96, 0.94)
BADGE_BAND = (0.22, 0.42, 0.74)
STEEL = (0.76, 0.79, 0.82)
STEEL_DARK = (0.42, 0.44, 0.48)
EDGE = (0.97, 0.99, 1.0)
TEAL = (0.15, 0.40, 0.44)        # calot / blouse du Chirurgien
HEART = (0.80, 0.16, 0.24)
HEART_DARK = (0.50, 0.07, 0.14)
HEART_LIGHT = (1.0, 0.50, 0.55)
HEART_GLOW = (1.0, 0.36, 0.42)
VEIN_BLUE = (0.36, 0.28, 0.56)
FAT = (0.90, 0.80, 0.52)
PINK = (0.93, 0.45, 0.52)
PINK_DARK = (0.70, 0.22, 0.32)
PINK_LIGHT = (0.98, 0.66, 0.68)
CORD = (0.99, 0.93, 0.90)
FORMOL = (0.94, 0.98, 0.80)      # formol jaune-vert (teinte du verre)
GLASS_TINT = (0.86, 0.96, 0.97)


def jit(col, c, amt=0.07, seed=0):
    """Variation de teinte par cube (« un pixel = un cube »)."""
    return vx.tone(col, 1.0 + (vx.noise(c, seed) - 0.5) * 2 * amt)


def mix(a, b, k):
    return tuple(x + (y - x) * k for x, y in zip(a, b))


class Sample:
    def __init__(self, sid, rot=(0, 0, 0)):
        self.id = sid
        self.parts = []          # [(Model, "solid" | "glass", nom)]
        self.rot = rot

    def part(self, name, kind="solid"):
        m = vx.Model(CUBE)
        self.parts.append((m, kind, name))
        return m


def surface(m, c):
    return any((c[0] + n[0], c[1] + n[1], c[2] + n[2]) not in m.vox for n in vx.DIRS.values())


# ---------------------------------------------------------------------------
# Chiens
# ---------------------------------------------------------------------------

def build_dog_fang():
    """Croc de chien : canine recourbée en ivoire, racine arrachée avec un
    morceau de gencive sanglant, coulures de sang."""
    s = Sample("dog_fang", rot=(0, -14, 0))
    m = s.part("fang")
    for z in range(0, 18):
        if z < 5:
            t = z / 5.0
            r, cx = 1.5 + 0.9 * t, 0.0
        else:
            t = (z - 5) / 12.0
            r = 2.55 * (1 - t) ** 0.85 + 0.42
            cx = 4.2 * t ** 1.8
        for x in range(-5, 9):
            for y in range(-4, 4):
                if ((x + 0.5 - cx) / r) ** 2 + ((y + 0.5) / (r * 0.82)) ** 2 <= 1.0:
                    c = (x, y, z)
                    if z < 4:
                        col = jit(DENTIN, c, 0.08, 1)
                        if vx.noise(c, 2) < 0.2:
                            col = jit(BLOOD_DRY, c, 0.1, 3)
                    else:
                        k = min(1.0, max(0.0, (z - 4) / 13.0))
                        col = mix(mix(DENTIN, TOOTH, 0.6), TOOTH, min(1, k * 2.2))
                        col = mix(col, TOOTH_TIP, max(0, k - 0.6) * 2.5)
                        col = jit(col, c, 0.035, 4)
                    m.set(x, y, z, "bone", color=col)
    # Gencive arrachée autour du collet (anneau de chair, bord déchiqueté).
    for z in (3, 4, 5):
        for x in range(-5, 5):
            for y in range(-5, 4):
                d = math.hypot(x + 0.5, (y + 0.5) / 0.85)
                rr = 3.3 if z == 4 else 2.8
                if d <= rr and (x, y, z) not in m.vox or (d <= rr and z == 4):
                    if z == 5 and vx.noise((x, y, z), 9) < 0.45:
                        continue
                    if z == 3 and vx.noise((x, y, z), 8) < 0.3:
                        continue
                    col = GUM if vx.noise((x, y, z), 5) < 0.6 else FLESH
                    if vx.noise((x, y, z), 6) < 0.18:
                        col = BLOOD_WET
                    m.set(x, y, z, "wound", color=jit(col, (x, y, z), 0.1, 7))
    # Coulures de sang sur l'émail (côté visible et dessus de la courbe).
    for (x, y, z) in list(m.vox):
        if m.vox[(x, y, z)].mat != "bone" or z < 6 or not surface(m, (x, y, z)):
            continue
        k = (z - 6) / 5.0
        if k < 1 and vx.noise((x, y, z), 11) < 0.22 * (1 - k) ** 2:
            m.set(x, y, z, "wound", color=BLOOD_WET if vx.noise((x, y, z), 12) < 0.5 else BLOOD)
    # Une coulure franche qui descend du collet sur la face avant.
    for z, x in ((6, 0), (7, 0), (8, 1), (9, 1)):
        for y in range(-4, 0):
            if (x, y, z) in m.vox and (x, y - 1, z) not in m.vox:
                m.set(x, y, z, "wound", color=BLOOD_WET)
                break
    return s


def build_dog_fur():
    """Touffe de poils prélevée : faisceau de poils gris-brun noué au milieu
    par une ficelle rouge (échantillon), les deux bouts qui s'évasent en
    mèches de longueurs inégales ; stries de poils dans la longueur,
    pointes plus claires, racines du côté gauche collées de sang et de
    bouts de peau galeuse."""
    s = Sample("dog_fur", rot=(0, -30, 0))
    m = s.part("fur")
    tones = [FUR, FUR_GREY, FUR_DARK, FUR, FUR_LIGHT, FUR, mix(FUR, FUR_DARK, 0.5)]
    # Faisceau en éventail dans le plan XZ (face à la caméra) : chaque brin
    # (y, s) part du nœud et s'écarte en ligne droite ; aux bouts, les brins
    # se séparent en mèches.
    for y in (-2, -1, 0, 1):
        for s2 in range(-5, 5):
            s_ = s2 + 0.5 + (0.5 if y % 2 else 0.0)
            if y in (-2, 1) and abs(s_) > 3.6:
                continue
            strand = (y, s2, 0)
            base = tones[int(vx.noise(strand, 1) * len(tones)) % len(tones)]
            if (s2 + y) % 2:
                base = vx.tone(base, 0.8)  # brins alternés clair / sombre
            lr = 10.0 - abs(s_) * 0.5 + vx.noise(strand, 2) * 2.5
            ll = 8.5 - abs(s_) * 0.4 + vx.noise(strand, 3) * 2.0
            for x in range(-12, 13):
                ax = abs(x + 0.5)
                lim = lr if x >= 0 else ll
                if ax > lim:
                    continue
                zf = s_ * (0.32 + 0.12 * ax) + 0.010 * max(0.0, x) ** 2
                c = (x, y, int(math.floor(zf)))
                t = ax / lim
                col = mix(base, FUR_LIGHT, max(0, t - 0.7) * 2.0)
                if x < -4 and vx.noise(c, 4) < 0.16:
                    col = BLOOD_DRY if vx.noise(c, 5) < 0.6 else MANGE
                m.set(*c, "cloth", color=jit(col, c, 0.04, 6))
    # Ficelle rouge nouée au milieu (deux tours) et bout qui pend.
    for x in (-1, 1):
        for y in range(-3, 3):
            for z in range(-3, 3):
                d = math.hypot(y + 0.5, z + 0.5)
                if 1.5 < d <= 2.5:
                    m.set(x, y, z, "fabric", color=jit((0.70, 0.12, 0.10), (x, y, z), 0.06))
    for c in ((0, -3, -1), (0, -3, -2), (1, -3, -3), (1, -3, -4), (0, -3, -4)):
        m.set(*c, "fabric", color=(0.62, 0.10, 0.08))
    return s


def build_dog_collar():
    """Collier de cuir rouge sang usé, clous d'acier, boucle, et médaille en
    os de laiton terni qui pend dessous."""
    s = Sample("dog_collar", rot=(0, 0, 0))
    m = s.part("collar")
    R0, R1, CZ = 5.4, 7.6, 0.0
    for x in range(-9, 9):
        for z in range(-9, 9):
            d = math.hypot(x + 0.5, z + 0.5 - CZ)
            if R0 <= d <= R1:
                for y in range(0, 3):
                    c = (x, y, z)
                    col = COLLAR if vx.noise(c, 1) < 0.75 else COLLAR_WORN
                    if vx.noise(c, 2) < 0.07:
                        col = mix(COLLAR, (0.75, 0.55, 0.45), 0.5)  # éraflure
                    m.set(*c, "leather", color=jit(col, c, 0.06, 3))
    # Coutures sombres le long des bords (face avant).
    for (x, y, z), v in list(m.vox.items()):
        if y == 0:
            d = math.hypot(x + 0.5, z + 0.5)
            if (d < R0 + 0.7 or d > R1 - 0.7) and (x + z) % 2 == 0:
                m.face_color[(x, y, z, "-y")] = vx.tone(v.color, 0.62)
    # Clous en façade.
    for a in range(0, 360, 36):
        if 70 <= a <= 110:
            continue
        ar = math.radians(a)
        rm = (R0 + R1) / 2
        x, z = int(math.floor(rm * math.cos(ar))), int(math.floor(rm * math.sin(ar)))
        m.set(x, -1, z, "metal", color=jit(STUD, (x, -1, z), 0.06))
    # Boucle (haut) : cadre d'acier sur la face avant, ardillon au centre.
    for x in range(-3, 3):
        for z in range(4, 9):
            edge = x in (-3, 2) or z in (4, 8)
            if edge:
                m.set(x, -1, z, "metal", color=jit(BUCKLE, (x, -1, z), 0.06, 4))
    for z in range(5, 8):
        m.set(-1, -2, z, "metal", color=STEEL)  # ardillon
    m.set(-1, -2, 7, "metal", color=vx.tone(BUCKLE, 0.8))
    # Rouille sur la boucle.
    for c in ((2, -1, 4), (-3, -1, 8)):
        m.set(*c, "metal", color=P["rust"])
    # Anneau en D et médaille en os.
    for x, z in ((-1, -9), (0, -9), (-2, -10), (1, -10), (-1, -11), (0, -11)):
        m.set(x, 1, z, "metal", color=STUD)
    bone = ["##.....##",
            "#########",
            "#########",
            "##.....##"]
    for r, row in enumerate(bone):
        for i, ch in enumerate(row):
            if ch == "#":
                c = (i - 5, 1, -12 - r)
                col = jit(TAG, c, 0.07, 5)
                m.set(*c, "metal", color=col)
    # Gravure (patte) et éclaboussure de sang.
    for x, z in ((-3, -13), (-1, -13), (1, -13), (-2, -14), (0, -14)):
        m.face_color[(x, 1, z, "-y")] = vx.tone(TAG, 0.5)
    for c in ((2, 1, -14), (3, 1, -13)):
        m.face_color[(c[0], c[1], c[2], "-y")] = BLOOD
    for c in ((-6, 0, -4), (-7, 0, -3), (-6, 0, -5), (5, 0, -5)):
        if c in m.vox:
            m.face_color[(c[0], c[1], c[2], "-y")] = BLOOD
    return s


# ---------------------------------------------------------------------------
# Brancardier
# ---------------------------------------------------------------------------

def build_brancard_strap():
    """Sangle de contention : cuir brun épais en S, bords foncés, trous de
    réglage, grosse boucle d'acier à un bout, bout arraché et sanglant."""
    s = Sample("brancard_strap", rot=(42, 0, -6))
    m = s.part("strap")
    L, hw, N = 22.0, 2.2, 400

    def center(t):
        return 2.0 + (L - 2.0) * t, 3.4 * math.sin(2 * math.pi * t * 0.85 + 0.35)

    pts = [center(i / float(N)) for i in range(N + 1)]
    for x in range(0, 24):
        for y in range(-8, 8):
            px, py = x + 0.5, y + 0.5
            bi = min(range(N + 1), key=lambda i: (px - pts[i][0]) ** 2 + (py - pts[i][1]) ** 2)
            d = math.hypot(px - pts[bi][0], py - pts[bi][1])
            t = bi / float(N)
            if d > hw or bi == N:
                continue
            c = (x, y, 0)
            if bi == 0 and px < pts[0][0] - 0.5:
                continue
            edge = d > hw - 0.9
            col = LEATHER_DARK if edge else LEATHER
            if not edge and vx.noise(c, 1) < 0.14:
                col = LEATHER_LIGHT
            if d < 0.7 and any(abs(t - th) < 0.014 for th in (0.38, 0.50, 0.62)):
                col = (0.05, 0.04, 0.03)  # trou de réglage
            if t > 0.92:
                if vx.noise(c, 3) < 0.35:
                    continue
                col = BLOOD if vx.noise(c, 4) < 0.6 else BLOOD_WET
            m.set(*c, "leather", color=jit(col, c, 0.06, 2))
            # Couture claire le long des bords (un point sur deux).
            if edge and (x + y) % 2 == 0 and 0.05 < t < 0.9:
                m.face_color[(x, y, 0, "+z")] = (0.72, 0.62, 0.44)
    # Fibres qui dépassent du bout arraché.
    ex, ey = center(1.0)
    for dy, ln in ((-1, 2), (0, 1), (1, 3)):
        for k in range(ln):
            m.set(int(ex) + k, int(math.floor(ey)) + dy, 0, "leather", color=LEATHER_LIGHT)
    # Boucle : cadre d'acier plat (un cube d'épaisseur) autour du début de
    # la sangle, barre arrière sous le cuir, ardillon posé dessus.
    bx, by = center(0.0)
    bx, by = int(bx), int(math.floor(by))
    y0, y1 = by - 3, by + 3
    for x in range(bx - 3, bx + 2):
        for y in range(y0, y1 + 1):
            side = y in (y0, y1)
            if x == bx - 3 or side:
                c = (x, y, 0)
            elif x == bx + 1:
                c = (x, y, 1)  # barre avant, par-dessus la sangle
            else:
                continue
            col = jit(BUCKLE, c, 0.06, 5)
            if vx.noise(c, 6) < 0.1:
                col = P["rust"]
            m.set(*c, "metal", color=col)
    for y in (y0, y1):
        m.set(bx + 1, y, 0, "metal", color=jit(BUCKLE, (bx + 1, y, 0), 0.06, 5))
    for x in range(bx - 2, bx + 3):
        m.set(x, by, 1, "metal", color=STEEL)  # ardillon
    # Taches de sang séché.
    for c in list(m.vox):
        if m.vox[c].mat == "leather" and vx.noise(c, 14) < 0.06:
            m.face_color[(c[0], c[1], c[2], "+z")] = BLOOD_DRY
    return s


def build_brancard_bracelet():
    """Bracelet d'identification d'hôpital : boucle ovale de plastique blanc,
    étiquette (bande bleue, écriture, code-barres), languette percée qui
    dépasse, bouton-pression bleu, traces de sang."""
    s = Sample("brancard_bracelet", rot=(10, 0, 0))
    m = s.part("bracelet")
    A, B, H = 8.6, 6.2, 3
    for x in range(-10, 10):
        for y in range(-8, 8):
            px, py = x + 0.5, y + 0.5
            r = math.hypot(px / A, py / B)
            ri = math.hypot(px / (A - 1.15), py / (B - 1.15))
            if r <= 1.0 and ri > 1.0:
                for z in range(H):
                    c = (x, y, z)
                    col = BAND if vx.noise(c, 1) < 0.85 else BAND_DARK
                    m.set(*c, "rubber", color=jit(col, c, 0.03, 2))
    # Étiquette sur l'avant (-Y) : plaque collée, un cube plus haute.
    yf = min(y for (x, y, z) in m.vox if x == 0) - 1
    lab = [  # de haut en bas (z = H .. 0), x = -5 .. 5
        "BBB.KKKK.K.",
        "BBB.KK.KKK.",
        "...........",
        "K.KK.K.KK.K",
    ]
    for r, row in enumerate(lab):
        z = H - r
        for i, ch in enumerate(row):
            x = i - 5
            c = (x, yf, z)
            m.set(*c, "fabric", color=jit(BADGE, c, 0.02, 3))
            if ch == "B":
                m.face_color[(x, yf, z, "-y")] = TAG_BLUE
            elif ch == "K":
                m.face_color[(x, yf, z, "-y")] = INK
            # Comble entre l'étiquette et l'ovale.
            for y in range(yf + 1, yf + 3):
                if (x, y, min(z, H - 1)) not in m.vox and z < H:
                    m.set(x, y, z, "rubber", color=BAND)
    # Languette qui dépasse de la fermeture (+X), trous de réglage.
    for k in range(7):
        for z in range(0, 2):
            c = (9 + k, -2 - (k // 3), z)
            m.set(*c, "rubber", color=jit(BAND, c, 0.03, 4))
    for k in (2, 5):
        m.face_color[(9 + k, -2 - (k // 3), 1, "+z")] = (0.30, 0.30, 0.30)
    for z in range(0, 3):
        m.set(8, -3, z, "rubber", color=TAG_BLUE)  # bouton-pression
    # Sang et crasse.
    for c in list(m.vox):
        if vx.noise(c, 15) < 0.07 and c[1] > yf:
            v = m.vox[c]
            m.set(*c, v.mat, color=BLOOD_DRY if vx.noise(c, 16) < 0.5 else BLOOD)
    for c in ((3, yf, 0), (4, yf, 0), (4, yf, 1), (5, yf, 0)):
        m.face_color[(c[0], c[1], c[2], "-y")] = BLOOD
    return s


# ---------------------------------------------------------------------------
# Infirmière
# ---------------------------------------------------------------------------

def _disk(r, x, y):
    return (x + 0.5) ** 2 + (y + 0.5) ** 2 <= r * r


def build_nurse_vocal_cords():
    """Cordes vocales dans un bocal à spécimen : larynx rose (anneau de chair,
    deux cordes nacrées en V autour de la glotte sombre, trachée annelée) qui
    flotte dans du formol, bulles, couvercle de métal, étiquette."""
    s = Sample("nurse_vocal_cords", rot=(0, 0, 0))
    jar = s.part("jar", "glass")
    org = s.part("larynx")
    lid = s.part("lid")
    R, TOP, LEVEL = 6.2, 19, 16
    for z in range(0, TOP):
        r = R if z < TOP - 2 else (R - 0.8 if z == TOP - 2 else R - 1.4)
        for x in range(-7, 7):
            for y in range(-7, 7):
                if _disk(r, x, y):
                    c = (x, y, z)
                    col = FORMOL if z < LEVEL else GLASS_TINT
                    if z == LEVEL - 1:
                        col = mix(FORMOL, (0.95, 1.0, 0.85), 0.5)
                    jar.set(*c, "glass", color=col)
    # Couvercle vissé.
    for z in range(TOP, TOP + 3):
        rr = R - 0.6 if z < TOP + 2 else R - 1.6
        for x in range(-7, 7):
            for y in range(-7, 7):
                if _disk(rr, x, y):
                    c = (x, y, z)
                    col = P["steel"] if (z == TOP + 1 and (x + y) % 2) else vx.tone(P["steel"], 0.82)
                    if z == TOP + 2:
                        col = vx.tone(P["steel"], 1.08)
                    if vx.noise(c, 3) < 0.12:
                        col = P["rust"]
                    lid.set(*c, "metal", color=jit(col, c, 0.05))
    # Larynx et trachée : tube rose annelé (anneaux de cartilage clairs),
    # bout arraché sanglant en bas ; boîte du larynx en haut (bouclier
    # thyroïde avec l'encoche de la pomme d'Adam), épiglotte en languette
    # derrière ; par l'ouverture du haut, les deux cordes nacrées en V.
    RING = (0.97, 0.68, 0.68)
    for z in range(0, 9):
        cx = 0.6 * math.sin(z * 0.45)  # légère courbe
        for x in range(-4, 4):
            for y in range(-4, 4):
                d = math.hypot(x + 0.5 - cx, y + 0.5)
                if d <= 2.5:
                    c = (x, y, z)
                    if z <= 1:
                        col = BLOOD_WET if vx.noise(c, 3) < 0.4 else PINK_DARK
                    else:
                        col = RING if z % 2 == 0 else PINK
                        if z % 2 == 0 and vx.noise(c, 4) < 0.15:
                            col = PINK_LIGHT
                    org.set(*c, "wound", color=jit(col, c, 0.05, 5))
    # Larynx : boîte plus large, bouclier en V à l'avant.
    for z in range(9, 14):
        for x in range(-4, 4):
            for y in range(-4, 3):
                ex = 3.6 if z < 13 else 3.2
                if ((x + 0.5) / ex) ** 2 + ((y + 0.5) / 3.1) ** 2 > 1.0:
                    continue
                c = (x, y, z)
                front = y <= -2
                col = PINK if vx.noise(c, 6) < 0.7 else PINK_LIGHT
                if front:
                    col = RING  # bouclier thyroïde
                    # Proéminence : arête verticale au milieu.
                    if x in (-1, 0):
                        col = vx.tone(RING, 1.04)
                if z == 13:
                    # Ouverture : bourrelet rose, glotte sombre, cordes en V.
                    ix, iy = x + 0.5, y + 0.5
                    if abs(ix) <= 2.0 and -1.8 <= iy <= 2.0:
                        w = (iy + 1.8) / 3.8 * 1.6  # s'ouvre vers l'arrière
                        if abs(ix) < w * 0.5:
                            continue  # glotte (trou)
                        col = CORD if abs(ix) < w * 0.5 + 0.9 else PINK_LIGHT
                org.set(*c, "wound", color=jit(col, c, 0.04, 7))
    # Encoche en V de la pomme d'Adam (haut du bouclier).
    for x, z in ((-1, 13), (0, 13), (-1, 12), (0, 12)):
        for y in range(-4, -1):
            if z == 12 and y > -3:
                continue
            org.vox.pop((x, y, z), None)
    # Fond de la glotte (sombre) sous le trou.
    for x in range(-2, 2):
        for y in range(-2, 2):
            c = (x, y, 12)
            if c in org.vox and (x, y, 13) not in org.vox:
                org.set(*c, "wound", color=(0.30, 0.04, 0.08))
    # Épiglotte : languette rose dressée à l'arrière.
    for x in range(-2, 2):
        for z in (14, 15):
            if not (z == 15 and x in (-2, 1)):
                org.set(x, 2, z, "wound", color=jit(PINK_LIGHT, (x, 2, z), 0.05, 8))
    # Veinules violettes, filaments sanglants qui flottent sous le bout.
    for c in list(org.vox):
        v = org.vox[c]
        if 2 <= c[2] <= 12 and v.color[1] < 0.55 and vx.noise(c, 17) < 0.10:
            org.set(*c, "wound", color=(0.56, 0.30, 0.50))
    # Bulles qui remontent.
    for c in ((4, -3, 4), (-4, -3, 8), (3, -4, 11)):
        org.set(*c, "wound", color=(0.95, 1.0, 0.92))
    return s


def build_nurse_syringe():
    """Seringue cassée : piston blanc, ailettes, corps de verre gradué brisé
    en deux (bords déchiquetés), reste de liquide vert de l'infirmière qui
    coule, aiguille tordue."""
    s = Sample("nurse_syringe", rot=(0, -28, 0))
    glass = s.part("barrel", "glass")
    sol = s.part("syringe")

    def ring(x, mdl, mat, col, r=2.3, hollow=False):
        for y in range(-3, 3):
            for z in range(-3, 3):
                d = math.hypot(y + 0.5, z + 0.5)
                if d <= r and not (hollow and d < r - 1.0):
                    mdl.set(x, y, z, mat, color=col(x, y, z) if callable(col) else col)

    # Poussoir et tige en croix.
    for y in range(-3, 3):
        for z in range(-3, 3):
            if not (y in (-3, 2) and z in (-3, 2)):
                sol.set(0, y, z, "rubber", color=jit(PLUNGER, (0, y, z), 0.03))
                sol.set(-1, y, z, "rubber", color=vx.tone(PLUNGER, 0.85))
    for x in range(1, 4):
        for y, z in ((-1, -1), (0, -1), (-1, 0), (0, 0), (-2, -1), (1, 0), (-1, -2), (0, 1)):
            if (y, z) in ((-1, -1), (0, -1), (-1, 0), (0, 0)) or x % 2:
                sol.set(x, y, z, "rubber", color=jit(PLUNGER, (x, y, z), 0.04))
    # Ailettes.
    for y in range(-4, 4):
        for z in (-1, 0):
            sol.set(4, y, z, "rubber", color=vx.tone(PLUNGER, 0.92))
    # Corps de verre (arrière) : x 5..11, cassé en biais vers x 10..12.
    def broken_end(x, y, z, lo):
        cut = lo + int(vx.noise((y, z, 0), 21) * 2.5) + (1 if y + z > 0 else 0)
        return x > cut
    for x in range(5, 13):
        for y in range(-3, 3):
            for z in range(-3, 3):
                if math.hypot(y + 0.5, z + 0.5) <= 2.4 and not broken_end(x, y, z, 10):
                    col = (0.95, 0.99, 1.0)
                    if z == 2 and x % 2 == 0:
                        col = (0.35, 0.40, 0.42)  # graduations
                    glass.set(x, y, z, "glass", color=col)
    # Joint de caoutchouc et liquide dans la partie arrière.
    ring(5, sol, "rubber", (0.08, 0.08, 0.08), r=1.6)
    for x in range(6, 10):
        for y in range(-2, 2):
            for z in range(-2, 1):
                if math.hypot(y + 0.5, z + 0.5) <= 1.6:
                    sol.set(x, y, z, "glow", color=jit(OOZE, (x, y, z), 0.08, 2))
    # Partie avant, détachée par la cassure (écart de 2 à 3 cubes, plus
    # bas et un peu de travers) : bout du corps, reste de liquide, embout,
    # aiguille tordue.
    ox, dz, dy = 3, -2, 1
    for x in range(13, 19):
        for y in range(-3, 3):
            for z in range(-3, 3):
                if math.hypot(y + 0.5, z + 0.5) <= 2.4 and x >= 13 + int(vx.noise((y, z, 1), 22) * 2.5):
                    col = (0.95, 0.99, 1.0)
                    if z == 2 and x % 2 == 0:
                        col = (0.35, 0.40, 0.42)
                    glass.set(x + ox, y + dy, z + dz, "glass", color=col)
    for x in (16, 17):
        for y in range(-2, 2):
            for z in range(-2, 0):
                if math.hypot(y + 0.5, z + 0.5) <= 1.4:
                    sol.set(x + ox, y + dy, z + dz, "glow", color=OOZE)
    for y in (-1, 0):
        for z in (-1, 0):
            sol.set(19 + ox, y + dy, z + dz, "rubber", color=PLUNGER)
    sol.set(20 + ox, -1 + dy, -1 + dz, "metal", color=STEEL)
    for x, z in ((21, -1), (22, -1), (23, -1), (24, -2), (25, -3)):
        sol.set(x + ox, -1 + dy, z + dz, "metal", color=NEEDLE)
    sol.set(25 + ox, -1 + dy, -4 + dz, "metal", color=BLOOD_WET)
    sol.set(21 + ox, -1 + dy, -1 + dz, "metal", color=BLOOD)
    # Éclats de verre tombés et liquide qui coule de la cassure.
    for c in ((13, -2, -5), (14, 1, -6), (12, 2, -7)):
        glass.set(*c, "glass", color=(0.95, 0.99, 1.0))
    for c in ((11, -1, -3), (11, -1, -4), (11, -1, -6), (12, -1, -7), (11, -1, -7), (10, -1, -7),
              (13, 0, -7), (12, 0, -7)):
        sol.set(*c, "glow", color=OOZE)
    return s


def build_nurse_badge():
    """Badge nominatif : carte blanche, bande bleue avec croix, photo de
    l'infirmière (avant), lignes de nom, pince d'acier, sang au coin."""
    s = Sample("nurse_badge", rot=(0, 0, 0))
    m = s.part("badge")
    W = {".": None, "W": BADGE, "B": BADGE_BAND, "X": (0.98, 0.98, 0.98), "R": (0.78, 0.12, 0.12),
         "p": (0.62, 0.72, 0.78), "h": (0.20, 0.14, 0.11), "s": (0.90, 0.72, 0.58), "e": (0.10, 0.08, 0.08),
         "m": (0.72, 0.30, 0.30), "d": (0.92, 0.92, 0.90), "c": BADGE_BAND, "K": INK, "k": (0.45, 0.47, 0.52),
         "b": BLOOD, "o": BLOOD_DRY, "n": (0.80, 0.76, 0.70), "t": (0.06, 0.06, 0.07)}
    art = [  # de haut en bas, 13 colonnes
        ".WWWWttWWWWW.",
        "WWWWWWWWWWWWW",
        "BBBBBBBBBBBBB",
        "BBXBBXXBXXXBB",
        "BXXXBBBBBBBBB",
        "BBXBBXXXBXXBB",
        "BBBBBBBBBBBBB",
        "WWWWWWWWWWWWW",
        "WphhhpWKKKKKW",
        "WhhhhhWKKKKWW",
        "WhssshWWWWWWW",
        "WsesesWkkkkWW",
        "WsssssWkkkWWW",
        "WpsmspWWWWWWW",
        "WdcdcdWkkkkWo",
        "WdddddWWWWWbb",
        "WWWWWWWWWWbbo",
        ".WWWWWWWWWWb.",
    ]
    Hh = len(art)
    for r, row in enumerate(art):
        z = Hh - 1 - r
        for i, ch in enumerate(row):
            col = W[ch]
            if col is None:
                continue
            c = (i, 0, z)
            back = BADGE if ch not in ("b", "o") else col
            m.set(*c, "fabric", color=jit(back, c, 0.02))
            m.face_color[(i, 0, z, "-y")] = jit(col, c, 0.025, 2)
            # Épaisseur : bord de plastique (2e couche en retrait).
            m.set(i, 1, z, "fabric", color=jit((0.84, 0.84, 0.82), c, 0.02, 3))
    # Pince : anneau et mâchoire d'acier au-dessus.
    top = Hh
    for x in range(4, 9):
        m.set(x, 0, top + 2, "metal", color=jit(P["steel"], (x, 0, top + 2), 0.06))
    for z in (top, top + 1):
        m.set(4, 0, z, "metal", color=P["steel"])
        m.set(8, 0, z, "metal", color=P["steel"])
    for x in range(5, 8):
        for z in range(top - 3, top + 1):
            m.set(x, 1, z, "metal", color=vx.tone(P["steel"], 0.85))
        m.set(x, 2, top - 3, "metal", color=vx.tone(P["steel"], 0.7))
    return s


# ---------------------------------------------------------------------------
# Chirurgien
# ---------------------------------------------------------------------------

def build_surgeon_scalpel():
    """Scalpel : manche d'acier strié à insert sarcelle (couleurs du
    Chirurgien), lame n° 10 au ventre courbe, fil brillant, sang au bout."""
    s = Sample("surgeon_scalpel", rot=(0, -32, 0))
    m = s.part("scalpel")
    # Manche : x 0..10, 3 cubes de haut, 2 d'épaisseur ; bout arrondi.
    for x in range(0, 11):
        for z in range(0, 3):
            if x == 0 and z == 2:
                continue
            for y in range(0, 2):
                c = (x, y, z)
                col = jit(STEEL_DARK if z == 0 else mix(STEEL_DARK, STEEL, 0.55), c, 0.05)
                if 2 <= x <= 7 and z == 1 and y == 0:
                    col = TEAL if x % 2 == 0 else vx.tone(TEAL, 1.5)
                if 2 <= x <= 7 and z == 2 and x % 2:
                    col = vx.tone(STEEL_DARK, 0.75)  # stries
                m.set(*c, "metal", color=col)
    # Monture de lame.
    for x in (11,):
        for z in (1, 2):
            m.set(x, 0, z, "metal", color=STEEL_DARK)
    # Lame : dos droit en haut (z = 3), ventre courbe, pointe en haut.
    prof = {12: (0, 2), 13: (-1, 2), 14: (-1, 2), 15: (-1, 2), 16: (0, 2), 17: (0, 2),
            18: (1, 2), 19: (2, 2)}
    for x, (lo, hi) in prof.items():
        for z in range(lo, hi + 1):
            c = (x, 0, z)
            col = jit(STEEL, c, 0.04)
            if z == lo:
                col = EDGE
            if z == hi:
                col = vx.tone(STEEL, 0.9)
            m.set(*c, "metal", color=col)
    # Reflet clair sur le plat de la lame.
    for x in (13, 14):
        m.face_color[(x, 0, 1, "-y")] = (0.90, 0.93, 0.96)
    # Sang : pointe et fil, coulure.
    for c in ((19, 0, 2), (18, 0, 1), (18, 0, 2), (17, 0, 0), (16, 0, 0)):
        m.set(*c, "wound", color=BLOOD_WET if vx.noise(c, 3) < 0.6 else BLOOD)
    m.set(17, 0, 1, "wound", color=BLOOD)
    m.set(16, 0, -1, "wound", color=BLOOD_WET)
    m.set(10, 1, 0, "wound", color=BLOOD_DRY)
    return s


def build_surgeon_heart():
    """Cœur mutant du Chirurgien : cœur anatomique cramoisi (aorte en crosse,
    artère pulmonaire, veine cave violette), excroissances, veines
    LUMINEUSES rose vif (faces « glow »)."""
    s = Sample("surgeon_heart", rot=(0, 0, 0))
    m = s.part("heart")
    for z in range(0, 14):
        for x in range(-8, 8):
            for y in range(-6, 6):
                zc = z + 0.5
                # Ellipsoïde dont la pointe (bas) part vers -X.
                sx = (6.5 - zc) * 0.28 if zc < 6.5 else 0.0
                rx = 5.6 * math.sqrt(max(0.0, 1 - ((zc - 7.0) / 7.2) ** 2)) + 0.3
                ry = rx * 0.82
                px, py = x + 0.5 + sx, y + 0.5
                if (px / rx) ** 2 + (py / ry) ** 2 <= 1.0:
                    c = (x, y, z)
                    col = HEART if vx.noise(c, 1) < 0.84 else mix(HEART, HEART_DARK, 0.6)
                    m.set(*c, "heart", color=jit(col, c, 0.05, 2))
    # Oreillette droite (bosse à +X, en haut).
    for x in range(2, 8):
        for y in range(-4, 3):
            for z in range(8, 13):
                if ((x - 4.5) / 2.8) ** 2 + ((y + 0.5) / 3.0) ** 2 + ((z - 10.5) / 2.6) ** 2 <= 1:
                    m.set(x, y, z, "heart", color=jit(HEART_DARK, (x, y, z), 0.08, 3))
    # Graisse jaunâtre au sillon (bande en travers).
    for c in list(m.vox):
        x, y, z = c
        if abs(z - (9 - 0.35 * x)) < 0.6 and surface(m, c) and vx.noise(c, 4) < 0.7:
            m.set(*c, "skin", color=jit(FAT, c, 0.06, 5))

    def tube(path, r, col, mat="heart"):
        for (cx, cy, cz) in path:
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                for y in range(int(cy - r - 1), int(cy + r + 2)):
                    for z in range(int(cz - r - 1), int(cz + r + 2)):
                        if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 + (z + 0.5 - cz) ** 2 <= r * r:
                            m.set(x, y, z, mat, color=jit(col, (x, y, z), 0.06, 6))

    # Aorte : monte puis crosse vers -X, trois branches sur le dessus.
    AC, AR, TR = (-1.8, 15.5), 2.7, 1.35
    aorta = [(0.9, 0.5, 11 + k * 0.5) for k in range(10)]
    aorta += [(AC[0] + AR * math.cos(math.radians(a)), 0.5, AC[1] + AR * math.sin(math.radians(a)))
              for a in range(0, 181, 8)]
    aorta += [(AC[0] - AR, 0.5, AC[1] - k * 0.5) for k in range(7)]
    tube(aorta, TR, mix(HEART, PINK, 0.35))
    for bx in (-3.6, -1.8, 0.0):
        top = AC[1] + math.sqrt(max(0.0, AR * AR - (bx - AC[0]) ** 2)) + TR - 0.5
        for k in range(2):
            z = int(top) + k
            m.set(int(math.floor(bx)), 0, z, "heart", color=mix(HEART, PINK, 0.45 + 0.1 * k))
    # Artère pulmonaire (devant, vers la gauche).
    tube([(-0.5 - k * 0.3, -2.6, 11.0 + k * 0.5) for k in range(10)], 1.3, mix(HEART, VEIN_BLUE, 0.25))
    # Veine cave (à droite, violette).
    tube([(4.5, 0.5, 12 + k * 0.5) for k in range(9)], 1.3, VEIN_BLUE)
    # Excroissances mutantes (pustules).
    for (cx, cy, cz, r) in ((-4.0, -3.0, 5.0, 1.6), (3.5, -3.5, 4.5, 1.3), (-1.0, -4.5, 9.0, 1.1)):
        for x in range(int(cx - 3), int(cx + 3)):
            for y in range(int(cy - 3), int(cy + 3)):
                for z in range(int(cz - 3), int(cz + 3)):
                    if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 + (z + 0.5 - cz) ** 2 <= r * r:
                        m.set(x, y, z, "heart", color=jit(mix(HEART_DARK, VEIN_BLUE, 0.4), (x, y, z), 0.08))
        m.set(int(cx), int(cy - r), int(cz), "glow", color=HEART_GLOW)
    # Veines lumineuses : marches aléatoires vers le bas sur la surface.
    surf = {c for c in m.vox if surface(m, c) and m.vox[c].mat in ("heart", "skin")}

    def walk(start, n, mat, col, seed):
        c = start
        for k in range(n):
            if c in surf:
                m.set(*c, mat, color=col)
            best = None
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, -1), (0, 1)):
                nc = (c[0] + dx, c[1] + dy, c[2] - 1)
                if nc in surf:
                    sc = vx.noise(nc, seed + k)
                    if best is None or sc > best[0]:
                        best = (sc, nc)
            if best is None:
                # Glisse latéralement à la même hauteur.
                for dx, dy in ((1, 0), (-1, 0), (0, -1), (0, 1)):
                    nc = (c[0] + dx, c[1] + dy, c[2])
                    if nc in surf:
                        best = (0, nc)
                        break
            if best is None:
                return
            c = best[1]

    def front_start(x, z):
        ys = [y for (cx, y, cz) in surf if cx == x and cz == z]
        return (x, min(ys), z) if ys else None

    def left_start(y, z):
        xs = [x for (x, cy, cz) in surf if cy == y and cz == z]
        return (min(xs), y, z) if xs else None

    starts = [front_start(-3, 11), front_start(1, 12), front_start(3, 9), left_start(-2, 10), left_start(1, 8)]
    for i, st in enumerate(starts):
        if st:
            walk(st, 13, "glow", HEART_GLOW, 30 + i * 7)
    for i, st in enumerate((front_start(-1, 8), left_start(-1, 6))):
        if st:
            walk(st, 8, "heart", VEIN_BLUE, 80 + i * 5)
    return s


SAMPLES = [
    build_dog_fang, build_dog_fur, build_dog_collar,
    build_brancard_strap, build_brancard_bracelet,
    build_nurse_vocal_cords, build_nurse_syringe, build_nurse_badge,
    build_surgeon_scalpel, build_surgeon_heart,
]


def build_all():
    return [f() for f in SAMPLES]
