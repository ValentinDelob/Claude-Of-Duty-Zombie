class_name Hub2ExchangesPanel
extends Hub2Panel
## LABO › ÉCHANGES (docs/hub_v2/Echanges.dc.html) : CATALOGUE DU LABO, un
## objet PRÉCIS contre des échantillons (ExchangeRules ; pas d'XP), au niveau
## du joueur. En-tête (titre, phrase, filtres POSSIBLES MAINTENANT / TOUS :
## Y, Tab ou clic), grille de deux colonnes (écart 14) de fiches : filet de
## rareté à gauche, sorte (« PIÈCE SOIGNÉE », « ARME ÉPIQUE »), nom, effet
## (modificateurs exacts, ou famille et niveau de l'arme), coût (pastille de
## couleur, mot, possédés / demandés en turquoise ou en rouge), ÉCHANGER
## (biseau 10 ; jaune si possible) ; une fiche d'un niveau trop haut est
## estompée (opacité 0,55) avec « NIV. n REQUIS ». La fiche choisie
## (focus, survol) est jaune. ÉCHANGER en deux appuis (« CONFIRMER », coût
## dans l'aide), puis la fenêtre Hub2RewardPopup. Défilement si le catalogue
## dépasse l'écran.

const ROW_GAP := 14.0

var data: HubData
var day := 0
## Filtre « POSSIBLES MAINTENANT ».
var only_tradable := false
## Échange dont la confirmation attend le deuxième appui ("" : aucun).
var confirm_id := ""
var popup: Hub2RewardPopup
var root: VBoxContainer
var scroll: ScrollContainer
var chip_now: Hub2Button
var chip_all: Hub2Button
## Échange -> Hub2Button (la fiche), dans l'ordre affiché.
var cards: Dictionary = {}
var empty_label: Label


func help() -> String:
	var lvl := profile().level() if profile() else 1
	return Lang.t("L’objet obtenu est à ton niveau actuel (niv. %d).", "The item you get is at your current level (lvl %d).") % lvl


func prompts() -> Array:
	if popup_open():
		var out := []
		if popup.primary_button:
			out.append([Hub2Input.ACCEPT, popup.primary_text])
		out.append([Hub2Input.BACK, Lang.t("Fermer", "Close")])
		return out
	if confirm_id != "":
		return [[Hub2Input.ACCEPT, Lang.t("Confirmer l’échange", "Confirm trade")], [Hub2Input.BACK, Lang.t("Annuler", "Cancel")]]
	return [[Hub2Input.ACCEPT, Lang.t("Échanger", "Trade")], [Hub2Input.FILTER, Lang.t("Filtrer", "Filter")],
		[Hub2Input.BACK, Lang.t("Retour", "Back")]]


func build() -> void:
	_fill()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func refresh() -> void:
	if not built:
		return
	var key := _focused_id()
	confirm_id = ""
	if root:
		remove_child(root)
		root.queue_free()
	_fill()
	if is_visible_in_tree():
		hub.focus_later(cards.get(key, first_focus()) if key != "" else first_focus())


func _fill() -> void:
	data = HubContractsView.data()
	day = HubContractsView.today()
	cards.clear()
	var pr := profile()
	root = VBoxContainer.new()
	root.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_main(root)
	# En-tête (34 px, écart 16).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	head.custom_minimum_size.y = Hub2Style.px(34)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	var h1 := Hub2Text.new()
	h1.setup(Lang.t("CATALOGUE DU LABO", "LAB CATALOGUE"), Hub2Style.CHAKRA, 700, 22, Hub2Style.TEXT, 0.06)
	h1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(h1)
	var sub := Hub2Style.label(Lang.t("Un objet précis contre des échantillons. Toujours disponible.",
			"A specific item for samples. Always available."), Hub2Style.BARLOW, 400, 14, Hub2Style.text_a(0.55))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(sub)
	chip_now = _chip(Lang.t("POSSIBLES MAINTENANT", "AVAILABLE NOW"), only_tradable)
	chip_now.pressed.connect(set_filter.bind(true))
	head.add_child(chip_now)
	chip_all = _chip(Lang.t("TOUS", "ALL"), not only_tradable)
	chip_all.pressed.connect(set_filter.bind(false))
	head.add_child(chip_all)
	# Grille (deux colonnes égales, écart 14), défilante.
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	scroll.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	root.add_child(scroll)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", int(Hub2Style.px(ROW_GAP)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(grid)
	var list := ExchangeRules.listed(pr, data, day, only_tradable)
	empty_label = null
	if list.is_empty():
		empty_label = Hub2Style.label(Lang.t("Rien d’échangeable pour l’instant : rapportez d’autres échantillons.",
				"Nothing to trade yet: bring back more samples.") if only_tradable else
				Lang.t("Le catalogue est vide.", "The catalogue is empty."), Hub2Style.BARLOW, 400, 15, Hub2Style.text_a(0.6))
		grid.add_child(empty_label)
	var row: HBoxContainer
	for i in list.size():
		if i % 2 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", int(Hub2Style.px(ROW_GAP)))
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(row)
		var card := _card(list[i], pr)
		row.add_child(card)
		cards[list[i].id] = card
	if list.size() % 2 == 1:
		var filler := Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(filler)


## Filtre (h 30, padding 0 12, Chakra Petch 13 px 600 0.1em) : allumé =
## fond et liseré #F2F0EA, texte sombre ; éteint = verre 50 %, liseré 14 %.
func _chip(text: String, on: bool) -> Hub2Button:
	var b := Hub2Button.new()
	if on:
		b.box.flat(Hub2Style.TEXT, Hub2Style.TEXT, 1.0)
	else:
		b.box.flat(Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.5), Hub2Style.white_a(0.14), 1.0)
	b.box.pad(0, 12)
	b.custom_minimum_size.y = Hub2Style.px(30)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, 600, 13, Hub2Style.INK if on else Hub2Style.text_a(0.75), 0.1)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_content(t)
	b.set_meta("on", on)
	return b


## Fiche d'un échange (padding 16 18 16 21, écart 16, verre ; filet de
## rareté de 3 px à gauche).
func _card(x: Dictionary, pr: PlayerProfile) -> Hub2Button:
	var b := Hub2Button.new()
	b.show_focus = false
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.x = Hub2Style.px(200)
	b.set_meta("id", x.id)
	var why := ExchangeRules.refusal(pr, data, x.id, day)
	var locked := why == ExchangeRules.LEVEL
	var limit := why == ExchangeRules.LIMIT
	var can := why == ""
	b.set_meta("can", can)
	b.box.glass(Hub2Style.GLASS, Hub2Style.LINE, 1.0)
	b.box.pad(16, 18, 16, 21)
	if locked:
		b.modulate.a = 0.55
	var rar := _rarity(x.reward)
	var col := Hub2Style.rarity_color(rar)
	var line := ColorRect.new()
	line.color = col
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_bottom = 1.0
	line.offset_right = Hub2Style.px(3)
	b.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(row)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var kind := Hub2Text.new()
	kind.setup(kind_text(x.reward), Hub2Style.CHAKRA, 700, 11, col, 0.16)
	v.add_child(kind)
	var nm := Hub2Style.label(HubData.text_of(x.title), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT,
			0.0)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	var eff := Hub2Style.label(effect_text(x.reward, pr), Hub2Style.BARLOW, 400, 14, Hub2Style.TEAL)
	eff.clip_text = true
	eff.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(eff)
	var costs := HFlowContainer.new()
	costs.add_theme_constant_override("h_separation", int(Hub2Style.px(14)))
	costs.add_theme_constant_override("v_separation", int(Hub2Style.px(4)))
	costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_top", int(Hub2Style.px(4)))
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cm.add_child(costs)
	v.add_child(cm)
	for k in x.samples:
		var need := int(x.samples[k])
		var have := pr.sample_count(String(k))
		var c := HBoxContainer.new()
		c.add_theme_constant_override("separation", int(Hub2Style.px(7)))
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sq := ColorRect.new()
		sq.color = Hub2LabKit.sample_color(String(k))
		sq.custom_minimum_size = Hub2Style.pxv(11, 11)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(sq)
		c.add_child(Hub2Style.label(Hub2LabKit.word_cap(String(k), 2), Hub2Style.BARLOW, 400, 14, Hub2Style.TEXT))
		var ct := Hub2Text.new()
		ct.setup("%d/%d" % [have, need], Hub2Style.MONO, 700, 14, Hub2Style.TEAL if have >= need else Hub2Style.BAD)
		ct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.add_child(ct)
		costs.add_child(c)
	if locked or limit:
		var lt := Hub2Text.new()
		lt.setup(ExchangeRules.refusal_text(why, x), Hub2Style.CHAKRA, 700, 13, Hub2Style.BAD if locked else Hub2Style.text_a(0.5), 0.1)
		lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lt)
	else:
		var btn := Hub2Box.new()
		btn.flat(Hub2Style.YELLOW if can else Hub2Style.white_a(0.08))
		btn.chamfer(10)
		btn.pad(0, 18)
		btn.custom_minimum_size.y = Hub2Style.px(40)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bt := Hub2Text.new()
		bt.setup(Lang.t("ÉCHANGER", "TRADE"), Hub2Style.CHAKRA, 700, 14, Hub2Style.INK if can else Hub2Style.text_a(0.4), 0.14)
		bt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.add_child(bt)
		row.add_child(btn)
		b.set_meta("label", bt)
	b.hint = _hint_for(x, why, pr)
	b.pressed.connect(trade.bind(String(x.id)))
	b.focus_entered.connect(_highlight.bind(b, true))
	b.focus_exited.connect(_highlight.bind(b, false))
	b.mouse_entered.connect(_highlight.bind(b, true))
	b.mouse_exited.connect(func(): _highlight(b, b.has_focus()))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can else Control.CURSOR_ARROW
	return b


## Fiche choisie (focus, survol) : fond jaune 10 %, liseré jaune.
func _highlight(b: Hub2Button, on: bool) -> void:
	if not is_instance_valid(b):
		return
	if b.has_focus() or b.is_hovered():
		on = true
	b.box.fill = Hub2Style.yellow_a(0.1) if on else Hub2Style.GLASS
	b.box.border_color = Hub2Style.YELLOW if on else Hub2Style.LINE


## Rareté affichée de la récompense (pièce : qualité de ses modificateurs).
static func _rarity(reward: Dictionary) -> int:
	if reward.get("kind") == "weapon":
		return maxi(OwnedWeapon.rarity_from_key(reward.get("rarity", "common")), 0)
	return int(Hub2LabKit.QUALITY_RARITY.get(Hub2LabKit.quality_of_mods(reward.get("mods", {})), 0))


## « PIÈCE SOIGNÉE », « ARME ÉPIQUE » (« FINE PART », « EPIC WEAPON »).
static func kind_text(reward: Dictionary) -> String:
	if reward.get("kind") == "weapon":
		var rn := GameWeapon.rarity_name(_rarity(reward))
		return Lang.t("ARME %s" % rn, "%s WEAPON" % rn)
	var qn := HubData.quality_name(Hub2LabKit.quality_of_mods(reward.get("mods", {})))
	return Lang.t("PIÈCE %s" % qn, "%s PART" % qn)


## Effet : modificateurs exacts (« +20 % vitesse de rechargement ») ou
## famille et niveau de l'arme (« Mitraillette · niv. 23 »).
static func effect_text(reward: Dictionary, pr: PlayerProfile) -> String:
	if reward.get("kind") == "weapon":
		var id := String(reward.get("weapon", ""))
		var lvl := maxi(pr.level(), WeaponDB.base_level(id)) if WeaponDB.exists(id) else pr.level()
		return Hub2LabKit.capitalize(WeaponDB.family_name(id).to_lower()) + Lang.t(" · niv. %d", " · lvl %d") % lvl
	return Hub2LabKit.mods_line(reward.get("mods", {}))


func _hint_for(x: Dictionary, why: String, pr: PlayerProfile) -> String:
	var t := HubData.text_of(x.get("text", {}))
	match why:
		"":
			# Échange possible : l'aide de l'écran reste (maquette).
			return ""
		ExchangeRules.MISSING_SAMPLES:
			var miss := {}
			for k in x.samples:
				var m := int(x.samples[k]) - pr.sample_count(String(k))
				if m > 0:
					miss[k] = m
			return Lang.t("Il manque : %s.", "Missing: %s.") % Hub2LabKit.cost_line(miss)
		ExchangeRules.LEVEL:
			return Lang.t("Disponible au niveau %d.", "Available at level %d.") % int(x.min_level)
	return ExchangeRules.refusal_text(why, x)


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

## ÉCHANGER : premier appui « CONFIRMER » (coût dans l'aide), deuxième
## appui : l'échange (une écriture du profil) et la fenêtre de l'objet.
func trade(id: String) -> void:
	var pr := profile()
	var b: Hub2Button = cards.get(id)
	if b == null:
		return
	var why := ExchangeRules.refusal(pr, data, id, day)
	if why != "":
		Audio.play_ui(MenuStyle.SND_BACK, -10.0)
		hub.set_hint(_hint_for(data.exchange(id), why, pr))
		return
	var x := data.exchange(id)
	if confirm_id != id:
		_cancel_confirm()
		confirm_id = id
		var lbl: Hub2Text = b.get_meta("label")
		lbl.text = Lang.t("CONFIRMER", "CONFIRM")
		if not b.has_focus():
			b.grab_focus()
		hub.set_hint(Lang.t("Appuyez encore pour échanger %s.", "Press again to trade %s.") % Hub2LabKit.cost_line(x.samples))
		hub.refresh_prompts()
		return
	confirm_id = ""
	var res := ExchangeRules.trade(pr, data, id, day)
	if not res.ok:
		return
	Audio.play_ui(MenuStyle.SND_SELECT, -6.0)
	var remaining := {}
	for k in x.samples:
		remaining[k] = pr.sample_count(String(k))
	hub.save_profile()
	popup = Hub2RewardPopup.new()
	popup.hub = hub
	hub.add_child(popup)
	popup.closed.connect(_on_popup_closed)
	popup.show_exchange(x, res, pr, remaining)
	hub.refresh_prompts()


func _cancel_confirm() -> void:
	if confirm_id == "":
		return
	var b: Hub2Button = cards.get(confirm_id)
	confirm_id = ""
	if b and is_instance_valid(b) and b.has_meta("label"):
		(b.get_meta("label") as Hub2Text).text = Lang.t("ÉCHANGER", "TRADE")
	if hub:
		hub.set_hint("")
		hub.refresh_prompts()


func set_filter(tradable: bool) -> void:
	if tradable == only_tradable:
		return
	only_tradable = tradable
	confirm_id = ""
	Audio.play_ui(MenuStyle.SND_SELECT, -10.0)
	refresh()
	if is_visible_in_tree():
		var f := first_focus()
		if f:
			hub.focus_later(f)
	hub.refresh_prompts()


func toggle_filter() -> void:
	set_filter(not only_tradable)


func _on_popup_closed() -> void:
	popup = null
	if hub == null or not is_visible_in_tree():
		return
	hub.set_hint("")
	hub.refresh_prompts()
	var f := first_focus()
	if f:
		hub.focus_later(f)


func popup_open() -> bool:
	return popup != null and is_instance_valid(popup) and popup.is_open()


# --------------------------------------------------------------------------
# Hub2Panel
# --------------------------------------------------------------------------

## Échange `id` choisi : filtre TOUS s'il était caché, focus sur sa fiche
## (A sur un échantillon de l'INVENTAIRE). Faux s'il n'est pas au catalogue.
func select_item(id: String) -> bool:
	if not cards.has(id) and only_tradable:
		set_filter(false)
	var c: Control = cards.get(id)
	if c == null:
		return false
	if hub:
		hub.focus_later(c)
	return true


## Focus : premier échange possible, sinon la première fiche.
func first_focus() -> Control:
	for id in cards:
		if cards[id].get_meta("can"):
			return cards[id]
	return cards.values()[0] if not cards.is_empty() else null


func back() -> bool:
	if popup_open():
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		popup.close()
		return true
	if confirm_id != "":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		_cancel_confirm()
		return true
	return false


func handle_input(event: InputEvent) -> bool:
	if popup_open():
		return Hub2Input.tab_step(event) != 0 or Hub2Input.is_play(event)
	var j := event as InputEventJoypadButton
	if Hub2Input.is_key(event, KEY_TAB) or (j and j.pressed and j.button_index == JOY_BUTTON_Y):
		toggle_filter()
		return true
	return false


## Tab : avant la navigation du focus de Godot (ui_focus_next), qui
## l'avalerait avant le hub.
func _input(event: InputEvent) -> void:
	if not Hub2Input.is_key(event, KEY_TAB) or not is_visible_in_tree() or hub == null:
		return
	if hub.get("current_id") != screen_id or hub.hub_menu.is_open() or not hub.call("_active"):
		return
	get_viewport().set_input_as_handled()
	if not popup_open():
		toggle_filter()


func on_prompt(id: String) -> void:
	if id == Hub2Input.FILTER:
		toggle_filter()


func hidden() -> void:
	_cancel_confirm()
	if popup_open():
		popup.close()


func _on_focus_changed(c: Control) -> void:
	if not is_visible_in_tree():
		return
	if confirm_id != "" and c != cards.get(confirm_id):
		_cancel_confirm()


func _focused_id() -> String:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	for id in cards:
		if cards[id] == f:
			return id
	return ""
