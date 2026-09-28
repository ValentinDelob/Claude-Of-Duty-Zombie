class_name MapPreview
extends RefCounted
## Plan « dossier classé » d'une carte : salles teintées par zone sur papier
## jauni, murs à l'encre, portes dorées, départ entouré de rouge. Sert à
## l'écran de sélection de carte. Cartes ASCII : dessiné depuis la grille ;
## cartes en maillage : depuis les contours des salles de la description
## (vue de dessus, nord en haut, étages supérieurs par-dessus).

const PX := 5  # pixels par cellule (cartes ASCII)
const PX_MESH := 4  # pixels par mètre (cartes en maillage)
const PAPER := Color(0.62, 0.55, 0.42)
const INK := Color(0.12, 0.08, 0.06)
const DOOR := Color(0.85, 0.62, 0.18)
const START := Color(0.75, 0.05, 0.04)

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
	if def.rows.is_empty():
		var layout := def.create_layout() as MeshMapLayout
		if layout != null:
			return render_mesh(def, layout)
	var data := MapData.parse(def.rows)
	var w := data.width * PX
	var h := data.height * PX
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := _paper_noise(def)
	var outside := BarricadeLayout.pocket_cells(BarricadeLayout.analyze(data))
	for y in h:
		for x in w:
			var c := Vector2i(x / PX, y / PX)
			var col := _paper(noise, x, y)
			if data.is_wall(c):
				col = INK
			elif data.is_floor(c) and not outside.has(c):
				col = _zone_tint(col, data.zone_at(c))
				var key := String.chr(data.at(c))
				if def.doors.has(key):
					col = DOOR
				elif key == "P":
					col = START
			img.set_pixel(x, y, col)
	return img


## Plan d'une carte en maillage : salles (contours de la description, sans
## les poches extérieures des fenêtres) du plus bas au plus haut, murs à
## l'encre, portes payantes dorées, départ des joueurs en rouge.
static func render_mesh(def: MapDef, layout: MeshMapLayout) -> Image:
	var rooms := []
	for r in layout.data.get("rooms", []):
		if not String(r.id).begins_with("dehors") and r.get("outline", []).size() >= 3:
			rooms.append(r)
	if rooms.is_empty():
		return Image.create(PX_MESH, PX_MESH, false, Image.FORMAT_RGBA8)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in rooms:
		for p in r.outline:
			lo = lo.min(Vector2(p[0], p[1]))
			hi = hi.max(Vector2(p[0], p[1]))
	lo -= Vector2(2, 2)
	hi += Vector2(2, 2)
	var size := Vector2i(((hi - lo) * PX_MESH).ceil())
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var noise := _paper_noise(def)
	for y in size.y:
		for x in size.x:
			img.set_pixel(x, y, _paper(noise, x, y))
	var to_px := func(p: Vector2) -> Vector2: return (p - lo) * PX_MESH
	rooms.sort_custom(func(a, b): return _room_floor(a) < _room_floor(b))
	for r in rooms:
		var poly := PackedVector2Array()
		for p in r.outline:
			poly.append(to_px.call(Vector2(p[0], p[1])))
		var fy := _room_floor(r)
		var mid := Vector2.ZERO
		for p in r.outline:
			mid += Vector2(p[0], p[1])
		mid /= r.outline.size()
		var zone := layout.zone_at(Vector3(mid.x, fy + 0.1, mid.y))
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		# Étages : un peu plus clairs, comme un calque posé sur le plan.
		var lift := clampf(fy / 10.0, 0.0, 0.4)
		# Salle rectangulaire (le cas courant) : pas de test point / polygone.
		var rect := poly.size() == 4 and absf(absf(_area(poly)) - box.get_area()) < 1.0
		for y in range(maxi(int(box.position.y), 0), mini(int(box.end.y) + 1, size.y)):
			for x in range(maxi(int(box.position.x), 0), mini(int(box.end.x) + 1, size.x)):
				if rect or Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
					var col := _zone_tint(_paper(noise, x, y), zone)
					img.set_pixel(x, y, col.lerp(PAPER, lift))
		for i in poly.size():
			_line(img, poly[i], poly[(i + 1) % poly.size()], INK, 1)
	for d in layout.data.get("markers", {}).get("doors", []):
		var c: Vector2 = to_px.call(Vector2(d.p[0], d.p[2]))
		var along := Vector2(cos(float(d.get("yaw", 0.0))), -sin(float(d.get("yaw", 0.0))))
		var half := along * float(d.get("w", 2.0)) * 0.5 * PX_MESH
		_line(img, c - half, c + half, DOOR, 2)
	var spawns := layout.player_spawns()
	if not spawns.is_empty():
		var s: Vector2 = to_px.call(Vector2(spawns[0].x, spawns[0].z))
		for y in range(-8, 9):
			for x in range(-8, 9):
				var r2 := x * x + y * y
				if r2 <= 64 and r2 >= 30:
					var px := Vector2i(int(s.x) + x, int(s.y) + y)
					if px.x >= 0 and px.y >= 0 and px.x < size.x and px.y < size.y:
						img.set_pixel(px.x, px.y, START)
	return img


## Aire signée d'un polygone (formule du lacet).
static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _room_floor(r: Dictionary) -> float:
	if r.has("floor") and r.floor != null:
		return float(r.floor)
	# Salle en pente : hauteur moyenne des points de la pente.
	var s: Array = r.get("slope", [])
	var sum := 0.0
	for p in s:
		sum += float(p[1])
	return sum / maxf(s.size(), 1)


static func _paper_noise(def: MapDef) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = hash(def.id)
	noise.frequency = 0.04
	return noise


static func _paper(noise: FastNoiseLite, x: int, y: int) -> Color:
	var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
	var col := PAPER * (0.78 + n * 0.25)
	col.a = 1.0
	return col


static func _zone_tint(col: Color, z: String) -> Color:
	var hue := fposmod(float(z.unicode_at(0)) * 0.13, 1.0) if z != "" else 0.0
	col = col.lerp(Color.from_hsv(hue, 0.28, 0.55), 0.35)
	if z == "a":
		col = col.lerp(Color(0.62, 0.12, 0.08), 0.35)
	return col


## Trait d'épaisseur `width` pixels entre deux points (en pixels).
static func _line(img: Image, a: Vector2, b: Vector2, col: Color, width: int) -> void:
	var steps := maxi(int(a.distance_to(b)), 1)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for oy in width:
			for ox in width:
				var x := int(p.x) + ox
				var y := int(p.y) + oy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)
