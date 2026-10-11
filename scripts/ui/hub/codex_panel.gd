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
const GAP := 12.0

var data: CodexData
var box: HubBox
## Fiches affichées, dans l'ordre (HubCodexCard).
var cards: Array = []
var _grid: GridContainer
## Fiches NOUVEAU affichées pendant cette visite (gardées jusqu'au départ).
var _seen_now: Dictionary = {}
var _pending_seen := false


func build() -> void:
	if data == null:
		data = CodexData.default()
	box = HubBox.new(Lang.t("BESTIAIRE DE DR BROWN", "DR BROWN'S BESTIARY"), "")
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
		var card := HubCodexCard.new(HubCodexCard.CARD_H, true, 6.0)
		card.fill(e, pr, _seen_now.has(id) or (pr != null and pr.codex.is_new(id)))
		card.chosen.connect(_on_card_chosen.bind(card))
		_grid.add_child(card)
		cards.append(card)
	box.set_right(Lang.t("%d / %d rencontrés", "%d / %d encountered") % [known, data.entries.size()])


## Fiche de l'ennemi `id` (null s'il n'y en a pas ; tests).
func card_of(id: String) -> HubCodexCard:
	for c in cards:
		if c.id == id:
			return c
	return null


func _on_card_chosen(card: HubCodexCard) -> void:
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

