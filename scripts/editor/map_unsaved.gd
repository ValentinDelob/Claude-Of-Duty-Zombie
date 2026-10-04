class_name MapUnsaved
extends RefCounted
## MODIFICATIONS NON ENREGISTRÉES de l'éditeur de cartes (docs/MAP_AUTHORING.md
## § 6) : le dossier de la carte n'est écrit QUE par Fichier > Enregistrer
## (Ctrl+S), Enregistrer sous et l'enregistrement d'une nouvelle carte.
## - Empreinte (signature) : contenu de la carte, indépendant de l'ordre des
##   éléments et des clés ; l'étoile « * » du titre = empreinte différente de
##   celle de l'état enregistré (une annulation qui y ramène l'efface).
## - Copie de RÉCUPÉRATION (jamais dans la carte) : user://maps/_recuperation/
##   (cinq JSON + meta.json : source, nom, date), écrite toutes les 60 s s'il y
##   a du nouveau et avant TESTER ; effacée après un enregistrement réussi,
##   « Quitter sans enregistrer », « Ignorer » ou une sortie sans changement.
##   Encore là au lancement suivant (plantage, fermeture forcée) : l'éditeur
##   propose de la récupérer.
## - Boîte « Enregistrer / Quitter sans enregistrer / Annuler » (ask).

## Taille maximale du meta.json de la copie de récupération.
const MAX_META_BYTES := 256 * 1024


## Dossier de la copie de récupération (dossier interne : « _ » en tête, ni
## listé, ni supprimable par Ouvrir > Supprimer).
static func recovery_dir() -> String:
	return EditorMap.maps_root().path_join("_recuperation")


## Ancien dossier de la sauvegarde automatique (versions d'avant) : repris
## comme copie de récupération s'il est encore là.
static func legacy_dir() -> String:
	return EditorMap.maps_root().path_join("_autosave")


## Dossier de récupération à proposer au lancement ("" : aucun).
static func pending_dir() -> String:
	for d in [recovery_dir(), legacy_dir()]:
		if EditorMap.is_map_dir(d):
			return d
	return ""


## Dossier de la copie de travail jouée par TESTER (jamais la carte du joueur ;
## identifiant de jeu « perso:_tester »).
const TEST_ID := "_tester"


static func test_dir() -> String:
	return EditorMap.maps_root().path_join(TEST_ID)


## meta.json d'une copie de récupération (source, exemple, nom, date) : {}
## s'il est absent, illisible ou trop gros (256 Ko au plus).
static func read_meta(dir: String) -> Dictionary:
	var txt: Variant = EditorMap.read_text(dir.path_join("meta.json"), MAX_META_BYTES)
	var meta: Variant = JSON.parse_string(txt) if txt != null else null
	return meta if meta is Dictionary else {}


## Dossier d'origine lu dans un meta.json acceptable : un dossier de carte
## directement dans le dossier des cartes, identifiant admis
## (EditorMap.valid_id), jamais un dossier interne (« _... »).
static func source_ok(src: String) -> bool:
	if src == "" or src.contains(".."):
		return false
	var root := EditorMap._abs(EditorMap.maps_root()).trim_suffix("/")
	var target := EditorMap._abs(src).trim_suffix("/")
	var id := target.get_file()
	return target.get_base_dir() == root and EditorMap.valid_id(id) and not id.begins_with("_")


## Écrit la copie de récupération de `m` (dossier de la carte d'origine
## `source`, "" si jamais enregistrée).
static func write_recovery(m: EditorMap, source: String, is_example: bool) -> Error:
	var dir := recovery_dir()
	var err := m.save_dir(dir)
	if err != OK:
		return err
	var f := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"source": source, "example": is_example, "name": m.display_name(),
		"time": int(Time.get_unix_time_from_system())}))
	f.close()
	# L'ancien dossier (versions d'avant) n'a plus lieu d'être.
	_remove(legacy_dir())
	return OK


## Efface la copie de récupération (et l'ancien dossier _autosave).
static func drop_recovery() -> void:
	_remove(recovery_dir())
	_remove(legacy_dir())


## Efface un dossier interne (récupération, copie de TESTER) : seulement un
## enfant direct « _... » du dossier des cartes.
static func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var root := EditorMap._abs(EditorMap.maps_root()).trim_suffix("/")
	var target := EditorMap._abs(dir).trim_suffix("/")
	if target.get_base_dir() != root or not target.get_file().begins_with("_"):
		push_warning("[MapUnsaved] effacement refusé : %s" % dir)
		return
	EditorMap._remove_tree(dir)


## Date lisible d'une copie de récupération (heure locale).
static func when_text(meta: Dictionary) -> String:
	var t := int(meta.get("time", 0))
	if t <= 0:
		return "?"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(t + bias, true)


## Empreinte du contenu de la carte : mêmes éléments (dans n'importe quel
## ordre, clés dans n'importe quel ordre, 17 et 17.0 confondus) = même
## empreinte. Les modèles des prefabs comptent par leur sha256 (model_sha).
static func signature(m: EditorMap) -> String:
	if m == null:
		return ""
	var by_id := func(a: Variant, b: Variant) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")) if a is Dictionary and b is Dictionary else false
	var parts := PackedStringArray()
	parts.append(JSON.stringify(EditorMap._ints(m.carte), "", true))
	for list in [m.pieces, m.ouvertures, m.objets, m.zones]:
		var arr: Array = (list as Array).duplicate()
		arr.sort_custom(by_id)
		parts.append(JSON.stringify(EditorMap._ints(arr), "", true))
	parts.append(m.depart)
	parts.append(JSON.stringify(EditorMap._ints(m.prefabs), "", true))
	var pids := m.models.keys()
	pids.sort()
	for pid in pids:
		parts.append("%s:%s" % [pid, model_sha(String(m.models[pid]))])
	# Format 15 : textures de la carte (définitions et images écrites).
	if not m.textures.is_empty():
		parts.append(JSON.stringify(EditorMap._ints(m.textures), "", true))
		var tk := MapTextureLib.texts_of(m)
		var keys := tk.keys().filter(func(k): return MapTextureLib.is_binary_key(k))
		keys.sort()
		for k in keys:
			parts.append("%s:%s" % [k, model_sha(String(tk[k]))])
	return "\n".join(parts).sha256_text()


## Empreintes sha256 des modèles de prefab (base64, lourds), calculées une
## fois par contenu : clé = taille + hachage rapide (String.hash). Le cache
## garde bien plus d'entrées qu'une carte n'a de modèles (aucun quota : une
## carte à 100+ modèles ne doit pas tout recalculer à chaque changement).
static var _model_sha: Dictionary = {}
const MODEL_SHA_CACHE := 4096


static func model_sha(data: String) -> String:
	var key := "%d:%d" % [data.length(), data.hash()]
	if not _model_sha.has(key):
		if _model_sha.size() > MODEL_SHA_CACHE:
			_model_sha.clear()
		_model_sha[key] = data.sha256_text()
	return _model_sha[key]


## Boîte au style de l'éditeur (fille de `parent`) : « Enregistrer » (Entrée),
## « Quitter sans enregistrer », « Annuler » (Échap, croix). `on_choice`
## reçoit "save", "discard" ou "cancel" (une seule fois).
static func ask(parent: Node, title_text: String, text: String, on_choice: Callable,
		save_text := "", discard_text := "", cancel_text := "") -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.name = "UnsavedDialog"
	d.title = title_text
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(int(EditorUi.px(460.0)), 0)
	d.ok_button_text = save_text if save_text != "" else Lang.t("Enregistrer", "Save")
	d.cancel_button_text = cancel_text if cancel_text != "" else Lang.t("Annuler", "Cancel")
	var discard := d.add_button(discard_text if discard_text != "" else Lang.t("Quitter sans enregistrer", "Quit without saving"), false, "discard")
	discard.name = "Discard"
	d.set_meta("discard", discard)
	parent.add_child(d)
	var state := {"done": false}
	var finish := func(choice: String) -> void:
		if state.done:
			return
		state.done = true
		d.hide()
		d.queue_free()
		on_choice.call(choice)
	d.confirmed.connect(func(): finish.call("save"))
	d.canceled.connect(func(): finish.call("cancel"))
	d.custom_action.connect(func(action: StringName):
		if action == &"discard":
			finish.call("discard"))
	d.popup_centered()
	# Entrée = Enregistrer : le bouton a le focus.
	d.get_ok_button().grab_focus.call_deferred()
	return d
