# Aperçus de mise au point des zombies (rendu EEVEE, lumière neutre) :
# corps entier de trois quarts, de face, de profil et gros plan du visage,
# assemblés en une planche PNG.
import bpy, math, os
from mathutils import Vector

VIEWS = [
    # (position caméra, cible, focale)
    ((1.7, -3.3, 1.3), (0, 0, 0.93), 50),
    ((0.0, -3.7, 1.0), (0, 0, 0.93), 50),
    ((3.7, 0.0, 1.0), (0, 0, 0.93), 50),
    ((0.28, -0.62, 1.8), (0, -0.02, 1.76), 60),
]


def _setup():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 600
    sc.render.film_transparent = False
    sc.world.color = (0.045, 0.045, 0.05)
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        sc.collection.objects.link(cam)
    for name, rot, energy in (("PreviewKey", (50, 0, 35), 3.5), ("PreviewFill", (70, 0, -140), 1.2)):
        lt = bpy.data.objects.get(name)
        if lt is None:
            lt = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
            sc.collection.objects.link(lt)
        lt.data.energy = energy
        lt.rotation_euler = [math.radians(a) for a in rot]
    for o in sc.objects:
        if o.type == "LIGHT" and not o.name.startswith("Preview"):
            o.hide_render = True
    sc.camera = cam
    return sc, cam


def render(path):
    sc, cam = _setup()
    tiles = []
    base, _ = os.path.splitext(path)
    for i, (pos, target, lens) in enumerate(VIEWS):
        cam.location = Vector(pos)
        cam.rotation_euler = (Vector(target) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        tile = "%s_%d.png" % (base, i)
        sc.render.filepath = tile
        bpy.ops.render.render(write_still=True)
        tiles.append(tile)
    # Planche 2 x 2.
    imgs = [bpy.data.images.load(t, check_existing=False) for t in tiles]
    w = imgs[0].size[0]
    sheet = bpy.data.images.new("preview_sheet", w * 2, w * 2)
    px = [0.0] * (w * 2 * w * 2 * 4)
    for k, im in enumerate(imgs):
        src = list(im.pixels)
        ox, oy = (k % 2) * w, (1 - k // 2) * w
        for y in range(w):
            row = (oy + y) * w * 2 + ox
            px[row * 4:(row + w) * 4] = src[y * w * 4:(y + 1) * w * 4]
        bpy.data.images.remove(im)
        os.remove(tiles[k])
    sheet.pixels = px
    sheet.filepath_raw = path
    sheet.file_format = "PNG"
    sheet.save()
    bpy.data.images.remove(sheet)
    return path
