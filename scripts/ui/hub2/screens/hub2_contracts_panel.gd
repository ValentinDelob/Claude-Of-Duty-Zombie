class_name Hub2ContractsPanel
extends Hub2Panel
## LABO › CONTRATS (docs/hub_v2/Contrats.dc.html) :
##   - à gauche, l'HISTOIRE (520 px, verre turquoise rgba(6, 22, 19, 0.72),
##     liseré turquoise 45 %) : « HISTOIRE · CHAPITRE 2 », titre du
##     chapitre, frise des étapes (remise : turquoise, en cours : jaune si
##     prête, verrouillée : « ??? »), étape en cours (« ÉTAPE 3 SUR 5 »,
##     TERMINÉ / EN COURS / NIV. n REQUIS), titre, demande de Dr Brown,
##     échantillons demandés (n / n et barre), récompense en tuiles (aperçu
##     EXACT de l'objet et XP, infobulle au survol ou au focus), étape ou
##     chapitre débloqué, REMETTRE (anneaux jaunes pulsés quand elle est
##     prête) ;
##   - à droite, les CONTRATS TEMPORAIRES : « 2 / 3 en cours », contrats
##     acceptés (titre, temps restant en orange, échantillons possédés /
##     demandés, tuiles), puis PROPOSITIONS (titre, demande et récompense en
##     mots, temps restant, ACCEPTER).
## Actions (règles StoryRules et ContractRules, une écriture du profil par
## action, fenêtre Hub2RewardPopup) : REMETTRE l'étape ; A sur un contrat
## temporaire prêt : le remettre ; X (Suppr, R, clic sur l'invite) :
## ABANDONNER le contrat temporaire choisi en deux appuis (rien n'est
## consommé) ; ACCEPTER une proposition (grisé quand 3 contrats sont en
## cours). Clavier, manette, souris ; FR / EN.

const STORY_W := 520.0
const STORY_BG := Color(6 / 255.0, 22 / 255.0, 19 / 255.0, 0.72)
## Orange du temps restant (#FF9A1F).
const ORANGE := Color("FF9A1F")

var data: HubData
var story: StoryData
var day := 0
var tooltip: Hub2RewardTooltip
var root: HBoxContainer
var story_box: Hub2Box
var temps_scroll: ScrollContainer
## Étape en cours ({} : histoire terminée) et son bouton REMETTRE.
var step: Dictionary = {}
var hand_in_button: Hub2Button
var hand_in_rings: Hub2PulseRings
var story_tiles: Array = []
## Contrats temporaires en cours : identifiant -> Hub2Button (l'article).
var temp_cards: Dictionary = {}
## Propositions : identifiant -> Hub2Button (ACCEPTER).
var offer_buttons: Dictionary = {}
## Contrat dont l'abandon attend le deuxième appui ("" : aucun).
var confirm_id := ""
var popup: Hub2RewardPopup
## Textes affichés (tests).
var chapter_text := ""
var step_label_text := ""
var unlock_text := ""
var count_text := ""


## Frise des étapes d'un chapitre (grid repeat(n, minmax(0, 1fr)), écart
## 6) : barre de 4 px, libellé Chakra Petch 11 px 600 0.06em.
class Track extends Control:
	## [[libellé, couleur de la barre, couleur du libellé]].
	var items: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _font() -> Font:
		return Hub2Style.font(Hub2Style.CHAKRA, 600)

	func _get_minimum_size() -> Vector2:
		return Vector2(0, Hub2Style.px(4) + Hub2Style.px(6) + Hub2Style.line_height(_font(), Hub2Style.fs(11)))

	func _draw() -> void:
		var n := items.size()
		if n == 0:
			return
		var gap := Hub2Style.px(6)
		var w := (size.x - gap * (n - 1)) / n
		var f := _font()
		var fs := Hub2Style.fs(11)
		var lh := Hub2Style.line_height(f, fs)
		for i in n:
			var x := roundf(i * (w + gap))
			var it: Array = items[i]
			draw_rect(Rect2(x, 0, roundf(w), Hub2Style.px(4)), it[1])
			var t := String(it[0])
			# Libellé coupé à la colonne (min-width: 0).
			var tr := Hub2Style.tracking_px(0.06, fs)
			while t.length() > 1 and Hub2Style.text_width(t, f, fs, tr) > w:
				t = t.left(t.length() - 2) + "…"
			Hub2Style.draw_text(self, f, Vector2(x, Hub2Style.baseline(f, fs, Hub2Style.px(10), lh)), t, fs, it[2], tr)


## Barre de progression d'un échantillon (3 px, fond blanc 10 %).
class Bar extends Control:
	var ratio := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = Hub2Style.px(3)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Hub2Style.white_a(0.1))
		draw_rect(Rect2(0, 0, roundf(size.x * clampf(ratio, 0.0, 1.0)), size.y), Hub2Style.TEAL)


func veil() -> Dictionary:
	return {"color": Hub2Style.shade(0.45)}


func help() -> String:
	return Lang.t("L’histoire avance d’un contrat à la fois ; les contrats temporaires donnent un bonus en attendant.",
			"The story moves on one contract at a time; timed contracts give a bonus in the meantime.")


func build() -> void:
	tooltip = Hub2RewardTooltip.new()
	_fill()
	add_child(tooltip)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func refresh() -> void:
	if not built:
		return
	var key := _focus_key()
	_cancel_confirm(false)
	if root:
		remove_child(root)
		root.queue_free()
	_fill()
	move_child(tooltip, -1)
	tooltip.show_for(null)
	if is_visible_in_tree():
		var f := _from_key(key)
		hub.focus_later(f if f else first_focus())


func _fill() -> void:
	data = HubContractsView.data()
	story = StoryRules.data()
	day = HubContractsView.today()
	temp_cards.clear()
	offer_buttons.clear()
	story_tiles.clear()
	hand_in_button = null
	hand_in_rings = null
	root = HBoxContainer.new()
	root.add_theme_constant_override("separation", int(Hub2Style.px(20)))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_main(root)
	_story(profile())
	_temps(profile())


# --------------------------------------------------------------------------
# HISTOIRE
# --------------------------------------------------------------------------

func _story(pr: PlayerProfile) -> void:
	story_box = Hub2Box.new()
	story_box.glass(STORY_BG, Hub2Style.teal_a(0.45), 1.0)
	# 520 px ; à une grande taille des menus, 47 % de <main> au plus (les
	# contrats temporaires gardent de la place).
	var mw := content_rect().size.x
	if mw <= 0.0:
		mw = get_viewport_rect().size.x - 2.0 * Hub2Style.px(Hub2Style.SIDE)
	story_box.custom_minimum_size.x = minf(Hub2Style.px(STORY_W), floorf(mw * 0.47))
	story_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(story_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_box.add_child(v)
	step = StoryRules.current(pr, story)
	var shown := step if not step.is_empty() else (story.steps[story.steps.size() - 1] if not story.steps.is_empty() else {})
	var loc := story.locate(String(shown.get("id", "")))
	# En-tête : chapitre et frise (padding 16 22 14, filet du bas 20 %).
	var head := Hub2Box.new()
	head.flat(Color(0, 0, 0, 0), Hub2Style.teal_a(0.2), 1.0)
	head.border = Vector4(0, 0, 0, 1)
	head.pad(16, 22, 14, 22)
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hv)
	var kicker := Hub2Text.new()
	chapter_text = Lang.t("HISTOIRE · CHAPITRE %d", "STORY · CHAPTER %d") % (int(loc.get("chapter_index", 0)) + 1) \
			if not loc.is_empty() else Lang.t("HISTOIRE", "STORY")
	kicker.setup(chapter_text, Hub2Style.CHAKRA, 700, 12, Hub2Style.TEAL, 0.24)
	hv.add_child(kicker)
	hv.add_child(_gap(4))
	var ct := Hub2Style.label(HubData.text_of(loc.chapter.title) if not loc.is_empty() else "", Hub2Style.CHAKRA, 700, 26, Hub2Style.TEXT)
	ct.clip_text = true
	ct.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hv.add_child(ct)
	hv.add_child(_gap(12))
	var track := Track.new()
	if not loc.is_empty():
		for s in loc.chapter.steps:
			var st := StoryRules.step_state(pr, s, story)
			var ready := st == StoryRules.CURRENT and StoryRules.is_ready(pr, story)
			match st:
				StoryRules.DONE:
					track.items.append([HubData.text_of(s.short), Hub2Style.TEAL, Hub2Style.teal_a(0.85)])
				StoryRules.CURRENT:
					track.items.append([HubData.text_of(s.short), Hub2Style.YELLOW if ready else Hub2Style.text_a(0.6),
						Hub2Style.YELLOW if ready else Hub2Style.TEXT])
				_:
					track.items.append(["???", Hub2Style.white_a(0.14), Hub2Style.text_a(0.35)])
	hv.add_child(track)
	# Corps : étape en cours.
	var body := Hub2Box.new()
	body.flat(Color(0, 0, 0, 0))
	body.pad(18, 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(bv)
	var scroll := _scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bv.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(sv)
	if step.is_empty():
		step_label_text = Lang.t("HISTOIRE TERMINÉE", "STORY COMPLETE")
		var done_t := Hub2Text.new()
		done_t.setup(step_label_text, Hub2Style.CHAKRA, 600, 13, Hub2Style.text_a(0.7), 0.16)
		sv.add_child(done_t)
		sv.add_child(_title(Lang.t("La suite au prochain chapitre", "To be continued")))
		sv.add_child(_paragraph(Hub2LabKit.quoted(Lang.t("L’antidote marche sur les rats. Pour la suite, je réfléchis. Revenez me voir.",
				"The antidote works on rats. I'm thinking about what comes next. Come back and see me."))))
		return
	var refusal := StoryRules.refusal(pr, story)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(row)
	var sl := Hub2Text.new()
	step_label_text = Lang.t("ÉTAPE %d SUR %d", "STEP %d OF %d") % [int(loc.step_index) + 1, int(loc.count)]
	sl.setup(step_label_text, Hub2Style.CHAKRA, 600, 13, Hub2Style.text_a(0.7), 0.16)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	match refusal:
		"":
			row.add_child(_tag(Lang.t("TERMINÉ", "DONE"), Hub2Style.INK, Hub2Style.YELLOW))
		StoryRules.LEVEL:
			row.add_child(_tag(StoryRules.refusal_text(refusal, step), Hub2Style.BAD, Color(0, 0, 0, 0), Hub2Style.BAD))
		_:
			row.add_child(_tag(Lang.t("EN COURS", "ONGOING"), Hub2Style.TEAL, Color(0, 0, 0, 0), Hub2Style.teal_a(0.6)))
	sv.add_child(_title(HubData.text_of(step.title)))
	sv.add_child(_paragraph(Hub2LabKit.quoted(HubData.text_of(step.text))))
	var reqs := VBoxContainer.new()
	reqs.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	reqs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(reqs)
	var prog := ContractRules.progress(step, pr.samples)
	for k in prog:
		var rq := VBoxContainer.new()
		rq.add_theme_constant_override("separation", int(Hub2Style.px(6)))
		rq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rr := HBoxContainer.new()
		rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := Hub2Style.label(Hub2LabKit.full_name(String(k)), Hub2Style.BARLOW, 400, 15, Hub2Style.TEXT)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(nl)
		var have: int = prog[k][0]
		var need: int = prog[k][1]
		var ct2 := Hub2Text.new()
		ct2.setup("%d / %d" % [have, need], Hub2Style.MONO, 700, 15, Hub2Style.TEAL if have >= need else Hub2Style.TEXT)
		ct2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rr.add_child(ct2)
		rq.add_child(rr)
		var bar := Bar.new()
		bar.ratio = float(have) / maxf(float(need), 1.0)
		rq.add_child(bar)
		reqs.add_child(rq)
	# Récompense et REMETTRE (margin-top: auto : en bas du corps).
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(foot)
	var fl := VBoxContainer.new()
	fl.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(fl)
	fl.add_child(Hub2Style.label(Lang.t("Récompense", "Reward"), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.6)))
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(tiles)
	var item := StoryRules.preview_item(pr, step)
	for spec in Hub2LabKit.reward_tiles(pr, step.reward, item, StoryRules.xp_for(step, pr.level(), story), true):
		var t := _tile(spec, false)
		tiles.add_child(t)
		story_tiles.append(t)
	unlock_text = _unlock_text(step)
	var ul := Hub2Style.label(unlock_text, Hub2Style.BARLOW, 400, 13, Hub2Style.TEAL)
	ul.clip_text = true
	ul.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fl.add_child(ul)
	hand_in_button = _hand_in(refusal == "")
	hand_in_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_in_button.pressed.connect(deliver_story)
	# Prête : l'aide de l'écran reste (maquette) ; sinon, pourquoi.
	hand_in_button.hint = "" if refusal == "" else _story_refusal_hint(refusal)
	foot.add_child(hand_in_button)


## « Débloque l'étape 4 : « Fiches patients » », le chapitre suivant, ou la
## fin de l'histoire.
func _unlock_text(s: Dictionary) -> String:
	var nx := StoryRules.next_step(s.id, story)
	if nx.is_empty():
		return Lang.t("Dernière étape de l’histoire", "Last step of the story")
	var nl := story.locate(nx.id)
	if String(nx.chapter) != String(s.chapter):
		return Lang.t("Débloque le chapitre %d : « %s »", "Unlocks chapter %d: “%s”") % [int(nl.chapter_index) + 1,
			HubData.text_of(nl.chapter.title)]
	return Lang.t("Débloque l’étape %d : « %s »", "Unlocks step %d: “%s”") % [int(nl.step_index) + 1, HubData.text_of(nx.title)]


func _story_refusal_hint(reason: String) -> String:
	if reason == StoryRules.LEVEL:
		return Lang.t("Dr Brown attend que vous soyez niveau %d pour cette étape.", "Dr Brown is waiting for you to reach level %d for this step.") \
				% int(step.min_level)
	return Lang.t("Il manque des échantillons : rapportez-les d’une partie (évacuez pour les garder).",
			"Samples are missing: bring them back from a match (evacuate to keep them).")


## REMETTRE : 52 px, padding 0 26, jaune, Chakra Petch 18 px 700 0.14em ;
## anneaux pulsés (1.1 × 1.5) quand l'étape est prête ; sinon grisé.
func _hand_in(ready: bool) -> Hub2Button:
	var b := Hub2Button.new()
	b.box.flat(Hub2Style.YELLOW if ready else Hub2Style.white_a(0.08))
	b.box.pad(0, 26)
	b.custom_minimum_size.y = Hub2Style.px(52)
	var t := Hub2Text.new()
	t.setup(Lang.t("REMETTRE", "HAND IN"), Hub2Style.CHAKRA, 700, 18, Hub2Style.INK if ready else Hub2Style.text_a(0.4), 0.14)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_content(t)
	b.disabled = not ready
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ready else Control.CURSOR_ARROW
	hand_in_rings = Hub2PulseRings.new()
	hand_in_rings.scale_to = Vector2(1.1, 1.5)
	hand_in_rings.running = ready
	b.add_child(hand_in_rings)
	return b


# --------------------------------------------------------------------------
# CONTRATS TEMPORAIRES
# --------------------------------------------------------------------------

func _temps(pr: PlayerProfile) -> void:
	temps_scroll = _scroll()
	temps_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(temps_scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	temps_scroll.add_child(v)
	var act := HubContractsView.active(pr, day)
	var amax := int(data.rules.active_max)
	var hd := VBoxContainer.new()
	hd.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hd)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hd.add_child(hr)
	var h2 := Hub2Text.new()
	h2.setup(Lang.t("CONTRATS TEMPORAIRES", "TIMED CONTRACTS"), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT, 0.08)
	hr.add_child(h2)
	var cnt := Hub2Text.new()
	count_text = Lang.t("%d / %d en cours", "%d / %d ongoing") % [act.size(), amax]
	cnt.setup(count_text, Hub2Style.MONO, 500, 13, Hub2Style.text_a(0.55))
	cnt.size_flags_vertical = Control.SIZE_SHRINK_END
	hr.add_child(cnt)
	var d := Hub2Style.label(Lang.t("Des demandes ponctuelles du labo, renouvelées après chaque partie. Elles expirent.",
			"One-off requests from the lab, renewed after every match. They expire."), Hub2Style.BARLOW, 400, 14, Hub2Style.text_a(0.6))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hd.add_child(d)
	if act.is_empty():
		var e := Hub2Box.new()
		e.glass()
		e.pad(14, 18)
		e.add_child(_wrap_label(Lang.t("Aucun contrat temporaire en cours : acceptez une proposition ci-dessous.",
				"No timed contract in progress: accept an offer below."), 14, Hub2Style.text_a(0.6)))
		v.add_child(e)
	for c in act:
		var card := _temp_card(c, pr)
		v.add_child(card)
		temp_cards[c.id] = card
	var ph := Hub2Text.new()
	ph.setup(Lang.t("PROPOSITIONS", "OFFERS"), Hub2Style.CHAKRA, 600, 13, Hub2Style.text_a(0.55), 0.18)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_top", int(Hub2Style.px(6)))
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_child(ph)
	v.add_child(pm)
	var ob := Hub2Box.new()
	ob.glass()
	v.add_child(ob)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 0)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ob.add_child(ov)
	var offers := HubContractsView.offers(pr, day)
	if offers.is_empty():
		var em := Hub2Box.new()
		em.flat(Color(0, 0, 0, 0))
		em.pad(10, 16)
		em.add_child(_wrap_label(Lang.t("Nouvelles propositions après votre prochaine partie.",
				"New offers after your next match."), 13, Hub2Style.text_a(0.6)))
		ov.add_child(em)
	var full := act.size() >= amax
	for i in offers.size():
		ov.add_child(_offer_row(offers[i], pr, i, full))


## Contrat temporaire en cours (article : padding 14 18, écart 16, verre) :
## focusable (A : remettre s'il est prêt ; X : abandonner en deux appuis).
func _temp_card(c: Dictionary, pr: PlayerProfile) -> Hub2Button:
	var b := Hub2Button.new()
	var ready: bool = c.ready
	b.box.glass(Hub2Style.GLASS, Hub2Style.yellow_a(0.6) if ready else Hub2Style.LINE, 1.0)
	b.box.pad(14, 18)
	b.set_meta("id", c.id)
	b.set_meta("ready", ready)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ready else Control.CURSOR_ARROW
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tr)
	# Titre à sa largeur, coupé (…) au-delà de 200 px : la carte tient dans
	# sa colonne à toute taille des menus.
	var tt := Hub2Style.label(String(c.title), Hub2Style.CHAKRA, 700, 18, Hub2Style.TEXT)
	tt.clip_text = true
	tt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tf := Hub2Style.font(Hub2Style.CHAKRA, 700)
	tt.custom_minimum_size.x = minf(ceilf(tf.get_string_size(tt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, Hub2Style.fs(18)).x),
			Hub2Style.px(200))
	tr.add_child(tt)
	var time := Hub2Text.new()
	time.setup(Hub2LabKit.time_left(int(c.days)), Hub2Style.MONO, 500, 12, ORANGE)
	time.size_flags_vertical = Control.SIZE_SHRINK_END
	tr.add_child(time)
	b.set_meta("time", time)
	var needs := HFlowContainer.new()
	needs.add_theme_constant_override("h_separation", int(Hub2Style.px(14)))
	needs.add_theme_constant_override("v_separation", int(Hub2Style.px(4)))
	needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(needs)
	# Prêt (pas dans la maquette) : étiquette TERMINÉ en tête des
	# échantillons (la ligne du titre reste à la largeur de la colonne).
	if ready:
		needs.add_child(_tag(Lang.t("TERMINÉ", "DONE"), Hub2Style.INK, Hub2Style.YELLOW))
	var prog := ContractRules.progress(c.contract, pr.samples)
	for k in prog:
		var n := HBoxContainer.new()
		n.add_theme_constant_override("separation", int(Hub2Style.px(4)))
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(Hub2Style.label(Hub2LabKit.word_cap(String(k), int(prog[k][1])), Hub2Style.BARLOW, 400, 14, Hub2Style.text_a(0.8)))
		var ok: bool = prog[k][0] >= prog[k][1]
		var nt := Hub2Text.new()
		nt.setup("%d/%d" % [prog[k][0], prog[k][1]], Hub2Style.MONO, 700, 14, Hub2Style.TEAL if ok else Hub2Style.TEXT)
		nt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.add_child(nt)
		needs.add_child(n)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tiles)
	var item := ContractRules.preview_item(pr, c.contract)
	for spec in Hub2LabKit.reward_tiles(pr, c.contract.reward, item, ContractRules.xp_for(data, c.contract, pr.level()), false):
		tiles.add_child(_tile(spec, true))
	b.hint = Lang.t("Contrat prêt : A / Entrée pour le remettre. X : abandonner.", "Contract ready: A / Enter to hand it in. X: abandon.") \
			if ready else Lang.t("Il manque des échantillons. X : abandonner (rien n’est consommé).",
			"Samples are missing. X: abandon (nothing is used up).")
	b.pressed.connect(deliver_temp.bind(String(c.id)))
	return b


## Proposition (padding 10 16, écart 16, filet du haut 6 % sauf la
## première) : titre, demande et récompense en mots, temps restant,
## ACCEPTER (h 32, liseré 40 %).
func _offer_row(o: Dictionary, pr: PlayerProfile, i: int, full: bool) -> Control:
	var r := Hub2Box.new()
	r.flat(Color(0, 0, 0, 0), Hub2Style.white_a(0.06), 1.0)
	r.border = Vector4(0, 1 if i > 0 else 0, 0, 0)
	r.pad(10, 16)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(h)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", int(Hub2Style.px(2)))
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(lv)
	var c: Dictionary = o.contract
	var tl := Hub2Style.label(String(o.title), Hub2Style.CHAKRA, 600, 15, Hub2Style.TEXT)
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lv.add_child(tl)
	var ask := Hub2LabKit.cost_line(c.samples)
	var rw := Hub2LabKit.reward_words(c.reward)
	var al := Hub2Style.label(ask + (" · " + rw if rw != "" else ""), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.6))
	al.clip_text = true
	al.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lv.add_child(al)
	var tm := Hub2Text.new()
	tm.setup(Hub2LabKit.offer_time(int(o.days)), Hub2Style.MONO, 500, 12, Hub2Style.text_a(0.5))
	tm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tm)
	var why := ContractRules.accept_refusal(pr.contracts, data, o.id, day)
	var b := Hub2Button.new()
	b.box.flat(Color(0, 0, 0, 0), Hub2Style.text_a(0.4 if why == "" else 0.15), 1.0)
	b.box.pad(0, 14)
	b.custom_minimum_size.y = Hub2Style.px(32)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bt := Hub2Text.new()
	bt.setup(Lang.t("ACCEPTER", "ACCEPT"), Hub2Style.CHAKRA, 700, 12, Hub2Style.TEXT if why == "" else Hub2Style.text_a(0.35), 0.12)
	bt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_content(bt)
	b.disabled = why != ""
	b.set_meta("id", o.id)
	b.hint = (ContractRules.refusal_text(why, int(data.rules.active_max)) + " : " + Lang.t("remettez ou abandonnez un contrat en cours.",
			"hand in or abandon an ongoing contract.")) if why == ContractRules.ACTIVE_FULL else \
			HubData.text_of(c.text)
	b.pressed.connect(accept.bind(String(o.id)))
	h.add_child(b)
	offer_buttons[o.id] = b
	return r


# --------------------------------------------------------------------------
# Éléments
# --------------------------------------------------------------------------

func _tile(spec: Dictionary, right: bool) -> Hub2RewardTile:
	var t := Hub2RewardTile.new()
	t.setup(spec)
	t.tip_right = right
	t.tip.connect(_on_tip)
	return t


func _on_tip(tile: Hub2RewardTile, on: bool) -> void:
	if on:
		tooltip.show_for(tile)
	elif tooltip.tile == tile:
		tooltip.show_for(null)


## Étiquette (padding 3 10, Chakra Petch 12 px 700 0.14em).
func _tag(text: String, fg: Color, bg: Color, line := Color(0, 0, 0, 0)) -> Hub2Box:
	var b := Hub2Box.new()
	b.flat(bg, line, 1.0 if line.a > 0.0 else 0.0)
	b.pad(3, 10)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, 700, 12, fg, 0.14)
	b.add_child(t)
	return b


## Titre de l'étape : Chakra Petch 30 px 700, line-height 1.05.
func _title(text: String) -> Label:
	var l := Hub2Style.label(text, Hub2Style.CHAKRA, 700, 30, Hub2Style.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
	l.add_theme_constant_override("line_spacing", int(roundf(Hub2Style.px(30 * 1.05) - Hub2Style.line_height(f, Hub2Style.fs(30)))))
	return l


## Demande de Dr Brown : 16 px, line-height 1.5, 82 %.
func _paragraph(text: String) -> Label:
	var l := Hub2Style.label(text, Hub2Style.BARLOW, 400, 16, Hub2Style.text_a(0.82))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f := Hub2Style.font(Hub2Style.BARLOW, 400)
	l.add_theme_constant_override("line_spacing", int(roundf(Hub2Style.px(16 * 1.5) - Hub2Style.line_height(f, Hub2Style.fs(16)))))
	return l


func _wrap_label(text: String, sz: float, color: Color) -> Label:
	var l := Hub2Style.label(text, Hub2Style.BARLOW, 400, sz, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = Hub2Style.px(h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Défilement vertical sans barre visible (molette, focus suivi) : rien ne
## sort de l'écran à une grande taille des menus.
func _scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	s.follow_focus = true
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	s.get_v_scroll_bar().scrolling.connect(func(): tooltip.show_for(null))
	return s


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

## REMETTRE l'étape d'histoire en cours.
func deliver_story() -> void:
	var pr := profile()
	if StoryRules.refusal(pr, story) != "":
		return
	var res := StoryRules.deliver(pr, story)
	if not res.ok:
		return
	Audio.play_ui(MenuStyle.SND_SELECT, -6.0)
	var remaining := {}
	for k in res.step.samples:
		remaining[k] = pr.sample_count(String(k))
	hub.save_profile()
	_open_popup().show_story(res, pr, remaining)
	hub.refresh_prompts()


## Remettre le contrat temporaire `id` (A / Entrée / clic sur l'article prêt).
func deliver_temp(id: String) -> void:
	if confirm_id != "":
		_cancel_confirm()
		return
	var pr := profile()
	if ContractRules.deliver_refusal(pr, data, id, day) != "":
		Audio.play_ui(MenuStyle.SND_BACK, -10.0)
		return
	var c := data.contract(id)
	var res := ContractRules.deliver(pr, data, id, day)
	if not res.ok:
		return
	Audio.play_ui(MenuStyle.SND_SELECT, -6.0)
	var remaining := {}
	for k in c.samples:
		remaining[k] = pr.sample_count(String(k))
	hub.save_profile()
	_open_popup().show_contract(c, res, pr, remaining)
	hub.refresh_prompts()


## ACCEPTER la proposition `id`.
func accept(id: String) -> void:
	var why := ContractRules.accept(profile().contracts, data, id, day)
	if why != "":
		Audio.play_ui(MenuStyle.SND_BACK, -10.0)
		return
	Audio.play_ui(MenuStyle.SND_SELECT, -6.0)
	hub.save_profile()
	var card: Control = temp_cards.get(id)
	if card:
		hub.focus_later(card)


## ABANDONNER (X) : premier appui, l'article passe en rouge (« ABANDONNER ? ») ;
## deuxième appui : le contrat disparaît, rien n'est consommé.
func abandon(id: String) -> void:
	var card: Hub2Button = temp_cards.get(id)
	if card == null:
		return
	if confirm_id != id:
		_cancel_confirm()
		confirm_id = id
		card.box.border_color = Hub2Style.BAD
		var tm: Hub2Text = card.get_meta("time")
		tm.text = Lang.t("ABANDONNER ?", "ABANDON?")
		tm.color = Hub2Style.BAD
		if not card.has_focus():
			card.grab_focus()
		hub.set_hint(Lang.t("Appuyez encore sur X pour abandonner « %s » : rien n’est consommé.",
				"Press X again to abandon “%s”: nothing is used up.") % HubData.text_of(data.contract(id).title))
		hub.refresh_prompts()
		return
	confirm_id = ""
	if ContractRules.abandon(profile().contracts, id):
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		hub.set_hint("")
		hub.save_profile()
		hub.focus_later(first_focus())


func _cancel_confirm(prompts_too := true) -> void:
	if confirm_id == "":
		return
	var card: Hub2Button = temp_cards.get(confirm_id)
	var c := data.contract(confirm_id)
	confirm_id = ""
	if card and is_instance_valid(card):
		card.box.border_color = Hub2Style.yellow_a(0.6) if card.get_meta("ready") else Hub2Style.LINE
		var tm: Hub2Text = card.get_meta("time")
		var days := -1
		for a in HubContractsView.active(profile(), day):
			if a.id == c.get("id", ""):
				days = int(a.days)
		tm.text = Hub2LabKit.time_left(days)
		tm.color = ORANGE
	if prompts_too and hub:
		hub.set_hint("")
		hub.refresh_prompts()


func _open_popup() -> Hub2RewardPopup:
	tooltip.show_for(null)
	popup = Hub2RewardPopup.new()
	popup.hub = hub
	hub.add_child(popup)
	popup.closed.connect(_on_popup_closed)
	return popup


func _on_popup_closed() -> void:
	popup = null
	if hub == null or not is_visible_in_tree():
		return
	hub.set_hint("")
	hub.refresh_prompts()
	hub.focus_later(first_focus())


func popup_open() -> bool:
	return popup != null and is_instance_valid(popup) and popup.is_open()


# --------------------------------------------------------------------------
# Hub2Panel
# --------------------------------------------------------------------------

## Focus : REMETTRE si l'étape est prête, sinon un contrat temporaire prêt,
## sinon une proposition qu'on peut accepter, sinon REMETTRE (grisé).
func first_focus() -> Control:
	if hand_in_button and not hand_in_button.disabled:
		return hand_in_button
	for id in temp_cards:
		if temp_cards[id].get_meta("ready"):
			return temp_cards[id]
	for id in offer_buttons:
		if not offer_buttons[id].disabled:
			return offer_buttons[id]
	if hand_in_button:
		return hand_in_button
	if not temp_cards.is_empty():
		return temp_cards.values()[0]
	return null


func prompts() -> Array:
	if popup_open():
		var out := []
		if popup.primary_button:
			out.append([Hub2Input.ACCEPT, popup.primary_text])
		out.append([Hub2Input.BACK, Lang.t("Fermer", "Close")])
		return out
	if confirm_id != "":
		return [[Hub2Input.SECONDARY, Lang.t("Confirmer l’abandon", "Confirm abandon")], [Hub2Input.BACK, Lang.t("Annuler", "Cancel")]]
	var f := _focus_owner()
	if f and offer_buttons.values().has(f):
		return [[Hub2Input.ACCEPT, Lang.t("Accepter", "Accept")], [Hub2Input.BACK, Lang.t("Labo", "Lab")]]
	return [[Hub2Input.ACCEPT, Lang.t("Remettre", "Hand in")], [Hub2Input.SECONDARY, Lang.t("Abandonner", "Abandon")],
		[Hub2Input.BACK, Lang.t("Labo", "Lab")]]


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
		# La fenêtre garde la main : ni onglets ni JOUER derrière elle.
		return Hub2Input.tab_step(event) != 0 or Hub2Input.is_play(event)
	if _is_secondary(event):
		on_prompt(Hub2Input.SECONDARY)
		return true
	return false


static func _is_secondary(event: InputEvent) -> bool:
	if Hub2Input.is_key(event, KEY_DELETE) or Hub2Input.is_key(event, KEY_R) or Hub2Input.is_key(event, KEY_X):
		return true
	var j := event as InputEventJoypadButton
	return j != null and j.pressed and j.button_index == JOY_BUTTON_X


## X / Suppr / clic sur l'invite : abandonner le contrat temporaire choisi
## (celui qui a le focus, ou dont une tuile a le focus ; sinon celui en
## attente de confirmation).
func on_prompt(id: String) -> void:
	if id != Hub2Input.SECONDARY:
		return
	var card := _focused_card()
	if card == null and confirm_id != "":
		card = temp_cards.get(confirm_id)
	if card:
		abandon(String(card.get_meta("id")))


func shown() -> void:
	tooltip.show_for(null)


func hidden() -> void:
	_cancel_confirm(false)
	if tooltip:
		tooltip.show_for(null)
	if popup_open():
		popup.close()


func badge() -> bool:
	return Hub2LabKit.ready_total(profile()) > 0


func _on_focus_changed(c: Control) -> void:
	if not is_visible_in_tree():
		return
	if confirm_id != "":
		var card: Control = temp_cards.get(confirm_id)
		if card == null or (c != card and not card.is_ancestor_of(c)):
			_cancel_confirm()
	if hub and is_ancestor_of(c):
		hub.refresh_prompts()


func _focus_owner() -> Control:
	var vp := get_viewport()
	return vp.gui_get_focus_owner() if vp else null


## Article du contrat temporaire qui a le focus (ou dont une tuile l'a).
func _focused_card() -> Hub2Button:
	var f := _focus_owner()
	if f == null:
		return null
	for id in temp_cards:
		var c: Hub2Button = temp_cards[id]
		if f == c or c.is_ancestor_of(f):
			return c
	return null


## Repère du focus, gardé à la reconstruction (profil changé).
func _focus_key() -> String:
	var f := _focus_owner()
	if f == null or not is_ancestor_of(f):
		return ""
	if f == hand_in_button:
		return "story"
	for id in temp_cards:
		if f == temp_cards[id]:
			return "temp:" + id
	for id in offer_buttons:
		if f == offer_buttons[id]:
			return "offer:" + id
	return ""


func _from_key(key: String) -> Control:
	if key == "story":
		return hand_in_button
	if key.begins_with("temp:"):
		return temp_cards.get(key.substr(5))
	if key.begins_with("offer:"):
		var id := key.substr(6)
		# Proposition acceptée : son contrat en cours.
		return offer_buttons.get(id, temp_cards.get(id))
	return null
