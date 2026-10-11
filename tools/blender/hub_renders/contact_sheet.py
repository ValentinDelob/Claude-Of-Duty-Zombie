# Planche de contrôle des rendus du hub (fond gris moyen, une case par PNG,
# nom de fichier dans l'ordre alphabétique) : jamais livrée dans le jeu.
#
#   sh tools/blender.sh tools/blender/hub_renders/contact_sheet.py --in DIR --out sheet.png [--cols 6] [--tile 280x140]
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "voxel"))
import voxel_lib as vx  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
src = os.path.abspath(args[args.index("--in") + 1])
out = os.path.abspath(args[args.index("--out") + 1])
cols = int(args[args.index("--cols") + 1]) if "--cols" in args else 6
tw, th = (int(v) for v in (args[args.index("--tile") + 1] if "--tile" in args else "280x140").split("x"))
files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
ims = [vx.fit(vx.load_png(os.path.join(src, f), bg=(0.42, 0.44, 0.47)), tw, th, bg=(0.42, 0.44, 0.47)) for f in files]
rows = [ims[i:i + cols] for i in range(0, len(ims), cols)]
vx.save_png(vx.sheet(rows, tw, th, gap=6, bg=(0.18, 0.19, 0.2)), out)
print("[contact_sheet]", out, ":", ", ".join(files))
