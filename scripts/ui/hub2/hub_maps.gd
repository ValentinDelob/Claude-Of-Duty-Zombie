class_name HubMaps
extends RefCounted
## Cartes jouables depuis le hub (JOUER, salon coop, récapitulatif) : cartes
## du jeu puis cartes perso de l'éditeur, définitions gardées en cache (une
## carte perso n'est relue que si l'un de ses fichiers a changé), nom affiché.

## Identifiant de la ligne du défi de la semaine dans les listes de cartes
## (JOUER, CHANGER DE CARTE du salon) : pas une carte.
const WEEKLY_ROW := "weekly"

## Définitions déjà lues : identifiant -> [date des fichiers, MapDef] (le hub
## se reconstruit souvent, la lecture d'une carte perso est lente).
static var _defs: Dictionary = {}


## Cartes jouables : cartes du jeu (Game.MENU_MAPS) puis cartes perso jouables
## de l'éditeur (user://maps) ; [{id, def, custom}].
static func playable_maps() -> Array:
	var out := []
	for id in Game.MENU_MAPS:
		var def: MapDef = _cached_def(id, 0)
		if def != null:
			out.append({"id": id, "def": def, "custom": false})
	for m in EditorMap.list_maps():
		var cid := EditorMapDef.CUSTOM_PREFIX + String(m.id)
		var cdef := _cached_def(cid, _stamp(String(m.dir))) as EditorMapDef
		if cdef != null and cdef.is_valid():
			out.append({"id": cid, "def": cdef, "custom": true})
	return out


static func _cached_def(id: String, stamp: int) -> MapDef:
	var c: Array = _defs.get(id, [])
	if not c.is_empty() and int(c[0]) == stamp:
		return c[1]
	var def := MapPreview.map_def(id)
	if def != null:  # carte partagée pas encore reçue : relue plus tard
		_defs[id] = [stamp, def]
	return def


## Définition d'une carte (dernière lue par playable_maps si elle existe).
static func def_of(id: String) -> MapDef:
	var c: Array = _defs.get(id, [])
	if not c.is_empty():
		return c[1]
	return _cached_def(id, 0)


## Oublie les définitions lues (tests : cartes perso remplacées).
static func clear_cache() -> void:
	_defs.clear()


## Date de modification la plus récente des fichiers d'un dossier de carte.
static func _stamp(dir: String) -> int:
	var t := 0
	for f in DirAccess.get_files_at(dir):
		t = maxi(t, FileAccess.get_modified_time(dir.path_join(f)))
	return t


## Nom affiché d'une carte (carte perso : nettoyé, jamais du BBCode).
static func map_name(def: MapDef) -> String:
	return CustomMapGuard.clean_display(def.display_name) if def else "..."
