# MAINS ET AVANT-BRAS DE LA VUE FPS EN CUBES DE 1,25 CM (validés le
# 2026-10-12 : prise à deux mains sur le M1912) : mains gantées du joueur de
# baseball à la taille réelle d'une main (≈ 9 cm de large, doigts séparés),
# même finesse que les armes (weapons_fine.py). Remplacent les mains en cubes
# de 2,5 cm de weapons_voxel.py (pièce « hands »).
#
#   sh tools/blender.sh tools/blender/weapons/hands_fine.py [--sheet DOSSIER] [--export] [--no-check]
#
#   --sheet    planche de validation <DOSSIER>/hands.png : chaque pièce, plus
#              la prise à deux mains sur le M1912 vue de l'œil du joueur
#   --export   écrit assets/models/weapons/voxel/hands.glb et l'entrée
#              « hands » de weapons_voxel.json (sans --export : planche seule)
#
# Pièces (une par nœud « hand__<pièce> », même repère que l'ancienne version,
# lu par ViewHands ; cubes de 1,25 cm ; points « wrist_<pièce> » en mètres) :
#   * grip : main droite autour d'une poignée verticale (axe Y, x = 0,
#     z de -2,5 à +2,5 cm, 3,75 cm de large), poing sous y = 0, index le
#     long du flanc droit et pulpe devant la détente, pouce gauche vers
#     l'avant ;
#   * pistol_grip, pistol_support : prise du pistolet à deux mains, mains
#     minces et jointes (validée le 2026-10-12, pistol_grips.png), même
#     repère que grip ; forearm_pistol, forearm_pistol_l : leurs avant-bras
#     droits de 3 × 3 cubes (même repère que forearm) ;
#   * foregrip, knife : main gauche autour d'un manche vertical, quatre doigts ;
#   * bat_r, bat_l : poings serrés sur un manche rond de 2,5 cm centré en 0 ;
#   * cradle : paume sous un garde-main (origine : milieu du dessous), doigts
#     qui montent sur le flanc droit, pouce à gauche ;
#   * throw_r : main droite autour de la grenade (7,5 cm, centrée en 0) ;
#   * throw_l : pince du pouce et de l'index (goupille) ;
#   Gants SOMBRES vus de l'œil (vue FPS, comme la planche validée) : le cuir
#   clair de la paume n'est peint que sur les faces qui serrent l'objet ;
#   manchettes en cuir sombre en haut, bracelet d'équipe dessous.
#   * forearm, forearm_l : du coude (z = 0) au poignet (z = -ARM_LEN = -0,3 m),
#     section qui s'affine vers le poignet, manche courte du maillot derrière
#     le coude ; forearm_l porte le bandage taché de sang.
import math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import weapons_fine as wf  # noqa: E402

vx, Item, Piece, PAL, FINE = wf.vx, wf.Item, wf.Piece, wf.PAL, wf.FINE
import bpy  # noqa: E402

PAL.update({
    # Palette du joueur de baseball (player_voxel.py, weapons_voxel.py).
    "glove": ("leather", (0.17, 0.17, 0.19)),
    "glove_knuckle": ("leather", (0.25, 0.25, 0.27)),
    "finger_a": ("leather", (0.22, 0.22, 0.24)),
    "finger_b": ("leather", (0.13, 0.13, 0.145)),
    "glove_palm": ("leather", (0.56, 0.47, 0.34)),
    "strap": ("team", (0.56, 0.56, 0.56)),
    "skin": ("skin", (0.80, 0.58, 0.44)),
    "undershirt": ("team", (0.80, 0.80, 0.80)),
    "jersey": ("cloth", (0.88, 0.85, 0.76)),
    "piping": ("team", (0.80, 0.80, 0.80)),
    "bandage": ("cloth", (0.76, 0.72, 0.62)),
    "bandage_tape": ("cloth", (0.78, 0.70, 0.56)),
    "blood_dry": ("cloth", (0.30, 0.10, 0.07)),
})

ARM_LEN = 24  # cubes (0,3 m, ViewHands.ARM_LEN)
ODD = (-0.5, 0.0, 0.0)    # axe au milieu de la colonne i = 0
EVEN = (0.0, 0.0, 0.0)    # axe entre les colonnes -1 et 0


class Hands(Item):
    def start(self, g, offset):
        self.pieces[g] = Piece(offset)
        return g

    def wrist(self, g, x, y, z):
        self.a("wrist_" + g, x, y, z)


def finger_key(n):
    """Doigts séparés par deux tons de cuir (n : numéro du doigt)."""
    return "finger_a" if n % 2 == 0 else "finger_b"


# ---------------------------------------------------------------------------
# Poings autour d'une poignée verticale (i = -1..1, k = -2..1, sous y = 0)
# ---------------------------------------------------------------------------

def fist(h, g, side, index_on_trigger):
    """Poing autour de la poignée. side = 1 : main droite (dos de la main sur
    le flanc droit, bouts des doigts et pouce à gauche) ; -1 : main gauche
    (symétrique). index_on_trigger : l'index longe le flanc et sa pulpe est
    devant la détente ; sinon il entoure la poignée comme les autres."""
    h.start(g, ODD)
    s = side
    F = h.fill

    def box(i0, i1, j0, j1, k0, k1, key):
        a, b = (i0, i1) if s > 0 else (-i1, -i0)
        F(a, b, j0, j1, k0, k1, key, g=g)

    # Dos de la main sur le flanc (2 cubes), jointures marquées à l'avant.
    for j in range(-7, 0):
        box(2, 3, j, j, -2, 3, "glove")
        h.paint(3 * s, j, -2, "+x" if s > 0 else "-x", "glove_knuckle", g=g)
    # Talon de la paume derrière la poignée, éminence du pouce sur l'autre
    # flanc : gant sombre dehors, cuir clair seulement sur la face qui serre
    # la poignée (vue FPS : l'œil voit le dos du talon, qui doit rester sombre
    # comme sur la planche validée hands_m1911.png).
    for j in range(-7, -1):
        box(-1, 1, j, j, 2, 2, "glove")
        box(-2, -2, j, j, 1, 2, "glove")
        for i in (-1, 0, 1):
            h.paint(i, j, 2, "-z", "glove_palm", g=g)
        h.paint(-2 * s, j, 1, "+x" if s > 0 else "-x", "glove_palm", g=g)
        h.paint(-2 * s, j, 2, "+x" if s > 0 else "-x", "glove_palm", g=g)
    # Doigts autour de l'avant, bouts sur l'autre flanc (2 rangées par doigt).
    rows = [(-4, -3), (-6, -5), (-8, -7)] if index_on_trigger else [(-2, -1), (-4, -3), (-6, -5), (-8, -7)]
    for n, (j0, j1) in enumerate(rows):
        key = finger_key(n)
        if j0 == -8 and index_on_trigger:
            j0 = -8
        box(-2, 3, j0, j1, -4, -3, key)
        box(-2, -2, j0, j1, -2, -1, key)
    if index_on_trigger:
        # Index le long du flanc, pulpe devant la détente (sous la carcasse).
        box(2, 2, -2, -1, -5, -3, "finger_b")
        box(0, 1, -2, -1, -5, -5, "glove_knuckle")
    # Pouce vers l'avant le long de l'autre flanc, en haut.
    box(-2, -2, 0, 0, -5, 0, "glove")
    box(-2, -2, -1, 0, 1, 2, "glove")
    # Manchette du gant : cuir sombre en haut (vue de l'œil, derrière le
    # poing), bracelet d'équipe dessous (au poignet).
    box(-1, 3, -3, -2, 4, 5, "glove")
    box(-1, 3, -7, -4, 4, 5, "strap")
    h.wrist(g, 1.0 * s, -4.5, 6.0)


# ---------------------------------------------------------------------------
# Prise du pistolet à deux mains (validée le 2026-10-12, planche
# docs/weapons/img/pistol_grips.png, image du milieu) : mains MINCES et
# JOINTES. Dos de la main, paume et doigts d'un cube, un doigt par rangée ;
# les deux poignets côte à côte sous la poignée, sans jour entre eux ;
# avant-bras DROITS (pièces rigides forearm_pistol / forearm_pistol_l,
# section de 3 × 3 cubes) qui partent vers le bas et l'arrière.
# Repère : celui de « grip » (haut de la poignée, sans inclinaison : ViewHands
# tourne la pièce de grip_angle) ; les indices k sont ceux du repère de l'arme
# du M1912 (poignée à k = 2,5), d'où le décalage de -2,5 cubes en z.
# ---------------------------------------------------------------------------

PISTOL = (-0.5, 0.0, -2.5)


def pistol_grip(h):
    """Main droite mince autour de la poignée : index le long de la carcasse,
    pulpe devant la détente ; majeur, annulaire et auriculaire autour du
    devant de la poignée ; pouce droit vers l'avant sous la glissière."""
    g = h.start("pistol_grip", PISTOL)
    F = h.fill
    for j in range(-6, 0):
        F(2, 2, j, j, 0, 4, "glove", g=g)             # dos de la main (1 cube)
        h.paint(2, j, 0, "+x", "glove_knuckle", g=g)  # jointures
    F(2, 2, -1, -1, -3, -1, "finger_b", g=g)          # index le long du flanc
    F(0, 1, -1, -1, -3, -3, "glove_knuckle", g=g)     # pulpe devant la détente
    for j, key in ((-3, "finger_a"), (-4, "finger_b"), (-5, "finger_a"), (-6, "finger_b")):
        F(-2, 2, j, j, -1, -1, key, g=g)              # doigts devant la poignée
        F(-2, -2, j, j, 0, 1, key, g=g)               # bouts sur le flanc gauche
    F(-2, -2, 0, 0, -2, 2, "glove", g=g)              # pouce droit
    # Poignet sous et derrière la poignée : (1 ; -4 ; 6) cubes dans le repère
    # de l'arme du M1912 (planche), ramené dans le repère de la main, que
    # ViewHands tourne de grip_angle (-15,9°) : (1 ; -4,8 ; 2,3).
    h.wrist(g, 1.0, -4.8, 2.3)


def pistol_support(h):
    """Main gauche mince (même repère que pistol_grip) : paume d'un cube sur
    le flanc gauche, doigts d'un cube devant ceux de la main droite, pouce
    gauche sous le pouce droit."""
    g = h.start("pistol_support", PISTOL)
    F = h.fill
    for j in range(-6, -1):
        F(-3, -3, j, j, -2, 3, "glove", g=g)
        h.paint(-3, j, -2, "-x", "glove_knuckle", g=g)
    for j, key in ((-3, "finger_b"), (-4, "finger_a"), (-5, "finger_b"), (-6, "finger_a")):
        F(-3, 3, j, j, -2, -2, key, g=g)
    F(-2, -2, -1, -1, -3, 1, "glove", g=g)            # pouce gauche
    h.wrist(g, -2.0, -4.8, 2.3)                     # joint au poignet droit


def forearm_pistol(h, g, bandage):
    """Avant-bras droit et mince de la prise du pistolet : du coude (z = 0)
    au poignet (z = -ARM_LEN), section de 3 × 3 cubes centrée sur l'axe
    (bracelet d'équipe et peau au poignet), manche du maillot derrière le
    coude."""
    h.start(g, (-0.5, -0.5, 0.0))
    F = h.fill
    for k in range(-ARM_LEN, 0):
        n = k + ARM_LEN
        key = "strap" if n < 2 else ("skin" if n < 4 else "undershirt")
        F(-1, 1, -1, 1, k, k, key, g=g, f=None)
    for k in range(0, 14):
        F(-2, 2, -2, 2, k, k, "piping" if k == 0 else "jersey", g=g, f=1.0)
    if bandage:
        for k in range(-14, -11):
            for i in range(-1, 2):
                for j in range(-1, 2):
                    if abs(i) == 1 or abs(j) == 1:
                        key = "blood_dry" if (i, j, k) in ((1, 1, -13), (0, 1, -12)) else "bandage"
                        h.put(i, j, k, key, g=g)


def bat_fist(h, g, side):
    """Poing serré sur un manche rond de 2,5 cm centré en 0 (i = -1..0,
    k = -1..0, largeurs paires)."""
    h.start(g, EVEN)
    s = side
    F = h.fill

    def box(i0, i1, j0, j1, k0, k1, key):
        # Symétrie autour de x = 0 en largeurs paires : i -> -1 - i.
        a, b = (i0, i1) if s > 0 else (-1 - i1, -1 - i0)
        F(a, b, j0, j1, k0, k1, key, g=g)

    for j in range(-8, 0):
        box(1, 2, j, j, -2, 3, "glove")          # dos de la main
        box(-2, 0, j, j, 1, 2, "glove")          # paume derrière le manche
        for i in (-2, -1, 0):
            ii = i if s > 0 else -1 - i
            h.paint(ii, j, 1, "-z", "glove_palm", g=g)   # cuir clair contre le manche
    for n, (j0, j1) in enumerate([(-2, -1), (-4, -3), (-6, -5), (-8, -7)]):
        key = finger_key(n)
        box(-3, 2, j0, j1, -3, -2, key)          # doigts devant le manche
        box(-3, -2, j0, j1, -1, 0, key)          # bouts sur l'autre flanc
    box(-3, -3, 0, 0, -3, 1, "glove")            # pouce replié par-dessus
    box(-2, 2, -3, -2, 4, 5, "glove")            # manchette sombre en haut
    box(-2, 2, -7, -4, 4, 5, "strap")
    h.wrist(g, 0.5 * s, -4.5, 6.0)


def cradle(h):
    """Paume sous un garde-main (origine : milieu du dessous), doigts qui
    montent sur le flanc droit, pouce le long du flanc gauche."""
    g = h.start("cradle", ODD)
    F = h.fill
    F(-2, 1, -2, -1, -4, 2, "glove", g=g)        # paume : gant sombre dehors,
    for i in range(-2, 2):                        # cuir clair contre le garde-main
        for k in range(-4, 3):
            h.paint(i, -1, k, "+y", "glove_palm", g=g)
    for n in range(4):                            # doigts sur le flanc droit
        k0 = -4 + 2 * n
        k1 = min(k0 + 1, 2)
        F(2, 3, -2, 1, k0, k1, finger_key(n), g=g)
        F(2, 2, 2, 2, k0, k1, finger_key(n), g=g)  # bouts sur le dessus du flanc
    F(-3, -3, -2, 0, -4, 0, "glove", g=g)         # pouce à gauche
    F(-2, 1, -3, -3, -1, 3, "glove", g=g)         # talon
    F(-2, 1, -5, -4, 1, 3, "strap", g=g)
    h.wrist(g, -0.5, -4.5, 4.0)


def throw_r(h):
    """Main droite refermée sur la grenade (cubes -3..2 sur chaque axe,
    centrée en 0, largeurs paires)."""
    g = h.start("throw_r", EVEN)
    F = h.fill
    F(3, 4, -3, 2, -3, 2, "glove", g=g)           # dos de la main à droite
    for n, (j0, j1) in enumerate([(1, 2), (-1, 0), (-3, -2)]):
        F(-3, 4, j0, j1, -5, -4, finger_key(n), g=g)   # doigts devant
        F(-4, -4, j0, j1, -3, -1, finger_key(n), g=g)  # bouts à gauche
    F(-3, 2, -5, -4, -3, 2, "glove", g=g)         # paume dessous (cuir clair
    for i in range(-3, 3):                        # contre la grenade)
        for k in range(-3, 3):
            h.paint(i, -4, k, "+y", "glove_palm", g=g)
    F(-4, -4, 0, 2, 0, 2, "glove", g=g)           # pouce
    F(1, 4, -4, -1, 3, 4, "strap", g=g)
    h.wrist(g, 2.0, -2.5, 5.0)


def throw_l(h):
    """Pince de la main gauche (goupille) : pouce et index qui se rejoignent
    devant l'origine, autres doigts repliés."""
    g = h.start("throw_l", ODD)
    F = h.fill
    F(-2, 1, -6, -1, 0, 4, "glove", g=g)          # main
    F(-1, 0, -1, -1, -3, -1, "finger_a", g=g)     # index tendu
    F(-1, 0, 0, 0, -2, -1, "glove", g=g)          # pouce au-dessus
    for n, j in enumerate((-3, -4, -5)):
        F(-2, 1, j, j, -1, -1, finger_key(n + 1), g=g)   # doigts repliés
    F(-2, 1, -6, -3, 5, 6, "strap", g=g)
    h.wrist(g, -0.5, -4.5, 7.0)


def forearm(h, g, bandage):
    """Du coude (z = 0) au poignet (z = -ARM_LEN), section centrée sur l'axe
    (largeurs impaires, décalage d'un demi-cube en x et en y)."""
    h.start(g, (-0.5, -0.5, 0.0))
    F = h.fill
    for k in range(-ARM_LEN, 5):
        if k < -20:
            w, t = 2, 1        # poignet : 6,25 × 3,75 cm
        elif k < -9:
            w, t = 2, 2        # 6,25 × 6,25 cm
        else:
            w, t = 3, 2        # près du coude : 8,75 × 6,25 cm
        key = "skin" if k < -ARM_LEN + 2 else "undershirt"
        F(-w, w, -t, t, k, k, key, g=g, f=None)
    # Manche courte du maillot derrière le coude (presque toujours hors champ :
    # teinte unie, faces fusionnées).
    for k in range(5, 23):
        F(-4, 4, -3, 3, k, k, "piping" if k == 5 else "jersey", g=g, f=1.0)
    if bandage:
        # Deux tours de gaze sale à mi-avant-bras, à plat (même section),
        # taches de sang séché sur le dessus et le flanc.
        for k in range(-15, -11):
            for i in range(-2, 3):
                for j in range(-2, 3):
                    if abs(i) == 2 or abs(j) == 2:
                        key = "bandage_tape" if (k == -12 and (i + j) % 2 == 0) else "bandage"
                        if (i, j, k) in ((1, 2, -14), (2, 1, -13), (0, 2, -13), (2, 0, -12)):
                            key = "blood_dry"
                        h.put(i, j, k, key, g=g)


def b_hands():
    h = Hands("hands", "hands")
    fist(h, "grip", 1, True)
    pistol_grip(h)
    pistol_support(h)
    fist(h, "foregrip", -1, False)
    fist(h, "knife", -1, False)
    bat_fist(h, "bat_r", 1)
    bat_fist(h, "bat_l", -1)
    cradle(h)
    throw_r(h)
    throw_l(h)
    forearm(h, "forearm", False)
    forearm(h, "forearm_l", True)
    forearm_pistol(h, "forearm_pistol", False)
    forearm_pistol(h, "forearm_pistol_l", True)
    h.info["cube"] = FINE
    h.info["arm_len"] = round(ARM_LEN * FINE, 4)
    return h


# ---------------------------------------------------------------------------
# Planche et export
# ---------------------------------------------------------------------------

def place(models, it, g, loc=(0, 0, 0), rot=None):
    """Construit la pièce g de it, placée en repère Godot (m) -> Blender."""
    p = it.pieces[g]
    m = wf.to_model(p, it.cube)
    ob, info = vx.build_mesh(m, "%s__%s" % (it.id, g))
    ox, oy, oz = p.offset
    base = (ox * it.cube + loc[0], -oz * it.cube - loc[2], oy * it.cube + loc[1])
    ob.location = base
    models[it.id + g + str(len(models))] = (m, ob)
    return info["tris"]


def render_sheet(h, out):
    os.makedirs(out, exist_ok=True)
    rows = []
    groups = [["grip", "pistol_grip", "pistol_support", "foregrip"], ["knife", "bat_r", "bat_l", "cradle"],
              ["throw_r", "throw_l", "forearm", "forearm_l"], ["forearm_pistol", "forearm_pistol_l"]]
    for row in groups:
        imgs = []
        for g in row:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            models = {}
            place(models, h, g)
            vx.setup_render((420, 420))
            for _k, (m, ob) in models.items():
                o = vx.add_outline(m, ob.name + "_o", thickness=0.0012)
                o.location = ob.location
            bpy.context.view_layer.update()
            c, s = wf._frame([ob for _, ob in models.values()])
            p = os.path.join(out, "_tmp_%s.png" % g)
            vx.render_view(p, -140.0, c, s * 1.3, elev=22.0, dist=10.0)
            imgs.append(vx.load_png(p))
        rows.append(imgs)
    path = os.path.join(out, "hands.png")
    vx.save_png(vx.sheet(rows, 420, 420), path)
    print("[hands_fine] planche : " + path)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir = os.path.abspath(args[args.index("--sheet") + 1]) if "--sheet" in args else ""
    h = b_hands()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs, tris = [], 0
    for g, p in h.pieces.items():
        m = wf.to_model(p, h.cube)
        ob, info = vx.build_mesh(m, "hand__%s" % g)
        ox, oy, oz = p.offset
        ob.location = (ox * h.cube, -oz * h.cube, oy * h.cube)
        obs.append(ob)
        tris += info["tris"]
        print("[hands_fine] %-15s %4d triangles" % (g, info["tris"]))
    print("[hands_fine] total %d triangles" % tris)
    if "--export" in args:
        # .glb et entrée « hands » de weapons_voxel.json (points, boîtes,
        # triangles) : même écriture que les armes fines.
        path = wf.export(h, obs, tris)
        print("[hands_fine] écrit : " + path)
        # Pièces indépendantes : vérifiées pièce par pièce (mode « animé »).
        if "--no-check" not in args:
            import shutil, subprocess
            exe = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot.exe")
            if exe:
                rel = "res://" + os.path.relpath(path, wf.ROOT).replace("\\", "/")
                r = subprocess.run([exe, "--headless", "--path", wf.ROOT, "-s", "res://tools/voxel_check.gd", "--",
                                    rel, "--anime", "--pas=%g" % (FINE * 100.0)], capture_output=True, text=True,
                                   timeout=900)
                print("\n".join(l for l in r.stdout.splitlines() if "voxel_check" in l or l.startswith("  ")))
                if r.returncode != 0:
                    print("[hands_fine] NON CONFORMES")
                    sys.exit(1)
    if sheet_dir:
        render_sheet(h, sheet_dir)


if __name__ == "__main__":
    main()
