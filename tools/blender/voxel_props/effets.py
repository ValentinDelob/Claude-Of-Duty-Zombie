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


BUILDERS = {
    "foyer_pierres": foyer_pierres,
}
BEFORE = {}

if __name__ == "__main__":
    C.main(BUILDERS, BEFORE)
