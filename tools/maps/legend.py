# Image de légende des cartes dessinées (docs/MAP_AUTHORING.md), rendue par
# Blender SANS FENÊTRE à partir de tools/maps/legende.json :
#   sh tools/blender.sh tools/maps/legend.py <sortie.png>
# Les textes sont rendus par Blender ; les carrés de couleur sont ensuite
# réécrits pixel par pixel : leurs valeurs RVB sont EXACTES (pipette de
# n'importe quel logiciel de dessin, ou copier-coller d'un carré).
import bpy, json, os, sys

args = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(args[0])
L = json.load(open(os.path.join(os.path.dirname(__file__), "legende.json"), encoding="utf-8"))
COLS = L["couleurs"]
PER_COL = 15
COL_W, ROW_H, TOP, LEFT, SW = 620, 62, 110, 30, 44
W = LEFT * 2 + COL_W * 3
H = TOP + ROW_H * PER_COL + 30

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "OBJECT"
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.resolution_percentage = 100
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("fond")
sc.world.color = (1, 1, 1)
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGB"

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = W
cam.location = (W / 2, -H / 2, 10)
sc.camera = cam


def text(body, x, y, size, box_w=0):
    """Texte noir, coin haut-gauche en (x, y) pixels depuis le haut-gauche de l'image."""
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = body
    cu.size = size
    cu.align_y = "TOP"
    if box_w:
        cu.text_boxes[0].width = box_w
    ob = bpy.data.objects.new("t", cu)
    ob.location = (x, -y, 0)
    ob.color = (0, 0, 0, 1)
    sc.collection.objects.link(ob)


text("Légende des cartes dessinées — 1 case (pixel) = %s m ; pipette sur les carrés : couleurs exactes" % str(L["echelle"]).replace(".", ","), LEFT, 22, 26)
text("Dessinez au crayon (sans lissage). Marqueur = petit carré ; objet mural = carré collé au mur ; porte / fenêtre = dans le mur. Voir docs/MAP_AUTHORING.md", LEFT, 62, 17)
swatches = []
for i, e in enumerate(COLS):
    col, row = divmod(i, PER_COL)
    x = LEFT + col * COL_W
    y = TOP + row * ROW_H
    swatches.append((x, y, e["rgb"]))
    text(e["nom"], x + SW + 14, y + 2, 17)
    text("%s   %s" % (" ".join(str(v) for v in e["rgb"]), e["role"]), x + SW + 14, y + 25, 12, COL_W - SW - 30)

sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)

# Carrés exacts (et un liseré noir pour voir le blanc), en réécrivant les pixels.
img = bpy.data.images.load(OUT)
px = list(img.pixels)
w, h = img.size


def put(x, y, rgb):
    i = ((h - 1 - y) * w + x) * 4
    px[i:i + 3] = [c / 255.0 for c in rgb]


for x0, y0, rgb in swatches:
    for yy in range(y0 - 1, y0 + SW + 1):
        for xx in range(x0 - 1, x0 + SW + 1):
            edge = yy in (y0 - 1, y0 + SW) or xx in (x0 - 1, x0 + SW)
            put(xx, yy, (0, 0, 0) if edge else rgb)
img.pixels[:] = px
img.filepath_raw = OUT
img.file_format = "PNG"
img.save()
print("[legende] %d couleurs -> %s" % (len(COLS), OUT))
