class_name MapPrefabTools
extends Node
## PREFABS DE LA CARTE dans l'éditeur (format 10, docs/MAP_OBJECTS.md § 11,
## MapPrefabLib) : catégorie « Prefabs de la carte » de l'inventaire.
##   - « Créer… » : glisser un rectangle sur le plan autour du décor à grouper
##     (décor du catalogue de l'étage affiché) ; nom ; le décor choisi peut
##     être remplacé par un seul prefab posé à sa place (annulable : Ctrl+Z) ;
##   - « Importer… » : un fichier .glb ou .gltf du disque, COPIÉ dans le
##     dossier de la carte (prefabs/<pid>/model.glb, à l'enregistrement) ;
##     emprise et collision (un pavé de sa boîte englobante) calculées ;
##   - sur chaque prefab : ⚙ (nom ; modèle : échelle et collision), ✕
##     (supprimer ; refusé tant qu'il est posé, ou supprimé avec ses objets
##     posés après confirmation).
## La bibliothèque des prefabs n'est pas dans l'historique d'annulation (comme
## un fichier) ; en session, seul l'hôte la change (la carte est renvoyée aux
## invités ; les modèles importés n'y passent pas : une boîte à leur place).

var ed: MapEditor
## Rectangle de capture en cours (« Créer… » : le prochain glissé sur le plan).
var capturing := false
var _file_dialog: FileDialog


# ------------------------------------------------------------------ inventaire

## Cases « Créer… » et « Importer… » en tête de la grille de l'inventaire.
func add_inventory_actions(grid: GridContainer) -> void:
	grid.add_child(_action(Lang.t("+ Créer…", "+ Create…"),
		Lang.t("Grouper du décor posé en un prefab : glissez un rectangle autour sur le plan", "Group placed props into a prefab: drag a rectangle around them on the plan"),
		func():
			ed.toggle_inventory()
			start_capture()))
	grid.add_child(_action(Lang.t("Importer…", "Import…"),
		Lang.t("Importer un modèle .glb ou .gltf (copié dans le dossier de la carte ; %d Mo au plus)", "Import a .glb or .gltf model (copied into the map folder; %d MB at most)") % (MapPrefabLib.MAX_MODEL_BYTES >> 20),
		func():
			ed.toggle_inventory()
			import_dialog()))


func _action(text: String, tip: String, on_press: Callable) -> Control:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(84, 84)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(on_press)
	return b


## Boutons ⚙ et ✕ sous un prefab de l'inventaire.
func add_item_buttons(box: VBoxContainer, it: Dictionary) -> void:
	var pid := String(it.get("map", ""))
	if pid == "":
		return
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var e := Button.new()
	e.text = "⚙"
	e.tooltip_text = Lang.t("Renommer, régler", "Rename, adjust")
	e.pressed.connect(func(): edit_dialog(pid))
	h.add_child(e)
	var d := Button.new()
	d.text = "✕"
	d.tooltip_text = Lang.t("Supprimer ce prefab", "Delete this prefab")
	d.pressed.connect(func(): delete_dialog(pid))
	h.add_child(d)
	box.add_child(h)


func _refresh_inventory() -> void:
	if ed.inventory != null and ed.inventory.visible:
		ed.inventory.show_category(ed.inventory.cat)


## La bibliothèque peut-elle être changée ? (en session : l'hôte seulement)
func _can_edit() -> bool:
	if ed.collab != null and ed.collab.role == MapCollab.Role.GUEST:
		ed.set_status(Lang.t("Seul l'hôte de la session change les prefabs de la carte", "Only the session host changes the map prefabs"), true)
		return false
	return true


## Après un changement de la bibliothèque : carte modifiée, panneaux,
## inventaire, invités de la session.
func _library_changed() -> void:
	ed.doc.activate_prefabs()
	ed.changed()
	_refresh_inventory()
	if ed.collab != null:
		ed.collab.broadcast_map()


static func clean_name(s: String) -> String:
	return CustomMapGuard.clean_display(s.strip_edges(), CustomMapGuard.MAX_NAME)


# ------------------------------------------------------------------ créer (groupe)

func start_capture() -> void:
	if not _can_edit():
		return
	capturing = true
	ed.set_status(Lang.t("Créer un prefab : glissez un rectangle autour du décor à grouper (clic droit : annuler)",
		"Create a prefab: drag a rectangle around the props to group (right click: cancel)"))


func cancel_capture() -> void:
	capturing = false


## Décor du catalogue de l'étage affiché dont le centre est dans `r` (m).
func captured(r: Rect2) -> Array:
	var out := []
	for o in ed.doc.objects_on(ed.floor_k):
		if MapPrefabLib.groupable(o) and r.has_point(MapGeom.v2(o.position)):
			out.append(o)
	return out


func finish_capture(r: Rect2) -> void:
	capturing = false
	var objs := captured(r)
	if objs.is_empty():
		ed.set_status(Lang.t("Aucun décor du catalogue dans le rectangle", "No catalogue prop in the rectangle"), true)
		return
	create_dialog(objs)


func create_dialog(objs: Array) -> void:
	var d := ConfirmationDialog.new()
	d.title = Lang.t("Créer un prefab", "Create a prefab")
	var box := VBoxContainer.new()
	d.add_child(box)
	var l := Label.new()
	l.text = Lang.t("%d décor(s) groupé(s). Nom du prefab :", "%d prop(s) grouped. Prefab name:") % objs.size()
	box.add_child(l)
	var e := LineEdit.new()
	e.text = Lang.t("Prefab %d", "Prefab %d") % (ed.doc.prefabs.size() + 1)
	e.max_length = CustomMapGuard.MAX_NAME
	e.custom_minimum_size = Vector2(360, 0)
	box.add_child(e)
	var rep := CheckBox.new()
	rep.text = Lang.t("Remplacer ce décor par le prefab (à la même place)", "Replace these props with the prefab (same place)")
	rep.button_pressed = true
	box.add_child(rep)
	d.ok_button_text = Lang.t("Créer", "Create")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	ed.add_child(d)
	d.confirmed.connect(func():
		create_from_objects(objs, e.text, rep.button_pressed)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	e.grab_focus.call_deferred()


## Prefab groupe tiré de `objs` (décor du catalogue posé), nommé `name` ;
## `replace` : ces objets remplacés par un prefab posé à leur place. Rend
## l'identifiant du prefab ("" : refusé, raison dans la barre d'état).
func create_from_objects(objs: Array, name: String, replace := true) -> String:
	if not _can_edit():
		return ""
	var nm := clean_name(name)
	if nm == "" or not CustomMapGuard.name_ok(nm):
		ed.set_status(Lang.t("Nom de prefab refusé", "Prefab name refused"), true)
		return ""
	if ed.doc.prefabs.size() >= MapPrefabLib.MAX_PREFABS:
		ed.set_status(Lang.t("Trop de prefabs dans la carte (%d au plus)", "Too many prefabs in the map (%d at most)") % MapPrefabLib.MAX_PREFABS, true)
		return ""
	var res := MapPrefabLib.from_objects(nm, nm, objs)
	if res.has("error"):
		ed.set_status(Lang.t("Prefab refusé : %s", "Prefab refused: %s") % Lang.t(res.error[0], res.error[1]), true)
		return ""
	var pid := MapPrefabLib.new_pid(nm, ed.doc.prefabs)
	if not ed.doc.set_prefab(pid, res.def):
		ed.set_status(Lang.t("Prefab refusé", "Prefab refused"), true)
		return ""
	if replace:
		var k := int(objs[0].get("etage", ed.floor_k))
		ed.push_undo()
		for o in objs:
			ed.doc.remove(String(o.id))
		ed.add_object({"type": "prefab", "prefab": MapPrefabLib.ref(pid), "position": MapGeom.arr(res.center), "rot": 0}, k)
	_library_changed()
	ed.set_status(Lang.t("Prefab « %s » créé (%d décors) : inventaire, « Prefabs de la carte »", "Prefab \"%s\" created (%d props): inventory, \"Map prefabs\"") % [nm, (res.def.parties as Array).size()])
	return pid


# ------------------------------------------------------------------ importer (modèle)

func import_dialog() -> void:
	if not _can_edit():
		return
	if _file_dialog != null:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.glb, *.gltf ; " + Lang.t("Modèle 3D glTF", "glTF 3D model")])
	_file_dialog.title = Lang.t("Importer un modèle (prefab de la carte)", "Import a model (map prefab)")
	_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_file_dialog.set_meta(EditorUi.SKIP, true)
	_file_dialog.size = Vector2i((Vector2(760, 480) * ed.ui_scale).min(ed.get_viewport_rect().size - Vector2(40, 40)))
	ed.add_child(_file_dialog)
	_file_dialog.file_selected.connect(func(path):
		var pid := import_file(path)
		if pid != "":
			edit_dialog(pid))
	_file_dialog.popup_centered()


## Importe le modèle `path` (.glb ou .gltf) : contrôlé, copié dans la carte
## (enregistré avec elle dans prefabs/<pid>/model.glb). Rend l'identifiant du
## prefab ("" : refusé, raison affichée).
func import_file(path: String, name := "") -> String:
	if not _can_edit():
		return ""
	if ed.doc.prefabs.size() >= MapPrefabLib.MAX_PREFABS or ed.doc.model_count() >= MapPrefabLib.MAX_MODELS:
		_refuse(Lang.t("Trop de prefabs ou de modèles dans la carte (%d prefabs, %d modèles au plus)", "Too many prefabs or models in the map (%d prefabs, %d models at most)") % [MapPrefabLib.MAX_PREFABS, MapPrefabLib.MAX_MODELS])
		return ""
	var got := MapPrefabLib.read_import(path)
	if got.has("error"):
		push_warning("[MapPrefabTools] import refusé (%s) : %s" % [path.get_file(), got.error[0]])
		_refuse(Lang.t(got.error[0], got.error[1]))
		return ""
	var glb: PackedByteArray = got.glb
	var total := glb.size()
	for p in ed.doc.models:
		total += ed.doc.model_bytes(p).size()
	if total > MapPrefabLib.MAX_MODELS_BYTES:
		_refuse(Lang.t("Modèles trop gros pour la carte (%d Mo au plus en tout)", "Models too big for the map (%d MB at most in all)") % (MapPrefabLib.MAX_MODELS_BYTES >> 20))
		return ""
	var nm := clean_name(name if name != "" else path.get_file().get_basename().replace("_", " "))
	if nm == "" or not CustomMapGuard.name_ok(nm):
		nm = Lang.t("Modèle %d", "Model %d") % (ed.doc.model_count() + 1)
	var res := MapPrefabLib.from_model(nm, nm, glb)
	if res.has("error"):
		_refuse(Lang.t(res.error[0], res.error[1]))
		return ""
	var pid := MapPrefabLib.new_pid(nm, ed.doc.prefabs)
	if not ed.doc.set_prefab(pid, res.def, glb):
		_refuse(Lang.t("Prefab refusé", "Prefab refused"))
		return ""
	_library_changed()
	ed.set_status(Lang.t("Modèle « %s » importé (%d Ko) : copié dans le dossier de la carte à l'enregistrement",
		"Model \"%s\" imported (%d KB): copied into the map folder when saved") % [nm, glb.size() >> 10])
	return pid


func _refuse(msg: String) -> void:
	ed.set_status(Lang.t("Import refusé : %s", "Import refused: %s") % msg, true)
	if ed.is_inside_tree() and DisplayServer.get_name() != "headless":
		ed._info(Lang.t("Importer un modèle", "Import a model"), msg)


# ------------------------------------------------------------------ régler, renommer, supprimer

func edit_dialog(pid: String) -> void:
	if not _can_edit() or not ed.doc.prefabs.has(pid):
		return
	var def: Dictionary = ed.doc.prefabs[pid]
	var d := ConfirmationDialog.new()
	d.title = Lang.t("Prefab de la carte", "Map prefab")
	var box := VBoxContainer.new()
	d.add_child(box)
	var l := Label.new()
	l.text = Lang.t("Nom :", "Name:")
	box.add_child(l)
	var e := LineEdit.new()
	e.text = MapPrefabLib.name_of(def)
	e.max_length = CustomMapGuard.MAX_NAME
	e.custom_minimum_size = Vector2(360, 0)
	box.add_child(e)
	var scale: SpinBox = null
	var block: OptionButton = null
	if MapPrefabLib.is_model(def):
		var hs := HBoxContainer.new()
		var ls := Label.new()
		ls.text = Lang.t("Échelle :", "Scale:")
		hs.add_child(ls)
		scale = SpinBox.new()
		scale.min_value = MapPrefabLib.SCALE[0]
		scale.max_value = MapPrefabLib.SCALE[1]
		scale.step = 0.01
		scale.value = float(def.modele.echelle)
		hs.add_child(scale)
		box.add_child(hs)
		var hb := HBoxContainer.new()
		var lb := Label.new()
		lb.text = Lang.t("Collision :", "Collision:")
		hb.add_child(lb)
		block = OptionButton.new()
		for t in [Lang.t("Solide (bloque aussi les balles)", "Solid (also blocks bullets)"), Lang.t("Barrière (les balles passent)", "Barrier (bullets go through)"),
				Lang.t("Aucune (on marche dessus)", "None (can be walked over)")]:
			block.add_item(t)
		block.selected = maxi(0, MapPrefabLib.BLOCKS.find(String(def.bloque)))
		hb.add_child(block)
		box.add_child(hb)
	var n := Label.new()
	var b := MapPrefabLib.model_box(def) if MapPrefabLib.is_model(def) else AABB()
	n.text = (Lang.t("Modèle importé · %s × %s × %s m · %d objet(s) posé(s)", "Imported model · %s × %s × %s m · %d placed object(s)") % [snappedf(b.size.x, 0.01), snappedf(b.size.z, 0.01), snappedf(b.size.y, 0.01), ed.doc.prefab_users(pid).size()]) \
		if MapPrefabLib.is_model(def) else (Lang.t("Groupe de %d décors · %d objet(s) posé(s)", "Group of %d props · %d placed object(s)") % [(def.parties as Array).size(), ed.doc.prefab_users(pid).size()])
	n.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(n)
	d.ok_button_text = Lang.t("Appliquer", "Apply")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	ed.add_child(d)
	d.confirmed.connect(func():
		update_prefab(pid, e.text, scale.value if scale != null else -1.0, MapPrefabLib.BLOCKS[block.selected] if block != null else "")
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	e.grab_focus.call_deferred()


## Nouveau nom ; modèle : échelle (> 0) et collision (« solide », « barriere »,
## « non » ; "" : inchangée), emprise et pavé recalculés.
func update_prefab(pid: String, name: String, scale := -1.0, block := "") -> bool:
	if not _can_edit() or not ed.doc.prefabs.has(pid):
		return false
	var def: Dictionary = (ed.doc.prefabs[pid] as Dictionary).duplicate(true)
	var nm := clean_name(name)
	if nm != "" and CustomMapGuard.name_ok(nm):
		def["nom"] = {"fr": nm, "en": nm}
	if MapPrefabLib.is_model(def):
		if scale > 0.0:
			def.modele["echelle"] = clampf(snappedf(scale, 0.001), MapPrefabLib.SCALE[0], MapPrefabLib.SCALE[1])
		if block in MapPrefabLib.BLOCKS:
			def["bloque"] = block
		MapPrefabLib.refit(def)
	if not ed.doc.set_prefab(pid, def):
		ed.set_status(Lang.t("Réglages refusés", "Settings refused"), true)
		return false
	_library_changed()
	ed.set_status(Lang.t("Prefab « %s » mis à jour", "Prefab \"%s\" updated") % MapPrefabLib.name_of(def))
	return true


func delete_dialog(pid: String) -> void:
	if not _can_edit() or not ed.doc.prefabs.has(pid):
		return
	var users := ed.doc.prefab_users(pid)
	var nm := MapPrefabLib.name_of(ed.doc.prefabs[pid])
	if users.is_empty():
		ed._confirm(Lang.t("Supprimer le prefab", "Delete the prefab"), Lang.t("Supprimer « %s » de la carte ?", "Delete \"%s\" from the map?") % nm, func(): delete_prefab(pid, false))
	else:
		ed._confirm(Lang.t("Supprimer le prefab", "Delete the prefab"),
			Lang.t("« %s » est posé %d fois sur la carte. Supprimer le prefab ET ses objets posés ?", "\"%s\" is placed %d times on the map. Delete the prefab AND its placed objects?") % [nm, users.size()],
			func(): delete_prefab(pid, true))


## Supprime le prefab ; s'il est posé : refusé, sauf `with_users` (ses objets
## posés supprimés aussi, annulable pour les objets).
func delete_prefab(pid: String, with_users := false) -> bool:
	if not _can_edit() or not ed.doc.prefabs.has(pid):
		return false
	var users := ed.doc.prefab_users(pid)
	if not users.is_empty() and not with_users:
		ed.set_status(Lang.t("Prefab posé %d fois : supprimez d'abord ses objets", "Prefab placed %d times: delete its objects first") % users.size(), true)
		return false
	if not users.is_empty():
		ed.push_undo()
		for o in users:
			ed.doc.remove(String(o.id))
	ed.doc.remove_prefab(pid)
	_library_changed()
	ed.set_status(Lang.t("Prefab supprimé", "Prefab deleted"))
	return true
