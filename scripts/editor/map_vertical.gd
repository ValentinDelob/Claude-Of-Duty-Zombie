class_name MapVertical
extends RefCounted
## Grandeurs verticales de la carte (docs/EDITOR_VIEWS.md, § 1.2 et § 6) :
## plafond réel d'une case (le plus bas du plafond de sa pièce et du dessous
## de la dalle de la première pièce posée au-dessus, à n'importe quel niveau ;
## trémie : plafond de la pièce où elle s'ouvre), partagé par l'export en jeu
## (MapLayoutExport) et les élévations de l'éditeur (MapElevationItems).
## Altitudes absolues en mètres (sol de l'étage + hauteur locale).

const DALLE := MapValidator.DALLE


## Un mur monte jusqu'à la dalle d'une pièce posée au-dessus si l'écart entre
## son haut et le dessous de cette dalle ne dépasse pas WALL_CLOSE (m) ; plus
## haut (pièce empilée loin au-dessus), il s'arrête à son plafond.
const WALL_CLOSE := 3.0
## Plafond réglé qui touche le dessous de la dalle du dessus (m) : c'est la
## dalle qui le dessine (comme avant le format 17).
const CEIL_EQ := 0.005


## Haut par défaut du niveau `k` (case sans plafond propre) : le plus haut
## plafond réglé de ses pièces (MapRaster : Floor.plafond).
static func top(v: MapValidator, k: int) -> float:
	return v.floors[k].plafond


## Premier niveau au-dessus de `k` dont la case `c` porte une DALLE (sol,
## mur, objet d'une pièce : tout sauf le vide et les trémies, escaliers et
## vides des pièces hautes) ; -1 sinon. Format 17 : n'importe quel niveau, pas
## seulement le suivant (niveaux libres, demi-niveaux côte à côte).
static func slab_above(v: MapValidator, k: int, c: Vector2i) -> int:
	for j in range(k + 1, v.floors.size()):
		var kd := v.floors[j].at(c)
		if kd != MapValidator.K.VIDE and kd != MapValidator.K.TREMIE:
			return j
	return -1


## Plafond au-dessus d'une case : [hauteur, plafond dessiné (sinon : dessous de dalle)].
## Décision 2 du plan : le plus bas du plafond réglé et du dessous de la dalle
## de la première pièce au-dessus ; une trémie (escalier, vide d'une pièce
## haute) n'est pas une dalle : le plafond y est le sien (pièce où elle s'ouvre).
static func ceil_at(v: MapValidator, k: int, c: Vector2i) -> Array:
	var own := v.floors[k].ceil_at(c)
	return ceil_room(v, k, c, own if own > 0.0 else top(v, k))


## Ciel ouvert au-dessus d'une case (format 17, plafond masqué) : son plafond
## effectif (ceil_at) est le plafond propre d'une pièce sans plafond
## (MapValidator.open_sky) : celui de son niveau, ou celui de la pièce où
## s'ouvre une trémie au-dessus ; jamais le dessous de la dalle d'une pièce
## posée au-dessus (à n'importe quel niveau, slab_above), qui reste dessiné.
static func open_at(v: MapValidator, k: int, c: Vector2i) -> bool:
	if k < 0 or k >= v.open_sky.size() or k >= v.floors.size():
		return false
	var own := v.floors[k].ceil_at(c)
	var r := _ceil_walk(v, k, c, own if own > 0.0 else top(v, k))
	if not bool(r[1]):
		return false
	var src: int = r[2]
	return src < v.open_sky.size() and (v.open_sky[src] as Dictionary).has(c)


## Ciel ouvert au-dessus d'une case pour une pièce de plafond `own` (m) au
## niveau `k`, sans plafond si `open` (EditorMap.no_ceiling) : comme open_at,
## mais avec CETTE pièce (morceaux en biais de l'export).
static func open_room(v: MapValidator, k: int, c: Vector2i, own: float, open: bool) -> bool:
	if not open:
		return false
	var r := _ceil_walk(v, k, c, own)
	return bool(r[1]) and int(r[2]) == k


## Haut des murs d'une case : jusqu'au plafond (le plus haut de ses pièces),
## au dessous de la dalle d'une pièce posée au-dessus si elle est proche
## (WALL_CLOSE), à travers une trémie jusqu'au niveau où elle s'ouvre.
static func wall_top(v: MapValidator, k: int, c: Vector2i) -> float:
	var own := v.floors[k].ceil_at(c)
	if own <= 0.0:
		own = top(v, k)
	for j in range(k + 1, v.floors.size()):
		var f := v.floors[j]
		var kd := f.at(c)
		if kd == MapValidator.K.VIDE:
			continue
		if kd == MapValidator.K.TREMIE:
			if f.ceil_at(c) > 0.0:
				return wall_top(v, j, c)
			continue
		var slab := f.sol - DALLE
		return slab if slab - own <= WALL_CLOSE + 0.001 else own
	return own


## Plafond d'une case pour une pièce de plafond `own` (m) : comme ceil_at, mais
## avec le plafond de CETTE pièce (un mur mitoyen porte le plus haut des deux).
static func ceil_room(v: MapValidator, k: int, c: Vector2i, own: float) -> Array:
	var r := _ceil_walk(v, k, c, own)
	return [r[0], r[1]]


## ceil_room avec le niveau d'où vient le plafond : [hauteur, plafond dessiné,
## niveau de la pièce dont c'est le plafond (`k`, ou celui où s'ouvre une
## trémie au-dessus ; celui de la dalle sinon)].
static func _ceil_walk(v: MapValidator, k: int, c: Vector2i, own: float) -> Array:
	var src := k
	for j in range(k + 1, v.floors.size()):
		var f := v.floors[j]
		var kd := f.at(c)
		if kd == MapValidator.K.VIDE:
			continue
		if kd == MapValidator.K.TREMIE:
			# Trémie : le plafond de la pièce où elle s'ouvre (le sien s'il est donné).
			var t := f.ceil_at(c)
			if t > 0.0:
				own = t
				src = j
			continue
		var slab := f.sol - DALLE
		if own < slab - CEIL_EQ:
			return [own, true, src]
		return [slab, false, j]
	return [own, true, src]


## Niveau (indice dans la grille `v`) d'un élément : celui de son altitude
## (EditorMap.alt_of), -1 s'il n'y en a pas.
static func level_in(v: MapValidator, e: Dictionary) -> int:
	if v == null:
		return -1
	var a := EditorMap.alt_of(e)
	for k in v.floors.size():
		if absf(v.floors[k].sol - a) <= EditorMap.ALT_EQ:
			return k
	return -1


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
## Format 17 : pas de maximum (seulement un nombre fini).
const ROOM_CEILING := [2.8, INF]
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
	var k := level_in(v, e)
	if v == null or k < 0 or k >= v.floors.size():
		return EditorMap.DEFAULT_CEILING
	return ceil_z(v, k, anchor_of(e)) - v.floors[k].sol


## Hauteur (m) de l'origine d'un effet au-dessus du sol de l'étage, en jeu
## comme dans l'éditeur (MapLayoutExport, élévations, aperçu 3D) : au
## plafond, plafond − 2 cm − descente ; mural, sous le plafond ; au sol, sa
## hauteur de pose. `y` : MapCatalog.effect_height ; `rh` : hauteur sous plafond ;
## `anchor` : MapCatalog.effect_anchor (flamme posée au bout d'un décor mural).
static func effect_ground(mount: String, y: float, desc: float, rh: float, anchor := 0.0) -> float:
	match mount:
		"plafond":
			return maxf(0.0, rh - 0.02 - desc)
		"mur":
			if anchor != 0.0:
				# Porté par un décor mural (flamme de torche, `anchor` m au-dessus
				# de lui) : bornée comme lui (applique), elle reste à son bout.
				var lo := float(MapCatalog.WALL_LIGHT_HEIGHT[0])
				return clampf(y - anchor, lo, maxf(lo, rh - WALL_MARGIN)) + anchor
			return clampf(y, 0.05, maxf(0.05, rh - WALL_FX_MARGIN))
	return maxf(0.0, y)


## Hauteur sous plafond (m) d'un effet posé, au point où le jeu le pose
## (mural : sur la face du mur, comme MapRaster._effect).
static func effect_room_h(v: MapValidator, e: Dictionary) -> float:
	var k := level_in(v, e)
	if v == null or k < 0 or k >= v.floors.size():
		return EditorMap.DEFAULT_CEILING
	var p := MapGeom.v2(e.get("position", [0, 0]))
	if MapCatalog.effect_mount(e) == "mur":
		p -= MapGeom.item_wall_dir(e) * MapGeom.WALL_HALF
	return ceil_z(v, k, p) - v.floors[k].sol


## Boîte d'un effet posé en hauteur : Vector2(bas, haut), m au-dessus du sol
## de l'étage, = son VOLUME (MapCatalog.effect_volume) posé à sa hauteur.
## `rh` : hauteur sous plafond à son point (effect_room_h).
static func effect_span(e: Dictionary, rh: float) -> Vector2:
	var fid := String(e.get("effet", ""))
	var mount := MapCatalog.effect_mount(e)
	var g := effect_ground(mount, MapCatalog.effect_height(e), descente(e) if mount == "plafond" else 0.0, rh, MapCatalog.effect_anchor(fid))
	var vol := MapCatalog.effect_volume(fid, MapCatalog.effect_zone(e), g, rh)
	return Vector2(g + vol.position.y, g + vol.end.y)


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
			# Format 14 : hauteur du décor mis à l'échelle.
			var size_h := MapScale.dims(e).z if t == "prefab" else 0.0
			return Vector2(maxf(h - DESCENTE[1], size_h), h - DESCENTE[0])
		"mur":
			if t == "effet":
				var an := MapCatalog.effect_anchor(String(e.get("effet", "")))
				if an != 0.0:
					# Flamme de torche : bornée comme sa torche (effect_ground).
					var lo := float(MapCatalog.WALL_LIGHT_HEIGHT[0])
					return Vector2(lo + an, maxf(lo, h - WALL_MARGIN) + an)
				return Vector2(0.05, maxf(0.05, h - WALL_FX_MARGIN))
			if t == "prefab" and MapScale.is_scaled(e):
				# Format 14 : décor mural mis à l'échelle (« hauteur » au centre) :
				# tout entier entre le sol et le plafond (marge de l'export).
				var half := MapScale.dims(e).z * 0.5
				var lo := maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], half)
				return Vector2(lo, maxf(lo, h - WALL_MARGIN - half))
			return Vector2(MapCatalog.WALL_LIGHT_HEIGHT[0], maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], h - WALL_MARGIN))
	match t:
		"effet":
			return Vector2(0.0, maxf(0.0, h - FLOOR_FX_MARGIN))
		"luminaire":
			return Vector2(0.0, maxf(0.0, h - float(d.get("y", 0.5)) - 0.15))
		"prefab":
			# Format 14 : hauteur de la boîte orientée (échelle, inclinaison).
			return Vector2(0.0, maxf(0.0, h - MapScale.height(e)))
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
## le haut de son modèle (`h`), depuis sa hauteur de pose. Format 14 : × son
## échelle en hauteur ; incliné, son point le plus haut (il ne porte rien).
static func decor_top(o: Dictionary) -> float:
	var t := String(o.get("type", ""))
	if t in ["caisse", "baril"]:
		return MapElevationItems.FLOOR_H[t]
	if MapScale.is_tilted(o):
		return decor_z(o) + MapScale.height(o)
	var d := MapCatalog.def_of(o)
	var top := float(d.get("support", d.get("h", 0.0)))
	return decor_z(o) + top * MapScale.scale_of(o).z


## Dessus des décors posés au sol sous l'emprise de `o` (m au-dessus du sol, triés).
static func tops_under(doc: EditorMap, o: Dictionary) -> Array:
	var out := []
	var r := MapRules.footprint_rect(o)
	var k := doc.level_of(o)
	for q in doc.objects_on(k):
		if String(q.get("id", "")) == String(o.get("id", "")) or not String(q.get("type", "")) in ["prefab", "caisse", "baril"]:
			continue
		# Format 14 : un décor incliné ne porte rien (§ 3.4).
		if mount_of(q) not in ["sol", ""] or not MapScale.carries(q):
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
	if not rests_ok(doc, e):
		return MapRules.refuse("décor en l'air : posez-le sur un autre", "prop in mid-air: put it on another one")
	return {"ok": true}


## § 7 : un décor bloquant posé au sol, au-dessus du sol (`z`), repose-t-il
## sur le dessus d'un autre décor ? (Vrai pour tout autre élément.)
static func rests_ok(doc: EditorMap, e: Dictionary) -> bool:
	if String(e.get("type", "")) != "prefab" or mount_of(e) != "sol" or MapCatalog.blocking(e) == "non":
		return true
	var z := decor_z(e)
	if z <= REST_TOL:
		return true
	return tops_under(doc, e).any(func(top): return absf(float(top) - z) <= REST_TOL)


## Décors bloquants posés sur `o` (identifiants, hors `skip`) : ceux qui
## tomberaient « en l'air » si `o` bougeait ou disparaissait.
static func resting_on(doc: EditorMap, o: Dictionary, skip: Array = []) -> Array:
	var out := []
	if not String(o.get("type", "")) in ["prefab", "caisse", "baril"] or mount_of(o) not in ["sol", ""] or not MapScale.carries(o):
		return out
	var top := decor_top(o)
	var r := MapRules.footprint_rect(o)
	for q in doc.objects_on(doc.level_of(o)):
		var qid := String(q.get("id", ""))
		if qid == String(o.get("id", "")) or qid in skip or String(q.get("type", "")) != "prefab" or mount_of(q) != "sol":
			continue
		if MapCatalog.blocking(q) == "non" or decor_z(q) <= REST_TOL or absf(decor_z(q) - top) > REST_TOL:
			continue
		if MapRules.footprint_rect(q).grow(-0.01).intersects(r.grow(-0.01)):
			out.append(qid)
	return out


## Refus si l'un des décors `ids` (posés sur un autre avant un changement)
## n'y repose plus ; {ok: true} sinon.
static func check_rests(doc: EditorMap, ids: Array) -> Dictionary:
	for qid in ids:
		var q := doc.find(String(qid))
		if not q.is_empty() and not rests_ok(doc, q):
			return MapRules.refuse("un décor est posé dessus : déplacez-le d'abord", "a prop stands on it: move that one first")
	return {"ok": true}


## Niveau (indice) dont la tranche contient l'altitude `za` (m, absolue) :
## du sol d'un niveau au sol du suivant (le dernier : jusqu'au plus haut
## plafond de ses pièces) ; -1 sous le premier sol ou au-dessus du dernier.
static func floor_at(doc: EditorMap, za: float) -> int:
	var n := doc.level_count()
	for k in range(n - 1, -1, -1):
		if za >= doc.level_alt(k) - 0.001:
			if k == n - 1:
				var hi := doc.level_alt(k) + EditorMap.DEFAULT_CEILING
				for p in doc.rooms_on(k):
					hi = maxf(hi, EditorMap.room_top(p))
				if za > hi + 0.001:
					return -1
			return k
	return -1


## Plafond le plus haut (m, hauteur sous plafond) d'une pièce. Format 17 :
## aucun maximum de conception (sous une pièce du dessus, le plafond réel est
## le plus bas des deux).
static func ceiling_max(_doc: EditorMap, _v: MapValidator, _room: Dictionary) -> float:
	return ROOM_CEILING[1]


## Niveau dont le sol est le plus proche de l'altitude `za` (aimantation sur les niveaux).
static func nearest_floor(doc: EditorMap, za: float) -> int:
	return doc.nearest_level(za)


## Aimants verticaux (§ 3.2) autour d'un élément : sols, plafonds de l'étage
## et de la pièce, dessous de dalle, hauteur des portes, allège et linteau
## des fenêtres, dessus du décor sous l'élément. -> [{z (m, absolue), name}].
static func magnets(doc: EditorMap, v: MapValidator, e: Dictionary) -> Array:
	var out := []
	var fr := not Lang.is_en()
	for k in doc.level_count():
		var sol := doc.level_alt(k)
		var tag := EditorMap.alt_text(sol, fr)
		out.append({"z": sol, "name": Lang.t("Sol %s", "Floor %s") % tag})
		out.append({"z": sol + EditorMap.DEFAULT_CEILING, "name": Lang.t("Plafond %s", "Ceiling %s") % tag})
		if k + 1 < doc.level_count():
			out.append({"z": doc.level_alt(k + 1) - DALLE, "name": Lang.t("Dessous de dalle %s", "Slab underside %s") % tag})
	var sol := EditorMap.alt_of(e)
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
