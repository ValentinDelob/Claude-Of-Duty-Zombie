class_name HubLabPanel
extends HubPanel
## Onglet LABO, accueil du hub (docs/HUB_PLAN.md §3.1, maquette écran 1) :
## trois colonnes —
##   - LE SCIENTIFIQUE (portrait cubique, réplique du moment, contrats prêts,
##     VOIR LES CONTRATS / LANCER UNE PARTIE) et DERNIÈRE PARTIE (issue,
##     manche, XP, butin gardé, VOIR L'ARSENAL) ;
##   - PROFIL (niveau, barre d'XP, meilleur score de l'arsenal, nombre
##     d'armes, de pièces, de contrats remplis ; pas de puissance, D5) et
##     CONTRATS ACTIFS (progression par échantillon, PRÊT, date de fin) ;
##   - RÉSERVE D'ÉCHANTILLONS (sortes connues, quantités, ennemi source ;
##     sortes jamais obtenues en « ??? »).
## Lecture seule du profil. Contrats : HubContractsView (lot A pas encore en
## place : un emplacement l'annonce).

## Colonnes et hauteurs de la maquette (px à 100 %), pour les proportions.
const COL_W := [420.0, 400.0, 396.0]
const SCIENTIST_H := 344.0
const LAST_H := 196.0
const PROFILE_H := 188.0
const CONTRACTS_H := 352.0
## Nom de la sorte d'ennemi de chaque groupe d'échantillons (LootRules.SAMPLES)
## [titre du groupe FR, EN, source FR, EN].
const GROUPS := {
	"dogs": ["MEUTE ERRANTE (CHIENS)", "STRAY PACK (DOGS)", "par chien tué", "per dog killed"],
}
## Sortes à découvrir montrées en « ??? » (ennemis à venir, GAME_CONCEPT §4.17).
const UNKNOWN_TEASERS := 2

var contracts_button: HubButton
var play_button: HubButton
var arsenal_button: HubButton
## Réplique affichée (tests).
var line_text := ""
var speech: RichTextLabel
var level_label: Label
var progress_label: Label
var xp_bar: HubBar
var stats: Dictionary = {}  # clé -> Label de la valeur
var sample_labels: Dictionary = {}  # sorte -> Label de la quantité
var contract_rows: Array = []
var contracts_box: HubBox
var last_box: HubBox
var _root: HBoxContainer


func build() -> void:
	_root = HubBox.hbox(16)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_fill()


## Le profil a changé : tout est relu (écran léger).
func refresh() -> void:
	var had_focus := get_viewport() != null and get_viewport().gui_get_focus_owner() != null \
		and is_ancestor_of(get_viewport().gui_get_focus_owner())
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	stats.clear()
	sample_labels.clear()
	contract_rows.clear()
	_fill()
	if had_focus:
		hub.focus_later(contracts_button)


func _fill() -> void:
	var pr := profile()
	var c1 := _column(0)
	c1.add_child(_scientist(pr))
	c1.add_child(_last_match())
	var c2 := _column(1)
	c2.add_child(_profile(pr))
	c2.add_child(_contracts(pr))
	var c3 := _column(2)
	c3.add_child(_reserve(pr))


func _column(i: int) -> VBoxContainer:
	var v := HubBox.vbox(16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = COL_W[i]
	v.custom_minimum_size = Vector2.ZERO
	_root.add_child(v)
	return v


func _sized(b: HubBox, h: float) -> HubBox:
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = h
	return b


func first_focus() -> Control:
	return contracts_button


func prompts() -> Array:
	return [[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]


# --------------------------------------------------------------------------
# LE SCIENTIFIQUE
# --------------------------------------------------------------------------

func _scientist(pr: PlayerProfile) -> HubBox:
	var box := _sized(HubBox.new(Lang.t("LE SCIENTIFIQUE", "THE SCIENTIST"), "", true), SCIENTIST_H)
	var v := box.content
	var top := HubBox.hbox(18)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_child(HubBox.pad(top, 12, 10, 12, 10))
	var portrait := HubIcon.make("doc", 9)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(portrait)
	var bubble := HubSpeech.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var bm := HubBox.pad(bubble, 6, 8, 0, 0)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(bm)
	line_text = scientist_line(pr)
	speech = bubble.text_label
	bubble.set_line(line_text)
	# Contrats prêts, ou état des contrats.
	var lines := HubBox.vbox(6)
	v.add_child(HubBox.pad(lines, 12, 4, 12, 0))
	for l in _status_lines(pr):
		lines.add_child(l)
	v.add_child(HubBox.spring())
	var btns := HubBox.hbox(8)
	v.add_child(HubBox.pad(btns, 12, 8, 12, 12))
	contracts_button = hub_button(Lang.t("VOIR LES CONTRATS", "SEE CONTRACTS"), func(): hub.select_tab("contracts"),
			HubButton.PRIMARY, Lang.t("Remettre vos contrats prêts au scientifique.", "Hand your ready contracts in to the scientist."))
	contracts_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(contracts_button)
	play_button = hub_button(Lang.t("LANCER UNE PARTIE", "START A MATCH"), func(): hub.select_tab("play"),
			HubButton.NORMAL, Lang.t("Choisir le mode et la carte (onglet PARTIE).", "Pick the mode and the map (PLAY tab)."))
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(play_button)
	return box


## Réplique du scientifique selon la situation (texte BBCode : [b] en rouge).
static func scientist_line(pr: PlayerProfile) -> String:
	if HubContractsView.ready_count(pr) > 0:
		return Lang.t("Un contrat est prêt, je le [b]sens[/b] d'ici. Posez vos échantillons sur la paillasse… doucement.",
				"A contract is ready, I can [b]smell[/b] it from here. Put your samples on the bench… gently.")
	var last: Dictionary = Router.last_match
	if not last.is_empty() and last.get("result") is MatchResult:
		if (last.result as MatchResult).evacuated:
			return Lang.t("Évacuation réussie ! Montrez-moi ce que vous avez [b]ramené[/b]. Non, pas la boue.",
					"Extraction successful! Show me what you [b]brought back[/b]. No, not the mud.")
		return Lang.t("Le butin est resté là-bas, mais vous êtes revenu. Enfin, [b]presque[/b] entier.",
				"The loot stayed down there, but you came back. Well, [b]almost[/b] in one piece.")
	if pr.xp == 0 and pr.weapons.is_empty():
		return Lang.t("Ah, un volontaire ! Ne touchez à rien, surtout pas au bocal qui [b]bouge[/b].",
				"Ah, a volunteer! Don't touch anything, especially the jar that [b]moves[/b].")
	return Lang.t("Vous revoilà, entier en plus. Je note ça dans le [b]registre des miracles[/b].",
			"You're back, in one piece too. I'm writing that down in the [b]book of miracles[/b].")


func _status_lines(pr: PlayerProfile) -> Array:
	var out := []
	if not HubContractsView.available(pr):
		out.append(_status(HubTag.make(Lang.t("BIENTÔT", "SOON")), Lang.t("Contrats du scientifique", "The scientist's contracts"),
				Lang.t("onglet CONTRATS", "CONTRACTS tab")))
		return out
	var act := HubContractsView.active(pr)
	var ready := 0
	for c in act:
		if c.ready and ready < 2:
			ready += 1
			out.append(_status(HubTag.make(Lang.t("PRÊT", "READY"), HubTag.READY), String(c.title), Lang.t("à remettre", "to hand in")))
	if ready == 0:
		out.append(_status(HubTag.make(str(act.size())), Lang.t("contrat actif" if act.size() <= 1 else "contrats actifs",
				"active contract" if act.size() == 1 else "active contracts"), Lang.t("aucun prêt", "none ready")))
	return out


func _status(tag: HubTag, t: String, right: String) -> HBoxContainer:
	var h := HubBox.hbox(8)
	h.add_child(tag)
	var l := HubStyle.label(t, 14, HubStyle.PAPER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(l)
	h.add_child(HubStyle.label(right, 13, HubStyle.DIM))
	return h


# --------------------------------------------------------------------------
# DERNIÈRE PARTIE
# --------------------------------------------------------------------------

func _last_match() -> HubBox:
	var last: Dictionary = Router.last_match
	var r: MatchResult = last.get("result") if last.get("result") is MatchResult else null
	var right := ""
	if r:
		right = "%s · %s" % [String(last.get("map", "")).to_upper(),
			"SOLO" if last.get("solo", true) else Lang.t("COOP", "CO-OP")]
	last_box = _sized(HubBox.new(Lang.t("DERNIÈRE PARTIE", "LAST MATCH"), right), LAST_H)
	var v := HubBox.vbox(8)
	last_box.content.add_child(HubBox.pad(v, 12, 10, 12, 10))
	if r == null:
		var none := HubStyle.label(Lang.t("Aucune partie depuis le lancement du jeu.", "No match since the game started."), 14, HubStyle.PLASTER)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(none)
		var tip := HubStyle.label(Lang.t("Après une partie : issue, manche, XP gagnée et butin gardé.",
				"After a match: outcome, round, XP earned and loot kept."), 13, HubStyle.DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tip)
	else:
		var l1 := HubBox.hbox(10)
		var outcome := HubStyle.label(r.title(), 20, HubStyle.OK if r.evacuated else HubStyle.BAD, "impact", true)
		l1.add_child(outcome)
		var sub := HubStyle.label(Lang.t("manche %d · %d zombies", "round %d · %d zombies") % [r.round_reached, r.kills], 13, HubStyle.DIM)
		sub.size_flags_vertical = Control.SIZE_SHRINK_END
		l1.add_child(sub)
		v.add_child(l1)
		var l2 := HubBox.hbox(16)
		var xp_row := HubBox.hbox(4)
		xp_row.add_child(HubStyle.label("+" + HubStyle.num(r.xp), 18, HubStyle.YELLOW, "impact", true))
		var xpl := HubStyle.label("XP", 14, HubStyle.PAPER)
		xpl.size_flags_vertical = Control.SIZE_SHRINK_END
		xp_row.add_child(xpl)
		l2.add_child(xp_row)
		var loot := r.loot
		var ws: Array = loot.get("weapons", []) if loot.get("weapons") is Array else []
		var n_samples := 0
		var ss: Variant = loot.get("samples", {})
		if ss is Dictionary:
			for k in ss:
				n_samples += maxi(int(ss[k]), 0)
		var kept: bool = loot.get("kept", false) == true
		if kept or loot.is_empty():
			for t in [_count(ws.size(), "arme", "armes", "weapon", "weapons"),
					_count(int(loot.get("parts", 0)), "pièce", "pièces", "part", "parts"),
					_count(n_samples, "échantillon", "échantillons", "sample", "samples")]:
				var tl := HubStyle.label(t, 14, HubStyle.PAPER)
				tl.size_flags_vertical = Control.SIZE_SHRINK_END
				l2.add_child(tl)
		else:
			var lost := HubStyle.label(Lang.t("butin perdu, l'XP est gardée", "loot lost, XP kept"), 14, HubStyle.BAD)
			lost.size_flags_vertical = Control.SIZE_SHRINK_END
			l2.add_child(lost)
		v.add_child(l2)
		if kept and not ws.is_empty():
			var l3 := HubBox.hbox(8)
			for i in mini(ws.size(), 2):
				var w: Array = ws[i]
				if w.size() < 3:
					continue
				if i == 1:
					l3.add_child(HubBox.spring(false))
				l3.add_child(HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW))
				var rr := clampi(int(w[2]), 0, 4)
				var nl := HubStyle.label(WeaponDB.display_name(String(w[0])).to_upper(), 13, HubStyle.rarity_color(rr))
				l3.add_child(nl)
				if i == 0:
					l3.add_child(HubStyle.label(Lang.t("niv. %d · %s", "lvl %d · %s") % [int(w[1]), GameWeapon.rarity_name(rr).to_lower()], 13, HubStyle.DIM))
			v.add_child(l3)
	v.add_child(HubBox.gap(0, 2))
	var b := HubBox.hbox(0)
	arsenal_button = hub_button(Lang.t("VOIR L'ARSENAL", "SEE THE ARSENAL"), func(): hub.select_tab("arsenal"),
			HubButton.NORMAL, Lang.t("Vos armes, leurs versions et leurs pièces.", "Your weapons, their versions and their parts."))
	b.add_child(arsenal_button)
	v.add_child(b)
	return last_box


static func _count(n: int, fr1: String, frn: String, en1: String, enn: String) -> String:
	return "%d %s" % [n, Lang.t(fr1 if n <= 1 else frn, en1 if n == 1 else enn)]


# --------------------------------------------------------------------------
# PROFIL
# --------------------------------------------------------------------------

func _profile(pr: PlayerProfile) -> HubBox:
	var box := _sized(HubBox.new(Lang.t("PROFIL", "PROFILE")), PROFILE_H)
	var v := HubBox.vbox(14)
	box.content.add_child(HubBox.pad(v, 12, 10, 12, 10))
	var top := HubBox.hbox(14)
	v.add_child(top)
	var lv := HubLevelBox.new()
	lv.level = pr.level()
	top.add_child(lv)
	var col := HubBox.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(col)
	var lvl := pr.level()
	level_label = HubStyle.label(Lang.t("NIVEAU %d", "LEVEL %d") % lvl + (Lang.t(" (MAXIMUM)", " (MAX)") if pr.is_max_level() else ""),
			22, HubStyle.PAPER, "impact", true)
	col.add_child(level_label)
	col.add_child(HubBox.gap(0, 6))
	var need := PlayerProfile.xp_to_next(lvl)
	xp_bar = HubBar.make(1.0 if pr.is_max_level() else float(pr.xp_in_level()) / maxf(need, 1.0))
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(xp_bar)
	col.add_child(HubBox.gap(0, 4))
	progress_label = HubStyle.label(progress_text(pr), 13, HubStyle.DIM)
	progress_label.clip_text = true
	progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(progress_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(HubStyle.px(18)))
	grid.add_theme_constant_override("v_separation", int(HubStyle.px(6)))
	v.add_child(grid)
	var done := HubContractsView.done_count(pr)
	_stat(grid, "best_score", Lang.t("Meilleur score", "Best score"), str(best_score(pr)), HubStyle.YELLOW)
	_stat(grid, "weapons", Lang.t("Armes de l'arsenal", "Arsenal weapons"), str(pr.weapons.size()))
	_stat(grid, "parts", Lang.t("Pièces en stock", "Parts in stock"), str(pr.parts.size()))
	_stat(grid, "contracts_done", Lang.t("Contrats remplis", "Contracts done"), str(done) if done >= 0 else "–")
	return box


## « 2 140 / 3 320 XP · encore 1 180 XP pour le niveau 8 ».
static func progress_text(pr: PlayerProfile) -> String:
	if pr.is_max_level():
		return Lang.t("%s XP au total · niveau maximum", "%s total XP · max level") % HubStyle.num(pr.xp)
	var lvl := pr.level()
	var need := PlayerProfile.xp_to_next(lvl)
	return Lang.t("%s / %s XP · encore %s XP pour le niveau %d", "%s / %s XP · %s XP to level %d") % [
		HubStyle.num(pr.xp_in_level()), HubStyle.num(need), HubStyle.num(pr.xp_to_next_level()), lvl + 1]


## Meilleur score de l'arsenal (niveau + niveaux des pièces ; D5 : à la place
## de la puissance) ; armes de base comprises.
static func best_score(pr: PlayerProfile) -> int:
	var best := 0
	for w in pr.weapons:
		best = maxi(best, w.score())
	for w in BaseWeapons.all():
		best = maxi(best, w.score())
	return best


func _stat(grid: GridContainer, key: String, t: String, value: String, col := HubStyle.PAPER) -> void:
	var h := HubBox.hbox(4)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := HubStyle.label(t, 14, HubStyle.PAPER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	var val := HubStyle.label(value, 14, col, "bold")
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	stats[key] = val
	grid.add_child(h)


# --------------------------------------------------------------------------
# CONTRATS ACTIFS
# --------------------------------------------------------------------------

func _contracts(pr: PlayerProfile) -> HubBox:
	var available := HubContractsView.available(pr)
	var act := HubContractsView.active(pr)
	contracts_box = _sized(HubBox.new(Lang.t("CONTRATS ACTIFS", "ACTIVE CONTRACTS"),
			"%d / 3" % act.size() if available else ""), CONTRACTS_H)
	var v := contracts_box.content
	if not available or act.is_empty():
		var m := HubBox.vbox(8)
		v.add_child(HubBox.pad(m, 12, 12, 12, 12))
		var t := HubStyle.label(Lang.t("Aucun contrat actif.", "No active contract.") if available
				else Lang.t("Les contrats du scientifique arrivent bientôt.", "The scientist's contracts are coming soon."), 15, HubStyle.PLASTER)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.add_child(t)
		var d := HubStyle.label(Lang.t("Le scientifique propose des contrats dans l'onglet CONTRATS : rapportez-lui des échantillons contre de l'XP et un objet.",
				"The scientist offers contracts in the CONTRACTS tab: bring him samples for XP and an item."), 13, HubStyle.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.add_child(d)
		return contracts_box
	for i in act.size():
		var c: Dictionary = act[i]
		var samples: Dictionary = c.samples
		var row := HubRow.new(HubRow.ROW, 96.0 + 11.0 * maxf(samples.size() - 1, 0), true, 6.0 if samples.size() <= 1 else 5.0)
		row.alt = i % 2 == 1
		row.bottom_line = i < act.size() - 1
		v.add_child(row)
		contract_rows.append(row)
		var head := HubBox.hbox(8)
		var title := HubStyle.label(String(c.title).to_upper(), 17, HubStyle.PAPER, "impact")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		head.add_child(title)
		var have_total := 0
		var need_total := 0
		for k in samples:
			need_total += int(samples[k])
			have_total += mini(pr.sample_count(k), int(samples[k]))
		var days := HubContractsView.days_left(String(c.ends))
		if c.ready:
			head.add_child(HubTag.make(Lang.t("PRÊT", "READY"), HubTag.READY))
		elif days >= 0:
			head.add_child(HubTag.make(Lang.t("ENCORE %d J", "%d DAYS LEFT") % days, HubTag.DATE))
		else:
			head.add_child(HubStyle.label("%d / %d" % [have_total, need_total], 13, HubStyle.DIM))
		row.box.add_child(head)
		for k in samples:
			row.box.add_child(_progress(String(k), pr.sample_count(k), int(samples[k])))
	return contracts_box


## Ligne de progression (.prog) : icône, barre, « possédés / demandés ».
static func _progress(kind: String, have: int, need: int) -> HBoxContainer:
	var h := HubBox.hbox(8)
	var ic := HubIcon.make(HubIcon.sample_art(kind), 2)
	ic.custom_minimum_size.x = maxf(ic.custom_minimum_size.x, HubStyle.px(22))
	h.add_child(ic)
	var full := have >= need
	var bar := HubBar.make(float(mini(have, need)) / maxf(need, 1.0), HubStyle.OK if full else HubStyle.YELLOW, true)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bar)
	var v := HubStyle.label("%d / %d" % [mini(have, need), need], 13, HubStyle.OK if full else HubStyle.PAPER, "bold")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size.x = HubStyle.px(54)
	h.add_child(v)
	return h


# --------------------------------------------------------------------------
# RÉSERVE D'ÉCHANTILLONS
# --------------------------------------------------------------------------

func _reserve(pr: PlayerProfile) -> HubBox:
	var box := _sized(HubBox.new(Lang.t("RÉSERVE D'ÉCHANTILLONS", "SAMPLE STOCK")), 556.0)
	var v := box.content
	var unknown := 0
	for group in LootRules.SAMPLES:
		var kinds: Array = LootRules.SAMPLES[group]
		if not group_known(pr, group):
			unknown += kinds.size()
			continue
		var g: Array = GROUPS.get(group, [String(group).to_upper(), String(group).to_upper(), "", ""])
		v.add_child(HubRow.group(Lang.t(g[0], g[1])))
		for s in kinds:
			v.add_child(_sample_row(String(s[0]), sentence_case(Lang.t(s[1], s[2])), Lang.t("%d %% %s", "%d%% %s") % [roundi(LootRules.SAMPLE_CHANCE * 100.0),
					Lang.t(g[2], g[3])], pr.sample_count(String(s[0])), true))
	v.add_child(HubRow.group(Lang.t("??? (JAMAIS RENCONTRÉ)", "??? (NEVER MET)")))
	for i in maxi(unknown, UNKNOWN_TEASERS):
		v.add_child(_sample_row("", "???", Lang.t("Survivez plus longtemps…", "Survive longer…"), 0, false))
	var foot := HubStyle.label(Lang.t("Les échantillons s'accumulent d'une partie à l'autre. Remettre un contrat ne consomme que la quantité demandée.",
			"Samples pile up from one match to the next. Handing in a contract only uses the amount asked for."), 13, HubStyle.DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(HubBox.pad(foot, 12, 12, 12, 12))
	return box


## « TOUFFE DE POILS » -> « Touffe de poils » (noms de LootRules.SAMPLES).
static func sentence_case(t: String) -> String:
	var l := t.to_lower()
	return l.left(1).to_upper() + l.substr(1)


## Une sorte est connue dès qu'un échantillon de son groupe est en réserve
## (ou demandé par un contrat actif).
static func group_known(pr: PlayerProfile, group: String) -> bool:
	for s in LootRules.SAMPLES.get(group, []):
		if pr.sample_count(String(s[0])) > 0:
			return true
	for c in HubContractsView.active(pr):
		for s in LootRules.SAMPLES.get(group, []):
			if c.samples.has(String(s[0])):
				return true
	return false


func _sample_row(kind: String, sample_name: String, src: String, qty: int, known: bool) -> HubRow:
	var r := HubRow.new(HubRow.SAMPLE)
	var ic := HubIcon.make(HubIcon.sample_art(kind) if known else "unk", 4)
	r.box.add_child(ic)
	var col := HubBox.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := HubStyle.label(sample_name, 15, HubStyle.PAPER if known else HubStyle.DIM2)
	n.clip_text = true
	col.add_child(n)
	var s := HubStyle.label(src, 12, HubStyle.DIM)
	s.clip_text = true
	col.add_child(s)
	r.box.add_child(col)
	var q := HubStyle.label(str(qty) if known else "–", 22, HubStyle.PAPER if known else HubStyle.DIM2, "impact", true)
	r.box.add_child(q)
	if known:
		sample_labels[kind] = q
	return r


## Pavé du niveau (classe .lvl, 56 px dans le PROFIL).
class HubLevelBox extends Control:
	var level := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = HubStyle.pxv(56, 56)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		HubStyle.draw_box(self, r, HubStyle.YELLOW, HubStyle.px(2), HubStyle.px(3), HubStyle.YELLOW_HI, HubStyle.YELLOW_LO, HubStyle.px(3))
		var f := HubStyle.font("impact")
		var s := HubStyle.fs(32)
		var t := str(level)
		draw_string(f, Vector2((r.size.x - HubStyle.text_width(t, f, s)) * 0.5, HubStyle.baseline(f, s, 0, r.size.y)), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, s, HubStyle.INK)


## Bulle de la réplique du scientifique (classe .speech : papier, contour noir,
## ombre de 4 px, pointe à gauche).
class HubSpeech extends MarginContainer:
	var text_label: RichTextLabel

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("margin_left", int(HubStyle.px(12) + HubStyle.px(2)))
		add_theme_constant_override("margin_right", int(HubStyle.px(12) + HubStyle.px(2)))
		add_theme_constant_override("margin_top", int(HubStyle.px(10) + HubStyle.px(2)))
		add_theme_constant_override("margin_bottom", int(HubStyle.px(10) + HubStyle.px(2)))
		text_label = RichTextLabel.new()
		text_label.bbcode_enabled = true
		text_label.fit_content = true
		text_label.scroll_active = false
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := HubStyle.fs(15)
		text_label.add_theme_font_override("normal_font", HubStyle.font("ui"))
		text_label.add_theme_font_override("bold_font", HubStyle.font("bold"))
		text_label.add_theme_font_size_override("normal_font_size", s)
		text_label.add_theme_font_size_override("bold_font_size", s)
		text_label.add_theme_color_override("default_color", Color("1D1B16"))
		text_label.add_theme_constant_override("line_separation", int(HubStyle.px(2)))
		add_child(text_label)

	## Réplique (BBCode : les mots en [b] sont en rouge sombre).
	func set_line(t: String) -> void:
		text_label.text = t.replace("[b]", "[b][color=#8a1410]").replace("[/b]", "[/color][/b]")

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var b := HubStyle.px(2)
		HubStyle.draw_box(self, r, HubStyle.PAPER, b, HubStyle.px(4))
		# Pointe : carré tourné, à gauche, 18 px sous le haut.
		var t := HubStyle.px(10)
		var y := HubStyle.px(18)
		var p := PackedVector2Array([Vector2(0, y), Vector2(-t - b, y + t * 0.5 + b), Vector2(0, y + t + b * 2.0)])
		draw_colored_polygon(PackedVector2Array([p[0] + Vector2(-b * 2.0, b), p[1] + Vector2(-b, b * 1.5), p[2] + Vector2(-b * 2.0, b)]), HubStyle.BLACK)
		draw_colored_polygon(p, HubStyle.BLACK)
		draw_colored_polygon(PackedVector2Array([p[0] + Vector2(b, b * 1.4), p[1] + Vector2(b * 2.2, 0), p[2] + Vector2(b, -b * 1.4)]), HubStyle.PAPER)
