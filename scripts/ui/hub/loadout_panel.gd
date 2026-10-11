class_name HubLoadoutPanel
extends HubPanel
## Onglet DÉPART (docs/HUB_PLAN.md §3.6, maquette écran 8) :
##   - à gauche, ARMES DE DÉPART : trois emplacements (§4.10 : au moins une,
##     au plus trois armes de base distinctes ; un emplacement non choisi reste
##     vide au départ), puis les ARMES DE BASE disponibles (Entrée / A :
##     ajouter ou retirer ; la dernière ne se retire pas) ;
##   - à droite, CONSTRUCTIBLES À LA STATION : les armes à feu de l'arsenal,
##     prix (BuildRules.price) et durée, celles d'un niveau trop haut grisées
##     « NIV. n REQUIS ».
## Chaque changement enregistre la sélection (PlayerProfile.
## set_starting_weapons, une écriture) ; elle est envoyée au serveur au
## lancement de la partie (Session.send_local_loadout).

const LEFT_W := 620.0
const RIGHT_W := 612.0
## Description courte de chaque arme de base [FR, EN] (autre : la famille).
const BASE_TEXT := {
	"m1911": ["peu efficace, munitions rechargeables à la station", "weak, ammo refilled at the station"],
	"bat": ["corps à corps, deux zombies par coup, coûte de l'énergie",
		"melee, two zombies per swing, costs energy"],
}

var slots: Array = []  # HubSlot ×3
var base_rows: Array = []  # HubPickRow, clé = identifiant d'arme de base
var station_box: HubBox
var action_button: HubButton
## Dernier élément choisi : "slot:<i>" ou "base:<id>" (bouton du bas).
var current := "slot:0"
var _root: HBoxContainer


func build() -> void:
	_root = HubBox.hbox(16)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_fill()


func refresh() -> void:
	var f := get_viewport().gui_get_focus_owner() if get_viewport() else null
	var key := ""
	if f and is_ancestor_of(f):
		if f is HubSlot:
			key = "slot:%d" % (f as HubSlot).index
		elif f is HubPickRow:
			key = "base:" + (f as HubPickRow).key
		elif f == action_button:
			key = current
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_fill()
	if key != "":
		var c := _control_of(key)
		if c:
			c.grab_focus()


func _fill() -> void:
	var pr := profile()
	slots.clear()
	base_rows.clear()
	# Armes de départ.
	var left := HubBox.new(Lang.t("ARMES DE DÉPART", "STARTING WEAPONS"), Lang.t("au moins 1, au plus 3", "at least 1, at most 3"), false, true)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = LEFT_W
	_root.add_child(left)
	var v := left.content
	var sl := HubBox.hbox(12)
	v.add_child(HubBox.pad(sl, 16, 16, 16, 16))
	var sel := pr.starting_weapons
	for i in BaseWeapons.MAX_START:
		var s := HubSlot.new(120.0, true)
		s.index = i
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < sel.size():
			var id := sel[i]
			var n := HubStyle.label(str(i + 1), 13, HubStyle.DIM)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s.box.add_child(n)
			var ic := HubIcon.make(HubGear.weapon_art(id), 4 if not HubGear.is_melee(id) else 3)
			s.box.add_child(ic)
			var nl := HubStyle.label(HubGear.weapon_name(id), 15, HubStyle.PAPER, "bold")
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# Sans clip_text : il couperait l'accent des capitales (PÉTOIRE) ; la
			# coupure « … » suffit en largeur.
			nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			s.box.add_child(nl)
			s.hint = _last_hint() if sel.size() <= BaseWeapons.MIN_START \
					else Lang.t("Retirer cette arme du départ.", "Remove this weapon from the loadout.")
		else:
			s.empty = true
			var n := HubStyle.label(str(i + 1), 15, HubStyle.DIM, "impact", false, 0.06)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s.box.add_child(n)
			var e := HubStyle.label(Lang.t("VIDE AU DÉPART", "EMPTY AT START"), 13, HubStyle.DIM, "impact", false, 0.06)
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s.box.add_child(e)
			s.hint = Lang.t("Choisir une arme de base pour cet emplacement.", "Pick a base weapon for this slot.")
		s.chosen.connect(_on_chosen.bind("slot:%d" % i, s))
		s.activated.connect(_slot_pressed.bind(i))
		sl.add_child(s)
		slots.append(s)
	v.add_child(HubRow.group(Lang.t("ARMES DE BASE (NIVEAU 1, COMMUNES, DONNÉES À TOUS)", "BASE WEAPONS (LEVEL 1, COMMON, GIVEN TO EVERYONE)")))
	var ids := BaseWeapons.ids()
	for i in ids.size():
		var id := ids[i]
		var row := HubPickRow.new()
		row.key = id
		row.alt = i % 2 == 1
		row.box.add_child(HubIcon.make(HubGear.weapon_art(id), 2))
		row.box.add_child(HubStyle.label(HubGear.weapon_name(id), 15, HubStyle.PAPER))
		var t: Array = BASE_TEXT.get(id, [HubGear.weapon_class(id).to_lower(), HubGear.weapon_class(id).to_lower()])
		var d := HubStyle.label(Lang.t(t[0], t[1]), 13, HubStyle.DIM)
		d.clip_text = true
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.box.add_child(d)
		if id in sel:
			row.box.add_child(HubTag.make(Lang.t("CHOISIE", "PICKED"), HubTag.READY))
		row.hint = (_last_hint() if sel.size() <= BaseWeapons.MIN_START else Lang.t("Retirer du départ.", "Remove from the loadout.")) \
				if id in sel else (Lang.t("Les trois emplacements sont pris : retirez d'abord une arme.", "All three slots are taken: remove a weapon first.")
				if sel.size() >= BaseWeapons.MAX_START else Lang.t("Ajouter au départ.", "Add to the loadout."))
		row.chosen.connect(_on_chosen.bind("base:" + id, row))
		row.activated.connect(toggle.bind(id))
		v.add_child(row)
		base_rows.append(row)
	v.add_child(HubBox.spring())
	var btns := HubBox.hbox(10)
	v.add_child(HubBox.pad(btns, 12, 12, 12, 12))
	action_button = hub_button("", _action, HubButton.NORMAL)
	action_button.focus_entered.connect(func(): hub.set_hint(action_button.hint))
	btns.add_child(action_button)
	_update_action()
	_link_focus()
	# Constructibles à la station.
	_root.add_child(_station(pr))


func _last_hint() -> String:
	return Lang.t("Impossible de retirer la dernière arme de départ.", "You can't remove the last starting weapon.")


func _station(pr: PlayerProfile) -> HubBox:
	station_box = HubBox.new(Lang.t("CONSTRUCTIBLES À LA STATION", "BUILDABLE AT THE STATION"),
			Lang.t("contre de la ferraille, en partie", "for scrap, during a match"), false, true)
	station_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	station_box.size_flags_stretch_ratio = RIGHT_W
	var v := station_box.content
	var ok: Array[OwnedWeapon] = []
	var ko: Array[OwnedWeapon] = []
	for w in pr.weapons:
		if WeaponDB.exists(w.weapon_id):
			(ok if pr.can_use(w) else ko).append(w)
	ok.sort_custom(func(a, b):
		var pa := BuildRules.owned_price(a)
		var pb := BuildRules.owned_price(b)
		return pa > pb if pa != pb else HubGear.before(a, b, "score"))
	ko.sort_custom(func(a, b): return HubGear.before(a, b, "level"))
	var i := 0
	for w in ok:
		var row := HubRow.new()
		row.alt = i % 2 == 1
		i += 1
		row.box.add_child(HubIcon.make(HubGear.weapon_art(w.weapon_id), 2))
		row.box.add_child(HubStyle.label(HubGear.weapon_name(w.weapon_id), 15, HubStyle.rarity_color(w.rarity)))
		var ver := HubGear.version_of(pr, w)
		row.box.add_child(HubStyle.label(("v%d · " % ver.x if ver.x > 1 else "") + HubGear.level_text(w.level), 13, HubStyle.DIM))
		row.box.add_child(HubBox.spring(false))
		var price := BuildRules.owned_price(w)
		row.box.add_child(HubStyle.label(HubStyle.num(price), 15, HubStyle.PAPER, "bold"))
		var r := HubStyle.label(BuildRules.rounds_text(BuildRules.rounds(price)), 13, HubStyle.DIM)
		r.custom_minimum_size.x = HubStyle.px(76)
		row.box.add_child(r)
		v.add_child(row)
	for w in ko:
		var row := HubRow.new()
		row.alt = i % 2 == 1
		i += 1
		var ic := HubIcon.make(HubGear.weapon_art(w.weapon_id), 2)
		ic.dim = 0.5
		row.box.add_child(ic)
		row.box.add_child(HubStyle.label(HubGear.weapon_name(w.weapon_id), 15, HubArsenalPanel.LOCK_TEXT))
		row.box.add_child(HubBox.spring(false))
		row.box.add_child(HubTag.make(Lang.t("NIV. %d REQUIS", "LVL %d REQUIRED") % w.level, HubTag.LOCK))
		v.add_child(row)
	var foot := HubStyle.label(Lang.t("Chaque partie commence à 0 ferraille. Une arme construite reste toujours dans l'arsenal, même si la partie est perdue.",
			"Every match starts with 0 scrap. A built weapon always stays in the arsenal, even if the match is lost.")
			if not pr.weapons.is_empty() else Lang.t("L'arsenal est vide : les armes gardées sur vous à l'évacuation y arrivent, puis se construisent ici contre de la ferraille. Chaque partie commence à 0 ferraille.",
			"The arsenal is empty: weapons you carry when you evacuate end up there, then can be built here for scrap. Every match starts with 0 scrap."), 13, HubStyle.DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(HubBox.pad(foot, 12, 12, 12, 12))
	return station_box


# --------------------------------------------------------------------------
# Actions (une écriture du profil chacune)
# --------------------------------------------------------------------------

## Ajoute ou retire l'arme de base `id` de la sélection ; faux si refusé
## (dernière arme, trois emplacements pris).
func toggle(id: String) -> bool:
	var sel := Array(profile().starting_weapons)
	if id in sel:
		if sel.size() <= BaseWeapons.MIN_START:
			_refuse(_last_hint())
			return false
		sel.erase(id)
	else:
		if sel.size() >= BaseWeapons.MAX_START:
			_refuse(Lang.t("Les trois emplacements sont pris : retirez d'abord une arme.", "All three slots are taken: remove a weapon first."))
			return false
		sel.append(id)
	return _apply(sel)


## Retire l'arme de l'emplacement `i` (pas la dernière).
func remove_slot(i: int) -> bool:
	var sel := Array(profile().starting_weapons)
	if i < 0 or i >= sel.size():
		return false
	if sel.size() <= BaseWeapons.MIN_START:
		_refuse(_last_hint())
		return false
	sel.remove_at(i)
	return _apply(sel)


func _apply(sel: Array) -> bool:
	if not profile().set_starting_weapons(PackedStringArray(sel)):
		return false
	hub.save_profile()
	return true


func _refuse(t: String) -> void:
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	hub.set_hint(t)


func _slot_pressed(i: int) -> void:
	if i < profile().starting_weapons.size():
		remove_slot(i)
		return
	# Emplacement vide : aller à la première arme de base non choisie.
	for r in base_rows:
		if not (r as HubPickRow).key in profile().starting_weapons:
			(r as Control).grab_focus()
			return
	if not base_rows.is_empty():
		(base_rows[0] as Control).grab_focus()


func _on_chosen(key: String, c: Control) -> void:
	current = key
	# Ligne de l'arme de base correspondante gardée en surbrillance (maquette :
	# emplacement 2 choisi, ligne BATTE sélectionnée).
	var sel := profile().starting_weapons
	var id := ""
	if key.begins_with("slot:"):
		var i := key.substr(5).to_int()
		id = sel[i] if i < sel.size() else ""
	else:
		id = key.substr(5)
	for r in base_rows:
		(r as HubPickRow).sticky = (r as HubPickRow).key == id
	_update_action()
	hub.set_hint(String(c.get("hint")))


## Bouton du bas selon le dernier élément choisi (maquette : « RETIRER DE
## L'EMPLACEMENT 2 »).
func _update_action() -> void:
	if action_button == null:
		return
	var sel := profile().starting_weapons
	if current.begins_with("slot:"):
		var i := current.substr(5).to_int()
		if i < sel.size():
			action_button.label = Lang.t("RETIRER DE L'EMPLACEMENT %d", "REMOVE FROM SLOT %d") % (i + 1)
			action_button.disabled = sel.size() <= BaseWeapons.MIN_START
			action_button.hint = _last_hint() if action_button.disabled else Lang.t("L'emplacement restera vide au départ.", "The slot will be empty at the start.")
		else:
			action_button.label = Lang.t("CHOISIR UNE ARME", "PICK A WEAPON")
			action_button.disabled = false
			action_button.hint = Lang.t("Choisir une arme de base pour cet emplacement.", "Pick a base weapon for this slot.")
	else:
		var id := current.substr(5)
		if id in sel:
			action_button.label = Lang.t("RETIRER DU DÉPART", "REMOVE FROM LOADOUT")
			action_button.disabled = sel.size() <= BaseWeapons.MIN_START
			action_button.hint = _last_hint() if action_button.disabled else ""
		else:
			action_button.label = Lang.t("AJOUTER AU DÉPART", "ADD TO LOADOUT")
			action_button.disabled = sel.size() >= BaseWeapons.MAX_START
			action_button.hint = ""


func _action() -> void:
	if current.begins_with("slot:"):
		_slot_pressed(current.substr(5).to_int())
	else:
		toggle(current.substr(5))


func _control_of(key: String) -> Control:
	if key.begins_with("slot:"):
		var i := key.substr(5).to_int()
		return slots[i] if i < slots.size() else null
	for r in base_rows:
		if "base:" + (r as HubPickRow).key == key:
			return r
	return null


func _link_focus() -> void:
	for i in slots.size():
		var s: Control = slots[i]
		if not base_rows.is_empty():
			s.focus_neighbor_bottom = s.get_path_to(base_rows[0])
	for i in base_rows.size():
		var r: Control = base_rows[i]
		r.focus_neighbor_top = r.get_path_to(base_rows[i - 1] if i > 0 else slots[0])
		r.focus_neighbor_bottom = r.get_path_to(base_rows[i + 1] if i < base_rows.size() - 1 else action_button)
	if not base_rows.is_empty():
		action_button.focus_neighbor_top = action_button.get_path_to(base_rows[base_rows.size() - 1])


# --------------------------------------------------------------------------
# Contrat des panneaux
# --------------------------------------------------------------------------

func first_focus() -> Control:
	var c := _control_of(current)
	return c if c else (slots[0] if not slots.is_empty() else null)


func prompts() -> Array:
	return [[HubPrompts.ACCEPT, Lang.t("Choisir / retirer", "Pick / remove")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]
