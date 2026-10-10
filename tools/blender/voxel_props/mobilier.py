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


BUILDERS = {
    "caisses": caisses,
    "sacs_sable": sacs_sable,
}
# Anciens modèles .glb (planches avant / après, --before).
BEFORE = {"caisses": "stage_crates"}

if __name__ == "__main__":
    C.main(BUILDERS, BEFORE)
