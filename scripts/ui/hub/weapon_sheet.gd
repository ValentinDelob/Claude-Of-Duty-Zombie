class_name HubWeaponSheet
extends HubBox
## Fiche d'arme de l'onglet ARSENAL (docs/HUB_PLAN.md §3.2, maquette écran
## 2, panneau de droite) : en-tête (pixel art, nom en couleur de rareté,
## famille et version, niveau, rareté, emplacements, « NIVEAU n REQUIS »,
## SCORE), statistiques effectives (GameWeapon.stats ; part des pièces en vert
## ou en rouge), prix et durée à la station, pièces installées et
## emplacements libres, boutons INSTALLER UNE PIÈCE, RETIRER LA PIÈCE,
## RECYCLER L'ARME.
##
## Retirer et recycler se font en DEUX APPUIS (D14) : le premier arme le
## bouton, qui dit la conséquence (« CONFIRMER : LA PIÈCE SERA DÉTRUITE ») ;
## le second émet la demande. Échap (cancel_armed) ou un déplacement du focus
## annule. La fiche ne touche jamais au profil : le panneau applique les
## demandes (signaux) et enregistre.

## Choisir une pièce pour l'emplacement `slot` (index, emplacement libre).
signal install_requested(slot: int)
## Retrait confirmé (deuxième appui) de la pièce `part_uid`.
signal remove_confirmed(part_uid: String)
## Recyclage confirmé (deuxième appui) de l'arme affichée.
signal recycle_confirmed
## L'état d'un double appui a changé (invites à recalculer).
signal armed_changed

const NONE := ""
const REMOVE := "remove"
const RECYCLE := "recycle"

## Arme affichée (exemplaire de l'arsenal ou arme de base).
var weapon: OwnedWeapon
var is_base := false
## Emplacements (HubSlot), dans l'ordre : pièces installées puis libres.
var slots: Array = []
var install_button: HubButton
var remove_button: HubButton
var recycle_button: HubButton
## Double appui en cours (NONE, REMOVE, RECYCLE).
var armed := NONE
## Emplacement visé par RETIRER (dernier emplacement de pièce choisi).
var target_slot := 0
## Libellés lus par les tests.
var name_label: Label
var score_label: Label
var stat_rows: Array = []
## Contrôle à gauche de la fiche (ligne choisie de la liste).
var left_target: Control
var _hub: Node


func _init() -> void:
	super("", "", false, true)


## Construit la fiche de `w` (null : fiche vide).
func show_weapon(hub: Node, pr: PlayerProfile, w: OwnedWeapon, keep_target := false) -> void:
	_hub = hub
	var old_target := target_slot
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	slots.clear()
	stat_rows.clear()
	install_button = null
	remove_button = null
	recycle_button = null
	armed = NONE
	weapon = w
	if w == null:
		var l := HubStyle.label(Lang.t("Aucune arme ne correspond au filtre.", "No weapon matches the filter."), 15, HubStyle.DIM)
		content.add_child(HubBox.pad(l, 16, 16, 16, 16))
		return
	is_base = w.uid.begins_with(BaseWeapons.UID_PREFIX)
	content.add_child(_head(pr, w))
	var body := SheetBody.new()
	body.add_theme_constant_override("separation", 0)
	content.add_child(body)
	body.add_child(_stats(w))
	body.add_child(_parts(w))
	content.add_child(HubBox.spring())
	content.add_child(_buttons(pr, w))
	target_slot = clampi(old_target if keep_target else 0, 0, maxi(w.parts.size() - 1, 0))
	_link_focus()


# --------------------------------------------------------------------------
# En-tête
# --------------------------------------------------------------------------

func _head(pr: PlayerProfile, w: OwnedWeapon) -> Control:
	var head := SheetHead.new()
	head.tint = HubStyle.rarity_color(w.rarity)
	var row := HubBox.hbox(18)
	head.add_child(HubBox.pad(row, 16, 14, 16, 10))
	var art := IconWell.new()
	art.custom_minimum_size = HubStyle.pxv(250, 92)
	art.add_child(HubIcon.make(HubGear.weapon_art(w.weapon_id), 8))
	row.add_child(art)
	var col := HubBox.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	name_label = HubStyle.label(HubGear.weapon_name(w.weapon_id), 30, HubStyle.rarity_color(w.rarity), "impact", true, 0.04)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	var sub := HubGear.weapon_class(w.weapon_id)
	if is_base:
		sub += Lang.t(" · arme de base", " · base weapon")
	else:
		var v := HubGear.version_of(pr, w)
		if v.y > 1:
			sub += Lang.t(" · version %d de %d", " · version %d of %d") % [v.x, v.y]
	col.add_child(HubStyle.label(sub, 13, HubStyle.DIM))
	# Ligne niveau / rareté / emplacements, 8 px sous le sous-titre ; elle
	# passe à la ligne si la taille des menus l'exige (130 %).
	col.add_child(HubBox.gap(0, 8))
	var bottom := HubBox.hbox(16)
	col.add_child(bottom)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", int(HubStyle.px(16)))
	line.add_theme_constant_override("v_separation", int(HubStyle.px(2)))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(line)
	var lv := HubBox.hbox(4)
	var lvt := HubStyle.label(Lang.t("Niveau", "Level"), 15, HubStyle.PAPER)
	lvt.size_flags_vertical = Control.SIZE_SHRINK_END
	lv.add_child(lvt)
	var lvn := HubStyle.label(str(w.level), 18, HubStyle.PAPER, "bold")
	lvn.size_flags_vertical = Control.SIZE_SHRINK_END
	lv.add_child(lvn)
	lv.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(lv)
	var rn := HubStyle.label(GameWeapon.rarity_name(w.rarity), 15, HubStyle.rarity_color(w.rarity), "bold")
	rn.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(rn)
	var sl := HubStyle.label((Lang.t("%d emplacement", "%d slot") if w.slot_count() == 1
			else Lang.t("%d emplacements", "%d slots")) % w.slot_count(), 15, HubStyle.PAPER)
	sl.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(sl)
	if w.level > pr.level():
		var lock := HubTag.make(Lang.t("NIVEAU %d REQUIS", "LEVEL %d REQUIRED") % w.level, HubTag.LOCK)
		lock.size_flags_vertical = Control.SIZE_SHRINK_END
		line.add_child(lock)
	# SCORE à droite de la ligne (centrée sur sa hauteur, comme la maquette).
	var sc := HubBox.vbox(0)
	var st := HubStyle.label("SCORE", 13, HubStyle.DIM)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(st)
	score_label = HubStyle.label(str(w.score()), 30, HubStyle.YELLOW, "impact", true)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(score_label)
	bottom.add_child(sc)
	return head


# --------------------------------------------------------------------------
# Statistiques
# --------------------------------------------------------------------------

func _stats(w: OwnedWeapon) -> Control:
	var v := HubBox.vbox(0)
	# 380 px sur 732 avec les marges et le filet (box-sizing de la maquette) :
	# proportion gardée à toute taille des menus.
	var m := HubBox.pad(v, 16, 12, 18, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_stretch_ratio = 380.0
	v.add_child(HubStyle.label(Lang.t("STATISTIQUES", "STATS"), 13, HubStyle.DIM, "impact", false, 0.06))
	v.add_child(HubBox.gap(0, 6))
	var lines := HubGear.melee_lines(w.weapon_id) if HubGear.is_melee(w.weapon_id) else HubGear.stat_lines(w)
	for l in lines:
		var r := StatRow.new()
		r.line = l
		v.add_child(r)
		stat_rows.append(r)
	v.add_child(HubBox.gap(0, 10))
	var st := HubGear.station_text(w)
	var price := RichTextLabel.new()
	price.bbcode_enabled = true
	price.fit_content = true
	price.scroll_active = false
	price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_theme_font_override("normal_font", HubStyle.font("ui"))
	price.add_theme_font_override("bold_font", HubStyle.font("bold"))
	price.add_theme_font_size_override("normal_font_size", HubStyle.fs(13))
	price.add_theme_font_size_override("bold_font_size", HubStyle.fs(13))
	price.add_theme_color_override("default_color", HubStyle.DIM)
	if st == "":
		price.text = Lang.t("Attaque de corps à corps séparée : elle ne se construit pas à la station.",
				"Separate melee attack: it is not built at the station.")
	else:
		var p := BuildRules.owned_price(w)
		price.text = Lang.t("Prix à la station : [b][color=#DBD6C2]%s[/color][/b] ferraille · %s",
				"Station price: [b][color=#DBD6C2]%s[/color][/b] scrap · %s") % [HubStyle.num(p), BuildRules.rounds_text(BuildRules.rounds(p))]
	v.add_child(price)
	return m


# --------------------------------------------------------------------------
# Pièces installées
# --------------------------------------------------------------------------

func _parts(w: OwnedWeapon) -> Control:
	var v := HubBox.vbox(8)
	var m := HubBox.pad(v, 16, 12, 16, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_stretch_ratio = 352.0
	var head := HubBox.hbox(8)
	var t := HubStyle.label(Lang.t("PIÈCES INSTALLÉES", "MOUNTED PARTS"), 13, HubStyle.DIM, "impact", false, 0.06)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(HubStyle.label("%d / %d" % [w.parts.size(), w.slot_count()], 13, HubStyle.DIM))
	v.add_child(head)
	if is_base:
		var note := HubStyle.label(Lang.t("Arme de base : ni modifiable ni recyclable. Améliorée en partie et ramenée, elle devient une nouvelle version de l'arsenal.",
				"Base weapon: it can't be modified or recycled. Upgraded during a match and brought back, it becomes a new arsenal version."), 13, HubStyle.DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)
		return m
	for i in w.slot_count():
		var s := HubSlot.new(76.0)
		s.index = i
		if i < w.parts.size():
			var p := w.parts[i]
			s.click_activates = false
			s.box.alignment = BoxContainer.ALIGNMENT_BEGIN
			s.box.add_child(HubIcon.make("part", 4))
			var col := HubBox.vbox(2)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.alignment = BoxContainer.ALIGNMENT_CENTER
			var nl := HubBox.hbox(5)
			nl.add_child(HubStyle.label(HubGear.part_name(p), 15, HubStyle.PAPER, "bold"))
			var lv := HubStyle.label(HubGear.level_text(p.level), 13, HubStyle.DIM)
			lv.size_flags_vertical = Control.SIZE_SHRINK_END
			lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lv.clip_text = true
			nl.add_child(lv)
			col.add_child(nl)
			col.add_child(mods_rich(HubGear.ordered_mods(p), 13))
			s.box.add_child(col)
			s.hint = Lang.t("Retirer cette pièce : deux appuis, elle sera détruite.", "Remove this part: two presses, it will be destroyed.")
			s.chosen.connect(func():
				target_slot = s.index
				_hint(s.hint))
			s.activated.connect(func():
				target_slot = s.index
				arm(REMOVE))
		else:
			s.empty = true
			var l := HubStyle.label(Lang.t("+ EMPLACEMENT LIBRE", "+ FREE SLOT"), 15, HubStyle.DIM, "impact", false, 0.06)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.box.add_child(l)
			s.hint = Lang.t("Choisir une pièce à installer ici.", "Pick a part to install here.")
			s.chosen.connect(func(): _hint(s.hint))
			s.activated.connect(func(): install_requested.emit(s.index))
		v.add_child(s)
		slots.append(s)
	return m


## Mêmes modificateurs en un texte qui passe à la ligne s'il manque de place
## (emplacements de la fiche, taille des menus à 130 %).
static func mods_rich(mods: Dictionary, size: int, short := false) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("normal_font", HubStyle.font("semi"))
	t.add_theme_font_size_override("normal_font_size", HubStyle.fs(size))
	t.add_theme_color_override("default_color", HubStyle.PAPER)
	t.add_theme_constant_override("line_separation", 0)
	var parts := PackedStringArray()
	for it in HubGear.mod_items(mods, short):
		parts.append("[color=#%s]%s[/color]" % [(HubStyle.OK if it[1] else HubStyle.BAD).to_html(false), String(it[0])])
	t.text = " · ".join(parts)
	return t


## Modificateurs en couleur : « cadence +10 % · précision −6 % ».
static func mods_row(mods: Dictionary, size: int, short := false) -> HBoxContainer:
	var h := HubBox.hbox(0)
	var items := HubGear.mod_items(mods, short)
	for i in items.size():
		if i > 0:
			h.add_child(HubStyle.label(" · ", size, HubStyle.PAPER, "semi"))
		h.add_child(HubStyle.label(String(items[i][0]), size, HubStyle.OK if items[i][1] else HubStyle.BAD, "semi"))
	return h


# --------------------------------------------------------------------------
# Boutons et double appui
# --------------------------------------------------------------------------

func _buttons(pr: PlayerProfile, w: OwnedWeapon) -> Control:
	var h := HubBox.hbox(10)
	var m := HubBox.pad(h, 12, 8, 12, 12)
	# INSTALLER et RETIRER à gauche (passent l'un sous l'autre s'il manque de
	# place, taille des menus à 130 %), RECYCLER à droite.
	var left := HFlowContainer.new()
	left.add_theme_constant_override("h_separation", int(HubStyle.px(10)))
	left.add_theme_constant_override("v_separation", int(HubStyle.px(8)))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	install_button = HubButton.make(Lang.t("INSTALLER UNE PIÈCE", "INSTALL A PART"), func():
		install_requested.emit(w.parts.size()), HubButton.NORMAL, _install_hint(pr, w))
	install_button.disabled = is_base or w.free_slots() <= 0 or pr.parts.is_empty()
	install_button.focus_entered.connect(func(): _hint(install_button.hint))
	left.add_child(install_button)
	if not is_base and not w.parts.is_empty():
		remove_button = HubButton.make("", _on_remove, HubButton.NORMAL)
		remove_button.focus_entered.connect(func(): _hint(remove_button.hint))
		remove_button.focus_exited.connect(_maybe_disarm.bind(REMOVE))
		left.add_child(remove_button)
	recycle_button = HubButton.make("", _on_recycle, HubButton.NORMAL)
	recycle_button.disabled = is_base
	recycle_button.focus_entered.connect(func(): _hint(recycle_button.hint))
	recycle_button.focus_exited.connect(_maybe_disarm.bind(RECYCLE))
	recycle_button.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(recycle_button)
	_update_buttons()
	return m


func _install_hint(pr: PlayerProfile, w: OwnedWeapon) -> String:
	if is_base:
		return Lang.t("Arme de base : pas de pièce.", "Base weapon: no parts.")
	if w.free_slots() <= 0:
		return Lang.t("Aucun emplacement libre : retirez d'abord une pièce.", "No free slot: remove a part first.")
	if pr.parts.is_empty():
		return Lang.t("Aucune pièce en stock : on en trouve en partie.", "No part in stock: they are found during matches.")
	return Lang.t("Choisir une pièce pour le premier emplacement libre.", "Pick a part for the first free slot.")


func _update_buttons() -> void:
	if remove_button:
		if armed == REMOVE:
			remove_button.label = Lang.t("CONFIRMER : LA PIÈCE SERA DÉTRUITE", "CONFIRM: THE PART WILL BE DESTROYED")
			remove_button.kind = HubButton.DANGER
			remove_button.hint = Lang.t("Une pièce retirée est détruite : elle ne revient pas dans l'onglet PIÈCES.",
					"A removed part is destroyed: it does not go back to the PARTS tab.")
		else:
			remove_button.label = Lang.t("RETIRER LA PIÈCE", "REMOVE THE PART")
			remove_button.kind = HubButton.NORMAL
			remove_button.hint = Lang.t("Retirer la pièce choisie : deux appuis, elle sera détruite.",
					"Remove the chosen part: two presses, it will be destroyed.")
	if recycle_button:
		if armed == RECYCLE:
			recycle_button.label = Lang.t("CONFIRMER : L'ARME SERA DÉTRUITE", "CONFIRM: THE WEAPON WILL BE DESTROYED")
			recycle_button.kind = HubButton.DANGER
			recycle_button.hint = Lang.t("Recycler au hub ne rapporte rien : l'arme et ses pièces quittent l'arsenal.",
					"Recycling at the hub gives nothing back: the weapon and its parts leave the arsenal.")
		else:
			recycle_button.label = Lang.t("RECYCLER L'ARME", "RECYCLE THE WEAPON")
			recycle_button.kind = HubButton.NORMAL
			recycle_button.hint = Lang.t("Arme de base : jamais recyclée." if is_base else "Recycler cette version : deux appuis, rien n'est rendu.",
					"Base weapon: never recycled." if is_base else "Recycle this version: two presses, nothing is given back.")
	for s in slots:
		s.marked = armed == REMOVE and s.index == target_slot


## Premier appui de RETIRER ou RECYCLER (ou Suppr sur une pièce).
func arm(what: String) -> void:
	if weapon == null or is_base:
		return
	if what == REMOVE and (remove_button == null or weapon.parts.is_empty()):
		return
	armed = what
	_update_buttons()
	var b := remove_button if what == REMOVE else recycle_button
	if b and b.is_inside_tree():
		b.grab_focus()
	_hint(b.hint if b else "")
	armed_changed.emit()


## Annule un double appui en cours ; vrai s'il y en avait un.
func cancel_armed() -> bool:
	if armed == NONE:
		return false
	var was := armed
	armed = NONE
	_update_buttons()
	armed_changed.emit()
	if was == REMOVE and target_slot < slots.size():
		(slots[target_slot] as Control).grab_focus()
	return true


func _on_remove() -> void:
	if armed != REMOVE:
		arm(REMOVE)
		return
	if target_slot < weapon.parts.size():
		var uid := weapon.parts[target_slot].uid
		armed = NONE
		remove_confirmed.emit(uid)


func _on_recycle() -> void:
	if armed != RECYCLE:
		arm(RECYCLE)
		return
	armed = NONE
	recycle_confirmed.emit()


## Le focus quitte le bouton armé : le double appui est annulé (sans voler
## le focus).
func _maybe_disarm(what: String) -> void:
	if armed == what:
		_disarm_if_left.call_deferred(what)


func _disarm_if_left(what: String) -> void:
	if armed == what and is_inside_tree():
		var b := remove_button if what == REMOVE else recycle_button
		if b == null or not b.has_focus():
			armed = NONE
			_update_buttons()
			armed_changed.emit()


func _hint(t: String) -> void:
	if _hub:
		_hub.set_hint(t)


## Premier élément choisissable de la fiche (A sur une ligne de la liste).
func first_control() -> Control:
	for s in slots:
		return s
	for b in [install_button, recycle_button]:
		if b and not b.disabled:
			return b
	return null


## Voisins de focus : colonne des emplacements au-dessus des boutons ; à
## gauche, la ligne choisie de la liste.
func _link_focus() -> void:
	var btns: Array = []
	for b in [install_button, remove_button, recycle_button]:
		if b:
			btns.append(b)
	for i in slots.size():
		var s: Control = slots[i]
		if i > 0:
			s.focus_neighbor_top = s.get_path_to(slots[i - 1])
		if i < slots.size() - 1:
			s.focus_neighbor_bottom = s.get_path_to(slots[i + 1])
		elif not btns.is_empty():
			s.focus_neighbor_bottom = s.get_path_to(btns[0])
	if not slots.is_empty():
		for b in btns:
			(b as Control).focus_neighbor_top = (b as Control).get_path_to(slots[slots.size() - 1])
	set_left(left_target)


func set_left(c: Control) -> void:
	left_target = c
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or not is_inside_tree():
		return
	for s in slots:
		(s as Control).focus_neighbor_left = (s as Control).get_path_to(c)
	if install_button:
		install_button.focus_neighbor_left = install_button.get_path_to(c)


## En-tête de la fiche : dégradé de la couleur de rareté (14 % à gauche,
## transparent à 60 %), liseré noir en bas.
class SheetHead extends MarginContainer:
	var tint := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("margin_bottom", int(HubStyle.px(2)))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var a := Color(tint, 0.14)
		var z := Color(tint, 0.0)
		var x := r.size.x * 0.6
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(x, 0), Vector2(x, r.size.y), Vector2(0, r.size.y)]),
				PackedColorArray([a, z, z, a]))
		draw_rect(Rect2(0, r.size.y - HubStyle.px(2), r.size.x, HubStyle.px(2)), HubStyle.BLACK)


## Corps de la fiche : deux colonnes, filet noir de 2 px entre elles.
class SheetBody extends HBoxContainer:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if get_child_count() > 1:
			var c := get_child(0) as Control
			draw_rect(Rect2(c.position.x + c.size.x - HubStyle.px(2), 0, HubStyle.px(2), size.y), HubStyle.BLACK)


## Cadre enfoncé de l'illustration (fond #141516, contour noir, biseau haut).
class IconWell extends CenterContainer:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		HubStyle.draw_box(self, Rect2(Vector2.ZERO, size), Color("141516"), HubStyle.px(2), 0.0, HubStyle.HEADER_BG,
				Color(0, 0, 0, 0), HubStyle.px(2))


## Ligne de statistique (.stat : nom 120 px, barre, valeur 92 px à droite ;
## 24 px de haut, 14 px) ; la part des pièces est en vert (bonus) ou en rouge
## (malus) au bout de la barre.
class StatRow extends Control:
	var line: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, HubStyle.px(24))

	func value_text() -> String:
		return String(line.get("text", "")) + ("  " + String(line.delta) if String(line.get("delta", "")) != "" else "")

	func _draw() -> void:
		var f := HubStyle.font("ui")
		var s := HubStyle.fs(14)
		var ss := HubStyle.fs(13)
		var h := size.y
		draw_string(f, Vector2(0, HubStyle.baseline(f, s, 0, h)), String(line.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT,
				HubStyle.px(120), s, HubStyle.PAPER)
		var vw := HubStyle.px(92)
		var gap := HubStyle.px(10)
		var bx := HubStyle.px(120) + gap
		var bw := size.x - bx - gap - vw
		var bh := HubStyle.px(10)
		var bar := Rect2(bx, (h - bh) * 0.5, bw, bh)
		draw_rect(bar, HubStyle.BLACK)
		var inner := bar.grow(-HubStyle.px(2))
		draw_rect(inner, HubStyle.TRACK)
		var r1 := float(line.get("ratio", 0.0))
		var r0 := float(line.get("base_ratio", r1))
		_stripes(inner, 0.0, minf(r0, r1), HubStyle.PLASTER)
		if r1 > r0 + 0.001:
			_stripes(inner, r0, r1, HubStyle.OK)
		elif r0 > r1 + 0.001:
			_stripes(inner, r1, r0, HubStyle.BAD)
		# Valeur, puis écart des pièces en petit, alignés à droite.
		var x := size.x
		var delta := String(line.get("delta", ""))
		if delta != "":
			var dw := HubStyle.text_width(delta, f, ss)
			x -= dw
			draw_string(f, Vector2(x, HubStyle.baseline(f, s, 0, h)), delta, HORIZONTAL_ALIGNMENT_LEFT, -1, ss,
					HubStyle.OK if line.get("good", true) else HubStyle.BAD)
			x -= HubStyle.px(4)
		var t := String(line.get("text", ""))
		var tw := HubStyle.text_width(t, f, s)
		draw_string(f, Vector2(x - tw, HubStyle.baseline(f, s, 0, h)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, s, HubStyle.PAPER)

	## Segments de 6 px séparés de 2 px (.sbar), de `a` à `b` (fractions).
	func _stripes(inner: Rect2, a: float, b: float, col: Color) -> void:
		var x0 := floorf(inner.size.x * clampf(a, 0.0, 1.0))
		var x1 := floorf(inner.size.x * clampf(b, 0.0, 1.0))
		if x1 <= x0:
			return
		var seg := maxf(HubStyle.px(6), 2.0)
		var unit := seg + maxf(HubStyle.px(2), 1.0)
		var dark := col.lerp(HubStyle.BLACK, 0.6)
		draw_rect(Rect2(inner.position.x + x0, inner.position.y, x1 - x0, inner.size.y), dark)
		var x := floorf(x0 / unit) * unit
		while x < x1:
			var s0 := maxf(x, x0)
			var s1 := minf(x + seg, x1)
			if s1 > s0:
				draw_rect(Rect2(inner.position.x + s0, inner.position.y, s1 - s0, inner.size.y), col)
			x += unit
