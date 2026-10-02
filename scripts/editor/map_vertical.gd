class_name MapVertical
extends RefCounted
## Grandeurs verticales de la carte (docs/EDITOR_VIEWS.md, § 1.2 et § 6) :
## plafond réel d'une case (dessous de la dalle de l'étage du dessus, plafond
## de la pièce, trémie : étage du dessus), partagé par l'export en jeu
## (MapLayoutExport) et les élévations de l'éditeur (MapElevationItems).
## Altitudes absolues en mètres (sol de l'étage + hauteur locale).

const DALLE := MapValidator.DALLE


## Haut de l'étage `k` : dessous de la dalle de l'étage du dessus, sinon le
## plafond du dernier étage.
static func top(v: MapValidator, k: int) -> float:
	return v.floors[k + 1].sol - DALLE if k < v.floors.size() - 1 else v.floors[k].plafond


## Plafond au-dessus d'une case : [hauteur, plafond dessiné (sinon : dessous de dalle)].
static func ceil_at(v: MapValidator, k: int, c: Vector2i) -> Array:
	var own := v.floors[k].ceil_at(c)
	if k == v.floors.size() - 1:
		return [own if own > 0.0 else top(v, k), true]
	var above := v.floors[k + 1].at(c)
	if above == MapValidator.K.TREMIE:
		return ceil_at(v, k + 1, c)
	if above == MapValidator.K.VIDE:
		return [own if own > 0.0 else top(v, k), true]
	return [v.floors[k + 1].sol - DALLE, false]


## Haut des murs d'une case (jusqu'au haut de l'étage du dessus au droit d'une trémie).
static func wall_top(v: MapValidator, k: int, c: Vector2i) -> float:
	if k < v.floors.size() - 1:
		var above := v.floors[k + 1].at(c)
		if above == MapValidator.K.TREMIE:
			return wall_top(v, k + 1, c)
		if above != MapValidator.K.VIDE:
			return top(v, k)
	var own := v.floors[k].ceil_at(c)
	return own if own > 0.0 else top(v, k)


## Plafond d'une case pour une pièce de plafond `own` (m) : comme ceil_at, mais
## avec le plafond de CETTE pièce (un mur mitoyen porte le plus haut des deux).
static func ceil_room(v: MapValidator, k: int, c: Vector2i, own: float) -> Array:
	if k == v.floors.size() - 1:
		return [own, true]
	var above := v.floors[k + 1].at(c)
	if above == MapValidator.K.TREMIE:
		return ceil_at(v, k + 1, c)
	if above == MapValidator.K.VIDE:
		return [own, true]
	return [v.floors[k + 1].sol - DALLE, false]


## Case (0,5 m) d'un point de l'éditeur.
static func cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / MapGeom.CELL), floori(p.y / MapGeom.CELL))


## Plafond réel (m, absolu) au-dessus d'un point de l'étage `k`.
static func ceil_z(v: MapValidator, k: int, p: Vector2) -> float:
	if k < 0 or k >= v.floors.size():
		return 0.0
	return float(ceil_at(v, k, cell(p))[0])


# ------------------------------------------------------------------ hauteurs de pose (format 12)

## Bornes (m) des hauteurs de pose du format 12 : `z` du décor posé au sol,
## `descente` sous le plafond (luminaires, effets et décor du plafond).
const DECOR_Z := [0.0, 30.0]
const DESCENTE := [0.0, 3.0]
## Lampe historique (« lampe ») : sous le plafond.
const LAMP_DROP := 0.35


## Montage vertical d'un élément : « sol », « mur », « plafond » (décor,
## luminaires, effets) ; "" pour les autres.
static func mount_of(e: Dictionary) -> String:
	match String(e.get("type", "")):
		"effet":
			return MapCatalog.effect_mount(e)
		"lampe":
			return "plafond"
		"luminaire", "prefab":
			var m := MapCatalog.light_mount(e)
			return m if m != "" else "sol"
	return ""


## Nombre fini lu dans `e[key]`, sinon `def`.
static func _num(e: Dictionary, key: String, def: float) -> float:
	var v: Variant = e.get(key, def)
	if not (v is float or v is int) or not is_finite(float(v)):
		return def
	return float(v)


## Descente sous le plafond (m) d'un élément accroché au plafond (format 12,
## clé « descente ») ; absente : celle du catalogue (luminaire : `drop`).
static func descente(e: Dictionary) -> float:
	var def := 0.0
	match String(e.get("type", "")):
		"luminaire":
			def = float(MapCatalog.def_of(e).get("drop", 0.4))
		"lampe":
			def = LAMP_DROP
	return clampf(_num(e, "descente", def), DESCENTE[0], maxf(DESCENTE[1], def))


## Hauteur de pose (m au-dessus du sol) d'un décor posé au sol (format 12, clé « z »).
static func decor_z(e: Dictionary) -> float:
	return clampf(_num(e, "z", 0.0), DECOR_Z[0], DECOR_Z[1])


## Hauteur (m au-dessus du sol) du pied d'un luminaire posé au sol : la clé
## « hauteur » (format 12), sinon le dessus du meuble sous lui (`support`).
static func floor_light_base(doc: EditorMap, e: Dictionary) -> float:
	if e.has("hauteur"):
		return clampf(_num(e, "hauteur", 0.0), 0.0, MapCatalog.WALL_LIGHT_HEIGHT[1])
	var sup := MapRules.support_under(doc, e) if doc != null else {}
	return MapRules.support_height(sup) if not sup.is_empty() else 0.0


# ------------------------------------------------------------------ édition verticale (étape 3)

## Bornes du plafond d'une pièce (m, hauteur sous plafond) : les mêmes dans
## le panneau, le catalogue (contrôle des cartes reçues) et le validateur.
const ROOM_CEILING := [2.8, 9.0]
## Marges sous le plafond (comme l'export en jeu, MapLayoutExport) : applique
## et décor mural, effet mural, effet au sol.
const WALL_MARGIN := 0.15
const WALL_FX_MARGIN := 0.2
const FLOOR_FX_MARGIN := 0.1
## Décor posé sur un autre : tolérance (m) entre son pied et le dessus de l'autre.
const REST_TOL := 0.02


## Effet d'un glissement vertical selon le type (§ 6.1) : « pose » (hauteur
## de pose continue), « niveau » (l'étage change, aimanté sur les sols),
## « fixe » (ouvertures : elles suivent leur mur).
static func pose_kind(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	if t in MapRules.ouvertures_types():
		return "fixe"
	if t in ["effet", "luminaire", "prefab"]:
		return "pose"
	return "niveau"


## Clé de la hauteur de pose d'un élément « pose » : « hauteur », « z » ou « descente ».
static func pose_key(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	match mount_of(e):
		"plafond":
			return "descente"
		"mur":
			return "hauteur"
	if t == "prefab":
		return "z"
	return "hauteur" if t in ["effet", "luminaire"] else ""


## Hauteur sous plafond (m) au-dessus du point de pose d'un élément.
static func room_h(v: MapValidator, e: Dictionary) -> float:
	var k := int(e.get("etage", 0))
	if v == null or k < 0 or k >= v.floors.size():
		return EditorMap.DEFAULT_CEILING
	return ceil_z(v, k, anchor_of(e)) - v.floors[k].sol


## Point (m, plan) où un élément est posé : sa position (mural : contre la face du mur).
static func anchor_of(e: Dictionary) -> Vector2:
	var p := MapGeom.v2(e.get("position", [0, 0]))
	if mount_of(e) == "mur":
		return p - MapGeom.item_wall_dir(e) * (MapGeom.WALL_HALF + 0.05)
	return p


## Hauteur de pose (m au-dessus du sol de l'étage) d'un élément « pose » :
## pied d'un décor ou d'un luminaire au sol, hauteur d'un effet au sol, d'une
## applique, d'un décor ou d'un effet mural ; au plafond : plafond − descente.
static func pose_z(doc: EditorMap, v: MapValidator, e: Dictionary) -> float:
	var t := String(e.get("type", ""))
	match mount_of(e):
		"plafond":
			return room_h(v, e) - descente(e)
		"mur":
			return MapCatalog.effect_height(e) if t == "effet" else MapCatalog.wall_light_height(e)
	match t:
		"effet":
			return MapCatalog.effect_height(e)
		"luminaire":
			return floor_light_base(doc, e)
		"prefab":
			return decor_z(e)
	return 0.0


## Bornes [min, max] (m au-dessus du sol) de la hauteur de pose d'un élément
## à son étage : sous le plafond réel, avec la marge de l'export en jeu.
static func pose_bounds(v: MapValidator, e: Dictionary) -> Vector2:
	var t := String(e.get("type", ""))
	var h := room_h(v, e)
	var d := MapCatalog.def_of(e)
	match mount_of(e):
		"plafond":
			var size_h := float(d.get("h", 0.0)) if t == "prefab" else 0.0
			return Vector2(maxf(h - DESCENTE[1], size_h), h - DESCENTE[0])
		"mur":
			if t == "effet":
				return Vector2(0.05, maxf(0.05, h - WALL_FX_MARGIN))
			return Vector2(MapCatalog.WALL_LIGHT_HEIGHT[0], maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], h - WALL_MARGIN))
	match t:
		"effet":
			return Vector2(0.0, maxf(0.0, h - FLOOR_FX_MARGIN))
		"luminaire":
			return Vector2(0.0, maxf(0.0, h - float(d.get("y", 0.5)) - 0.15))
		"prefab":
			return Vector2(0.0, maxf(0.0, h - float(d.get("h", 1.0))))
	return Vector2(0.0, h)


## Écrit la hauteur de pose `z` (m au-dessus du sol) dans l'élément : la clé
## de son type, bornée, au centimètre ; la valeur par défaut retire la clé
## (une carte d'avant garde ses octets).
static func set_pose_z(doc: EditorMap, v: MapValidator, e: Dictionary, z: float) -> void:
	var t := String(e.get("type", ""))
	var b := pose_bounds(v, e)
	z = snappedf(clampf(z, b.x, b.y), 0.01)
	match pose_key(e):
		"descente":
			var d := snappedf(room_h(v, e) - z, 0.01)
			var def := 0.0
			if t == "luminaire":
				def = float(MapCatalog.def_of(e).get("drop", 0.4))
			if absf(d - def) < 0.005:
				e.erase("descente")
			else:
				e["descente"] = clampf(d, DESCENTE[0], DESCENTE[1])
		"hauteur":
			if t == "effet":
				e["hauteur"] = z
				MapCatalog.tidy_effect(e)
			elif mount_of(e) == "mur":
				MapCatalog.set_wall_light_height(e, z)
			else:
				# Luminaire au sol (format 12) : par défaut, le dessus du meuble dessous.
				e.erase("hauteur")
				if absf(floor_light_base(doc, e) - z) >= 0.005:
					e["hauteur"] = z
		"z":
			if z < 0.005:
				e.erase("z")
			else:
				e["z"] = z


## Remet en ordre les clés du format 12 d'un objet lu (fichier écrit à la
## main) : illisibles, hors de leur type ou à leur valeur par défaut retirées,
## sinon bornées.
static func tidy(o: Dictionary) -> void:
	var t := String(o.get("type", ""))
	var m := mount_of(o)
	if o.has("z"):
		var zv: Variant = o.z
		if t != "prefab" or m != "sol" or not (zv is float or zv is int) or not is_finite(float(zv)) or float(zv) < 0.005:
			o.erase("z")
		else:
			o["z"] = snappedf(clampf(float(zv), DECOR_Z[0], DECOR_Z[1]), 0.01)
	if o.has("descente"):
		var dv: Variant = o.descente
		if not (t in ["luminaire", "effet", "prefab"] and m == "plafond") or not (dv is float or dv is int) or not is_finite(float(dv)):
			o.erase("descente")
		else:
			var def := float(MapCatalog.def_of(o).get("drop", 0.4)) if t == "luminaire" else 0.0
			if absf(float(dv) - def) < 0.005:
				o.erase("descente")
			else:
				o["descente"] = snappedf(clampf(float(dv), DESCENTE[0], DESCENTE[1]), 0.01)


## Dessus (m au-dessus du sol) d'un décor : son `support` s'il en a un, sinon
## le haut de son modèle (`h`), depuis sa hauteur de pose.
static func decor_top(o: Dictionary) -> float:
	var t := String(o.get("type", ""))
	if t in ["caisse", "baril"]:
		return MapElevationItems.FLOOR_H[t]
	var d := MapCatalog.def_of(o)
	var top := float(d.get("support", d.get("h", 0.0)))
	return decor_z(o) + top


## Dessus des décors posés au sol sous l'emprise de `o` (m au-dessus du sol, triés).
static func tops_under(doc: EditorMap, o: Dictionary) -> Array:
	var out := []
	var r := MapRules.footprint_rect(o)
	var k := int(o.get("etage", 0))
	for q in doc.objects_on(k):
		if String(q.get("id", "")) == String(o.get("id", "")) or not String(q.get("type", "")) in ["prefab", "caisse", "baril"]:
			continue
		if mount_of(q) not in ["sol", ""]:
			continue
		if MapRules.footprint_rect(q).grow(-0.01).intersects(r.grow(-0.01)):
			out.append(decor_top(q))
	out.sort()
	return out


## Vérifie la hauteur de pose d'un élément (bornes de son type sous le plafond
## réel ; § 7 : un décor qui bloque, posé au-dessus du sol, repose sur un autre).
static func check_pose(doc: EditorMap, v: MapValidator, e: Dictionary) -> Dictionary:
	if pose_kind(e) != "pose":
		return {"ok": true}
	var z := pose_z(doc, v, e)
	var b := pose_bounds(v, e)
	if z < b.x - 0.011 or z > b.y + 0.011:
		return MapRules.refuse("hauteur hors des bornes (%s à %s m ici)" % [MapRules._m(b.x), MapRules._m(b.y)],
			"height out of bounds (%s to %s m here)" % [MapRules._m(b.x, false), MapRules._m(b.y, false)])
	if String(e.get("type", "")) == "prefab" and mount_of(e) == "sol" and z > REST_TOL and MapCatalog.blocking(e) != "non":
		if not tops_under(doc, e).any(func(top): return absf(float(top) - z) <= REST_TOL):
			return MapRules.refuse("décor en l'air : posez-le sur un autre", "prop in mid-air: put it on another one")
	return {"ok": true}


## Étage (indice) dont la tranche contient l'altitude `za` (m, absolue) :
## du sol d'un étage au sol du suivant (le dernier : jusqu'à son plafond) ;
## -1 sous le premier sol ou au-dessus du haut du dernier étage.
static func floor_at(doc: EditorMap, za: float) -> int:
	var n := doc.floor_count()
	for k in range(n - 1, -1, -1):
		if za >= doc.floor_sol(k) - 0.001:
			if k == n - 1 and za > doc.floor_sol(k) + doc.floor_height(k) + 0.001:
				return -1
			return k
	return -1


## Plafond le plus haut (m, hauteur sous plafond) d'une pièce : 9 m, ou le
## dessous de la dalle de l'étage du dessus si une pièce de cet étage la
## couvre entièrement.
static func ceiling_max(doc: EditorMap, v: MapValidator, room: Dictionary) -> float:
	var k := int(room.get("etage", 0))
	if v == null or k + 1 >= v.floors.size():
		return ROOM_CEILING[1]
	var cells: Array = MapRaster.room_cells(doc.room_poly(room))[1]
	if cells.is_empty():
		return ROOM_CEILING[1]
	for c in cells:
		if v.floors[k + 1].at(c) in [MapValidator.K.VIDE, MapValidator.K.TREMIE]:
			return ROOM_CEILING[1]
	return clampf(doc.floor_sol(k + 1) - DALLE - doc.floor_sol(k), ROOM_CEILING[0], ROOM_CEILING[1])


## Étage dont le sol est le plus proche de l'altitude `za` (aimantation sur les niveaux).
static func nearest_floor(doc: EditorMap, za: float) -> int:
	var best := 0
	for k in doc.floor_count():
		if absf(doc.floor_sol(k) - za) < absf(doc.floor_sol(best) - za):
			best = k
	return best


## Aimants verticaux (§ 3.2) autour d'un élément : sols, plafonds de l'étage
## et de la pièce, dessous de dalle, hauteur des portes, allège et linteau
## des fenêtres, dessus du décor sous l'élément. -> [{z (m, absolue), name}].
static func magnets(doc: EditorMap, v: MapValidator, e: Dictionary) -> Array:
	var out := []
	var fr := not Lang.is_en()
	for k in doc.floor_count():
		var sol := doc.floor_sol(k)
		var tag := Lang.t("É%d", "F%d") % k
		out.append({"z": sol, "name": Lang.t("Sol %s", "Floor %s") % tag})
		out.append({"z": sol + doc.floor_height(k), "name": Lang.t("Plafond %s", "Ceiling %s") % tag})
		if k + 1 < doc.floor_count():
			out.append({"z": doc.floor_sol(k + 1) - DALLE, "name": Lang.t("Dessous de dalle %s", "Slab underside %s") % tag})
	var k := int(e.get("etage", 0))
	var sol := doc.floor_sol(k)
	var dh := float(doc.carte.get("hauteur_portes", MapValidator.DOOR_HEIGHT))
	out.append({"z": sol + dh, "name": Lang.t("Haut des portes", "Door top")})
	out.append({"z": sol + MapValidator.SILL, "name": Lang.t("Allège fenêtres", "Window sill")})
	out.append({"z": sol + MapValidator.LINTEL, "name": Lang.t("Linteau fenêtres", "Window lintel")})
	if v != null and not e.is_empty() and e.has("position"):
		out.append({"z": sol + room_h(v, e), "name": Lang.t("Plafond de la pièce", "Room ceiling")})
		for top in tops_under(doc, e):
			out.append({"z": sol + float(top), "name": Lang.t("Dessus du décor", "Prop top")})
	for m in out:
		m["label"] = "%s · %s" % [String(m.name), MapRules._m(float(m.z) - sol, fr)]
	return out
