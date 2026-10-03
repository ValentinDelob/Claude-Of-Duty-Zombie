class_name MapScale
extends RefCounted
## ÉCHELLE ET ROTATION 3D du décor (format 14, docs/EDITOR_SCALE_ROTATE.md) :
## logique pure partagée par l'éditeur (règles de pose, vues, panneau), le
## contrôle des cartes reçues (CustomMapGuard), l'export en jeu
## (MapLayoutExport) et l'aperçu 3D. Clés facultatives d'un objet « prefab »,
## jamais écrites à leur valeur par défaut :
##   echelle  [sx, sy, sz] facteurs dans le REPÈRE DE L'OBJET : X = largeur
##            (fp[0]), Y = profondeur (fp[1]), Z = hauteur (h), avant rotation ;
##            chacun de 0,25 à 4 au pas de 0,01 ; défaut [1, 1, 1] ;
##   incl     [x, y] inclinaisons (degrés, au dixième) autour des axes X (est)
##            et Y (sud) de la carte ; seulement un décor posé au sol ;
##            défaut [0, 0].
## Orientation = Rz(rot) · Ry(incl[1]) · Rx(incl[0]) dans le repère de la carte
## (X est, Y sud, Z haut). Sens positif de chaque axe : HORAIRE à l'écran dans
## la vue qui regarde l'axe de bout (Dessus pour Z, c'est le « rot » d'avant ;
## Avant pour Y ; Droite pour X).
## Un décor incliné reste « posé » : « z » est la hauteur de son point le plus
## bas ; sa « position » est le centre de sa boîte (vu de dessus).
##
## Ce qui change d'échelle (§ 1) : seul le type « prefab » (décor du
## catalogue au sol, mural ou au plafond, prefabs de la carte), sauf un
## prefab de la carte qui contient un objet de jeu (bloqué : unscalable_parts,
## raison qui NOMME l'objet). Rien d'autre (objets de jeu, ouvertures,
## construction, luminaires, effets).

## Bornes d'un facteur d'échelle (par axe) et son pas.
const LO := 0.25
const HI := 4.0
const STEP := 0.01
## Inclinaison : bornes (degrés) et pas.
const INCL_MAX := 180.0
const INCL_STEP := 0.1
## Dimension finale (m) d'un décor mis à l'échelle et côté maximal de son
## emprise au sol (m : 40 cases de 0,5 m, MapPrefabLib.MAX_FP).
const MIN_DIM := 0.05
const MAX_DIM := MapPrefabLib.MAX_SIZE
const MAX_FOOT := MapPrefabLib.MAX_FP * MapGeom.CELL
## Noms des objets bloquants cités au plus dans un message (puis « et N autres »).
const MAX_NAMED := 2


# ------------------------------------------------------------------ lecture des clés

## Échelle lisible d'une valeur de fichier ([sx, sy, sz] bornés) ; Vector3.ONE sinon.
static func read_scale(v: Variant) -> Vector3:
	if not (v is Array and v.size() == 3):
		return Vector3.ONE
	var out := Vector3.ONE
	for i in 3:
		var x: Variant = v[i]
		if not ((x is float or x is int) and is_finite(float(x))):
			return Vector3.ONE
		out[i] = clampf(float(x), LO, HI)
	return out


## Inclinaison lisible ([x, y] degrés bornés) ; Vector2.ZERO sinon.
static func read_incl(v: Variant) -> Vector2:
	if not (v is Array and v.size() == 2):
		return Vector2.ZERO
	var out := Vector2.ZERO
	for i in 2:
		var x: Variant = v[i]
		if not ((x is float or x is int) and is_finite(float(x))):
			return Vector2.ZERO
		out[i] = clampf(float(x), -INCL_MAX, INCL_MAX)
	return out


## Échelle d'un objet posé (Vector3.ONE si elle n'a pas de sens pour lui).
static func scale_of(o: Dictionary) -> Vector3:
	if String(o.get("type", "")) != "prefab" or not o.has("echelle"):
		return Vector3.ONE
	return read_scale(o.echelle)


## Inclinaison d'un objet posé (degrés ; zéro pour ce qui ne s'incline pas).
static func incl_of(o: Dictionary) -> Vector2:
	if String(o.get("type", "")) != "prefab" or not o.has("incl"):
		return Vector2.ZERO
	return read_incl(o.incl)


static func is_scaled(o: Dictionary) -> bool:
	return not scale_of(o).is_equal_approx(Vector3.ONE)


static func is_tilted(o: Dictionary) -> bool:
	var i := incl_of(o)
	return absf(i.x) >= INCL_STEP * 0.5 or absf(i.y) >= INCL_STEP * 0.5


## Mis à l'échelle ou incliné (sinon : tout se calcule comme avant le format 14).
static func transformed(o: Dictionary) -> bool:
	return is_scaled(o) or is_tilted(o)


## Facteur uniforme (les trois axes égaux) ?
static func is_uniform(s: Vector3) -> bool:
	return is_equal_approx(s.x, s.y) and is_equal_approx(s.y, s.z)


## Facteur arrondi au pas et borné.
static func snap_factor(v: float) -> float:
	return clampf(snappedf(v, STEP), LO, HI)


## Écrit l'échelle (bornée, au pas de 0,01) ; [1, 1, 1] retire la clé.
static func set_scale(o: Dictionary, s: Vector3) -> void:
	var q := Vector3(snap_factor(s.x), snap_factor(s.y), snap_factor(s.z))
	if q.is_equal_approx(Vector3.ONE):
		o.erase("echelle")
	else:
		o["echelle"] = [q.x, q.y, q.z]


## Écrit l'inclinaison (bornée, au dixième de degré) ; [0, 0] retire la clé.
static func set_incl(o: Dictionary, v: Vector2) -> void:
	var q := Vector2(snap_deg(v.x), snap_deg(v.y))
	if absf(q.x) < INCL_STEP * 0.5 and absf(q.y) < INCL_STEP * 0.5:
		o.erase("incl")
	else:
		o["incl"] = [q.x, q.y]


## Angle d'inclinaison ramené dans ]-180, 180] et arrondi au dixième.
static func snap_deg(a: float) -> float:
	var w := wrapf(a, -180.0, 180.0)
	if w <= -180.0 + 0.0001:
		w = 180.0
	var s := snappedf(w, INCL_STEP)
	return 0.0 if absf(s) < INCL_STEP * 0.5 else s


# ------------------------------------------------------------------ ce qui change d'échelle (§ 1)

## Montage d'un décor : « sol », « mur » ou « plafond ».
static func mount_of(o: Dictionary) -> String:
	return MapCatalog.prefab_mount(String(o.get("prefab", "")))


## Définition (catalogue ou prefab de la carte) d'un décor posé.
static func def_of(o: Dictionary) -> Dictionary:
	return MapCatalog.prefab_def(String(o.get("prefab", ""))) if String(o.get("type", "")) == "prefab" else {}


## Noms [fr, en] des objets qui empêchent `o` de changer d'échelle : pour un
## prefab de la carte, ses parties non redimensionnables (unscalable_parts) ;
## pour tout ce qui n'est pas un décor « prefab », l'objet lui-même. [] :
## redimensionnable.
static func blockers_of(o: Dictionary) -> Array:
	var t := String(o.get("type", ""))
	if t != "prefab":
		return [phrase(o)]
	var d := def_of(o)
	if d.is_empty():
		return [phrase(o)]
	if d.has("fixe"):
		return (d.fixe as Array).duplicate(true)
	return []


## Le décor peut-il changer d'échelle (E1, E2) ?
static func scalable(o: Dictionary) -> bool:
	return String(o.get("type", "")) == "prefab" and not def_of(o).is_empty() and blockers_of(o).is_empty()


## Le décor peut-il s'incliner (E6) ? Redimensionnable et posé au sol (un
## décor qui en porte un autre ne s'incline pas : tilt_refusal, avec la carte).
static func tiltable(o: Dictionary) -> bool:
	return scalable(o) and mount_of(o) == "sol"


## Échelle uniforme seulement (§ 2.1) : une partie, une copie ou un pavé du
## décor est tourné en biais dans son repère (angle non multiple de 90°).
static func uniform_only(o: Dictionary) -> bool:
	return def_uniform_only(def_of(o))


static func def_uniform_only(d: Dictionary) -> bool:
	if d.has("uniforme"):
		return bool(d.uniforme)
	for cp in d.get("copies", []):
		if cp is Array and cp.size() > 2 and not _quarter_rad(float(cp[2])):
			return true
	for b in d.get("boxes", []):
		if b is Dictionary and not _quarter_rad(float(b.get("yaw", 0.0))):
			return true
	for p in d.get("parties", []):
		if p is Dictionary and posmod(int(p.get("rot", 0)), 90) != 0:
			return true
	return false


static func _quarter_rad(a: float) -> bool:
	var q := a / (PI * 0.5)
	return absf(q - roundf(q)) < 0.001


## Parties non redimensionnables d'une définition de prefab de la carte
## (§ 1.2) : noms [fr, en] des objets de jeu qu'elle contient (récursif pour
## un prefab cité dans un autre), d'après le tableau du § 1.1. Une partie
## « decor » du catalogue (PREFABS) se redimensionne ; tout autre objet du
## catalogue (atout, arme, boîte, Pack-a-Punch...) non. Calculée à la lecture
## de la bibliothèque (MapCatalog.set_map_prefabs), jamais écrite.
static func unscalable_parts(d: Dictionary, defs := {}, depth := 0) -> Array:
	var out := []
	if depth > 4:
		return out
	for p in d.get("parties", []):
		if not p is Dictionary:
			continue
		var id := String(p.get("decor", ""))
		if p.has("type"):
			# Partie décrite comme un objet posé (objet de jeu dans un prefab).
			var o: Dictionary = p
			if String(o.type) == "prefab":
				id = String(o.get("prefab", ""))
			else:
				out.append(phrase(o))
				continue
		if MapCatalog.PREFABS.has(id):
			continue
		var pid := MapPrefabLib.pid_of(id)
		if pid != "":
			var sub: Variant = defs.get(pid, MapCatalog.prefab_def(id))
			if sub is Dictionary:
				for n in unscalable_parts(sub, defs, depth + 1):
					if not out.has(n):
						out.append(n)
			continue
		var it := MapCatalog.item(id)
		if it.is_empty():
			out.append([id, id, id, id])
		else:
			var ph := _phrase_of_item(it, String(it.get("make", {}).get("type", id)))
			if not out.has(ph):
				out.append(ph)
	return out


## Nom d'un objet avec son article, dans les deux langues : « un
## Pack-a-Punch », « l'atout Juggernog », « une boîte mystère » ->
## [fr, en, nom fr seul, nom en seul].
static func phrase(o: Dictionary) -> Array:
	return _phrase_of_item(MapCatalog.item_for(o), String(o.get("type", "")))


## Types dont le nom français est féminin (article « une »).
const _FEM := ["boite", "porte", "fenetre", "porte_courant", "grenades", "apparition", "arrivee", "caisse", "lampe", "escalier", "piece", "barriere", "bloc_invisible"]


static func _phrase_of_item(it: Dictionary, t: String) -> Array:
	var fr := String(it.get("fr", t))
	var en := String(it.get("en", fr))
	match t:
		"atout":
			return ["l'atout %s" % fr, "the %s perk" % en, fr, en]
		"arme":
			return ["l'arme murale %s" % fr, "the %s wall weapon" % en, fr, en]
		"pap":
			return ["un %s" % fr, "a %s" % en, fr, en]
	var low_fr := fr.left(1).to_lower() + fr.substr(1) if fr.length() > 1 and fr.substr(1, 1) == fr.substr(1, 1).to_lower() else fr
	var low_en := en.left(1).to_lower() + en.substr(1) if en.length() > 1 and en.substr(1, 1) == en.substr(1, 1).to_lower() else en
	var art_en := "an" if low_en.left(1) in ["a", "e", "i", "o", "u"] else "a"
	return ["%s %s" % ["une" if t in _FEM else "un", low_fr], "%s %s" % [art_en, low_en], fr, en]


## Liste de noms (phrase) -> « un Pack-a-Punch, l'atout Juggernog et 2
## autres » ; `bare` : les noms seuls (« Pack-a-Punch, Juggernog »).
static func names_text(names: Array, bare := false) -> Array:
	if names.is_empty():
		return ["", ""]
	var fr := []
	var en := []
	var i0 := 2 if bare else 0
	for i in mini(names.size(), MAX_NAMED):
		var n: Array = names[i]
		fr.append(String(n[i0] if n.size() > i0 else n[0]))
		en.append(String(n[i0 + 1] if n.size() > i0 + 1 else n[1]))
	var rest := names.size() - MAX_NAMED
	if rest > 0:
		return [", ".join(fr) + " et %d autre%s" % [rest, "s" if rest > 1 else ""], ", ".join(en) + " and %d other%s" % [rest, "s" if rest > 1 else ""]]
	if fr.size() == 2:
		return ["%s et %s" % fr, "%s and %s" % en]
	return [fr[0], en[0]]


## Nom affiché d'un élément (décor : son nom ; prefab de la carte : le sien).
static func label_of(o: Dictionary) -> Array:
	var it := MapCatalog.item_for(o)
	var fr := String(it.get("fr", o.get("type", "")))
	return [fr, String(it.get("en", fr))]


## Raison du refus d'échelle de `o` ([fr, en] ; [] : permise). Nomme l'objet
## (barre d'état, MCP) : « Échelle impossible : « Coin Pack-a-Punch »
## contient un Pack-a-Punch (objet de jeu à taille fixe) ».
static func scale_refusal(o: Dictionary) -> Array:
	if String(o.get("type", "")) != "prefab" or def_of(o).is_empty():
		var ph := phrase(o)
		return ["Échelle impossible : %s garde sa taille (objet de jeu, ouverture ou construction)" % ph[0],
			"Scale impossible: %s keeps its size (game object, opening or building element)" % ph[1]]
	var b := blockers_of(o)
	if b.is_empty():
		return []
	var nm := label_of(o)
	var t := names_text(b)
	return ["Échelle impossible : « %s » contient %s (objet de jeu à taille fixe)" % [nm[0], t[0]],
		"Scale impossible: \"%s\" contains %s (fixed-size game object)" % [nm[1], t[1]]]


## Raison du refus d'inclinaison de `o` sans la carte ([fr, en] ; [] : permise).
static func tilt_refusal(o: Dictionary) -> Array:
	if String(o.get("type", "")) != "prefab" or def_of(o).is_empty():
		return ["Inclinaison impossible : seul le décor posé au sol s'incline", "Tilt impossible: only floor props can tilt"]
	if not blockers_of(o).is_empty():
		var t := names_text(blockers_of(o))
		return ["Inclinaison impossible : objet de jeu (%s), reste droit" % t[0], "Tilt impossible: game object (%s), stays upright" % t[1]]
	match mount_of(o):
		"mur":
			return ["Inclinaison impossible : un décor mural suit son mur", "Tilt impossible: a wall prop follows its wall"]
		"plafond":
			return ["Inclinaison impossible : un décor du plafond pend droit", "Tilt impossible: a ceiling prop hangs straight"]
	return []


## Premier élément non redimensionnable d'une sélection ({} : tous le sont).
static func group_blocker(objs: Array) -> Dictionary:
	for o in objs:
		if o is Dictionary and not scalable(o):
			return o
	return {}


## Refus d'échelle d'une sélection (Q2 : bloquée si un seul élément ne
## change pas d'échelle, message qui le nomme) ; [] : permise.
static func group_refusal(objs: Array) -> Array:
	var b := group_blocker(objs)
	if b.is_empty():
		return []
	var ph := phrase(b)
	if String(b.get("type", "")) == "prefab" and not blockers_of(b).is_empty():
		var nm := label_of(b)
		var t := names_text(blockers_of(b))
		return ["Échelle impossible : la sélection contient « %s » (%s)" % [nm[0], t[0]], "Scale impossible: the selection contains \"%s\" (%s)" % [nm[1], t[1]]]
	return ["Échelle impossible : la sélection contient %s" % ph[0], "Scale impossible: the selection contains %s" % ph[1]]


# ------------------------------------------------------------------ dimensions

## Dimensions d'origine (m) [largeur, profondeur, hauteur] du décor (emprise et
## hauteur du catalogue ou du prefab de la carte).
static func base_dims(o: Dictionary) -> Vector3:
	var d := def_of(o)
	if d.is_empty():
		var fp := MapCatalog.footprint(o)
		return Vector3(fp.x * MapGeom.CELL, fp.y * MapGeom.CELL, 0.0)
	var fp: Array = d.get("fp", [1, 1])
	return Vector3(float(fp[0]) * MapGeom.CELL, float(fp[1]) * MapGeom.CELL, float(d.get("h", 1.0)))


## Dimensions finales (m) [largeur, profondeur, hauteur] dans le repère de l'objet.
static func dims(o: Dictionary) -> Vector3:
	return base_dims(o) * scale_of(o)


## Emprise (m) dans le repère de l'objet : [largeur, profondeur] (objet
## mural : [le long du mur, profondeur]), échelle comprise.
static func foot_m(o: Dictionary) -> Vector2:
	var fp := MapCatalog.footprint(o)
	var s := scale_of(o)
	return Vector2(fp.x * MapGeom.CELL * s.x, fp.y * MapGeom.CELL * s.y)


## Cases (0,5 m) le long du mur d'un objet mural, échelle comprise.
static func wall_cells(o: Dictionary) -> int:
	if not is_scaled(o):
		return MapCatalog.footprint(o).x
	return maxi(1, ceili(foot_m(o).x / MapGeom.CELL - 0.01))


## Échelle `s` admise pour `o` ? [fr, en] sinon (bornes par axe, dimension
## finale de 0,05 à 30 m, emprise de 20 m au plus, uniforme imposée).
static func check_scale(o: Dictionary, s: Vector3) -> Array:
	for i in 3:
		if not is_finite(s[i]) or s[i] < LO - 0.0001 or s[i] > HI + 0.0001:
			return ["échelle hors des bornes (×%s à ×%s par axe)" % [MapCatalog.short_num(LO), MapCatalog.short_num(HI)],
				"scale out of bounds (×%s to ×%s per axis)" % [str(LO), str(HI)]]
	if uniform_only(o) and not is_uniform(s):
		return ["parties tournées en biais : échelle uniforme seulement", "parts turned at an angle: uniform scale only"]
	var f := base_dims(o) * s
	for i in 3:
		if base_dims(o)[i] > 0.0 and (f[i] < MIN_DIM - 0.0001 or f[i] > MAX_DIM + 0.0001):
			return ["dimension finale hors des bornes (%s à %s m)" % [MapCatalog.short_num(MIN_DIM), MapCatalog.short_num(MAX_DIM)],
				"final size out of bounds (%s to %s m)" % [str(MIN_DIM), str(MAX_DIM)]]
	if f.x > MAX_FOOT + 0.0001 or f.y > MAX_FOOT + 0.0001:
		return ["emprise au sol trop grande (%s m au plus par côté)" % MapCatalog.short_num(MAX_FOOT), "footprint too large (%s m at most per side)" % str(MAX_FOOT)]
	return []


# ------------------------------------------------------------------ orientation (§ 3.1)

## Rotations élémentaires dans le repère de la CARTE (X est, Y sud, Z haut),
## sens horaire à l'écran dans la vue qui regarde l'axe de bout. Les Basis
## servent ici de matrices 3 × 3 (colonnes = images des axes X, Y, Z).
static func rz(deg: float) -> Basis:
	var a := deg_to_rad(deg)
	return Basis(Vector3(cos(a), sin(a), 0), Vector3(-sin(a), cos(a), 0), Vector3(0, 0, 1))


static func ry(deg: float) -> Basis:
	var a := deg_to_rad(deg)
	return Basis(Vector3(cos(a), 0, -sin(a)), Vector3(0, 1, 0), Vector3(sin(a), 0, cos(a)))


static func rx(deg: float) -> Basis:
	var a := deg_to_rad(deg)
	return Basis(Vector3(1, 0, 0), Vector3(0, cos(a), sin(a)), Vector3(0, -sin(a), cos(a)))


## Rotation d'un axe du monde de la carte (0 : X, 1 : Y, 2 : Z).
static func axis_rot(axis: int, deg: float) -> Basis:
	match axis:
		0:
			return rx(deg)
		1:
			return ry(deg)
	return rz(deg)


## Orientation (carte) d'un lacet `rot` et d'une inclinaison `incl` (degrés).
static func orient(rot: float, incl: Vector2) -> Basis:
	return rz(rot) * ry(incl.y) * rx(incl.x)


## Orientation (carte) d'un objet posé.
static func matrix(o: Dictionary) -> Basis:
	return orient(float(MapGeom.rot_of(o)), incl_of(o))


## Orientation (carte) -> {rot (degrés, réel), incl Vector2 (degrés)} :
## décomposition Rz · Ry · Rx (Ry dans [-90, 90]).
static func decompose(m: Basis) -> Dictionary:
	var sb := clampf(-m.x.z, -1.0, 1.0)
	var b := asin(sb)
	var a := 0.0
	var r := 0.0
	if absf(cos(b)) > 0.000001:
		a = atan2(m.y.z, m.z.z)
		r = atan2(m.x.y, m.x.x)
	else:
		r = atan2(-m.y.x, m.y.y)
	return {"rot": rad_to_deg(r), "incl": Vector2(rad_to_deg(a), rad_to_deg(b))}


## Écrit une orientation (carte) dans l'objet : « rot » au degré (0 à 359),
## « incl » au dixième (écart d'arrondi < 0,5°, invisible).
static func set_orientation(o: Dictionary, m: Basis) -> void:
	var d := decompose(m)
	var r := MapGeom.norm_deg(float(d.rot))
	if r == 0:
		o.erase("rot")
	else:
		o["rot"] = r
	set_incl(o, d.incl)


## Matrice de passage carte <-> jeu (jeu : x est, y haut, z sud).
const P := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))


## Rotation (repère du JEU) d'une orientation de la carte.
static func to_game(m: Basis) -> Basis:
	return P * m * P


## Orientation dans le repère du jeu d'un objet posé (rotation seule).
static func game_basis(o: Dictionary) -> Basis:
	return to_game(matrix(o))


## Échelle dans le repère local du JEU (x largeur, y hauteur, z profondeur).
static func game_scale(o: Dictionary) -> Vector3:
	var s := scale_of(o)
	return Vector3(s.x, s.z, s.y)


## Demi-hauteur verticale (m) de la boîte orientée : du centre au point le plus bas.
static func half_z(o: Dictionary) -> float:
	var m := matrix(o)
	var h := dims(o) * 0.5
	return absf(m.x.z) * h.x + absf(m.y.z) * h.y + absf(m.z.z) * h.z


## Hauteur verticale (m) de l'objet : du point le plus bas au plus haut.
static func height(o: Dictionary) -> float:
	if not is_tilted(o):
		return dims(o).z
	return 2.0 * half_z(o)


## Coins (carte : x, y en m, z en m au-dessus du sol de l'étage) de la boîte
## orientée d'un décor au sol, posée à sa hauteur « z » (point le plus bas).
static func corners(o: Dictionary) -> Array:
	var m := matrix(o)
	var h := dims(o) * 0.5
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var c := Vector3(p.x, p.y, MapVertical.decor_z(o) + half_z(o))
	var out := []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				out.append(c + m * Vector3(h.x * sx, h.y * sy, h.z * sz))
	return out


## Emprise au sol (m) d'un décor au sol ou au plafond : le rectangle tourné
## (échelle comprise) ; incliné, la projection de sa boîte orientée
## (enveloppe convexe, même sens de parcours que le rectangle).
static func ground_poly(o: Dictionary) -> PackedVector2Array:
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var d := dims(o)
	var rect := MapGeom.rot_rect_poly(p, Vector2(d.x, d.y), MapGeom.rot_of(o))
	if not is_tilted(o):
		return rect
	var pts := PackedVector2Array()
	for c in corners(o):
		pts.append(Vector2(c.x, c.y))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	if signf(_signed_area(hull)) != signf(_signed_area(rect)):
		hull.reverse()
	return hull


static func _signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


## Décalage (repère du JEU, m) de l'origine du modèle par rapport au point
## (position, z) d'un décor au sol : nul s'il n'est pas incliné ; incliné,
## la boîte tourne autour de son centre et son point le plus bas reste à « z ».
static func floor_offset(o: Dictionary) -> Vector3:
	if not is_tilted(o):
		return Vector3.ZERO
	var m := matrix(o)
	var hz := dims(o).z * 0.5
	var off := Vector3(0, 0, half_z(o)) - m * Vector3(0, 0, hz)
	return P * off


## Pavé de collision {center, size, yaw} (coordonnées de l'objet, repère du
## jeu) mis à l'échelle de `o` : centre × échelle, taille × échelle dans le
## repère du pavé (axes échangés pour un lacet de 90° ou 270°). Pavé tourné
## en biais et échelle non uniforme (pavés d'un modèle du catalogue, comme la
## pile de caisses) : sa boîte englobante droite, mise à l'échelle (un peu
## plus grande, jamais cisaillée).
## -> {center: Vector3, size: Vector3, yaw: float}
static func scaled_box(o: Dictionary, bx: Dictionary) -> Dictionary:
	var gs := game_scale(o)
	var c: Array = bx.center
	var sz: Array = bx.size
	var yaw := float(bx.get("yaw", 0.0))
	var size := Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	var q := posmod(roundi(yaw / (PI * 0.5)), 2)
	if _quarter_rad(yaw):
		size *= Vector3(gs.z, gs.y, gs.x) if q == 1 else gs
	elif is_uniform(gs):
		size *= gs.x
	else:
		var ca := absf(cos(yaw))
		var sa := absf(sin(yaw))
		size = Vector3(ca * size.x + sa * size.z, size.y, sa * size.x + ca * size.z) * gs
		yaw = 0.0
	return {"center": Vector3(float(c[0]), float(c[1]), float(c[2])) * gs, "size": size, "yaw": yaw}


# ------------------------------------------------------------------ fichier (format 14)

## Clés du format 14 remises en ordre (fichier écrit à la main) : valeur
## illisible ou par défaut retirée, sinon bornée et arrondie ; « incl »
## retirée d'un décor qui ne s'incline pas ; échelle d'un prefab bloqué
## retirée. Rend le message de chargement [fr, en] ([] : rien de retiré pour
## une raison de règle).
static func tidy(o: Dictionary) -> Array:
	var t := String(o.get("type", ""))
	if t != "prefab":
		o.erase("echelle")
		o.erase("incl")
		return []
	if o.has("echelle"):
		var v: Variant = o.echelle
		var ok: bool = v is Array and v.size() == 3 and (v as Array).all(func(x): return (x is float or x is int) and is_finite(float(x)))
		if not ok:
			o.erase("echelle")
		else:
			set_scale(o, read_scale(v))
	if o.has("incl"):
		var v: Variant = o.incl
		var ok: bool = v is Array and v.size() == 2 and (v as Array).all(func(x): return (x is float or x is int) and is_finite(float(x)))
		if not ok:
			o.erase("incl")
		else:
			set_incl(o, read_incl(v))
	if def_of(o).is_empty():
		return []
	var msg := []
	if o.has("echelle") and not blockers_of(o).is_empty():
		o.erase("echelle")
		var r := scale_refusal(o)
		msg = ["%s : %s (échelle retirée)" % [String(o.get("id", "?")), r[0]], "%s: %s (scale removed)" % [String(o.get("id", "?")), r[1]]]
	if o.has("echelle") and uniform_only(o) and not is_uniform(scale_of(o)):
		var s := scale_of(o)
		var u := snap_factor((s.x + s.y + s.z) / 3.0)
		set_scale(o, Vector3(u, u, u))
	if o.has("incl") and not tiltable(o):
		o.erase("incl")
	return msg


## Contrôle d'un objet posé d'une carte reçue ou ouverte (§ 5.3), avec la
## définition de son décor (`d` : catalogue, ou prefab.json lu ; {} : inconnu)
## et les noms des objets non redimensionnables qu'il contient (`fixed`).
## [fr, en] si refusé, [] sinon. Les bornes des valeurs sont vérifiées par le
## schéma (MapCatalog.allowed_kinds).
static func check_object(o: Dictionary, d: Dictionary, fixed: Array) -> Array:
	var has_s := o.has("echelle")
	var has_i := o.has("incl")
	if not (has_s or has_i):
		return []
	if String(o.get("type", "")) != "prefab":
		return ["échelle ou inclinaison sur un élément qui n'est pas un décor", "scale or tilt on an element that is not a prop"]
	if d.is_empty():
		return []
	var mount := String(d.get("mount", "sol"))
	if has_i and mount != "sol":
		return ["inclinaison sur un décor qui n'est pas posé au sol", "tilt on a prop that does not stand on the floor"]
	if not fixed.is_empty():
		if has_s and not read_scale(o.echelle).is_equal_approx(Vector3.ONE):
			return ["échelle d'un prefab qui contient un objet de jeu", "scale of a prefab that contains a game object"]
		if has_i:
			return ["inclinaison d'un prefab qui contient un objet de jeu", "tilt of a prefab that contains a game object"]
	if has_s:
		var s := read_scale(o.echelle)
		if def_uniform_only(d) and not is_uniform(s):
			return ["parties tournées en biais : échelle uniforme exigée", "parts turned at an angle: uniform scale required"]
		var fp: Array = d.get("fp", [1, 1])
		var f := Vector3(float(fp[0]) * MapGeom.CELL, float(fp[1]) * MapGeom.CELL, float(d.get("h", 1.0))) * s
		if f.x > MAX_FOOT + 0.0001 or f.y > MAX_FOOT + 0.0001:
			return ["emprise du décor mis à l'échelle trop grande (%s m au plus)" % MapCatalog.short_num(MAX_FOOT), "scaled prop footprint too large (%s m at most)" % str(MAX_FOOT)]
		for i in 3:
			if f[i] < MIN_DIM - 0.0001 or f[i] > MAX_DIM + 0.0001:
				return ["dimension du décor mis à l'échelle hors des bornes (%s à %s m)" % [MapCatalog.short_num(MIN_DIM), MapCatalog.short_num(MAX_DIM)],
					"scaled prop size out of bounds (%s to %s m)" % [str(MIN_DIM), str(MAX_DIM)]]
	return []


# ------------------------------------------------------------------ règles de pose (§ 2.3, § 3.4)

## Un décor posé au sol porte-t-il quelque chose ? Incliné : jamais (son
## dessus n'est pas plat, § 3.4).
static func carries(o: Dictionary) -> bool:
	return not is_tilted(o)


## Vérifie un décor après un changement d'échelle ou d'orientation (sur la
## carte `doc`, validateur `v`) : échelle permise et bornée, inclinaison
## permise, décor porteur (« un décor est posé dessus »), hauteur sous le
## plafond réel, décor bloquant qui reste posé, règles de pose (emprise
## orientée : chevauchements, pièce). `before` : l'élément avant le
## changement (décors qui reposaient dessus) ; `held` : ces décors s'ils sont
## déjà connus (geste en cours : calculés une fois). -> {ok} ou {ok: false, fr, en}.
static func check(doc: EditorMap, v: MapValidator, e: Dictionary, before: Dictionary = {}, held: Variant = null) -> Dictionary:
	var t := String(e.get("type", ""))
	if t != "prefab" and (e.has("echelle") or e.has("incl")):
		var rf := scale_refusal(e) if e.has("echelle") else tilt_refusal(e)
		return MapRules.refuse(rf[0], rf[1])
	if is_scaled(e) or (not before.is_empty() and not scale_of(before).is_equal_approx(scale_of(e))):
		var r := scale_refusal(e)
		if not r.is_empty():
			return MapRules.refuse(r[0], r[1])
		var c := check_scale(e, scale_of(e))
		if not c.is_empty():
			return MapRules.refuse(c[0], c[1])
	if is_tilted(e):
		var r := tilt_refusal(e)
		if not r.is_empty():
			return MapRules.refuse(r[0], r[1])
	if not before.is_empty():
		var changed := not scale_of(before).is_equal_approx(scale_of(e)) or not incl_of(before).is_equal_approx(incl_of(e))
		var on_it: Array = held if held is Array else MapVertical.resting_on(doc, before)
		if changed and not on_it.is_empty():
			return MapRules.refuse("un décor est posé dessus : sélectionnez-les ensemble", "a prop stands on it: select them together")
	if v != null:
		if t == "prefab" and mount_of(e) == "sol" and MapVertical.decor_z(e) + height(e) > MapVertical.room_h(v, e) + 0.011:
			var rh := MapVertical.room_h(v, e)
			return MapRules.refuse("trop haut pour le plafond (%s m)" % ("%.2f" % rh).replace(".", ","), "too tall for the ceiling (%.2f m)" % rh)
		var chk := MapVertical.check_pose(doc, v, e)
		if not chk.ok:
			return chk
	return MapRules.check_existing(doc, e)
