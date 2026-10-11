class_name HubExchangesPanel
extends HubPanel
## Onglet ÉCHANGES (docs/HUB_PLAN.md §3.5 ; maquette, écran 7) : catalogue
## permanent du scientifique, des échantillons contre un objet PRÉCIS au
## niveau du joueur, sans XP (D10).
##   - CATALOGUE D'ÉCHANGES (932 × 556) : filtre TOUS / ÉCHANGEABLES
##     MAINTENANT (Tab / Y / clic), une ligne de 72 px par échange : objet
##     (nom, modificateurs ou arme précise), coût « possédés / demandés » (vert
##     si assez, rouge sinon), ÉCHANGER en deux appuis (« CONFIRMER : 4
##     COLLIERS + 2 TOUFFES »), ou ce qui manque ; un échange d'un niveau trop
##     haut est grisé, « NIV. 8 REQUIS » (un objectif) ; limite atteinte :
##     « LIMITE ATTEINTE » ;
##   - RÉSERVE à droite : quantités, et ce que l'échange choisi laisse aux
##     contrats actifs.
## Règles : ExchangeRules (lot A), une écriture du profil par échange ; la
## fenêtre HubRewardPopup montre l'objet reçu.

const LEFT_W := 932.0
const RIGHT_W := 300.0
const ROW_H := 72.0
## Texte grisé d'une ligne verrouillée (.row.lock).
const LOCK_TEXT := Color("6D6A63")

var data: HubData
var day := 0
## Filtre « ÉCHANGEABLES MAINTENANT ».
var only_tradable := false
## Échange dont la confirmation attend le deuxième appui ("" : aucun).
var confirm_id := ""
var catalog: HubBox
var column: HubSamplesColumn
var popup: HubRewardPopup
var chip_all: ExchangeChip
var chip_tradable: ExchangeChip
## Identifiant -> {row: HubRow, button: HubButton ou null, tag: HubTag ou null}.
var rows: Dictionary = {}
## Ordre d'affichage des échanges.
var order: PackedStringArray = []
var _list: VBoxContainer
var _root: HBoxContainer


func build() -> void:
	data = HubContractsView.data()
	day = HubContractsView.today()
	_root = HubBox.hbox(16)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	catalog = HubBox.new(Lang.t("CATALOGUE D'ÉCHANGES", "EXCHANGE CATALOGUE"), "")
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog.size_flags_stretch_ratio = LEFT_W
	_root.add_child(catalog)
	var chips := HubBox.hbox(6)
	var cm := HubBox.pad(chips, 10, 8, 10, 10)
	cm.draw.connect(func():
		cm.draw_rect(Rect2(0, cm.size.y - HubStyle.px(2), cm.size.x, HubStyle.px(2)), HubStyle.BLACK))
	catalog.content.add_child(cm)
	chip_all = ExchangeChip.make(Lang.t("TOUS", "ALL"), func(): set_filter(false))
	chip_tradable = ExchangeChip.make(Lang.t("ÉCHANGEABLES MAINTENANT", "TRADABLE NOW"), func(): set_filter(true))
	chips.add_child(chip_all)
	chips.add_child(chip_tradable)
	_list = HubBox.vbox(0)
	catalog.content.add_child(_list)
	column = HubSamplesColumn.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = RIGHT_W
	_root.add_child(column)
	_fill()


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func refresh() -> void:
	var keep := _focused_id()
	day = HubContractsView.today()
	confirm_id = ""
	_fill()
	if keep != "" and is_visible_in_tree():
		var f := _button_of(keep)
		if f == null:
			f = first_focus()
		if f:
			hub.focus_later(f)


func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	order.clear()
	var pr := profile()
	catalog.set_right(Lang.t("objets au niveau du joueur (%d)", "items at your level (%d)") % pr.level())
	chip_all.on = not only_tradable
	chip_tradable.on = only_tradable
	var list := ExchangeRules.listed(pr, data, day, only_tradable)
	var wanted := {}
	for i in list.size():
		var x: Dictionary = list[i]
		wanted.merge(x.samples)
		_list.add_child(_row(x, pr, i))
	if list.is_empty():
		var t := HubStyle.label(Lang.t("Rien d'échangeable pour l'instant : rapportez d'autres échantillons.",
				"Nothing to trade yet: bring back more samples.") if only_tradable
				else Lang.t("Le scientifique n'a rien à échanger.", "The scientist has nothing to trade."), 15, HubStyle.PLASTER)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(HubBox.pad(t, 12, 14, 12, 14))
	column.show_samples(pr, wanted)
	_update_note()


func _row(x: Dictionary, pr: PlayerProfile, i: int) -> HubRow:
	var id: String = x.id
	var why := ExchangeRules.refusal(pr, data, id, day)
	var locked := why == ExchangeRules.LEVEL or why == ExchangeRules.LIMIT
	var r := HubRow.new(HubRow.ROW, ROW_H)
	r.alt = i % 2 == 1
	var entry := {"row": r, "button": null, "tag": null}
	rows[id] = entry
	order.append(id)
	var reward: Dictionary = x.reward
	var is_weapon: bool = reward.get("kind") == "weapon"
	var ic := HubIcon.make(HubContractCard.weapon_art(String(reward.get("weapon", "any"))) if is_weapon else "part", 2 if is_weapon else 4)
	if locked:
		ic.dim = 0.5
	r.box.add_child(ic)
	# Nom et objet (250 px).
	var name_col := HubBox.vbox(0)
	name_col.custom_minimum_size.x = HubStyle.px(250)
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := HubStyle.label(HubData.text_of(x.title), 16, LOCK_TEXT if locked else HubStyle.PAPER, "bold")
	n.clip_text = true
	name_col.add_child(n)
	var sub := ""
	if is_weapon:
		var rr := maxi(OwnedWeapon.rarity_from_key(reward.get("rarity", "common")), 0)
		var wn := HubGear.weapon_name(String(reward.weapon))
		sub = Lang.t("Arme %s précise : %s", "Exact %s weapon: %s") % [GameWeapon.rarity_name(rr).to_lower(), wn]
	elif not locked:
		sub = Lang.t("Pièce", "Part") + " · " + HubContractCard.mods_bb(reward.get("mods", {}))
	else:
		sub = Lang.t("Pièce", "Part") + " · " + LootRules.mods_text(reward.get("mods", {}))
	if int(x.limit) > 0:
		sub += Lang.t(" · limite %d / %d", " · limit %d / %d") % [ExchangeRules.count(pr, id), int(x.limit)]
	var col := LOCK_TEXT if locked else (HubStyle.PAPER if is_weapon else HubStyle.OK)
	var s := HubSamplesColumn.rich(sub, 13, col)
	s.add_theme_font_override("normal_font", HubStyle.font("semi"))
	name_col.add_child(s)
	r.box.add_child(name_col)
	# Coût.
	var cost := HubBox.hbox(6)
	for k in x.samples:
		cost.add_child(HubContractCard.need_chip(String(k), pr.sample_count(String(k)), int(x.samples[k]), locked))
	if locked:
		cost.modulate.a = 0.6
	r.box.add_child(cost)
	r.box.add_child(HubBox.spring(false))
	var hint := Lang.t("Un échange ne rapporte pas d'XP : il garantit l'objet.", "An exchange gives no XP: it guarantees the item.")
	if locked:
		var t := HubTag.make(ExchangeRules.refusal_text(why, x), HubTag.LOCK)
		entry.tag = t
		r.box.add_child(t)
		return r
	var b: HubButton
	if why == "":
		b = HubButton.make(Lang.t("ÉCHANGER", "TRADE"), trade.bind(id), HubButton.PRIMARY, hint)
	else:
		var label := HubSamplesColumn.missing_text(pr, x.samples) if why == ExchangeRules.MISSING_SAMPLES \
				else ExchangeRules.refusal_text(why, x)
		b = HubButton.make(label, func(): pass, HubButton.NORMAL, hint)
		b.disabled = true
	b.focus_entered.connect(func():
		if hub:
			hub.set_hint(b.hint))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	entry.button = b
	r.box.add_child(b)
	return r


## Texte du deuxième appui : « CONFIRMER : 4 COLLIERS + 2 TOUFFES ».
static func confirm_text(x: Dictionary) -> String:
	return Lang.t("CONFIRMER : %s", "CONFIRM: %s") % HubSamplesColumn.cost_words(x.samples, true)


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

## ÉCHANGER : premier appui « CONFIRMER : … », deuxième appui : l'échange
## (une écriture du profil), puis la fenêtre de l'objet reçu.
func trade(id: String) -> void:
	var x := data.exchange(id)
	if confirm_id != id:
		_cancel_confirm()
		var b := _button_of(id)
		if b == null or b.disabled:
			return
		confirm_id = id
		b.label = confirm_text(x)
		b.kind = HubButton.DANGER
		if not b.has_focus():
			b.grab_focus()
		hub.refresh_prompts()
		_update_note()
		return
	confirm_id = ""
	var pr := profile()
	var res := ExchangeRules.trade(pr, data, id, day)
	if not res.ok:
		hub.set_hint(ExchangeRules.refusal_text(res.reason, x))
		return
	var remaining := {}
	for k in x.samples:
		remaining[k] = pr.sample_count(String(k))
	hub.save_profile()
	popup = HubRewardPopup.new(hub)
	hub.add_child(popup)
	popup.closed.connect(_on_popup_closed)
	popup.show_exchange(x, res, pr, remaining)
	hub.refresh_prompts()


func _cancel_confirm() -> void:
	if confirm_id == "":
		return
	var b := _button_of(confirm_id)
	confirm_id = ""
	if b:
		b.label = Lang.t("ÉCHANGER", "TRADE")
		b.kind = HubButton.PRIMARY
	if hub:
		hub.refresh_prompts()
	_update_note()


## Filtre TOUS / ÉCHANGEABLES MAINTENANT.
func set_filter(tradable: bool) -> void:
	if tradable == only_tradable:
		return
	Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
	only_tradable = tradable
	confirm_id = ""
	_fill()
	var f := first_focus()
	if f and hub:
		hub.focus_later(f)
	if hub:
		hub.refresh_prompts()


func toggle_filter() -> void:
	set_filter(not only_tradable)


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

## Focus : premier échange possible, sinon la première ligne qui a un bouton.
func first_focus() -> Control:
	for id in order:
		var b: HubButton = rows[id].button
		if b and not b.disabled:
			return b
	for id in order:
		if rows[id].button:
			return rows[id].button
	return null


func prompts() -> Array:
	if popup_open():
		var out := []
		if popup.primary_button:
			out.append([HubPrompts.ACCEPT, popup.primary_text])
		out.append([HubPrompts.BACK, Lang.t("Fermer", "Close")])
		return out
	var filt := [HubPrompts.FILTER, Lang.t("Filtre", "Filter")]
	if confirm_id != "":
		return [[HubPrompts.ACCEPT, Lang.t("Confirmer l'échange", "Confirm the exchange")], [HubPrompts.BACK, Lang.t("Annuler", "Cancel")], filt]
	return [[HubPrompts.ACCEPT, Lang.t("Échanger", "Trade")], filt, [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]


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


## Y (manette) : filtre. Tab est lu dans _input (avant la navigation du
## focus de Godot, qui le prendrait).
func handle_input(event: InputEvent) -> bool:
	if popup_open():
		return false
	var j := event as InputEventJoypadButton
	if j and j.pressed and j.button_index == JOY_BUTTON_Y:
		toggle_filter()
		return true
	return false


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.physical_keycode != KEY_TAB or k.ctrl_pressed or k.alt_pressed:
		return
	if not is_visible_in_tree() or hub == null or popup_open() or not hub.has_method("_active") or not hub._active():
		return
	if hub.hub_menu and hub.hub_menu.is_open():
		return
	get_viewport().set_input_as_handled()
	toggle_filter()


func on_prompt(id: String) -> void:
	if id == HubPrompts.FILTER:
		toggle_filter()


func shown() -> void:
	_update_note()


func hidden() -> void:
	_cancel_confirm()
	if popup_open():
		popup.close()


# --------------------------------------------------------------------------
# Focus, aide de la réserve
# --------------------------------------------------------------------------

func _on_focus_changed(c: Control) -> void:
	if not is_visible_in_tree() or hub == null or popup_open():
		return
	if confirm_id != "" and c != _button_of(confirm_id):
		_cancel_confirm()
	for id in rows:
		var e: Dictionary = rows[id]
		(e.row as HubRow).selected = e.button != null and e.button == c
	if c and is_ancestor_of(c):
		hub.refresh_prompts()
		_update_note()


func _button_of(id: String) -> HubButton:
	return rows[id].button if rows.has(id) else null


func _focused_id() -> String:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	for id in rows:
		if rows[id].button != null and rows[id].button == f:
			return id
	return ""


func _update_note() -> void:
	if column == null:
		return
	var id := confirm_id if confirm_id != "" else _focused_id()
	var pr := profile()
	if id != "" and ExchangeRules.refusal(pr, data, id, day) == "":
		column.set_note(trade_note(pr, data, id))
	elif id != "":
		var x := data.exchange(id)
		var miss := HubSamplesColumn.missing_text(pr, x.samples)
		column.set_note((miss.to_lower().left(1).to_upper() + miss.to_lower().substr(1) + ". " if miss != "" else "")
				+ Lang.t("Les échantillons tombent des ennemis : évacuez pour les garder.", "Samples drop from enemies: extract to keep them."))
	else:
		column.set_note(Lang.t("Le catalogue est permanent : chaque échange donne exactement l'objet affiché, à votre niveau.",
				"The catalogue is permanent: each exchange gives exactly the item shown, at your level."))


## « Après cet échange : 1 collier, 0 touffe. Analyse complète (contrat
## actif) aura besoin de 3 touffes et 3 colliers. » (contrats actifs qui
## n'auraient plus assez, en rouge ; BBCode du hub).
static func trade_note(pr: PlayerProfile, d: HubData, id: String) -> String:
	var x := d.exchange(id)
	var rest := HubSamplesColumn.remaining_after(pr, x.samples)
	var left := PackedStringArray()
	for k in rest:
		left.append(HubSamplesColumn.words(String(k), int(rest[k])))
	var s := Lang.t("Après cet échange : %s.", "After this exchange: %s.") % ", ".join(left)
	for cid in pr.contracts.active_ids():
		var c := d.contract(cid)
		if c.is_empty():
			continue
		# Signalé seulement si l'échange crée le manque (assez avant, plus
		# assez après) ; maquette : besoins du contrat pour les sortes
		# communes.
		var short := false
		var needs := PackedStringArray()
		for k in c.samples:
			if rest.has(k):
				needs.append(HubSamplesColumn.words(String(k), int(c.samples[k])))
				if int(rest[k]) < int(c.samples[k]) and pr.sample_count(String(k)) >= int(c.samples[k]):
					short = true
		if short:
			s += " " + Lang.t("[bad]%s[/bad] (contrat actif) aura besoin de %s.", "[bad]%s[/bad] (active contract) will need %s.") % [
				HubSamplesColumn.esc(HubData.text_of(c.title)), HubSamplesColumn.join_words(needs)]
	return s


## Filtre cliquable (classe .chip de la maquette) : pavé à contour noir,
## texte semi-gras de 13 px ; choisi : fond brun, texte jaune, liseré jaune
## de 3 px en bas. Pas de focus (Tab / Y changent le filtre).
class ExchangeChip extends Button:
	var label := ""
	var on := false:
		set(v):
			on = v
			queue_redraw()

	static func make(t: String, cb: Callable) -> ExchangeChip:
		var c := ExchangeChip.new()
		c.label = t
		c.pressed.connect(cb)
		return c

	func _ready() -> void:
		text = ""
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, empty)
		var f := HubStyle.font("semi")
		var fs := HubStyle.fs(13)
		custom_minimum_size = Vector2(ceilf(HubStyle.text_width(label, f, fs) + HubStyle.px(9) * 2.0 + HubStyle.px(2) * 2.0),
				ceilf(fs * 1.25 + HubStyle.px(3) * 2.0 + HubStyle.px(2) * 2.0))
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		HubStyle.draw_box(self, r, Color("4A4126") if on else HubStyle.HEADER_BG, HubStyle.px(2), 0.0)
		if on:
			var b := HubStyle.px(2)
			draw_rect(Rect2(b, r.size.y - b - HubStyle.px(3), r.size.x - b * 2.0, HubStyle.px(3)), HubStyle.YELLOW)
		var f := HubStyle.font("semi")
		var fs := HubStyle.fs(13)
		var tw := HubStyle.text_width(label, f, fs)
		draw_string(f, Vector2((r.size.x - tw) * 0.5, HubStyle.baseline(f, fs, 0.0, r.size.y - (HubStyle.px(1) if on else 0.0))),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HubStyle.YELLOW_HI if on else HubStyle.DIM)
