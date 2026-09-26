class_name MapPreview
extends RefCounted
## Plan « dossier classé » d'une carte, dessiné depuis sa grille ASCII :
## salles teintées par zone sur papier jauni, murs à l'encre, portes dorées,
## départ entouré de rouge. Sert à l'écran de sélection de carte.

const PX := 5  # pixels par cellule

static var _cache: Dictionary = {}


## Définition d'une carte du registre Game.MAP_SCRIPTS.
static func map_def(map_id: String) -> MapDef:
	if not Game.MAP_SCRIPTS.has(map_id):
		return null
	return load(Game.MAP_SCRIPTS[map_id]).new()


static func texture(map_id: String) -> Texture2D:
	if _cache.has(map_id):
		return _cache[map_id]
	var def := map_def(map_id)
	if def == null:
		return null
	var tex := ImageTexture.create_from_image(render(def))
	_cache[map_id] = tex
	return tex


static func render(def: MapDef) -> Image:
	var data := MapData.parse(def.rows)
	var w := data.width * PX
	var h := data.height * PX
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var paper := Color(0.62, 0.55, 0.42)
	var ink := Color(0.12, 0.08, 0.06)
	var noise := FastNoiseLite.new()
	noise.seed = hash(def.id)
	noise.frequency = 0.04
	var outside := BarricadeLayout.pocket_cells(BarricadeLayout.analyze(data))
	for y in h:
		for x in w:
			var c := Vector2i(x / PX, y / PX)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var col := paper * (0.78 + n * 0.25)
			col.a = 1.0
			if data.is_wall(c):
				col = ink
			elif data.is_floor(c) and not outside.has(c):
				var z := data.zone_at(c)
				var hue := fposmod(float(z.unicode_at(0)) * 0.13, 1.0) if z != "" else 0.0
				var tint := Color.from_hsv(hue, 0.28, 0.55)
				col = col.lerp(tint, 0.35)
				if z == "a":
					col = col.lerp(Color(0.62, 0.12, 0.08), 0.35)
				var key := String.chr(data.at(c))
				if def.doors.has(key):
					col = Color(0.85, 0.62, 0.18)
				elif key == "P":
					col = Color(0.75, 0.05, 0.04)
			img.set_pixel(x, y, col)
	return img
