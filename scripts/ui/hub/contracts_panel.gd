class_name HubContractsPanel
extends HubPanel
## Onglet CONTRATS (docs/HUB_PLAN.md §3.4 ; maquette, écrans 5, 6 et 11) :
##   - ACTIFS (3 cases de 300 × 300, case vide « LIBRE ») : demande du
##     scientifique, progression par échantillon, jours restants, récompense
##     au niveau actuel, REMETTRE (ou ce qui manque) et ABANDONNER (deux
##     appuis : « CONFIRMER », rien n'est consommé) ;
##   - PROPOSITIONS DU SCIENTIFIQUE (5 cases de 180 × 190, case vide jusqu'à
##     la prochaine partie) : échantillons demandés, XP, objet, NOUVEAU,
##     ACCEPTER (grisé à 3 contrats actifs, raison dans l'aide) ;
##   - RÉSERVE à droite (HubSamplesColumn) : quantités et conséquence de la
##     remise choisie sur les autres contrats actifs.
## REMETTRE ouvre la fenêtre « contrat remis » (HubRewardPopup).
##
## Règles : ContractRules (lot A) sur le profil en mémoire, puis UNE
## écriture (hub.save_profile) par action. Touches : Entrée / A (bouton
## choisi), Suppr / R / X (abandonner le contrat choisi), Échap / B (annuler
## le deuxième appui, fermer la fenêtre).

## Proportions de la maquette (px à 100 %).
const LEFT_W := 932.0
const RIGHT_W := 300.0
const ACTIVE_H := 300.0
const OFFER_H := 190.0

var data: HubData
var day := 0
var active_cards: Array[HubContractCard] = []
var offer_cards: Array[HubContractCard] = []
var column: HubSamplesColumn
var popup: HubRewardPopup
## Contrat dont l'abandon attend le deuxième appui ("" : aucun).
var confirm_id := ""
var active_count_label: Label
var offers_count_label: Label
var _root: HBoxContainer
var _scroll: ScrollContainer
var _left: VBoxContainer


func build() -> void:
	data = HubContractsView.data()
	day = HubContractsView.today()
	_root = HubBox.hbox(16)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# Partie gauche : défile à 130 % (rien ne sort de l'écran).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = LEFT_W
	HubBox.style_scrollbar(_scroll.get_v_scroll_bar())
	_root.add_child(_scroll)
	_left = HubBox.vbox(0)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_left)
	column = HubSamplesColumn.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = RIGHT_W
	_root.add_child(column)
	_fill()


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Le profil a changé : tout est reconstruit, le focus reste sur le même
## contrat quand il existe encore.
func refresh() -> void:
	var keep := _focus_key()
	day = HubContractsView.today()
	confirm_id = ""
	for c in _left.get_children():
		_left.remove_child(c)
		c.queue_free()
	_fill()
	if keep.size() > 0:
		var f := _find_focus(keep)
		if f == null:
			f = first_focus()
		if f and hub:
			hub.focus_later(f)


func _fill() -> void:
	active_cards.clear()
	offer_cards.clear()
	var pr := profile()
	var act := HubContractsView.active(pr, day)
	var offs := HubContractsView.offers(pr)
	var amax := int(data.rules.active_max)
	var omax := int(data.rules.offers)
	var full := act.size() >= amax
	# ACTIFS n / 3
	var h1 := _section(Lang.t("ACTIFS", "ACTIVE"), "%d / %d" % [act.size(), amax])
	active_count_label = h1[1]
	_left.add_child(h1[0])
	var row := HubBox.hbox(16)
	row.custom_minimum_size.y = HubStyle.px(ACTIVE_H)
	_left.add_child(row)
	for i in maxi(amax, act.size()):
		var card := _active_card(act[i], pr) if i < act.size() else _free_card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		if i < act.size():
			active_cards.append(card)
	_left.add_child(HubBox.gap(0, 16))
	# PROPOSITIONS DU SCIENTIFIQUE n / 5 · 3 CONTRATS ACTIFS AU MAXIMUM
	var right := "%d / %d" % [offs.size(), omax]
	if full:
		right += " · " + Lang.t("%d CONTRATS ACTIFS AU MAXIMUM", "%d ACTIVE CONTRACTS MAXIMUM") % amax
	var h2 := _section(Lang.t("PROPOSITIONS DE DR BROWN", "DR BROWN'S OFFERS"), right)
	offers_count_label = h2[1]
	_left.add_child(h2[0])
	var orow := HubBox.hbox(10)
	orow.custom_minimum_size.y = HubStyle.px(OFFER_H)
	_left.add_child(orow)
	for i in maxi(omax, offs.size()):
		var card := _offer_card(offs[i], pr, full) if i < offs.size() else _empty_card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		orow.add_child(card)
		if i < offs.size():
			offer_cards.append(card)
	var wanted := {}
	for c in act:
		wanted.merge(c.samples)
	for o in offs:
		wanted.merge(o.contract.samples)
	column.show_samples(pr, wanted)
	_update_note()


## Titre de section (« ACTIFS 3 / 3 ») : Impact 16 et nombre en police des
## menus, ombre noire. Rend [ligne, Label du nombre].
func _section(t: String, n: String) -> Array:
	var h := HubBox.hbox(6)
	h.custom_minimum_size.y = HubStyle.px(24)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	var a := HubStyle.label(t, 16, HubStyle.PLASTER, "impact", true, 0.08)
	a.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(a)
	var b := HubStyle.label(n, 16, HubStyle.DIM, "ui", true, 0.08)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(b)
	# Maquette : texte 2 px à droite du bord des cartes, 2 px plus haut.
	var m := HubBox.pad(h, 2, 0, 0, 0)
	m.add_theme_constant_override("margin_top", -int(HubStyle.px(2)))
	m.custom_minimum_size.y = HubStyle.px(24)
	return [m, b]


# --------------------------------------------------------------------------
# Cartes
# --------------------------------------------------------------------------

func _active_card(c: Dictionary, pr: PlayerProfile) -> HubContractCard:
	var card := HubContractCard.new(HubContractCard.ACTIVE)
	card.contract_id = c.id
	var fiche: Dictionary = c.contract
	var samples: Dictionary = c.samples
	var head := card.add_header(c.title, 18, [8, 6], 10)
	if c.ready:
		card.tag = HubTag.make(Lang.t("PRÊT", "READY"), HubTag.READY)
		head.add_child(card.tag)
	elif int(c.days) >= 0:
		card.tag = HubTag.make(days_text(int(c.days)), HubTag.DATE)
		head.add_child(card.tag)
	else:
		var have := 0
		var need := 0
		for k in samples:
			need += int(samples[k])
			have += mini(pr.sample_count(String(k)), int(samples[k]))
		card.right_label = HubStyle.label("%d / %d" % [have, need], 13, HubStyle.DIM)
		head.add_child(card.right_label)
	var body := card.add_body(8, 10, 7)
	card.quote_label = HubContractCard.quote(String(c.text), 3 if samples.size() <= 1 else 2)
	body.add_child(card.quote_label)
	for k in samples:
		body.add_child(HubLabPanel._progress(String(k), pr.sample_count(String(k)), int(samples[k])))
	if c.ready:
		var names := PackedStringArray()
		for other in ContractRules.shared_with(pr.contracts, data, c.id):
			names.append(HubData.text_of(data.contract(other).title))
		if not names.is_empty():
			card.shared_label = HubStyle.label(Lang.t("Partagé avec : %s", "Shared with: %s") % ", ".join(names), 13, HubStyle.DIM)
			card.shared_label.clip_text = true
			card.shared_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			body.add_child(card.shared_label)
	if int(c.ends) >= 0:
		var e := HubStyle.label(ends_text(int(c.ends)), 13, HubStyle.DIM)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(e)
	body.add_child(HubBox.spring())
	body.add_child(HubContractCard.reward_box(ContractRules.xp_for(data, fiche, pr.level()), fiche.reward, pr.level()))
	var foot := card.add_footer(8, 10)
	var why := ContractRules.deliver_refusal(pr, data, c.id, day)
	var label := Lang.t("REMETTRE", "HAND IN")
	var hint := Lang.t("Récompense au niveau du joueur au moment de la remise.", "Rewards match your level when you hand in.")
	if why == ContractRules.MISSING_SAMPLES:
		label = HubSamplesColumn.missing_text(pr, samples)
		hint = Lang.t("Il manque des échantillons : rapportez-les d'une partie (évacuez pour les garder).",
				"Samples are missing: bring them back from a match (extract to keep them).")
	elif why != "":
		label = ContractRules.refusal_text(why, int(data.rules.active_max))
		hint = label
	card.main_button = _btn(label, deliver.bind(c.id), HubButton.PRIMARY, hint)
	card.main_button.disabled = why != ""
	card.main_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.main_button.size_flags_stretch_ratio = 1.25
	foot.add_child(card.main_button)
	card.abandon_button = _btn(Lang.t("ABANDONNER", "ABANDON"), abandon.bind(c.id), HubButton.NORMAL,
			Lang.t("Abandonner ce contrat : rien n'est consommé, il pourra revenir plus tard.",
				"Abandon this contract: nothing is used up, it may come back later."))
	card.abandon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(card.abandon_button)
	return card


func _offer_card(o: Dictionary, pr: PlayerProfile, full: bool) -> HubContractCard:
	var card := HubContractCard.new(HubContractCard.OFFER)
	card.contract_id = o.id
	var c: Dictionary = o.contract
	card.add_header(o.title, 15, [6, 6], 8)
	var body := card.add_body(6, 8, 5)
	var chips := HubBox.hbox(6)
	for k in c.samples:
		chips.add_child(HubContractCard.need_chip(String(k), pr.sample_count(String(k)), int(c.samples[k])))
	if o.new:
		chips.add_child(HubBox.spring(false))
		card.tag = HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW)
		chips.add_child(card.tag)
	body.add_child(chips)
	var xp := ContractRules.xp_for(data, c, pr.level())
	var t := HubSamplesColumn.rich("[b][color=#%s]+%s XP[/color][/b]\n%s" % [HubStyle.XP_BLUE.to_html(false), HubStyle.num(xp),
			HubContractCard.reward_text(c.reward)], 13, HubStyle.PAPER, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(t)
	var foot := card.add_footer(6, 8)
	var why := ContractRules.accept_refusal(pr.contracts, data, o.id, day)
	var hint := HubData.text_of(c.text)
	if why != "":
		hint = ContractRules.refusal_text(why, int(data.rules.active_max)) + " — " + hint
	card.main_button = _btn(Lang.t("ACCEPTER", "ACCEPT"), accept.bind(o.id), HubButton.NORMAL, hint)
	card.main_button.disabled = why != ""
	card.main_button.height = 28
	card.main_button.font_size = 13
	card.main_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(card.main_button)
	return card


## Case de contrat actif libre (« LIBRE »).
func _free_card() -> HubContractCard:
	var card := HubContractCard.new(HubContractCard.FREE)
	var v := HubBox.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var t := HubStyle.label(Lang.t("LIBRE", "FREE"), 18, HubStyle.DIM, "impact", false, 0.06)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := HubStyle.label(Lang.t("Acceptez une proposition de Dr Brown.", "Accept one of Dr Brown's offers."), 13, HubStyle.DIM2)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	card.col.add_child(HubBox.pad(v, 10, 10, 10, 10))
	card.col.get_child(0).size_flags_vertical = Control.SIZE_EXPAND_FILL
	return card


## Case de proposition vide (.emptycard).
func _empty_card() -> HubContractCard:
	var card := HubContractCard.new(HubContractCard.EMPTY)
	var s := HubStyle.label(Lang.t("Nouvelle proposition après votre prochaine partie", "New offer after your next match"), 13, HubStyle.DIM2)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m := HubBox.pad(s, 10, 10, 10, 10)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.col.add_child(m)
	return card


## Bouton de carte : texte qui se plie, aide dans la barre d'invites.
func _btn(t: String, cb: Callable, kind: String, hint: String) -> HubFitButton:
	var b := HubFitButton.make_fit(t, cb, kind, hint)
	b.focus_entered.connect(func():
		if hub:
			hub.set_hint(b.hint))
	return b


## « ENCORE 12 J » / « 12 DAYS LEFT » ; dernier jour : « DERNIER JOUR ».
static func days_text(days: int) -> String:
	if days <= 0:
		return Lang.t("DERNIER JOUR", "LAST DAY")
	return Lang.t("ENCORE %d J", "%d DAYS LEFT") % days if days > 1 or not Lang.is_en() else "1 DAY LEFT"


const MONTHS := [["janvier", "January"], ["février", "February"], ["mars", "March"], ["avril", "April"],
	["mai", "May"], ["juin", "June"], ["juillet", "July"], ["août", "August"], ["septembre", "September"],
	["octobre", "October"], ["novembre", "November"], ["décembre", "December"]]


## « Se termine le 30 novembre (supprimé ensuite) ».
static func ends_text(ends_day: int) -> String:
	var d := Time.get_date_dict_from_unix_time(ends_day * 86400)
	var m: Array = MONTHS[clampi(int(d.month) - 1, 0, 11)]
	return Lang.t("Se termine le %d %s (supprimé ensuite)" % [int(d.day), m[0]],
			"Ends on %s %d (removed afterwards)" % [m[1], int(d.day)])


# --------------------------------------------------------------------------
# Actions (une écriture du profil chacune)
# --------------------------------------------------------------------------

## Accepte la proposition `id` ; le focus suit le nouveau contrat actif.
func accept(id: String) -> void:
	var why := ContractRules.accept(profile().contracts, data, id, day)
	if why != "":
		hub.set_hint(ContractRules.refusal_text(why, int(data.rules.active_max)))
		return
	hub.save_profile()
	var f := _find_focus([id, "main"])
	if f:
		hub.focus_later(f)


## REMETTRE : consomme les échantillons, XP, objet ; fenêtre de récompense.
func deliver(id: String) -> void:
	var pr := profile()
	var c := data.contract(id)
	var res := ContractRules.deliver(pr, data, id, day)
	if not res.ok:
		hub.set_hint(ContractRules.refusal_text(res.reason, int(data.rules.active_max)))
		return
	var remaining := {}
	for k in c.samples:
		remaining[k] = pr.sample_count(String(k))
	hub.save_profile()
	_open_popup().show_delivery(c, res, pr, remaining)
	hub.refresh_prompts()


## ABANDONNER : premier appui « CONFIRMER », deuxième appui : le contrat
## disparaît (rien n'est consommé).
func abandon(id: String) -> void:
	if confirm_id != id:
		_cancel_confirm()
		var card := _active(id)
		if card == null:
			return
		confirm_id = id
		card.abandon_button.label = Lang.t("CONFIRMER", "CONFIRM")
		card.abandon_button.kind = HubButton.DANGER
		if not card.abandon_button.has_focus():
			card.abandon_button.grab_focus()
		hub.set_hint(Lang.t("Appuyez encore pour abandonner « %s » : rien n'est consommé.", "Press again to abandon \"%s\": nothing is used up.")
				% HubData.text_of(data.contract(id).title))
		hub.refresh_prompts()
		return
	confirm_id = ""
	if ContractRules.abandon(profile().contracts, id):
		hub.save_profile()
		var f := first_focus()
		if f:
			hub.focus_later(f)


func _cancel_confirm() -> void:
	if confirm_id == "":
		return
	var card := _active(confirm_id)
	confirm_id = ""
	if card:
		card.abandon_button.label = Lang.t("ABANDONNER", "ABANDON")
		card.abandon_button.kind = HubButton.NORMAL
	if hub:
		hub.refresh_prompts()


func _open_popup() -> HubRewardPopup:
	popup = HubRewardPopup.new(hub)
	hub.add_child(popup)
	popup.closed.connect(_on_popup_closed)
	return popup


func _on_popup_closed() -> void:
	popup = null
	if not is_visible_in_tree() or hub == null:
		return
	hub.set_hint("")
	hub.refresh_prompts()
	var f := first_focus()
	if f:
		hub.focus_later(f)


func popup_open() -> bool:
	return popup != null and is_instance_valid(popup) and popup.is_open()


# --------------------------------------------------------------------------
# HubPanel
# --------------------------------------------------------------------------

## Focus : premier contrat PRÊT (maquette), sinon une proposition qu'on peut
## accepter, sinon le premier contrat actif, sinon la première proposition.
func first_focus() -> Control:
	for c in active_cards:
		if not c.main_button.disabled:
			return c.main_button
	for c in offer_cards:
		if not c.main_button.disabled:
			return c.main_button
	if not active_cards.is_empty():
		return active_cards[0].main_button
	if not offer_cards.is_empty():
		return offer_cards[0].main_button
	return null


func prompts() -> Array:
	if popup_open():
		var out := []
		if popup.primary_button:
			out.append([HubPrompts.ACCEPT, popup.primary_text])
		out.append([HubPrompts.BACK, Lang.t("Fermer", "Close")])
		return out
	if confirm_id != "":
		return [[HubPrompts.ACCEPT, Lang.t("Confirmer l'abandon", "Confirm abandon")], [HubPrompts.BACK, Lang.t("Annuler", "Cancel")]]
	var tail := [[HubPrompts.TABS, Lang.t("Onglets", "Tabs")], [HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]
	var card := _focused_card()
	if card and card.kind == HubContractCard.OFFER:
		return [[HubPrompts.ACCEPT, Lang.t("Accepter", "Accept")]] + tail
	if card and _focus_owner() == card.abandon_button:
		return [[HubPrompts.ACCEPT, Lang.t("Abandonner", "Abandon")]] + tail
	if active_cards.is_empty():
		return [[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")]] + tail
	return [[HubPrompts.ACCEPT, Lang.t("Remettre", "Hand in")], [HubPrompts.SECONDARY, Lang.t("Abandonner", "Abandon")]] + tail


func back() -> bool:
	if popup_open():
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		popup.close()
		return true
	if confirm_id != "":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		_cancel_confirm()
		hub.set_hint("")
		return true
	return false


func handle_input(event: InputEvent) -> bool:
	if popup_open():
		return false
	var secondary := false
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and (k.physical_keycode == KEY_DELETE or k.physical_keycode == KEY_R):
		secondary = true
	var j := event as InputEventJoypadButton
	if j and j.pressed and j.button_index == JOY_BUTTON_X:
		secondary = true
	if not secondary:
		return false
	on_prompt(HubPrompts.SECONDARY)
	return true


## Invite cliquée (action propre au panneau) : Abandonner.
func on_prompt(id: String) -> void:
	if id != HubPrompts.SECONDARY:
		return
	var card := _focused_card()
	if card == null or card.kind != HubContractCard.ACTIVE:
		card = active_cards[0] if not active_cards.is_empty() else null
	if card:
		abandon(card.contract_id)


func shown() -> void:
	_update_note()


func hidden() -> void:
	_cancel_confirm()
	if popup_open():
		popup.close()


## Pastille de l'onglet : contrats prêts à remettre (maquette).
func badge() -> int:
	return HubContractsView.ready_count(profile())


# --------------------------------------------------------------------------
# Focus, aide de la réserve
# --------------------------------------------------------------------------

func _on_focus_changed(c: Control) -> void:
	if not is_visible_in_tree() or hub == null or popup_open():
		return
	if confirm_id != "":
		var card := _active(confirm_id)
		if card == null or c != card.abandon_button:
			_cancel_confirm()
	if c and is_ancestor_of(c):
		hub.refresh_prompts()
		_update_note()


func _focus_owner() -> Control:
	var vp := get_viewport()
	return vp.gui_get_focus_owner() if vp else null


func _focused_card() -> HubContractCard:
	var f := _focus_owner()
	if f == null:
		return null
	for c in active_cards + offer_cards:
		if c.is_ancestor_of(f):
			return c
	return null


func _active(id: String) -> HubContractCard:
	for c in active_cards:
		if c.contract_id == id:
			return c
	return null


## [identifiant du contrat, "main" / "abandon"] du bouton qui a le focus.
func _focus_key() -> Array:
	var card := _focused_card()
	if card == null:
		return []
	return [card.contract_id, "abandon" if _focus_owner() == card.abandon_button else "main"]


func _find_focus(key: Array) -> Control:
	for c in active_cards + offer_cards:
		if c.contract_id == key[0]:
			return c.abandon_button if key[1] == "abandon" and c.abandon_button else c.main_button
	return null


## Texte sous la réserve : conséquence de la remise du contrat choisi
## (maquette : « Remettre Dents de lait consommera 4 crocs : il en restera 3,
## assez pour Analyse complète. »), rappel des règles.
func _update_note() -> void:
	if column == null:
		return
	var rule := Lang.t("Un contrat ne se remet qu'au hub. En partie, un message vous prévient quand l'objectif est atteint : évacuez pour garder vos échantillons.",
			"Contracts are only handed in at the hub. In a match, a message tells you when the goal is met: extract to keep your samples.")
	var card := _focused_card()
	var id := ""
	if card and card.kind == HubContractCard.ACTIVE and not card.main_button.disabled:
		id = card.contract_id
	elif card == null:
		for c in active_cards:
			if not c.main_button.disabled:
				id = c.contract_id
				break
	if id != "":
		column.set_note(deliver_note(profile(), data, id), rule)
	elif card and card.kind == HubContractCard.OFFER:
		var c := data.contract(card.contract_id)
		var have := PackedStringArray()
		for k in c.samples:
			have.append(HubSamplesColumn.words(String(k), profile().sample_count(String(k))))
		column.set_note(Lang.t("[b]%s[/b] demande %s. Vous avez %s.", "[b]%s[/b] asks for %s. You have %s.") % [
			HubSamplesColumn.esc(HubData.text_of(c.title)), HubSamplesColumn.join_words(_cost_items(c.samples)),
			HubSamplesColumn.join_words(have)], rule)
	else:
		column.set_note(Lang.t("Remettre un contrat ne consomme que la quantité demandée : le reste de la réserve est gardé.",
				"Handing in a contract only uses the amount asked for: the rest of your stock is kept."), rule)


static func _cost_items(cost: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k in cost:
		out.append(HubSamplesColumn.words(String(k), int(cost[k])))
	return out


## Conséquence de la remise du contrat actif `id` sur les autres contrats
## actifs qui demandent les mêmes sortes (BBCode du hub).
static func deliver_note(pr: PlayerProfile, d: HubData, id: String) -> String:
	var c := d.contract(id)
	if c.is_empty():
		return ""
	var title := HubSamplesColumn.esc(HubData.text_of(c.title))
	var rest := HubSamplesColumn.remaining_after(pr, c.samples)
	var s := ""
	if c.samples.size() == 1:
		var k: String = c.samples.keys()[0]
		s = Lang.t("Remettre [b]%s[/b] consommera %s : il en restera %d", "Handing in [b]%s[/b] will use %s: %d will be left") % [
			title, HubSamplesColumn.words(k, int(c.samples[k])), int(rest[k])]
	else:
		var left := PackedStringArray()
		for k in rest:
			left.append(HubSamplesColumn.words(String(k), int(rest[k])))
		s = Lang.t("Remettre [b]%s[/b] consommera %s ; il restera %s", "Handing in [b]%s[/b] will use %s; %s will be left") % [
			title, HubSamplesColumn.join_words(_cost_items(c.samples)), HubSamplesColumn.join_words(left)]
	var ok := PackedStringArray()
	var short := PackedStringArray()
	for other in ContractRules.shared_with(pr.contracts, d, id):
		var o := d.contract(other)
		# Assez après la remise pour les sortes communes ; manque créé par la
		# remise (assez avant, plus assez après) en rouge ; sinon rien.
		var enough := true
		var created := false
		for k in c.samples:
			if o.samples.has(k) and int(rest[k]) < int(o.samples[k]):
				enough = false
				if pr.sample_count(String(k)) >= int(o.samples[k]):
					created = true
		var n := HubSamplesColumn.esc(HubData.text_of(o.title))
		if enough:
			ok.append("[b]%s[/b]" % n)
		elif created:
			short.append("[bad]%s[/bad]" % n)
	if not ok.is_empty():
		s += Lang.t(", assez pour %s", ", enough for %s") % HubSamplesColumn.join_words(ok)
	s += "."
	if not short.is_empty():
		s += " " + Lang.t("%s n'en aura plus assez.", "%s will no longer have enough.") % HubSamplesColumn.join_words(short)
	return s
