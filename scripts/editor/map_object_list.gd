class_name MapObjectList
extends HBoxContainer
## Onglet déployable « Objets sur la carte » de l'éditeur (à gauche de la vue,
## touche L) : tous les éléments posés (pièces, ouvertures, objets, décor,
## luminaires) avec icône, nom, type, étage et position en mètres, triés par
## identifiant, filtrés par catégorie et par texte, PAGINÉS PAR 50.
##   - survol d'une ligne : l'élément est entouré sur la carte (la vue ne bouge
##     pas) ; survol d'un élément sur la carte : sa ligne est surlignée et la
##     liste saute à sa page ;
##   - clic : choisir et centrer ; double-clic : centrer et zoomer.
## Performance : la liste n'est refaite qu'après une modification de la carte
## (mark_dirty), et seulement si l'onglet est ouvert ; les 50 lignes de la page
## sont dessinées par un seul contrôle (Rows), jamais recréées au survol.
## Ouvert / replié : mémorisé (MapEditor.pref « liste_objets »).

const PER_PAGE := 50
const ROW_H := 26.0
const WIDTH := 340.0
## Filtres : [id, FR, EN].
const FILTERS := [
	["tout", "Tout", "All"],
	["pieces", "Pièces", "Rooms"],
	["ouvertures", "Ouvertures", "Openings"],
	["construction", "Construction", "Building"],
	["jeu", "Objets de jeu", "Game objects"],
	["prefabs", "Décor et obstacles", "Props and obstacles"],
	["lumieres", "Luminaires", "Light fixtures"],
]
## Catégorie du catalogue -> filtre.
const CAT_FILTER := {"construction": "construction", "ouvertures": "ouvertures", "atouts": "jeu", "armes": "jeu", "boite": "jeu",
	"machines": "jeu", "pieges": "jeu", "joueurs": "jeu", "prefabs": "prefabs", "lumieres": "lumieres"}

var ed: MapEditor
var expanded := false
var page := 0
var filter := "tout"
var search := ""
## Tous les éléments de la carte, triés par identifiant : [{id, filter, name,
## type, floor, pos, item, text}].
var entries: Array = []
## Éléments retenus par le filtre et la recherche (même ordre).
var shown: Array = []
## Élément surligné (survol sur la carte ou dans la liste).
var hover_id := ""
## Nombre de reconstructions de la liste (tests : jamais à chaque image).
var rebuild_count := 0
var _dirty := true
var _index_of: Dictionary = {}   # id -> index dans `shown`

var _handle: Handle
var _panel: PanelContainer
var _scroll: ScrollContainer
var rows: Rows
var _page_label: Label
var _count_label: Label
var _prev: Button
var _next: Button
var _search_edit: LineEdit
var _filter_opt: OptionButton


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_handle = Handle.new()
	_handle.list = self
	add_child(_handle)
	_panel = PanelContainer.new()
	# Largeur donnée par l'éditeur (fit_width : taille de l'interface, bornée).
	_panel.set_meta(EditorUi.KEEP_MIN, true)
	_panel.custom_minimum_size = Vector2(EditorUi.px(WIDTH), 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiStyle.label(Lang.t("OBJETS SUR LA CARTE", "ITEMS ON MAP"), 16, UiStyle.GOLD, "impact")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "◂"
	close.tooltip_text = Lang.t("Replier la liste (L)", "Collapse the list (L)")
	close.pressed.connect(toggle)
	head.add_child(close)
	var fh := HBoxContainer.new()
	v.add_child(fh)
	_filter_opt = OptionButton.new()
	for f in FILTERS:
		_filter_opt.add_item(Lang.t(String(f[1]), String(f[2])))
	_filter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_opt.item_selected.connect(func(i): set_filter(String(FILTERS[i][0])))
	fh.add_child(_filter_opt)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = Lang.t("Rechercher…", "Search…")
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(set_search)
	fh.add_child(_search_edit)
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", UiStyle.DIM)
	_count_label.add_theme_font_size_override("font_size", 12)
	v.add_child(_count_label)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	rows = Rows.new()
	rows.list = self
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(foot)
	_prev = Button.new()
	_prev.text = "◄"
	_prev.tooltip_text = Lang.t("Page précédente", "Previous page")
	_prev.pressed.connect(func(): set_page(page - 1))
	foot.add_child(_prev)
	_page_label = Label.new()
	_page_label.custom_minimum_size = Vector2(110, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(_page_label)
	_next = Button.new()
	_next.text = "►"
	_next.tooltip_text = Lang.t("Page suivante", "Next page")
	_next.pressed.connect(func(): set_page(page + 1))
	foot.add_child(_next)
	var hint := Label.new()
	hint.text = Lang.t("Survol : l'objet s'allume sur la carte · clic : le choisir · double-clic : zoomer",
		"Hover: the item lights up on the map · click: pick it · double-click: zoom")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	hint.add_theme_font_size_override("font_size", 11)
	v.add_child(hint)
	filter = String(MapEditor.pref("liste_filtre", "tout"))
	var fi := FILTERS.map(func(f): return f[0]).find(filter)
	if fi < 0:
		filter = "tout"
		fi = 0
	_filter_opt.selected = fi
	set_expanded(bool(MapEditor.pref("liste_objets", false)), false)


# ------------------------------------------------------------------ ouvrir / replier

func toggle() -> void:
	set_expanded(not expanded)


func set_expanded(on: bool, remember := true) -> void:
	expanded = on
	_panel.visible = on
	_handle.queue_redraw()
	if remember:
		MapEditor.set_pref("liste_objets", on)
	if on:
		_ensure_built()
	elif ed != null:
		ed.list_hovered("")


# ------------------------------------------------------------------ données

## La carte a changé : la liste sera refaite (tout de suite si l'onglet est
## ouvert, sinon à sa prochaine ouverture).
func mark_dirty() -> void:
	_dirty = true
	if expanded:
		_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	if _dirty and expanded:
		_ensure_built()


func _ensure_built() -> void:
	if ed == null or ed.doc == null:
		return
	if _dirty:
		rebuild()
	else:
		refresh_rows()


## Refait la liste des éléments (après une modification de la carte).
func rebuild() -> void:
	_dirty = false
	rebuild_count += 1
	entries = build_entries(ed.doc)
	_apply_filter(false)


## Éléments de la carte `doc` pour la liste, triés par identifiant (ordre
## naturel : p2 avant p10) : [{id, filter, name, type, floor, pos, item, text}].
static func build_entries(doc: EditorMap) -> Array:
	var out := []
	var cat_names := {}
	for c in MapCatalog.CATEGORIES:
		cat_names[String(c[0])] = Lang.t(String(c[1]), String(c[2]))
	for p in doc.pieces:
		var poly := doc.room_poly(p)
		var shape := String(p.get("forme", {}).get("type", "")) if p.get("forme") is Dictionary else ""
		var it := MapCatalog.item(("piece_" + shape) if shape != "" and not MapCatalog.item("piece_" + shape).is_empty()
			else ("piece_rect" if MapGeom.is_axis_rect(poly) else "piece_poly"))
		out.append({"id": String(p.id), "filter": "pieces", "name": String(p.get("nom", p.id)), "type": Lang.t("Pièce", "Room"),
			"floor": int(p.get("etage", 0)), "pos": MapGeom.bbox(poly).get_center(), "item": it})
	for o in doc.ouvertures:
		var it := MapCatalog.item_for(o)
		var nm := MapCatalog.name_of(it)
		if o.has("prix"):
			nm += " (%d)" % int(o.prix)
		out.append({"id": String(o.id), "filter": "ouvertures", "name": nm, "type": String(cat_names.get("ouvertures", "")),
			"floor": int(o.get("etage", 0)), "pos": MapGeom.v2(o.get("position", [0, 0])), "item": it})
	for o in doc.objets:
		var it := MapCatalog.item_for(o)
		var cat := String(it.get("cat", "construction"))
		var pos := (MapGeom.v2(o.a) + MapGeom.v2(o.b)) * 0.5 if String(o.get("type", "")) == "mur" else MapRules.footprint_rect(o).get_center()
		out.append({"id": String(o.id), "filter": String(CAT_FILTER.get(cat, "jeu")), "name": MapCatalog.name_of(it) if not it.is_empty() else String(o.get("type", "?")),
			"type": String(cat_names.get(cat, "")), "floor": int(o.get("etage", 0)), "pos": pos, "item": it})
	for e in out:
		e["text"] = ("%s %s %s" % [e.name, e.type, e.id]).to_lower()
	out.sort_custom(func(a, b): return String(a.id).naturalnocasecmp_to(String(b.id)) < 0)
	return out


## Pagination de `total` éléments par `per` : {pages (1 au moins), page
## (bornée), from, to (exclu)}.
static func paginate(total: int, p: int, per := PER_PAGE) -> Dictionary:
	var pages := maxi(1, ceili(float(total) / per))
	var pg := clampi(p, 0, pages - 1)
	return {"pages": pages, "page": pg, "from": pg * per, "to": mini(total, (pg + 1) * per)}


## Page (0 = première) de l'élément d'index `i` de la liste.
static func page_of(i: int, per := PER_PAGE) -> int:
	return maxi(0, i) / per


func set_filter(f: String) -> void:
	filter = f
	MapEditor.set_pref("liste_filtre", f)
	_apply_filter(true)


func set_search(t: String) -> void:
	search = t.strip_edges().to_lower()
	_apply_filter(true)


func _apply_filter(reset_page: bool) -> void:
	shown = entries.filter(func(e): return (filter == "tout" or e.filter == filter) and (search == "" or String(e.text).contains(search)))
	_index_of.clear()
	for i in shown.size():
		_index_of[String(shown[i].id)] = i
	if reset_page:
		page = 0
	set_page(page)


func set_page(p: int) -> void:
	var pg := paginate(shown.size(), p)
	page = pg.page
	_page_label.text = Lang.t("page %d/%d", "page %d/%d") % [page + 1, pg.pages]
	_prev.disabled = page <= 0
	_next.disabled = page >= pg.pages - 1
	_count_label.text = Lang.t("%d élément(s) sur %d · 50 par page", "%d item(s) of %d · 50 per page") % [shown.size(), entries.size()]
	refresh_rows()


## Hauteur d'une ligne à la taille de l'interface (EditorUi).
static func row_h() -> float:
	return EditorUi.px(ROW_H)


## Largeur de la liste dépliée (MapEditor.side_width).
func fit_width(w: float) -> void:
	if _panel != null:
		_panel.custom_minimum_size = Vector2(w, 0)


## Taille de l'interface changée : lignes et languette redessinées.
func ui_scale_changed() -> void:
	refresh_rows()
	if _handle != null:
		_handle.queue_redraw()


## Lignes de la page courante : [entrée].
func page_rows() -> Array:
	var pg := paginate(shown.size(), page)
	return shown.slice(pg.from, pg.to)


func refresh_rows() -> void:
	if rows == null:
		return
	var items := page_rows()
	if items != rows.items:
		# Autre page : l'ancienne ligne survolée ne veut plus rien dire.
		rows._hover_row = -1
	rows.items = items
	rows.custom_minimum_size = Vector2(0, rows.items.size() * row_h())
	rows.queue_redraw()


## Survol d'un élément sur la carte : sa ligne est surlignée, la liste va à
## sa page et la fait défiler jusqu'à elle.
func show_hover(eid: String) -> void:
	hover_id = eid
	if not expanded:
		return
	if _dirty:
		rebuild()
	if _index_of.has(eid):
		var i: int = _index_of[eid]
		var pg := page_of(i)
		if pg != page:
			set_page(pg)
		var y := (i - pg * PER_PAGE) * row_h()
		if y < _scroll.scroll_vertical or y + row_h() > _scroll.scroll_vertical + _scroll.size.y:
			_scroll.scroll_vertical = int(maxf(0.0, y - _scroll.size.y * 0.4))
	rows.queue_redraw()


## Ligne de la page courante qui montre l'élément `eid` (-1 : aucune).
func row_of(eid: String) -> int:
	if not _index_of.has(eid):
		return -1
	var i: int = _index_of[eid]
	return i - page * PER_PAGE if page_of(i) == page else -1


# ------------------------------------------------------------------ onglet replié

## Languette verticale au bord gauche de la vue : un clic ouvre / replie.
class Handle extends Control:
	var list: MapObjectList

	func _init() -> void:
		custom_minimum_size = Vector2(22, 0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = Lang.t("Objets sur la carte (L) : cliquer pour ouvrir ou replier", "Items on map (L): click to open or collapse")

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.13, 0.1) if list.expanded else Color(0.12, 0.12, 0.13))
		draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), Color(0.5, 0.4, 0.25), 1.0)
		var font := UiStyle.font("impact")
		var txt := ("◂  " if list.expanded else "▸  ") + Lang.t("OBJETS SUR LA CARTE", "ITEMS ON MAP")
		# Texte vertical, de haut en bas : ligne de base à gauche, lettres vers la droite.
		draw_set_transform(Vector2(EditorUi.px(6.0), EditorUi.px(12.0)), PI / 2, Vector2.ONE)
		draw_string(font, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(14), UiStyle.GOLD)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			list.toggle()
			accept_event()


# ------------------------------------------------------------------ lignes

## Les lignes de la page (50 au plus), dessinées par ce seul contrôle.
class Rows extends Control:
	var list: MapObjectList
	var items: Array = []
	var _hover_row := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Hauteur déjà calculée à la taille de l'interface (row_h).
		set_meta(EditorUi.SKIP, true)
		mouse_exited.connect(func():
			_hover_row = -1
			list.ed.list_hovered("")
			queue_redraw())

	func _draw() -> void:
		var font := UiStyle.font("body")
		var sel := list.ed.selected
		# Lignes dessinées à la taille de l'interface (EditorUi).
		var rh := MapObjectList.row_h()
		var f13 := EditorUi.fs(13)
		var f11 := EditorUi.fs(11)
		var f10 := EditorUi.fs(10)
		for i in items.size():
			var e: Dictionary = items[i]
			var r := Rect2(0, i * rh, size.x, rh)
			var eid := String(e.id)
			if eid == list.hover_id or i == _hover_row:
				draw_rect(r, Color(0.2, 0.55, 0.65, 0.45))
				draw_rect(r, Color(0.35, 0.9, 1.0, 0.9), false, 1.0)
			elif eid == sel:
				draw_rect(r, Color(0.45, 0.35, 0.1, 0.5))
			elif i % 2 == 1:
				draw_rect(r, Color(1, 1, 1, 0.03))
			var m3: float = EditorUi.px(3.0)
			MapIcons.draw(self, e.item, Rect2(r.position + Vector2(m3, m3), Vector2(rh - 2.0 * m3, rh - 2.0 * m3)))
			var fr := not Lang.is_en()
			var p: Vector2 = e.pos
			var where := "%s%d · %s ; %s m" % [Lang.t("É", "F"), int(e.floor), MapRules._m(snappedf(p.x, 0.25), fr), MapRules._m(snappedf(p.y, 0.25), fr)]
			var x0: float = rh + EditorUi.px(4.0)
			var wwhere := font.get_string_size(where, HORIZONTAL_ALIGNMENT_LEFT, -1, f11).x
			var y1: float = r.position.y + EditorUi.px(12.0)
			draw_string(font, Vector2(x0, y1), String(e.name), HORIZONTAL_ALIGNMENT_LEFT, size.x - x0 - wwhere - EditorUi.px(10.0), f13, Color(0.92, 0.9, 0.84))
			draw_string(font, Vector2(x0, r.position.y + EditorUi.px(23.0)), "%s · %s" % [e.type, eid], HORIZONTAL_ALIGNMENT_LEFT, size.x - x0 - EditorUi.px(6.0), f10, Color(0.62, 0.62, 0.6))
			draw_string(font, Vector2(size.x - wwhere - EditorUi.px(6.0), y1), where, HORIZONTAL_ALIGNMENT_LEFT, -1, f11, Color(0.7, 0.75, 0.8))

	func _row_at(y: float) -> int:
		var i := int(y / MapObjectList.row_h())
		return i if i >= 0 and i < items.size() else -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var i := _row_at(event.position.y)
			if i != _hover_row:
				_hover_row = i
				var eid := String(items[i].id) if i >= 0 else ""
				list.hover_id = eid
				list.ed.list_hovered(eid)
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _row_at(event.position.y)
			if i < 0:
				return
			var eid := String(items[i].id)
			if event.double_click:
				list.ed.zoom_to_element(eid)
			else:
				list.ed.focus_element(eid)
			accept_event()
