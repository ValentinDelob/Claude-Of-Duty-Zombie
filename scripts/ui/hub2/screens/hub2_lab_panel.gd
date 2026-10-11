class_name Hub2LabPanel
extends Hub2Panel
## LABO, accueil du hub v2 (docs/hub_v2/Main.dc.html) — PROVISOIRE (cadre) :
## colonne de droite (right 28, top 108, 560 px, écart 20) avec l'en-tête
## (LABORATOIRE DE QUARANTAINE, Dr Brown, sous-titre) et les deux entrées
## CONTRATS (anneaux jaunes pulsés quand un contrat est prêt) et ÉCHANGES, qui
## ouvrent les sous-écrans. À compléter par l'écran réel : Dr Brown en grand
## (rendu Blender, left 70, bottom 6, 640 px de haut), réplique, état des
## contrats, nombre d'échanges possibles.

var contracts_button: Hub2Button
var exchanges_button: Hub2Button
var rings: Hub2PulseRings


func veil() -> Dictionary:
	# linear-gradient(90deg, rgba(8, 9, 11, 0) 35%, rgba(8, 9, 11, 0.75) 70%)
	return {"stops": [[0.35, Hub2Style.shade(0.0)], [0.7, Hub2Style.shade(0.75)]]}


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Ouvrir", "Open")], [Hub2Input.TABS, Lang.t("Onglets", "Tabs")],
		[Hub2Input.PLAY, Lang.t("Jouer", "Play")]]


func help() -> String:
	return Lang.t("Dr Brown cherche l’antidote : ses contrats et ses échanges sont ici.",
			"Dr Brown is working on the antidote: his contracts and trades are here.")


func build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(Hub2Style.px(20)))
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_right = -Hub2Style.px(28)
	col.offset_left = -Hub2Style.px(28) - Hub2Style.px(560)
	col.offset_top = Hub2Style.px(108)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	col.add_child(head)
	var kicker := Hub2Text.new()
	kicker.setup(Lang.t("LABORATOIRE DE QUARANTAINE", "QUARANTINE LAB"), Hub2Style.CHAKRA, 600, 13, Hub2Style.TEAL, 0.24)
	head.add_child(kicker)
	var name_t := Hub2Text.new()
	name_t.setup("Dr Brown", Hub2Style.CHAKRA, 700, 52, Hub2Style.TEXT, 0.02)
	name_t.line_height = 52
	head.add_child(name_t)
	head.add_child(Hub2Style.label(Lang.t("Virologue. Il cherche l’antidote, et il a besoin de vous pour ça.",
			"Virologist. He is looking for the antidote, and he needs you for it."), Hub2Style.BARLOW, 400, 17, Hub2Style.text_a(0.7)))
	var ready := HubContractsView.ready_count(profile()) if profile() else 0
	contracts_button = _card(col, Lang.t("CONTRATS", "CONTRACTS"),
			Lang.t("Histoire et contrats temporaires", "Story and timed contracts"), true,
			Lang.t("Les contrats de Dr Brown : l’histoire et les contrats temporaires.", "Dr Brown's contracts: the story and timed contracts."))
	contracts_button.pressed.connect(func(): hub.call("open", "contracts"))
	rings = Hub2PulseRings.new()
	rings.scale_to = Vector2(1.12, 1.35)
	rings.running = ready > 0
	contracts_button.add_child(rings)
	exchanges_button = _card(col, Lang.t("ÉCHANGES", "EXCHANGES"),
			Lang.t("Des objets précis contre vos échantillons", "Specific items for your samples"), false,
			Lang.t("Le catalogue de Dr Brown : un objet précis contre des échantillons.", "Dr Brown's catalogue: a specific item for samples."))
	exchanges_button.pressed.connect(func(): hub.call("open", "exchanges"))
	contracts_button.focus_neighbor_bottom = contracts_button.get_path_to(exchanges_button)
	exchanges_button.focus_neighbor_top = exchanges_button.get_path_to(contracts_button)


## Entrée du LABO (<a> de la maquette) : padding 18 22, écart 18, carré
## d'icône 52 px, titre Chakra Petch 24 px 700 0.1em, ligne Barlow 15 px 80 %.
func _card(parent: Control, title: String, sub: String, yellow: bool, hint_text: String) -> Hub2Button:
	var b := Hub2Button.new()
	b.hint = hint_text
	if yellow:
		b.box.glass(Hub2Style.YELLOW_TINT, Hub2Style.YELLOW, 2.0)
	else:
		b.box.glass(Hub2Style.GLASS, Hub2Style.white_a(0.12), 1.0)
	b.box.pad(18, 22)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(18)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(row)
	var icon := Hub2Box.new()
	if yellow:
		icon.flat(Hub2Style.YELLOW)
	else:
		icon.flat(Hub2Style.teal_a(0.14), Hub2Style.teal_a(0.5), 1.0)
	icon.custom_minimum_size = Hub2Style.pxv(52, 52)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)
	var t := Hub2Text.new()
	t.setup(title, Hub2Style.CHAKRA, 700, 24, Hub2Style.TEXT, 0.1)
	v.add_child(t)
	v.add_child(Hub2Style.label(sub, Hub2Style.BARLOW, 400, 15, Hub2Style.text_a(0.8)))
	parent.add_child(b)
	return b


func first_focus() -> Control:
	return contracts_button


func refresh() -> void:
	if rings and profile():
		rings.running = HubContractsView.ready_count(profile()) > 0


func badge() -> bool:
	return profile() != null and HubContractsView.ready_count(profile()) > 0
