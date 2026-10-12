class_name InventorySlot
extends Button
## Case de l'inventaire de partie (docs/hub_v2/InventaireJeu.dc.html) : arme
## EN MAIN (168 px de haut), arme du SAC À DOS (134 px) ou pièce trouvée
## (PIÈCES TROUVÉES). Fond en verre (Hub2Box, flou 12 px) ou jaune pâle
## quand elle est choisie, liseré 1 px plein (pointillés si la case est
## vide), trait de rareté de 3 px à gauche ; contenu dessiné par `_face`
## d'après la maquette (rendu de l'arme en object-fit: contain avec ombre,
## nom, NIV., rareté, touche 1 / 2 / 3, étiquette NEUF, LIBRE).
##
## Toutes les valeurs sont celles de la maquette (px à 100 %), passées par
## Hub2Style.px / fs (TAILLE DES MENUS).

enum Kind { HAND, BAG, PART }

const HAND_H := 168.0
const BAG_H := 134.0
## padding: 14px 14px 12px 17px ; gap: 4px.
const PAD_T := 14.0
const PAD_R := 14.0
const PAD_B := 12.0
const PAD_L := 17.0
const GAP := 4.0
## Pièce : padding 10px 14px, gap 2px, min-width 190px.
const PART_PAD_V := 10.0
const PART_PAD_H := 14.0
const PART_GAP := 2.0
const PART_MIN_W := 190.0

## Apparence : normale, choisie (fond et liseré jaunes), comparée (liseré
## rgba(242, 240, 234, 0.55)).
enum Look { NORMAL, ON, COMPARED }

var kind := Kind.HAND
## Arme de partie ({} : case vide) ; pièce : {name, effects: [[texte, bénéfique]]}
## ({} : aucune).
var data: Dictionary = {}
var key_text := ""
var key_bright := false
var is_new := false
## Niveau de l'arme trop élevé pour le joueur (NIV. en rouge).
var too_high := false
var look := Look.NORMAL

var _bg: Hub2Box
var _face: Control


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	flat = true
	text = ""
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, empty)
	_bg = Hub2Box.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_face = Control.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.texture_filter = HubRenders.FILTER
	_face.draw.connect(_draw_face)
	add_child(_face)
	focus_entered.connect(_redraw)
	focus_exited.connect(_redraw)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func setup(k: Kind) -> void:
	kind = k
	match kind:
		Kind.HAND:
			custom_minimum_size = Vector2(0, Hub2Style.px(HAND_H))
		Kind.BAG:
			custom_minimum_size = Vector2(0, Hub2Style.px(BAG_H))
		Kind.PART:
			custom_minimum_size = Vector2(Hub2Style.px(PART_MIN_W), 0)
	_apply_look()


## Remplit la case : arme (ou pièce {name, effects}) et apparence.
func show_item(d: Dictionary, lk: Look, new_tag := false, high := false) -> void:
	data = d
	look = lk
	is_new = new_tag and not d.is_empty()
	too_high = high
	if kind == Kind.PART:
		custom_minimum_size = Vector2(maxf(Hub2Style.px(PART_MIN_W), ceilf(_part_width())), ceilf(_part_height()))
		update_minimum_size()
	_apply_look()


func _redraw() -> void:
	_apply_look()


func _apply_look() -> void:
	if _bg == null:
		return
	var on := look == Look.ON
	var fill := Hub2Style.yellow_a(0.12) if on else Hub2Style.GLASS
	var line := Hub2Style.YELLOW if on else (Hub2Style.text_a(0.55) if look == Look.COMPARED else Hub2Style.white_a(0.1))
	# Focus (clavier, manette) sans être la case choisie : liseré jaune.
	if has_focus() and not on:
		line = Hub2Style.yellow_a(0.6)
	var dashed := data.is_empty() and kind != Kind.PART
	_bg.glass(fill, line, 0.0 if dashed else 1.0, Hub2Style.BLUR)
	_bg.set_meta("line", line)
	_face.queue_redraw()


## Largeur / hauteur naturelles d'une pièce (padding + textes).
func _part_width() -> float:
	var nw := Hub2Style.text_width(String(data.get("name", "")), Hub2Style.font(Hub2Style.CHAKRA, 700), Hub2Style.fs(15))
	var mw := InventoryDraw.effects_width(data.get("effects", []), 13)
	return maxf(nw, mw) + Hub2Style.px(PART_PAD_H) * 2.0 + Hub2Style.px(2)


func _part_height() -> float:
	return Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 15) + Hub2Style.px(PART_GAP) \
		+ Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13) + Hub2Style.px(PART_PAD_V) * 2.0 + Hub2Style.px(2)


func _draw_face() -> void:
	var s := _face.size
	var line: Color = _bg.get_meta("line", Hub2Style.white_a(0.1))
	if kind == Kind.PART:
		_draw_part(s)
		return
	var dashed := data.is_empty()
	if dashed:
		Hub2ArsenalDraw.draw_dashed_rect(_face, Rect2(Vector2.ZERO, s), line, maxf(Hub2Style.px(1), 1.0))
	else:
		# Trait de rareté : left 0, top 0, bottom 0, 3 px.
		_face.draw_rect(Rect2(0, 0, Hub2Style.px(3), s.y), Hub2Style.rarity_color(GameWeapon.rarity_of(data)))
	if kind == Kind.HAND and key_text != "":
		var kf := Hub2Style.font(Hub2Style.MONO, 700)
		Hub2ArsenalDraw.text(_face, key_text, Hub2Style.MONO, 700, 12, Hub2Style.TEXT if key_bright else Hub2Style.text_a(0.45), 0.0,
				Hub2Style.px(12), Hub2Style.px(8) + kf.get_ascent(Hub2Style.fs(12)))
	var x := Hub2Style.px(PAD_L)
	var w := s.x - x - Hub2Style.px(PAD_R)
	var y := Hub2Style.px(PAD_T)
	if dashed:
		var bottom := s.y - Hub2Style.px(PAD_B)
		var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 500, 13)
		Hub2ArsenalDraw.text(_face, Lang.t("LIBRE", "EMPTY"), Hub2Style.CHAKRA, 500, 13, Hub2Style.text_a(0.4), 0.12, x,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 500, 13, y + (bottom - y - lh) * 0.5, lh), w, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var id := String(data.get("id", ""))
	var lvl_col := Hub2Style.BAD_ALT if too_high else Hub2Style.text_a(0.7)
	var lvl := Hub2ArsenalView.level_text(GameWeapon.level_of(data))
	var rar := GameWeapon.rarity_of(data)
	var name_t := InventoryPanel.weapon_title(data)
	if kind == Kind.HAND:
		var ih := Hub2Style.px(84)
		Hub2ArsenalDraw.draw_render(_face, HubRenders.weapon(id), Rect2(x, y, w, ih), Hub2Style.px(6), Hub2Style.px(8), 0.6)
		y += ih + Hub2Style.px(GAP)
		# Nom (18 px) et NIV. (13 px) sur la même ligne de base.
		# Ligne (align-items: baseline) : hauteur = plus grande ascendante +
		# plus grande descendante des deux textes.
		var mc := Hub2ArsenalDraw.css_metrics(Hub2Style.CHAKRA, 700)
		var mm := Hub2ArsenalDraw.css_metrics(Hub2Style.MONO, 500)
		var asc := maxf(mc.x * Hub2Style.fs(18), mm.x * Hub2Style.fs(13))
		var lh := asc + maxf(mc.y * Hub2Style.fs(18), mm.y * Hub2Style.fs(13))
		var base := y + asc
		var lw := Hub2Style.text_width(lvl, Hub2Style.font(Hub2Style.MONO, 500), Hub2Style.fs(13))
		var nw := Hub2Style.text_width(name_t, Hub2Style.font(Hub2Style.CHAKRA, 700), Hub2Style.fs(18))
		# Case étroite (TAILLE DES MENUS 130 %) : NIV. descend sur la ligne de
		# la rareté plutôt que d'écraser le nom.
		var lvl_below := nw + Hub2Style.px(6) + lw > w
		_text_fit(name_t, Hub2Style.CHAKRA, 700, 18, Hub2Style.TEXT, 0.0, x, base, w if lvl_below else w - lw - Hub2Style.px(6))
		if not lvl_below:
			Hub2ArsenalDraw.text(_face, lvl, Hub2Style.MONO, 500, 13, lvl_col, 0.0, x, base, w, HORIZONTAL_ALIGNMENT_RIGHT)
		y += lh + Hub2Style.px(GAP)
		var rh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 12)
		var rb := Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 12, y, rh)
		Hub2ArsenalDraw.text(_face, GameWeapon.rarity_name(rar), Hub2Style.CHAKRA, 700, 12, Hub2Style.rarity_color(rar), 0.12, x, rb)
		if lvl_below:
			Hub2ArsenalDraw.text(_face, lvl, Hub2Style.MONO, 500, 13, lvl_col, 0.0, x, rb, w, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var ih2 := Hub2Style.px(58)
		Hub2ArsenalDraw.draw_render(_face, HubRenders.weapon(id), Rect2(x, y, w, ih2), Hub2Style.px(5), Hub2Style.px(7), 0.6)
		y += ih2 + Hub2Style.px(GAP)
		var nh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 16)
		_text_fit(name_t, Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.0, x,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 16, y, nh), w)
		y += nh + Hub2Style.px(GAP)
		# Rareté | NIV. (justify-content: space-between, en haut de la ligne).
		var rh2 := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 12)
		var mh := Hub2ArsenalDraw.line_h(Hub2Style.MONO, 500, 12)
		Hub2ArsenalDraw.text(_face, GameWeapon.rarity_name(rar), Hub2Style.CHAKRA, 700, 12, Hub2Style.rarity_color(rar), 0.12, x,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 12, y, rh2))
		Hub2ArsenalDraw.text(_face, lvl, Hub2Style.MONO, 500, 12, lvl_col, 0.0, x,
				Hub2ArsenalDraw.baseline(Hub2Style.MONO, 500, 12, y, mh), w, HORIZONTAL_ALIGNMENT_RIGHT)
		if is_new:
			# NEUF : top 8, right 8, padding 1px 6px, Chakra 10 px 700 0,12em.
			var t := Lang.t("NEUF", "NEW")
			var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
			var fsz := Hub2Style.fs(10)
			var tw := Hub2Style.text_width(t, f, fsz, Hub2Style.tracking_px(0.12, fsz))
			var th := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 10)
			var r := Rect2(s.x - Hub2Style.px(8) - tw - Hub2Style.px(12), Hub2Style.px(8), tw + Hub2Style.px(12), th + Hub2Style.px(2))
			_face.draw_rect(r, Hub2Style.YELLOW)
			Hub2ArsenalDraw.text(_face, t, Hub2Style.CHAKRA, 700, 10, Hub2Style.INK, 0.12, r.position.x + Hub2Style.px(6),
					Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 10, r.position.y + Hub2Style.px(1), th))


func _draw_part(s: Vector2) -> void:
	var line: Color = _bg.get_meta("line", Hub2Style.white_a(0.1))
	var x := Hub2Style.px(PART_PAD_H) + Hub2Style.px(1)
	if data.is_empty():
		Hub2ArsenalDraw.draw_dashed_rect(_face, Rect2(Vector2.ZERO, s), line, maxf(Hub2Style.px(1), 1.0))
		var lh0 := Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
		Hub2ArsenalDraw.text(_face, Lang.t("Aucune pièce pour l'instant", "No part yet"), Hub2Style.BARLOW, 400, 13,
				Hub2Style.text_a(0.4), 0.0, x, Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 13, (s.y - lh0) * 0.5, lh0))
		return
	var y := Hub2Style.px(PART_PAD_V) + Hub2Style.px(1)
	var nh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 15)
	Hub2ArsenalDraw.text(_face, String(data.get("name", "")), Hub2Style.CHAKRA, 700, 15, Hub2Style.TEXT, 0.0, x,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 15, y, nh))
	y += nh + Hub2Style.px(PART_GAP)
	var mh := Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
	InventoryDraw.draw_effects(_face, data.get("effects", []), 13, x, Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 13, y, mh))


## Texte d'une ligne réduit (jusqu'à 70 %) pour tenir dans `w` : un nom long
## (« FUSIL À POMPE » à 130 %) ne déborde jamais de la case.
func _text_fit(t: String, fam: String, wt: int, sz: float, col: Color, tr: float, x: float, base: float, w: float) -> void:
	var f := Hub2Style.font(fam, wt)
	var size := sz
	while size > sz * 0.7 and Hub2Style.text_width(t, f, Hub2Style.fs(size), Hub2Style.tracking_px(tr, Hub2Style.fs(size))) > w:
		size -= 0.5
	Hub2ArsenalDraw.text(_face, t, fam, wt, size, col, tr, x, base)
