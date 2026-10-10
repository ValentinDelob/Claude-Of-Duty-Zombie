# OBJETS DE CARTE CUBIQUES de taille fixe (lot 4 de docs/VOXEL_DECOR_PLAN.md) :
# caisse au hasard, levier du courant, téléporteur et sa sortie, poste
# central (mural et au sol), panneau des pièges, porte d'évacuation. Cubes de
# 5 cm (GAME_CONCEPT.md § 4.19), sur tools/blender/voxel_props/common.py.
# Les objets dont la taille vient de la carte (portes, débris, planches et
# portes à zombies des barricades, caisse et baril de l'éditeur) sont
# construits par le jeu (scripts/game/map/voxel_build.gd).
#
#   sh tools/blender.sh tools/blender/voxel_props/objets.py [ids...] [--sheet DOSSIER] [--before DOSSIER] [--no-check]
#   sh tools/blender.sh tools/blender/voxel_props/objets.py --glb FICHIER.glb [...] --sheet DOSSIER
#
# Un objet = un .glb assets/models/props/voxel/objets/<objet>.glb, un nœud
# par PIÈCE « voxel__<objet>_<pièce>__<type> » (type « block » : ombre portée,
# « ns » : sans ombre). Toutes les pièces sont décrites dans le repère de
# l'objet (même origine que l'ancien visuel construit par son script) : le
# jeu (VoxelBuild.parts / attach) range les pièces mobiles (couvercle,
# levier, battant) sous leur pivot, qui les fait tourner ou glisser ; les
# voyants et anneaux lumineux reçoivent le matériau émissif de leur script.
# Aucune collision dans le .glb (celles des scripts sont inchangées).
#
# Description en cellules dans le REPÈRE GODOT de l'objet (x, y en haut,
# z vers la pièce) : G.box / G.put / G.paint convertissent en repère Blender
# (x, -z, y) ; cellule Godot (x, y, z) = [x, x+1] × [y, y+1] × [z, z+1] cubes.
#
# --glb : planche d'un .glb exporté par le jeu (objets construits par le jeu,
# couleurs de sommet), sans contrôle.
import math, os, sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import voxel_lib as vx  # noqa: E402

OUT_DIR = os.path.join(C.ROOT, "assets", "models", "props", "voxel", "objets")

# Teintes propres aux objets de carte (sRGB), en plus de vx.DECOR_PALETTE
# (gardées ici : voxel_lib n'est pas modifié). Mêmes valeurs que
# VoxelBuild.PAL dans le jeu.
PAL = dict(vx.DECOR_PALETTE)
PAL.update({
    "door_steel": (0.33, 0.37, 0.38),     # tôle grise (armoires, panneaux)
    "door_edge": (0.20, 0.22, 0.23),      # cadres, rivets
    "crate_olive": (0.34, 0.38, 0.27),    # caisse au hasard, peinture olive
    "crate_inner": (0.24, 0.17, 0.11),    # intérieur de la caisse
    "glow_gold": (1.0, 0.80, 0.45),       # fond lumineux de la caisse
    "lab_green": (0.22, 0.42, 0.36),      # vert laboratoire (téléporteur)
    "evac_green": (0.16, 0.40, 0.24),     # porte d'évacuation
    "cream": (0.86, 0.80, 0.64),          # cadrans
    "lever_red": (0.62, 0.08, 0.06),      # poignée du levier
})


def col(name, f=1.0):
    return vx.tone(PAL[name], f)


def grain(c, base, seed=0, amp=0.07, levels=3):
    return C.grain(c, base, seed, amp, levels)


# Directions Godot -> Blender (repère Blender : x, y = -z Godot, z = y Godot).
GDIR = {"+x": "+x", "-x": "-x", "+y": "+z", "-y": "-z", "+z": "-y", "-z": "+y"}


class G:
    """Modèle décrit dans le repère Godot de l'objet."""

    def __init__(self):
        self.m = vx.Model(C.CUBE)

    @staticmethod
    def b(x, y, z):
        return (x, -z - 1, y)

    def put(self, x, y, z, mat, color):
        bx, by, bz = self.b(x, y, z)
        self.m.set(bx, by, bz, mat, color=color)

    def has(self, x, y, z):
        return self.b(x, y, z) in self.m.vox

    def remove(self, x, y, z):
        self.m.vox.pop(self.b(x, y, z), None)

    def box(self, x0, x1, y0, y1, z0, z1, mat, base, seed=0, amp=0.06, levels=3, keep=None):
        for x in range(x0, x1):
            for y in range(y0, y1):
                for z in range(z0, z1):
                    if keep is None or keep(x, y, z):
                        self.put(x, y, z, mat, grain((x, y, z), base, seed, amp, levels))

    def paint(self, x, y, z, d, color):
        c = self.b(x, y, z)
        if c in self.m.vox:
            self.m.face_color[(c[0], c[1], c[2], GDIR[d])] = color

    def front(self, x, y, d, color, z0=-200, z1=200):
        """Peint la face `d` (+z / -z) du premier cube rencontré en (x, y)."""
        zs = range(z1 - 1, z0 - 1, -1) if d == "+z" else range(z0, z1)
        for z in zs:
            if self.has(x, y, z):
                self.paint(x, y, z, d, color)
                return True
        return False

    def top(self, x, z, color, y0=-200, y1=200):
        """Peint le dessus du cube le plus haut en (x, z)."""
        for y in range(y1 - 1, y0 - 1, -1):
            if self.has(x, y, z):
                self.paint(x, y, z, "+y", color)
                return True
        return False


def disc(r, x, z):
    """Cellule (x, z) dans le disque de rayon `r` cubes centré sur l'origine."""
    return (x + 0.5) ** 2 + (z + 0.5) ** 2 <= r * r


# ------------------------------------------------------------------ caisse au hasard

def boite():
    """Caisse au hasard (MysteryBox, BODY_SIZE 1,8 × 0,85 × 0,85) : caisse de
    matériel peinte olive, planches à joints, cornières et cerclages d'acier,
    bande de danger, dé peint sur le couvercle (« au hasard »), intérieur
    capitonné et fond qui s'allume à l'ouverture. Couvercle à part (pivot de
    la charnière, LID_HINGE). Origine : au sol, au centre ; +z : l'avant."""
    body, lid, inner, bed = G(), G(), G(), G()
    olive = col("crate_olive")
    steel = col("steel")
    X, Z = 18, 8          # demi-largeur, demi-profondeur (cubes) : 1,8 × 0,8 m
    H = 15                # coffre : 0,75 m ; couvercle jusqu'à 0,85 m

    def wall(x, y, z):
        return not (-X + 1 <= x < X - 1 and 1 <= y and -Z + 1 <= z < Z - 1)

    body.box(-X, X, 0, H, -Z, Z, "wood", olive, 1, 0.05, 3, keep=wall)
    # Joints des planches (tous les 3 cubes), cornières et cerclages d'acier.
    for x in range(-X, X):
        for y in range(H):
            for z in (-Z, Z - 1):
                d = "+z" if z == Z - 1 else "-z"
                if y % 3 == 2:
                    body.paint(x, y, z, d, col("crate_olive", 0.7))
    for x in range(-X, X):
        for y in range(H):
            for z in range(-Z, Z):
                if not body.has(x, y, z):
                    continue
                ex = x in (-X, X - 1)
                ez = z in (-Z, Z - 1)
                band = x in (-11, -10, 9, 10)
                if (ex and ez) or (y in (0, H - 1) and (ex or ez)) or (band and (ez or y == 0)):
                    body.put(x, y, z, "metal", grain((x, y, z), steel, 2, 0.05, 2))
    # Bande de danger en façade (+z) et à l'arrière, entre les cerclages.
    for x in range(-9, 9):
        for y in (3, 4, 5):
            for z, d in ((Z - 1, "+z"), (-Z, "-z")):
                body.paint(x, y, z, d, col("hazard_yellow") if (x - y) % 6 < 3 else col("rubber"))
    # Poignées encastrées sur les petits côtés (±x) : cuvette sombre, barre d'acier.
    for x, d in ((-X, "-x"), (X - 1, "+x")):
        for z in range(-3, 3):
            for y in (8, 10):
                body.paint(x, y, z, d, col("rubber"))
            body.paint(x, 9, z, d, steel)
    # Fermeture en façade (sous le couvercle) : plaque d'acier en saillie.
    for x in (-1, 0):
        body.put(x, H - 2, Z, "metal", col("steel", 1.1))
        body.put(x, H - 3, Z, "metal", col("steel", 0.9))
    # Intérieur capitonné (s'éclaire à l'ouverture) et fond lumineux.
    inner.box(-X + 1, X - 1, 1, H, -Z + 1, Z - 1, "fabric", col("crate_inner"), 3, 0.06, 2,
              keep=lambda x, y, z: not (-X + 2 <= x < X - 2 and 2 <= y and -Z + 2 <= z < Z - 2))
    bed.box(-X + 2, X - 2, 2, 3, -Z + 2, Z - 2, "glow", col("glow_gold"), 4, 0.12, 3)
    # Couvercle : planches olive, rebord d'acier, charnières derrière, moraillon devant.
    lid.box(-X, X, H, H + 2, -Z, Z, "wood", olive, 5, 0.05, 3)
    for x in range(-X, X):
        for z in range(-Z, Z):
            if x in (-X, X - 1) or z in (-Z, Z - 1):
                for y in (H, H + 1):
                    lid.put(x, y, z, "metal", grain((x, y, z), steel, 6, 0.05, 2))
            elif (z + Z) % 4 == 3:
                lid.paint(x, H + 1, z, "+y", col("crate_olive", 0.72))
    # Dé peint sur le couvercle (cinq points blancs sur un carré sombre).
    for x in range(-5, 5):
        for z in range(-5, 5):
            pip = any(x in (px, px + 1) and z in (pz, pz + 1) for px, pz in ((-4, -4), (2, -4), (-1, -1), (-4, 2), (2, 2)))
            lid.paint(x, H + 1, z, "+y", col("paint_white") if pip else col("rubber", 2.2))
    for x in (-13, -12, 11, 12):
        lid.put(x, H, -Z - 1, "metal", col("steel", 0.85))
    for x in (-1, 0):
        lid.put(x, H, Z, "metal", col("steel", 1.15))
        lid.put(x, H - 1, Z, "metal", col("steel", 1.0))
    return {"coffre": (body, "block"), "couvercle": (lid, "block"), "interieur": (inner, "ns"), "fond": (bed, "ns")}


# ------------------------------------------------------------------ courant

def courant():
    """Levier du générateur (PowerSwitch : boîtier 0,7 × 1,0 × 0,2 m au mur,
    origine au milieu du boîtier, à 12 cm du mur ; +z vers la pièce) : tôle
    grise, éclair peint, câbles qui montent au plafond, levier à poignée
    rouge (pivot (0, 0, 0,12)), gyrophare de secours au-dessus."""
    box, lever, beacon = G(), G(), G()
    box.box(-7, 7, -10, 10, -2, 2, "metal", col("door_steel"), 11, 0.05, 2)
    for x in range(-7, 7):
        for y in range(-10, 10):
            if x in (-7, 6) or y in (-10, 9):
                for z in range(-2, 2):
                    box.put(x, y, z, "metal", grain((x, y, z), col("door_edge"), 12, 0.06, 2))
    # Bandes de danger en haut, éclair jaune au milieu, fente du levier.
    for x in range(-6, 6):
        for y in (7, 8):
            box.paint(x, y, 1, "+z", col("hazard_yellow") if (x + y) % 4 < 2 else col("rubber"))
    bolt = ["...##", "..##.", ".##..", "#####", "..##.", ".##..", "##..."]
    for r, line in enumerate(bolt):
        for k, ch in enumerate(line):
            if ch == "#":
                box.paint(-6 + k, 5 - r, 1, "+z", col("hazard_yellow"))
    for y in range(-8, 2):
        box.paint(-1, y, 1, "+z", col("rubber"))
        box.paint(0, y, 1, "+z", col("rubber"))
    # Joues du pivot de part et d'autre du levier.
    for x in (-3, -2, 1, 2):
        box.put(x, -1, 2, "metal", col("metal_dark"))
        box.put(x, 0, 2, "metal", col("metal_dark"))
    # Trois câbles vers le plafond (1,5 m), à l'arrière, socle du gyrophare.
    for x0 in (-5, -1, 3):
        box.box(x0, x0 + 2, 10, 40, -2, 0, "rubber", col("rubber", 1.6), 13, 0.1, 2)
    box.box(-2, 2, 10, 11, 0, 2, "metal", col("metal_dark"), 14, 0.05, 2)
    # Levier (repère de l'objet, pivot en (0, 0, 0,12)) : bras d'acier, poignée rouge.
    lever.box(-1, 1, 0, 9, 2, 3, "metal", col("steel"), 15, 0.05, 2)
    lever.box(-2, 2, 8, 10, 2, 4, "rubber", col("lever_red"), 16, 0.06, 2)
    beacon.box(-1, 1, 11, 13, 0, 2, "glow", col("medic_red"), 17, 0.05, 2)
    return {"boitier": (box, "block"), "levier": (lever, "block"), "gyrophare": (beacon, "ns")}


# ------------------------------------------------------------------ pièges

def levier_piege():
    """Panneau d'un piège électrique (ElectricTrap) et de son second levier
    (TrapLever) : boîtier 0,5 × 0,6 m à 2 cm du mur (origine à 12 cm du mur,
    au milieu ; +z vers la pièce), cadre jaune et noir, levier fixe à poignée
    rouge, voyant (pièce à part, couleur donnée par le jeu)."""
    panel, lamp = G(), G()
    panel.box(-5, 5, -6, 6, -2, 1, "metal", col("door_steel", 0.9), 21, 0.05, 2)
    for x in range(-5, 5):
        for y in range(-6, 6):
            if x in (-5, 4) or y in (-6, 5):
                panel.paint(x, y, 0, "+z", col("hazard_yellow") if (x + y) % 2 == 0 else col("rubber"))
    # Levier : socle, tige verticale, poignée rouge.
    panel.box(2, 4, -1, 1, 1, 2, "metal", col("metal_dark"), 22, 0.05, 2)
    panel.box(2, 3, 1, 5, 1, 2, "metal", col("steel"), 23, 0.05, 2)
    panel.box(1, 4, 5, 7, 1, 2, "rubber", col("lever_red"), 24, 0.05, 2)
    lamp.box(-4, -2, 3, 5, 1, 2, "glow", col("medic_red"), 25, 0.05, 2)
    return {"panneau": (panel, "block"), "voyant": (lamp, "ns")}


# ------------------------------------------------------------------ téléporteur

def _pad(k):
    """Plateforme du téléporteur à l'échelle `k` (1 : départ, Ø 3 m ; 0,7 :
    arrivée) : disque en deux marches, bord à bandes de danger, plateau à
    grille peinte, quatre bobines de cuivre ; anneau et boules (pièce à part,
    matériau lumineux du jeu)."""
    base, ring = G(), G()
    R = int(round(30 * k))
    R1 = R - max(1, int(round(2 * k)))
    lo, hi = int(round(21 * k)), int(round(24 * k))
    plate = col("door_steel", 1.1)
    for x in range(-R, R):
        for z in range(-R, R):
            if disc(R, x, z):
                base.put(x, 0, z, "metal", grain((x // 3, 0, z // 3), col("door_edge", 1.2), 31, 0.05, 2))
            if disc(R1, x, z):
                c = plate if (x % 6 and z % 6) else col("door_steel", 0.8)
                base.put(x, 1, z, "metal", grain((x // 6, 1, z // 6), c, 32, 0.04, 2))
            if disc(hi, x, z) and not disc(lo, x, z):
                ring.put(x, 2, z, "glow", col("ember", 0.9))
    # Bandes de danger sur le chant de la marche du bas.
    for (x, y, z) in [((c[0]), c[2], -c[1] - 1) for c in list(base.m.vox)]:
        if y != 0:
            continue
        for d, (dx, dz) in (("+x", (1, 0)), ("-x", (-1, 0)), ("+z", (0, 1)), ("-z", (0, -1))):
            if not base.has(x + dx, 0, z + dz):
                base.paint(x, 0, z, d, col("hazard_yellow") if (x + z) % 4 < 2 else col("rubber"))
    # Bobines aux quatre coins (45°) : fût en escalier, enroulements de cuivre.
    c0 = int(round(1.3 * k / math.sqrt(2) / C.CUBE))
    top = int(round(1.6 * k / C.CUBE))
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * c0, sz * c0
            base.box(cx - 2, cx + 2, 2, 5, cz - 2, cz + 2, "metal", col("metal_dark"), 33, 0.05, 2)
            for y in range(5, top):
                copper = (y // 2) % 2 == 0
                for x in range(cx - 1, cx + 1):
                    for z in range(cz - 1, cz + 1):
                        base.put(x, y, z, "metal", col("copper", 0.9 + 0.15 * vx.noise((x, y, z), 34)) if copper else col("metal_dark", 1.2))
            ring.box(cx - 2, cx + 2, top, top + 4, cz - 2, cz + 2, "glow", col("ember", 0.9), 35, 0.05, 2,
                     keep=lambda x, y, z, cx=cx, cz=cz, top=top: not ((x in (cx - 2, cx + 1)) and (z in (cz - 2, cz + 1)) and y in (top, top + 3)))
    return {"socle": (base, "block"), "anneau": (ring, "ns")}


def teleporteur():
    """Plateforme de départ du téléporteur (Teleporter, Ø 3 m)."""
    return _pad(1.0)


def arrivee():
    """Plateforme d'arrivée du téléporteur (ExitPad, Ø 2,1 m)."""
    return _pad(0.7)


# ------------------------------------------------------------------ poste central

def poste_central_mur():
    """Poste central mural (TeleporterMainframe : armoire 2,2 × 2,3 × 0,7 m,
    origine au sol au milieu ; +z vers la pièce) : chapeau, panneau d'acier,
    quatre cadrans, tubes à vide (pièce « tubes ») et voyant (pièce
    « voyant ») lumineux selon la liaison, quatre câbles vers le plafond."""
    cab, tubes, lamp = G(), G(), G()
    cab.box(-22, 22, 0, 46, -7, 7, "metal", col("door_steel"), 41, 0.05, 2)
    # Montants sombres, portes à deux battants (joint), socle.
    for x in range(-22, 22):
        for y in range(46):
            if x in (-22, -21, 20, 21) or y < 2:
                for z in range(-7, 7):
                    cab.put(x, y, z, "metal", grain((x, y, z), col("door_edge"), 42, 0.05, 2))
    for y in range(2, 22):
        cab.paint(-1, y, 6, "+z", col("door_edge"))
    # Poignées des deux battants.
    for x in (-3, 1):
        for y in range(10, 15):
            cab.paint(x, y, 6, "+z", col("steel", 1.1))
    cab.box(-23, 23, 46, 48, -8, 8, "metal", col("steel", 0.9), 43, 0.04, 2)
    cab.box(-20, 20, 23, 41, 7, 8, "metal", col("steel"), 44, 0.04, 2)
    # Cadrans : plaques crème en saillie, aiguille sombre.
    for x0 in (-16, -7, 3, 12):
        cab.box(x0, x0 + 4, 33, 37, 8, 9, "metal", col("cream"), 45, 0.03, 2)
        cab.paint(x0 + 1, 35, 8, "+z", col("rubber"))
        cab.paint(x0 + 2, 34, 8, "+z", col("rubber"))
        cab.paint(x0 + 1, 34, 8, "+z", col("medic_red"))
    # Tubes à vide sur leurs culots.
    for x0 in (-16, -10, -4, 2, 8, 14):
        cab.box(x0, x0 + 2, 22, 23, 8, 10, "metal", col("metal_dark"), 46, 0.04, 2)
        tubes.box(x0, x0 + 2, 23, 28, 8, 10, "glow", col("ember"), 47, 0.04, 2)
    lamp.box(-2, 2, 41, 45, 7, 9, "glow", col("medic_red"), 48, 0.04, 2)
    # Câbles du plafond (3 m), à l'arrière.
    for x0 in (-17, -7, 7, 16):
        cab.box(x0, x0 + 2, 48, 106, -5, -3, "rubber", col("rubber", 1.6), 49, 0.1, 2)
    return {"armoire": (cab, "block"), "tubes": (tubes, "ns"), "voyant": (lamp, "ns")}


def poste_central_sol():
    """Poste central au sol (Kino : disque de 4,4 m, 30 cm de haut, bord en
    marches de cubes ; origine au sol au centre) : socle sombre, plateau
    d'acier peint, anneau de lampes à fleur du dessus (pièce « anneau »),
    voyant central (pièce « voyant ») ; câble au sol (pièce « cable », 6 m le
    long de -z, placé par le jeu)."""
    base, ring, lamp, cable = G(), G(), G(), G()
    radii = (44, 42, 40, 39, 37, 35)
    for y, r in enumerate(radii):
        for x in range(-r, r):
            for z in range(-r, r):
                if not disc(r, x, z):
                    continue
                if y == len(radii) - 1 and disc(26, x, z) and not disc(23, x, z):
                    ring.put(x, y, z, "glow", col("ember", 0.9))
                    continue
                # Grain par plaque de 3 × 3 cubes : moins de faces séparées.
                base.put(x, y, z, "metal", grain((x // 3, y, z // 3), col("door_edge", 1.15), 51, 0.05, 2))
    top = len(radii) - 1
    for x in range(-22, 22):
        for z in range(-22, 22):
            if disc(21.7, x, z):
                base.paint(x, top, z, "+y", grain((x // 5, top, z // 5), col("steel", 0.95) if (x % 5 and z % 5) else col("steel", 0.75), 52, 0.04, 2))
    # Chant du bas à bandes de danger.
    for x in range(-44, 44):
        for z in range(-44, 44):
            if not base.has(x, 0, z):
                continue
            for d, (dx, dz) in (("+x", (1, 0)), ("-x", (-1, 0)), ("+z", (0, 1)), ("-z", (0, -1))):
                if not base.has(x + dx, 0, z + dz):
                    base.paint(x, 0, z, d, col("hazard_yellow") if (x + z) % 4 < 2 else col("rubber"))
    lamp.box(-2, 2, 6, 7, -2, 2, "glow", col("medic_red"), 53, 0.03, 2)
    lamp.box(-1, 1, 7, 8, -1, 1, "glow", col("medic_red"), 53, 0.03, 2)
    cable.box(-2, 2, 0, 4, -60, 60, "rubber", col("rubber", 1.6), 54, 0.1, 2)
    return {"socle": (base, "block"), "anneau": (ring, "ns"), "voyant": (lamp, "ns"), "cable": (cable, "block")}


# ------------------------------------------------------------------ évacuation

def evacuation():
    """Porte d'évacuation (EvacDoor : battant 1,2 × 2,0 m, bâti de 10 cm,
    15 cm de profondeur ; origine au pied de la porte sur la face du mur, +z
    vers la pièce) : bâti d'acier, battant vert de secours (pièce
    « battant », recule dans le mur à l'ouverture) à barre de poussée et
    flèche peinte, voyant au-dessus (pièce « voyant », couleur du jeu)."""
    frame, leaf, lamp = G(), G(), G()
    steel = col("steel", 0.85)
    for x0 in (-14, 12):
        frame.box(x0, x0 + 2, 0, 40, 0, 3, "metal", steel, 61, 0.05, 2)
    frame.box(-14, 14, 40, 42, 0, 3, "metal", steel, 62, 0.05, 2)
    for x in range(-14, 14):
        for y in range(42):
            if frame.has(x, y, 2) and (x + y) % 8 == 0:
                frame.paint(x, y, 2, "+z", col("steel", 1.1))
    leaf.box(-12, 12, 0, 40, 0, 2, "metal", col("evac_green"), 63, 0.05, 2)
    for x in range(-12, 12):
        for y in range(40):
            if x in (-12, 11) or y in (0, 39, 13, 27):
                leaf.paint(x, y, 1, "+z", col("evac_green", 0.75))
    # Flèche blanche vers la sortie (haut du battant).
    arrow = [".....#...", ".....##..", "########.", "#########", "########.", ".....##..", ".....#..."]
    for r, line in enumerate(arrow):
        for k, ch in enumerate(line):
            if ch == "#":
                leaf.paint(-5 + k, 36 - r, 1, "+z", col("paint_white"))
    leaf.box(-8, 8, 19, 21, 2, 3, "metal", col("steel", 1.05), 64, 0.04, 2)
    leaf.box(-9, -8, 18, 22, 2, 3, "metal", col("metal_dark"), 65, 0.04, 2)
    leaf.box(8, 9, 18, 22, 2, 3, "metal", col("metal_dark"), 65, 0.04, 2)
    lamp.box(-4, 4, 42, 45, 1, 3, "glow", col("medic_red"), 66, 0.03, 2)
    return {"bati": (frame, "block"), "battant": (leaf, "block"), "voyant": (lamp, "ns")}


BUILDERS = {
    "boite": boite,
    "courant": courant,
    "levier_piege": levier_piege,
    "teleporteur": teleporteur,
    "arrivee": arrivee,
    "poste_central_mur": poste_central_mur,
    "poste_central_sol": poste_central_sol,
    "evacuation": evacuation,
}
# Anciens modèles .glb (planches avant / après, --before).
BEFORE = {"boite": "mystery_box"}


# ------------------------------------------------------------------ export et planches

def export_obj(oid, parts):
    """Ombrage peint, maillages et export de l'objet : un nœud par pièce."""
    obs, info = [], []
    for part, (g, kind) in parts.items():
        vx.shade(g.m)
        ob, inf = vx.build_mesh(g.m, "voxel__%s_%s__%s" % (oid, part, kind))
        obs.append(ob)
        info.append((part, inf))
    path = os.path.join(OUT_DIR, oid + ".glb")
    vx.export_glb(path, obs, C.CUBE)
    tris = sum(i["tris"] for _, i in info)
    print("[objets] %-18s %s  -> %d triangles" % (oid, "  ".join("%s %d cel./%d tri." % (p, i["cells"], i["tris"]) for p, i in info), tris))
    return obs


def _frame(objs):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return tuple((a + b) / 2 for a, b in zip(lo, hi)), max(hi[i] - lo[i] for i in range(3))


VIEWS = (("trois-quarts", 35.0, 28.0), ("face", 0.0, 0.0), ("dos", 200.0, 20.0))


def _render(tmp, tag, frame):
    c, size = frame
    out = []
    for name, az, el in VIEWS:
        p = os.path.join(tmp, "%s_%s.png" % (tag, name))
        vx.render_view(p, az, c, size * 1.25, elev=el, dist=30.0)
        out.append(vx.load_png(p))
    return out


def board_obj(oid, parts, obs, sheet_dir, before_glb=None):
    tmp = os.path.join(sheet_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    vx.setup_render((520, 520))
    outlines = [vx.add_outline(g.m, "%s_%s_outline" % (oid, p), thickness=0.006) for p, (g, _k) in parts.items()]
    frame = _frame(obs)
    rows = [_render(tmp, oid + "_apres", frame)]
    if before_glb and os.path.exists(before_glb):
        for o in obs + outlines:
            o.hide_render = True
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=before_glb)
        olds = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        rows.insert(0, _render(tmp, oid + "_avant", frame))
        for o in olds:
            bpy.data.objects.remove(o)
        for o in obs + outlines:
            o.hide_render = False
    path = os.path.join(sheet_dir, oid + ".png")
    vx.save_png(vx.sheet(rows, 520, 520), path)
    print("[objets] planche : " + path)


def board_glb(path, sheet_dir):
    """Planche d'un .glb exporté par le jeu (couleurs de sommet linéaires,
    COLOR_0), sans contour (rectangles non soudés : une coque Solidify y
    laisserait des traits parasites)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    mat = bpy.data.materials.new("vc")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    for o in obs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    tmp = os.path.join(sheet_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    vx.setup_render((520, 520))
    name = os.path.splitext(os.path.basename(path))[0]
    rows = [_render(tmp, name, _frame(obs))]
    out = os.path.join(sheet_dir, name + ".png")
    vx.save_png(vx.sheet(rows, 520, 520), out)
    print("[objets] planche : " + out)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir = before_dir = ""
    check = True
    ids, glbs = [], []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sheet":
            sheet_dir = os.path.abspath(args[i + 1])
            i += 1
        elif a == "--before":
            before_dir = os.path.abspath(args[i + 1])
            i += 1
        elif a == "--glb":
            glbs.append(os.path.abspath(args[i + 1]))
            i += 1
        elif a == "--no-check":
            check = False
        else:
            ids.append(a)
        i += 1
    for g in glbs:
        board_glb(g, sheet_dir)
    if glbs and not ids:
        return
    bad = []
    for oid in ids or list(BUILDERS):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        parts = BUILDERS[oid]()
        obs = export_obj(oid, parts)
        if sheet_dir:
            old = BEFORE.get(oid)
            board_obj(oid, parts, obs, sheet_dir, os.path.join(before_dir, old + ".glb") if (before_dir and old) else None)
        if check and not vx.godot_check(os.path.join(OUT_DIR, oid + ".glb"), animated=False):
            bad.append(oid)
    if bad:
        print("[objets] NON CONFORMES : " + ", ".join(bad))
        sys.exit(1)


if __name__ == "__main__":
    main()
