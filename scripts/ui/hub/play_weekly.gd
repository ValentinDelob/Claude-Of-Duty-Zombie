class_name HubPlayWeekly
extends RefCounted
## Défi de la semaine dans l'onglet PARTIE (GAME_CONCEPT §4.18) : morceaux de
## la vue SOLO (ligne « DÉFI DE LA SEMAINE » au-dessus des cartes, aperçu à
## droite : carte, modificateurs, objectif, meilleur résultat, temps restant,
## récompense, armes imposées, règles) et du salon coop (l'hôte choisit le
## défi dans CHANGER DE CARTE ; il s'applique à tout le groupe). Même style
## que les lignes de cartes (HubPlayView).

## Identifiant de la ligne du défi dans les listes de cartes.
const ROW_ID := "weekly"


## Défi de la semaine en cours (null : aucune carte de la réserve ne convient).
static func current() -> WeeklyChallenge:
	return WeeklyChallenge.current()


## Titre de la ligne : « S41 · Bunker K-7 ».
static func row_title(ch: WeeklyChallenge) -> String:
	if ch == null:
		return Lang.t("Indisponible cette semaine", "Unavailable this week")
	return "%s · %s" % [ch.week_label(), HubPlayView.map_name(HubPlayView.def_of(ch.map_id))]


## Note à droite de la ligne : « RÉUSSI » ou le temps restant (« 3 j 4 h »).
static func row_note(ch: WeeklyChallenge, pr: PlayerProfile) -> String:
	if ch == null:
		return ""
	if pr and pr.weekly.is_rewarded(ch.key):
		return Lang.t("réussi", "complete")
	return Lang.t("encore %s", "%s left") % WeeklyChallenge.remaining_text(ch.seconds_left())


## Aide de la ligne (barre d'invites).
static func hint(ch: WeeklyChallenge) -> String:
	if ch == null:
		return Lang.t("Aucune carte du jeu ne convient au défi cette semaine.", "No game map suits the challenge this week.")
	return Lang.t("Le même défi pour tout le monde cette semaine : mêmes armes de base, même carte, mêmes conditions.",
		"The same challenge for everyone this week: same base weapons, same map, same conditions.")


## Modificateurs : « [b]Horde pressée[/b] (zombies et chiens 15 % plus
## rapides) » ; « aucun » sans modificateur.
static func mods_text(ch: WeeklyChallenge) -> String:
	if ch.modifiers.is_empty():
		return Lang.t("[b]aucun[/b]", "[b]none[/b]")
	var items := PackedStringArray()
	for m in ch.modifiers:
		items.append("[b]%s[/b] (%s)" % [HubSamplesColumn.esc(WeeklyChallenge.mod_title(m)),
			HubSamplesColumn.esc(lower_first(WeeklyChallenge.mod_text(m).trim_suffix(".")))])
	return " · ".join(items)


## Première lettre en minuscule (« Évacuez » -> « évacuez »).
static func lower_first(t: String) -> String:
	return t.left(1).to_lower() + t.substr(1)


## Trois lignes de l'aperçu (BBCode du hub) : carte et temps restant,
## modificateurs, objectif et meilleur résultat.
static func info_lines(ch: WeeklyChallenge, pr: PlayerProfile) -> Array:
	if ch == null:
		return [hint(null), "", ""]
	var map := HubSamplesColumn.esc(HubPlayView.map_name(HubPlayView.def_of(ch.map_id)))
	return [
		Lang.t("Carte : [b]%s[/b] · semaine %d · fin dans [b]%s[/b]", "Map: [b]%s[/b] · week %d · ends in [b]%s[/b]")
			% [map, ch.week, WeeklyChallenge.remaining_text(ch.seconds_left())],
		Lang.t("Modificateurs : %s", "Modifiers: %s") % mods_text(ch),
		Lang.t("Objectif : [b]%s[/b] · meilleur résultat : [b]%s[/b]", "Goal: [b]%s[/b] · best result: [b]%s[/b]")
			% [lower_first(ch.goal_text()), ch.best_text(pr)],
	]


## Récompense dans la rangée de pastilles : « Récompense : +400 XP », une
## pastille par échantillon, « REÇUE » si déjà donnée cette semaine.
static func fill_reward(chips: Container, ch: WeeklyChallenge, pr: PlayerProfile) -> void:
	for c in chips.get_children():
		chips.remove_child(c)
		c.queue_free()
	if ch == null:
		return
	var lab := HubStyle.label(Lang.t("Récompense (une fois) : +%s XP", "Reward (once): +%s XP") % XpSystem.group(ch.reward_xp_for(pr.level() if pr else 1)), 13, HubStyle.DIM)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chips.add_child(lab)
	var keys := ch.reward_samples.keys()
	keys.sort()
	for k in keys:
		var n := HubStyle.label("%d ×" % int(ch.reward_samples[k]), 13, HubStyle.PAPER, "bold")
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chips.add_child(n)
		chips.add_child(HubPlayView.sample_chip(String(k)))
	if pr and pr.weekly.is_rewarded(ch.key):
		var t := HubTag.make(Lang.t("REÇUE", "CLAIMED"), HubTag.READY)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chips.add_child(t)


## Ligne « VOUS PARTEZ AVEC » du défi : armes de base imposées, sans MODIFIER.
static func loadout_row() -> HubRow:
	var row := HubRow.new()
	var first := true
	for id in WeeklyChallenge.starting_ids():
		if not first:
			row.box.add_child(HubBox.gap(4, 0))
		first = false
		var ic := HubIcon.make(HubPlayView.weapon_art(String(id)), 2)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.box.add_child(ic)
		var l := HubStyle.label(HubPlayView.weapon_label(String(id)), 15, HubStyle.PAPER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.box.add_child(l)
	row.box.add_child(HubBox.spring(false))
	var n := HubStyle.label(Lang.t("imposées : les mêmes pour tous", "fixed: the same for everyone"), 13, HubStyle.DIM)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.box.add_child(n)
	return row


## Règles du défi (lignes sous « RÈGLES DU DÉFI »).
static func rule_texts() -> PackedStringArray:
	return PackedStringArray([
		Lang.t("Votre arsenal et vos pièces restent au labo : la station ne construit que les armes de base.",
			"Your arsenal and parts stay at the lab: the station only builds base weapons."),
		Lang.t("Le butin de la partie n'est pas gardé ; l'XP l'est toujours.",
			"Loot from the game is not kept; XP always is."),
		Lang.t("En coop, le défi de l'hôte s'applique à tout le groupe.",
			"In co-op, the host's challenge applies to the whole group."),
	])


static func rule_rows() -> Array:
	var out := []
	var i := 0
	for t in rule_texts():
		var r := HubRow.new()
		r.alt = i % 2 == 1
		var l := HubStyle.label(t, 13, HubStyle.PLASTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.box.add_child(l)
		out.append(r)
		i += 1
	return out


## Lignes du salon (carte de l'hôte) quand le défi est choisi.
static func lobby_lines(ch: WeeklyChallenge) -> PackedStringArray:
	var out := PackedStringArray()
	if ch == null:
		return out
	var mods := PackedStringArray()
	for m in ch.modifiers:
		mods.append(WeeklyChallenge.mod_title(m))
	out.append(Lang.t("Défi de la semaine %d : %s", "Week %d challenge: %s") % [ch.week,
		", ".join(mods) if not mods.is_empty() else Lang.t("sans modificateur", "no modifier")])
	out.append(ch.goal_text() + Lang.t(" ; armes de base pour tous, butin non gardé.", "; base weapons for everyone, loot not kept."))
	return out
