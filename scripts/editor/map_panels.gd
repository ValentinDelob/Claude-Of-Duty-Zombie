class_name MapPanels
extends TabContainer
## Panneaux de l'éditeur de cartes : Propriétés (élément choisi, sinon la
## carte), Pièces, Zones (regrouper, renommer FR/EN, fusionner, séparer, zone
## de départ), Étages (ajouter, hauteurs, étage du dessous en transparence) et
## Vérification (validateur : clic sur un problème = vue centrée dessus).

const TABS := ["props", "rooms", "zones", "floors", "check"]
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
	var fv := _tab("floors", Lang.t("Étages", "Floors"))
	_floors = ItemList.new()
	_floors.custom_minimum_size = Vector2(0, 140)
	_floors.item_selected.connect(func(i): ed.set_floor(i))
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
	tab_changed.connect(func(t):
		if TABS[t] == "check" and (ed.validation_stale or ed.validator == null):
			ed.validate())


func _tab(id: String, title_text: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = id
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	o.item_selected.connect(func(i): apply.call(i))
	_row(box, label, o)
	return o


func _check(box: Container, text: String, value: bool, apply: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
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


# ------------------------------------------------------------------ propriétés

func _fill_props() -> void:
	_props_for = ed.selected
	_clear(_props)
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
	var h := HBoxContainer.new()
	_props.add_child(h)
	if e.has("contour") or e.has("rect") or String(e.get("type", "")) == "mur":
		_button(h, Lang.t("Pivoter (R)", "Rotate (R)"), ed.rotate_selected)
	_button(h, Lang.t("Supprimer (Suppr)", "Delete (Del)"), func(): ed.delete_element(String(e.id)))


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
	_note(_props, Lang.t("Dossier : %s\n%d pièce(s), %d ouverture(s), %d objet(s)", "Folder: %s\n%d room(s), %d opening(s), %d object(s)") % [
		ed.doc.id(), ed.doc.pieces.size(), ed.doc.ouvertures.size(), ed.doc.objets.size()])


func _room_props(r: Dictionary) -> void:
	_title(_props, Lang.t("Pièce", "Room"))
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
	var k := int(r.get("etage", 0))
	var def_h := ed.doc.floor_height(k)
	_spin(_props, Lang.t("Plafond", "Ceiling"), float(r.get("plafond", def_h)), 2.8, 9.0, 0.1, func(v):
		if absf(v - def_h) < 0.001:
			r.erase("plafond")
		else:
			r["plafond"] = v)
	var top := k >= ed.doc.floor_count() - 1
	var dh := _check(_props, Lang.t("Double hauteur (ouverte sur l'étage du dessus)", "Double height (open to the floor above)"), bool(r.get("double_hauteur", false)), func(on):
		if on:
			r["double_hauteur"] = true
		else:
			r.erase("double_hauteur"))
	dh.disabled = top
	if top:
		dh.tooltip_text = Lang.t("Ajoutez un étage au-dessus (onglet Étages)", "Add a floor above (Floors tab)")
	var poly := ed.doc.room_poly(r)
	var bb := MapGeom.bbox(poly)
	_note(_props, Lang.t("Étage %d · %s × %s m · %s m²\nMurs générés sur le contour ; un bord commun avec une pièce collée = un seul mur.",
		"Floor %d · %s × %s m · %s m²\nWalls follow the outline; an edge shared with a touching room = a single wall.") % [k, _m(bb.size.x), _m(bb.size.y), _m(snappedf(MapGeom.area(poly), 0.5))])


func _opening_props(o: Dictionary) -> void:
	var t := String(o.type)
	var it := MapCatalog.item_for(o)
	_title(_props, MapCatalog.name_of(it))
	var k := int(o.get("etage", 0))
	if t != "fenetre":
		var types := ["porte", "debris", "porte_courant", "passage"]
		var names := types.map(func(x): return MapCatalog.name_of(MapCatalog.item(x)))
		_option(_props, Lang.t("Type", "Type"), names, types.find(t), func(i):
			ed.push_undo()
			o["type"] = types[i]
			if types[i] in ["porte", "debris"] and not o.has("prix"):
				o["prix"] = ed.default_door_price()
			if not types[i] in ["porte", "debris"]:
				o.erase("prix")
			ed.changed())
		if t in ["porte", "debris"]:
			_spin(_props, Lang.t("Prix", "Price"), float(o.get("prix", 750)), 0, 20000, 250, func(v): o["prix"] = int(v), "")
		var w := _spin(_props, Lang.t("Largeur", "Width"), MapRules.opening_width(o), 1.0, 6.0, 0.5, func(v):
			var res := MapRules.place_opening(ed.doc, k, t, MapGeom.v2(o.position), v, String(o.id))
			if res.ok:
				o["largeur"] = v
				o["position"] = res.position
			else:
				ed.canvas.show_refusal(res))
		w.tooltip_text = Lang.t("BO1 : 1,5 à 3 m", "BO1: 1.5 to 3 m")
	var res := MapRules.place_opening(ed.doc, k, t, MapGeom.v2(o.position), MapRules.opening_width(o), String(o.id))
	if res.ok:
		var rn: Array = res.rooms.map(func(rid): return String(ed.doc.find(rid).get("nom", rid)))
		_note(_props, (Lang.t("Relie : %s", "Links: %s") % " ↔ ".join(rn)) if t != "fenetre" else (Lang.t("Mur extérieur de « %s » ; les zombies arrivent de dehors", "Outer wall of \"%s\"; zombies come from outside") % rn[0]))
	var p := MapGeom.v2(o.position)
	_note(_props, Lang.t("Position : x %s m, y %s m, étage %d", "Position: x %s m, y %s m, floor %d") % [_m(p.x), _m(p.y), k])


func _object_props(o: Dictionary) -> void:
	var t := String(o.type)
	var it := MapCatalog.item_for(o)
	_title(_props, MapCatalog.name_of(it))
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
		"boite":
			_check(_props, Lang.t("Départ de la boîte (un seul)", "Box start (only one)"), bool(o.get("depart", false)), func(on):
				if on:
					for q in ed.doc.objets:
						if String(q.get("type", "")) == "boite":
							q["depart"] = false
				o["depart"] = on)
		"escalier":
			var dirs := ["n", "e", "s", "o"]
			_option(_props, Lang.t("Monte vers", "Goes up to"), dirs.map(func(d): return Lang.t(DIR_NAMES[d][0], DIR_NAMES[d][1])), dirs.find(String(o.get("monte", "n"))), func(i):
				ed.push_undo()
				o["monte"] = dirs[i]
				ed.changed())
			_note(_props, Lang.t("Relie l'étage %d à l'étage %d. Le haut arrive sur le plancher d'une pièce de l'étage du dessus ; le vide au-dessus des marches est automatique.",
				"Links floor %d to floor %d. The top lands on a room floor of the floor above; the opening above the steps is automatic.") % [int(o.etage), int(o.etage) + 1])
		"mur":
			var th := [0.5, 1.5, 2.5]
			_option(_props, Lang.t("Épaisseur", "Thickness"), th.map(func(v): return _m(v) + " m"), maxi(0, th.find(float(o.get("epaisseur", 0.5)))), func(i):
				ed.push_undo()
				o["epaisseur"] = th[i]
				ed.changed())
	var price := int(it.get("price", 0))
	if t == "atout":
		price = PerkDB.cost(String(o.atout), false)
	if price > 0:
		_note(_props, Lang.t("Prix en jeu : %d points", "In-game price: %d points") % price)
	var hint := Lang.t(String(it.get("hint_fr", "")), String(it.get("hint_en", "")))
	if hint != "":
		_note(_props, hint)
	var r := MapRules.footprint_rect(o)
	_note(_props, Lang.t("Position : x %s m, y %s m, étage %d", "Position: x %s m, y %s m, floor %d") % [_m(r.get_center().x), _m(r.get_center().y), int(o.get("etage", 0))])


# ------------------------------------------------------------------ listes

func _fill_rooms() -> void:
	_rooms.clear()
	_room_ids.clear()
	var list := ed.doc.pieces.duplicate()
	list.sort_custom(func(a, b): return [int(a.etage), String(a.get("nom", ""))] < [int(b.etage), String(b.get("nom", ""))])
	for p in list:
		var poly := ed.doc.room_poly(p)
		_rooms.add_item(Lang.t("É%d · %s — %s (%s m²)", "F%d · %s — %s (%s m²)") % [int(p.etage), p.get("nom", ""), ed.doc.zone_name(String(p.get("zone", ""))), _m(snappedf(MapGeom.area(poly), 0.5))])
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
	var mats := [Lang.t("(par défaut)", "(default)")] + MapCatalog.materials()
	_option(_zone_form, Lang.t("Sol", "Floor"), mats, maxi(0, mats.find(String(z.get("sol", "")))), func(i):
		ed.push_undo()
		if i == 0:
			z.erase("sol")
		else:
			z["sol"] = mats[i]
		ed.changed(false))
	_option(_zone_form, Lang.t("Murs", "Walls"), mats, maxi(0, mats.find(String(z.get("murs", "")))), func(i):
		ed.push_undo()
		if i == 0:
			z.erase("murs")
		else:
			z["murs"] = mats[i]
		ed.changed(false))
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


func _fill_floors() -> void:
	_floors.clear()
	for k in ed.doc.floor_count():
		_floors.add_item(Lang.t("Étage %d — sol %s m, plafond %s m (%d pièce(s))", "Floor %d — floor %s m, ceiling %s m (%d room(s))") % [
			k, _m(ed.doc.floor_sol(k)), _m(ed.doc.floor_height(k)), ed.doc.rooms_on(k).size()])
	_floors.select(ed.floor_k)
	_clear(_floor_form)
	var k := ed.floor_k
	var f: Dictionary = ed.doc.floors()[k]
	_title(_floor_form, Lang.t("Étage %d", "Floor %d") % k)
	_spin(_floor_form, Lang.t("Hauteur du sol", "Floor level"), float(f.get("sol", 0.0)), -20.0, 200.0, 0.1, func(v): f["sol"] = v)
	_spin(_floor_form, Lang.t("Plafond", "Ceiling"), float(f.get("hauteur", EditorMap.DEFAULT_CEILING)), 2.8, 10.0, 0.1, func(v): f["hauteur"] = v)
	_note(_floor_form, Lang.t("Plafond des pièces sans rien au-dessus ; sous un étage, le plafond est sa dalle (3,1 m au moins entre deux sols).",
		"Ceiling of rooms with nothing above; under a floor, the ceiling is its slab (at least 3.1 m between two floors)."))
	_button(_floor_form, Lang.t("+ Ajouter un étage au-dessus", "+ Add a floor above"), ed.add_floor)
	var rm := _button(_floor_form, Lang.t("Supprimer le dernier étage (vide)", "Delete the top floor (empty)"), ed.remove_top_floor)
	rm.disabled = ed.doc.floor_count() <= 1
	var gh := CheckBox.new()
	gh.text = Lang.t("Afficher l'étage du dessous en transparence", "Show the floor below, see-through")
	gh.button_pressed = ed.ghost_below
	gh.toggled.connect(func(on):
		ed.ghost_below = on
		ed.canvas.queue_redraw())
	_floor_form.add_child(gh)


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
