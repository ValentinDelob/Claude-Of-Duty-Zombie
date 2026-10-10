class_name MapPanels
extends TabContainer
## Panneaux de l'éditeur de cartes : Propriétés (élément choisi, sinon la
## carte), Pièces, Zones (regrouper, renommer FR/EN, fusionner, séparer, zone
## de départ), Niveaux (ajouter, hauteurs, niveau du dessous en transparence) et
## Vérification (validateur : clic sur un problème = vue centrée dessus),
## Historique (actions de la carte, par auteur : CollabHistory).

const TABS := ["props", "rooms", "zones", "floors", "check", "history"]
const PANEL_TEXT_W := 300.0
const DIR_NAMES := {"n": ["Nord", "North"], "e": ["Est", "East"], "s": ["Sud", "South"], "o": ["Ouest", "West"]}

var ed: MapEditor
var _props: VBoxContainer
var _rooms: ItemList
var _room_ids: Array = []
var _zones: ItemList
var _zone_ids: Array = []
var _zone_form: VBoxContainer
var _zone_sel := ""
var _floors: ItemList
var _floor_form: VBoxContainer
var _check_list: VBoxContainer
var _check_summary: Label
var _check_msgs: Array = []
var _props_for := "?"
## Champs de la ligne « Position » de l'élément choisi : {X, Y, Z: cadre du champ}.
var _pos_fields: Dictionary = {}
## Format 14 : champs des sections Échelle et Rotation d'un décor (MapPanelsScale).
var _scale_fields: Dictionary = {}
## Onglet Historique (docs/MAP_COLLAB.md § 4).
var history: CollabHistory


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_props = _tab("props", Lang.t("Propriétés", "Properties"))
	var rv := _tab("rooms", Lang.t("Pièces", "Rooms"))
	_rooms = ItemList.new()
	_rooms.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms.item_selected.connect(func(i): ed.focus_element(String(_room_ids[i])))
	rv.add_child(_rooms)
	var zv := _tab("zones", Lang.t("Zones", "Zones"))
	var zh := Label.new()
	zh.text = Lang.t("Une zone regroupe des pièces : elle s'ouvre d'un coup (ses fenêtres s'activent ensemble). Par défaut, une zone par pièce.",
		"A zone groups rooms: it opens at once (its windows activate together). By default, one zone per room.")
	zh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zh.add_theme_color_override("font_color", UiStyle.DIM)
	zv.add_child(zh)
	_zones = ItemList.new()
	_zones.custom_minimum_size = Vector2(0, 170)
	_zones.item_selected.connect(func(i):
		_zone_sel = String(_zone_ids[i])
		_fill_zone_form())
	zv.add_child(_zones)
	_zone_form = VBoxContainer.new()
	zv.add_child(_zone_form)
	var fv := _tab("floors", Lang.t("Niveaux", "Levels"))
	_floors = ItemList.new()
	_floors.custom_minimum_size = Vector2(0, 140)
	_floors.name = "LevelList"
	# Clic : le niveau sur lequel agir ; double-clic : l'afficher.
	_floors.item_selected.connect(func(i):
		_level_sel = ed.doc.level_alt(int(_floors.get_item_metadata(i)))
		_fill_floors.call_deferred())
	_floors.item_activated.connect(func(i): ed.set_floor(int(_floors.get_item_metadata(i))))
	fv.add_child(_floors)
	_floor_form = VBoxContainer.new()
	fv.add_child(_floor_form)
	var cv := _tab("check", Lang.t("Vérification", "Check"))
	var b := Button.new()
	b.text = Lang.t("Vérifier maintenant", "Check now")
	b.pressed.connect(func(): ed.validate())
	cv.add_child(b)
	_check_summary = Label.new()
	_check_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_check_summary)
	_check_list = VBoxContainer.new()
	_check_list.add_theme_constant_override("separation", 2)
	cv.add_child(_check_list)
	var hv := _tab("history", Lang.t("Historique", "History"))
	history = CollabHistory.new()
	history.name = "CollabHistory"
	hv.add_child(history)
	tab_changed.connect(func(t):
		if TABS[t] == "check" and (ed.validation_stale or ed.validator == null):
			ed.validate()
		elif TABS[t] == "history":
			history.mark_dirty())


func _tab(id: String, title_text: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = id
	# Défilement horizontal seulement si une ligne ne tient pas (grande taille
	# d'interface : la largeur des panneaux est bornée, MapEditor.side_width).
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(sc)
	set_tab_title(get_tab_count() - 1, title_text)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	if id == "rooms":
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return v


func show_tab(id: String) -> void:
	current_tab = TABS.find(id)


func is_check_tab() -> bool:
	return TABS[current_tab] == "check"


var _refresh_queued := false


## Reconstruit les panneaux (en fin d'image : jamais pendant le signal d'un de leurs contrôles).
func refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh_now.call_deferred()


func refresh_now() -> void:
	_refresh_queued = false
	if ed == null or ed.doc == null:
		return
	_fill_props()
	_fill_rooms()
	_fill_zones()
	_fill_floors()


# ------------------------------------------------------------------ petits contrôles

static func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _title(box: Container, text: String) -> void:
	var l := UiStyle.label(text, 17, UiStyle.GOLD, "impact")
	box.add_child(l)


func _note(box: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(l)
	return l


func _row(box: Container, label: String, ctl: Control) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(118, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	box.add_child(h)
	return ctl


## Champ de texte : appliqué à Entrée ou en quittant le champ.
func _line(box: Container, label: String, value: String, apply: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.set_meta("applied", value)
	var commit := func(_t := ""):
		if e.text != String(e.get_meta("applied")):
			e.set_meta("applied", e.text)
			ed.push_undo()
			apply.call(e.text)
			ed.changed(false)
			_fill_rooms()
			_fill_zones.call_deferred()
	e.text_submitted.connect(commit)
	e.focus_exited.connect(commit)
	_row(box, label, e)
	return e


func _spin(box: Container, label: String, value: float, lo: float, hi: float, stp: float, apply: Callable, suffix := "m") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = stp
	s.value = value
	s.suffix = suffix
	s.select_all_on_focus = true
	s.value_changed.connect(func(v):
		ed.push_undo()
		apply.call(v)
		ed.changed(false)
		_fill_rooms())
	_row(box, label, s)
	return s


func _option(box: Container, label: String, items: Array, selected_i: int, apply: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = selected_i
	# Largeur donnée par le panneau (texte coupé au besoin, liste complète).
	o.fit_to_longest_item = false
	o.clip_text = true
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	o.item_selected.connect(func(i): apply.call(i))
	_row(box, label, o)
	return o


func _check(box: Container, text: String, value: bool, apply: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.button_pressed = value
	c.toggled.connect(func(on):
		ed.push_undo()
		apply.call(on)
		ed.changed(false))
	box.add_child(c)
	return c


func _button(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	box.add_child(b)
	return b


static func _m(v: float) -> String:
	return MapRules._m(v, not Lang.is_en())


## Choix d'une texture (clé de WorldLook.SURFACES) pour `target[key]`, avec
## un aperçu dans la liste et à côté ; premier choix : la valeur par défaut
## (`default_key`, celle de la zone pour une pièce), qui efface la clé.
func _surface_option(box: Container, label: String, target: Dictionary, key: String, default_key: String, of_zone := false) -> OptionButton:
	var tt := ed.texture_tools
	# Format 15 : surfaces du jeu, puis les textures de la carte (« map:<tid> »),
	# « Importer une texture… » et « Gérer les textures… » (MapTextureTools).
	var keys: Array = MapCatalog.allowed_surfaces().duplicate()
	var tids := ed.doc.textures.keys()
	tids.sort()
	var o := OptionButton.new()
	var def_txt := (Lang.t("(%s)", "(%s)") if of_zone else Lang.t("(zone : %s)", "(zone: %s)")) % tt.surface_name(default_key)
	o.add_icon_item(tt.icon(default_key), def_txt)
	o.set_item_metadata(0, "")
	for k in keys:
		o.add_icon_item(MapIcons.surface_texture(String(k)), MapCatalog.surface_name(String(k)))
		o.set_item_metadata(o.item_count - 1, String(k))
	o.add_separator(Lang.t("Textures de la carte", "Map textures"))
	var cur := String(target.get(key, ""))
	if MapTextureLib.is_ref(cur) and not ed.doc.textures.has(MapTextureLib.tid_of(cur)):
		tids.append(MapTextureLib.tid_of(cur))   # citée mais absente : montrée telle quelle
	for tid in tids:
		o.add_icon_item(tt.icon(MapTextureLib.ref(tid)), tt.surface_name(MapTextureLib.ref(tid)))
		o.set_item_metadata(o.item_count - 1, MapTextureLib.ref(tid))
	o.add_item(Lang.t("Importer une texture…", "Import a texture…"))
	o.set_item_metadata(o.item_count - 1, "#importer")
	o.add_item(Lang.t("Gérer les textures…", "Manage textures…"))
	o.set_item_metadata(o.item_count - 1, "#gerer")
	var index_of := func(v: String) -> int:
		for i in o.item_count:
			if not o.is_item_separator(i) and String(o.get_item_metadata(i)) == v:
				return i
		return 0
	o.selected = index_of.call(cur)
	o.fit_to_longest_item = false
	o.clip_text = true
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(118, 0)
	h.add_child(l)
	var sw := TextureRect.new()
	sw.custom_minimum_size = Vector2(40, 24)
	sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sw.stretch_mode = TextureRect.STRETCH_SCALE
	sw.texture = tt.icon(String(target.get(key, default_key)))
	sw.tooltip_text = Lang.t("Aperçu de la texture", "Texture preview")
	h.add_child(sw)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(o)
	# Texture de la carte choisie : ⚙ ouvre ses réglages.
	if MapTextureLib.is_ref(cur) and ed.doc.textures.has(MapTextureLib.tid_of(cur)):
		var gear := Button.new()
		gear.text = "⚙"
		gear.tooltip_text = Lang.t("Régler cette texture de la carte (nom, taille du motif, rugosité…)", "Adjust this map texture (name, pattern size, roughness…)")
		gear.pressed.connect(func(): tt.edit_dialog(MapTextureLib.tid_of(cur)))
		h.add_child(gear)
	box.add_child(h)
	# Choix d'une surface : une modification annulable (Ctrl+Z) ; l'élément est
	# relu par son id (import asynchrone : le panneau a pu être reconstruit).
	var eid := String(target.get("id", ""))
	var choose := func(v: String, rebuild: bool) -> void:
		var t: Dictionary = ed.doc.find(eid) if eid != "" else target
		if t.is_empty():
			return
		ed.push_undo()
		if v == "":
			t.erase(key)
		else:
			t[key] = v
		ed.changed(rebuild)
	o.item_selected.connect(func(i):
		var v := String(o.get_item_metadata(i))
		if v.begins_with("#"):
			o.selected = index_of.call(String(target.get(key, "")))
			if v == "#importer":
				tt.import_dialog(func(tid): choose.call(MapTextureLib.ref(tid), true))
			else:
				tt.manage_dialog()
			return
		sw.texture = tt.icon(v if v != "" else default_key)
		choose.call(v, false))
	return o


# ------------------------------------------------------------------ propriétés

func _fill_props() -> void:
	_props_for = ed.selected
	_clear(_props)
	if ed.group.size() >= 2:
		_group_props()
		return
	var e := ed.doc.find(ed.selected)
	if e.is_empty():
		_map_props()
		return
	if e.has("contour"):
		_room_props(e)
	elif String(e.get("type", "")) in MapRules.ouvertures_types():
		_opening_props(e)
	else:
		_object_props(e)
	if ed.invalid.has(String(e.id)):
		var l := _note(_props, "⚠ " + String(ed.invalid[String(e.id)]))
		l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	# Boutons à la ligne s'ils ne tiennent pas côte à côte (grande taille d'interface).
	var h := HFlowContainer.new()
	_props.add_child(h)
	if MapTransform.can_rotate(e):
		_button(h, Lang.t("Pivoter (R)", "Rotate (R)"), ed.rotate_selected)
	_button(h, Lang.t("Supprimer (Suppr)", "Delete (Del)"), func(): ed.delete_element(String(e.id)))


## Sélection multiple (MapGroup) : « N éléments sélectionnés », ce qu'ils
## sont, le niveau et la rotation quand ils sont communs, les éléments
## invalides, les actions de groupe et la liste (un clic : cet élément seul).
func _group_props() -> void:
	var ids: Array = ed.group
	_title(_props, Lang.t("%d éléments sélectionnés", "%d elements selected") % ids.size())
	var kinds := {}
	var order := []
	var floors := {}
	var rots := {}
	var bad := []
	var els := []
	for id in ids:
		var e := ed.doc.find(String(id))
		if e.is_empty():
			continue
		els.append(e)
		var nm := Lang.t("pièce(s)", "room(s)") if e.has("contour") else MapCatalog.name_of(MapCatalog.item_for(e))
		if not kinds.has(nm):
			order.append(nm)
		kinds[nm] = int(kinds.get(nm, 0)) + 1
		floors[ed.doc.level_of(e)] = true
		rots[MapTransform.angle_of(e)] = true
		if ed.invalid.has(String(id)):
			bad.append(e)
	_note(_props, ", ".join(order.map(func(nm): return "%d × %s" % [kinds[nm], nm])))
	# Champs communs (lecture seule) : seulement quand tous ont la même valeur.
	if floors.size() == 1:
		var a := ed.doc.level_alt(int(floors.keys()[0]))
		_note(_props, Lang.t("Niveau : %s (commun)", "Level: %s (common)") % EditorMap.alt_text(a, not Lang.is_en()))
	else:
		var fr := not Lang.is_en()
		_note(_props, Lang.t("Niveaux : %s", "Levels: %s") % ", ".join(floors.keys().map(func(k): return EditorMap.alt_text(ed.doc.level_alt(int(k)), fr))))
	if rots.size() == 1:
		_note(_props, Lang.t("Rotation : %d° (commune)", "Rotation: %d° (common)") % int(rots.keys()[0]))
	var bb := MapGroup.bounds(ed.doc, ids)
	_note(_props, Lang.t("Encombrement : %s × %s m", "Extent: %s × %s m") % [_m(bb.size.x), _m(bb.size.y)])
	for e in bad:
		var l := _note(_props, "⚠ %s : %s" % [ed._label(e), String(ed.invalid[String(e.id)])])
		l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	var h := HFlowContainer.new()
	_props.add_child(h)
	_button(h, Lang.t("Créer une prefab… (Ctrl+G)", "Create a prefab… (Ctrl+G)"), ed.create_prefab_from_selection)
	_button(h, Lang.t("Dupliquer (Ctrl+D)", "Duplicate (Ctrl+D)"), ed.duplicate_selection)
	_button(h, Lang.t("Pivoter (R)", "Rotate (R)"), ed.rotate_selection)
	_button(h, Lang.t("Copier (Ctrl+C)", "Copy (Ctrl+C)"), ed.copy_selected)
	_button(h, Lang.t("Couper (Ctrl+X)", "Cut (Ctrl+X)"), ed.cut_selected)
	_button(h, Lang.t("Supprimer (Suppr)", "Delete (Del)"), ed.delete_selection)
	_button(h, Lang.t("Désélectionner (Échap)", "Deselect (Esc)"), func(): ed.select(""))
	_note(_props, Lang.t("Glisser un des éléments sur le plan déplace tout le groupe ; flèches : d'un pas ; Maj + clic : ajouter / retirer.",
		"Drag one of the elements on the plan to move the whole group; arrow keys: one step; Shift + click: add / remove."))
	_title(_props, Lang.t("Éléments", "Elements"))
	var shown := 0
	for e in els:
		if shown >= 30:
			_note(_props, Lang.t("… et %d autre(s)", "… and %d more") % (els.size() - shown))
			break
		var eid := String(e.id)
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  (%s)" % [ed._label(e), eid]
		b.tooltip_text = Lang.t("Choisir cet élément seul", "Pick this element alone")
		b.pressed.connect(func(): ed.focus_element(eid))
		_props.add_child(b)
		shown += 1


func _map_props() -> void:
	var c: Dictionary = ed.doc.carte
	_title(_props, Lang.t("Carte", "Map"))
	_note(_props, Lang.t("Rien n'est choisi : réglages de la carte. Outil Sélection (touche 1) pour choisir un élément.",
		"Nothing selected: map settings. Select tool (key 1) to pick an element."))
	var n: Dictionary = c.get("nom", {})
	_line(_props, Lang.t("Nom (FR)", "Name (FR)"), String(n.get("fr", "")), func(t): c.nom["fr"] = t)
	_line(_props, Lang.t("Nom (EN)", "Name (EN)"), String(n.get("en", "")), func(t): c.nom["en"] = t)
	var d: Dictionary = c.get("description", {"fr": "", "en": ""})
	c["description"] = d
	_line(_props, Lang.t("Description (FR)", "Description (FR)"), String(d.get("fr", "")), func(t): d["fr"] = t)
	_line(_props, Lang.t("Description (EN)", "Description (EN)"), String(d.get("en", "")), func(t): d["en"] = t)
	var musics := MapCatalog.musics()
	_option(_props, Lang.t("Musique", "Music"), musics, maxi(0, musics.find(String(c.get("musique", "ambience_bunker")))), func(i):
		ed.push_undo()
		c["musique"] = musics[i]
		ed.changed(false))
	_spin(_props, Lang.t("Hauteur portes", "Door height"), float(c.get("hauteur_portes", 2.5)), 2.2, 3.5, 0.1, func(v): c["hauteur_portes"] = v)
	_check(_props, Lang.t("Lampes automatiques (une tous les 6 m)", "Automatic lamps (one every 6 m)"), bool(c.get("lampes_auto", true)), func(on): c["lampes_auto"] = on)
	_sky_props(c)
	# Format 9 : décor et obstacles qui se chevauchent (MapCatalog.OVERLAP_TYPES).
	var ov := _check(_props, Lang.t("Autoriser les chevauchements décor / obstacles", "Allow decor / obstacle overlaps"),
		MapRules.overlaps_allowed(ed.doc), func(on):
			if on:
				c[MapCatalog.OVERLAP_KEY] = true
			else:
				c.erase(MapCatalog.OVERLAP_KEY))
	ov.tooltip_text = Lang.t("Coché : caisses, barils, décor, luminaires et piliers peuvent se recouvrir entre eux. Les objets de jeu (portes, fenêtres, atouts, armes, boîte, départs, escaliers...) ne se chevauchent jamais.",
		"Checked: crates, barrels, props, light fixtures and pillars may overlap each other. Gameplay objects (doors, windows, perks, weapons, box, starts, stairs...) never overlap.")
	_note(_props, Lang.t("Dossier : %s\n%d pièce(s), %d ouverture(s), %d objet(s)", "Folder: %s\n%d room(s), %d opening(s), %d object(s)") % [
		ed.doc.id(), ed.doc.pieces.size(), ed.doc.ouvertures.size(), ed.doc.objets.size()])


## Format 17 : ciel de la carte (« carte.ciel »), vu au-dessus des pièces sans
## plafond (et dans l'aperçu 3D) : type et luminosité (jamais écrits à leur
## valeur par défaut : noir, 100 %).
func _sky_props(c: Dictionary, box: Container = null) -> void:
	if box == null:
		box = _props
	var s := EditorMap.sky_of(c)
	var names := [Lang.t("Sans fond (noir)", "None (black)"), Lang.t("Ciel", "Sky"), Lang.t("Nuit étoilée", "Starry night")]
	var o := _option(box, Lang.t("Ciel", "Sky"), names, maxi(0, EditorMap.SKY_TYPES.find(String(s.type))), func(i):
		ed.push_undo()
		EditorMap.set_sky(c, String(EditorMap.SKY_TYPES[i]), float(EditorMap.sky_of(c).luminosite))
		ed.changed())
	o.tooltip_text = Lang.t("Vu au-dessus des pièces sans plafond (propriété « Afficher le plafond » d'une pièce). Il n'éclaire pas les pièces.",
		"Seen above rooms without a ceiling (a room's \"Show the ceiling\" property). It does not light the rooms.")
	if String(s.type) == EditorMap.SKY_DEFAULT:
		return
	var l := _spin(box, Lang.t("Luminosité", "Brightness"), roundf(float(s.luminosite) * 100.0), EditorMap.SKY_LUM[0] * 100.0, EditorMap.SKY_LUM[1] * 100.0, 5.0, func(v):
		EditorMap.set_sky(c, String(EditorMap.sky_of(c).type), float(v) / 100.0), "%")
	l.tooltip_text = Lang.t("Luminosité du ciel (100 % par défaut).", "Sky brightness (100% by default).")


func _room_props(r: Dictionary) -> void:
	_title(_props, Lang.t("Pièce", "Room"))
	_position_row(r)
	var old_name := String(r.get("nom", ""))
	_line(_props, Lang.t("Nom", "Name"), old_name, func(t):
		# Zone d'une seule pièce qui portait le nom de la pièce : renommée avec elle.
		var z := ed.doc.zone(String(r.get("zone", "")))
		if not z.is_empty() and ed.doc.rooms_of_zone(String(z.id)).size() == 1 and String(z.nom.get("fr", "")) == String(r.get("nom", "")):
			z.nom = {"fr": t, "en": t if String(z.nom.get("en", "")) == String(r.get("nom", "")) else String(z.nom.get("en", ""))}
		r["nom"] = t)
	var names := []
	var ids := []
	for z in ed.doc.zones:
		names.append(("★ " if String(z.id) == ed.doc.depart else "") + ed.doc.zone_name(String(z.id)))
		ids.append(String(z.id))
	names.append(Lang.t("+ nouvelle zone", "+ new zone"))
	ids.append("")
	_option(_props, Lang.t("Zone", "Zone"), names, maxi(0, ids.find(String(r.get("zone", "")))), func(i): ed.set_room_zone(String(r.id), String(ids[i])))
	var k := ed.doc.level_of(r)
	# Format 17 : hauteur sous plafond sans maximum (2,8 m au moins) ; une pièce
	# dont le plafond dépasse le niveau du dessus est une pièce haute.
	var def_h := EditorMap.DEFAULT_CEILING
	var cs := _spin(_props, Lang.t("Hauteur sous plafond", "Ceiling height"), EditorMap.room_ceiling(r), MapVertical.ROOM_CEILING[0], 100.0, 0.1, func(v):
		if absf(v - def_h) < 0.001:
			r.erase("plafond")
		else:
			r["plafond"] = v)
	cs.allow_greater = true
	# Format 17 : plafond masqué (« sans_plafond ») : à ciel ouvert, on voit le
	# ciel de la carte (réglages de la carte).
	var shown := CheckBox.new()
	shown.text = Lang.t("Afficher le plafond", "Show the ceiling")
	shown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shown.button_pressed = not EditorMap.no_ceiling(r)
	shown.toggled.connect(func(on):
		ed.push_undo()
		EditorMap.set_no_ceiling(r, not on)
		# Panneau refait : la note du ciel ouvert apparaît ou disparaît.
		ed.changed())
	_props.add_child(shown)
	shown.tooltip_text = Lang.t("Décoché : pas de plafond (ni collision) au-dessus de la pièce, on voit le ciel de la carte. Rien n'empêche de sortir par le haut : fermez la carte par des murs assez hauts.",
		"Unchecked: no ceiling (nor collision) above the room, the map's sky shows. Nothing stops players leaving through the top: close the map with high enough walls.")
	if EditorMap.no_ceiling(r):
		_note(_props, Lang.t("À ciel ouvert : murs jusqu'à %s m ; les luminaires au plafond flottent.", "Open sky: walls up to %s m; ceiling lights float.") % _m(EditorMap.room_ceiling(r)))
	if ed.doc.is_high(r):
		_note(_props, Lang.t("Pièce haute : elle traverse le niveau du dessus (vide et murs ; une pièce posée au-dessus est une mezzanine).",
			"High room: it goes through the level above (void and walls; a room placed above is a mezzanine)."))
	MapPanelsShape.room_shape(self, r)
	# Textures de la pièce (par défaut : celles de sa zone).
	var z := ed.doc.zone(String(r.get("zone", "")))
	_title(_props, Lang.t("Textures", "Textures"))
	_surface_option(_props, Lang.t("Sol", "Floor"), r, "surface_sol", String(z.get("sol", "concrete")))
	_surface_option(_props, Lang.t("Murs", "Walls"), r, "surface_murs", String(z.get("murs", "wall")))
	_surface_option(_props, Lang.t("Plafond", "Ceiling"), r, "surface_plafond", String(z.get("plafond", "ceiling")))
	_note(_props, Lang.t("Un mur mitoyen montre de chaque côté la texture de sa pièce.", "A shared wall shows each room's texture on its own side."))
	var poly := ed.doc.room_poly(r)
	var bb := MapGeom.bbox(poly)
	_note(_props, Lang.t("%s · %s × %s m · %s m²\nMurs générés sur le contour ; un bord commun avec une pièce collée = un seul mur.",
		"%s · %s × %s m · %s m²\nWalls follow the outline; an edge shared with a touching room = a single wall.") % [EditorMap.level_name(ed.doc.level_alt(k)), _m(bb.size.x), _m(bb.size.y), _m(snappedf(MapGeom.area(poly), 0.5))])


## Monte ou descend la pièce `rid` à l'altitude `alt` (m, sans borne ; champ Z
## d'une pièce, format 17) : elle emporte son contenu (un escalier qui en part :
## son pied ; qui y arrive : son arrivée), en une étape d'annulation ; refus
## nommé, carte intacte (pièces empilées à moins de 3,1 m, contenu ou escalier
## qui ne tient pas).
func set_room_altitude(rid: String, alt: float) -> Dictionary:
	var o := ed.doc.find(rid)
	if o.is_empty() or not is_finite(alt):
		return MapRules.refuse("pièce introuvable", "room not found")
	var dalt := snappedf(alt, 0.0001) - EditorMap.alt_of(o)
	if absf(dalt) <= EditorMap.ALT_EQ:
		return {"ok": true}
	var snap := ed.doc.snapshot()
	var res := ed.try_move_alt(o.duplicate(true), ed.attached_to(o), Vector2.ZERO, dalt, NAN, snap)
	if res.ok:
		ed.push_undo_snapshot(snap)
		ed.changed()
		ed.select(rid)
	else:
		ed.canvas.show_refusal(res)
		refresh()
	return res


func _opening_props(o: Dictionary) -> void:
	var t := String(o.type)
	var it := MapCatalog.item_for(o)
	_title(_props, MapCatalog.name_of(it))
	_position_row(o)
	var k := ed.doc.level_of(o)
	if t != "fenetre":
		var types := ["porte", "debris", "porte_courant", "passage"]
		var names := types.map(func(x): return MapCatalog.name_of(MapCatalog.item(x)))
		_option(_props, Lang.t("Type", "Type"), names, types.find(t), func(i):
			ed.push_undo()
			o["type"] = types[i]
			# Les variantes sont propres à un type : l'aspect par défaut du nouveau.
			o.erase("variante")
			if types[i] in ["porte", "debris"] and not o.has("prix"):
				o["prix"] = ed.default_door_price()
			if not types[i] in ["porte", "debris"]:
				o.erase("prix")
			ed.changed())
		if t in ["porte", "debris"]:
			_spin(_props, Lang.t("Prix", "Price"), float(o.get("prix", 750)), 0, 20000, 250, func(v): o["prix"] = int(v), "")
		_variant_row(o)
		var w := _spin(_props, Lang.t("Largeur", "Width"), MapRules.opening_width(o), 1.0, 6.0, 0.5, func(v):
			var res := MapRules.place_opening(ed.doc, k, t, MapGeom.v2(o.position), v, String(o.id))
			if res.ok:
				o["largeur"] = v
				o["position"] = res.position
			else:
				ed.canvas.show_refusal(res))
		w.tooltip_text = Lang.t("BO1 : 1,5 à 3 m", "BO1: 1.5 to 3 m")
	else:
		# Format 8 : fenêtre, porte à zombies simple ou double (largeur du type).
		_variant_row(o)
		var bk := MapCatalog.barricade_kind(o)
		_note(_props, Lang.t("%s m de large · %d planches · %s", "%s m wide · %d boards · %s") % [_m(MapRules.opening_width(o)),
			BarricadeRules.planks_for(bk), Lang.t({"fenetre": "3 zombies arrachent à la fois", "porte": "1 zombie arrache à la fois, 3 attendent",
				"porte_double": "2 zombies arrachent à la fois (un par battant), 4 attendent"}[bk],
				{"fenetre": "3 zombies tear at once", "porte": "1 zombie tears at a time, 3 wait",
				"porte_double": "2 zombies tear at once (one per leaf), 4 wait"}[bk])])
	var res := MapRules.place_opening(ed.doc, k, t, MapGeom.v2(o.position), MapRules.opening_width(o), String(o.id))
	if res.ok:
		var rn: Array = res.rooms.map(func(rid): return String(ed.doc.find(rid).get("nom", rid)))
		_note(_props, (Lang.t("Relie : %s", "Links: %s") % " ↔ ".join(rn)) if t != "fenetre" else (Lang.t("Mur extérieur de « %s » ; les zombies arrivent de dehors", "Outer wall of \"%s\"; zombies come from outside") % rn[0]))


func _object_props(o: Dictionary) -> void:
	var t := String(o.type)
	var it := MapCatalog.item_for(o)
	_title(_props, MapCatalog.name_of(it).to_upper() if t == "prefab" else MapCatalog.name_of(it))
	_scale_fields = {}
	if t != "prefab":
		_position_row(o)
	match t:
		"atout":
			var ids := PerkDB.PERKS.keys()
			_option(_props, Lang.t("Atout", "Perk"), ids.map(func(x): return "%s (%d)" % [PerkDB.display_name(x), PerkDB.cost(x, false)]), ids.find(String(o.atout)), func(i):
				ed.push_undo()
				o["atout"] = String(ids[i])
				ed.changed())
		"arme":
			var list := MapCatalog.in_category("armes").filter(func(x): return String(x.id).begins_with("arme:"))
			var ids := list.map(func(x): return String(x.id).substr(5))
			_option(_props, Lang.t("Arme", "Weapon"), list.map(func(x): return "%s (%d)" % [MapCatalog.name_of(x), int(x.price)]), ids.find(String(o.arme)), func(i):
				ed.push_undo()
				o["arme"] = String(ids[i])
				ed.changed())
			_variant_row(o)
		"bloc_invisible":
			_clip_props(o)
		"boite":
			_check(_props, Lang.t("Départ de la boîte (un seul)", "Box start (only one)"), bool(o.get("depart", false)), func(on):
				if on:
					for q in ed.doc.objets:
						if String(q.get("type", "")) == "boite":
							q["depart"] = false
				o["depart"] = on)
			# Format 15 : pose de la boîte (au sol ou contre un mur).
			_note(_props, Lang.t("Posée au sol : l'avant (flèche) est le côté où s'ouvre le couvercle ; en jeu, elle s'achète de tous les côtés, jamais à travers un mur. Glissez-la près d'un mur pour l'y coller (Alt : sans aimant).",
				"On the floor: the front (arrow) is the side where the lid opens; in game it can be bought from every side, never through a wall. Drag it near a wall to snap it there (Alt: no magnet).") if MapCatalog.floor_box(o)
				else Lang.t("Contre un mur, face à la pièce. Glissez-la loin du mur pour la poser au sol (puis l'anneau ou « Angle » pour la tourner).",
				"Against a wall, facing the room. Drag it away from the wall to put it on the floor (then the ring or \"Angle\" to turn it)."))
		"escalier":
			_stair_props(o)
			var dirs := ["n", "e", "s", "o"]
			_option(_props, Lang.t("Monte vers", "Goes up to"), dirs.map(func(d): return Lang.t(DIR_NAMES[d][0], DIR_NAMES[d][1])), dirs.find(String(o.get("monte", "n"))), func(i):
				ed.push_undo()
				o["monte"] = dirs[i]
				ed.changed())
			# « Monte vers » qui contredit la forme : le jeu prend le seul sens
			# possible (MapRules.pick_stair_dir) ; on propose de l'écrire.
			var eff := String(MapRules.check_existing(ed.doc, o).get("monte", o.get("monte", "n")))
			if eff != String(o.get("monte", "n")) and DIR_NAMES.has(eff):
				var en := Lang.t(DIR_NAMES[eff][0], DIR_NAMES[eff][1])
				_note(_props, Lang.t("« Monte vers » ne correspond pas à la forme de l'escalier : le jeu le fait monter vers « %s » (seul sens où le départ et l'arrivée sont libres).",
					"\"Goes up to\" does not match the shape of the stairs: the game makes them go up to \"%s\" (the only way with a clear start and arrival).") % en)
				_button(_props, Lang.t("Corriger : monte vers « %s »", "Fix: goes up to \"%s\"") % en, func():
					ed.push_undo()
					o["monte"] = eff
					ed.changed())
			_note(_props, Lang.t("Relie le niveau %s au niveau %s. Le haut arrive sur le plancher d'une pièce du niveau du dessus ; le vide au-dessus des marches est automatique.",
				"Links level %s to level %s. The top lands on a room floor of the level above; the opening above the steps is automatic.") % [
					EditorMap.alt_text(EditorMap.alt_of(o), not Lang.is_en()), EditorMap.alt_text(ed.doc.stair_top_of(o), not Lang.is_en())])
		"prefab":
			_prefab_props(o)
		"luminaire":
			_light_props(o)
		"effet":
			_effect_props(o)
		"mur", "mur_courbe":
			var th := [0.5, 1.5, 2.5]
			_option(_props, Lang.t("Épaisseur", "Thickness"), th.map(func(v): return _m(v) + " m"), maxi(0, th.find(float(o.get("epaisseur", 0.5)))), func(i):
				ed.push_undo()
				o["epaisseur"] = th[i]
				ed.changed())
			if t == "mur_courbe":
				MapPanelsShape.arc_props(self, o)
	if t == "prefab":
		# Format 14 : sections Échelle, Rotation (X, Y, Z), Collision (MapPanelsScale).
		return
	if MapTransform.can_rotate(o) and not o.has("sommets"):
		# Polygone (barrière invisible) : pas d'angle propre ; poignée ronde ou R.
		MapPanelsShape.angle_row(self, o)
	var price := int(it.get("price", 0))
	if t == "atout":
		price = PerkDB.cost(String(o.atout), false)
	if price > 0:
		_note(_props, Lang.t("Prix en jeu : %d ferraille", "In-game price: %d scrap") % price)
	var hint := Lang.t(String(it.get("hint_fr", "")), String(it.get("hint_en", "")))
	if hint != "":
		_note(_props, hint)


## Barrière invisible (format 9 : polygone) : « Jusqu'au plafond » (pas de
## clé « hauteur ») ou une hauteur de 0,5 m au moins (format 17 : sans
## maximum de conception, MapCatalog.CLIP_HEIGHT), au dixième de mètre ;
## hauteur en jeu, sommets et surface ; rappel de ce qu'elle bloque.
func _clip_props(o: Dictionary) -> void:
	var to_ceiling := not o.has("hauteur")
	var room_h := MapVertical.room_h(ed.raster().v, {"altitude": EditorMap.alt_of(o), "position": MapGeom.bbox(MapRaster.clip_poly(o)).get_center()})
	var lim: Array = MapCatalog.CLIP_HEIGHT
	_check(_props, Lang.t("Jusqu'au plafond (hauteur de la pièce)", "Up to the ceiling (room height)"), to_ceiling, func(on):
		if on:
			o.erase("hauteur")
		else:
			# Hauteur de départ : celle de la pièce, à modifier ensuite.
			o["hauteur"] = snappedf(clampf(room_h, float(lim[0]), float(lim[1])), 0.1)
		refresh())
	var hs := _spin(_props, Lang.t("Hauteur", "Height"), float(o.get("hauteur", room_h)), float(lim[0]), float(lim[1]),
		MapCatalog.CLIP_HEIGHT_STEP, func(v):
			o["hauteur"] = snappedf(clampf(v, float(lim[0]), float(lim[1])), 0.01))
	hs.editable = not to_ceiling
	hs.tooltip_text = Lang.t("Du sol au haut de la barrière, %s à %s m (pas de 0,1 m). Décochez « Jusqu'au plafond » pour la régler." % [_m(float(lim[0])), _m(float(lim[1]))],
		"From the floor to the top of the barrier, %s to %s m (0.1 m steps). Untick \"Up to the ceiling\" to set it." % [_m(float(lim[0])), _m(float(lim[1]))])
	if to_ceiling:
		_note(_props, Lang.t("Hauteur en jeu : jusqu'au plafond (%s m ici, ou plus sous une pièce plus haute)", "In-game height: up to the ceiling (%s m here, or more under a taller room)") % _m(snappedf(room_h, 0.01)))
	else:
		_note(_props, Lang.t("Hauteur en jeu : %s m depuis le sol", "In-game height: %s m from the floor") % _m(float(o.hauteur)))
	var poly := MapRaster.clip_poly(o)
	_note(_props, Lang.t("%d sommets · %s m² · poignées carrées : déplacer un sommet", "%d corners · %s m² · square handles: move a corner") % [poly.size(), _m(snappedf(MapGeom.area(poly), 0.01))])
	_note(_props, Lang.t("Invisible en jeu. Se pose n'importe où (à cheval sur un mur, dehors, par-dessus un objet). Bloque les joueurs et les zombies (leurs trajets la contournent) ; les balles et les grenades passent, comme les barrières invisibles de BO1.",
		"Invisible in game. Goes anywhere (across a wall, outside, over an object). Blocks players and zombies (their paths go around it); bullets and grenades go through, like BO1 invisible clips."))


## Escalier (format 6) : type (V), sens du virage, garde-corps, côtés
## fermés ; rappel de ce qu'exige le type. Marches : toujours automatiques.
func _stair_props(o: Dictionary) -> void:
	var ids := MapCatalog.variants("escalier")
	var kind := MapCatalog.stair_kind(o)
	var opt := _option(_props, Lang.t("Type (V)", "Type (V)"), ids.map(func(x): return MapCatalog.variant_name("escalier", String(x))),
		maxi(0, ids.find(kind)), func(i):
			ed.push_undo()
			MapCatalog.set_variant(o, String(ids[i]))
			MapCatalog.tidy_stair(o)
			ed.changed())
	opt.tooltip_text = Lang.t("Forme des marches, leur collision et le trajet des zombies (ancres) suivent le type. V : type suivant",
		"Step layout, collision and the zombies' route (anchors) follow the type. V: next type")
	if StairGen.is_shaped(kind):
		var turns := MapCatalog.STAIR_TURNS
		_option(_props, Lang.t("Tourne vers", "Turns"), [Lang.t("la droite", "right"), Lang.t("la gauche", "left")],
			maxi(0, turns.find(String(o.get("sens", "droite")))), func(i):
				ed.push_undo()
				o["sens"] = turns[i]
				MapCatalog.tidy_stair(o)
				ed.changed())
	if StairGen.SIDE_KINDS.has(kind):
		# Format 17 : sortie en face (absente) ou sur un côté, vu en montant ;
		# choisie à la pose quand le haut des marches touche un mur.
		var exits := ["", "gauche", "droite"]
		var eo := _option(_props, Lang.t("Sortie en haut", "Exit at the top"), [Lang.t("en face", "straight ahead"), Lang.t("à gauche", "on the left"), Lang.t("à droite", "on the right")],
			maxi(0, exits.find(String(o.get("sortie", "")))), func(i):
				ed.push_undo()
				if exits[i] == "":
					o.erase("sortie")
				else:
					o["sortie"] = exits[i]
				MapCatalog.tidy_stair(o)
				ed.changed())
		eo.tooltip_text = Lang.t("Sur le côté : un palier plat en haut, la volée est plus courte ; le haut des marches peut toucher un mur.",
			"On the side: a flat landing at the top, the flight is shorter; the top of the stairs may touch a wall.")
	# Arrivée : un niveau au-dessus du pied (format 17 : n'importe lequel).
	var foot := EditorMap.alt_of(o)
	var ups := ed.doc.levels().filter(func(a): return float(a) > foot + EditorMap.ALT_EQ)
	if not ups.is_empty():
		var top := ed.doc.stair_top_of(o)
		var cur := 0
		for i in ups.size():
			if absf(float(ups[i]) - top) <= EditorMap.ALT_EQ:
				cur = i
		# Mêmes niveaux et mêmes noms que le menu de la barre et l'onglet Niveaux
		# (doc.levels(), EditorMap.level_name ; niveau vide signalé).
		var names := ups.map(func(a):
			var n := EditorMap.level_name(float(a))
			return n + Lang.t(" (vide)", " (empty)") if ed.doc.rooms_on(ed.doc.level_index(float(a))).is_empty() else n)
		_option(_props, Lang.t("Arrivée : altitude", "Arrival: altitude"), names, cur, func(i):
			ed.push_undo()
			o["altitude_haut"] = float(ups[i])
			ed.changed())
	_check(_props, Lang.t("Garde-corps", "Railing"), bool(o.get("garde_corps", MapCatalog.stair_rail_default(kind))), func(on):
		o["garde_corps"] = on
		MapCatalog.tidy_stair(o))
	_check(_props, Lang.t("Côtés fermés (limons pleins)", "Closed sides (solid stringers)"), String(o.get("cotes", "ouverts")) == "fermes", func(on):
		o["cotes"] = "fermes" if on else "ouverts"
		MapCatalog.tidy_stair(o))
	var mw := MapCatalog.stair_min_width(kind)
	var need: String = {
		"quart": Lang.t("En L : la sortie est sur le côté où il tourne, au bout ; il faut le plancher d'une pièce du niveau d'arrivée de ce côté.",
			"L-shaped: the exit is on the side it turns to, at the far end; the arrival level needs a room floor on that side."),
		"demi_tour": Lang.t("En U : la sortie revient du côté du pied, à côté du départ ; il faut le plancher d'une pièce du niveau d'arrivée de ce côté.",
			"U-shaped: the exit comes back on the foot side, next to the start; the arrival level needs a room floor on that side."),
		"colimacon": Lang.t("Colimaçon : un tour complet autour d'un noyau, sortie en face du pied ; 4 m de côté et 3,2 m entre les niveaux au moins.",
			"Spiral: one full turn around a newel, exit opposite the foot; at least 4 m per side and 3.2 m between levels."),
		"service": Lang.t("Escalier de service : 1 m de large suffit ; les zombies y montent en file indienne.", "Service stairs: 1 m wide is enough; zombies climb in single file."),
		"large": Lang.t("Escalier d'honneur : 3 m de large au moins, garde-corps des deux côtés ; la horde monte de front.",
			"Grand stairs: at least 3 m wide, railing on both sides; the horde climbs abreast."),
	}.get(kind, "")
	if need != "":
		_note(_props, need)
	_note(_props, Lang.t("Largeur minimale : %s m. Les zombies suivent ses ancres : entrée devant le pied, axe des marches, sortie sur le palier.",
		"Minimum width: %s m. Zombies follow its anchors: entry in front of the foot, the stairs' centreline, exit on the landing.") % _m(mw))


## Liste « Aspect » (variantes d'un type, MapCatalog.VARIANTS ; touche V).
func _variant_row(o: Dictionary) -> void:
	var t := String(o.get("type", ""))
	var ids := MapCatalog.variants(t)
	if ids.size() < 2:
		return
	var opt := _option(_props, Lang.t("Type (V)", "Type (V)") if t == "fenetre" else Lang.t("Aspect (V)", "Look (V)"), ids.map(func(x): return MapCatalog.variant_name(t, String(x))),
		maxi(0, ids.find(MapCatalog.variant_of(o))), func(i):
			if t == "fenetre":
				# Entrée des zombies : la porte double est plus large, elle doit tenir.
				var cand := o.duplicate(true)
				var res := MapRules.apply_variant(ed.doc, cand, String(ids[i]))
				if not res.ok:
					ed.canvas.show_refusal(res)
					ed.changed()
					return
				ed.push_undo()
				MapRules.apply_variant(ed.doc, o, String(ids[i]))
				ed.changed()
				return
			ed.push_undo()
			MapCatalog.set_variant(o, String(ids[i]))
			ed.changed(false))
	if t == "fenetre":
		opt.tooltip_text = Lang.t("Fenêtre, porte à zombies simple (1 m) ou double (2 m). V : type suivant",
			"Window, single (1 m) or double (2 m) zombie door. V: next type")
		return
	opt.tooltip_text = Lang.t("Modèle affiché en jeu ; même prix et même collision. V : aspect suivant",
		"Model shown in game; same price and same collision. V: next look")


## Change le modèle d'un décor ou d'un luminaire posé (`key` : prefab ou
## luminaire), s'il tient à sa place (emprise différente) ; sinon la raison.
func _swap_kind(o: Dictionary, key: String, value: String) -> void:
	var cand := o.duplicate(true)
	cand[key] = value
	if key == "luminaire":
		# Réglages par défaut du nouveau luminaire.
		var d: Dictionary = MapCatalog.LIGHTS[value]
		for p in ["couleur", "intensite", "portee", "courant", "vacille"]:
			cand[p] = d[p]
	var k := ed.doc.level_of(o)
	var res := MapRules.place_floor_item(ed.doc, k, cand, MapGeom.v2(o.position), String(o.id)) if MapCatalog.tool_of(cand) == "floor_item" \
		else MapRules.place_wall_item(ed.doc, k, cand, MapGeom.v2(o.position) - MapGeom.item_wall_dir(o) * 0.3, String(o.id))
	if not res.ok:
		ed.canvas.show_refusal(res)
		_fill_props.call_deferred()
		return
	ed.push_undo()
	for p in cand:
		o[p] = cand[p]
	o["position"] = res.position
	if MapCatalog.tool_of(cand) == "wall_item":
		MapRules.apply_wall(o, res)
	ed.changed()


func _prefab_props(o: Dictionary) -> void:
	# Décors du catalogue, puis les prefabs de la carte (format 10) ; format
	# 11 : seulement ceux du même montage (au sol, au mur, au plafond).
	var mount := MapCatalog.prefab_mount(String(o.get("prefab", "")))
	var ids := MapCatalog.prefab_ids().filter(func(x): return MapCatalog.prefab_mount(String(x)) == mount)
	var is_map := MapPrefabLib.is_ref(o.get("prefab"))
	# Prefab de la carte : « Prefab », son nom suivi de « (carte) » (maquette, écran 3).
	_option(_props, Lang.t("Prefab", "Prefab") if is_map else Lang.t("Décor", "Prop"),
		ids.map(func(x): return MapCatalog.prefab_name(String(x)) + (Lang.t(" (carte)", " (map)") if MapPrefabLib.is_ref(x) else "")),
		ids.find(String(o.get("prefab", ""))), func(i): _swap_kind(o, "prefab", String(ids[i])))
	var d := MapCatalog.def_of(o)
	# Maquette (format 14) : Décor, puis Position (sa note Z en bulle du champ Z).
	_position_row(o)
	if mount == "mur":
		# Format 11 : décor mural, hauteur libre sur le mur (comme une applique).
		_spin(_props, Lang.t("Hauteur", "Height"), MapCatalog.wall_light_height(o), MapCatalog.WALL_LIGHT_HEIGHT[0], MapCatalog.WALL_LIGHT_HEIGHT[1], 0.05,
			func(v): MapCatalog.set_wall_light_height(o, v))
	# Format 14 : Échelle, Rotation, Collision, Parties (docs/EDITOR_SCALE_ROTATE.md § 2.5).
	MapPanelsScale.build(self, o)
	if float(d.get("support", 0.0)) > 0.0 and MapScale.carries(o):
		_note(_props, Lang.t("Une lampe de bureau ou des bougies peuvent être posées dessus.", "A desk lamp or candles can be placed on top."))


func _light_props(o: Dictionary) -> void:
	var d := MapCatalog.def_of(o)
	var mount := String(d.get("mount", "plafond"))
	# Changer de luminaire : seulement pour un autre du même montage.
	var ids := MapCatalog.LIGHTS.keys().filter(func(x): return String(MapCatalog.LIGHTS[x].mount) == mount)
	_option(_props, Lang.t("Luminaire", "Fixture"), ids.map(func(x): return Lang.t(String(MapCatalog.LIGHTS[x].fr), String(MapCatalog.LIGHTS[x].en))),
		ids.find(String(o.get("luminaire", ""))), func(i): _swap_kind(o, "luminaire", String(ids[i])))
	var cp := ColorPickerButton.new()
	cp.color = MapCatalog.light_color(o)
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(0, 26)
	# Nuancier de Godot : sa mise en page interne n'est pas touchée (EditorUi).
	cp.get_popup().set_meta(EditorUi.SKIP, true)
	# Appliqué à la fermeture du nuancier (une seule étape d'annulation).
	cp.popup_closed.connect(func():
		var html := "#" + cp.color.to_html(false)
		if html != String(o.get("couleur", "")):
			ed.push_undo()
			o["couleur"] = html
			ed.changed(false))
	_row(_props, Lang.t("Couleur", "Colour"), cp)
	var lim: Dictionary = MapCatalog.LIGHT_LIMITS
	_spin(_props, Lang.t("Intensité", "Intensity"), float(o.get("intensite", d.intensite)), lim.intensite[0], lim.intensite[1], 0.1,
		func(v): o["intensite"] = snappedf(v, 0.1), "×")
	_spin(_props, Lang.t("Portée", "Range"), float(o.get("portee", d.portee)), lim.portee[0], lim.portee[1], 0.5, func(v): o["portee"] = v)
	_check(_props, Lang.t("Liée au courant (s'allume au courant)", "Tied to the power (lights up with the power)"), bool(o.get("courant", d.courant)),
		func(on): o["courant"] = on)
	_check(_props, Lang.t("Vacille", "Flickers"), bool(o.get("vacille", d.vacille)), func(on): o["vacille"] = on)
	if mount == "mur":
		# Format 7 : hauteur libre sur le mur (sous le plafond en jeu).
		_spin(_props, Lang.t("Hauteur", "Height"), MapCatalog.wall_light_height(o), MapCatalog.WALL_LIGHT_HEIGHT[0], MapCatalog.WALL_LIGHT_HEIGHT[1], 0.05,
			func(v): MapCatalog.set_wall_light_height(o, v))
	var where: String = {"plafond": Lang.t("Accroché au plafond de la pièce.", "Hung from the room ceiling."),
		"mur": Lang.t("Contre le mur, n'importe où le long du mur ; hauteur au choix (2 m par défaut, toujours sous le plafond en jeu).",
			"Against the wall, anywhere along it; any height (2 m by default, always below the ceiling in game)."),
		"sol": Lang.t("Posé au sol, ou sur un meuble (bureau, chariot, sacs de sable).", "On the floor, or on furniture (desk, cart, sandbags).")}[mount]
	_note(_props, where)
	if mount == "sol":
		var sup := MapRules.support_under(ed.doc, o)
		if not sup.is_empty():
			_note(_props, Lang.t("Posé sur : %s", "Standing on: %s") % MapCatalog.name_of(MapCatalog.item_for(sup)))
	if not bool(o.get("courant", d.courant)):
		_note(_props, Lang.t("Toujours allumé, même sans courant (bougies, feu).", "Always lit, even without power (candles, fire)."))


## Effet (format 10) : autre effet du même sous-onglet et du même montage,
## intensité, zone (format 11 : largeur, profondeur, hauteur d'un volume ou
## d'un effet mural), couleur (effets qui se teintent), hauteur de pose (au
## sol : surélévation ; au mur : hauteur) ; décor qui va avec ; jamais de
## collision.
func _effect_props(o: Dictionary) -> void:
	var d := MapCatalog.effect_def(o)
	if d.is_empty():
		return
	var mount := String(d.mount)
	var ids := MapCatalog.EFFECTS.keys().filter(func(x): return String(MapCatalog.EFFECTS[x].sub) == String(d.sub) and String(MapCatalog.EFFECTS[x].mount) == mount)
	if ids.size() > 1:
		_option(_props, Lang.t("Effet", "Effect"), ids.map(func(x): return Lang.t(String(MapCatalog.EFFECTS[x].fr), String(MapCatalog.EFFECTS[x].en))),
			ids.find(String(o.get("effet", ""))), func(i):
				var nid := String(ids[i])
				var cand := o.duplicate(true)
				cand["effet"] = nid
				# Zone gardée si elle tient dans les bornes du nouvel effet (sinon bornée).
				var zkeep := MapCatalog.effect_zone(o)
				cand.erase("zone")
				MapCatalog.set_effect_zone(cand, zkeep)
				MapCatalog.tidy_effect(cand)
				if mount != "mur" and not cand.has("rot"):
					cand["rot"] = 0
				var k := ed.doc.level_of(o)
				var res := MapRules.place_floor_item(ed.doc, k, cand, MapGeom.v2(o.position), String(o.id), false) if mount != "mur" \
					else MapRules.place_wall_item(ed.doc, k, cand, MapGeom.v2(o.position) - MapGeom.item_wall_dir(o) * 0.3, String(o.id))
				if not res.ok:
					ed.canvas.show_refusal(res)
					_fill_props.call_deferred()
					return
				ed.push_undo()
				o.clear()
				o.merge(cand)
				o["position"] = res.position
				if mount == "mur":
					MapRules.apply_wall(o, res)
				ed.changed())
	var lim: Dictionary = MapCatalog.EFFECT_LIMITS
	_spin(_props, Lang.t("Intensité", "Intensity"), MapCatalog.effect_value(o, "intensite"), lim.intensite[0], lim.intensite[1], 0.05, func(v):
		o["intensite"] = v
		MapCatalog.tidy_effect(o), "×").tooltip_text = Lang.t("Quantité de particules (densité dans la zone) et force de la lumière",
			"Amount of particles (density in the zone) and strength of the light")
	# Format 11 : zone de l'effet (largeur, profondeur ; hauteur d'un volume ou
	# d'un effet mural), dans les bornes de l'effet ; aussi aux poignées du plan.
	var fid := String(o.get("effet", ""))
	var z := MapCatalog.effect_zone(o)
	var labels := {"l": [Lang.t("Largeur", "Width"), Lang.t("Le long du mur", "Along the wall") if mount == "mur" else Lang.t("Côté x de la zone (avant rotation)", "Zone x side (before rotation)")],
		"p": [Lang.t("Profondeur", "Depth"), Lang.t("Côté y de la zone (avant rotation)", "Zone y side (before rotation)")],
		"h": [Lang.t("Hauteur de zone", "Zone height"), Lang.t("Étendue verticale sur le mur", "Vertical extent on the wall") if mount == "mur"
			else Lang.t("Épaisseur du volume, depuis sa hauteur de pose", "Thickness of the volume, from its placement height")]}
	for key in MapCatalog.effect_dims(fid):
		var b := MapCatalog.effect_zone_bounds(fid, key)
		var cur: float = {"l": z.x, "p": z.y, "h": z.z}[key]
		var sp := _spin(_props, String(labels[key][0]), cur, b[0], b[1], MapCatalog.ZONE_STEP, func(v):
			var nz := MapCatalog.effect_zone(o)
			match key:
				"l":
					nz.x = v
				"p":
					nz.y = v
				"h":
					nz.z = v
			MapCatalog.set_effect_zone(o, nz))
		sp.tooltip_text = "%s (%s – %s m)" % [labels[key][1], MapCatalog.short_num(b[0]), MapCatalog.short_num(b[1])]
	if mount != "plafond":
		var hs := _spin(_props, Lang.t("Hauteur", "Height"), MapCatalog.effect_height(o), lim.hauteur[0], lim.hauteur[1], 0.05, func(v):
			o["hauteur"] = v
			MapCatalog.tidy_effect(o))
		hs.tooltip_text = Lang.t("Au-dessus du sol (sur un baril, une table...)", "Above the floor (on a barrel, a table...)") if mount == "sol" \
			else Lang.t("Hauteur sur le mur (toujours sous le plafond en jeu)", "Height on the wall (always below the ceiling in game)")
	if MapCatalog.effect_tints(o):
		var cp := ColorPickerButton.new()
		cp.color = MapCatalog.effect_color(o)
		cp.edit_alpha = false
		cp.custom_minimum_size = Vector2(0, 26)
		cp.get_popup().set_meta(EditorUi.SKIP, true)
		cp.popup_closed.connect(func():
			var html := "#" + cp.color.to_html(false)
			if html != String(o.get("couleur", "")):
				ed.push_undo()
				o["couleur"] = html
				MapCatalog.tidy_effect(o)
				ed.changed(false))
		_row(_props, Lang.t("Couleur", "Colour"), cp)
	if MapCatalog.rotates(o):
		_note(_props, Lang.t("Rotation : %d° (R, poignée ronde)", "Rotation: %d° (R, round handle)") % int(o.get("rot", 0)))
	_note(_props, Lang.t("Zone : poignées aux coins et aux milieux sur le plan ; plus grande, plus de particules (même densité).",
		"Zone: handles at the corners and midpoints on the plan; bigger means more particles (same density).") if mount != "mur"
		else Lang.t("Zone : poignées aux deux bouts sur le plan ; plus large, plus de particules (même densité).",
		"Zone: handles at both ends on the plan; wider means more particles (same density)."))
	var decor: Array = d.get("decor", [])
	if not decor.is_empty():
		_note(_props, Lang.t("Objet qui va avec : %s (onglet Décor).", "Matching object: %s (Props tab).") % ", ".join(decor.map(func(x): return MapCatalog.prefab_name(String(x)))))
	_note(_props, Lang.t("Effet visuel seulement : aucun objet, aucune collision, ne blesse personne ; se pose par-dessus le décor et les objets de jeu. %d effets au plus par carte.",
		"Visual effect only: no object, no collision, hurts nobody; goes over props and game objects. At most %d effects per map.") % MapCatalog.MAX_EFFECTS)


# ------------------------------------------------------------------ position (X, Y, Z)

## Point repère d'un élément pour les champs X et Y (m) : coin nord-ouest
## d'une pièce ou d'une barrière, position d'un objet posé, milieu d'un
## rectangle (pilier, escalier, piège) ou d'un mur.
static func ref_point(doc: EditorMap, o: Dictionary) -> Vector2:
	if o.has("contour"):
		return MapGeom.bbox(doc.room_poly(o)).position
	if String(o.get("type", "")) == "bloc_invisible":
		return MapGeom.bbox(MapRaster.clip_poly(o)).position
	if o.has("position"):
		return MapGeom.v2(o.position)
	if o.has("centre"):
		return MapGeom.v2(o.centre)
	if o.has("a") and o.has("b"):
		return (MapGeom.v2(o.a) + MapGeom.v2(o.b)) * 0.5
	return MapRules.footprint_rect(o).get_center()


## Ligne « Position » (docs/EDITOR_VIEWS.md § 6.3, D11) : X, Y (m) et Z (hauteur
## de pose au-dessus du sol du niveau quand l'élément en a une, sinon
## l'altitude de son sol ; celle d'une pièce est libre). Un champ validé =
## une étape d'annulation ; une valeur refusée est remise et la raison s'affiche.
func _position_row(o: Dictionary) -> void:
	_pos_fields = {}
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = Lang.t("Position", "Position")
	# Colonne du libellé plus étroite : trois champs tiennent même à 150 %.
	l.custom_minimum_size = Vector2(76, 0)
	h.add_child(l)
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	h.add_child(box)
	_props.add_child(h)
	var p := ref_point(ed.doc, o)
	var oid := String(o.id)
	_axis_field(box, "X", p.x, func(v: float): _apply_xy(oid, "X", v))
	_axis_field(box, "Y", p.y, func(v: float): _apply_xy(oid, "Y", v))
	var kind := MapVertical.pose_kind(o)
	if kind == "pose":
		_axis_field(box, "Z", MapVertical.pose_z(ed.doc, ed.raster().v, o), func(v: float): _apply_z(oid, v))
		var b := MapVertical.pose_bounds(ed.raster().v, o)
		var room := MapRules.room_at(ed.doc, ed.doc.level_of(o), MapVertical.anchor_of(o))
		var note := Lang.t("Z : hauteur au-dessus du sol du niveau, de %s à %s m ici", "Z: height above the floor, %s to %s m here") % [_m(snappedf(b.x, 0.01)), _m(snappedf(b.y, 0.01))]
		if not room.is_empty():
			note += Lang.t(" (plafond de « %s »).", " (\"%s\" ceiling).") % String(room.get("nom", ""))
		if String(o.get("type", "")) == "prefab":
			# Format 14 (maquette) : la note du décor est la bulle du champ Z.
			(_pos_fields["Z"] as Control).tooltip_text = note
		else:
			_note(_props, note)
	elif o.has("contour"):
		# Format 17 : Z d'une pièce = l'altitude de son sol, libre (une nouvelle
		# altitude crée un niveau) ; elle emporte son contenu.
		_axis_field(box, "Z", EditorMap.alt_of(o), func(v: float): set_room_altitude(oid, v))
		(_pos_fields["Z"] as Control).tooltip_text = Lang.t("Altitude du sol de la pièce (son niveau). La changer emporte son contenu ; une nouvelle altitude crée un niveau.",
			"Altitude of the room's floor (its level). Changing it carries its content; a new altitude creates a level.")
		_note(_props, Lang.t("X, Y : coin nord-ouest. Z : altitude du sol ; la changer emporte le contenu de la pièce.",
			"X, Y: north-west corner. Z: floor altitude; changing it carries the room's content."))
	else:
		# Z d'un élément sans hauteur de pose : l'altitude de son niveau (une
		# valeur tapée va au niveau le plus proche).
		var ze := _axis_field(box, "Z", EditorMap.alt_of(o), func(v: float): _apply_floor(oid, MapVertical.nearest_floor(ed.doc, v)))
		(_pos_fields["Z"] as Control).tooltip_text = Lang.t("Z : altitude de son niveau (une valeur va au niveau le plus proche)", "Z: altitude of its level (a value goes to the nearest level)")
		if kind == "fixe":
			ze.editable = false
			_note(_props, Lang.t("Une ouverture suit son mur : pour changer de niveau, déplacez la pièce.", "An opening follows its wall: to change level, move the room."))


## Champ d'un axe : sa lettre en couleur, la valeur (m).
func _axis_field(box: Container, axis: String, value: float, apply: Callable) -> LineEdit:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("121214")
	sb.border_color = Color("4D4D54")
	sb.set_border_width_all(1)
	sb.content_margin_left = 5
	sb.content_margin_right = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	pc.add_child(hb)
	var lab := Label.new()
	lab.text = axis
	lab.add_theme_color_override("font_color", MapView.axis_color(axis))
	lab.add_theme_font_override("font", MapView.bold_font())
	hb.add_child(lab)
	var e := LineEdit.new()
	e.flat = true
	e.text = MapView.num(value, 2)
	e.custom_minimum_size = Vector2(16, 0)
	e.add_theme_constant_override("minimum_character_width", 1)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	e.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	e.select_all_on_focus = true
	e.set_meta("applied", e.text)
	var commit := func(_t := ""):
		if e.text == String(e.get_meta("applied")):
			return
		# Vrai signe moins de MapView.num (coordonnées négatives, format 17).
		var s := e.text.replace(",", ".").replace("−", "-").strip_edges()
		if not s.is_valid_float() or not is_finite(float(s)):
			e.text = String(e.get_meta("applied"))
			return
		e.set_meta("applied", e.text)
		apply.call(float(s))
	e.text_submitted.connect(commit)
	e.focus_exited.connect(commit)
	hb.add_child(e)
	box.add_child(pc)
	_pos_fields[axis] = pc
	return e


## Déplacement de l'élément (champ X ou Y) : mêmes règles qu'un glissement.
func _apply_xy(oid: String, axis: String, v: float) -> void:
	var o := ed.doc.find(oid)
	if o.is_empty():
		return
	var p := ref_point(ed.doc, o)
	var d := Vector2(v - p.x, 0) if axis == "X" else Vector2(0, v - p.y)
	_apply_3d(oid, d, ed.doc.level_of(o), NAN)


func _apply_z(oid: String, v: float) -> void:
	var o := ed.doc.find(oid)
	if not o.is_empty():
		_apply_3d(oid, Vector2.ZERO, ed.doc.level_of(o), v)


func _apply_floor(oid: String, k: int) -> void:
	var o := ed.doc.find(oid)
	if o.is_empty():
		return
	if k != ed.doc.level_of(o):
		_apply_3d(oid, Vector2.ZERO, k, NAN)
	else:
		# Même niveau : le champ Z reprend son altitude.
		refresh()


func _apply_3d(oid: String, delta: Vector2, k: int, z: float) -> void:
	var o := ed.doc.find(oid)
	var snap := ed.doc.snapshot()
	var res := ed.try_move_3d(o.duplicate(true), ed.attached_to(o), delta, k, z, snap)
	if res.ok:
		ed.push_undo_snapshot(snap)
		ed.changed()
		if ed.doc.level_of(ed.doc.find(oid)) != ed.floor_k:
			ed.select(oid)
	else:
		ed.canvas.show_refusal(res)
		refresh()


## Format 14 : pendant un geste d'échelle ou de rotation, les champs
## Échelle et Rotation (et la position) suivent l'élément, bord jaune.
func live_scale(on: bool) -> void:
	var o := ed.doc.find(ed.selected)
	if o.is_empty():
		return
	MapPanelsScale.live(self, o, on)
	# La position suit (le centre bouge) sans bord jaune (maquette, écran 1) ;
	# X et Y seulement (Z demanderait la grille de la carte : trop lent pendant
	# un geste sur une grande carte).
	var p := ref_point(ed.doc, o)
	for axis in ["X", "Y"]:
		var c: Variant = _pos_fields.get(axis)
		if c is PanelContainer and is_instance_valid(c):
			var le := (c as PanelContainer).get_child(0).get_child(1) as LineEdit
			if le != null and not le.has_focus():
				le.text = MapView.num(p.x if axis == "X" else p.y, 2)
				le.set_meta("applied", le.text)


## Pendant un glissement : les champs X, Y, Z suivent l'élément (bord jaune).
func live_position(on: bool) -> void:
	var o := ed.doc.find(ed.selected)
	if o.is_empty() or _pos_fields.is_empty():
		return
	var p := ref_point(ed.doc, o)
	var vals := {"X": p.x, "Y": p.y}
	vals["Z"] = MapVertical.pose_z(ed.doc, ed.raster().v, o) if MapVertical.pose_kind(o) == "pose" else EditorMap.alt_of(o)
	for axis in _pos_fields:
		var c: Control = _pos_fields[axis]
		if not is_instance_valid(c):
			continue
		if c is PanelContainer:
			var sb := (c as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null:
				sb.border_color = Color("FFD94D") if on else Color("4D4D54")
			var le := c.get_child(0).get_child(1) as LineEdit
			if vals.has(axis) and le != null and not le.has_focus():
				le.text = MapView.num(float(vals[axis]), 2)
				le.set_meta("applied", le.text)


# ------------------------------------------------------------------ listes

func _fill_rooms() -> void:
	_rooms.clear()
	_room_ids.clear()
	var list := ed.doc.pieces.duplicate()
	list.sort_custom(func(a, b): return [ed.doc.level_of(a), String(a.get("nom", ""))] < [ed.doc.level_of(b), String(b.get("nom", ""))])
	for p in list:
		var poly := ed.doc.room_poly(p)
		_rooms.add_item(Lang.t("É%d · %s — %s (%s m²)", "F%d · %s — %s (%s m²)") % [ed.doc.level_of(p), p.get("nom", ""), ed.doc.zone_name(String(p.get("zone", ""))), _m(snappedf(MapGeom.area(poly), 0.5))])
		_room_ids.append(String(p.id))
		if String(p.id) == ed.selected:
			_rooms.select(_rooms.item_count - 1)


func _fill_zones() -> void:
	_zones.clear()
	_zone_ids.clear()
	for z in ed.doc.zones:
		var n := ed.doc.rooms_of_zone(String(z.id)).size()
		_zones.add_item("%s%s  (%d %s)" % ["★ " if String(z.id) == ed.doc.depart else "", ed.doc.zone_name(String(z.id)), n, Lang.t("pièce(s)", "room(s)")])
		_zone_ids.append(String(z.id))
	if not _zone_ids.has(_zone_sel):
		var r := ed.doc.find(ed.selected)
		_zone_sel = String(r.get("zone", _zone_ids[0] if not _zone_ids.is_empty() else ""))
	var i := _zone_ids.find(_zone_sel)
	if i >= 0:
		_zones.select(i)
	_fill_zone_form()


func _fill_zone_form() -> void:
	_clear(_zone_form)
	var z := ed.doc.zone(_zone_sel)
	if z.is_empty():
		_note(_zone_form, Lang.t("Posez une pièce : elle crée sa zone.", "Place a room: it creates its zone."))
		return
	var nm: Dictionary = z.get("nom", {})
	_line(_zone_form, Lang.t("Nom (FR)", "Name (FR)"), String(nm.get("fr", "")), func(t): z.nom["fr"] = t)
	_line(_zone_form, Lang.t("Nom (EN)", "Name (EN)"), String(nm.get("en", "")), func(t): z.nom["en"] = t)
	_surface_option(_zone_form, Lang.t("Sol", "Floor"), z, "sol", "concrete", true)
	_surface_option(_zone_form, Lang.t("Murs", "Walls"), z, "murs", "wall", true)
	_surface_option(_zone_form, Lang.t("Plafond", "Ceiling"), z, "plafond", "ceiling", true)
	_note(_zone_form, Lang.t("Textures par défaut des pièces de la zone (chaque pièce peut avoir les siennes : onglet Propriétés).",
		"Default textures of the zone's rooms (each room may have its own: Properties tab)."))
	var rooms := ed.doc.rooms_of_zone(_zone_sel).map(func(p): return String(p.get("nom", p.id)))
	_note(_zone_form, Lang.t("Pièces : %s", "Rooms: %s") % ", ".join(rooms))
	var start := _zone_sel == ed.doc.depart
	var b := _button(_zone_form, Lang.t("★ Zone de départ", "★ Starting zone") if start else Lang.t("En faire la zone de départ", "Make it the starting zone"), func(): ed.set_start_zone(_zone_sel))
	b.disabled = start
	var sp := _button(_zone_form, Lang.t("Séparer (une zone par pièce)", "Split (one zone per room)"), func(): ed.split_zone(_zone_sel))
	sp.disabled = rooms.size() < 2
	var others := ed.doc.zones.filter(func(q): return String(q.id) != _zone_sel)
	if not others.is_empty():
		var h := HBoxContainer.new()
		_zone_form.add_child(h)
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for q in others:
			o.add_item(ed.doc.zone_name(String(q.id)))
		h.add_child(o)
		var mb := Button.new()
		mb.text = Lang.t("Fusionner dedans", "Merge into")
		mb.tooltip_text = Lang.t("Les pièces de cette zone rejoignent la zone choisie", "This zone's rooms join the chosen zone")
		mb.pressed.connect(func(): ed.merge_zones(_zone_sel, String(others[o.selected].id)))
		h.add_child(mb)


## Onglet Niveaux (format 17, étape 5) : les niveaux de la carte (altitudes
## distinctes des pièces), du plus haut au plus bas, avec leurs pièces et
## leurs zones. Un clic choisit le niveau sur lequel agir (double-clic ou
## « Voir » : l'afficher) ; actions : altitude, déplacer de … m, dupliquer
## au-dessus, nouveau niveau vide à … m, supprimer (confirmation) ;
## affichage du plan (fantôme du dessous, pièces du dessus en pointillés) et
## ciel de la carte (vu au-dessus des pièces sans plafond).
func _fill_floors() -> void:
	_floors.clear()
	var fr := not Lang.is_en()
	# Le niveau choisi suit le niveau affiché quand celui-ci change.
	if absf(ed.view_alt() - _level_view_seen) > EditorMap.ALT_EQ or ed.doc.level_index(_level_sel) < 0:
		_level_sel = ed.view_alt()
	_level_view_seen = ed.view_alt()
	var ksel := maxi(0, ed.doc.level_index(_level_sel))
	for line in ed.level_menu_lines():
		var k := int(line.k)
		var rooms := ed.doc.rooms_on(k)
		var zs := {}
		for p in rooms:
			zs[ed.doc.zone_name(String(p.get("zone", "")))] = true
		var t := ("▶ " if k == ed.floor_k else "") + Lang.t("%s — %d pièce(s)", "%s — %d room(s)") % [EditorMap.level_name(ed.doc.level_alt(k)), rooms.size()]
		if not zs.is_empty():
			t += " · " + ", ".join(zs.keys())
		elif rooms.is_empty():
			t += Lang.t(" (vide, non enregistré)", " (empty, not saved)")
		var i := _floors.add_item(t)
		_floors.set_item_metadata(i, k)
		if k == ksel:
			_floors.select(i)
	_clear(_floor_form)
	var k := ksel
	var a := ed.doc.level_alt(k)
	_title(_floor_form, EditorMap.level_name(a) + (Lang.t(" (affiché)", " (shown)") if k == ed.floor_k else ""))
	var see := _button(_floor_form, Lang.t("Voir ce niveau", "Show this level"), func(): ed.set_floor(k))
	see.name = "LevelSee"
	see.disabled = k == ed.floor_k
	var s := _free_spin(a, 0.05)
	s.name = "LevelAlt"
	s.value_changed.connect(func(v): ed.move_level(k, float(v)))
	s.tooltip_text = Lang.t("Altitude du sol du niveau : tout ce qui y est posé suit (et l'arrivée des escaliers qui y montent).",
		"Floor altitude of the level: everything on it follows (and the arrival of the stairs going up to it).")
	_row(_floor_form, Lang.t("Altitude du sol", "Floor altitude"), s)
	var mh := HBoxContainer.new()
	var ml := Label.new()
	ml.text = Lang.t("Déplacer de", "Move by")
	ml.custom_minimum_size = Vector2(118, 0)
	mh.add_child(ml)
	var md := _free_spin(_level_move_by, 0.25)
	md.name = "LevelMoveBy"
	md.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	md.value_changed.connect(func(v): _level_move_by = float(v))
	mh.add_child(md)
	var mb := Button.new()
	mb.name = "LevelMoveGo"
	mb.text = Lang.t("Déplacer", "Move")
	mb.pressed.connect(func():
		var v := md.get_line_edit().text.replace(",", ".").replace("m", "").strip_edges()
		ed.move_level_by(k, float(v) if v.is_valid_float() else md.value))
	mh.add_child(mb)
	_floor_form.add_child(mh)
	var dup := _button(_floor_form, Lang.t("Dupliquer au-dessus (+%s)", "Duplicate above (+%s)") % EditorMap.alt_text(ed.level_copy_gap(k), fr), func(): ed.duplicate_level(k))
	dup.name = "LevelDuplicate"
	dup.disabled = ed.doc.rooms_on(k).is_empty()
	dup.tooltip_text = Lang.t("Copie de ses pièces, ouvertures et objets juste au-dessus de sa plus haute pièce (nouveaux identifiants, une zone neuve par zone ; les escaliers ne sont pas copiés).",
		"Copy of its rooms, openings and objects right above its highest room (new ids, a new zone per zone; stairs are not copied).")
	var nh := HBoxContainer.new()
	var nl := Label.new()
	nl.text = Lang.t("Nouveau niveau vide à", "New empty level at")
	nl.custom_minimum_size = Vector2(118, 0)
	nh.add_child(nl)
	var top := ed.doc.level_alt(ed.doc.level_count() - 1)
	var na := _free_spin(snappedf(top + EditorMap.FLOOR_STEP, 0.01), 0.05)
	na.name = "LevelNewAlt"
	na.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(na)
	var nb := Button.new()
	nb.name = "LevelNewGo"
	nb.text = Lang.t("Créer", "Create")
	nb.pressed.connect(func():
		var v := na.get_line_edit().text.replace(",", ".").replace("m", "").strip_edges()
		ed.add_level_at(float(v) if v.is_valid_float() else na.value))
	nh.add_child(nb)
	_floor_form.add_child(nh)
	var rm := _button(_floor_form, Lang.t("Supprimer le niveau…", "Delete the level…"), func(): ed.delete_level(k))
	rm.name = "LevelDelete"
	rm.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	rm.disabled = ed.doc.level_count() <= 1 and ed.level_content(k).is_empty()
	rm.tooltip_text = Lang.t("Supprime tout ce qui y est posé (et les escaliers qui y arrivent), après confirmation ; Ctrl+Z le rétablit.",
		"Deletes everything placed on it (and the stairs arriving there), after confirmation; Ctrl+Z brings it back.")
	_note(_floor_form, Lang.t("Un niveau = les pièces posées à la même altitude ; changer son altitude déplace tout ce qui y est posé. Les niveaux sont libres (demi-niveau compris) ; deux pièces qui se recouvrent sont à %s au moins l'une de l'autre. Chaque pièce règle sa hauteur sous plafond ; sous une pièce posée au-dessus, le plafond est le plus bas des deux (sa dalle)." % EditorMap.alt_text(EditorMap.MIN_STACK, fr),
		"A level = the rooms placed at the same altitude; changing its altitude moves everything on it. Levels are free (half levels included); two overlapping rooms are at least %s apart. Each room sets its ceiling height; under a room placed above, the ceiling is the lower of the two (its slab)." % EditorMap.alt_text(EditorMap.MIN_STACK, false)))
	_title(_floor_form, Lang.t("Plan", "Plan"))
	var gh := CheckBox.new()
	gh.name = "LevelGhost"
	gh.text = Lang.t("Fantôme du niveau du dessous (ses sommets aimantent sans grille)", "Ghost of the level below (its corners snap without grid)")
	gh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gh.button_pressed = ed.ghost_below
	gh.toggled.connect(func(on):
		ed.ghost_below = on
		ed.canvas.queue_redraw())
	_floor_form.add_child(gh)
	var da := CheckBox.new()
	da.name = "LevelDashedAbove"
	da.text = Lang.t("Pièces du dessus en pointillés", "Rooms above as dashed outlines")
	da.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	da.button_pressed = ed.dashed_above
	da.toggled.connect(func(on):
		ed.dashed_above = on
		ed.canvas.queue_redraw())
	_floor_form.add_child(da)
	_note(_floor_form, Lang.t("Hachures : vide d'une pièce haute d'un niveau plus bas (elle traverse ce niveau). Alt + clic : pièce empilée suivante sous le curseur.",
		"Hatching: void of a high room from a lower level (it goes through this level). Alt + click: next stacked room under the cursor."))
	_title(_floor_form, Lang.t("Ciel de la carte", "Map sky"))
	_sky_props(ed.doc.carte, _floor_form)
	_note(_floor_form, Lang.t("Vu au-dessus des pièces sans plafond (case « Afficher le plafond » d'une pièce). Aussi dans les réglages de la carte (rien de sélectionné, onglet Propriétés).",
		"Seen above rooms without a ceiling (a room's \"Show the ceiling\" box). Also in the map settings (nothing selected, Properties tab)."))


## Niveau choisi dans l'onglet Niveaux (altitude : suit les changements
## d'indices) et niveau affiché vu au dernier remplissage.
var _level_sel := 0.0
var _level_view_seen := INF
## Écart de « Déplacer le niveau de … m » (gardé d'un remplissage à l'autre).
var _level_move_by := 0.5


## Champ d'altitude sans borne (m).
func _free_spin(value: float, stp: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = -100.0
	s.max_value = 100.0
	s.allow_greater = true
	s.allow_lesser = true
	s.step = stp
	s.value = value
	s.suffix = "m"
	s.select_all_on_focus = true
	return s


# ------------------------------------------------------------------ vérification

func show_validation() -> void:
	var v := ed.validator
	_clear(_check_list)
	_check_msgs.clear()
	if v == null:
		return
	var ne := v.errors().size()
	var nw := v.warnings().size()
	_check_summary.text = Lang.t("✔ Carte jouable : %d avertissement(s). Bouton ▶ TESTER pour y jouer.", "✔ Playable map: %d warning(s). ▶ PLAY TEST button to play it.") % nw if ne == 0 \
		else Lang.t("✖ %d erreur(s) à corriger avant de jouer, %d avertissement(s). Cliquez un problème pour le voir.", "✖ %d error(s) to fix before playing, %d warning(s). Click a problem to see it.") % [ne, nw]
	_check_summary.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if ne == 0 else Color(1, 0.45, 0.4))
	for level in ["erreur", "attention", "info"]:
		for m in v.messages.filter(func(x): return x.level == level):
			var icon: String = {"erreur": "✖ ", "attention": "⚠ ", "info": "· "}[level]
			# Bouton plat à la ligne : clic = vue centrée sur le problème.
			var b := Button.new()
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.text = icon + MapValidator.text_of(m)
			b.custom_minimum_size = Vector2(PANEL_TEXT_W, 0)
			var col: Color = {"erreur": Color(1, 0.5, 0.45), "attention": Color(1, 0.8, 0.4), "info": Color(0.75, 0.78, 0.8)}[level]
			b.add_theme_color_override("font_color", col)
			b.add_theme_color_override("font_hover_color", col.lightened(0.3))
			b.add_theme_font_size_override("font_size", 13)
			if not (m.get("cells", []) as Array).is_empty():
				b.pressed.connect(ed.focus_problem.bind(m))
				b.tooltip_text = Lang.t("Clic : voir sur la carte", "Click: show on the map")
			_check_list.add_child(b)
			_check_msgs.append(m)
