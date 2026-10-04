class_name MapPrefabTools
extends Node
## PREFABS DE LA CARTE dans l'éditeur (format 10, docs/MAP_OBJECTS.md § 11,
## MapPrefabLib) : catégorie « Prefabs de la carte » de l'inventaire.
##   - « Créer une prefab… » (clic droit, Ctrl+G, panneau Propriétés, ou
##     « + Créer… » de l'inventaire) : depuis la SÉLECTION (Maj + clic,
##     rectangle : MapGroup) ; sans sélection, « + Créer… » fait glisser un
##     rectangle sur le plan autour du décor. Boîte : nom, contenu, ce qui
##     n'est pas repris et pourquoi (EXCLUDED : seul le décor du catalogue posé
##     au sol entre dans une prefab, format 10), ancrage au centre ; le décor
##     peut être remplacé par la prefab posée à sa place (annulable : Ctrl+Z),
##     sinon la prefab est mise en main pour être posée ;
##   - « Importer… » : un fichier .glb ou .gltf du disque, COPIÉ dans le
##     dossier de la carte (prefabs/<pid>/model.glb, à l'enregistrement) ;
##     emprise et collision (un pavé de sa boîte englobante) calculées ;
##   - sur chaque prefab : ⚙ (nom ; modèle : échelle et collision), ✕
##     (supprimer ; refusé tant qu'il est posé, ou supprimé avec ses objets
##     posés après confirmation).
## La bibliothèque des prefabs n'est pas dans l'historique d'annulation (comme
## un fichier) ; en session, seul l'hôte la change (la carte est renvoyée aux
## invités ; les modèles importés n'y passent pas : une boîte à leur place).
## Aucun quota de prefabs ni de modèles (nombre, taille, triangles) : c'est au
## concepteur de la carte de gérer ses ressources.
## Claude passe par les mêmes fonctions, sans boîte de dialogue
## (MapAgentPrefabs) : chaque refus est aussi gardé dans `last_error`.

var ed: MapEditor
## Rectangle de capture en cours (« Créer… » : le prochain glissé sur le plan).
var capturing := false
## Dernier refus (texte dans la langue du jeu, aussi dans la barre d'état) :
## rendu à Claude par MapAgentPrefabs. Vidé au début de chaque action.
var last_error := ""
var _file_dialog: FileDialog


# ------------------------------------------------------------------ inventaire

## Cases « Créer… » et « Importer… » en tête de la grille de l'inventaire.
func add_inventory_actions(grid: GridContainer) -> void:
	grid.add_child(_action(Lang.t("+ Créer…", "+ Create…"),
		Lang.t("Grouper du décor posé en une prefab : sélectionnez-le sur le plan (Maj + clic, ou un rectangle), puis clic droit > Créer une prefab… (Ctrl+G). Sans sélection : glissez un rectangle autour du décor",
			"Group placed props into a prefab: select them on the plan (Shift + click, or a rectangle), then right click > Create a prefab… (Ctrl+G). With nothing selected: drag a rectangle around the props"),
		func():
			ed.toggle_inventory()
			if ed.sel_ids().is_empty():
				start_capture()
			else:
				create_dialog_for(ed.sel_ids())))
	grid.add_child(_action(Lang.t("Importer…", "Import…"),
		Lang.t("Importer un modèle .glb ou .gltf (copié dans le dossier de la carte)", "Import a .glb or .gltf model (copied into the map folder)"),
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
	last_error = ""
	if ed.collab != null and ed.collab.role == MapCollab.Role.GUEST:
		_fail(Lang.t("Seul l'hôte de la session change les prefabs de la carte", "Only the session host changes the map prefabs"))
		return false
	return true


## Refus : barre d'état (en rouge) et `last_error`.
func _fail(msg: String) -> void:
	last_error = msg
	ed.set_status(msg, true)


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


func create_dialog(objs: Array) -> ConfirmationDialog:
	return create_dialog_for(objs.map(func(o): return String(o.id)))


## Catégories d'éléments qu'une prefab ne peut pas contenir (format 10 : une
## prefab groupe n'a que des « parties » de décor du catalogue posé au sol,
## MapPrefabLib.check_def) : clé -> [nom fr, nom en, raison fr, raison en].
const EXCLUDED := {
	"piece": ["pièce(s)", "room(s)", "une prefab se pose DANS une pièce : elle n'a ni sol, ni murs, ni zone",
		"a prefab is placed INSIDE a room: it has no floor, walls or zone"],
	"ouverture": ["porte(s), fenêtre(s) ou passage(s)", "door(s), window(s) or passage(s)", "elles relient deux pièces ou donnent dehors : elles restent sur leur mur",
		"they join two rooms or open outside: they stay on their wall"],
	"structure": ["mur(s), pilier(s) ou barrière(s) invisible(s)", "wall(s), pillar(s) or invisible barrier(s)", "construction de la carte, pas du décor",
		"map construction, not props"],
	"jeu": ["objet(s) de jeu", "game object(s)", "armes, atouts, boîte, pièges, escaliers… : le jeu gère chacun (prix, règles, apparitions)",
		"weapons, perks, box, traps, stairs…: the game handles each one (price, rules, spawns)"],
	"effet": ["effet(s)", "effect(s)", "un effet a sa propre zone et son animation ; le format des prefabs ne garde que du décor",
		"an effect has its own zone and animation; the prefab format only keeps props"],
	"lumiere": ["luminaire(s)", "light(s)", "la lumière est calculée à part par le jeu ; le format des prefabs ne garde que du décor",
		"light is computed separately by the game; the prefab format only keeps props"],
	"mural": ["décor mural ou au plafond", "wall or ceiling prop(s)", "une prefab se pose au sol : le décor accroché n'y entre pas",
		"a prefab stands on the floor: hung props cannot go in"],
	"prefab_carte": ["prefab(s) de la carte", "map prefab(s)", "une prefab ne contient pas d'autre prefab ni de modèle importé",
		"a prefab cannot hold another prefab or an imported model"],
}


## Catégorie d'exclusion d'un élément (EXCLUDED) ; "" s'il entre dans une prefab.
static func excluded_kind(e: Dictionary) -> String:
	if MapPrefabLib.groupable(e):
		return ""
	if e.has("contour"):
		return "piece"
	var t := String(e.get("type", ""))
	if t in MapRules.ouvertures_types():
		return "ouverture"
	match t:
		"mur", "mur_courbe", "pilier", "bloc_invisible":
			return "structure"
		"effet":
			return "effet"
		"luminaire":
			return "lumiere"
		"prefab":
			return "prefab_carte" if MapPrefabLib.is_ref(e.get("prefab", "")) else "mural"
	return "jeu"


## Ce que la sélection `ids` donne pour une prefab : les décors qui y entrent
## (« parts », objets ; le contenu des pièces choisies compris, comme quand
## elles bougent) et ce qui n'y entre pas (« excluded » : clé -> nombre).
static func analyze(doc: EditorMap, ids: Array) -> Dictionary:
	var parts := []
	var excluded := {}
	for id in MapGroup.movers(doc, ids):
		var e := doc.find(String(id))
		var k := excluded_kind(e)
		if k == "":
			parts.append(e)
		else:
			excluded[k] = int(excluded.get(k, 0)) + 1
	return {"parts": parts, "excluded": excluded}


## Texte du contenu d'une prefab : « 2 × Sacs de sable, 1 × Table » (ordre
## d'apparition).
static func parts_text(parts: Array) -> String:
	var n := {}
	var order := []
	for o in parts:
		var nm := MapCatalog.name_of(MapCatalog.item_for(o))
		if not n.has(nm):
			order.append(nm)
		n[nm] = int(n.get(nm, 0)) + 1
	return ", ".join(order.map(func(nm): return "%d × %s" % [n[nm], nm]))


## « Créer une prefab… » (clic droit, Ctrl+G, panneau Propriétés, « + Créer… »
## de l'inventaire) : boîte au style de l'éditeur pour la sélection `ids` —
## aide, nom, contenu (nombre et liste des décors), ce qui n'est pas repris et
## pourquoi, point d'ancrage, « remplacer ce décor par la prefab ». Rend la
## boîte (null si refusée).
func create_dialog_for(ids: Array) -> ConfirmationDialog:
	if not _can_edit():
		return null
	var an := analyze(ed.doc, ids)
	var parts: Array = an.parts
	if floors_of(parts).size() > 1:
		ed.set_status(multi_floor_text(), true)
		return null
	var d := ConfirmationDialog.new()
	d.name = "CreatePrefabDialog"
	d.title = Lang.t("Créer une prefab", "Create a prefab")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	d.add_child(box)
	var w := 440.0
	var help := Label.new()
	help.name = "Help"
	help.text = Lang.t("Une prefab regroupe du décor posé au sol en UN objet réutilisable. Elle rejoint l'inventaire (E), catégorie « Prefabs de la carte » : prenez-la puis cliquez sur le plan pour la poser (R : pivoter), comme un décor.",
		"A prefab groups props placed on the floor into ONE reusable object. It joins the inventory (E), \"Map prefabs\" category: take it, then click on the plan to place it (R: rotate), like a prop.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(w, 0)
	help.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(help)
	var l := Label.new()
	l.text = Lang.t("Nom de la prefab :", "Prefab name:")
	box.add_child(l)
	var e := LineEdit.new()
	e.name = "Name"
	e.text = Lang.t("Prefab %d", "Prefab %d") % (ed.doc.prefabs.size() + 1)
	e.max_length = CustomMapGuard.MAX_NAME
	e.custom_minimum_size = Vector2(w, 0)
	box.add_child(e)
	var c := Label.new()
	c.name = "Content"
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.custom_minimum_size = Vector2(w, 0)
	if parts.is_empty():
		c.text = Lang.t("Contenu : aucun décor du catalogue posé au sol — rien à grouper.", "Content: no catalogue prop placed on the floor — nothing to group.")
		c.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	elif parts.size() > MapPrefabLib.MAX_PARTS:
		c.text = Lang.t("Contenu : %d décors — trop pour une prefab (%d au plus).", "Content: %d props — too many for a prefab (%d at most).") % [parts.size(), MapPrefabLib.MAX_PARTS]
		c.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	else:
		c.text = Lang.t("Contenu : %d décor(s) — %s", "Content: %d prop(s) — %s") % [parts.size(), parts_text(parts)]
	box.add_child(c)
	var ex: Dictionary = an.excluded
	if not ex.is_empty():
		var x := Label.new()
		x.name = "Excluded"
		x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		x.custom_minimum_size = Vector2(w, 0)
		var lines := [Lang.t("Non repris (une prefab ne garde que du décor du catalogue posé au sol) :", "Not included (a prefab only keeps catalogue props placed on the floor):")]
		for k in EXCLUDED:
			if ex.has(k):
				var en: Array = EXCLUDED[k]
				lines.append(Lang.t("• %d %s : %s" % [int(ex[k]), en[0], en[2]], "• %d %s: %s" % [int(ex[k]), en[1], en[3]]))
		x.text = "\n".join(lines)
		x.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
		box.add_child(x)
	var anchor := Label.new()
	anchor.name = "Anchor"
	anchor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anchor.custom_minimum_size = Vector2(w, 0)
	anchor.text = Lang.t("Point d'ancrage : centre de l'emprise (la prefab se pose, s'aimante sur la grille et pivote autour de son centre).",
		"Anchor point: centre of the footprint (the prefab is placed, snapped to the grid and rotated around its centre).")
	anchor.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(anchor)
	var rep := CheckBox.new()
	rep.name = "Replace"
	rep.text = Lang.t("Remplacer ce décor par la prefab, à la même place (sinon : la prefab en main, à poser)", "Replace these props with the prefab, in the same place (otherwise: the prefab in hand, to place)")
	rep.button_pressed = true
	box.add_child(rep)
	d.ok_button_text = Lang.t("Créer", "Create")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	d.get_ok_button().disabled = parts.is_empty() or parts.size() > MapPrefabLib.MAX_PARTS
	ed.add_child(d)
	d.confirmed.connect(func():
		d.queue_free()
		create_from_selection(ids, e.text, rep.button_pressed))
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	e.grab_focus.call_deferred()
	e.select_all.call_deferred()
	return d


## Étages (indices) des décors `parts`.
static func floors_of(parts: Array) -> Array:
	var out := []
	for o in parts:
		var k := int(o.get("etage", 0))
		if not out.has(k):
			out.append(k)
	return out


static func multi_floor_text() -> String:
	return Lang.t("Créer une prefab : la sélection est sur plusieurs étages ; une prefab se pose à un seul étage (sélectionnez le décor d'un étage)",
		"Create a prefab: the selection spans several floors; a prefab stands on a single floor (select the props of one floor)")


## « Créer » de la boîte : la sélection `ids` est RELUE dans la carte telle
## qu'elle est au moment de valider (un autre participant ou Claude a pu
## supprimer ou déplacer des éléments depuis l'ouverture) : les décors
## restants, à leur place actuelle ; refusé (message) s'il n'en reste aucun
## ou s'ils sont sur plusieurs étages. Rend le pid ("" : refusé).
func create_from_selection(ids: Array, name: String, replace := true) -> String:
	last_error = ""
	var parts: Array = analyze(ed.doc, ids).parts
	if parts.is_empty():
		_fail(Lang.t("Créer une prefab : la sélection n'a plus de décor posé au sol (supprimé ou changé entre-temps)",
			"Create a prefab: the selection no longer has props placed on the floor (deleted or changed meanwhile)"))
		return ""
	if floors_of(parts).size() > 1:
		_fail(multi_floor_text())
		return ""
	if ed.edit_blocked():
		last_error = ed.status.text
		return ""
	return create_from_objects(parts, name, replace)


## Prefab groupe tiré de `objs` (décor du catalogue posé), nommé `name` ;
## `replace` : ces objets remplacés par un prefab posé à leur place
## (annulable : Ctrl+Z) ; sinon `hand` : la prefab mise en main. Rend
## l'identifiant du prefab ("" : refusé, raison dans `last_error`).
func create_from_objects(objs: Array, name: String, replace := true, hand := true) -> String:
	var made := make_group(objs, name)
	if made.is_empty():
		return ""
	var pid := String(made.pid)
	var nm := MapPrefabLib.name_of(made.def)
	var n := (made.def.parties as Array).size()
	if replace:
		var k := int(objs[0].get("etage", ed.floor_k))
		ed.push_undo()
		for o in objs:
			ed.doc.remove(String(o.id))
		ed.add_object({"type": "prefab", "prefab": MapPrefabLib.ref(pid), "position": MapGeom.arr(made.center), "rot": 0}, k)
		ed.set_status(Lang.t("Prefab « %s » créée (%d décors), posée à leur place : inventaire, « Prefabs de la carte », pour en poser d'autres",
			"Prefab \"%s\" created (%d props), placed in their stead: inventory, \"Map prefabs\", to place more") % [nm, n])
	elif hand:
		# Prefab en main : un clic sur le plan la pose (R : pivoter).
		ed.pick_item("prefab:" + MapPrefabLib.ref(pid))
		ed.set_status(Lang.t("Prefab « %s » créée (%d décors), en main : cliquez sur le plan pour la poser (R : pivoter) ; inventaire, « Prefabs de la carte »",
			"Prefab \"%s\" created (%d props), in hand: click on the plan to place it (R: rotate); inventory, \"Map prefabs\"") % [nm, n])
	return pid


## Ajoute à la bibliothèque la prefab groupe tirée de `objs` (décor du
## catalogue, un seul étage ; MapPrefabLib.from_objects), nommée `name`, sans
## rien poser. Rend {pid, def, center (centre de l'emprise des objets, m)} ;
## {} si refusée (raison dans `last_error`).
func make_group(objs: Array, name: String) -> Dictionary:
	if not _can_edit():
		return {}
	if floors_of(objs).size() > 1:
		_fail(multi_floor_text())
		return {}
	var nm := clean_name(name)
	if nm == "" or not CustomMapGuard.name_ok(nm):
		_fail(Lang.t("Nom de prefab refusé", "Prefab name refused"))
		return {}
	var res := MapPrefabLib.from_objects(nm, nm, objs)
	if res.has("error"):
		_fail(Lang.t("Prefab refusé : %s", "Prefab refused: %s") % Lang.t(res.error[0], res.error[1]))
		return {}
	var pid := MapPrefabLib.new_pid(nm, ed.doc.prefabs)
	if not ed.doc.set_prefab(pid, res.def):
		_fail(Lang.t("Prefab refusé", "Prefab refused"))
		return {}
	_library_changed()
	ed.set_status(Lang.t("Prefab « %s » créée (%d décors) : inventaire, « Prefabs de la carte »", "Prefab \"%s\" created (%d props): inventory, \"Map prefabs\"")
		% [nm, (res.def.parties as Array).size()])
	return {"pid": pid, "def": ed.doc.prefabs[pid], "center": res.center}


# ------------------------------------------------------------------ importer (modèle)

## « Importer… » : explorateur du système (FilePick ; la fenêtre de Godot
## seulement sans dialogue natif). Le fichier choisi (chemin absolu) passe par
## import_file et ses contrôles (extension, taille, contenu).
func import_dialog() -> void:
	if not _can_edit():
		return
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()
	var chosen := func(path: String):
		var pid := import_file(path)
		if pid != "":
			edit_dialog(pid)
	_file_dialog = FilePick.pick(ed, Lang.t("Importer un modèle (prefab de la carte)", "Import a model (map prefab)"),
		FilePick.Mode.OPEN, PackedStringArray(["*.glb, *.gltf ; " + Lang.t("Modèle 3D glTF", "glTF 3D model")]),
		chosen, "", "", ed.ui_scale)


## Importe le modèle `path` (.glb ou .gltf) : contrôlé, copié dans la carte
## (enregistré avec elle dans prefabs/<pid>/model.glb). Rend l'identifiant du
## prefab ("" : refusé, raison affichée et dans `last_error`).
## `dialog` : refus aussi montré dans une boîte (l'interface, pas Claude).
func import_file(path: String, name := "", scale := 1.0, block := "solide", dialog := true) -> String:
	if not _can_edit():
		return ""
	var got := MapPrefabLib.read_import(path)
	if got.has("error"):
		push_warning("[MapPrefabTools] import refusé (%s) : %s" % [path.get_file(), got.error[0]])
		_refuse(Lang.t(got.error[0], got.error[1]), dialog)
		return ""
	return import_glb(got.glb, name if name != "" else path.get_file().get_basename().replace("_", " "), scale, block, dialog)


## Importe un modèle .glb déjà lu (`glb` : octets ; fichier du disque ou
## données envoyées par Claude) : contrôlé (MapPrefabLib.from_model :
## check_glb), ajouté à la bibliothèque. Aucun nombre ni taille maximale de
## modèles (pas de quota). Rend le pid ("" : refusé, `last_error`).
func import_glb(glb: PackedByteArray, name: String, scale := 1.0, block := "solide", dialog := true) -> String:
	if not _can_edit():
		return ""
	var nm := clean_name(name)
	if nm == "" or not CustomMapGuard.name_ok(nm):
		nm = Lang.t("Modèle %d", "Model %d") % (ed.doc.model_count() + 1)
	var res := MapPrefabLib.from_model(nm, nm, glb, scale, block)
	if res.has("error"):
		_refuse(Lang.t(res.error[0], res.error[1]), dialog)
		return ""
	var pid := MapPrefabLib.new_pid(nm, ed.doc.prefabs)
	if not ed.doc.set_prefab(pid, res.def, glb):
		_refuse(Lang.t("Prefab refusé", "Prefab refused"), dialog)
		return ""
	_library_changed()
	ed.set_status(Lang.t("Modèle « %s » importé (%d Ko) : copié dans le dossier de la carte à l'enregistrement",
		"Model \"%s\" imported (%d KB): copied into the map folder when saved") % [nm, glb.size() >> 10])
	return pid


func _refuse(msg: String, dialog := true) -> void:
	_fail(Lang.t("Import refusé : %s", "Import refused: %s") % msg)
	if dialog and ed.is_inside_tree() and DisplayServer.get_name() != "headless":
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
		_fail(Lang.t("Réglages refusés", "Settings refused"))
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
		_fail(Lang.t("Prefab posé %d fois : supprimez d'abord ses objets", "Prefab placed %d times: delete its objects first") % users.size())
		return false
	if not users.is_empty():
		ed.push_undo()
		for o in users:
			ed.doc.remove(String(o.id))
	ed.doc.remove_prefab(pid)
	_library_changed()
	ed.set_status(Lang.t("Prefab supprimé", "Prefab deleted"))
	return true
