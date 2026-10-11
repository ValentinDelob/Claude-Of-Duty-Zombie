class_name HubCodexCard
extends HubSlot
## Fiche d'un ennemi de l'onglet CODEX (HubCodexPanel) : HubSlot vertical
## (focus, anneau jaune, clic). Connue : nom, pastille NOUVEAU, famille et
## manche, description, éliminations, XP (XpRules), échantillons. Inconnue :
## pointillés gris, « ??? » et la manche d'apparition seulement.

## Hauteur d'une fiche à 100 %.
const CARD_H := 236.0
## Couleur du « ??? » d'une fiche inconnue.
const UNKNOWN_TEXT := Color("6D6A63")

var id := ""
var known := false


## Remplit une fiche neuve (HubCodexCard.new(HubCodexCard.CARD_H, true, 6.0)).
## Pas de fabrique statique : une méthode statique qui nomme sa propre classe
## garde tout le graphe de scripts chargé à la sortie (fuite vue par le check).
func fill(e: Dictionary, pr: PlayerProfile, is_new: bool) -> void:
	id = String(e.id)
	known = pr != null and pr.codex.is_known(id)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_activates = false
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	if known:
		_build_known(e, pr, is_new)
	else:
		_build_unknown(e)



func _build_known(e: Dictionary, pr: PlayerProfile, is_new: bool) -> void:
	var head := HubBox.hbox(6)
	var n := HubStyle.label(HubData.text_of(e.name).to_upper(), 18, HubStyle.PAPER, "impact", true, 0.04)
	n.clip_text = true
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(n)
	if is_new:
		head.add_child(HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW))
	box.add_child(head)
	box.add_child(HubStyle.label(CodexData.family_line(e), 12, HubStyle.YELLOW, "semi"))
	var d := HubStyle.label(HubData.text_of(e.text), 13, HubStyle.PLASTER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(d)
	var stats := HubBox.hbox(14)
	stats.add_child(_stat(Lang.t("ÉLIMINÉS", "KILLED"), HubStyle.num(pr.codex.kills(id)), HubStyle.PAPER))
	stats.add_child(_stat("XP", HubStyle.num(CodexData.xp(e)), HubStyle.XP_BLUE))
	box.add_child(stats)
	var sm := HubBox.hbox(8)
	var samples: PackedStringArray = e.samples
	if samples.is_empty():
		sm.add_child(HubStyle.label(Lang.t("Aucun échantillon", "No samples"), 12, HubStyle.DIM, "semi"))
	var names := PackedStringArray()
	for s in samples:
		var chip := HubBox.hbox(4)
		chip.add_child(HubIcon.make(HubIcon.sample_art(s), 2))
		chip.add_child(HubStyle.label(CodexData.sample_name(s), 11, HubStyle.GREEN, "semi"))
		sm.add_child(chip)
		names.append(CodexData.sample_name(s).to_lower())
	box.add_child(sm)
	if names.is_empty():
		hint = Lang.t("Cet ennemi ne laisse aucun échantillon.", "This enemy leaves no samples.")
	else:
		hint = Lang.t("Échantillons : %s.", "Samples: %s.") % ", ".join(names)


func _build_unknown(e: Dictionary) -> void:
	empty = true
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var q := HubStyle.label("???", 34, UNKNOWN_TEXT, "impact", false, 0.1)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	var r := HubStyle.label(CodexData.round_hint(int(e.round)), 13, HubStyle.DIM, "semi")
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(r)
	hint = Lang.t("Ennemi inconnu : touchez-le ou laissez-le vous toucher en partie pour remplir sa fiche.",
			"Unknown enemy: hit it, or let it hit you, in a match to fill in its entry.")


func _stat(title: String, value: String, col: Color) -> HBoxContainer:
	var h := HubBox.hbox(5)
	var t := HubStyle.label(title, 11, HubStyle.DIM, "bold", false, 0.06)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	h.add_child(HubStyle.label(value, 16, col, "bold"))
	return h
