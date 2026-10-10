# Zombie « patient » CUBIQUE (GAME_CONCEPT.md § 4.19 : personnages et mobs en
# cubes de 2,5 cm, 72 cubes pour 1,80 m), reproduit au plus près de la planche
# docs/reference/zombie_patient/turnaround.png (dossier ignoré par git ; un
# pixel de la planche ≈ 2 cm, une rangée de 2,5 cm ≈ 9,5 pixels).
#
#   sh tools/blender.sh tools/blender/zombies/zombie_voxel.py [--glb FICHIER] [--sheet FICHIER.png] [--cache]
#
# Construit avec tools/blender/voxel/voxel_lib.py :
#   - FORMES : chaque partie (tête, mâchoire, torse, jupe, manches, bras et
#     mains, jambes et pieds) est un pavé de cellules SCULPTÉ par les vues de la
#     planche : une cellule reste si sa case projetée est « pleine » (ou de la
#     bonne matière : peau, tissu) dans la vue de face (ou de dos) ET dans la vue
#     de profil. Le dos voûté, la tête en avant, les genoux, le bas déchiré, les
#     manches évasées et les marches du col sortent ainsi de la planche, en
#     escaliers de cubes (jamais de cisaillement) ;
#   - jupe CREUSE (parois d'un cube) autour des jambes ; bas déchiré mesuré sur
#     la vue qui montre chaque paroi ;
#   - détails : yeux 3 × 2 émissifs au fond d'orbites, arcades en saillie, nez
#     creusé, bouche ouverte et dents d'un cube, oreilles, encolure en V en
#     escalier, doigts séparés et recourbés, orteils marqués ;
#   - couleurs PRÉLEVÉES sur la planche, une par face de cube (plis de la
#     blouse, taches de sang, bleus compris) ; faces cachées comblées ; ombrage
#     peint ; palette réduite ;
#   - ossature du jeu (RigBuilder.BONES), os droits, repos membres pendants,
#     pondération rigide (chaque cube à 100 % sur un os).
# CACHE : cellules et couleurs de faces dans zombie_voxel_cells.json (suivi par
# git, à côté du script) ; sans la planche (ou avec --cache), le modèle est
# reconstruit depuis ce fichier, à l'identique.
#
# Repère : Z en haut, face avant vers -Y, gauche du personnage vers +X. Dans
# ce script, « f » est la profondeur vers l'AVANT : la cellule (x, f, z) est
# la cellule (x, y = -f - 1, z) du modèle.
import bpy, math, os, sys
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "voxel"))
import voxel_lib as vx  # noqa: E402

CUBE = vx.CUBE_CHAR
CACHE = os.path.join(HERE, "zombie_voxel_cells.json")
REF_REL = os.path.join("docs", "reference", "zombie_patient", "turnaround.png")


def _ref_path():
    p = os.path.join(ROOT, REF_REL)
    if os.path.exists(p):
        return p
    # Worktree .claude/worktrees/<nom> : la planche est dans le dépôt principal.
    main = os.path.abspath(os.path.join(ROOT, "..", "..", ".."))
    p = os.path.join(main, REF_REL)
    return p if os.path.exists(p) else None


# Retouches (sRGB).
SKIN = (0.42, 0.50, 0.38)
CLOTH = (0.84, 0.82, 0.68)
EYE = (1.0, 0.88, 0.30)
TOOTH = (0.88, 0.82, 0.58)
MOUTH = (0.16, 0.04, 0.04)
NOSTRIL = (0.10, 0.12, 0.09)


def cell(x, f, z):
    return (x, -f - 1, z)


# ---------------------------------------------------------------------------
# Planche : vues de la rangée du haut, masques et classes de pixels.
# ---------------------------------------------------------------------------

# (nom, colonnes de la silhouette, direction de la face vue, axe horizontal
# de l'écran) ; rangée : sommet du crâne (≈ 84) -> pieds (770), 72 cubes.
VIEWS = [
    ("front", (166, 537), "-y", (1, 0, 0)),
    ("back", (828, 1216), "+y", (-1, 0, 0)),
    ("right", (1477, 1661), "-x", (0, -1, 0)),   # 3e colonne : côté droit, avant à droite
    ("left", (1822, 2006), "+x", (0, 1, 0)),     # 4e colonne : côté gauche, avant à gauche
]
ROW = (0, 800)
PAD = 120


def _dilate(m, n):
    for _ in range(n):
        o = m.copy()
        o[1:] |= m[:-1]
        o[:-1] |= m[1:]
        o[:, 1:] |= m[:, :-1]
        o[:, :-1] |= m[:, 1:]
        m = o
    return m


class Ref:
    def __init__(self, path):
        im = bpy.data.images.load(path)
        W, H = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3].copy()
        bpy.data.images.remove(im)
        self.a = a
        mx, mn = a.max(2), a.min(2)
        sat = (mx - mn) / np.maximum(mx, 1e-4)
        lum = a.mean(2)
        r, g = a[..., 0], a[..., 1]
        self.mask = (sat > 0.08) | (lum < 0.3) | (lum > 0.68)
        ink = (lum < 0.15) & (sat < 0.45)
        bg = ~self.mask
        # Plein : silhouette sans le trait noir EXTÉRIEUR (encrage touchant le
        # fond) ; les traits intérieurs restent pleins.
        self.solid = self.mask & ~(ink & _dilate(bg, 6))
        self.green = self.mask & (g > r + 0.015) & (lum >= 0.12)
        self.red = self.mask & (r > g + 0.08) & (r > 0.18)
        self.cream = self.mask & (lum > 0.5) & ~self.green & ~self.red
        # Tissu (bas déchirés) : ni vert ni sombre ; peau : tout sauf crème.
        self.cloth = self.solid & ~self.green & ((lum > 0.35) | self.red)
        self.skinish = self.solid & ~self.cream
        # Peau (bras, jambes) : vert, sang, ombres et traits sombres.
        self.skin = self.solid & (self.green | self.red | ((lum < 0.25) & ~self.cream))
        # Pixels à ne jamais prélever : encrage, fond (et 2 pixels de bord).
        self.bad = _dilate(ink | bg | ((sat < 0.05) & (np.abs(lum - 0.565) < 0.05)), 2)

    def views(self):
        out = {}
        for name, (x0, x1), d, right in VIEWS:
            c0, c1 = x0 - PAD, x1 + PAD
            sl = (slice(ROW[0], ROW[1]), slice(c0, c1))
            rows = np.where(self.mask[sl][:, PAD // 2:-PAD // 2].any(1))[0]
            top, bot = rows[0], rows[-1] + 1
            s = (bot - top) / 72.0
            v = vx.View(name, self.a[sl], d, right, s, (x1 - x0) / 2.0 + PAD, float(bot), ok=~self.bad[sl])
            for k in ("solid", "cloth", "skinish", "skin", "cream", "green", "red", "mask"):
                setattr(v, k, getattr(self, k)[sl])
            v.crop = (c0, c1)
            v.cx = (x0 + x1) / 2.0
            out[name] = v
        return out


class Probe:
    """Tests de cellules dans les vues : face (x, z), dos (x, z), profils
    (f, z) ; `kind` = masque (« solid », « cloth », « skinish »...)."""

    def __init__(self, views):
        self.v = views

    def front(self, kind, x, z):
        return self.v["front"].frac(getattr(self.v["front"], kind), (x, 0, z))

    def back(self, kind, x, z):
        return self.v["back"].frac(getattr(self.v["back"], kind), (x, 0, z))

    def side(self, kind, f, z, which):
        """`which` : « right », « left », « union » ou « both »."""
        if which in ("right", "left"):
            v = self.v[which]
            return v.frac(getattr(v, kind), (0, -f - 1, z))
        a = self.side(kind, f, z, "right")
        b = self.side(kind, f, z, "left")
        return max(a, b) if which == "union" else min(a, b)


# ---------------------------------------------------------------------------
# Formes.
# ---------------------------------------------------------------------------

def build_model(views):
    P = Probe(views)
    m = vx.Model(CUBE)
    T = 0.5

    def put(x, f, z, mat, bone, part, color):
        m.set(*cell(x, f, z), mat, bone, part, color)

    def has(x, f, z):
        return cell(x, f, z) in m.vox

    # --- torse (spine sous z 42, chest au-dessus) : silhouette de DOS (la
    # tête et la mâchoire ne la cachent pas) et des deux profils ---
    torso = set()
    neck = set()
    for z in range(30, 56):
        for x in range(-10, 10):
            if P.back("solid", x, z) < T:
                continue
            for f in range(-11, 6):
                if P.side("solid", f, z, "union") < T:
                    continue
                # Haut du col : du tissu seulement là où les profils en
                # montrent ; ailleurs, le cou (peau) dans l'encolure.
                if z >= 48 and -6 <= x < 6 and f >= -4 and P.side("cloth", f, z, "union") < T:
                    neck.add((x, f, z))
                else:
                    torso.add((x, f, z))
    # --- jupe creuse (hips) : silhouette pleine, puis parois d'un cube ---
    # Profondeur de la jupe : la même à toutes les hauteurs (prisme : pas de
    # rebord parasite), celle que les profils montrent sur la moitié au moins
    # des rangées de la jupe.
    fs = [f for f in range(-12, 6)
          if sum(P.side("solid", f, z, "union") >= T for z in range(14, 30)) >= 8]
    R = set()
    for z in range(10, 30):
        for x in range(-11, 11):
            if P.front("solid", x, z) < T:
                continue
            for f in fs:
                R.add((x, f, z))
    walls = {}
    for (x, f, z) in R:
        out_f = (x, f + 1, z) not in R
        out_b = (x, f - 1, z) not in R
        out_l = (x + 1, f, z) not in R
        out_r = (x - 1, f, z) not in R
        if out_f or out_b or out_l or out_r:
            walls.setdefault((x, f), []).append((z, out_f, out_b, out_l, out_r))
    skirt = set()
    for (x, f), col in walls.items():
        # Bas déchiré : chaque colonne de paroi descend tant que la vue qui la
        # montre y voit du tissu (aucun trou au-dessus du bas).
        for z, out_f, out_b, out_l, out_r in sorted(col, reverse=True):
            # Profils : les mains cachent la jupe au-dessus de z 15.
            side_z = z < 15
            if z < 20:
                ok = (out_f and P.front("cloth", x, z) >= T) or (out_b and P.back("cloth", x, z) >= T) or \
                     (out_l and (not side_z or P.side("cloth", f, z, "left") >= T)) or \
                     (out_r and (not side_z or P.side("cloth", f, z, "right") >= T))
                if not ok:
                    break
            skirt.add((x, f, z))
    for (x, f, z) in skirt:
        put(x, f, z, "cloth", "hips", "skirt", CLOTH)
    for (x, f, z) in torso:
        put(x, f, z, "cloth", "spine" if z < 42 else "chest", "torso", CLOTH)
    for (x, f, z) in neck:
        put(x, f, z, "skin", "chest", "neck", SKIN)

    # --- manches (os arm) : tissu de face ET de profil ; bras et mains (os
    # arm au-dessus du coude z 40, forearm dessous) : peau ---
    for s, side in ((1, "l"), (-1, "r")):
        sv = "left" if s > 0 else "right"
        xs = range(10, 20) if s > 0 else range(-20, -10)
        for z in range(37, 57):
            for x in xs:
                if P.front("cloth", x, z) < T or P.back("solid", x, z) < T:
                    continue
                for f in range(-10, 5):
                    # Profil : tissu près du bas (déchirures), plein au-dessus
                    # (les traits de la planche ne creusent pas la manche).
                    if P.side("cloth" if z < 44 else "solid", f, z, sv) >= T and not has(x, f, z):
                        put(x, f, z, "cloth", "arm_" + side, "sleeve_" + side, CLOTH)
        xs = range(11, 21) if s > 0 else range(-21, -11)
        for z in range(15, 41):
            for x in xs:
                if P.front("skin", x, z) < T:
                    continue
                for f in range(-11, 5):
                    if P.side("skin", f, z, sv) >= T and not has(x, f, z):
                        part = ("hand_" if z < 25 else "arm_") + side
                        put(x, f, z, "skin", "arm_" + side if z >= 40 else "forearm_" + side, part, SKIN)
        # Haut du bras caché sous la manche (relie la manche à l'avant-bras).
        x0, x1 = (13, 17) if s > 0 else (-17, -13)
        for z in range(38, 54):
            for x in range(x0, x1):
                for f in range(-5, -1):
                    if not has(x, f, z):
                        put(x, f, z, "skin", "arm_" + side if z >= 40 else "forearm_" + side, "arm_" + side, SKIN)
        # Doigts : trois doigts séparés (fentes de la planche), bouts recourbés
        # vers le corps.
        hand = [(c[0], -c[1] - 1, c[2]) for c, v in m.vox.items() if v.part == "hand_" + side]
        if hand:
            zmin = min(z for _, _, z in hand)
            xs_h = sorted({x for x, _, _ in hand})
            mid = (xs_h[0] + xs_h[-1]) / 2.0
            for (x, f, z) in hand:
                if z < zmin + 4 and f in (-5, -3, -1):
                    m.vox.pop(cell(x, f, z), None)
                elif z < zmin + 2 and (x > mid if s > 0 else x < mid):
                    m.vox.pop(cell(x, f, z), None)

    # --- jambes et pieds (thigh au-dessus du genou z 14, shin dessous) ---
    for s, side in ((1, "l"), (-1, "r")):
        sv = "left" if s > 0 else "right"
        xs = range(2, 11) if s > 0 else range(-11, -2)
        leg = []
        for z in range(0, 16):
            for x in xs:
                if P.front("skin", x, z) < T:
                    continue
                for f in range(-11, 7):
                    if P.side("skin", f, z, sv) >= T and not has(x, f, z):
                        leg.append((x, f, z))
        # Les jambes restent DANS la jupe (parois intactes).
        top = {}
        for (x, f, z) in leg:
            put(x, f, z, "skin", "shin_" + side if z < 14 else "thigh_" + side, "leg_" + side, SKIN)
            top[(x, f)] = max(top.get((x, f), -1), z)
        # Haut caché : la section du haut de la jambe monte jusqu'au genou,
        # puis la cuisse jusqu'au bassin (z 30).
        zt = max(top.values())
        for (x, f), z0 in top.items():
            if z0 < zt - 1:
                continue
            for z in range(z0 + 1, 14):
                if not has(x, f, z):
                    put(x, f, z, "skin", "shin_" + side, "leg_" + side, SKIN)
        x0, x1 = (3, 9) if s > 0 else (-9, -3)
        for z in range(14, 30):
            for x in range(x0, x1):
                for f in range(-6, -1):
                    if not has(x, f, z):
                        put(x, f, z, "skin", "thigh_" + side, "leg_" + side, SKIN)
        # Orteils marqués : rainures d'un cube sur le dessus de l'avant du pied.
        foot = [(x, f) for (x, f, z) in leg if z == 1]
        if foot:
            fmax = max(f for _, f in foot)
            xs_f = sorted({x for x, f in foot if f == fmax})
            for x in xs_f:
                if (x - xs_f[0]) % 2 == 1:
                    for f in (fmax - 1, fmax):
                        m.vox.pop(cell(x, f, 1), None)

    # --- mâchoire (os jaw) puis tête (os head) ---
    for z in range(50, 56):
        for x in range(-7, 7):
            if P.front("solid", x, z) < T:
                continue
            for f in range(3, 9):
                if P.side("solid", f, z, "union") >= T:
                    put(x, f, z, "skin", "jaw", "jaw", SKIN)
    for z in range(56, 73):
        for x in range(-9, 9):
            if P.front("solid", x, z) < T:
                continue
            ear = x in (-9, 8)
            for f in range(-9, 11):
                if ear and not -1 <= f < 2:
                    continue
                if P.side("solid", f, z, "both" if not ear else "union") >= T:
                    put(x, f, z, "skin", "head", "head", SKIN)
    # Fentes d'un cube laissées par la sculpture (bruit de la planche).
    m.fill_gaps(("torso", "neck", "sleeve_l", "sleeve_r", "head", "jaw"))

    def front_f(x, z, part):
        fs = [-c[1] - 1 for c, v in m.vox.items() if c[0] == x and c[2] == z and v.part == part]
        return max(fs) if fs else None

    # Arcades : une rangée en saillie au-dessus des yeux.
    for z in (62, 63):
        for x in list(range(-6, -1)) + list(range(1, 6)):
            ff = front_f(x, z, "head")
            if ff is not None:
                put(x, ff + 1, z, "skin", "head", "head", SKIN)
    holes = {}
    # Orbites : yeux 3 × 2 au fond (un cube en retrait).
    eyes = []
    for z in (60, 61):
        for x in list(range(-5, -2)) + list(range(2, 5)):
            ff = front_f(x, z, "head")
            if ff is not None:
                m.vox.pop(cell(x, ff, z), None)
                holes[cell(x, ff, z)] = None
                eyes.append((cell(x, ff - 1, z), "-y"))
    # Nez creusé.
    for z in (57, 58):
        for x in (-1, 0):
            ff = front_f(x, z, "head")
            if ff is not None:
                m.vox.pop(cell(x, ff, z), None)
                holes[cell(x, ff, z)] = (NOSTRIL, None)
    # Bouche ouverte (deux cubes de profondeur) et dents d'un cube.
    for z in range(52, 56):
        for x in range(-4, 4):
            ff = front_f(x, z, "jaw")
            if ff is None:
                continue
            for k in (0, 1):
                m.vox.pop(cell(x, ff - k, z), None)
                holes[cell(x, ff - k, z)] = (MOUTH, "wound")
            tooth = (z == 55 and x in (-3, -1, 0, 2)) or (z == 52 and x in (-2, 1))
            if tooth:
                put(x, ff - 1, z, "bone", "jaw", "teeth", TOOTH)
                holes.pop(cell(x, ff - 1, z), None)
    # Encolure en V en escalier : là où la planche montre la peau (cou, sang)
    # devant le torse, la couche de tissu avant disparaît ; le cube derrière
    # devient la peau du cou.
    for z in range(44, 56):
        for x in range(-8, 8):
            if P.front("cream", x, z) >= 0.35 or front_f(x, z, "jaw") is not None:
                continue
            ff = front_f(x, z, "torso")
            if ff is None or ff < 1:
                continue
            m.vox.pop(cell(x, ff, z), None)
            b = m.vox.get(cell(x, ff - 1, z))
            if b is not None and b.part == "torso":
                m.vox[cell(x, ff - 1, z)] = vx.Voxel("skin", b.bone, "neck", SKIN)
    return m, holes, eyes


# ---------------------------------------------------------------------------
# Couleurs.
# ---------------------------------------------------------------------------

CLOTH_PARTS = ("skirt", "torso", "sleeve_l", "sleeve_r")


def paint(m, views, holes, eyes):
    """Prélèvement sur la planche, retouches, comblement, ombrage, palette."""
    def accept(view, c, d, px):
        r, g = px[:, 0], px[:, 1]
        lum = px.mean(1)
        part = m.vox[c].part
        if part == "teeth":
            return np.zeros(len(px), bool)
        red = (r > g + 0.08) & (r > 0.18)
        if part in CLOTH_PARTS:
            # Blouse : crème, plis gris, sang ; jamais la peau verte voisine
            # ni le gris sombre de l'encrage.
            return ~((g > r + 0.015) & (lum < 0.55)) & ((lum > 0.3) | red)
        # Peau : ni crème ni gris clair ni noir d'encrage.
        mx, mn = px.max(1), px.min(1)
        sat = (mx - mn) / np.maximum(mx, 1e-4)
        return ~((lum > 0.55) & (r >= g - 0.02)) & ~((lum < 0.18) & (sat < 0.4))

    painted = vx.paint_from_views(m, list(views.values()), accept)
    # Cases prises sur un trait d'encrage (bord de pièce) : recomblées par
    # leurs voisines (le contour noir est rendu à part).
    for c, d in list(painted):
        r, g, b = m.face_color[(c[0], c[1], c[2], d)]
        lum = (r + g + b) / 3.0
        dark = lum < (0.32 if m.vox[c].part in CLOTH_PARTS else 0.12)
        if dark and not (r > g + 0.08 and r > 0.18):
            painted.discard((c, d))
            del m.face_color[(c[0], c[1], c[2], d)]
    for key in eyes:
        c, d = key
        if c in m.vox:
            m.face_color[(c[0], c[1], c[2], d)] = EYE
            m.face_mat[(c[0], c[1], c[2], d)] = "eye"
            painted.add((c, d))
    for (c, d) in m.exposed():
        v = m.vox[c]
        key = (c[0], c[1], c[2], d)
        if v.part == "teeth":
            m.face_color[key] = TOOTH
            painted.add((c, d))
            continue
        n = vx.DIRS[d]
        nb = (c[0] + n[0], c[1] + n[1], c[2] + n[2])
        if nb in holes and nb not in m.vox and holes[nb] is not None:
            col, mat = holes[nb]
            m.face_color[key] = col
            if mat:
                m.face_mat[key] = mat
            painted.add((c, d))
    vx.fill_unpainted(m, painted, interior=0.6, interior_parts=("skirt",))
    # Matière selon la couleur : sang (wound), peau de l'encolure.
    for c, d in m.exposed():
        mat = m.mat_of(c, d)
        if mat in ("eye", "bone"):
            continue
        r, g, b = m.color_of(c, d)
        if r > g + 0.1 and r > 0.2:
            m.face_mat[(c[0], c[1], c[2], d)] = "wound"
        elif mat == "cloth" and g > r + 0.015:
            m.face_mat[(c[0], c[1], c[2], d)] = "skin"
    vx.shade(m, {"+z": 1.05, "-z": 0.62, "+x": 0.88, "-x": 0.88, "-y": 1.0, "+y": 1.0}, skip_mats=("eye",))
    vx.quantize(m, {"skin": 40, "cloth": 32, "wound": 12})


# ---------------------------------------------------------------------------
# Ossature (RigBuilder.BONES), en cubes de 2,5 cm ; os droits.
# ---------------------------------------------------------------------------

BONES = [
    ("hips", None, (0, 3, 28), (0, 3, 30)),
    ("spine", "hips", (0, 3, 30), (0, 3, 42)),
    ("chest", "spine", (0, 2, 42), (0, 2, 55)),
    ("neck", "chest", (0, 1, 55), (0, 1, 56)),
    ("head", "neck", (0, 0, 56), (0, 0, 72)),
    ("arm_l", "chest", (15, 3, 53), (15, 3, 40)),
    ("forearm_l", "arm_l", (15, 3, 40), (15, 3, 17)),
    ("arm_r", "chest", (-15, 3, 53), (-15, 3, 40)),
    ("forearm_r", "arm_r", (-15, 3, 40), (-15, 3, 17)),
    ("thigh_l", "hips", (6, 3.5, 30), (6, 3.5, 14)),
    ("shin_l", "thigh_l", (6, 3.5, 14), (6, 3.5, 0)),
    ("thigh_r", "hips", (-6, 3.5, 30), (-6, 3.5, 14)),
    ("shin_r", "thigh_r", (-6, 3.5, 14), (-6, 3.5, 0)),
    # Mâchoire : pivot en haut, à l'arrière du menton ; ouverture vers le bas.
    ("jaw", "head", (0, -4, 56), (0, -9, 56)),
]


# Bas de la jupe lié aux CUISSES (moitié gauche -> thigh_l, droite -> thigh_r)
# sous cette rangée : en marche et en course, chaque pan suit sa jambe au
# lieu d'être traversé par elle (fente au milieu, devant et derrière, comme
# une blouse d'hôpital). Le haut de la jupe reste sur le bassin. Liaison
# seule : forme et couleurs inchangées (le cache garde le bassin).
SKIRT_SPLIT_Z = 26


def split_skirt(m):
    n = 0
    for (x, y, z), v in m.vox.items():
        if v.part == "skirt" and z < SKIRT_SPLIT_Z:
            v.bone = "thigh_l" if x >= 0 else "thigh_r"
            n += 1
    return n


def build(use_cache=False):
    ref = None if use_cache else _ref_path()
    info = {}
    views = None
    if ref:
        views = Ref(ref).views()
        m, holes, eyes = build_model(views)
        paint(m, views, holes, eyes)
        vx.save_cache(m, CACHE)
        info["iou"] = {k: round(vx.iou(m, v, v.solid), 3) for k, v in views.items()}
    else:
        m = vx.load_cache(CACHE)
        info["from_cache"] = True
    info["skirt_on_thighs"] = split_skirt(m)
    ob, mi = vx.build_mesh(m, "zombie_voxel")
    info.update(mi)
    rig = vx.build_armature("zombie_voxel_rig", BONES, CUBE)
    vx.bind(ob, rig)
    lo, hi = m.bounds()
    info["size_cubes"] = tuple(int(x) for x in (hi - lo))
    by_part = {}
    for v in m.vox.values():
        by_part[v.part] = by_part.get(v.part, 0) + 1
    info["cells_by_part"] = by_part
    return m, ob, rig, info, views


# ---------------------------------------------------------------------------
# Planche de validation (même cadrage et même échelle que la planche).
# ---------------------------------------------------------------------------

def pose_attack(rig):
    """Bras tendus vers l'avant, dos et tête penchés (pose des os)."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")

    def rot(name, axis, deg):
        pb = rig.pose.bones[name]
        bpy.context.view_layer.update()
        mw = pb.matrix.copy()
        loc = mw.translation.copy()
        r = Matrix.Rotation(math.radians(deg), 4, axis) @ mw
        r.translation = loc
        pb.matrix = r
        bpy.context.view_layer.update()

    rot("spine", "X", 8)
    rot("chest", "X", 4)
    rot("head", "X", 6)
    for side, spread in (("l", -6), ("r", 6)):
        rot("arm_" + side, "X", -80)
        rot("arm_" + side, "Z", spread)
        rot("forearm_" + side, "X", -10)
    rot("jaw", "X", 18)
    rot("thigh_l", "X", -12)
    rot("shin_l", "X", 10)
    rot("thigh_r", "X", 10)
    bpy.ops.object.mode_set(mode="OBJECT")


def rest_pose(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def _ref_image(path):
    im = bpy.data.images.load(path)
    W, H = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3].copy()
    bpy.data.images.remove(im)
    return a


def render_sheet(m, rig, path, ref_path):
    """Rangée 1 : planche ; rangée 2 : rendu (même cadrage, même échelle :
    pixel à pixel) ; rangée 3 : les deux à 50 % (vues orthographiques)."""
    tmp = os.path.join(os.path.dirname(os.path.abspath(path)), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    vx.add_outline(m, "zombie_voxel_outline", rig)
    TW, TH = 420, 800
    vx.setup_render((TW, TH))
    ref = _ref_image(ref_path) if ref_path else None
    # Cadrage : colonne centrée sur la silhouette de chaque vue, rangées 0-800
    # (pieds à 770 px, 9,51 px par cube de 2,5 cm = 380,6 px/m).
    pxm, bot = 9.514 / CUBE, 770.0
    tz = (bot - TH / 2.0) / pxm
    hm = TH / pxm
    shots = [("front", 0, 0, 351.5), ("back", 180, 0, 1022.0), ("right", -90, 0, 1569.0), ("left", 90, 0, 1914.0),
             ("34", 35, 8, 2394.0)]
    tiles, refs = [], []
    for name, az, el, cx in shots:
        tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, name + ".png"), az, (0, 0, tz), hm, el)))
        if ref is not None:
            x0 = int(round(cx - TW / 2.0))
            refs.append(ref[0:TH, x0:x0 + TW])
    pose_attack(rig)
    tiles.append(vx.load_png(vx.render_view(os.path.join(tmp, "attack.png"), 35, (0, -0.15, tz), hm, 8)))
    rest_pose(rig)
    rows = [tiles]
    if ref is not None:
        # Pose d'attaque : 2e rangée de la planche, pieds calés à 770 px.
        x0 = int(round(2394.0 - TW / 2.0))
        sub = ref[800:, x0:x0 + TW]
        mx, mn = sub.max(2), sub.min(2)
        filled = ((mx - mn) / np.maximum(mx, 1e-4) > 0.08) | (sub.mean(2) < 0.3)
        rows_f = np.where(filled.any(1))[0]
        y0 = min(ref.shape[0] - TH, 800 + int(rows_f[-1]) + 1 - int(bot)) if len(rows_f) else 736
        refs.append(ref[y0:y0 + TH, x0:x0 + TW])
        blend = [0.5 * r + 0.5 * t for r, t in zip(refs[:4], tiles[:4])]
        rows = [refs, tiles, blend]
    out = vx.sheet(rows, TW, TH)
    vx.save_png(out, path)
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = os.path.join(ROOT, "assets", "models", "zombies", "zombie_voxel.glb")
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
    m, ob, rig, info, views = build(use_cache)
    vx.export_glb(os.path.abspath(glb), [ob, rig], CUBE)
    print("[zombie_voxel] %s -> %s" % (info, glb))
    if sheet:
        render_sheet(m, rig, os.path.abspath(sheet), _ref_path())
        print("[zombie_voxel] planche -> %s" % sheet)
