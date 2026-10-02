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
