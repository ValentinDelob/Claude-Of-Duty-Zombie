class_name MapRaster
extends RefCounted
## Carte de l'éditeur (EditorMap) -> grille du validateur (MapValidator) :
## une case de 0,5 m centrée sur chaque multiple de 0,5 m (MapGeom), par étage.
##   - pièce : les cases que traverse son contour sont des MURS, celles dont le
##     centre est à l'intérieur son SOL (zone de la pièce) ; deux pièces collées
##     partagent les cases de leur bord commun : un seul mur mitoyen ;
##   - pièce « double hauteur » : à l'étage du dessus, son contour reste un mur
##     et son intérieur un VIDE (trémie) ; une pièce posée au-dessus forme une
##     mezzanine (ses bords au-dessus du vide ont un garde-corps) ;
##   - ouvertures : les cases du mur commun (porte, débris, passage) ou
##     extérieur (fenêtre, 1 m) sur la largeur de l'ouverture ;
##   - piliers, murs libres, décor : cases pleines ; escalier : cases de marches
##     et vide au-dessus ; objets : leurs cases (emprise le long du mur ou au sol).
## Zones : la zone de départ devient « a » (MapLayout.start_zone), les autres
## « b », « c »... dans l'ordre de zones.json.

const K := MapValidator.K
## Cases de marge au-delà de la carte (cours des fenêtres).
const MARGIN := 8
## Clés de texture d'une pièce (pieces.json) -> partie (MapValidator.room_surfaces).
const ROOM_SURFACES := {"surface_sol": "sol", "surface_murs": "murs", "surface_plafond": "plafond"}

var doc: EditorMap
var v: MapValidator
## Zone de l'éditeur -> lettre du jeu.
var letters: Dictionary = {}
## Élément de l'éditeur -> [étage, cases] (dessin, clic sur un problème).
var cells_of: Dictionary = {}


static func build(d: EditorMap) -> MapRaster:
	var r := MapRaster.new()
	r.doc = d
	r._build()
	return r


## Lettre de jeu de la n-ième zone (0 -> a, 25 -> z, 26 -> za...).
static func letter(n: int) -> String:
	if n < 26:
		return String.chr(97 + n)
	return "z" + letter(n - 26)


func _build() -> void:
	v = MapValidator.new()
	# Format 10 : prefabs de la carte connus du catalogue (fil principal ; un
	# fil de travail lit ceux mis en place avant son lancement).
	doc.activate_prefabs()
	v.map_models = doc.models
	var c: Dictionary = doc.carte
	v.id = doc.id()
	v.display_name = doc.display_name()
	var desc: Dictionary = c.get("description", {})
	v.description = Lang.t(String(desc.get("fr", "")), String(desc.get("en", desc.get("fr", ""))))
	v.music = String(c.get("musique", "ambience_bunker"))
	v.door_height = float(c.get("hauteur_portes", MapValidator.DOOR_HEIGHT))
	v.lamps_auto = bool(c.get("lampes_auto", true))
	_zones()
	# Textures propres aux pièces (surface_sol, surface_murs, surface_plafond).
	for p in doc.pieces:
		var s := {}
		for key in ROOM_SURFACES:
			if WorldLook.SURFACES.has(String(p.get(key, ""))):
				s[ROOM_SURFACES[key]] = String(p[key])
		if not s.is_empty():
			v.room_surfaces[String(p.id)] = s
	# Variantes d'aspect (format 5) : seulement celles admises et autres que
	# l'aspect par défaut (une carte sans variante : description inchangée).
	for o in doc.ouvertures + doc.objets:
		if o.has("variante"):
			var va := MapCatalog.variant_of(o)
			if va != MapCatalog.default_variant(String(o.get("type", ""))):
				v.variants[String(o.get("id", ""))] = va
	# Étages.
	var n := doc.floor_count()
	for k in n:
		var f := MapValidator.Floor.new()
		f.index = k
		f.sol = doc.floor_sol(k)
		f.plafond = f.sol + doc.floor_height(k)
		v.floors.append(f)
	# Taille de la grille : tout ce qui est posé, plus la marge.
	var hi := Vector2(10, 10)
	var neg := false
	for p in doc.pieces:
		for pt in p.get("contour", []):
			hi = hi.max(MapGeom.v2(pt))
			neg = neg or float(pt[0]) < -0.001 or float(pt[1]) < -0.001
	for o in doc.objets + doc.ouvertures:
		for key in ["position", "a", "b"]:
			if o.has(key):
				hi = hi.max(MapGeom.v2(o[key]))
				neg = neg or float(o[key][0]) < -0.001 or float(o[key][1]) < -0.001
		if o.has("rect"):
			hi = hi.max(MapGeom.rect_of(o.rect).end)
			if MapGeom.rot_of(o) != 0:
				var rb := MapGeom.bbox(rect_poly(o))
				hi = hi.max(rb.end)
				neg = neg or rb.position.x < -0.001 or rb.position.y < -0.001
		if o.get("sommets") is Array:
			# Barrière invisible en polygone (format 9).
			var sb := MapGeom.bbox(clip_poly(o))
			hi = hi.max(sb.end)
			neg = neg or sb.position.x < -0.001 or sb.position.y < -0.001
		if String(o.get("type", "")) == "mur_courbe":
			var ab := MapGeom.bbox(MapShapes.wall_arc(o))
			hi = hi.max(ab.end)
			neg = neg or ab.position.x < -0.001 or ab.position.y < -0.001
	if neg:
		_err("un élément est hors du terrain : les coordonnées x et y doivent être positives", "an element is off the board: x and y coordinates must be positive")
	var w := ceili(hi.x / MapGeom.CELL) + MARGIN + 1
	var h := ceili(hi.y / MapGeom.CELL) + MARGIN + 1
	for f in v.floors:
		f.setup(w, h)
		v.oblique_walls.append([])
		v.diag_cells.append({})
		v.room_polys.append([])
	for k in n:
		_floor(k)


func _err(fr: String, en: String, k := -1, cells: Array = []) -> void:
	v._msg("erreur", fr, en, k, cells)


func _zones() -> void:
	var order := []
	if not doc.zone(doc.depart).is_empty():
		order.append(doc.zone(doc.depart))
	for z in doc.zones:
		if String(z.id) != doc.depart:
			order.append(z)
	for i in order.size():
		var z: Dictionary = order[i]
		var l := letter(i)
		letters[String(z.id)] = l
		var nm: Dictionary = z.get("nom", {})
		var fr := String(nm.get("fr", z.id))
		var en := String(nm.get("en", fr))
		v.zone_label[l] = [fr, en]
		v.zone_names[l] = Lang.t(fr, en)
		if z.has("sol"):
			v.floor_mats[l] = String(z.sol)
		if z.has("murs"):
			v.wall_mats[l] = String(z.murs)
		if z.has("plafond"):
			v.ceil_mats[l] = String(z.plafond)
	# Pièce sans zone connue : sa propre zone (le nom de la pièce).
	for p in doc.pieces:
		var zid := String(p.get("zone", ""))
		if not letters.has(zid):
			var l := letter(letters.size())
			letters[zid if zid != "" else "_" + String(p.id)] = l
			v.zone_label[l] = [String(p.get("nom", p.id)), String(p.get("nom", p.id))]
			v.zone_names[l] = String(p.get("nom", p.id))


func zone_letter(p: Dictionary) -> String:
	var zid := String(p.get("zone", ""))
	return letters.get(zid if zid != "" else "_" + String(p.id), "a")


func _ceil_of(p: Dictionary, k: int) -> float:
	return doc.floor_sol(k) + float(p.get("plafond", doc.floor_height(k)))


## Cases d'un côté de pièce : celles que traverse le trait (côté droit sur la
## grille) ou celles que coupe le mur de 0,5 m (côté en biais ou tracé hors de
## la grille : marquage prudent).
static func edge_cells(a: Vector2, b: Vector2) -> Array:
	if MapGeom.is_grid_seg(a, b):
		return MapGeom.segment_cells(a, b)
	return MapGeom.slab_cells(a, b, MapGeom.WALL_HALF)


# ------------------------------------------------------------------ rectangles tournés, décor

## Pilier, escalier ou piège construit sur la grille (pas de rotation, bords
## sur la grille de 0,5 m) ? Sinon : vraie géométrie (rectangle tourné).
static func rect_on_grid(o: Dictionary) -> bool:
	return MapGeom.rot_of(o) == 0 and MapGeom.rect_on_grid(MapGeom.rect_of(o.get("rect", [0, 0, 0, 0])))


## Contour (sur le trait) d'un pilier, escalier ou piège, rotation comprise.
static func rect_poly(o: Dictionary) -> PackedVector2Array:
	var r := MapGeom.rect_of(o.get("rect", [0, 0, 0, 0]))
	return MapGeom.rot_rect_poly(r.get_center(), r.size, MapGeom.rot_of(o))


## Contour (m) d'une barrière invisible : ses « sommets » (format 9), sinon
## le rectangle tourné d'une barrière d'avant (« rect », « rot »).
static func clip_poly(o: Dictionary) -> PackedVector2Array:
	var s: Variant = o.get("sommets")
	if s is Array:
		return MapGeom.poly(s)
	return rect_poly(o)


## Cases intérieures d'un escalier ou d'un piège (marches, zone électrifiée) :
## centres strictement dans le rectangle (tourné).
static func rect_inner_cells(o: Dictionary) -> Array:
	if rect_on_grid(o):
		return MapGeom.rect_cells_inside(MapGeom.rect_of(o.rect))
	return MapGeom.poly_cells(rect_poly(o))


## Repère d'un escalier posé (m, plan de l'éditeur) : centre, taille,
## rotation, direction de montée (`monte` tourné), longueur le long de la
## montée et largeur en travers (rectangle avant rotation).
static func stair_frame(o: Dictionary) -> Dictionary:
	var r := MapGeom.rect_of(o.get("rect", [0, 0, 0, 0]))
	var rot := MapGeom.rot_of(o)
	var m := String(o.get("monte", "n"))
	var along_x := m == "e" or m == "o"
	return {"center": r.get_center(), "size": r.size, "rot": rot, "up": MapGeom.dir_vec(m).rotated(deg_to_rad(rot)),
		"length": r.size.x if along_x else r.size.y, "width": r.size.y if along_x else r.size.x}


## Plan StairGen d'un escalier posé, dans le plan de l'éditeur (x, z = x, y
## en mètres ; y0 / y1 : sols du bas et du haut). Son emprise : le rectangle
## tracé en retrait de 0,25 m (le tracé est « sur le trait », comme un mur :
## les marches occupent ses cases intérieures, MapGeom.rect_cells_inside).
static func stair_plan(o: Dictionary, y0: float, y1: float) -> Dictionary:
	return StairGen.plan(stair_spec(o, y0, y1))


## Entrée StairGen (sans décalage du monde) d'un escalier posé : voir stair_plan.
static func stair_spec(o: Dictionary, y0: float, y1: float) -> Dictionary:
	var fr := stair_frame(o)
	var opts := MapCatalog.stair_layout_opts(o)
	var kind := String(opts.get("kind", StairGen.DEFAULT_KIND))
	opts.erase("kind")
	var inset := MapGeom.WALL_HALF * 2.0
	return StairGen.spec(fr.center, fr.up, maxf(float(fr.length) - inset, 0.5), maxf(float(fr.width) - inset, 0.5), y0, y1, kind, opts)


## Cases d'un escalier (marches et paliers) : tout le rectangle, sauf l'escalier
## en L (ses deux volées et le palier d'angle ; le coin libre reste du sol).
static func stair_cells(o: Dictionary) -> Array:
	if MapCatalog.stair_kind(o) != "quart":
		return rect_inner_cells(o)
	var pl := stair_plan(o, 0.0, 3.5)
	var seen := {}
	var out := []
	for poly: PackedVector2Array in pl.polys:
		for c in MapGeom.poly_cells(poly, false):
			if not seen.has(c):
				seen[c] = true
				out.append(c)
	return out


## Cases d'une barrière invisible : celles dont le centre est dans le
## rectangle (tourné) pris demi-ouvert dans son repère ([x0, x1[ × [y0, y1[) :
## autant de cases que de surface, même pour une barrière de 0,5 m posée sur
## la grille (une rangée de cases, pas deux).
static func clip_cells(o: Dictionary) -> Array:
	if o.get("sommets") is Array:
		# Format 9 : cases dont le centre, poussé d'un millimètre vers le
		# sud-est, est dans le polygone : un côté droit sur la grille compte
		# comme le bord [x0, x1[ d'un rectangle d'avant (barrière de 0,5 m sur
		# la grille : une rangée de cases). Une barrière plus mince qu'une case
		# peut n'en couvrir aucune : le jeu la construit quand même, à sa forme.
		var poly := clip_poly(o)
		var pb := MapGeom.bbox(poly)
		var cells := []
		for j in range(floori(pb.position.y / MapGeom.CELL) - 1, ceili(pb.end.y / MapGeom.CELL) + 2):
			for i in range(floori(pb.position.x / MapGeom.CELL) - 1, ceili(pb.end.x / MapGeom.CELL) + 2):
				if MapGeom.contains(poly, MapGeom.cell_center(Vector2i(i, j)) + Vector2(0.001, 0.0007)):
					cells.append(Vector2i(i, j))
		return cells
	var r := MapGeom.rect_of(o.get("rect", [0, 0, 0, 0]))
	var c := r.get_center()
	var h := r.size * 0.5
	var rot := deg_to_rad(MapGeom.rot_of(o))
	var bb := MapGeom.bbox(rect_poly(o))
	var out := []
	for j in range(floori(bb.position.y / MapGeom.CELL) - 1, ceili(bb.end.y / MapGeom.CELL) + 2):
		for i in range(floori(bb.position.x / MapGeom.CELL) - 1, ceili(bb.end.x / MapGeom.CELL) + 2):
			var q := (MapGeom.cell_center(Vector2i(i, j)) - c).rotated(-rot)
			if q.x >= -h.x - 0.001 and q.x < h.x - 0.001 and q.y >= -h.y - 0.001 and q.y < h.y - 0.001:
				out.append(Vector2i(i, j))
	return out


## Pavé d'un pilier hors de la grille (tourné) : mur oblique de l'épaisseur du
## pilier, contour sur le trait (0,25 m de mur de chaque côté, comme une pièce).
static func pillar_box(o: Dictionary) -> Dictionary:
	var r := MapGeom.rect_of(o.rect)
	var c := r.get_center()
	var u := Vector2(1, 0).rotated(deg_to_rad(MapGeom.rot_of(o)))
	var hl := r.size.x * 0.5 + MapGeom.WALL_HALF
	return {"a": c - u * hl, "b": c + u * hl, "t": u, "n": Vector2(-u.y, u.x), "half": r.size.y * 0.5 + MapGeom.WALL_HALF}


## Emprise au sol (m) d'un décor ou d'un luminaire posé au sol, rotation comprise.
static func floor_poly(o: Dictionary) -> PackedVector2Array:
	if String(o.get("type", "")) == "effet":
		return MapRules.effect_poly(o)
	var it := MapCatalog.item_for(o)
	var fp: Array = it.get("fp", [1, 1])
	var sz := Vector2(float(fp[0]), float(fp[1] if it.get("rotates", false) else fp[0])) * MapGeom.CELL
	return MapGeom.rot_rect_poly(MapGeom.v2(o.get("position", [0, 0])), sz, MapGeom.rot_of(o))


## Rotation « au degré près » (pas un quart de tour) ?
static func free_rot(o: Dictionary) -> bool:
	return MapGeom.rot_of(o) % 90 != 0


## Contour -> [cases du bord (dictionnaire), cases intérieures (tableau)].
static func room_cells(poly: PackedVector2Array) -> Array:
	var border := {}
	for i in poly.size():
		for c in edge_cells(poly[i], poly[(i + 1) % poly.size()]):
			border[c] = true
	var inner := []
	var bb := MapGeom.bbox(poly)
	for j in range(floori(bb.position.y / MapGeom.CELL), ceili(bb.end.y / MapGeom.CELL) + 1):
		for i in range(floori(bb.position.x / MapGeom.CELL), ceili(bb.end.x / MapGeom.CELL) + 1):
			var c := Vector2i(i, j)
			if not border.has(c) and Geometry2D.is_point_in_polygon(MapGeom.cell_center(c), poly):
				inner.append(c)
	return [border, inner]


func _floor(k: int) -> void:
	var f := v.floors[k]
	var ceil_up := f.sol + doc.floor_height(k)
	# Cases des murs droits (côtés droits, piliers, murs libres droits) : elles
	# restent des blocs de la grille même si un mur en biais les coupe aussi.
	_axis = {}
	_diag_pass = {}
	_grid_edges = []
	# Côtés en biais de cet étage (fusionnés en murs obliques après (b)).
	var raw := []
	var void_polys := []
	# (a) Pièces à double hauteur de l'étage du dessous : vide et murs qui montent.
	var voids := {}   # case -> true (intérieur d'une double hauteur)
	if k > 0:
		for p in doc.rooms_on(k - 1):
			if not p.get("double_hauteur", false):
				continue
			var poly := doc.room_poly(p)
			void_polys.append(poly)
			_edges(poly, String(p.id), false, raw)
			var rc := room_cells(poly)
			for c in rc[1]:
				f.put(c, K.TREMIE, "tremie")
				f.ceil[c.y * f.w + c.x] = ceil_up
				voids[c] = true
			for c in rc[0]:
				f.put(c, K.MUR, "mur")
				f.ceil[c.y * f.w + c.x] = ceil_up
		# Piliers et murs d'une double hauteur : jusqu'en haut.
		for o in doc.objects_on(k - 1):
			if String(o.type) in ["pilier", "mur", "mur_courbe"]:
				var cells := _obstacle_cells(o)
				var up := false
				for c in cells:
					if voids.has(c):
						f.put(c, K.MUR, "mur")
						up = true
				if up:
					_obstacle_record(k, o, cells)
	# (b) Pièces de cet étage.
	var inner_of := {}
	var border_of := {}
	for p in doc.rooms_on(k):
		var poly := doc.room_poly(p)
		_edges(poly, String(p.id), true, raw)
		var rc := room_cells(poly)
		var z := zone_letter(p)
		v.room_zone[String(p.id)] = z
		var ce := _ceil_of(p, k)
		v.room_polys[k].append({"id": String(p.id), "poly": poly, "zone": z, "ceil": ce})
		# Plafond de la pièce dans ses bornes (les mêmes que le panneau et le
		# contrôle des cartes reçues, MapVertical.ROOM_CEILING).
		if p.has("plafond"):
			var pv: Variant = p.plafond
			if not ((pv is float or pv is int) and float(pv) >= MapVertical.ROOM_CEILING[0] - 0.001 and float(pv) <= MapVertical.ROOM_CEILING[1] + 0.001):
				_err("pièce « %s » : plafond hors des bornes (2,8 à 9 m)" % p.get("nom", p.id), "room \"%s\": ceiling out of bounds (2.8 to 9 m)" % p.get("nom", p.id), k)
		var own := []
		for c in rc[1]:
			if inner_of.has(c):
				_err("les pièces « %s » et « %s » se chevauchent" % [p.get("nom", p.id), inner_of[c].get("nom", "")],
					"rooms \"%s\" and \"%s\" overlap" % [p.get("nom", p.id), inner_of[c].get("nom", "")], k, [c])
				break
			inner_of[c] = p
		for c in rc[1]:
			if f.at(c) == K.MUR and f.key_at(c) == "mur" and k > 0 and not voids.has(c):
				continue   # mur d'une double hauteur : il reste
			f.put(c, K.SOL, "zone", z)
			f.ceil[c.y * f.w + c.x] = ce
			f.room[c.y * f.w + c.x] = String(p.id)
			own.append(c)
		for c in rc[0]:
			border_of.get_or_add(c, []).append(p)
		cells_of[String(p.id)] = [k, own]
	for c in border_of:
		var list: Array = border_of[c]
		var p: Dictionary = list[0]
		var i: int = c.y * f.w + c.x
		if not f.inside(c):
			continue
		if list.size() == 1 and voids.has(c) and not inner_of.has(c):
			# Bord d'une mezzanine au-dessus du vide : plancher (garde-corps).
			f.put(c, K.SOL, "zone", zone_letter(p))
			f.ceil[i] = _ceil_of(p, k)
			f.room[i] = String(p.id)
			continue
		if inner_of.has(c):
			continue
		f.put(c, K.MUR, "mur")
		var ce := 0.0
		for q in list:
			ce = maxf(ce, _ceil_of(q, k))
		f.ceil[i] = maxf(f.ceil[i], ce)
	# Murs en biais : côtés obliques fusionnés (un seul mur mitoyen), pièce de
	# chaque côté.
	v.oblique_walls[k].append_array(_merge_obliques(raw, void_polys))
	# (c) Escaliers de l'étage du dessous : vide au-dessus des marches.
	if k > 0:
		for o in doc.objects_on(k - 1):
			if String(o.type) == "escalier":
				for c in stair_cells(o):
					f.put(c, K.TREMIE, "tremie")
					f.ceil[c.y * f.w + c.x] = ceil_up
	# (d) Ouvertures.
	for o in doc.openings_on(k):
		_opening(f, o)
	# (e) Piliers, murs libres, décor.
	for o in doc.objects_on(k):
		match String(o.type):
			"pilier", "mur", "mur_courbe":
				var cells := _obstacle_cells(o)
				for c in cells:
					f.put(c, K.MUR, "mur")
				_obstacle_record(k, o, cells)
				cells_of[String(o.id)] = [k, cells]
			"caisse", "baril":
				var fp := MapCatalog.footprint(o)
				var cells := _square(o, fp.x)
				var key := "decor#" + String(o.id)
				# Posé librement (format 7) : contre un mur, à moitié dedans, au
				# centimètre. Seules ses cases de sol deviennent pleines : un mur
				# qu'il touche reste un mur (jamais de trou), et son bloc suit sa
				# vraie place (pas les cases arrondies).
				var in_wall := false
				for c in cells:
					if f.at(c) == K.SOL:
						f.put(c, K.MUR, key)
					else:
						in_wall = true
				v.eid_of[key] = String(o.id)
				v.decor.append({"floor": k, "rect": MapValidator._bbox(cells), "box": MapRules.footprint_rect(o), "in_wall": in_wall,
					"h": 1.0 if o.type == "caisse" else 0.9, "mat": "crate" if o.type == "caisse" else "barrel", "eid": String(o.id)})
				cells_of[String(o.id)] = [k, cells]
			"prefab", "luminaire":
				# Décor posé : ses cases bloquent le passage (validateur, trajets)
				# sauf s'il ne bloque pas ; sa géométrie vient du jeu (props).
				var cells := floor_cells(o) if MapCatalog.light_mount(o) != "mur" else []
				if String(o.type) == "prefab":
					if MapCatalog.def_of(o).is_empty():
						_err("décor inconnu « %s »" % o.get("prefab", ""), "unknown prop \"%s\"" % o.get("prefab", ""), k)
						continue
					var pr := {"floor": k, "prefab": String(o.prefab), "center": MapGeom.v2(o.position),
						"rot": posmod(int(o.get("rot", 0)), 360), "eid": String(o.id)}
					# Format 11 : décor mural (sur la face du mur, tourné vers la pièce,
					# à sa hauteur) ou accroché au plafond.
					var pm := MapCatalog.light_mount(o)
					if pm == "mur":
						var dv := MapGeom.item_wall_dir(o) if MapGeom.item_oblique(o) else MapGeom.dir_vec(_cardinal(o))
						pr["mount"] = "mur"
						pr["center"] = MapGeom.v2(o.position) - dv * MapGeom.WALL_HALF
						pr["wall"] = dv
						pr["y"] = MapCatalog.wall_light_height(o)
						cells = wall_item_cells(o)
					elif pm == "plafond":
						pr["mount"] = "plafond"
						# Format 12 : descente sous le plafond.
						pr["descente"] = MapVertical.descente(o)
					else:
						# Format 12 : hauteur de pose (posé sur un autre décor).
						pr["y"] = MapVertical.decor_z(o)
					v.props.append(pr)
				if MapCatalog.blocking(o) != "non" and not cells.is_empty():
					var key := "decor#" + String(o.id)
					for c in cells:
						if f.at(c) == K.SOL:
							f.put(c, K.MUR, key)
					v.eid_of[key] = String(o.id)
				cells_of[String(o.id)] = [k, cells]
	# (f) Escaliers de cet étage (tournés : vraie géométrie, MapValidator.diag_stairs).
	for o in doc.objects_on(k):
		if String(o.type) == "escalier":
			var key := "escalier#" + String(o.id)
			var cells := stair_cells(o)
			for c in cells:
				f.put(c, K.ESCALIER, key, f.zone_of(c))
			v.eid_of[key] = String(o.id)
			cells_of[String(o.id)] = [k, cells]
			# Type et réglages (format 6) : validateur (pente, largeur) et export.
			v.stair_opts[key] = MapCatalog.stair_layout_opts(o)
			var shaped := StairGen.is_shaped(MapCatalog.stair_kind(o))
			if shaped or not rect_on_grid(o):
				# Tourné, hors de la grille, ou en L / U / colimaçon (sortie ailleurs
				# qu'en face du pied) : vraie géométrie, sens de montée donné.
				var r := MapGeom.rect_of(o.rect)
				v.diag_stairs[key] = {"center": r.get_center(), "size": r.size, "rot": MapGeom.rot_of(o), "cells": cells, "floor": k,
					"up": MapGeom.dir_vec(String(o.get("monte", "n"))).rotated(deg_to_rad(MapGeom.rot_of(o))), "eid": String(o.id)}
				if shaped:
					v.diag_stairs[key]["shaped"] = true
					v.diag_stairs[key]["obj"] = o.duplicate(true)
	# (g) Objets muraux et au sol.
	for o in doc.objects_on(k):
		var t := String(o.type)
		var tool := MapCatalog.tool_of(o)
		if t == "lampe":
			var c := MapGeom.cell_of(MapGeom.v2(o.position))
			v.lamps_extra.append({"floor": k, "center": Vector2(c) + Vector2(0.5, 0.5)})
			cells_of[String(o.id)] = [k, [c]]
			continue
		if t == "luminaire":
			_light(k, o)
			continue
		if t == "effet":
			_effect(k, o)
			continue
		if t in ["caisse", "baril", "pilier", "mur", "mur_courbe", "escalier", "prefab", "bloc_invisible"]:
			continue
		var cells := []
		if tool == "wall_item":
			cells = wall_item_cells(o)
		elif t == "piege":
			cells = rect_inner_cells(o)
			if not rect_on_grid(o):
				# Zone tournée : le jeu électrifie le vrai rectangle (MapLayoutExport).
				var r := MapGeom.rect_of(o.rect)
				v.diag_traps[String(o.id)] = {"center": r.get_center(), "size": r.size, "rot": MapGeom.rot_of(o)}
		elif tool == "floor_item":
			cells = floor_cells(o)
		if cells.is_empty():
			continue
		var key := "%s#%s" % [MapCatalog.validator_key(o), o.id]
		var e := MapValidator.entry(key)
		var bad := cells.filter(func(c): return f.at(c) != K.SOL)
		if not bad.is_empty():
			var w := v._at(k, bad[0])
			if f.at(bad[0]) == K.MARQUEUR:
				_err("%s en %s : chevauche un autre objet" % [e.fr, w[0]], "%s at %s: overlaps another object" % [e.en, w[1]], k, bad)
			else:
				_err("%s en %s : doit être posé sur le sol d'une pièce (pas dans un mur ni dehors)" % [e.fr, w[0]],
					"%s at %s: must stand on a room floor (not in a wall nor outside)" % [e.en, w[1]], k, bad)
			continue
		for c in cells:
			f.put(c, K.MARQUEUR, key, f.zone_of(c))
		if tool == "wall_item" and MapGeom.item_oblique(o):
			v.diag_items[key] = {"p": MapGeom.v2(o.position), "wall": MapGeom.item_wall_dir(o), "eid": String(o.id)}
		elif tool == "wall_item":
			v.wall_hint[key] = MapGeom.DIRS.get(_cardinal(o), Vector2i(0, -1))
		v.eid_of[key] = String(o.id)
		cells_of[String(o.id)] = [k, cells]
	# (h) Barrières invisibles (format 9 : polygones posés n'importe où), après
	# tout le reste : seules leurs cases de SOL deviennent pleines (validateur,
	# trajets, comme un décor) ; un mur, un escalier ou un objet de jeu
	# qu'elles recouvrent garde sa case. Le jeu y pose une CollisionBox sans
	# maillage, à la forme exacte du polygone (MapLayoutExport._clips).
	for o in doc.objects_on(k):
		if String(o.type) != "bloc_invisible":
			continue
		var cells := clip_cells(o)
		var key := "decor#" + String(o.id)
		for c in cells:
			if f.inside(c) and f.at(c) == K.SOL:
				f.put(c, K.MUR, key)
		v.eid_of[key] = String(o.id)
		var poly := clip_poly(o)
		var bb := MapGeom.bbox(poly)
		var hv: Variant = o.get("hauteur", 0.0)
		v.clips.append({"floor": k, "poly": poly, "center": bb.get_center(), "size": bb.size,
			"h": clampf(float(hv), 0.0, MapCatalog.CLIP_HEIGHT[1]) if (hv is float or hv is int) and is_finite(float(hv)) else 0.0,
			"eid": String(o.id)})
		cells_of[String(o.id)] = [k, cells]
	_finish_diag(k)


## Cases coupées par un mur droit (pièces, piliers, murs libres droits) de
## l'étage en cours : elles restent des blocs de la grille.
var _axis: Dictionary = {}
## Cases d'un passage libre posé sur un mur en biais (sol, sans mur).
var _diag_pass: Dictionary = {}


## Direction (n, e, s, o) d'un objet mural posé contre un mur droit (l'angle,
## s'il est donné, l'emporte sur « mur »).
static func _cardinal(o: Dictionary) -> String:
	if o.has("angle"):
		return MapGeom.cardinal_of(MapGeom.item_wall_dir(o))
	return String(o.get("mur", "n"))


## Côtés d'un contour : droits sur la grille -> cases de la grille (_axis) ;
## en biais ou hors de la grille -> `raw` (fusionnés ensuite par
## _merge_obliques). `own` : pièce de cet étage (sinon contour d'une double
## hauteur de l'étage du dessous).
func _edges(poly: PackedVector2Array, rid: String, own: bool, raw: Array) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if MapGeom.is_grid_seg(a, b):
			for c in MapGeom.segment_cells(a, b):
				_axis[c] = true
			_grid_edges.append([a, b])
		else:
			raw.append({"a": a, "b": b, "room": rid, "poly": poly, "own": own})


## Côtés de pièce construits en blocs de la grille (étage en cours) : un mur
## oblique qui les longe (pièce tracée sans grille collée à une pièce de la
## grille) n'est pas construit une seconde fois.
var _grid_edges: Array = []


## Pilier, mur libre ou mur courbe de l'étage k : cases droites (_axis) ou
## mur oblique (vraie géométrie).
func _obstacle_record(k: int, o: Dictionary, cells: Array) -> void:
	var t0 := String(o.type)
	var rid := ""
	if t0 != "pilier" or not rect_on_grid(o):
		# Pièce de l'obstacle (texture de ses faces) : sous son milieu.
		var at := Vector2.ZERO
		match t0:
			"pilier":
				at = MapGeom.rect_of(o.rect).get_center()
			"mur_courbe":
				var arc := MapShapes.wall_arc(o)
				@warning_ignore("integer_division")
				at = arc[arc.size() / 2]
			_:
				at = (MapGeom.v2(o.a) + MapGeom.v2(o.b)) * 0.5
		rid = String(MapRules.room_at(doc, int(o.get("etage", 0)), at).get("id", ""))
	var half := float(o.get("epaisseur", 0.5)) * 0.5
	match t0:
		"pilier":
			if not rect_on_grid(o):
				var box := pillar_box(o)
				box.merge({"pos": rid, "neg": rid, "kind": "pilier", "eid": String(o.id)})
				v.oblique_walls[k].append(box)
				return
		"mur":
			var a := MapGeom.v2(o.a)
			var b := MapGeom.v2(o.b)
			if not MapGeom.is_grid_seg(a, b):
				var t := (b - a).normalized()
				v.oblique_walls[k].append({"a": a, "b": b, "t": t, "n": Vector2(-t.y, t.x), "half": half,
					"pos": rid, "neg": rid, "kind": "mur", "eid": String(o.id)})
				return
		"mur_courbe":
			for s in MapShapes.arc_segments(o):
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				if a.distance_to(b) < 0.01:
					continue
				var t := (b - a).normalized()
				v.oblique_walls[k].append({"a": a, "b": b, "t": t, "n": Vector2(-t.y, t.x), "half": half,
					"pos": rid, "neg": rid, "kind": "mur", "eid": String(o.id)})
			return
	for c in cells:
		_axis[c] = true


## Côtés en biais -> murs obliques : les côtés colinéaires qui se recouvrent
## (bord commun de deux pièces) ne font qu'UN mur, découpé là où la pièce
## d'un côté change ; pas de mur au bord d'une mezzanine au-dessus du vide
## (garde-corps).
func _merge_obliques(raw: Array, void_polys: Array) -> Array:
	var lines := {}
	var order := []   # lignes dans l'ordre de création (regroupement tolérant)
	for r in raw:
		var t: Vector2 = (r.b - r.a).normalized()
		if t.x < -MapGeom.EPS or (absf(t.x) <= MapGeom.EPS and t.y < 0.0):
			t = -t
		var n := Vector2(-t.y, t.x)
		# Côtés colinéaires à JOIN_TOL près (pièces collées sans grille) : la
		# même ligne, donc un seul mur mitoyen.
		var line: Dictionary = {}
		for l: Dictionary in order:
			var lt: Vector2 = l.t
			var ln: Vector2 = l.n
			if absf(t.dot(lt)) > 0.99985 and absf(Vector2(r.a).dot(ln) - float(l.off)) < MapGeom.JOIN_TOL \
					and absf(Vector2(r.b).dot(ln) - float(l.off)) < MapGeom.JOIN_TOL:
				line = l
				break
		if line.is_empty():
			var off := snappedf(Vector2(r.a).dot(n), 0.001)
			var key := "%.4f:%.4f:%.3f" % [t.x, t.y, off]
			while lines.has(key):
				key += "+"
			line = {"t": t, "n": n, "off": off, "spans": [], "key": key}
			lines[key] = line
			order.append(line)
		var lt2: Vector2 = line.t
		var ln2: Vector2 = line.n
		var s0: float = Vector2(r.a).dot(lt2)
		var s1: float = Vector2(r.b).dot(lt2)
		var mid: Vector2 = (r.a + r.b) * 0.5
		var side := 1 if MapGeom.contains(r.poly, mid + ln2 * 0.2) else -1
		line.spans.append([minf(s0, s1), maxf(s0, s1), String(r.room), side, bool(r.own)])
	var out := []
	var keys := lines.keys()
	keys.sort()
	for key in keys:
		var line: Dictionary = lines[key]
		var t: Vector2 = line.t
		var n: Vector2 = line.n
		var base: Vector2 = n * float(line.off)
		# Parties déjà construites en blocs de la grille (côté d'une pièce de la
		# grille sur la même ligne) : pas de second mur.
		var covered := []
		for g in _grid_edges:
			var ga: Vector2 = g[0]
			var gb: Vector2 = g[1]
			if absf((gb - ga).normalized().dot(t)) > 0.9998 and absf(ga.dot(n) - float(line.off)) < MapGeom.JOIN_TOL \
					and absf(gb.dot(n) - float(line.off)) < MapGeom.JOIN_TOL:
				covered.append([minf(ga.dot(t), gb.dot(t)), maxf(ga.dot(t), gb.dot(t))])
		var cuts := []
		for sp in line.spans:
			for s in [sp[0], sp[1]]:
				if not cuts.any(func(x): return absf(x - s) < 0.001):
					cuts.append(s)
		for cv in covered:
			for s in [cv[0], cv[1]]:
				if not cuts.any(func(x): return absf(x - s) < 0.001):
					cuts.append(s)
		cuts.sort()
		for i in cuts.size() - 1:
			var u: float = cuts[i]
			var w: float = cuts[i + 1]
			if w - u < 0.01:
				continue
			var mid_s := (u + w) * 0.5
			if covered.any(func(cv): return mid_s > float(cv[0]) - 0.001 and mid_s < float(cv[1]) + 0.001):
				continue
			var sides := {1: ["", false], -1: ["", false]}
			for sp in line.spans:
				if sp[0] <= u + 0.001 and sp[1] >= w - 0.001:
					var cur: Array = sides[sp[3]]
					if cur[0] == "" or (sp[4] and not cur[1]):
						sides[sp[3]] = [sp[2], sp[4]]
			var pos := String(sides[1][0])
			var neg := String(sides[-1][0])
			if pos == "" and neg == "":
				continue
			if (pos == "") != (neg == ""):
				var empty := n if pos == "" else -n
				var outside := base + t * ((u + w) * 0.5) + empty * 0.3
				if void_polys.any(func(vp): return MapGeom.strictly_inside(vp, outside)):
					continue
			var a := base + t * u
			var b := base + t * w
			if not out.is_empty():
				var last: Dictionary = out[-1]
				if last.kind == "piece" and last.b.distance_to(a) < 0.001 and last.t.is_equal_approx(t) and last.pos == pos and last.neg == neg:
					last.b = b
					continue
			out.append({"a": a, "b": b, "t": t, "n": n, "half": MapGeom.WALL_HALF, "pos": pos, "neg": neg, "kind": "piece"})
	return out


## Mur oblique (côté de pièce) de l'étage k qui passe par `p` ({} sinon).
func oblique_at(k: int, p: Vector2) -> Dictionary:
	for w in v.oblique_walls[k]:
		if w.kind == "piece" and MapGeom.dist_to_segment(p, w.a, w.b) <= MapGeom.JOIN_TOL:
			return w
	return {}


## Fin d'un étage : cases des murs obliques qui ne sont pas des murs droits
## (le jeu les construit en vrais murs obliques, pas en blocs de la grille).
func _finish_diag(k: int) -> void:
	var f := v.floors[k]
	var dc: Dictionary = v.diag_cells[k]
	for w in v.oblique_walls[k]:
		for c in MapGeom.slab_cells(w.a, w.b, w.half):
			if _axis.has(c) or not f.inside(c):
				continue
			var kd := f.at(c)
			var key := f.key_at(c)
			if (kd == K.MUR and key == "mur") or (kd in [K.PORTE, K.DEBRIS, K.FENETRE] and v.diag_open.has(key)) or (kd == K.SOL and _diag_pass.has(c)):
				dc[c] = true


## Luminaire posé -> lampe du jeu (v.lamps_extra) : position de la lumière en
## cases (comme les lampes historiques : case + 0,5), réglages bornés.
func _light(k: int, o: Dictionary) -> void:
	var d := MapCatalog.def_of(o)
	if d.is_empty():
		_err("luminaire inconnu « %s »" % o.get("luminaire", ""), "unknown light fixture \"%s\"" % o.get("luminaire", ""), k)
		return
	var p := MapGeom.v2(o.position)
	var mount := String(d.mount)
	var lim: Dictionary = MapCatalog.LIGHT_LIMITS
	var l := {"floor": k, "luminaire": String(o.luminaire), "mount": mount, "eid": String(o.id),
		"color": MapCatalog.light_color(o),
		"energy": clampf(float(o.get("intensite", d.intensite)), lim.intensite[0], lim.intensite[1]),
		"range": clampf(float(o.get("portee", d.portee)), lim.portee[0], lim.portee[1]),
		"power": bool(o.get("courant", d.courant)), "flicker": bool(o.get("vacille", d.vacille)),
		"yaw": -deg_to_rad(posmod(int(o.get("rot", 0)), 360)), "boxes": d.get("boxes", []),
		"barrier": MapCatalog.blocking(o) == "barriere"}
	var cells := []
	if mount == "mur":
		# Sur le trait du mur, face vers l'intérieur : la face du mur est à
		# 0,25 m du trait, côté pièce (mur en biais : selon son angle).
		var dv := MapGeom.item_wall_dir(o) if MapGeom.item_oblique(o) else MapGeom.dir_vec(_cardinal(o))
		var face := p - dv * MapGeom.CELL * 0.5
		l["center"] = face / MapGeom.CELL + Vector2(0.5, 0.5)
		l["wall"] = dv
		# Hauteur choisie (format 7 ; absente : celle du luminaire, 2 m).
		l["y"] = MapCatalog.wall_light_height(o)
		# Lacet : l'axe +z de l'applique (du mur vers la pièce) vers -dv.
		l["yaw"] = atan2(-dv.x, -dv.y)
		cells = wall_item_cells(o)
	else:
		l["center"] = p / MapGeom.CELL + Vector2(0.5, 0.5)
		cells = floor_cells(o)
		if mount == "sol":
			# Format 12 : « hauteur » choisie, sinon le dessus du meuble dessous.
			l["support"] = MapVertical.floor_light_base(doc, o)
		else:
			# Format 12 : descente sous le plafond (sinon `drop` du luminaire).
			l["descente"] = MapVertical.descente(o)
	v.lamps_extra.append(l)
	cells_of[String(o.id)] = [k, cells]


## Effet posé (format 10) -> v.effects : aucune case bloquée (ni collision,
## ni marqueur) ; mural : sur la face du mur, tourné vers la pièce.
func _effect(k: int, o: Dictionary) -> void:
	var d := MapCatalog.effect_def(o)
	if d.is_empty():
		_err("effet inconnu « %s »" % o.get("effet", ""), "unknown effect \"%s\"" % o.get("effet", ""), k)
		return
	var p := MapGeom.v2(o.position)
	var mount := String(d.mount)
	# Format 11 : zone (largeur, profondeur, hauteur en m) à la place de la taille.
	var e := {"floor": k, "effet": String(o.effet), "mount": mount, "eid": String(o.id), "center": p,
		"y": MapCatalog.effect_height(o), "yaw": -deg_to_rad(posmod(int(o.get("rot", 0)), 360)),
		"intensity": MapCatalog.effect_value(o, "intensite"), "zone": MapCatalog.effect_zone(o),
		"color": MapCatalog.effect_color(o).to_html(false) if MapCatalog.effect_tints(o) else "",
		"descente": MapVertical.descente(o) if mount == "plafond" else 0.0}
	var cells := []
	if mount == "mur":
		var dv := MapGeom.item_wall_dir(o) if MapGeom.item_oblique(o) else MapGeom.dir_vec(_cardinal(o))
		e["center"] = p - dv * MapGeom.WALL_HALF
		e["wall"] = dv
		# Axe +z de l'effet (du mur vers la pièce) vers -dv.
		e["yaw"] = atan2(-dv.x, -dv.y)
		cells = MapGeom.poly_cells(MapRules.effect_poly(o))
	else:
		cells = floor_cells(o)
	v.effects.append(e)
	cells_of[String(o.id)] = [k, cells]


## Cases d'un pilier (contour et intérieur), d'un mur libre (segment épais)
## ou d'un mur courbe (ses segments épais).
func _obstacle_cells(o: Dictionary) -> Array:
	if String(o.type) == "pilier":
		if rect_on_grid(o):
			return MapGeom.rect_cells_closed(MapGeom.rect_of(o.rect))
		# Pilier tourné ou hors de la grille : toutes les cases que touche son pavé.
		var box := pillar_box(o)
		return MapGeom.slab_cells(box.a, box.b, float(box.half))
	if String(o.type) == "mur_courbe":
		var all := {}
		for s in MapShapes.arc_segments(o):
			for c in MapGeom.slab_cells(s[0], s[1], float(o.get("epaisseur", 0.5)) * 0.5):
				all[c] = true
		return all.keys()
	var a := MapGeom.v2(o.a)
	var b := MapGeom.v2(o.b)
	if not MapGeom.is_grid_seg(a, b):
		# Mur libre en biais ou hors de la grille : toutes les cases que coupe son épaisseur.
		return MapGeom.slab_cells(a, b, float(o.get("epaisseur", 0.5)) * 0.5)
	var cells := {}
	for c in MapGeom.segment_cells(a, b):
		cells[c] = true
	var half := (float(o.get("epaisseur", 0.5)) - MapGeom.CELL) * 0.5 + 0.01
	if half > 0.1:
		var bb := Rect2(a, Vector2.ZERO).expand(b).grow(half + MapGeom.CELL)
		for j in range(floori(bb.position.y / MapGeom.CELL), ceili(bb.end.y / MapGeom.CELL) + 1):
			for i in range(floori(bb.position.x / MapGeom.CELL), ceili(bb.end.x / MapGeom.CELL) + 1):
				if MapGeom.dist_to_segment(MapGeom.cell_center(Vector2i(i, j)), a, b) <= half:
					cells[Vector2i(i, j)] = true
	return cells.keys()


## Carré de n × n cases centré sur la position de l'objet.
static func _square(o: Dictionary, n: int) -> Array:
	return _block(o, Vector2i(n, n))


## Rectangle de n.x × n.y cases centré sur la position de l'objet.
static func _block(o: Dictionary, n: Vector2i) -> Array:
	var p := MapGeom.v2(o.position)
	var i0 := MapGeom.first_cell(p.x, n.x)
	var j0 := MapGeom.first_cell(p.y, n.y)
	var out := []
	for j in n.y:
		for i in n.x:
			out.append(Vector2i(i0 + i, j0 + j))
	return out


## Cases d'un objet au sol (rotation comprise : MapCatalog.floor_size ; tourné
## au degré près : cases dont le centre est dans l'emprise tournée).
static func floor_cells(o: Dictionary) -> Array:
	if (free_rot(o) and MapCatalog.rotates(o)) or String(o.get("type", "")) == "effet":
		return MapGeom.poly_cells(floor_poly(o))
	return _block(o, MapCatalog.floor_size(o))


## Cases d'un objet mural : la rangée collée au mur, sur sa largeur. La
## position est sur le trait du mur (centre de l'objet le long du mur).
static func wall_item_cells(o: Dictionary) -> Array:
	if MapGeom.item_oblique(o):
		return oblique_item_cells(o)
	var p := MapGeom.v2(o.position)
	var d: Vector2i = MapGeom.DIRS.get(_cardinal(o), Vector2i(0, -1))
	var n := MapCatalog.footprint(o).x
	var out := []
	if d.x == 0:
		var j := roundi(p.y / MapGeom.CELL) - d.y
		var i0 := MapGeom.first_cell(p.x, n)
		for i in n:
			out.append(Vector2i(i0 + i, j))
	else:
		var i := roundi(p.x / MapGeom.CELL) - d.x
		var j0 := MapGeom.first_cell(p.y, n)
		for j in n:
			out.append(Vector2i(i, j0 + j))
	return out


## Cases d'un objet mural contre un mur EN BIAIS : celles dont le centre est
## dans son emprise tournée (MapRules.wall_item_poly), sauf les cases coupées
## par le mur ; au moins la case libre la plus proche de son milieu.
static func oblique_item_cells(o: Dictionary) -> Array:
	var poly := MapRules.wall_item_poly(o)
	var p := MapGeom.v2(o.position)
	var dv := MapGeom.item_wall_dir(o)
	var cut := MapGeom.WALL_HALF + (MapGeom.CELL * 0.5 - 0.02) * (absf(dv.x) + absf(dv.y))
	var out := []
	var best := Vector2i.ZERO
	var best_d := INF
	var mid := MapGeom.centroid(poly)
	var bb := MapGeom.bbox(poly).grow(MapGeom.CELL)
	for j in range(floori(bb.position.y / MapGeom.CELL), ceili(bb.end.y / MapGeom.CELL) + 1):
		for i in range(floori(bb.position.x / MapGeom.CELL), ceili(bb.end.x / MapGeom.CELL) + 1):
			var c := Vector2i(i, j)
			var cc := MapGeom.cell_center(c)
			if absf((cc - p).dot(dv)) <= cut or (cc - p).dot(dv) > 0.0:
				continue
			if MapGeom.contains(poly, cc):
				out.append(c)
			elif cc.distance_to(mid) < best_d:
				best_d = cc.distance_to(mid)
				best = c
	if out.is_empty():
		out.append(best)
	return out


## Cases d'une ouverture : sur le trait du mur, centrées sur sa position.
## `horizontal` : mur est-ouest (y constant).
static func opening_cells(o: Dictionary, horizontal: bool) -> Array:
	var p := MapGeom.v2(o.position)
	var n := maxi(1, roundi(MapRules.opening_width(o) / MapGeom.CELL))
	var out := []
	if horizontal:
		var j := roundi(p.y / MapGeom.CELL)
		var i0 := MapGeom.first_cell(p.x, n)
		for i in n:
			out.append(Vector2i(i0 + i, j))
	else:
		var i := roundi(p.x / MapGeom.CELL)
		var j0 := MapGeom.first_cell(p.y, n)
		for j in n:
			out.append(Vector2i(i, j0 + j))
	return out


## Sens du mur sous une ouverture : un bord de pièce de la grille (horizontal
## ou vertical, bouts sur la grille) qui passe par sa position. -1 : aucun
## (mur en biais ou hors de la grille : vrai mur oblique).
func opening_axis(o: Dictionary) -> int:
	var p := MapGeom.v2(o.position)
	for r in doc.rooms_on(int(o.get("etage", 0))):
		var poly := doc.room_poly(r)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if MapGeom.dist_to_segment(p, a, b) > 0.01 or not MapGeom.is_grid_seg(a, b):
				continue
			if absf(a.y - b.y) < MapGeom.EPS:
				return 1
			if absf(a.x - b.x) < MapGeom.EPS:
				return 0
	return -1


func _opening(f: MapValidator.Floor, o: Dictionary) -> void:
	var t := String(o.type)
	var axis := opening_axis(o)
	if axis < 0:
		var ow := oblique_at(f.index, MapGeom.v2(o.position))
		if not ow.is_empty():
			_opening_oblique(f, o, ow)
			return
	var cells := opening_cells(o, axis != 0)
	cells_of[String(o.id)] = [f.index, cells]
	if axis < 0:
		var w := v._at(f.index, cells[0])
		_err("ouverture en %s : elle doit être posée sur un mur d'une pièce" % w[0],
			"opening at %s: it must sit on a room wall" % w[1], f.index, cells)
		return
	var key := "%s#%s" % ["fenetre" if t == "fenetre" else "porte", o.id]
	v.eid_of[key] = String(o.id)
	match t:
		"fenetre":
			for c in cells:
				f.put(c, K.FENETRE, key)
		"passage":
			# Sol de la pièce au nord (ou à l'ouest) du mur, sinon de l'autre côté.
			var side := Vector2i(0, -1) if axis == 1 else Vector2i(-1, 0)
			var z := ""
			for c in cells:
				z = f.zone_of(c + side) if f.zone_of(c + side) != "" else z
			if z == "":
				for c in cells:
					z = f.zone_of(c - side) if f.zone_of(c - side) != "" else z
			for c in cells:
				f.put(c, K.SOL, "zone", z)
				var i: int = c.y * f.w + c.x
				if f.inside(c):
					f.ceil[i] = maxf(f.ceil_at(c + side), f.ceil_at(c - side))
		_:
			for c in cells:
				f.put(c, K.DEBRIS if t == "debris" else K.PORTE, key)
			v.door_info[key] = {"cost": 0 if t == "porte_courant" else int(o.get("prix", 1000)), "power": t == "porte_courant",
				"debris": t == "debris", "eid": String(o.id)}


## Ouverture sur un mur EN BIAIS : les cases que coupe le mur sur la largeur
## de l'ouverture (même marquage prudent que le mur) ; le validateur vérifie
## ses deux côtés (MapValidator._diag_opening), le jeu découpe le mur oblique.
func _opening_oblique(f: MapValidator.Floor, o: Dictionary, ow: Dictionary) -> void:
	var t := String(o.type)
	var p := MapGeom.v2(o.position)
	var dir: Vector2 = ow.t
	var w := maxi(1, roundi(MapRules.opening_width(o) / MapGeom.CELL)) * MapGeom.CELL
	var cells := MapGeom.slab_cells(p - dir * w * 0.5, p + dir * w * 0.5, float(ow.half)).filter(func(c): return f.inside(c) and not _axis.has(c))
	cells_of[String(o.id)] = [f.index, cells]
	if cells.is_empty():
		return
	var key := "%s#%s" % ["fenetre" if t == "fenetre" else "porte", o.id]
	v.eid_of[key] = String(o.id)
	v.diag_open[key] = {"p": p, "t": dir, "n": ow.n, "w": w, "half": float(ow.half), "type": t, "kind": MapCatalog.barricade_kind(o), "eid": String(o.id),
		"floor": f.index, "cells": cells}
	match t:
		"fenetre":
			for c in cells:
				f.put(c, K.FENETRE, key)
		"passage":
			# Sol de la pièce d'un côté du mur (sinon de l'autre), plafond le plus haut.
			var z := String(v.room_zone.get(String(ow.pos), "")) if ow.pos != "" else ""
			if z == "":
				z = String(v.room_zone.get(String(ow.neg), ""))
			var ce := 0.0
			for rid in [ow.pos, ow.neg]:
				var r := doc.find(String(rid))
				if not r.is_empty():
					ce = maxf(ce, _ceil_of(r, f.index))
			for c in cells:
				f.put(c, K.SOL, "zone", z)
				f.ceil[c.y * f.w + c.x] = maxf(f.ceil_at(c), ce)
				_diag_pass[c] = true
		_:
			for c in cells:
				f.put(c, K.DEBRIS if t == "debris" else K.PORTE, key)
			v.door_info[key] = {"cost": 0 if t == "porte_courant" else int(o.get("prix", 1000)), "power": t == "porte_courant",
				"debris": t == "debris", "eid": String(o.id)}
