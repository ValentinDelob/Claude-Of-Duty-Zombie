class_name HubCodexPanel
extends HubPanel
## Onglet CODEX (bestiaire, GAME_CONCEPT §4.17 ; docs/HUB_PLAN.md §3.10) :
## une fiche par type d'ennemi (CodexData, assets/data/hub/codex.json), en
## grille de 4 colonnes, dans le style du hub (HubBox, HubSlot, HubTag).
##   - ennemi RENCONTRÉ (CodexState du profil : coup porté ou reçu,
##     élimination) : nom, famille et manche d'apparition, description,
##     nombre d'éliminations, XP de base (XpRules), échantillons ;
##   - ennemi INCONNU : fiche grisée en pointillés, « ??? » et seulement la
##     manche à partir de laquelle il peut apparaître (la curiosité pousse à
##     aller plus loin).
## Pastille NOUVEAU : fiche découverte depuis la dernière visite ; l'onglet
## porte leur nombre (badge) ; elles sont marquées vues à l'affichage de
## l'onglet et enregistrées en le quittant (comme l'ARSENAL).
## Navigation : flèches / stick / croix entre les fiches (voisins de focus de
## Godot dans la grille), souris ; aucune action sur une fiche.

const COLUMNS := 4
const CARD_H := 236.0
const GAP := 12.0
## Couleur du texte d'une fiche inconnue.
const UNKNOWN_TEXT := Color("6D6A63")

var data: CodexData
var box: HubBox
## Fiches affichées, dans l'ordre (CodexCard).
var cards: Array = []
var _grid: GridContainer
## Fiches NOUVEAU affichées pendant cette visite (gardées jusqu'au départ).
var _seen_now: Dictionary = {}
var _pending_seen := false


func build() -> void:
	if data == null:
		data = CodexData.default()
	box = HubBox.new(Lang.t("BESTIAIRE DU SCIENTIFIQUE", "THE SCIENTIST'S BESTIARY"), "")
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(HubStyle.px(GAP)))
	_grid.add_theme_constant_override("v_separation", int(HubStyle.px(GAP)))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Marge droite élargie : l'anneau de focus (3 px + ombre) reste visible.
	box.content.add_child(HubBox.pad(_grid, 14, 14, 18, 18))
	_fill()


func refresh() -> void:
	var keep := _focused_index()
	_fill()
	if keep >= 0 and is_visible_in_tree() and hub:
		hub.focus_later(cards[mini(keep, cards.size() - 1)])


func _fill() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	cards.clear()
	var pr := profile()
	var known := 0
	for e in data.entries:
		var id := String(e.id)
		var is_known := pr != null and pr.codex.is_known(id)
		if is_known:
			known += 1
		var card := CodexCard.make(e, pr, _seen_now.has(id) or (pr != null and pr.codex.is_new(id)))
		card.chosen.connect(_on_card_chosen.bind(card))
		_grid.add_child(card)
		cards.append(card)
	box.set_right(Lang.t("%d / %d rencontrés", "%d / %d encountered") % [known, data.entries.size()])


## Fiche de l'ennemi `id` (null s'il n'y en a pas ; tests).
func card_of(id: String) -> CodexCard:
	for c in cards:
		if c.id == id:
			return c
	return null


func _on_card_chosen(card: CodexCard) -> void:
	if hub:
		hub.set_hint(card.hint)


func _focused_index() -> int:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return cards.find(f)


## Fiches nouvelles marquées vues (enregistrées en quittant l'onglet) ; la
## pastille reste affichée pendant la visite.
func _mark_seen() -> void:
	var pr := profile()
	if pr == null:
		return
	for e in data.entries:
		var id := String(e.id)
		if pr.codex.is_new(id):
			_seen_now[id] = true
			pr.codex.mark_seen(id)
			_pending_seen = true


# --------------------------------------------------------------------------
# HubPanel
# --------------------------------------------------------------------------

func first_focus() -> Control:
	return cards[0] if not cards.is_empty() else null


func prompts() -> Array:
	return [[HubPrompts.TABS, Lang.t("Onglets", "Tabs")], [HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]


func badge() -> int:
	var pr := profile()
	return pr.codex.new_count(data.ids()) if pr and data else 0


func shown() -> void:
	_mark_seen()
	# Pastille de l'onglet : les fiches sont vues dès l'affichage.
	if hub and hub.has_method("refresh_badges"):
		hub.refresh_badges()


func hidden() -> void:
	_seen_now.clear()
	if _pending_seen:
		_pending_seen = false
		if hub:
			hub.save_profile()


## Fiche d'un ennemi (HubSlot vertical : focus, anneau jaune, clic).
class CodexCard extends HubSlot:
	var id := ""
	var known := false

	static func make(e: Dictionary, pr: PlayerProfile, is_new: bool) -> CodexCard:
		var c := CodexCard.new(CARD_H, true, 6.0)
		c.id = String(e.id)
		c.known = pr != null and pr.codex.is_known(c.id)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.click_activates = false
		c.box.alignment = BoxContainer.ALIGNMENT_BEGIN
		if c.known:
			c._build_known(e, pr, is_new)
		else:
			c._build_unknown(e)
		return c

	func _build_known(e: Dictionary, pr: PlayerProfile, is_new: bool) -> void:
		var head := HubBox.hbox(6)
		var n := HubStyle.label(HubData.text_of(e.name).to_upper(), 18, HubStyle.PAPER, "impact", true, 0.04)
		n.clip_text = true
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(n)
		if is_new:
			head.add_child(HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW))
		box.add_child(head)
		box.add_child(HubStyle.label(HubCodexPanel.family_line(e), 12, HubStyle.YELLOW, "semi"))
		var d := HubStyle.label(HubData.text_of(e.text), 13, HubStyle.PLASTER)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(d)
		var stats := HubBox.hbox(14)
		stats.add_child(_stat(Lang.t("ÉLIMINÉS", "KILLED"), HubStyle.num(pr.codex.kills(id)), HubStyle.PAPER))
		stats.add_child(_stat("XP", HubStyle.num(CodexData.xp(e)), HubStyle.XP_BLUE))
		box.add_child(stats)
		var sm := HubBox.hbox(8)
		var samples: PackedStringArray = e.samples
		if samples.is_empty():
			sm.add_child(HubStyle.label(Lang.t("Aucun échantillon", "No samples"), 12, HubStyle.DIM, "semi"))
		for s in samples:
			var chip := HubBox.hbox(4)
			chip.add_child(HubIcon.make(HubIcon.sample_art(s), 2))
			var l := HubStyle.label(CodexData.sample_name(s), 11, HubStyle.GREEN, "semi")
			chip.add_child(l)
			sm.add_child(chip)
		box.add_child(sm)
		var names := PackedStringArray()
		for s in samples:
			names.append(CodexData.sample_name(s).to_lower())
		if names.is_empty():
			hint = Lang.t("Cet ennemi ne laisse aucun échantillon.", "This enemy leaves no samples.")
		else:
			hint = Lang.t("Échantillons : %s.", "Samples: %s.") % ", ".join(names)

	func _build_unknown(e: Dictionary) -> void:
		empty = true
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var q := HubStyle.label("???", 34, UNKNOWN_TEXT, "impact", false, 0.1)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(q)
		var r := HubStyle.label(HubCodexPanel.round_hint(int(e.round)), 13, HubStyle.DIM, "semi")
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(r)
		hint = Lang.t("Ennemi inconnu : touchez-le ou laissez-le vous toucher en partie pour remplir sa fiche.",
				"Unknown enemy: hit it, or let it hit you, in a match to fill in its entry.")

	func _stat(title: String, value: String, col: Color) -> HBoxContainer:
		var h := HubBox.hbox(5)
		var t := HubStyle.label(title, 11, HubStyle.DIM, "bold", false, 0.06)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		h.add_child(HubStyle.label(value, 16, col, "bold"))
		return h


## « ZOMBIE · DÈS LA MANCHE 4 » : famille (XpRules) et manche d'apparition.
static func family_line(e: Dictionary) -> String:
	var id := String(e.id)
	var cat := XpRules.category_of(id) if XpRules.is_enemy(id) else XpRules.category_of(String(e.get("xp_ref", "")))
	var fam := ""
	match cat:
		XpRules.SPECIAL:
			fam = Lang.t("VAGUE SPÉCIALE", "SPECIAL WAVE")
		XpRules.MINIBOSS:
			fam = "MINI-BOSS"
		XpRules.BOSS:
			fam = "BOSS"
		_:
			fam = "ZOMBIE"
	return fam + " · " + Lang.t("DÈS LA MANCHE %d", "FROM ROUND %d") % int(e.round)


## Indice d'une fiche inconnue : « Peut apparaître dès la manche 20 ».
static func round_hint(round_n: int) -> String:
	if round_n <= 1:
		return Lang.t("Rôde dès la première manche", "Lurks from the very first round")
	return Lang.t("Peut apparaître dès la manche %d", "May appear from round %d") % round_n
