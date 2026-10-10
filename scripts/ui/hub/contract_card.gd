class_name HubContractCard
extends MarginContainer
## Carte de contrat de l'onglet CONTRATS (classe .card de la maquette, écrans
## 5 et 11) :
##   - ACTIVE (300 × 300) : en-tête (titre, PRÊT / « ENCORE 12 J » / « 8 / 9 »),
##     demande du scientifique entre guillemets, progression par échantillon,
##     « Partagé avec : … » (contrat prêt), date de fin, récompense (XP au
##     niveau actuel, objet « niv. 7 »), REMETTRE (ou ce qui manque) et
##     ABANDONNER (deux appuis) ;
##   - OFFER (180 × 190) : titre, échantillons demandés (possédés en couleur),
##     XP et objet, pastille NOUVEAU, ACCEPTER ;
##   - FREE : case de contrat actif libre (« LIBRE ») ;
##   - EMPTY : case de proposition vide (.emptycard, pointillés).
## Le cadre jaune (.focus-ring) entoure la carte dont un bouton a le focus.
## Construite par HubContractsPanel (qui fait les actions).

const ACTIVE := "active"
const OFFER := "offer"
const FREE := "free"
const EMPTY := "empty"

const CARD_BG := Color("1F2022")
const HEAD_BG := Color("2A2C2E")
const FOOT_BG := Color("232427")
const INSET_BG := Color("17181A")
const DASH := Color("4A4844")
const EMPTY_BG := Color(20 / 255.0, 21 / 255.0, 22 / 255.0, 0.6)

var kind := ACTIVE
var contract_id := ""
## REMETTRE (actif) ou ACCEPTER (proposition).
var main_button: HubFitButton
var abandon_button: HubFitButton
var title_label: Label
var quote_label: Label
var tag: HubTag
var right_label: Label
var shared_label: Label
var col: VBoxContainer


func _init(k := ACTIVE) -> void:
	kind = k
	mouse_filter = Control.MOUSE_FILTER_PASS
	var b := int(HubStyle.px(2))
	for side in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, b)
	col = HubBox.vbox(0)
	add_child(col)


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(func(_c): queue_redraw())


## Un bouton de la carte a-t-il le focus ?
func is_focused() -> bool:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return f != null and is_ancestor_of(f)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		EMPTY, FREE:
			draw_rect(r, EMPTY_BG)
			_dashed(r, DASH, HubStyle.px(2))
		_:
			if is_focused():
				# .focus-ring : anneau jaune de 3 px, ombre élargie d'autant.
				var t := HubStyle.px(3)
				var o := HubStyle.px(4)
				draw_rect(Rect2(r.position + Vector2(o, o), r.size).grow(t), HubStyle.BLACK)
				draw_rect(r.grow(t), HubStyle.YELLOW)
				HubStyle.draw_box(self, r, CARD_BG, HubStyle.px(2), 0.0, HubStyle.PANEL_HI, Color(0, 0, 0, 0), HubStyle.px(2))
			else:
				HubStyle.draw_box(self, r, CARD_BG, HubStyle.px(2), HubStyle.px(4), HubStyle.PANEL_HI, Color(0, 0, 0, 0), HubStyle.px(2))


## Bord en pointillés (border: 2px dashed).
func _dashed(r: Rect2, c: Color, w: float) -> void:
	var dash := HubStyle.px(6)
	var gap := HubStyle.px(4)
	var x := r.position.x
	while x < r.end.x:
		var l := minf(dash, r.end.x - x)
		draw_rect(Rect2(x, r.position.y, l, w), c)
		draw_rect(Rect2(x, r.end.y - w, l, w), c)
		x += dash + gap
	var y := r.position.y
	while y < r.end.y:
		var l := minf(dash, r.end.y - y)
		draw_rect(Rect2(r.position.x, y, w, l), c)
		draw_rect(Rect2(r.end.x - w, y, w, l), c)
		y += dash + gap


func _gui_input(event: InputEvent) -> void:
	# Clic sur la carte : le focus va à son bouton principal.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and main_button and main_button.focus_mode != Control.FOCUS_NONE:
		main_button.grab_focus()


# --------------------------------------------------------------------------
# Parties de la carte
# --------------------------------------------------------------------------

## En-tête (.ch) : fond gris, liseré noir en bas ; titre en Impact.
func add_header(title: String, size_px: int, pad_v: Array, pad_h: float) -> HBoxContainer:
	var h := HubBox.hbox(8)
	var m := HubBox.pad(h, pad_h, pad_v[0], pad_h, pad_v[1] + 2.0)
	m.draw.connect(func():
		m.draw_rect(Rect2(Vector2.ZERO, m.size), HEAD_BG)
		m.draw_rect(Rect2(0, m.size.y - HubStyle.px(2), m.size.x, HubStyle.px(2)), HubStyle.BLACK))
	title_label = HubStyle.label(title.to_upper(), size_px, HubStyle.PAPER, "impact", false, 0.03)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title_label)
	col.add_child(m)
	return h


## Corps (.cb) : colonne qui prend la hauteur restante.
func add_body(pad_v: float, pad_h: float, sep: float) -> VBoxContainer:
	var v := HubBox.vbox(sep)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m := HubBox.pad(v, pad_h, pad_v, pad_h, pad_v)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(m)
	return v


## Pied (.cf) : fond, liseré noir en haut, boutons.
func add_footer(pad_v: float, pad_h: float) -> HBoxContainer:
	var h := HubBox.hbox(8)
	var m := HubBox.pad(h, pad_h, pad_v + 2.0, pad_h, pad_v)
	m.draw.connect(func():
		m.draw_rect(Rect2(Vector2.ZERO, m.size), FOOT_BG)
		m.draw_rect(Rect2(0, 0, m.size.x, HubStyle.px(2)), HubStyle.BLACK))
	col.add_child(m)
	return h


## Demande du scientifique en italique, entre guillemets, `lines` lignes au
## plus (la suite en « … » ; le texte entier est dans l'aide du bouton).
static func quote(text: String, lines: int) -> Label:
	var q := HubStyle.label(Lang.t("« %s »", "\"%s\"") % text, 13, HubStyle.PLASTER)
	q.add_theme_font_override("font", italic_font())
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.max_lines_visible = lines
	q.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return q


static var _italic: Font


## Police des menus penchée (font-style: italic de la maquette ; Bahnschrift
## n'a pas d'italique : oblique synthétique, comme le navigateur).
static func italic_font() -> Font:
	if _italic == null:
		var fv := FontVariation.new()
		fv.base_font = HubStyle.font("ui")
		# Inclinaison synthétique (doc. de TextServer.font_set_transform :
		# Transform2D(1, pente, 0, 1, 0, 0)).
		fv.variation_transform = Transform2D(Vector2(1, 0.2), Vector2(0, 1), Vector2.ZERO)
		_italic = fv
	return _italic


## Encadré de récompense (.reward) : « +1 340 XP », icône, objet.
static func reward_box(xp: int, reward: Dictionary, lvl: int) -> MarginContainer:
	var h := HubBox.hbox(8)
	var m := HubBox.pad(h, 8, 5, 8, 5)
	m.draw.connect(func():
		HubStyle.draw_box(m, Rect2(Vector2.ZERO, m.size), INSET_BG, HubStyle.px(2), 0.0))
	var b := HubStyle.px(2)
	m.add_theme_constant_override("margin_left", int(HubStyle.px(8) + b))
	m.add_theme_constant_override("margin_right", int(HubStyle.px(8) + b))
	m.add_theme_constant_override("margin_top", int(HubStyle.px(5) + b))
	m.add_theme_constant_override("margin_bottom", int(HubStyle.px(5) + b))
	var x := HubStyle.label("+%s XP" % HubStyle.num(xp), 16, HubStyle.XP_BLUE, "impact", false, 0.03)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(x)
	var art := reward_art(reward)
	if art != "":
		var ic := HubIcon.make(art, 2 if art == "part" else 1)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	# Texte replié s'il ne tient pas (taille des menus 130 %).
	var t := HubSamplesColumn.rich(reward_text(reward, lvl), 13, HubStyle.PAPER, true)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	return m


## Icône d'une récompense (pièce, arme selon sa famille).
static func reward_art(reward: Dictionary) -> String:
	match reward.get("kind"):
		"part":
			return "part"
		"weapon":
			return weapon_art(String(reward.get("weapon", "any")))
	return ""


## Icône en pixel art d'une arme (famille de WeaponDB ; « any » : smg).
static func weapon_art(id: String) -> String:
	if id == "any" or not WeaponDB.exists(id):
		return "smg"
	var cls := String(WeaponDB.WEAPONS[id].get("class", ""))
	return cls if HubIcon.ART.has(cls) else "rifle"


## Nom d'une qualité de pièce en minuscules (FR) ou capitalisé (EN), et sa
## couleur : ordinaire (texte), soignée (texte, gras), d'exception (jaune).
static func quality_word(q: String) -> Array:
	var n := HubData.quality_name(q)
	var w := n.to_lower() if not Lang.is_en() else n.left(1) + n.substr(1).to_lower()
	return [w, HubStyle.YELLOW if q == "superior" else HubStyle.PAPER]


## Mot de rareté en couleur (BBCode) : « [b]rare[/b] » / « [b]Rare[/b] ».
static func rarity_bb(r: int) -> String:
	var n := GameWeapon.rarity_name(r).to_lower()
	if Lang.is_en():
		n = n.left(1).to_upper() + n.substr(1)
	return "[b][color=#%s]%s[/color][/b]" % [HubStyle.rarity_color(r).to_html(false), n]


## Objet d'une récompense en clair (BBCode) : « Pièce [b]soignée[/b], niv.
## 7 » / « [b]Fine[/b] part, lvl 7 », « Arme [b]rare[/b], niv. 7 » ;
## `lvl` < 0 : sans le niveau (propositions).
static func reward_text(reward: Dictionary, lvl := -1) -> String:
	var at := ""
	if lvl > 0:
		at = Lang.t(", niv. %d", ", lvl %d") % lvl
	match reward.get("kind"):
		"part":
			if reward.has("mods"):
				return Lang.t("Pièce", "Part") + at + " : " + mods_bb(reward.mods)
			var q := quality_word(String(reward.get("quality", "standard")))
			var qb := "[b][color=#%s]%s[/color][/b]" % [(q[1] as Color).to_html(false), q[0]]
			return Lang.t("Pièce %s%s" % [qb, at], "%s part%s" % [qb, at])
		"weapon":
			var r := maxi(OwnedWeapon.rarity_from_key(reward.get("rarity", "common")), 0)
			var id := String(reward.get("weapon", "any"))
			var named := id != "any" and WeaponDB.exists(id)
			if named and lvl > 0:
				at = Lang.t(", niv. %d", ", lvl %d") % maxi(lvl, WeaponDB.base_level(id))
			var what := (" " + WeaponDB.display_name(id)) if named else ""
			return Lang.t("Arme %s%s%s" % [rarity_bb(r), what, at], "%s%s weapon%s" % [rarity_bb(r), what, at])
	return Lang.t("XP seulement", "XP only")


## Modificateurs d'une pièce en couleur (BBCode) : « dégâts +15 %, cadence
## +10 % » (bonus en vert, malus en rouge ; nom d'abord, comme la maquette).
static func mods_bb(mods: Dictionary, sep := ", ") -> String:
	var items := PackedStringArray()
	for k in mods:
		var v := float(mods[k])
		var n: Array = LootRules.MOD_NAMES.get(String(k), [String(k), String(k)])
		var t := Lang.t("%s %s%d %%", "%s %s%d%%") % [Lang.t(n[0], n[1]), "+" if v >= 0.0 else "−", roundi(absf(v) * 100.0)]
		items.append("[color=#%s]%s[/color]" % [(HubStyle.OK if v >= 0.0 else HubStyle.BAD).to_html(false), t])
	return sep.join(items)


## Pastille d'échantillons demandés (.need) : icône, quantité possédée (vert
## si assez, rouge sinon ; sans couleur si `plain`), « /demandés ».
static func need_chip(kind: String, have: int, need: int, plain := false) -> MarginContainer:
	var h := HubBox.hbox(5)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := HubStyle.px(2)
	m.add_theme_constant_override("margin_left", int(HubStyle.px(3) + b))
	m.add_theme_constant_override("margin_right", int(HubStyle.px(7) + b))
	m.add_theme_constant_override("margin_top", int(HubStyle.px(2) + b))
	m.add_theme_constant_override("margin_bottom", int(HubStyle.px(2) + b))
	m.add_child(h)
	m.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.draw.connect(func():
		HubStyle.draw_box(m, Rect2(Vector2.ZERO, m.size), INSET_BG, HubStyle.px(2), 0.0))
	h.add_child(HubIcon.make(HubIcon.sample_art(kind), 2))
	var hc := HubStyle.PAPER if plain else (HubStyle.OK if have >= need else HubStyle.BAD)
	var hl := HubStyle.label(str(have), 13, hc, "bold")
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	var nl := HubStyle.label("/%d" % need, 13, HubStyle.PAPER, "bold")
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nl)
	return m
