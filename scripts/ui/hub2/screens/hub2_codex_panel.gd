class_name Hub2CodexPanel
extends Hub2Panel
## CODEX (docs/hub_v2/Codex.dc.html) : rendus des ennemis (silhouette noire si
## inconnu), fiche avec taux de butin par échantillon.
##
## Gauche : « BESTIAIRE » + « x / y rencontrés », grille de 3 cartes
## (CodexData.cards() : un groupe du fichier, « Les zombies », est UNE carte) :
## rendu de 150 px (inconnu : silhouette noire, « ? », « INCONNU », bordure en
## pointillés), famille à sa couleur, « MANCHE N », nom ; pastille NOUVEAU
## (fiche découverte depuis la dernière visite : vue à l'affichage de
## l'onglet, enregistrée en le quittant, comme l'ancien codex).
## Droite (fiche, 392 px) : grand rendu, « FAMILLE · DÈS LA MANCHE N », nom,
## description, Éliminés, XP par élimination (XpRules), ÉCHANTILLONS · TAUX
## DE BUTIN (LootRules : SAMPLE_CHANCE, BOSS_SAMPLE_CHANCE).
## Navigation : flèches / croix / stick (le focus choisit la carte), clic ;
## stick droit / molette : la fiche défile (130 %).
## Page DÉTAILS (demande du 2026-10-12, docs/hub_v2/README.md) : A / Entrée
## ou clic sur la carte déjà choisie, « DÉTAILS ▾ » en haut à droite du rendu,
## D / R3 : la description, Éliminés / XP et le butin glissent et laissent la
## place (≈ 0,26 s) à CodexDetails (ce qu'il te fait, résistance, quand il
## apparaît, ce qu'il rapporte, butin, point faible, conseil ; verrouillée si
## inconnu) ; A, B / Échap, « RETOUR ▴ » : retour animé à la fiche.

## Familles (catégories de XpRules) : nom [fr, en] et couleur (maquette).
const FAMILY := {
	XpRules.COMMON: ["ZOMBIE", "ZOMBIE", "C9C7BE"],
	XpRules.SPECIAL: ["VAGUE SPÉCIALE", "SPECIAL WAVE", "4FE3C1"],
	XpRules.MINIBOSS: ["MINI-BOSS", "MINI-BOSS", "4D9BFF"],
	XpRules.BOSS: ["BOSS", "BOSS", "FF9A1F"],
}
## Grille de la maquette : 3 cartes de 262,7 px, écart 12.
const COLUMNS := 3
const CARD_W := 262.67
const GAP := 12.0

var data: CodexData
## Colonnes affichées (moins qu'à la maquette à une grande TAILLE DES MENUS).
var columns := COLUMNS
## Cartes (CodexData.cards()), dans l'ordre affiché.
var entries: Array[Dictionary] = []
## Carte choisie (identifiant de carte : fiche ou groupe).
var selected_id := ""
## Identifiant de carte -> Hub2Button.
var cards: Dictionary = {}
var header_count: Hub2Text
var list_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var _grid: GridContainer
var _detail: VBoxContainer
var _title: Hub2Text
## Types NOUVEAU affichés pendant cette visite (pastille gardée jusqu'au départ).
var _seen_now: Dictionary = {}
var _pending_seen := false

## Page DÉTAILS affichée à la place de la fiche (gardée en changeant de
## carte, refermée en quittant l'onglet).
var details_open := false
## « DÉTAILS ▾ » / « RETOUR ▴ » en haut à droite du rendu de la fiche.
var details_toggle: Hub2WeaponDetails.Title
## Bascule fiche <-> DÉTAILS en cours (tests, captures).
var anim_running := false
## Durées (s) de la bascule : sortie (ease-in) puis entrée (ease-out) ;
## glissements (px de la maquette) et échelle de départ du contenu entrant.
const ANIM_OUT := 0.08
const ANIM_IN := 0.18
const ANIM_SHIFT_OUT := 12.0
const ANIM_SHIFT_IN := 18.0
const ANIM_SCALE := 0.97
## Invite de la page DÉTAILS ouverte (A / Entrée ou B / Échap : retour).
const PROMPT_CLOSE := "codex_close_details"
var _slide: SlideBox
var _body: VBoxContainer
var _anim: Tween
var _anim_dir := 1.0
var _anim_swapped := true
## Carte choisie par le clic en cours (le relâchement ne bascule pas).
var _click_select := ""


static func family_name(cat: String) -> String:
	var f: Array = FAMILY.get(cat, FAMILY[XpRules.COMMON])
	return Lang.t(f[0], f[1])


static func family_color(cat: String) -> Color:
	return Color(String((FAMILY.get(cat, FAMILY[XpRules.COMMON]) as Array)[2]))


func build() -> void:
	if data == null:
		data = CodexData.default()
	# <section> : 1280 − 2 × 28 − 20 − 392 = 812 px à 100 %.
	var w: float = hub.size.x if hub and hub.size.x > 0.0 else Hub2Style.SCREEN.x
	columns = Hub2ItemsUi.columns_for(COLUMNS, CARD_W, GAP, w - Hub2Style.px(2 * Hub2Style.SIDE) - Hub2Style.px(20) - Hub2Style.px(392))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(20)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_main(row)
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sec)
	sec.add_child(_header())
	list_scroll = Hub2ItemsUi.scroller()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sec.add_child(list_scroll)
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", int(Hub2Style.px(GAP)))
	_grid.add_theme_constant_override("v_separation", int(Hub2Style.px(GAP)))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_scroll.add_child(_grid)
	var aside := Hub2Box.new()
	aside.glass(Hub2Style.GLASS_STRONG, Hub2Style.LINE, 1.0)
	aside.pad(1)
	aside.custom_minimum_size.x = Hub2Style.px(392)
	row.add_child(aside)
	detail_scroll = Hub2ItemsUi.scroller()
	aside.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 0)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_scroll.add_child(_detail)
	_fill()


func _header() -> Control:
	var h := Control.new()
	h.custom_minimum_size.y = Hub2Style.px(34)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Hub2Text.new()
	_title.setup(Lang.t("BESTIAIRE", "BESTIARY"), Hub2Style.CHAKRA, 700, 22, Hub2Style.TEXT, 0.06)
	h.add_child(_title)
	header_count = Hub2Text.new()
	header_count.setup("", Hub2Style.MONO, 500, 13, Hub2Style.text_a(0.55))
	h.add_child(header_count)
	var place := func() -> void:
		var ta := _title.get_font().get_ascent(_title.size_px())
		var ca := header_count.get_font().get_ascent(header_count.size_px())
		_title.position = Vector2.ZERO
		_title.size = _title.get_combined_minimum_size()
		header_count.position = Vector2(_title.size.x + Hub2Style.px(16), roundf(ta - ca))
		header_count.size = header_count.get_combined_minimum_size()
	h.resized.connect(place)
	header_count.minimum_size_changed.connect(place)
	return h


# --------------------------------------------------------------------------
# État d'une carte (profil)
# --------------------------------------------------------------------------

## Carte rencontrée : au moins une de ses fiches l'est.
func is_known(card: Dictionary) -> bool:
	var pr := profile()
	if pr == null:
		return false
	for m in card.members:
		if pr.codex.is_known(m):
			return true
	return false


## Pastille NOUVEAU : une de ses fiches découverte depuis la dernière visite.
func is_new(card: Dictionary) -> bool:
	var pr := profile()
	for m in card.members:
		if _seen_now.has(m) or (pr != null and pr.codex.is_new(m)):
			return true
	return false


## Éliminations de la carte (somme de ses fiches).
func kills(card: Dictionary) -> int:
	var pr := profile()
	var n := 0
	for m in card.members:
		n += pr.codex.kills(m) if pr else 0
	return n


## « 4 » ou « 1 à 3 » (XpRules, XP de base d'une élimination).
static func xp_text(card: Dictionary) -> String:
	if int(card.xp_min) == int(card.xp_max):
		return Hub2Style.num(int(card.xp_max))
	return Lang.t("%s à %s", "%s to %s") % [Hub2Style.num(int(card.xp_min)), Hub2Style.num(int(card.xp_max))]


func card_entry(id: String) -> Dictionary:
	for c in entries:
		if c.id == id:
			return c
	return {}


# --------------------------------------------------------------------------
# Grille
# --------------------------------------------------------------------------

func refresh() -> void:
	if not built:
		return
	var had := _focused_id()
	_fill()
	if had != "" and cards.has(had) and is_visible_in_tree() and hub:
		hub.call("focus_later", cards[had])


func _fill() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	cards.clear()
	entries = data.cards()
	var known := 0
	var list := []
	for e in entries:
		if is_known(e):
			known += 1
		var b := _card(e)
		_grid.add_child(b)
		list.append(b)
	Hub2ItemsUi.link_rows(Hub2ItemsUi.rows_of(list, columns))
	var cells := list.duplicate()
	var n := entries.size()
	while n % columns != 0:
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(pad)
		cells.append(pad)
		n += 1
	Hub2ItemsUi.equal_columns(list_scroll, cells, columns, GAP)
	header_count.text = Lang.t("%d / %d rencontrés", "%d / %d encountered") % [known, entries.size()]
	if selected_id == "" or not cards.has(selected_id):
		selected_id = _default_selection()
	_show_selection()


## Première carte nouvelle, sinon la première connue la plus avancée… sinon la
## première.
func _default_selection() -> String:
	for e in entries:
		if is_new(e):
			return e.id
	for e in entries:
		if is_known(e):
			return e.id
	return entries[0].id if not entries.is_empty() else ""


func _card(e: Dictionary) -> Hub2Button:
	var known := is_known(e)
	var b := Hub2Button.new()
	b.name = "Enemy_" + String(e.id)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.box.pad(11, 15, 15, 15)  # border 1 px + padding 10 14 14
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(v)
	# Rendu : 150 px de haut, image de 140 px en bas, centrée, rognée.
	var area := Control.new()
	area.custom_minimum_size.y = Hub2Style.px(150)
	area.clip_contents = true
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(area)
	var img := Hub2ShadowRender.new()
	img.texture = HubRenders.enemy(String(e.members[0]) if not HubRenders.has(HubRenders.enemy_path(e.id)) else String(e.id))
	img.fixed_height = 140
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	if known:
		img.drop_shadow(8, 10, 0.6)
	else:
		img.silhouette = 0.55
	img.name = "Render"
	area.add_child(img)
	if not known:
		var q := Hub2Text.new()
		q.setup("?", Hub2Style.CHAKRA, 700, 40, Hub2Style.text_a(0.35))
		q.align = HORIZONTAL_ALIGNMENT_CENTER
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.name = "Unknown"
		area.add_child(q)
	if is_new(e):
		area.add_child(_new_badge())
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	var fam := Hub2Text.new()
	fam.setup(family_name(e.category) if known else Lang.t("INCONNU", "UNKNOWN"), Hub2Style.CHAKRA, 700, 11,
			family_color(e.category) if known else Hub2Style.text_a(0.35), 0.16)
	fam.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fam.name = "Family"
	line.add_child(fam)
	var rd := Hub2Text.new()
	rd.setup(Lang.t("MANCHE %d", "ROUND %d") % int(e.round), Hub2Style.MONO, 500, 11, Hub2Style.text_a(0.5))
	line.add_child(rd)
	var nm := Hub2Text.new()
	nm.setup(HubData.text_of(e.name) if known else "???", Hub2Style.CHAKRA, 700, 18,
			Hub2Style.TEXT if known else Hub2Style.text_a(0.5), 0.02)
	nm.name = "Name"
	v.add_child(nm)
	if not known:
		# border: 1px dashed rgba(255, 255, 255, 0.16), entre le fond et le
		# cadre de focus.
		var dash := Control.new()
		dash.name = "Dashes"
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dash.set_anchors_preset(Control.PRESET_FULL_RECT)
		dash.draw.connect(func(): Hub2ItemsUi.draw_dashes(dash, Hub2Style.white_a(0.16)))
		b.add_child(dash)
		b.move_child(dash, 1)
	b.set_meta("card", String(e.id))
	b.focus_entered.connect(_on_card_focus.bind(String(e.id)))
	b.pressed.connect(_on_card_pressed.bind(String(e.id)))
	cards[String(e.id)] = b
	return b


## Pastille NOUVEAU (en haut à gauche du rendu).
func _new_badge() -> Control:
	var tag := Hub2Box.new()
	tag.flat(Hub2Style.YELLOW)
	tag.pad(2, 6)
	tag.name = "New"
	tag.position = Vector2.ZERO
	var t := Hub2Text.new()
	t.setup(Lang.t("NOUVEAU", "NEW"), Hub2Style.CHAKRA, 700, 10, Hub2Style.INK, 0.16)
	tag.add_child(t)
	tag.size = tag.get_combined_minimum_size()
	return tag


## Focus (flèches, stick, clic) : la carte est choisie ; un clic qui la
## choisit ne bascule pas la page DÉTAILS en se relâchant.
func _on_card_focus(id: String) -> void:
	if id != selected_id and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_click_select = id
	_select(id)


## A / Entrée / clic sur une carte : une autre carte est choisie ; la carte
## déjà choisie ouvre ou ferme la page DÉTAILS.
func _on_card_pressed(id: String) -> void:
	if _click_select == id:
		_click_select = ""
		return
	_click_select = ""
	if id != selected_id:
		_select(id)
		return
	toggle_details()


func _select(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	_show_selection()


func _show_selection() -> void:
	for id in cards:
		var e := card_entry(id)
		var on: bool = id == selected_id
		var known := is_known(e)
		var b: Hub2Button = cards[id]
		var line := Hub2Style.LINE
		if not known:
			line = Color(0, 0, 0, 0)  # pointillés dessinés à part
		elif on:
			line = Hub2Style.YELLOW
		b.box.glass(Hub2Style.yellow_a(0.1) if on else Hub2Style.GLASS, line, 1.0)
	_show_detail(card_entry(selected_id))


# --------------------------------------------------------------------------
# Fiche
# --------------------------------------------------------------------------

func _show_detail(e: Dictionary) -> void:
	_stop_anim()
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	_body = null
	_slide = null
	details_toggle = null
	if e.is_empty():
		return
	var known := is_known(e)
	var fam_col := family_color(e.category)
	# Rendu : hauteur 190 + padding-top 12 + liseré 3 (boîte CSS content-box) ;
	# inconnu : toute la tête en brightness(0) opacity(0.55) (liseré compris).
	var head := Hub2Box.new()
	head.flat(Color(0, 0, 0, 0), fam_col if known else Color(0, 0, 0, 0.2 * 0.55), 0.0)
	head.border = Vector4(0, 3, 0, 0)
	head.pad(15, 0, 0, 0)
	head.name = "Head"
	_detail.add_child(head)
	var area := Control.new()
	area.custom_minimum_size.y = Hub2Style.px(190)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(area)
	var img := Hub2ShadowRender.new()
	img.texture = HubRenders.enemy(String(e.members[0]) if not HubRenders.has(HubRenders.enemy_path(e.id)) else String(e.id))
	img.fixed_height = 190
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.name = "Render"
	if known:
		img.drop_shadow(10, 16, 0.6)
	else:
		img.silhouette = 0.55
	area.add_child(img)
	# DÉTAILS ▾ / RETOUR ▴ (style des titres « DÉTAILS » des fiches d'arme),
	# en haut à droite du rendu : n'ajoute rien à la mise en page de la fiche.
	details_toggle = Hub2WeaponDetails.Title.new()
	details_toggle.name = "DetailsToggle"
	details_toggle.clicked.connect(toggle_details)
	area.add_child(details_toggle)
	_update_toggle()
	# Famille, nom : padding 14 20 (12 sous la description), écart 6.
	var info := MarginContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Hub2InventoryPanel._margins(info, 14, 20, 0, 20)
	_detail.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(iv)
	var fam := Hub2ItemsUi.kicker("%s · %s" % [family_name(e.category) if known else Lang.t("INCONNU", "UNKNOWN"),
			Lang.t("DÈS LA MANCHE %d", "FROM ROUND %d") % int(e.round)], 11, 700, fam_col if known else Hub2Style.text_a(0.35), 0.16)
	fam.name = "Family"
	iv.add_child(fam)
	var title := Hub2ItemsUi.para(HubData.text_of(e.name) if known else "???", 30, Hub2Style.TEXT, 1.0)
	title.add_theme_font_override("font", Hub2Style.font(Hub2Style.CHAKRA, 700))
	title.add_theme_constant_override("line_spacing", roundi(Hub2Style.px(30) - Hub2Style.line_height(Hub2Style.font(Hub2Style.CHAKRA, 700), Hub2Style.fs(30))))
	title.name = "Title"
	iv.add_child(title)
	# Corps : la fiche (description, Éliminés / XP, butin) ou la page DÉTAILS.
	_slide = SlideBox.new()
	_slide.name = "Slide"
	_detail.add_child(_slide)
	_fill_body(e)


## Corps de la fiche ou de la page DÉTAILS (selon details_open) dans _slide.
func _fill_body(e: Dictionary) -> void:
	if _slide == null:
		return
	for c in _slide.get_children():
		_slide.remove_child(c)
		c.queue_free()
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.name = "DetailsPage" if details_open else "Sheet"
	_slide.add_child(_body)
	if details_open:
		_details_page(e)
	else:
		_sheet(e)


## Fiche de la maquette : description (margin-top 4 sous l'écart 6, 12 en
## bas), Éliminés / XP par élimination, échantillons et taux de butin.
func _sheet(e: Dictionary) -> void:
	var known := is_known(e)
	var pm := MarginContainer.new()
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Hub2InventoryPanel._margins(pm, 10, 20, 12, 20)
	var text := HubData.text_of(e.text) if known else Lang.t("Pas encore rencontré. Il peut apparaître dès la manche %d.",
			"Not encountered yet. It may show up from round %d.") % int(e.round)
	var p := Hub2ItemsUi.para(text, 15, Hub2Style.text_a(0.78), 1.4)
	p.name = "Text"
	pm.add_child(p)
	_body.add_child(pm)
	# Éliminés, XP par élimination : padding 10 20, 2 colonnes, écart 12.
	var stats := Hub2ItemsUi.section(10, 20, 10, 20, 0)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.get_child(0).add_child(sr)
	sr.add_child(_stat(Lang.t("Éliminés", "Killed"), Hub2Style.num(kills(e)), Hub2Style.TEXT, "Kills"))
	sr.add_child(_stat(Lang.t("XP par élimination", "XP per kill"), xp_text(e) if known else "?", Hub2Style.YELLOW, "Xp"))
	_body.add_child(stats)
	# ÉCHANTILLONS · TAUX DE BUTIN : padding 10 20 14, écart 8.
	var loot := Hub2ItemsUi.section(10, 20, 14, 20, 8)
	var lv: VBoxContainer = loot.get_child(0)
	lv.add_child(Hub2ItemsUi.kicker(Lang.t("ÉCHANTILLONS · TAUX DE BUTIN", "SAMPLES · DROP RATE")))
	if (e.samples as PackedStringArray).is_empty():
		var none := Hub2ItemsUi.para(Lang.t("Aucun échantillon : il ne donne que de la ferraille.", "No samples: it only drops scrap."),
				14, Hub2Style.text_a(0.55))
		none.name = "NoLoot"
		lv.add_child(none)
	for s in e.samples:
		lv.add_child(_loot_row(String(s), known))
	_body.add_child(loot)


## Page DÉTAILS (CodexDetails) : sections au style des blocs de la fiche
## (liseré du haut, padding 10 20 14, libellé de section, écart 8) ; carte
## inconnue : page verrouillée.
func _details_page(e: Dictionary) -> void:
	var page := CodexDetails.of(e, is_known(e), kills(e))
	var gap := Control.new()
	gap.custom_minimum_size.y = Hub2Style.px(12)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(gap)
	if page.locked:
		var sec := Hub2ItemsUi.section(12, 20, 16, 20, 8)
		sec.name = "Locked"
		var v: VBoxContainer = sec.get_child(0)
		v.add_child(Hub2ItemsUi.kicker(Lang.t("DÉTAILS VERROUILLÉS", "DETAILS LOCKED")))
		var t := Hub2ItemsUi.para(Lang.t("Rencontre-le pour en savoir plus.", "Meet it to learn more."), 16, Hub2Style.TEXT, 1.35, 500)
		t.name = "LockedText"
		v.add_child(t)
		if String(page.hint) != "":
			var h := Hub2ItemsUi.para(String(page.hint) + ".", 14, Hub2Style.text_a(0.55), 1.35)
			h.name = "LockedHint"
			v.add_child(h)
		_body.add_child(sec)
		return
	for s in page.sections:
		var sec := Hub2ItemsUi.section(10, 20, 14, 20, 8)
		sec.name = "Section_" + String(s.id)
		var v: VBoxContainer = sec.get_child(0)
		v.add_child(Hub2ItemsUi.kicker(String(s.title)))
		if String(s.text) != "":
			var p := Hub2ItemsUi.para(String(s.text), 15, Hub2Style.text_a(0.78), 1.4)
			p.name = "Text"
			v.add_child(p)
		for r in s.rows:
			v.add_child(_loot_row(String(r.sample), true) if String(r.sample) != "" else _detail_row(r))
		_body.add_child(sec)


## Ligne de la page DÉTAILS : libellé (Barlow 15) et précision (Barlow 12,
## 55 %) à gauche, valeur à droite (Chakra Petch 16 700, couleur du ton :
## dégâts orange, XP jaune, butin turquoise).
func _detail_row(r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.name = "Row_" + String(r.id)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", int(Hub2Style.px(1)))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	var l := Hub2ItemsUi.para(String(r.label), 15, Hub2Style.TEXT, 1.25)
	l.name = "Label"
	left.add_child(l)
	if String(r.note) != "":
		var n := Hub2ItemsUi.para(String(r.note), 12, Hub2Style.text_a(0.55), 1.3)
		n.name = "Note"
		left.add_child(n)
	var col := Hub2Style.TEXT
	match String(r.tone):
		"bad": col = Hub2Style.BAD
		"xp": col = Hub2Style.YELLOW
		"loot": col = Hub2Style.TEAL
	var val := Hub2ItemsUi.para(String(r.value), 16, col, 1.25)
	val.add_theme_font_override("font", Hub2Style.font(Hub2Style.CHAKRA, 700))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Valeur courte sur une ligne ; le libellé à gauche revient à la ligne.
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.size_flags_horizontal = Control.SIZE_SHRINK_END
	val.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	val.name = "Value"
	h.add_child(val)
	return h


# --------------------------------------------------------------------------
# Page DÉTAILS : bascule animée
# --------------------------------------------------------------------------

## Ouvre / ferme la page DÉTAILS de la carte choisie (A sur la carte choisie,
## clic sur la carte choisie ou sur « DÉTAILS », D / R3 ; B / Échap ferme).
func toggle_details() -> void:
	set_details(not details_open)


func set_details(v: bool, animate := true) -> void:
	if v == details_open:
		return
	details_open = v
	_update_toggle()
	if hub:
		hub.call("refresh_prompts")
	if _slide == null:
		return
	if not animate or not is_inside_tree():
		_stop_anim()
		_fill_body(card_entry(selected_id))
		return
	_play_swap(1.0 if v else -1.0)


func _update_toggle() -> void:
	if details_toggle == null:
		return
	details_toggle.text = Lang.t("RETOUR", "BACK") if details_open else Lang.t("DÉTAILS", "DETAILS")
	details_toggle.up = details_open
	details_toggle.tooltip_text = Lang.t("A ou D : détails de l’ennemi (dégâts, résistance, butin…)",
			"A or D: enemy details (damage, toughness, loot…)")
	details_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(Hub2Style.px(14)))


## Animation (≈ 0,26 s) : le contenu glisse et s'efface (ANIM_OUT, ease-in),
## puis le nouveau arrive de l'autre côté en grandissant légèrement
## (ANIM_IN, ease-out cubique) ; `dir` : 1 vers les détails, -1 retour.
func _play_swap(dir: float) -> void:
	_stop_anim()
	_anim_dir = dir
	_anim_swapped = false
	anim_running = true
	_anim = create_tween()
	_anim.tween_method(_anim_step, 0.0, ANIM_OUT + ANIM_IN, ANIM_OUT + ANIM_IN)
	_anim.finished.connect(_end_anim)


func _anim_step(t: float) -> void:
	if _slide == null:
		return
	if t < ANIM_OUT:
		var k := t / ANIM_OUT
		var e := k * k
		_slide.shift = -_anim_dir * Hub2Style.px(ANIM_SHIFT_OUT) * e
		_slide.modulate.a = 1.0 - e
		return
	if not _anim_swapped:
		_anim_swapped = true
		_fill_body(card_entry(selected_id))
		detail_scroll.scroll_vertical = 0
	var k2 := clampf((t - ANIM_OUT) / ANIM_IN, 0.0, 1.0)
	var e2 := 1.0 - pow(1.0 - k2, 3.0)
	_slide.shift = _anim_dir * Hub2Style.px(ANIM_SHIFT_IN) * (1.0 - e2)
	_slide.modulate.a = e2
	if _body:
		_body.pivot_offset = Vector2(_body.size.x * 0.5, 0.0)
		_body.scale = Vector2.ONE * lerpf(ANIM_SCALE, 1.0, e2)


func _end_anim() -> void:
	if not _anim_swapped:
		_fill_body(card_entry(selected_id))
	_reset_anim_state()


func _stop_anim() -> void:
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = null
	_reset_anim_state()


func _reset_anim_state() -> void:
	anim_running = false
	_anim_swapped = true
	if _slide:
		_slide.shift = 0.0
		_slide.modulate.a = 1.0
	if _body:
		_body.scale = Vector2.ONE


## Conteneur qui pose son enfant à sa largeur, décalé de `shift` px (le
## glissement de la page DÉTAILS) ; la mise en page de l'enfant ne remet pas
## son échelle à 1 (contrairement à fit_child_in_rect).
class SlideBox extends Container:
	var shift := 0.0:
		set(v):
			shift = v
			queue_sort()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _get_minimum_size() -> Vector2:
		var m := Vector2.ZERO
		for c in get_children():
			if c is Control and (c as Control).visible:
				m = m.max((c as Control).get_combined_minimum_size())
		return m

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					var cc := c as Control
					cc.position = Vector2(shift, 0.0)
					cc.size = Vector2(size.x, maxf(size.y, cc.get_combined_minimum_size().y))


func _stat(label: String, value: String, color: Color, node_name: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(2)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 1.0
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(Hub2Style.label(label, Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55)))
	var t := Hub2Text.new()
	t.setup(value, Hub2Style.MONO, 700, 20, color)
	t.name = node_name
	v.add_child(t)
	return v


## Ligne de butin : rendu 34 px, nom, taux (turquoise) et note.
func _loot_row(s: String, enemy_known: bool) -> Control:
	var b := Hub2Box.new()
	b.flat(Hub2Style.white_a(0.04))
	b.pad(6, 10)
	b.name = "Loot_" + s
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	var img := Hub2ShadowRender.new()
	img.texture = HubRenders.sample(s)
	img.custom_minimum_size = Hub2Style.pxv(34, 34)
	img.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not SampleCatalog.is_known(profile(), s, data):
		img.silhouette = 0.5
	r.add_child(img)
	var n := Hub2ItemsUi.para(SampleCatalog.display_name(s) if enemy_known else "???", 15, Hub2Style.TEXT)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	n.name = "Name"
	r.add_child(n)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 0)
	rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(rv)
	var lr := SampleCatalog.loot_rate(s, data)
	var rate := Hub2Text.new()
	rate.setup(String(lr.rate) if enemy_known else "?", Hub2Style.MONO, 700, 15, Hub2Style.TEAL)
	rate.align = HORIZONTAL_ALIGNMENT_RIGHT
	rate.size_flags_horizontal = Control.SIZE_SHRINK_END
	rate.name = "Rate"
	rv.add_child(rate)
	if enemy_known:
		var note := Hub2Text.new()
		note.setup(String(lr.note), Hub2Style.BARLOW, 400, 11, Hub2Style.text_a(0.5))
		note.align = HORIZONTAL_ALIGNMENT_RIGHT
		note.size_flags_horizontal = Control.SIZE_SHRINK_END
		note.name = "Note"
		rv.add_child(note)
	return b


func _focused_id() -> String:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return String(f.get_meta("card", "")) if f and f.has_meta("card") else ""


func _process(delta: float) -> void:
	if visible:
		Hub2ItemsUi.pad_scroll(detail_scroll, delta)


## Fiches nouvelles marquées vues (enregistrées en quittant l'onglet) ; la
## pastille reste affichée pendant la visite.
func _mark_seen() -> void:
	var pr := profile()
	if pr == null or data == null:
		return
	for id in data.ids():
		if pr.codex.is_new(id):
			_seen_now[id] = true
			pr.codex.mark_seen(id)
			_pending_seen = true


# --------------------------------------------------------------------------
# Hub2Panel
# --------------------------------------------------------------------------

func first_focus() -> Control:
	return cards.get(selected_id)


## Fiche : A DÉTAILS, B RETOUR ; page DÉTAILS ouverte : A B RETOUR (A et B
## referment la page).
func prompts() -> Array:
	if details_open:
		return [[PROMPT_CLOSE, Lang.t("Retour", "Back"),
			PackedStringArray(Array(Hub2Input.keys_of(Hub2Input.ACCEPT)) + Array(Hub2Input.keys_of(Hub2Input.BACK))),
			Hub2Input.pads_of(Hub2Input.ACCEPT) + Hub2Input.pads_of(Hub2Input.BACK)]]
	return [[Hub2Input.ACCEPT, Lang.t("Détails", "Details")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]


func on_prompt(id: String) -> void:
	if id == PROMPT_CLOSE:
		set_details(false)


## B / Échap / clic droit : la page DÉTAILS se referme d'abord.
func back() -> bool:
	if details_open:
		set_details(false)
		return true
	return false


## D / clic du stick droit (comme la fiche complète d'une arme) : page
## DÉTAILS.
func handle_input(event: InputEvent) -> bool:
	if Hub2Input.is_details(event) and not entries.is_empty():
		toggle_details()
		return true
	return false


func help() -> String:
	return Lang.t("Les fiches sombres attendent ta première rencontre.", "The dark entries await your first encounter.")


func badge() -> bool:
	var pr := profile()
	return pr != null and data != null and pr.codex.new_count(data.ids()) > 0


func shown() -> void:
	_mark_seen()
	if hub:
		hub.call("refresh_badges")


func hidden() -> void:
	set_details(false, false)
	_seen_now.clear()
	if _pending_seen:
		# Enregistré une fois ; refresh() (profil changé) retire les pastilles
		# NOUVEAU de la visite.
		_pending_seen = false
		if hub:
			hub.call("save_profile")


## Pastille de l'onglet CODEX avant le premier affichage de l'écran
## (Hub2Screen.refresh_badges, écran pas encore construit).
static func tab_badge(pr: PlayerProfile) -> bool:
	return pr != null and pr.codex.new_count(CodexData.default().ids()) > 0
