class_name Hub2ArsenalPanel
extends Hub2Panel
## ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html, à suivre à 100 %) :
##   - en-tête : sous-onglets ARMES / PIÈCES (Chakra Petch 22 px, nombre en
##     JetBrains Mono 13 px, soulignement jaune 2 px), filtres TOUTES / À FEU /
##     MÊLÉE / UTILISABLES (pièces : TOUTES / MONTABLES ; Y / Tab : cycle,
##     clic) ;
##   - panneau de verre : RAIL HORIZONTAL DES NIVEAUX (Hub2ArsenalRail) :
##     une colonne par niveau (5 visibles à 100 %), « NIV. N » et « ×n »,
##     losange sur un filet, armes d'un même niveau empilées (rareté puis
##     score) ; ◄ ► : niveau voisin, ▲ ▼ : même niveau ; flèches ‹ › ; vue
##     d'ensemble en bas (tous les niveaux, fenêtre visible surlignée, niveau
##     choisi en jaune, clic : saut) ;
##   - FICHE à droite (384 px) : rareté · classe, nom 36 px, niveau, rendu de
##     l'arme et SCORE, six statistiques en icônes (valeur de BASE +
##     modificateur des pièces vert / rouge, sans unité), fiche complète
##     repliable « DÉTAILS ▾ » (Hub2WeaponDetails ; D / R3, clic ; état
##     retenu pour la session ; la fiche défile, aussi au stick droit), PIÈCES n / m
##     (installées ou « Emplacement libre — A : installer une pièce »).
## Actions (logique de l'ancien hub : arsenal_panel, weapon_sheet, parts_panel,
## part_picker) : A sur une carte -> emplacements de la fiche ; A sur un
## emplacement libre -> fenêtre des pièces (Hub2PartPicker, aperçu avant /
## après) ; X / Suppr sur une pièce installée : RETIRER en deux appuis (la
## pièce est détruite) ; X / Suppr sur une carte : RECYCLER en deux appuis
## (jamais une arme de base, rien n'est rendu). Onglet PIÈCES : même rail par
## niveau pour les pièces non installées, fiche = effets + armes compatibles
## avec l'aperçu ; A sur une arme compatible -> fenêtre des pièces, la pièce
## déjà choisie.
## Chaque action modifie le profil puis l'enregistre une fois
## (hub.save_profile) ; les pastilles NEUF vues restent jusqu'au départ de
## l'écran et sont enregistrées « vues » au départ.

const WEAPONS := "weapons"
const PARTS := "parts"

## Mesures de la maquette (px à 100 %).
const GAP_MAIN := 20.0
const ASIDE_W := 384.0
const HEADER_H := 34.0
const ARROW_W := 36.0
const RAIL_PAD := 6.0
const COL_GAP := 14.0
## Largeur d'une colonne à 100 % ((818 − 72 − 12 − 4 × 14) / 5 ≈ 135,6).
const COL_W := 135.0
const COL_HEAD_H := 48.0
const NODE_H := 14.0
const LINE_Y := 56.0
const CARD_GAP := 10.0
const STRIP_H := 58.0
## Écran de la fiche complète (état ouvert / fermé retenu pour la session).
const DETAILS_SCREEN := "arsenal"

var tab := WEAPONS
var filter := "all"
var part_filter := "all"
var rail := Hub2ArsenalRail.new()
var selected_uid := ""
var selected_part_uid := ""

var main_row: HBoxContainer
var header: VBoxContainer
var header_row: HBoxContainer
var header_row2: HBoxContainer
var tab_buttons: Dictionary = {}  # WEAPONS / PARTS -> Hub2Button
var chips: Array = []  # Hub2Button
var chips_box: HBoxContainer
var prev_button: Hub2Button
var next_button: Hub2Button
var rail_area: Control
var columns_box: HBoxContainer
var overview: Control
var aside: Hub2Box
var aside_scroll: ScrollContainer
var aside_col: VBoxContainer
## Cartes affichées (Hub2ArsenalCard).
var cards: Array = []
## Têtes de colonne affichées (pour la couleur du niveau choisi).
var col_heads: Array = []
## Emplacements de la fiche (Hub2Button ; meta "slot" = index, "installed").
var slots: Array = []
## Armes compatibles de la fiche d'une pièce (Hub2Button ; meta "uid").
var compat_rows: Array = []
var picker: Hub2PartPicker
## Double appui en cours : "" , "recycle", "remove".
var armed := ""
var armed_slot := -1
## Libellés lus par les tests.
var name_text: String = ""
var stat_cells: Array = []
## Fiche complète de l'arme choisie (null : pièce ou rien de choisi).
var details: Hub2WeaponDetails

var _seen_now: Dictionary = {}
var _pending_seen := false
var _visible_cols := Hub2ArsenalRail.VISIBLE
var _rebuilding := false


# --------------------------------------------------------------------------
# Contrat Hub2Panel
# --------------------------------------------------------------------------

func build() -> void:
	main_row = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", int(Hub2Style.px(GAP_MAIN)))
	main_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_main(main_row)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_row.add_child(section)
	section.add_child(_build_header())
	section.add_child(_build_rail_box())
	aside = Hub2Box.new()
	aside.glass(Hub2Style.GLASS_STRONG)
	# width: 384px + liseré 1 px de chaque côté (content-box).
	aside.custom_minimum_size.x = Hub2Style.px(ASIDE_W) + Hub2Style.px(1) * 2.0
	aside.pad(1)
	main_row.add_child(aside)
	# La fiche entière défile si elle ne tient pas (130 %) ; à 100 % seule la
	# liste des pièces défile (elle remplit le reste de la hauteur).
	var wrap := VBoxContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aside.add_child(wrap)
	aside_scroll = ScrollContainer.new()
	aside_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	aside_scroll.follow_focus = true
	aside_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(aside_scroll)
	scroll_mark(aside_scroll, wrap, -Hub2Style.px(6))
	aside_col = VBoxContainer.new()
	aside_col.add_theme_constant_override("separation", 0)
	aside_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aside_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aside_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aside_scroll.add_child(aside_col)
	resized.connect(_on_resized)
	if not Settings.input_device_changed.is_connected(_on_device):
		Settings.input_device_changed.connect(_on_device)
	_reload(true)


func _exit_tree() -> void:
	if Settings.input_device_changed.is_connected(_on_device):
		Settings.input_device_changed.disconnect(_on_device)


func refresh() -> void:
	if main_row == null:
		return
	var fk := _focus_key()
	_reload(false)
	_restore_focus(fk)


func shown() -> void:
	_mark_seen()


func hidden() -> void:
	close_picker()
	_disarm()
	_seen_now.clear()
	if _pending_seen:
		_pending_seen = false
		hub.call("save_profile")


func first_focus() -> Control:
	if picker:
		return picker.rows[picker.selected] if picker.selected >= 0 else picker.cancel_button
	var c := selected_card()
	if c:
		return c
	return tab_buttons.get(tab)


## Invites de l'écran ; fiche d'une arme : DÉTAILS / MASQUER (D / R3) avant
## RETOUR (sauf fenêtre des pièces et confirmation en cours).
func prompts() -> Array:
	var list := _prompts()
	if picker == null and armed == "" and details != null and details.visible and not list.is_empty():
		list.insert(list.size() - 1, [Hub2Input.DETAILS, Hub2WeaponDetails.prompt_text(details.open)])
	return list


func _prompts() -> Array:
	var back_t := Lang.t("Retour", "Back")
	if picker:
		return [[Hub2Input.ACCEPT, Lang.t("Installer", "Install")], [Hub2Input.BACK, Lang.t("Annuler", "Cancel")]]
	if armed != "":
		return [[Hub2Input.SECONDARY, Lang.t("Confirmer", "Confirm")], [Hub2Input.BACK, Lang.t("Annuler", "Cancel")]]
	var f := _focus_owner()
	if f != null and f in slots:
		if bool(f.get_meta("installed", false)):
			return [[Hub2Input.SECONDARY, Lang.t("Retirer", "Remove")], [Hub2Input.BACK, back_t]]
		return [[Hub2Input.ACCEPT, Lang.t("Installer", "Install")], [Hub2Input.BACK, back_t]]
	if f != null and f in compat_rows:
		return [[Hub2Input.ACCEPT, Lang.t("Installer", "Install")], [Hub2Input.BACK, back_t]]
	if tab == PARTS:
		return [[Hub2Input.ACCEPT, Lang.t("Installer", "Install")], [Hub2Input.FILTER, Lang.t("Filtrer", "Filter")],
			[Hub2Input.BACK, back_t]]
	return [[Hub2Input.ACCEPT, Lang.t("Installer", "Install")], [Hub2Input.SECONDARY, Lang.t("Recycler", "Recycle")],
		[Hub2Input.FILTER, Lang.t("Filtrer", "Filter")], [Hub2Input.BACK, back_t]]


func help() -> String:
	if tab == PARTS:
		return Lang.t("◄ ► change de niveau · ▲ ▼ parcourt les pièces d’un même niveau",
				"◄ ► changes level · ▲ ▼ browses the parts of one level")
	return Lang.t("◄ ► change de niveau · ▲ ▼ parcourt les armes d’un même niveau",
			"◄ ► changes level · ▲ ▼ browses the weapons of one level")


func back() -> bool:
	if picker:
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		close_picker()
		return true
	if armed != "":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		_disarm()
		return true
	var f := _focus_owner()
	if f != null and is_ancestor_of(f) and not (f is Hub2ArsenalCard):
		var c := selected_card()
		if c:
			Audio.play_ui(MenuStyle.SND_BACK, -4.0)
			c.grab_focus()
			return true
	return false


func handle_input(event: InputEvent) -> bool:
	if picker:
		return false
	if _pad_pressed(event, JOY_BUTTON_Y):
		cycle_filter()
		return true
	if _pad_pressed(event, JOY_BUTTON_X) or Hub2Input.is_key(event, KEY_DELETE):
		secondary()
		return true
	if Hub2Input.is_details(event) and toggle_details():
		return true
	return false


## DÉTAILS ▾ / MASQUER ▴ de la fiche d'une arme (D, R3, invite, clic sur le
## titre) ; faux s'il n'y a pas de fiche d'arme.
func toggle_details() -> bool:
	if details == null or not details.visible:
		return false
	details.toggle()
	return true


## Fiche plus haute que le panneau (fiche complète ouverte) : elle défile au
## stick droit, comme à la molette.
func _process(delta: float) -> void:
	if visible and picker == null:
		Hub2ItemsUi.pad_scroll(aside_scroll, delta)


## Tab : filtre suivant (Tab ferait sinon passer le focus au contrôle suivant).
func _input(event: InputEvent) -> void:
	if not visible or picker or hub == null or not hub.call("_active") or hub.get("hub_menu").is_open():
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_TAB and not k.ctrl_pressed and not k.alt_pressed:
		get_viewport().set_input_as_handled()
		cycle_filter()


func on_prompt(id: String) -> void:
	match id:
		Hub2Input.FILTER:
			cycle_filter()
		Hub2Input.SECONDARY:
			secondary()
		Hub2Input.DETAILS:
			toggle_details()


func badge() -> bool:
	var pr := profile()
	if pr == null:
		return false
	for w in pr.weapons:
		if pr.is_new_weapon(w.uid):
			return true
	for p in pr.parts:
		if pr.is_new_part(p.uid):
			return true
	return false


# --------------------------------------------------------------------------
# En-tête : sous-onglets et filtres
# --------------------------------------------------------------------------

func _build_header() -> Control:
	# Une ligne (maquette) ; à 130 % les filtres passent sur une deuxième
	# ligne, alignés à droite, s'ils ne tiennent plus (_fit_header).
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = Hub2Style.px(HEADER_H)
	row.add_theme_constant_override("separation", int(Hub2Style.px(28)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(row)
	header_row = row
	header_row2 = HBoxContainer.new()
	header_row2.alignment = BoxContainer.ALIGNMENT_END
	header_row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row2.visible = false
	header.add_child(header_row2)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(Hub2Style.px(22)))
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tabs)
	for id in [WEAPONS, PARTS]:
		var b := Hub2Button.new()
		b.custom_minimum_size.y = Hub2Style.px(HEADER_H)
		var face := TabFace.new()
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_content(face)
		b.set_meta("face", face)
		var tid: String = id
		b.pressed.connect(func(): set_tab(tid))
		b.hint = Lang.t("Les armes de l’arsenal, rangées par niveau.", "The arsenal weapons, by level.") if id == WEAPONS \
				else Lang.t("Les pièces en stock (non installées), rangées par niveau.", "Parts in stock (not mounted), by level.")
		tabs.add_child(b)
		tab_buttons[id] = b
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spring)
	chips_box = HBoxContainer.new()
	chips_box.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	chips_box.alignment = BoxContainer.ALIGNMENT_END
	chips_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chips_box)
	return header


## Filtres sur la ligne des sous-onglets s'ils tiennent, sinon dessous.
func _fit_header() -> void:
	var tabs_w := 0.0
	for id in tab_buttons:
		tabs_w += (tab_buttons[id] as Control).get_combined_minimum_size().x
	tabs_w += Hub2Style.px(22) * float(tab_buttons.size() - 1)
	var need := tabs_w + Hub2Style.px(28) + chips_box.get_combined_minimum_size().x
	var two := need > _section_width() + 0.5
	var parent := chips_box.get_parent()
	var want: Node = header_row2 if two else header_row
	if parent != want:
		parent.remove_child(chips_box)
		want.add_child(chips_box)
	header_row2.visible = two
	header_row2.custom_minimum_size.y = Hub2Style.px(30) if two else 0.0


func _fill_header() -> void:
	var pr := profile()
	var counts := {WEAPONS: BaseWeapons.ids().size() + (pr.weapons.size() if pr else 0), PARTS: pr.parts.size() if pr else 0}
	var names := {WEAPONS: Lang.t("ARMES", "WEAPONS"), PARTS: Lang.t("PIÈCES", "PARTS")}
	for id in tab_buttons:
		var face: TabFace = (tab_buttons[id] as Hub2Button).get_meta("face")
		face.label = names[id]
		face.count = str(counts[id])
		face.on = id == tab
		var b: Hub2Button = tab_buttons[id]
		b.custom_minimum_size.x = face.content_width()
		face.queue_redraw()
	for c in chips:
		chips_box.remove_child(c)
		c.queue_free()
	chips.clear()
	var list: Array = Hub2ArsenalView.PART_FILTERS if tab == PARTS else Hub2ArsenalView.FILTERS
	var cur := part_filter if tab == PARTS else filter
	for f in list:
		var on: bool = f == cur
		var b := Hub2Button.new()
		b.box.flat(Hub2Style.TEXT if on else Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.5),
				Hub2Style.TEXT if on else Hub2Style.white_a(0.14), 1.0)
		b.custom_minimum_size.y = Hub2Style.px(30)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.box.pad(0, 12)
		var t := Hub2Text.new()
		t.setup(Hub2ArsenalView.filter_name(f, tab == PARTS), Hub2Style.CHAKRA, 600, 13,
				Hub2Style.INK if on else Hub2Style.text_a(0.75), 0.1)
		b.add_content(t)
		var fid: String = f
		b.pressed.connect(func(): set_filter(fid))
		b.hint = Lang.t("Filtre (%s : suivant).", "Filter (%s: next).") % key_name(Hub2Input.FILTER)
		b.set_meta("filter", f)
		chips_box.add_child(b)
		chips.append(b)
	_fit_header()
	_link_header()


## Voisins de focus de l'en-tête : en ligne, ▼ vers la carte choisie.
func _link_header() -> void:
	var line: Array = [tab_buttons[WEAPONS], tab_buttons[PARTS]]
	line.append_array(chips)
	var c := selected_card()
	for i in line.size():
		var b: Control = line[i]
		b.focus_neighbor_left = b.get_path_to(line[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(line[mini(i + 1, line.size() - 1)])
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(c if c else b)


func set_tab(id: String) -> void:
	if id != WEAPONS and id != PARTS:
		return
	var from_header := _focus_owner() != null and _focus_owner() in tab_buttons.values()
	if id == tab:
		return
	_disarm()
	tab = id
	_reload(true)
	hub.call("refresh_prompts")
	if from_header and is_instance_valid(tab_buttons[id]):
		(tab_buttons[id] as Control).grab_focus()
	elif visible:
		var c := selected_card()
		if c:
			c.grab_focus()


## Objet `uid` (arme ou pièce du profil) choisi et montré : sous-onglet qui
## le contient, filtre remis à TOUT s'il le cachait, fenêtre centrée dessus,
## focus sur sa carte (VOIR DANS L'ARSENAL d'une récompense). Faux si
## l'objet n'est pas dans l'arsenal.
func show_item(uid: String) -> bool:
	var pr := profile()
	if pr == null or uid == "" or main_row == null:
		return false
	var want := ""
	if pr.get_weapon(uid) != null:
		want = WEAPONS
	elif pr.get_part(uid) != null:
		want = PARTS
	if want == "":
		return false
	close_picker()
	_disarm()
	tab = want
	if want == PARTS:
		selected_part_uid = uid
		if not Hub2ArsenalView.parts(pr, part_filter).any(func(p): return String(p.uid) == uid):
			part_filter = "all"
	else:
		selected_uid = uid
		if not Hub2ArsenalView.weapons(pr, filter).any(func(w): return String(w.uid) == uid):
			filter = "all"
	_reload(true)
	var found := String(rail.selected().uid) == uid if rail.selected() != null else false
	_apply_selection(true)
	hub.call("refresh_prompts")
	# Après le focus par défaut de l'ouverture (Hub2Screen.open, différé).
	var c := selected_card()
	if c and hub:
		hub.focus_later(c)
	return found


func set_filter(f: String) -> void:
	var list: Array = Hub2ArsenalView.PART_FILTERS if tab == PARTS else Hub2ArsenalView.FILTERS
	if not f in list:
		return
	_disarm()
	var fk := _focus_key()
	if tab == PARTS:
		part_filter = f
	else:
		filter = f
	_reload(false)
	if fk.begins_with("chip:"):
		fk = "chip:" + f
	_restore_focus(fk)
	hub.call("set_hint", Lang.t("Filtre : %s", "Filter: %s") % Hub2ArsenalView.filter_name(f, tab == PARTS))


func cycle_filter() -> void:
	var list: Array = Hub2ArsenalView.PART_FILTERS if tab == PARTS else Hub2ArsenalView.FILTERS
	set_filter(Hub2ArsenalView.next_filter(list, part_filter if tab == PARTS else filter))


# --------------------------------------------------------------------------
# Rail des niveaux
# --------------------------------------------------------------------------

func _build_rail_box() -> Control:
	var box := Hub2Box.new()
	box.glass()
	box.pad(1)  # contenu sous le liseré de 1 px
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	prev_button = _arrow("‹", -1)
	row.add_child(prev_button)
	rail_area = RailArea.new()
	rail_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_area.clip_contents = true
	row.add_child(rail_area)
	columns_box = HBoxContainer.new()
	columns_box.add_theme_constant_override("separation", int(Hub2Style.px(COL_GAP)))
	columns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns_box.offset_left = Hub2Style.px(RAIL_PAD)
	columns_box.offset_right = -Hub2Style.px(RAIL_PAD)
	rail_area.add_child(columns_box)
	next_button = _arrow("›", 1)
	row.add_child(next_button)
	# Bande du bas : 58 px, liseré haut, padding 0 18, écart 20.
	var strip := Hub2Box.new()
	strip.flat(Color(0, 0, 0, 0), Hub2Style.LINE)
	strip.border = Vector4(0, 1, 0, 0)
	strip.pad(1, 18, 0, 18)
	strip.custom_minimum_size.y = Hub2Style.px(STRIP_H)
	v.add_child(strip)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", int(Hub2Style.px(20)))
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(sh)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(hints)
	for h in [["◄ ►", Lang.t("NIVEAU", "LEVEL")], ["▲ ▼", Lang.t("MÊME NIVEAU", "SAME LEVEL")]]:
		var sc := StripHint.new()
		sc.keys = String(h[0])
		sc.label = String(h[1])
		hints.add_child(sc)
	overview = Overview.new()
	overview.panel = self
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(overview)
	return box


## Flèche ‹ › (36 px, Chakra Petch 30 px ; jaune si active, sinon 15 %).
func _arrow(t: String, dir: int) -> Hub2Button:
	var b := Hub2Button.new()
	b.custom_minimum_size.x = Hub2Style.px(ARROW_W)
	b.focus_mode = Control.FOCUS_NONE
	var face := ArrowFace.new()
	face.glyph = t
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_content(face)
	b.set_meta("face", face)
	b.pressed.connect(func(): shift(dir))
	return b


## Largeur de la <section> de gauche (px à l'échelle).
func _section_width() -> float:
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	return w - Hub2Style.px(Hub2Style.SIDE) * 2.0 - Hub2Style.px(GAP_MAIN) - Hub2Style.px(ASIDE_W) - Hub2Style.px(1) * 2.0


## Colonnes visibles selon la largeur du rail (5 à 100 %).
func _fit_columns() -> int:
	var rail_w := _section_width() - Hub2Style.px(1) * 2.0 - Hub2Style.px(ARROW_W) * 2.0 - Hub2Style.px(RAIL_PAD) * 2.0
	return Hub2ArsenalRail.fit_visible(rail_w, Hub2Style.px(COL_W), Hub2Style.px(COL_GAP))


func _on_resized() -> void:
	if main_row == null or _rebuilding:
		return
	var n := _fit_columns()
	if n != _visible_cols:
		var fk := _focus_key()
		_visible_cols = n
		rail.visible = n
		rail.ensure_visible()
		_build_columns()
		_apply_selection(false)
		_restore_focus(fk)


## Objets du sous-onglet et rail reconstruits ; `fresh` : fenêtre centrée
## sur l'objet choisi (ouverture, changement de sous-onglet).
func _reload(fresh: bool) -> void:
	_rebuilding = true
	var pr := profile()
	var items: Array
	if tab == PARTS:
		items = Hub2ArsenalView.parts(pr, part_filter)
	else:
		items = Hub2ArsenalView.weapons(pr, filter)
	var old_start := rail.start
	rail.setup(items, Hub2ArsenalView.part_before if tab == PARTS else Hub2ArsenalView.weapon_before)
	_visible_cols = _fit_columns()
	rail.visible = _visible_cols
	var uid := selected_part_uid if tab == PARTS else selected_uid
	var found := uid != "" and rail.select_uid(uid)
	if not found:
		_default_selection()
	if fresh or not found:
		rail.center_on_selection()
	else:
		rail.start = old_start
		rail.ensure_visible()
	_store_selection()
	_fill_header()
	_build_columns()
	_apply_selection(false)
	_rebuilding = false


## Choix par défaut : la première arme du plus haut niveau utilisable (ou la
## première pièce du plus haut niveau montable).
func _default_selection() -> void:
	if rail.is_empty():
		return
	var lvl := profile().level() if profile() else 1
	var best := 0
	for i in rail.levels.size():
		if rail.levels[i] <= lvl:
			best = i
	rail.select_at(best, 0)


func _store_selection() -> void:
	var it: Variant = rail.selected()
	var uid := String(it.uid) if it != null else ""
	if tab == PARTS:
		selected_part_uid = uid
	else:
		selected_uid = uid


func _build_columns() -> void:
	for c in columns_box.get_children():
		columns_box.remove_child(c)
		c.queue_free()
	cards.clear()
	col_heads.clear()
	var pr := profile()
	var lvl := pr.level() if pr else 1
	var vis := rail.visible_cols()
	for k in rail.visible:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns_box.add_child(col)
		if k >= vis.size():
			continue
		var i: int = vis[k]
		var items := rail.column(i)
		var head := ColumnHead.new()
		head.level = rail.levels[i]
		head.count = items.size()
		head.over = rail.levels[i] > lvl and tab == WEAPONS
		# height: 48px + padding-bottom: 2px (content-box : 50), losange 14,
		# vide 14 : cartes à 78 px du haut du rail.
		head.custom_minimum_size.y = Hub2Style.px(COL_HEAD_H) + Hub2Style.px(2) + Hub2Style.px(NODE_H) + Hub2Style.px(14)
		col.add_child(head)
		col_heads.append(head)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.follow_focus = true
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll_mark(sc, col, Hub2Style.px(1.5))
		col.add_child(sc)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", int(Hub2Style.px(CARD_GAP)))
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(list)
		for r in items.size():
			var card := Hub2ArsenalCard.new()
			card.key = String(items[r].uid)
			card.level = rail.levels[i]
			card.set_meta("col", i)
			card.set_meta("row", r)
			card.setup(_card_data(items[r]))
			card.hint = _card_hint(items[r])
			card.focus_entered.connect(_on_card_focus.bind(card))
			card.pressed.connect(_on_card_pressed.bind(card))
			card.nav.connect(_on_card_nav)
			list.add_child(card)
			cards.append(card)
	_update_arrows()
	overview.queue_redraw()


func _card_data(it: Variant) -> Dictionary:
	var pr := profile()
	if it is WeaponPart:
		var p: WeaponPart = it
		var q := Hub2ArsenalView.part_quality(p)
		return {"name": HubGear.part_name(p).to_upper(), "color": Hub2ArsenalView.quality_color(q),
			"kind_name": Hub2ArsenalView.quality_name(q), "part_art": true,
			"is_new": pr.is_new_part(p.uid) or _seen_now.has(p.uid), "base": false, "locked": false,
			"score": "", "slots": 0, "filled": 0, "effects": Hub2ArsenalView.effects(p)}
	var w: OwnedWeapon = it
	var base := Hub2ArsenalView.is_base(w)
	return {"name": HubGear.weapon_name(w.weapon_id), "color": Hub2Style.rarity_color(w.rarity),
		"kind_name": GameWeapon.rarity_name(w.rarity), "img": HubRenders.weapon(w.weapon_id),
		"is_new": not base and (pr.is_new_weapon(w.uid) or _seen_now.has(w.uid)), "base": base,
		"locked": w.level > pr.level(), "required": Hub2ArsenalView.required_text(w.level),
		"score": str(w.score()), "slots": w.slot_count(), "filled": w.parts.size()}


func _card_hint(it: Variant) -> String:
	if it is WeaponPart:
		var key := Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.ACCEPT), Hub2Input.pads_of(Hub2Input.ACCEPT), Settings.using_pad)
		return Lang.t("%s : installer cette pièce sur une arme compatible.", "%s: install this part on a compatible weapon.") % key
	var w: OwnedWeapon = it
	if w.level > profile().level():
		return Lang.t("Niveau %d requis pour l’équiper ou la construire : gardée pour plus tard.",
				"Level %d required to equip or build it: kept for later.") % w.level
	if Hub2ArsenalView.is_base(w):
		return Lang.t("Arme de base : donnée à tous, ni modifiable ni recyclable.",
				"Base weapon: given to everyone, can't be modified or recycled.")
	return ""


func cards_of_col(i: int) -> Array:
	var out := []
	for c in cards:
		if int(c.get_meta("col")) == i:
			out.append(c)
	return out


func card_at(i: int, r: int) -> Hub2ArsenalCard:
	for c in cards:
		if int(c.get_meta("col")) == i and int(c.get_meta("row")) == r:
			return c
	return null


func selected_card() -> Hub2ArsenalCard:
	return card_at(rail.sel_col, rail.sel_row)


func _update_arrows() -> void:
	for pair in [[prev_button, -1], [next_button, 1]]:
		var b: Hub2Button = pair[0]
		var on := rail.can_shift(int(pair[1]))
		(b.get_meta("face") as ArrowFace).enabled = on
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW


## ‹ › : fenêtre décalée (la sélection ne change pas ; si sa carte sort de la
## fenêtre et qu'elle avait le focus, le focus va à la carte visible la plus
## proche).
func shift(dir: int) -> void:
	if not rail.shift(dir):
		return
	_scrolled()


## Vue d'ensemble : saut au niveau d'indice `i`.
func jump(i: int) -> void:
	var old := rail.start
	rail.jump(i)
	if rail.start != old:
		_scrolled()


func _scrolled() -> void:
	var had_focus := _focus_owner() is Hub2ArsenalCard
	_build_columns()
	_apply_selection(false)
	if had_focus:
		var c := selected_card()
		if c == null:
			var target := clampi(rail.sel_col, rail.start, rail.start + rail.visible - 1)
			c = card_at(target, 0)
		if c:
			c.grab_focus()


func _on_card_focus(card: Hub2ArsenalCard) -> void:
	var i := int(card.get_meta("col"))
	var r := int(card.get_meta("row"))
	if armed == "recycle" and (i != rail.sel_col or r != rail.sel_row):
		_disarm()
	if i != rail.sel_col or r != rail.sel_row:
		rail.select_at(i, r)
		_store_selection()
		_apply_selection(true)
	if card.hint != "":
		hub.call("set_hint", card.hint)
	hub.call("refresh_prompts")


func _on_card_pressed(card: Hub2ArsenalCard) -> void:
	var mouse := card.pressed_by_mouse
	card.pressed_by_mouse = false
	var i := int(card.get_meta("col"))
	var r := int(card.get_meta("row"))
	if i != rail.sel_col or r != rail.sel_row:
		rail.select_at(i, r)
		_store_selection()
		_apply_selection(true)
	if mouse:
		return
	enter_aside()


## ◄ ► ▲ ▼ sur une carte.
func _on_card_nav(dir: Vector2i) -> void:
	if dir.x != 0:
		var old := rail.start
		if not rail.move_col(dir.x):
			return
		if rail.start != old:
			_build_columns()
	elif dir.y != 0:
		if not rail.move_row(dir.y):
			if dir.y < 0:
				var tb: Control = tab_buttons[tab]
				tb.grab_focus()
			return
	Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
	_store_selection()
	var c := selected_card()
	if c:
		c.grab_focus()
	_apply_selection(true)


## Sélection affichée : cartes, têtes de colonne, vue d'ensemble, fiche.
func _apply_selection(user: bool) -> void:
	for c in cards:
		(c as Hub2ArsenalCard).selected = int(c.get_meta("col")) == rail.sel_col and int(c.get_meta("row")) == rail.sel_row
	var sl := rail.selected_level()
	for h in col_heads:
		(h as ColumnHead).on = (h as ColumnHead).level == sl
		(h as ColumnHead).queue_redraw()
	_update_arrows()
	overview.queue_redraw()
	_fill_aside()
	_link_header()
	if user:
		_mark_seen()


## NOUVEAU vu : seulement quand l'écran est affiché.
func _mark_seen() -> void:
	var pr := profile()
	if pr == null or not is_visible_in_tree():
		return
	var it: Variant = rail.selected()
	if it == null:
		return
	if it is WeaponPart:
		if pr.is_new_part(String(it.uid)):
			_seen_now[String(it.uid)] = true
			pr.mark_part_seen(String(it.uid))
			_pending_seen = true
	elif pr.is_new_weapon(String(it.uid)):
		_seen_now[String(it.uid)] = true
		pr.mark_weapon_seen(String(it.uid))
		for p in (it as OwnedWeapon).parts:
			pr.mark_part_seen(p.uid)
		_pending_seen = true


# --------------------------------------------------------------------------
# Fiche (à droite)
# --------------------------------------------------------------------------

func _fill_aside() -> void:
	for c in aside_col.get_children():
		aside_col.remove_child(c)
		c.queue_free()
	slots.clear()
	compat_rows.clear()
	stat_cells.clear()
	details = null
	name_text = ""
	var it: Variant = rail.selected()
	if it == null:
		var m := Hub2Box.new()
		m.flat(Color(0, 0, 0, 0))
		m.pad(20)
		var l := Hub2Style.label(Lang.t("Aucune pièce en stock : on en trouve en partie." if tab == PARTS
				else "Aucune arme ne correspond au filtre.",
				"No part in stock: they are found during matches." if tab == PARTS else "No weapon matches the filter."),
				Hub2Style.BARLOW, 400, 15, Hub2Style.text_a(0.6))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = Hub2Style.px(300)
		m.add_child(l)
		aside_col.add_child(m)
		return
	if it is WeaponPart:
		_fill_part(it)
	else:
		_fill_weapon(it)


## En-tête de la fiche : padding 20 20 16, liseré haut 3 px de la couleur ;
## « RARETÉ · CLASSE » (Chakra Petch 13 px 700 0,14em), 4 px plus bas le nom
## (36 px 700 0,03em, line-height 1) et « NIV. N » (JetBrains Mono 14 px,
## 70 %) sur la même ligne de base.
func _head(kicker: String, col: Color, title: String, lvl: int) -> void:
	var head := Hub2Box.new()
	head.flat(Color(0, 0, 0, 0), col)
	head.border = Vector4(0, 3, 0, 0)
	head.pad(23, 20, 16, 20)  # liseré 3 + padding 20
	aside_col.add_child(head)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(v)
	var k := StrutText.new()
	k.text = kicker
	k.color = col
	v.add_child(k)
	var hl := HeadLine.new()
	hl.title = title
	hl.level = Hub2ArsenalView.level_text(lvl)
	v.add_child(hl)
	name_text = title


func _fill_weapon(w: OwnedWeapon) -> void:
	var rc := Hub2Style.rarity_color(w.rarity)
	_head("%s · %s" % [GameWeapon.rarity_name(w.rarity), Hub2ArsenalView.class_name_of(w.weapon_id)], rc,
			HubGear.weapon_name(w.weapon_id), w.level)
	var rv := RenderView.new()
	rv.tex = HubRenders.weapon(w.weapon_id)
	rv.score = str(w.score())
	aside_col.add_child(_margin(rv, 0, 20, 0, 20))
	# Statistiques : padding 12 20, grille 2 colonnes, écarts 10 / 16.
	var sb := Hub2Box.new()
	sb.flat(Color(0, 0, 0, 0), Hub2Style.LINE)
	sb.border = Vector4(0, 1, 0, 0)
	sb.pad(13, 20, 12, 20)  # liseré 1 + padding 12
	aside_col.add_child(sb)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sb.add_child(sv)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(Hub2Style.px(16)))
	grid.add_theme_constant_override("v_separation", int(Hub2Style.px(10)))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(grid)
	for line in Hub2ArsenalView.stat_lines(w):
		var cell := Hub2ArsenalStat.new()
		cell.line = line
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		stat_cells.append(cell)
	# Fiche complète repliable (DÉTAILS ▾ : D / R3, clic), même grille.
	details = Hub2WeaponDetails.new()
	details.setup(DETAILS_SCREEN, 16, 10)
	details.set_lines(Hub2ArsenalView.detail_lines(w))
	details.toggled.connect(func(_o): hub.call("refresh_prompts"))
	sv.add_child(details)
	# Pièces : padding 14 20, écart 8, reste de la hauteur (défile).
	var pb := Hub2Box.new()
	pb.flat(Color(0, 0, 0, 0), Hub2Style.LINE)
	pb.border = Vector4(0, 1, 0, 0)
	pb.pad(15, 20, 14, 20)
	pb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aside_col.add_child(pb)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(pv)
	var base := Hub2ArsenalView.is_base(w)
	var ph := Hub2Text.new()
	ph.setup(Lang.t("PIÈCES · %d / %d", "PARTS · %d / %d") % [w.parts.size(), 0 if base else w.slot_count()],
			Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.18)
	pv.add_child(ph)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_mark(sc, pv, Hub2Style.px(8))
	sc.custom_minimum_size.y = Hub2Style.px(56)  # au moins une ligne visible
	pv.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(list)
	if base:
		list.add_child(_slot_box(Lang.t("Arme de base", "Base weapon"),
				Lang.t("Ni pièce ni recyclage : améliorée en partie et ramenée, elle devient une nouvelle version.",
				"No parts, no recycling: upgraded in a match and brought back, it becomes a new version."), false, -1))
		return
	for i in w.slot_count():
		var b: Hub2Button
		if i < w.parts.size():
			var p := w.parts[i]
			b = _slot_box(Hub2ArsenalView.part_line_name(p), "", true, i, Hub2ArsenalView.effects(p))
			b.hint = Lang.t("%s : retirer cette pièce (deux appuis, elle sera détruite).",
					"%s: remove this part (two presses, it will be destroyed).") % key_name(Hub2Input.SECONDARY)
		else:
			var key := Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.ACCEPT), Hub2Input.pads_of(Hub2Input.ACCEPT), Settings.using_pad)
			b = _slot_box(Lang.t("Emplacement libre", "Free slot"),
					Lang.t("%s : installer une pièce", "%s: install a part") % key, true, i)
			b.hint = _install_hint(w)
		list.add_child(b)
	_link_slots()


## Ligne d'emplacement : pièce installée (fond rgba(255,255,255,.05)) ou
## emplacement libre (tirets 1 px rgba(255,255,255,.18)) ; padding 9 12,
## nom Chakra Petch 15 px 700 0,04em, ligne Barlow 13 px.
func _slot_box(title: String, sub: String, focusable: bool, index: int, eff: Array = []) -> Hub2Button:
	var installed := not eff.is_empty()
	var b := Hub2Button.new()
	b.box.flat(Hub2Style.white_a(0.05) if installed else Color(0, 0, 0, 0))
	b.box.pad(9, 12)
	if not focusable:
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(2)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(v)
	var t := Hub2Text.new()
	t.setup(title, Hub2Style.CHAKRA, 700, 15, Hub2Style.TEXT if installed else Hub2Style.text_a(0.55), 0.04)
	v.add_child(t)
	var ml := Hub2ArsenalModLine.new()
	if installed:
		ml.effects = eff
	else:
		ml.plain = sub
		ml.color_override = Hub2Style.text_a(0.45)
	v.add_child(ml)
	if not installed:
		var dash := Dashed.new()
		dash.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(dash)
		b.move_child(dash, 1)
	b.set_meta("slot", index)
	b.set_meta("installed", installed)
	b.set_meta("title", t)
	if focusable and index >= 0:
		b.focus_entered.connect(func():
			if armed == "remove" and armed_slot != index:
				_disarm()
			hub.call("set_hint", b.hint)
			hub.call("refresh_prompts"))
		b.pressed.connect(func(): _on_slot_pressed(b))
		slots.append(b)
	return b


func _install_hint(w: OwnedWeapon) -> String:
	var pr := profile()
	if pr.parts.is_empty():
		return Lang.t("Aucune pièce en stock : on en trouve en partie.", "No part in stock: they are found during matches.")
	return Lang.t("Choisir une pièce à installer ici (aperçu avant / après).", "Pick a part to install here (before / after preview).") \
			if w.free_slots() > 0 else ""


func _link_slots() -> void:
	var c := selected_card()
	for i in slots.size():
		var s: Control = slots[i]
		s.focus_neighbor_top = s.get_path_to(slots[maxi(i - 1, 0)])
		s.focus_neighbor_bottom = s.get_path_to(slots[mini(i + 1, slots.size() - 1)])
		s.focus_neighbor_right = s.get_path_to(s)
		s.focus_neighbor_left = s.get_path_to(c if c else s)


func _on_slot_pressed(b: Hub2Button) -> void:
	if bool(b.get_meta("installed")):
		if not b.has_focus():
			b.grab_focus()
		hub.call("set_hint", b.hint)
		return
	var w := selected_weapon()
	if w == null:
		return
	open_picker(w, int(b.get_meta("slot")))


func _margin(c: Control, t: float, r: float, b: float, l: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", int(Hub2Style.px(t)))
	m.add_theme_constant_override("margin_right", int(Hub2Style.px(r)))
	m.add_theme_constant_override("margin_bottom", int(Hub2Style.px(b)))
	m.add_theme_constant_override("margin_left", int(Hub2Style.px(l)))
	m.add_child(c)
	return m


func selected_weapon() -> OwnedWeapon:
	var it: Variant = rail.selected()
	return it as OwnedWeapon if it is OwnedWeapon else null


func selected_part() -> WeaponPart:
	var it: Variant = rail.selected()
	return it as WeaponPart if it is WeaponPart else null


## Fiche d'une pièce : qualité · PIÈCE, nom, niveau ; pixel art et apport au
## score ; effets ; ARMES COMPATIBLES (aperçu de la statistique changée ; A :
## installer) puis les autres avec la raison.
func _fill_part(p: WeaponPart) -> void:
	var pr := profile()
	var q := Hub2ArsenalView.part_quality(p)
	var qc := Hub2ArsenalView.quality_color(q)
	_head("%s · %s" % [Hub2ArsenalView.quality_name(q), Lang.t("PIÈCE", "PART")], qc, HubGear.part_name(p).to_upper(), p.level)
	var rv := RenderView.new()
	rv.part = true
	rv.score = "+%d" % p.level
	aside_col.add_child(_margin(rv, 0, 20, 0, 20))
	var eb := Hub2Box.new()
	eb.flat(Color(0, 0, 0, 0), Hub2Style.LINE)
	eb.border = Vector4(0, 1, 0, 0)
	eb.pad(13, 20, 12, 20)
	aside_col.add_child(eb)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	ev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eb.add_child(ev)
	var eh := Hub2Text.new()
	eh.setup(Lang.t("EFFETS", "EFFECTS"), Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.18)
	ev.add_child(eh)
	for e in Hub2ArsenalView.effects(p):
		var t := Hub2Text.new()
		t.setup(String(e[0]), Hub2Style.MONO, 700, 15, Hub2ArsenalView.GOOD if e[1] else Hub2ArsenalView.HARMFUL)
		ev.add_child(t)
	var rule := Hub2Text.new()
	rule.setup(Lang.t("Se monte sur une arme de niveau %d ou plus", "Fits a weapon of level %d or more") % p.level,
			Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55))
	ev.add_child(rule)
	var cb := Hub2Box.new()
	cb.flat(Color(0, 0, 0, 0), Hub2Style.LINE)
	cb.border = Vector4(0, 1, 0, 0)
	cb.pad(15, 20, 14, 20)
	cb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aside_col.add_child(cb)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb.add_child(cv)
	var comp := Hub2ArsenalView.compatible(pr, p)
	var ch := Hub2Text.new()
	ch.setup(Lang.t("ARMES COMPATIBLES · %d", "COMPATIBLE WEAPONS · %d") % (comp.ok as Array).size(),
			Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.18)
	cv.add_child(ch)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_mark(sc, cv, Hub2Style.px(8))
	sc.custom_minimum_size.y = Hub2Style.px(56)
	cv.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(list)
	for w: OwnedWeapon in comp.ok:
		list.add_child(_compat_row(w, p, ""))
	if (comp.ok as Array).is_empty():
		var none := Hub2Style.label(Lang.t("Aucune arme de l’arsenal ne peut la recevoir pour l’instant.",
				"No arsenal weapon can take it for now."), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = Hub2Style.px(250)
		list.add_child(none)
	for pair in comp.ko:
		list.add_child(_compat_row(pair[0], p, String(pair[1])))
	var c := selected_card()
	for i in compat_rows.size():
		var r: Control = compat_rows[i]
		r.focus_neighbor_top = r.get_path_to(compat_rows[maxi(i - 1, 0)])
		r.focus_neighbor_bottom = r.get_path_to(compat_rows[mini(i + 1, compat_rows.size() - 1)])
		r.focus_neighbor_right = r.get_path_to(r)
		r.focus_neighbor_left = r.get_path_to(c if c else r)


## Arme compatible (focusable : A = installer) ou non (raison, 50 %).
func _compat_row(w: OwnedWeapon, p: WeaponPart, why: String) -> Hub2Button:
	var b := Hub2Button.new()
	b.box.flat(Hub2Style.white_a(0.05))
	b.box.pad(9, 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(2)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(v)
	var t := Hub2Text.new()
	t.setup("%s · %s" % [HubGear.weapon_name(w.weapon_id), Hub2ArsenalView.level_text(w.level)], Hub2Style.CHAKRA, 700, 15,
			Hub2Style.rarity_color(w.rarity), 0.04)
	v.add_child(t)
	if why != "":
		b.modulate.a = 0.5
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		var r := Hub2Text.new()
		r.setup(why, Hub2Style.CHAKRA, 700, 11, Hub2Style.BAD, 0.08)
		v.add_child(r)
		return b
	var pv := Hub2ArsenalView.preview_lines(w, p)
	var ml := Hub2ArsenalModLine.new()
	if pv.is_empty():
		ml.plain = Lang.t("%d emplacement(s) libre(s)", "%d free slot(s)") % w.free_slots()
		ml.color_override = Hub2Style.text_a(0.55)
	else:
		var eff := []
		for l in pv:
			eff.append(["%s %s → %s" % [String(l.label), l.before, l.after], l.good])
		ml.effects = eff
	v.add_child(ml)
	b.set_meta("uid", w.uid)
	b.hint = Lang.t("Installer la pièce sur cette arme (aperçu avant / après).", "Install the part on this weapon (before / after preview).")
	b.focus_entered.connect(func():
		hub.call("set_hint", b.hint)
		hub.call("refresh_prompts"))
	b.pressed.connect(func():
		var pr := profile()
		var ww := pr.get_weapon(String(b.get_meta("uid")))
		if ww:
			open_picker(ww, ww.parts.size(), p.uid))
	compat_rows.append(b)
	return b


## A sur une carte : vers la fiche (premier emplacement libre, sinon la
## première pièce ; onglet PIÈCES : première arme compatible).
func enter_aside() -> void:
	if tab == PARTS:
		if not compat_rows.is_empty():
			(compat_rows[0] as Control).grab_focus()
		else:
			hub.call("set_hint", Lang.t("Aucune arme de l’arsenal ne peut recevoir cette pièce.", "No arsenal weapon can take this part."))
		return
	var w := selected_weapon()
	if w == null:
		return
	if Hub2ArsenalView.is_base(w):
		hub.call("set_hint", Lang.t("Arme de base : pas de pièce.", "Base weapon: no parts."))
		return
	var target: Control = null
	for s in slots:
		if not bool(s.get_meta("installed")):
			target = s
			break
	if target == null and not slots.is_empty():
		target = slots[0]
	if target:
		target.grab_focus()


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

## Fenêtre des pièces pour l'emplacement `slot` de `w` (`pre` : pièce choisie).
func open_picker(w: OwnedWeapon, slot: int, pre := "") -> void:
	if w == null or Hub2ArsenalView.is_base(w):
		return
	if w.free_slots() <= 0:
		hub.call("set_hint", Lang.t("Aucun emplacement libre : retirez d’abord une pièce.", "No free slot: remove a part first."))
		return
	close_picker()
	_disarm()
	picker = Hub2PartPicker.new()
	picker.install_requested.connect(_install.bind(w.uid))
	picker.closed.connect(close_picker)
	add_child(picker)
	picker.open(hub, profile(), w, mini(slot, w.parts.size()), content_rect(), pre)
	hub.call("refresh_prompts")


func close_picker() -> void:
	if picker == null:
		return
	var p := picker
	picker = null
	if is_instance_valid(p):
		remove_child(p)
		p.queue_free()
	hub.call("refresh_prompts")
	if visible:
		var f := first_focus()
		if tab == WEAPONS and not slots.is_empty():
			f = slots[0]
			for s in slots:
				if not bool(s.get_meta("installed")):
					f = s
					break
		if f:
			f.grab_focus()


func _install(part_uid: String, weapon_uid: String) -> void:
	var pr := profile()
	var w := pr.get_weapon(weapon_uid)
	if w == null:
		return
	var slot := w.parts.size()
	if not pr.mount_part(weapon_uid, part_uid):
		hub.call("set_hint", Lang.t("Cette pièce ne se monte pas sur cette arme.", "This part can't be mounted on this weapon."))
		return
	pr.mark_part_seen(part_uid)
	var p := picker
	picker = null
	if is_instance_valid(p):
		remove_child(p)
		p.queue_free()
	_pending_seen = false
	# L'arme montée est choisie (onglet ARMES), focus sur son emplacement.
	if tab == PARTS:
		tab = WEAPONS
	selected_uid = weapon_uid
	hub.call("save_profile")
	_reload(false)
	var f: Control = slots[mini(slot, slots.size() - 1)] if not slots.is_empty() else selected_card()
	if f:
		f.grab_focus()
	hub.call("refresh_prompts")
	hub.call("set_hint", Lang.t("Pièce installée.", "Part installed."))


## X / Suppr : retirer la pièce qui a le focus, ou recycler l'arme choisie,
## en deux appuis.
func secondary() -> void:
	if picker or tab != WEAPONS:
		return
	var f := _focus_owner()
	if f != null and f in slots and bool(f.get_meta("installed")):
		var i := int(f.get_meta("slot"))
		if armed == "remove" and armed_slot == i:
			_remove_part(i)
		else:
			_arm("remove", i)
		return
	# Focus dans l'en-tête ou sur un emplacement libre : rien à recycler.
	if f != null and is_ancestor_of(f) and not (f is Hub2ArsenalCard):
		return
	var w := selected_weapon()
	if w == null:
		return
	if not profile().is_recyclable(w.uid):
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		hub.call("set_hint", Lang.t("Arme de base : jamais recyclée.", "Base weapon: never recycled."))
		return
	if armed == "recycle":
		_recycle()
	else:
		_arm("recycle", -1)


func _arm(what: String, slot: int) -> void:
	armed = what
	armed_slot = slot
	if what == "remove":
		for s in slots:
			var on := int(s.get_meta("slot")) == slot
			(s as Hub2Button).box.flat(Hub2Style.white_a(0.05), Hub2Style.BAD_ALT if on else Color(0, 0, 0, 0), 1.0 if on else 0.0)
		hub.call("set_hint", Lang.t("%s encore pour confirmer : la pièce sera DÉTRUITE.",
				"%s again to confirm: the part will be DESTROYED.") % key_name(Hub2Input.SECONDARY))
	else:
		hub.call("set_hint", Lang.t("%s encore pour confirmer : l’arme sera détruite, rien n’est rendu.",
				"%s again to confirm: the weapon will be destroyed, nothing is given back.") % key_name(Hub2Input.SECONDARY))
	hub.call("refresh_prompts")


func _disarm() -> void:
	if armed == "":
		return
	armed = ""
	armed_slot = -1
	for s in slots:
		if bool(s.get_meta("installed")):
			(s as Hub2Button).box.flat(Hub2Style.white_a(0.05))
	if hub:
		hub.call("set_hint", "")
		hub.call("refresh_prompts")


func _remove_part(i: int) -> void:
	var w := selected_weapon()
	armed = ""
	armed_slot = -1
	if w == null or i >= w.parts.size() or not profile().unmount_part(w.uid, w.parts[i].uid):
		return
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	_pending_seen = false
	hub.call("save_profile")
	if not slots.is_empty():
		(slots[mini(i, slots.size() - 1)] as Control).grab_focus()
	hub.call("refresh_prompts")
	hub.call("set_hint", Lang.t("Pièce retirée et détruite.", "Part removed and destroyed."))


func _recycle() -> void:
	var w := selected_weapon()
	armed = ""
	armed_slot = -1
	var pr := profile()
	if w == null or not pr.is_recyclable(w.uid):
		return
	# La carte suivante de la colonne (ou la précédente, ou la colonne
	# voisine) prend la place.
	var col := rail.column(rail.sel_col)
	var next: Variant = null
	if rail.sel_row + 1 < col.size():
		next = col[rail.sel_row + 1]
	elif rail.sel_row > 0:
		next = col[rail.sel_row - 1]
	else:
		var nc := rail.column(rail.sel_col + 1)
		if nc.is_empty():
			nc = rail.column(rail.sel_col - 1)
		if not nc.is_empty():
			next = nc[0]
	if pr.remove_weapon(w.uid) == null:
		return
	_seen_now.erase(w.uid)
	_pending_seen = false
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	selected_uid = String(next.uid) if next != null else ""
	hub.call("save_profile")
	var c := selected_card()
	if c:
		c.grab_focus()
	hub.call("refresh_prompts")
	hub.call("set_hint", Lang.t("Arme recyclée : rien n’est rendu au hub.", "Weapon recycled: nothing is given back at the hub."))


func _on_device(_pad: bool) -> void:
	# Textes qui nomment une touche (« A : installer une pièce ») : relus.
	if built and picker == null and armed == "" and is_visible_in_tree():
		var fk := _focus_key()
		_reload(false)
		_restore_focus(fk)


# --------------------------------------------------------------------------
# Focus
# --------------------------------------------------------------------------

func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if is_inside_tree() else null


## Clé de l'élément qui a le focus (retrouvé après reconstruction).
func _focus_key() -> String:
	var f := _focus_owner()
	if f == null or not is_ancestor_of(f):
		return ""
	if f is Hub2ArsenalCard:
		return "card"
	if f in slots:
		return "slot:%d" % int(f.get_meta("slot"))
	if f in compat_rows:
		return "compat:" + String(f.get_meta("uid"))
	if f in chips:
		return "chip:" + String(f.get_meta("filter"))
	for id in tab_buttons:
		if tab_buttons[id] == f:
			return "tab:" + String(id)
	return "card"


func _restore_focus(fk: String) -> void:
	if fk == "" or not is_visible_in_tree():
		return
	var c: Control = null
	if fk.begins_with("slot:"):
		var i := fk.substr(5).to_int()
		if not slots.is_empty():
			c = slots[mini(i, slots.size() - 1)]
	elif fk.begins_with("compat:"):
		for r in compat_rows:
			if String(r.get_meta("uid")) == fk.substr(7):
				c = r
		if c == null and not compat_rows.is_empty():
			c = compat_rows[0]
	elif fk.begins_with("chip:"):
		for ch in chips:
			if String(ch.get_meta("filter")) == fk.substr(5):
				c = ch
	elif fk.begins_with("tab:"):
		c = tab_buttons.get(fk.substr(4))
	if c == null:
		c = first_focus()
	if c:
		c.grab_focus()


## Nom de la touche de l'invite `id` pour le périphérique courant (« A »,
## « Entrée », « X », « Suppr »).
static func key_name(id: String) -> String:
	return Hub2Input.keycap_text(Hub2Input.keys_of(id), Hub2Input.pads_of(id), Settings.using_pad)


static func _pad_pressed(event: InputEvent, button: JoyButton) -> bool:
	var b := event as InputEventJoypadButton
	return b != null and b.pressed and b.button_index == button


## Liste qui défile sans barre (la maquette n'en dessine pas et une barre
## prendrait de la largeur aux cartes) : molette, focus suivi ; quand la
## liste déborde (130 %, longues colonnes), `host` (un conteneur sans
## matériau qui contient la liste) dessine à `dx` px à droite de la liste un
## trait de 3 px rgba(255,255,255,.18) à la position et à la taille de la
## partie visible.
static func scroll_mark(sc: ScrollContainer, host: Control, dx: float) -> void:
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var bar := sc.get_v_scroll_bar()
	bar.changed.connect(host.queue_redraw)
	bar.value_changed.connect(func(_v: float): host.queue_redraw())
	sc.resized.connect(host.queue_redraw)
	host.draw.connect(func():
		if not is_instance_valid(sc) or not sc.is_visible_in_tree() or bar.max_value <= bar.page + 0.5:
			return
		var r := Rect2(host.get_global_transform().affine_inverse() * sc.global_position, sc.size)
		var h := maxf(r.size.y * bar.page / bar.max_value, Hub2Style.px(12))
		var y := r.position.y + (r.size.y - h) * (bar.value / maxf(bar.max_value - bar.page, 1.0))
		host.draw_rect(Rect2(r.end.x + dx, y, maxf(Hub2Style.px(3), 2.0), h), Hub2Style.white_a(0.18)))


# ==========================================================================
# Éléments dessinés
# ==========================================================================

## Sous-onglet (« ARMES 14 ») : Chakra Petch 22 px 0,06em (700 choisi,
## 600 sinon, 50 %), nombre JetBrains Mono 13 px (55 % ; 50 % hors choix),
## padding-bottom 6, soulignement 2 px jaune (choisi). Centré dans les 34 px
## de la ligne (align-items: center).
class TabFace extends Control:
	var label := ""
	var count := ""
	var on := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _weight() -> int:
		return 700 if on else 600

	func content_width() -> float:
		var f := Hub2Style.font(Hub2Style.CHAKRA, _weight())
		var s := Hub2Style.fs(22)
		var tr := Hub2Style.tracking_px(0.06, s)
		var mf := Hub2Style.font(Hub2Style.MONO, 500)
		var ms := Hub2Style.fs(13)
		return ceilf(Hub2Style.text_width(label + " ", f, s, tr) + Hub2Style.text_width(count, mf, ms, Hub2Style.tracking_px(0.06, ms)))

	func _draw() -> void:
		var f := Hub2Style.font(Hub2Style.CHAKRA, _weight())
		var s := Hub2Style.fs(22)
		var tr := Hub2Style.tracking_px(0.06, s)
		var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, _weight(), 22)
		var h := lh + Hub2Style.px(6) + Hub2Style.px(2)
		var top := (size.y - h) * 0.5
		var base := roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, _weight(), 22, top, lh))
		var col := Hub2Style.TEXT if on else Hub2Style.text_a(0.5)
		var x := Hub2Style.draw_text(self, f, Vector2(0, base), label + " ", s, col, tr)
		var mf := Hub2Style.font(Hub2Style.MONO, 500)
		var ms := Hub2Style.fs(13)
		Hub2Style.draw_text(self, mf, Vector2(roundf(x), base), count, ms, Hub2Style.text_a(0.55) if on else col,
				Hub2Style.tracking_px(0.06, ms))
		if on:
			draw_rect(Rect2(0, top + h - Hub2Style.px(2), size.x, Hub2Style.px(2)), Hub2Style.YELLOW)


## Flèche ‹ › du rail.
class ArrowFace extends Control:
	var glyph := "‹"
	var enabled := true:
		set(v):
			enabled = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Hub2ArsenalDraw.text(self, glyph, Hub2Style.CHAKRA, 500, 30, Hub2Style.YELLOW if enabled else Hub2Style.text_a(0.15), 0.0,
				0.0, Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 500, 30, 0.0, size.y), size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Zone des colonnes : filet de 1 px rgba(255,255,255,.16) à 56 px du haut.
class RailArea extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, Hub2Style.px(LINE_Y), size.x, maxf(Hub2Style.px(1), 1.0)), Hub2Style.white_a(0.16))


## Tête de colonne : « NIV. N » (Chakra Petch 16 px 700 0,06em ; jaune si
## choisie, 35 % au-dessus du niveau du joueur) et « ×n » (JetBrains Mono
## 12 px, 55 %) en bas d'une boîte de 48 px (+ padding-bottom 2 : 50 px,
## écart 6), puis losange de 9 px (jaune / 40 %) centré dans 14 px (sur le
## filet à 56 px), puis 14 px vides.
class ColumnHead extends Control:
	var level := 1
	var count := 1
	var on := false
	var over := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
		var s := Hub2Style.fs(16)
		var tr := Hub2Style.tracking_px(0.06, s)
		var t := Hub2ArsenalView.level_text(level)
		var lw := Hub2Style.text_width(t, f, s, tr)
		var mf := Hub2Style.font(Hub2Style.MONO, 500)
		var ms := Hub2Style.fs(12)
		var ct := "×%d" % count
		var cw := Hub2Style.text_width(ct, mf, ms) if count > 1 else 0.0
		var gap := Hub2Style.px(6) if count > 1 else 0.0
		var x := roundf((size.x - lw - gap - cw) * 0.5)
		var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 16)
		# Boîte de 48 px (content-box) + padding-bottom 2 : bas du texte à 48.
		var bottom := Hub2Style.px(48)
		var base := roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 16, bottom - lh, lh))
		var col := Hub2Style.YELLOW if on else (Hub2Style.text_a(0.35) if over else Hub2Style.TEXT)
		Hub2Style.draw_text(self, f, Vector2(x, base), t, s, col, tr)
		if count > 1:
			# align-items: flex-end : le bas des deux boîtes de ligne aligné.
			var mlh := Hub2ArsenalDraw.line_h(Hub2Style.MONO, 500, 12)
			Hub2Style.draw_text(self, mf, Vector2(x + lw + gap, roundf(Hub2ArsenalDraw.baseline(Hub2Style.MONO, 500, 12, bottom - mlh, mlh))),
					ct, ms, Hub2Style.text_a(0.55))
		var c := Vector2(roundf(size.x * 0.5), Hub2Style.px(50) + Hub2Style.px(7))
		Hub2ArsenalDraw.draw_diamond(self, c, Hub2Style.px(9), Hub2Style.YELLOW if on else Hub2Style.text_a(0.4))


## Aide de la bande du bas : <kbd> (20 px, padding 0 5, JetBrains Mono
## 10 px 700) puis le libellé (Chakra Petch 12 px 600 0,1em, 60 %), écart 6.
class StripHint extends Control:
	var keys := ""
	var label := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		custom_minimum_size = Vector2(ceilf(_kbd_w() + Hub2Style.px(6) + _label_w()), Hub2Style.px(20))

	func _kbd_w() -> float:
		return _glyphs_w() + Hub2Style.px(5) * 2.0

	## Largeur des flèches : celles de la police si elle les a, sinon dessinées.
	func _glyphs_w() -> float:
		var mf := Hub2Style.font(Hub2Style.MONO, 700)
		var ms := Hub2Style.fs(10)
		return Hub2Style.text_width(keys, mf, ms)

	func _label_w() -> float:
		var s := Hub2Style.fs(12)
		return Hub2Style.text_width(label, Hub2Style.font(Hub2Style.CHAKRA, 600), s, Hub2Style.tracking_px(0.1, s))

	func _draw() -> void:
		var kh := Hub2Style.px(20)
		var top := roundf((size.y - kh) * 0.5)
		var kr := Rect2(0, top, _kbd_w(), kh)
		draw_rect(kr, Hub2Style.KEYCAP_BG)
		var mf := Hub2Style.font(Hub2Style.MONO, 700)
		var ms := Hub2Style.fs(10)
		var x := Hub2Style.px(5)
		for ch in keys:
			var cw := Hub2Style.text_width(ch, mf, ms)
			if ch == " ":
				x += cw
				continue
			if mf.has_char(ch.unicode_at(0)):
				Hub2Style.draw_text(self, mf, Vector2(x, Hub2Style.baseline(mf, ms, top, kh)), ch, ms, Hub2Style.INK)
			else:
				_triangle(Rect2(x, top, cw, kh), ch)
			x += cw
		Hub2ArsenalDraw.text(self, label, Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.6), 0.1, kr.end.x + Hub2Style.px(6),
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 12, 0.0, size.y))

	## Flèche ◄ ► ▲ ▼ dessinée (police sans ce glyphe).
	func _triangle(r: Rect2, ch: String) -> void:
		var c := r.get_center()
		var e := minf(r.size.x, r.size.y) * 0.32
		var pts: PackedVector2Array
		match ch:
			"◄":
				pts = [c + Vector2(-e, 0), c + Vector2(e, -e), c + Vector2(e, e)]
			"►":
				pts = [c + Vector2(e, 0), c + Vector2(-e, -e), c + Vector2(-e, e)]
			"▲":
				pts = [c + Vector2(0, -e), c + Vector2(e, e), c + Vector2(-e, e)]
			_:
				pts = [c + Vector2(0, e), c + Vector2(e, -e), c + Vector2(-e, -e)]
		draw_colored_polygon(pts, Hub2Style.INK)


## Vue d'ensemble de tous les niveaux (36 px, filet à 11 px ; niveaux
## répartis (space-between), 34 px chacun, padding 3 0 : losange 7 px puis,
## à 5 px, le niveau JetBrains Mono 11 px 700) ; fenêtre visible surlignée
## (rgba(255,255,255,.07)), niveau choisi jaune ; clic : saut.
class Overview extends Control:
	var panel: Node

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _ready() -> void:
		custom_minimum_size.y = Hub2Style.px(36)

	func _rail() -> Hub2ArsenalRail:
		return panel.get("rail") if panel else null

	## Largeur d'un niveau et pas entre deux niveaux.
	func _metrics(n: int) -> Vector2:
		var iw := minf(Hub2Style.px(34), size.x / maxf(float(n), 1.0))
		var step := (size.x - iw) / float(n - 1) if n > 1 else 0.0
		return Vector2(iw, step)

	func item_rect(i: int) -> Rect2:
		var r := _rail()
		var n := r.levels.size() if r else 0
		var m := _metrics(n)
		var ih := Hub2Style.px(3) * 2.0 + Hub2Style.px(7) + Hub2Style.px(5) + Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 11)
		var top := (size.y - ih) * 0.5
		return Rect2(roundf(i * m.y), top, m.x, ih)

	func _draw() -> void:
		draw_rect(Rect2(0, Hub2Style.px(11), size.x, maxf(Hub2Style.px(1), 1.0)), Hub2Style.white_a(0.16))
		var r := _rail()
		if r == null:
			return
		var sl := r.selected_level()
		for i in r.levels.size():
			var ir := item_rect(i)
			var vis := r.is_visible_col(i)
			var on := r.levels[i] == sl
			if vis:
				draw_rect(ir, Hub2Style.white_a(0.07))
			var dc := Vector2(ir.get_center().x, ir.position.y + Hub2Style.px(3) + Hub2Style.px(3.5))
			Hub2ArsenalDraw.draw_diamond(self, dc, Hub2Style.px(7),
					Hub2Style.YELLOW if on else (Hub2Style.text_a(0.8) if vis else Hub2Style.text_a(0.3)))
			var t := str(r.levels[i])
			var mf := Hub2Style.font(Hub2Style.MONO, 700)
			var ms := Hub2Style.fs(11)
			var tw := Hub2Style.text_width(t, mf, ms)
			if tw <= ir.size.x + Hub2Style.px(2) or on:
				var ty := ir.position.y + Hub2Style.px(3) + Hub2Style.px(7) + Hub2Style.px(5)
				var lh := Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 11)
				Hub2Style.draw_text(self, mf, Vector2(roundf(ir.get_center().x - tw * 0.5),
						roundf(Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 11, ty, lh))), t, ms,
						Hub2Style.YELLOW if on else (Hub2Style.TEXT if vis else Hub2Style.text_a(0.5)))

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var r := _rail()
			if r == null:
				return
			var best := -1
			var best_d := INF
			for i in r.levels.size():
				var d := absf(item_rect(i).get_center().x - mb.position.x)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				accept_event()
				panel.call("jump", best)


## Nom de la fiche (Chakra Petch 36 px 700 0,03em, line-height 1, coupé
## « … ») et « NIV. N » (JetBrains Mono 14 px, 70 %) à droite, même ligne
## de base (align-items: baseline ; justify-content: space-between).
class HeadLine extends Control:
	var title := ""
	var level := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var s := Hub2Style.fs(36)
		# Hauteur de la ligne : boîte du titre (line-height 1) et celle du
		# niveau alignées sur la ligne de base.
		var base := Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 36, 0.0, float(s))
		var mb := Hub2ArsenalDraw.css_metrics(Hub2Style.MONO, 500).y * Hub2Style.fs(14)
		custom_minimum_size.y = roundf(maxf(float(s), base + mb))

	func _draw() -> void:
		var s := Hub2Style.fs(36)
		var base := roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 36, 0.0, float(s)))
		var mf := Hub2Style.font(Hub2Style.MONO, 500)
		var ms := Hub2Style.fs(14)
		var lw := Hub2Style.text_width(level, mf, ms)
		Hub2Style.draw_text(self, mf, Vector2(roundf(size.x - lw), roundf(base)), level, ms, Hub2Style.text_a(0.7))
		# Jamais coupé : un nom trop long rapetisse (36 -> 20 px), même ligne
		# de base.
		Hub2ArsenalDraw.text(self, title, Hub2Style.CHAKRA, 700, title_size(size.x - lw - Hub2Style.px(10)), Hub2Style.TEXT, 0.03,
				0.0, base)

	## Taille (px de la maquette) à laquelle le nom tient dans `room`.
	func title_size(room: float) -> float:
		var sz := 36.0
		while sz > 20.0:
			var s := Hub2Style.fs(sz)
			if Hub2Style.text_width(title, Hub2Style.font(Hub2Style.CHAKRA, 700), s, Hub2Style.tracking_px(0.03, s)) <= room:
				break
			sz -= 1.0
		return sz


## « RARETÉ · CLASSE » (Chakra Petch 13 px 700 0,14em) : <span> dans un
## bloc en Barlow 16 px ; la ligne a la hauteur de cette police (strut) et
## le texte est posé sur sa ligne de base, comme dans le navigateur.
class StrutText extends Control:
	var text := ""
	var color := Hub2Style.TEXT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _metrics() -> Vector3:
		var sm := Hub2ArsenalDraw.css_metrics(Hub2Style.BARLOW, 400) * float(Hub2Style.fs(16))
		var m := Hub2ArsenalDraw.css_metrics(Hub2Style.CHAKRA, 700) * float(Hub2Style.fs(13))
		var asc := maxf(sm.x, m.x)
		var desc := maxf(sm.y, m.y)
		return Vector3(asc, desc, asc + desc)

	func _ready() -> void:
		custom_minimum_size.y = roundf(_metrics().z)

	func _draw() -> void:
		Hub2ArsenalDraw.text(self, text, Hub2Style.CHAKRA, 700, 13, color, 0.14, 0.0, roundf(_metrics().x), size.x)


## Rendu de la fiche : 118 px de haut, contain, drop-shadow 0 8 12
## rgba(0,0,0,.6) ; SCORE en bas à droite (bottom 4) : libellé Chakra Petch
## 11 px 600 0,18em (55 %) sur le nombre JetBrains Mono 26 px 700
## (line-height 1). Pièce : pixel art à la place du rendu.
class RenderView extends Control:
	var tex: Texture2D
	var part := false
	var score := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		custom_minimum_size.y = Hub2Style.px(118)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if part:
			Hub2ArsenalDraw.draw_part_art(self, r, maxf(roundf(Hub2Style.px(10)), 3.0))
		else:
			Hub2ArsenalDraw.draw_render(self, tex, r, Hub2Style.px(8), Hub2Style.px(12), 0.6)
		var mf := Hub2Style.font(Hub2Style.MONO, 700)
		var ms := Hub2Style.fs(26)
		var bottom := size.y - Hub2Style.px(4)
		var sw := Hub2Style.text_width(score, mf, ms)
		var nb := Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 26, bottom - float(ms), float(ms))
		Hub2Style.draw_text(self, mf, Vector2(roundf(size.x - sw), roundf(nb)), score, ms, Hub2Style.TEXT)
		var lf := Hub2Style.font(Hub2Style.CHAKRA, 600)
		var ls := Hub2Style.fs(11)
		var tr := Hub2Style.tracking_px(0.18, ls)
		var lw := Hub2Style.text_width("SCORE", lf, ls, tr)
		var llh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 600, 11)
		Hub2Style.draw_text(self, lf, Vector2(roundf(size.x - lw),
				roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 11, bottom - float(ms) - llh, llh))), "SCORE", ls, Hub2Style.text_a(0.55), tr)


## Tirets 1 px rgba(255,255,255,.18) d'un emplacement libre.
class Dashed extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Hub2ArsenalDraw.draw_dashed_rect(self, Rect2(Vector2.ZERO, size), Hub2Style.white_a(0.18), maxf(Hub2Style.px(1), 1.0))
