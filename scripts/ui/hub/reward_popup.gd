class_name HubRewardPopup
extends Control
## Fenêtre « CONTRAT REMIS » (maquette, écran 6) ouverte après REMETTRE, et
## « ÉCHANGE CONCLU » après un échange (même fenêtre, sans XP) : voile sombre
## sur le hub (la barre d'invites reste visible), panneau de 700 × 470 :
##   - en-tête : « CONTRAT REMIS », titre du contrat (grand titre rouge) ;
##   - portrait du scientifique et sa réplique de remerciement (champ
##     `thanks` du contrat, sinon une réplique générique) ;
##   - XP GAGNÉE : « +1 340 », niveau avant → après (« NIVEAU 8 ! NIVEAU
##     SUPÉRIEUR »), barre d'XP du niveau atteint ;
##   - objet reçu : sorte, qualité ou rareté, niveau, nom, modificateurs,
##     pastille NOUVEAU ;
##   - échantillons consommés et ce qui reste ;
##   - VOIR DANS LES PIÈCES (ou L'ARSENAL) et FERMER.
## Posée sur l'hôte du panneau (HubScreen) pour couvrir la barre du haut et
## les onglets ; garde le focus (Échap / B / clic sur le voile : fermer).
## Le profil est déjà enregistré par l'appelant (une écriture par action).

## Noms des pièces d'après leur premier modificateur (maquette : Renfort,
## Mire, Amortisseur, Guide) : [FR, EN].
const PART_NAMES := {
	"damage": ["RENFORT", "REINFORCEMENT"], "accuracy": ["MIRE", "SIGHT"],
	"recoil": ["AMORTISSEUR", "DAMPER"], "reload": ["GUIDE", "GUIDE"],
	"fire_rate": ["CULASSE ALLÉGÉE", "LIGHT BOLT"], "mag": ["CHARGEUR LONG", "LONG MAG"],
	"reserve": ["CARTOUCHIÈRE", "BANDOLIER"],
}
## Remerciements génériques (contrat sans `thanks`, échange).
const THANKS := ["Excellent travail. La science vous remercie, moi aussi, un peu.",
	"Excellent work. Science thanks you, and so do I, a little."]
const DEAL := ["Marché conclu. Ne me demandez pas d'où vient l'odeur.",
	"Deal. Don't ask me where the smell comes from."]

const SIZE := Vector2(700, 470)

var hub: Node
var panel: Control
var primary_button: HubButton
var close_button: HubButton
## Texte de l'invite « Entrée » (VOIR DANS LES PIÈCES…).
var primary_text := ""
## Onglet ouvert par le bouton principal (« parts », « arsenal », "").
var target_tab := ""
## Textes affichés (tests).
var title_text := ""
var thanks_text := ""
var level_text := ""
var item_name := ""

signal closed


func _init(owner_hub: Node) -> void:
	hub = owner_hub
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# La barre d'invites (36 px en bas) reste visible et cliquable.
	offset_bottom = -HubStyle.px(HubPrompts.HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Contrat remis : `res` = rapport de ContractRules.deliver ; `c` = fiche du
## contrat ; `remaining` = échantillons restants {sorte: n}.
func show_delivery(c: Dictionary, res: Dictionary, pr: PlayerProfile, remaining: Dictionary) -> void:
	var th := HubData.text_of(c.get("thanks", {}))
	_build(Lang.t("CONTRAT REMIS", "CONTRACT DELIVERED"), HubData.text_of(c.title),
			th if th != "" else Lang.t(THANKS[0], THANKS[1]), res, pr, c.samples, remaining, true)


## Échange conclu : `res` = rapport d'ExchangeRules.trade ; `x` = l'échange.
func show_exchange(x: Dictionary, res: Dictionary, pr: PlayerProfile, remaining: Dictionary) -> void:
	_build(Lang.t("ÉCHANGE CONCLU", "EXCHANGE DONE"), HubData.text_of(x.title), Lang.t(DEAL[0], DEAL[1]),
			res, pr, x.samples, remaining, false, HubData.text_of(x.title))


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
	queue_free()


func _build(head: String, title: String, line: String, res: Dictionary, pr: PlayerProfile, cost: Dictionary,
		remaining: Dictionary, with_xp: bool, exact_name := "") -> void:
	title_text = title
	thanks_text = line
	panel = HubBox.new("", "", false, false)
	panel.size = HubStyle.pxv(SIZE.x, SIZE.y)
	panel.custom_minimum_size = panel.size
	add_child(panel)
	resized.connect(_place)
	# Le panneau n'est pas dans un conteneur : sa taille est remise à celle de
	# la maquette quand son contenu se met en page (texte replié de la bulle).
	panel.minimum_size_changed.connect(_place)
	var v: VBoxContainer = panel.content
	# En-tête : « CONTRAT REMIS », grand titre rouge (dégradé jaune léger).
	var hv := HubBox.vbox(0)
	# Maquette : en-tête de 78 px (14 + 16 + 4 + 38 + 8 ; lignes de 1,25).
	hv.add_theme_constant_override("separation", int(HubStyle.px(4)))
	var hm := HubBox.pad(hv, 18, 14, 18, 8)
	hm.custom_minimum_size.y = HubStyle.px(78)
	hm.draw.connect(func():
		var r := Rect2(Vector2.ZERO, hm.size)
		var top := Color(HubStyle.YELLOW, 0.18)
		var bottom := Color(HubStyle.YELLOW, 0.0)
		hm.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(r.size.x, 0), r.size, Vector2(0, r.size.y)]),
				PackedColorArray([top, top, bottom, bottom]))
		hm.draw_rect(Rect2(0, r.size.y - HubStyle.px(2), r.size.x, HubStyle.px(2)), HubStyle.BLACK))
	v.add_child(hm)
	var small := HubStyle.label(head, 13, HubStyle.DIM, "ui", false, 0.1)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(small)
	var big := HubStyle.label(title.to_upper(), 30, HubStyle.RED_HI, "stencil", false, 0.05)
	big.add_theme_color_override("font_shadow_color", HubStyle.BLACK)
	big.add_theme_constant_override("shadow_offset_x", int(HubStyle.px(3)))
	big.add_theme_constant_override("shadow_offset_y", int(HubStyle.px(3)))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.clip_text = true
	hv.add_child(big)
	# Portrait et réplique.
	var sp := HubBox.hbox(18)
	v.add_child(HubBox.pad(sp, 18, 16, 18, 16))
	sp.add_child(HubIcon.make("doc", 5))
	var bubble := HubLabPanel.HubSpeech.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bubble.set_line(HubSamplesColumn.esc(line))
	sp.add_child(bubble)
	# XP gagnée et objet reçu.
	var grid := HubBox.hbox(16)
	v.add_child(HubBox.pad(grid, 18, 0, 18, 0))
	if with_xp:
		grid.add_child(_xp_box(res, pr))
	grid.add_child(_item_box(res.get("item"), pr, exact_name))
	# Consommé.
	var cons := HubBox.hbox(10)
	v.add_child(HubBox.pad(cons, 18, 12, 18, 12))
	cons.add_child(HubStyle.label(Lang.t("Consommé :", "Used:"), 14, HubStyle.DIM))
	for k in cost:
		var chip := HubContractCard.need_chip(String(k), int(cost[k]), int(cost[k]), true)
		cons.add_child(chip)
		var nl := chip.get_child(0).get_child(2) as Label
		chip.get_child(0).remove_child(nl)
		nl.queue_free()
	var left := PackedStringArray()
	for k in remaining:
		left.append(HubSamplesColumn.words(String(k), int(remaining[k])))
	cons.add_child(HubStyle.label("· " + Lang.t("il reste %s", "%s left") % ", ".join(left), 14, HubStyle.DIM))
	v.add_child(HubBox.spring())
	# Boutons.
	var btns := HubBox.hbox(10)
	v.add_child(HubBox.pad(btns, 18, 0, 18, 16))
	var item: Variant = res.get("item")
	if item is WeaponPart:
		target_tab = "parts"
		primary_text = Lang.t("Voir dans les pièces", "See in parts")
	elif item is OwnedWeapon:
		target_tab = "arsenal"
		primary_text = Lang.t("Voir dans l'arsenal", "See in the arsenal")
	if target_tab != "":
		primary_button = HubButton.make(primary_text.to_upper(), _go, HubButton.PRIMARY,
				Lang.t("L'objet est rangé avec la pastille NOUVEAU.", "The item is stored with a NEW badge."))
		primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(primary_button)
	close_button = HubButton.make(Lang.t("FERMER", "CLOSE"), close, HubButton.NORMAL,
			Lang.t("Revenir aux contrats.", "Back to the contracts.") if with_xp else Lang.t("Revenir au catalogue.", "Back to the catalogue."))
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(close_button)
	for b in [primary_button, close_button]:
		if b == null:
			continue
		b.focus_entered.connect(func():
			if hub:
				hub.set_hint(b.hint))
	# Le focus reste dans la fenêtre.
	var list := [primary_button, close_button].filter(func(b): return b != null)
	for i in list.size():
		var b: HubButton = list[i]
		var prev: HubButton = list[(i - 1 + list.size()) % list.size()]
		var next: HubButton = list[(i + 1) % list.size()]
		b.focus_neighbor_left = b.get_path_to(prev)
		b.focus_neighbor_right = b.get_path_to(next)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_previous = b.focus_neighbor_left
		b.focus_next = b.focus_neighbor_right
	visible = true
	_place()
	(list[0] as HubButton).grab_focus.call_deferred()
	Audio.play_ui("menu_whoosh", -12.0)


## Panneau centré (maquette : 290, 140 dans 1280 × 720).
func _place() -> void:
	if panel == null:
		return
	var s := HubStyle.pxv(SIZE.x, SIZE.y)
	panel.size = s
	var top := HubStyle.px(140) if size.y >= HubStyle.px(140) + s.y else maxf((size.y - s.y) * 0.5, 0.0)
	panel.position = Vector2(roundf((size.x - s.x) * 0.5), roundf(top))


func _xp_box(res: Dictionary, pr: PlayerProfile) -> Control:
	var v := HubBox.vbox(0)
	var m := _inset(v)
	m.add_child(v)
	v.add_child(HubStyle.label(Lang.t("XP GAGNÉE", "XP EARNED"), 13, HubStyle.DIM))
	v.add_child(HubStyle.label("+" + HubStyle.num(int(res.get("xp", 0))), 30, HubStyle.XP_BLUE, "impact", true))
	var before := int(res.get("level_before", pr.level()))
	var after := int(res.get("level_after", pr.level()))
	if after > before:
		level_text = Lang.t("NIVEAU %d → [y]NIVEAU %d ! NIVEAU SUPÉRIEUR[/y]", "LEVEL %d → [y]LEVEL %d! LEVEL UP[/y]") % [before, after]
	elif pr.is_max_level():
		level_text = Lang.t("NIVEAU %d (MAXIMUM)", "LEVEL %d (MAX)") % after
	else:
		level_text = Lang.t("NIVEAU %d · encore %s XP pour le niveau %d", "LEVEL %d · %s XP to level %d") % [
			after, HubStyle.num(pr.xp_to_next_level()), after + 1]
	var lt := HubSamplesColumn.rich(level_text.replace("[y]", "[b][color=#%s]" % HubStyle.YELLOW.to_html(false)).replace("[/y]", "[/color][/b]"), 13)
	v.add_child(HubBox.pad(lt, 0, 4, 0, 6))
	var need := PlayerProfile.xp_to_next(pr.level())
	var bar := HubBar.make(1.0 if pr.is_max_level() else float(pr.xp_in_level()) / maxf(need, 1.0))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(bar)
	var n := HubStyle.label("%s / %s XP" % [HubStyle.num(pr.xp_in_level()), HubStyle.num(need)] if not pr.is_max_level()
			else HubStyle.num(pr.xp) + " XP", 13, HubStyle.DIM)
	v.add_child(HubBox.pad(n, 0, 4, 0, 0))
	return m


func _item_box(item: Variant, pr: PlayerProfile, exact_name: String) -> Control:
	var h := HubBox.hbox(12)
	var m := _inset(h)
	m.add_child(h)
	var v := HubBox.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if item is WeaponPart:
		var p := item as WeaponPart
		var ic := HubIcon.make("part", 6)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var q := _part_quality(p, exact_name)
		v.add_child(HubStyle.label(q + Lang.t(" · NIVEAU %d", " · LEVEL %d") % p.level, 13, HubStyle.DIM))
		item_name = exact_name.to_upper() if exact_name != "" else part_name(p)
		v.add_child(HubStyle.label(item_name, 22, HubStyle.PAPER, "impact", true))
		v.add_child(HubSamplesColumn.rich(HubContractCard.mods_bb(p.mods, " · "), 13))
		if pr.is_new_part(p.uid):
			var t := HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW)
			t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			v.add_child(HubBox.pad(t, 0, 4, 0, 0))
	elif item is OwnedWeapon:
		var w := item as OwnedWeapon
		var ic := HubIcon.make(HubContractCard.weapon_art(w.weapon_id), 3)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		v.add_child(HubStyle.label((Lang.t("ARME %s", "%s WEAPON") % GameWeapon.rarity_name(w.rarity).to_upper())
				+ Lang.t(" · NIVEAU %d", " · LEVEL %d") % w.level, 13, HubStyle.DIM))
		item_name = WeaponDB.display_name(w.weapon_id).to_upper()
		v.add_child(HubStyle.label(item_name, 22, HubStyle.rarity_color(w.rarity), "impact", true))
		v.add_child(HubStyle.label(Lang.t("score %d · rangée dans l'arsenal", "score %d · stored in the arsenal") % w.score(), 13, HubStyle.PLASTER))
		if pr.is_new_weapon(w.uid):
			var t := HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW)
			t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			v.add_child(HubBox.pad(t, 0, 4, 0, 0))
	else:
		v.add_child(HubStyle.label(Lang.t("Aucun objet : de l'XP seulement.", "No item: XP only."), 15, HubStyle.PLASTER))
	h.add_child(v)
	return m


## « PIÈCE SOIGNÉE » d'après les modificateurs (bonus de 10 à 25 % :
## soignée ; 18 à 25 % : d'exception) ; pièce d'échange : « PIÈCE ».
static func _part_quality(p: WeaponPart, exact_name: String) -> String:
	if exact_name != "":
		return Lang.t("PIÈCE", "PART")
	var lo := 1.0
	var malus := false
	for k in p.mods:
		lo = minf(lo, float(p.mods[k]))
		malus = malus or float(p.mods[k]) < 0.0
	var q := "standard"
	if not malus and p.mods.size() >= 2:
		q = "superior" if lo >= 0.18 else "fine"
	return Lang.t("PIÈCE %s" % HubData.quality_name(q), "%s PART" % HubData.quality_name(q))


## Nom d'une pièce d'après son premier modificateur (« RENFORT »).
static func part_name(p: WeaponPart) -> String:
	for k in p.mods:
		var n: Array = PART_NAMES.get(String(k), [])
		if not n.is_empty():
			return Lang.t(n[0], n[1])
	return Lang.t("PIÈCE", "PART")


## Encadré sombre (fond #17181a, contour noir, marges 10 / 12).
func _inset(_c: Control) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := HubStyle.px(2)
	m.add_theme_constant_override("margin_left", int(HubStyle.px(12) + b))
	m.add_theme_constant_override("margin_right", int(HubStyle.px(12) + b))
	m.add_theme_constant_override("margin_top", int(HubStyle.px(10) + b))
	m.add_theme_constant_override("margin_bottom", int(HubStyle.px(10) + b))
	m.draw.connect(func():
		HubStyle.draw_box(m, Rect2(Vector2.ZERO, m.size), HubContractCard.INSET_BG, HubStyle.px(2), 0.0))
	return m


func _go() -> void:
	# Onglet d'abord : le panneau qui a ouvert la fenêtre est alors caché et
	# ne reprend pas le focus à la fermeture.
	if target_tab != "" and hub and hub.has_method("select_tab"):
		hub.select_tab(target_tab)
	close()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))


func _gui_input(event: InputEvent) -> void:
	# Clic sur le voile, hors du panneau : fermer.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and panel \
			and not panel.get_global_rect().has_point(mb.global_position):
		accept_event()
		close()


func _unhandled_input(event: InputEvent) -> void:
	# Rien derrière la fenêtre : onglets (Q / E, LB / RB) bloqués, Start ferme.
	if not visible:
		return
	if event.is_action_pressed("ui_page_up") or event.is_action_pressed("ui_page_down") \
			or (event is InputEventJoypadButton and event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("pause"):
			close()
		return
	var k := event as InputEventKey
	if k and k.pressed and (k.physical_keycode == KEY_Q or k.physical_keycode == KEY_E):
		get_viewport().set_input_as_handled()
