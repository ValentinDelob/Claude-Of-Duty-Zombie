class_name MapElevationItems
extends RefCounted
## Boîtes 3D des éléments de la carte pour les élévations de l'éditeur
## (docs/EDITOR_VIEWS.md, § 3.2) : logique pure, sans dessin. Chaque élément
## devient un PRISME : un contour au sol (m, repère de l'éditeur) et une
## tranche d'altitude [z0, z1] (m, absolue), à sa vraie hauteur (plafond réel
## sous la dalle du dessus, double hauteur, portes de `hauteur_portes`,
## fenêtres de l'allège au linteau, escaliers d'un sol à l'autre, décor
## d'après `h`, luminaires et effets à leur hauteur de lumière...).
##
## Un élément de la liste : {id, kind, floor, poly (PackedVector2Array),
## z0, z1, col (Color), e (l'élément de la carte)} et selon le type :
##   room    zone, name, slab (la pièce a une dalle sous elle)
##   opening otype (porte, debris, porte_courant, passage, fenetre), price
##   stairs  up (direction de montée, Vector2), steps
##   point   z (hauteur de la lumière ou de l'effet), hook (altitude du
##           point d'accroche : plafond, sol ou meuble ; NAN : le mur)
## kind : room, pillar, wall, opening, stairs, trap, wobj (objet mural),
## fobj (objet au sol), decor, light, effect, clip.

const SILL := MapValidator.SILL
const LINTEL := MapValidator.LINTEL
## Objets muraux : [bas, haut] (m au-dessus du sol), d'après leur modèle en
## jeu (tableau d'arme à 1,45 m, boîte, machines).
const WALL_Z := {"atout": [0.0, 2.1], "arme": [1.1, 1.8], "grenades": [1.1, 1.8], "boite": [0.0, 1.0],
	"courant": [1.0, 1.8], "pap": [0.0, 1.9], "poste_central": [0.0, 2.0], "levier": [1.0, 1.6]}
## Objets au sol : hauteur (m).
const FLOOR_H := {"depart": 1.8, "apparition": 1.8, "teleporteur": 2.6, "arrivee": 0.15, "caisse": 1.0, "baril": 1.2, "boite": 1.0}
## Hauteur (m) de la zone électrifiée d'un piège.
const TRAP_H := 2.5
## Épaisseur (m) d'une ouverture dans son mur (vue de dessus).
const OPENING_DEPTH := 0.5


## Toutes les boîtes de la carte (`v` : grille du validateur de cette carte,
## MapRaster.build(doc).v, pour les plafonds réels).
static func build(doc: EditorMap, v: MapValidator) -> Array:
	var out := []
	if doc == null or v == null or v.floors.is_empty():
		return out
	for p in doc.pieces:
		var it := _room(doc, v, p)
		if not it.is_empty():
			out.append(it)
	for o in doc.ouvertures:
		var it := _opening(doc, v, o)
		if not it.is_empty():
			out.append(it)
	for o in doc.objets:
		var it := _object(doc, v, o)
		if not it.is_empty():
			out.append(it)
	return out


## Boîte d'un seul élément (pièce, ouverture ou objet) ; {} s'il n'en a pas.
static func item_of(doc: EditorMap, v: MapValidator, e: Dictionary) -> Dictionary:
	if doc == null or v == null or e.is_empty():
		return {}
	if e.has("contour"):
		return _room(doc, v, e)
	if String(e.get("type", "")) in MapRules.ouvertures_types():
		return _opening(doc, v, e)
	return _object(doc, v, e)


static func _floor_ok(v: MapValidator, k: int) -> bool:
	return k >= 0 and k < v.floors.size()


static func _sol(v: MapValidator, k: int) -> float:
	return v.floors[k].sol


## Pièce : du sol au plafond réel le plus haut de ses cases (pièce haute :
## jusqu'à son plafond, au-dessus du niveau suivant ; sous une dalle : son dessous).
static func _room(doc: EditorMap, v: MapValidator, p: Dictionary) -> Dictionary:
	var k := doc.level_of(p)
	if not _floor_ok(v, k):
		return {}
	var poly := doc.room_poly(p)
	if poly.size() < 3:
		return {}
	var top := room_top(doc, v, p)
	return {"id": String(p.id), "kind": "room", "floor": k, "poly": poly, "z0": _sol(v, k), "z1": top,
		"zone": String(p.get("zone", "")), "name": String(p.get("nom", "")), "slab": k > 0, "e": p}


## Plafond réel (m, absolu) d'une pièce : le plus haut de ses cases.
static func room_top(doc: EditorMap, v: MapValidator, p: Dictionary) -> float:
	var k := doc.level_of(p)
	var poly := doc.room_poly(p)
	var own := EditorMap.room_top(p)
	if k < 0:
		return own
	var top := -INF
	var cells: Array = MapRaster.room_cells(poly)[1]
	for c in cells:
		if v.floors[k].room_of(c) != String(p.id):
			continue
		top = maxf(top, float(MapVertical.ceil_at(v, k, c)[0]))
	if top == -INF:
		top = own
	return top


## Contour (m) d'une ouverture : sa largeur le long de son mur, l'épaisseur du mur en travers.
static func opening_poly(doc: EditorMap, o: Dictionary) -> PackedVector2Array:
	var k := doc.level_of(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var dir := Vector2.ZERO
	var best := 0.06
	for r in doc.rooms_on(k):
		var rp := doc.room_poly(r)
		for i in rp.size():
			var a := rp[i]
			var b := rp[(i + 1) % rp.size()]
			var d := MapGeom.dist_to_segment(p, a, b)
			if d < best and a.distance_to(b) > 0.01:
				best = d
				dir = (b - a).normalized()
	if dir == Vector2.ZERO:
		# Pas de pièce : d'après sa case (mur nord-sud si x est sur le trait).
		dir = Vector2(0, 1) if MapGeom.on_grid(p.x) and not MapGeom.on_grid(p.y) else Vector2(1, 0)
	var n := Vector2(-dir.y, dir.x) * OPENING_DEPTH * 0.5
	var w := MapRules.opening_width(o) * 0.5
	return PackedVector2Array([p - dir * w - n, p + dir * w - n, p + dir * w + n, p - dir * w + n])


## Porte, débris, porte du courant : de 0 à `hauteur_portes` ; fenêtre : de
## l'allège au linteau (porte à zombies : 2,1 m) ; passage : jusqu'au plafond.
static func _opening(doc: EditorMap, v: MapValidator, o: Dictionary) -> Dictionary:
	var k := doc.level_of(o)
	if not _floor_ok(v, k):
		return {}
	var t := String(o.get("type", ""))
	var sol := _sol(v, k)
	var z0 := sol
	var z1 := sol + v.door_height
	match t:
		"fenetre":
			if MapCatalog.barricade_kind(o) != "fenetre":
				z1 = sol + MapValidator.ZOMBIE_DOOR_TOP
			else:
				z0 = sol + SILL
				z1 = sol + LINTEL
		"passage":
			z1 = MapVertical.ceil_z(v, k, MapGeom.v2(o.position))
	var cols := {"porte": Color("FFAB00"), "porte_courant": Color("FFAB00"), "debris": Color("AB6626"), "fenetre": Color("1A73FF"), "passage": Color("0f0f11")}
	var it := {"id": String(o.id), "kind": "opening", "floor": k, "poly": opening_poly(doc, o), "z0": z0, "z1": z1,
		"col": cols.get(t, Color.WHITE), "otype": t, "e": o}
	if t in ["porte", "debris"]:
		it["price"] = int(o.get("prix", 0))
	return it


## Objets : piliers, murs, escaliers, pièges, objets muraux et au sol, décor,
## luminaires, effets, barrières invisibles.
static func _object(doc: EditorMap, v: MapValidator, o: Dictionary) -> Dictionary:
	var k := doc.level_of(o)
	if not _floor_ok(v, k):
		return {}
	var t := String(o.get("type", ""))
	var sol := _sol(v, k)
	var cat := MapCatalog.item_for(o)
	var col: Color = cat.get("color", Color(0.8, 0.8, 0.8))
	var base := {"id": String(o.id), "floor": k, "e": o, "col": col}
	match t:
		"pilier", "mur", "mur_courbe":
			var poly := _obstacle_poly(o)
			var c := MapGeom.bbox(poly).get_center()
			base.merge({"kind": "pillar" if t == "pilier" else "wall", "poly": poly, "z0": sol,
				"z1": obstacle_top(doc, v, k, c)})
			return base
		"escalier":
			var up := MapGeom.dir_vec(String(o.get("monte", "n"))).rotated(deg_to_rad(float(MapGeom.rot_of(o))))
			# Arrivée (format 17 : n'importe quel niveau au-dessus du pied).
			var z1 := doc.stair_top_of(o)
			base.merge({"kind": "stairs", "poly": MapRaster.rect_poly(o), "z0": sol, "z1": z1, "up": up,
				# Nombre de marches automatique, comme en jeu (StairGen.flight_steps :
				# ≈ 18 cm chacune) ; « marches » d'une carte ancienne est ignoré.
				"steps": maxi(2, StairGen.flight_steps({"y0": sol, "y1": z1, "steps": 0}, z1 - sol))})
			return base
		"piege":
			base.merge({"kind": "trap", "poly": MapRaster.rect_poly(o), "z0": sol, "z1": sol + TRAP_H})
			return base
		"bloc_invisible":
			var h := float(o.get("hauteur", 0.0))
			var poly := MapRaster.clip_poly(o)
			var z1 := sol + h if h > 0.0 else maxf(MapVertical.ceil_z(v, k, MapGeom.bbox(poly).get_center()), sol + 2.0)
			base.merge({"kind": "clip", "poly": poly, "z0": sol, "z1": z1})
			return base
		"effet":
			return _effect(doc, v, o, base)
		"luminaire", "lampe":
			return _light(doc, v, o, base)
		"prefab":
			return _decor(doc, v, o, base)
		"caisse", "baril":
			base.merge({"kind": "decor", "poly": MapGeom.rect_poly(MapRules.footprint_rect(o)), "z0": sol, "z1": sol + float(FLOOR_H[t])})
			return base
	var poly := MapRules.wall_item_poly(o) if MapCatalog.tool_of(o) == "wall_item" else MapGeom.rect_poly(MapRules.footprint_rect(o))
	if MapCatalog.floor_box(o):
		# Format 15 : boîte posée au sol, son emprise tournée exacte.
		poly = MapRaster.floor_poly(o)
	if MapCatalog.tool_of(o) == "wall_item":
		var z: Array = WALL_Z.get(t, [0.0, 2.0])
		base.merge({"kind": "wobj", "poly": poly, "z0": sol + float(z[0]), "z1": sol + float(z[1])})
		return base
	base.merge({"kind": "fobj", "poly": poly, "z0": sol, "z1": sol + float(FLOOR_H.get(t, 1.0))})
	return base


## Haut (m, absolu) d'un pilier ou d'un mur libre : le haut des murs de sa
## case ; dans une pièce haute, il monte jusqu'en haut du niveau du dessus
## (MapRaster le prolonge dans la trémie).
static func obstacle_top(doc: EditorMap, v: MapValidator, k: int, c: Vector2) -> float:
	var cell := MapVertical.cell(c)
	var top := MapVertical.wall_top(v, k, cell)
	var kk := k
	while kk + 1 < v.floors.size() and v.floors[kk + 1].at(cell) == MapValidator.K.MUR 			and doc.rooms_through(kk + 1).any(func(p): return MapGeom.contains(doc.room_poly(p), c)):
		kk += 1
		top = MapVertical.wall_top(v, kk, cell)
	return top


## Contour d'un pilier (tourné), d'un mur libre (segment épais) ou d'un mur courbe.
static func _obstacle_poly(o: Dictionary) -> PackedVector2Array:
	match String(o.get("type", "")):
		"pilier":
			return MapRaster.rect_poly(o)
		"mur":
			var a := MapGeom.v2(o.a)
			var b := MapGeom.v2(o.b)
			var half := float(o.get("epaisseur", 0.5)) * 0.5
			var d := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector2.RIGHT
			var n := Vector2(-d.y, d.x) * half
			return PackedVector2Array([a + n, b + n, b - n, a - n])
	return MapGeom.rect_poly(MapRules.footprint_rect(o))


## Décor : au sol (de sa hauteur de pose `z` sur `h`), mural (centré sur sa
## hauteur) ou accroché au plafond (sous le plafond réel).
static func _decor(doc: EditorMap, v: MapValidator, o: Dictionary, base: Dictionary) -> Dictionary:
	var k := int(base.floor)
	var sol := _sol(v, k)
	var d := MapCatalog.def_of(o)
	# Format 14 : hauteur mise à l'échelle ; inclinée, celle de sa boîte orientée.
	var h := float(d.get("h", 1.0)) * MapScale.scale_of(o).z
	if MapScale.is_tilted(o):
		h = MapScale.height(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	match MapVertical.mount_of(o):
		"mur":
			var c := sol + MapCatalog.wall_light_height(o)
			base.merge({"kind": "decor", "poly": MapRules.wall_item_poly(o), "z0": c - h * 0.5, "z1": c + h * 0.5})
		"plafond":
			var top := MapVertical.ceil_z(v, k, p) - MapVertical.descente(o)
			base.merge({"kind": "decor", "poly": MapRaster.floor_poly(o), "z0": top - h, "z1": top, "hook": MapVertical.ceil_z(v, k, p)})
		_:
			var z0 := sol + MapVertical.decor_z(o)
			base.merge({"kind": "decor", "poly": MapRaster.floor_poly(o), "z0": z0, "z1": z0 + maxf(h, 0.02)})
			if MapScale.is_tilted(o):
				# Format 14 : les 8 coins de la boîte orientée (x, y, z absolu).
				var box := []
				for q in MapScale.corners(o):
					box.append(Vector3(q.x, q.y, q.z + sol))
				base["box3"] = box
	return base


## Luminaire : la lumière à sa hauteur, son accroche (plafond, meuble ou sol ; le mur).
static func _light(doc: EditorMap, v: MapValidator, o: Dictionary, base: Dictionary) -> Dictionary:
	var k := int(base.floor)
	var sol := _sol(v, k)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var d := MapCatalog.def_of(o)
	var poly := MapGeom.rect_poly(MapRules.footprint_rect(o))
	match MapVertical.mount_of(o):
		"plafond":
			var ce := MapVertical.ceil_z(v, k, p)
			var z := ce - MapVertical.descente(o)
			base.merge({"kind": "light", "poly": poly, "z0": z - 0.2, "z1": ce, "z": z, "hook": ce})
		"mur":
			var z := sol + MapCatalog.wall_light_height(o)
			base.merge({"kind": "light", "poly": MapRules.wall_item_poly(o), "z0": z - 0.25, "z1": z + 0.25, "z": z, "hook": NAN})
		_:
			var b := sol + MapVertical.floor_light_base(doc, o)
			var z := b + float(d.get("y", 0.5))
			base.merge({"kind": "light", "poly": MapRaster.floor_poly(o), "z0": b, "z1": z + 0.15, "z": z, "hook": b})
	return base


## Effet : au sol (sa hauteur, le volume de sa zone), mural (centré sur sa
## hauteur, hauteur de sa zone), au plafond (sous le plafond réel).
static func _effect(_doc: EditorMap, v: MapValidator, o: Dictionary, base: Dictionary) -> Dictionary:
	var k := int(base.floor)
	var sol := _sol(v, k)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var poly := MapRules.effect_poly(o)
	base["col"] = MapCatalog.effect_color(o) if MapCatalog.effect_tints(o) else base.col
	# Boîte = VOLUME de l'effet (MapCatalog.effect_volume), celui où le jeu
	# contient tout ce qu'il affiche, à la hauteur où le jeu le pose.
	var mount := MapCatalog.effect_mount(o)
	var rh := MapVertical.effect_room_h(v, o)
	var span := MapVertical.effect_span(o, rh)
	var z := sol + MapVertical.effect_ground(mount, MapCatalog.effect_height(o), MapVertical.descente(o) if mount == "plafond" else 0.0, rh, MapCatalog.effect_anchor(String(o.get("effet", ""))))
	var hook: float = NAN if mount == "mur" else (MapVertical.ceil_z(v, k, p) if mount == "plafond" else sol)
	base.merge({"kind": "effect", "poly": poly, "z0": sol + span.x, "z1": sol + span.y, "z": z, "hook": hook})
	return base
