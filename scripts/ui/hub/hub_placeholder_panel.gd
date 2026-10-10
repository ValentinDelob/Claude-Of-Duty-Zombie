class_name HubPlaceholderPanel
extends HubPanel
## Panneau provisoire « à venir » d'un onglet pas encore fait (lots C, D, E de
## docs/HUB_PLAN.md §8) : titre de l'onglet, ce qu'il contiendra, bouton de
## retour au LABO. Remplacé dès qu'un script est enregistré pour l'onglet
## (HubScreen.PANELS).

## Ce que contiendra chaque onglet [FR, EN].
const CONTENT := {
	"arsenal": ["Vos armes et leurs versions, la fiche de chaque arme, l'installation et le retrait des pièces, le recyclage.",
		"Your weapons and their versions, each weapon's sheet, installing and removing parts, recycling."],
	"parts": ["Toutes vos pièces non installées et, pour chacune, les armes qui peuvent la recevoir.",
		"All your unmounted parts and, for each one, the weapons that can take it."],
	"contracts": ["Les contrats du scientifique : trois actifs au plus, ses propositions, la remise contre de l'XP et un objet.",
		"The scientist's contracts: up to three active, his offers, handing in for XP and an item."],
	"exchanges": ["Le catalogue permanent : vos échantillons contre un objet précis, connu d'avance.",
		"The permanent catalogue: your samples for a precise item, known in advance."],
	"loadout": ["Vos armes de départ : une à trois armes de base, et les armes que vous pourrez construire en partie.",
		"Your starting weapons: one to three base weapons, and the weapons you can build during a match."],
	"play": ["Lancer une partie en solo ou en coopération, et le salon de la coop.",
		"Start a solo or co-op match, and the co-op lobby."],
}

var box: HubBox
var back_button: HubButton


func build() -> void:
	var m := HubBox.pad(HubBox.hbox(), 0, 0, 0, 0)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var row: HBoxContainer = m.get_child(0)
	box = HubBox.new(String(hub.tab_label(tab_id)), Lang.t("à venir", "coming soon"))
	box.custom_minimum_size = Vector2(HubStyle.px(620), 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var v := HubBox.vbox(10)
	box.content.add_child(HubBox.pad(v, 16, 16, 16, 16))
	v.add_child(HubStyle.label(Lang.t("À VENIR", "COMING SOON"), 30, HubStyle.RED_HI, "stencil", true, 0.05))
	var desc := HubStyle.label(_content(), 16, HubStyle.PLASTER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var note := HubStyle.label(Lang.t("Cet onglet sera rempli par une prochaine mise à jour du hub.",
			"This tab will be filled by an upcoming hub update."), 13, HubStyle.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	extra(v)
	v.add_child(HubBox.gap(0, 8))
	var btns := HubBox.hbox(10)
	v.add_child(btns)
	back_button = hub_button(Lang.t("RETOUR AU LABO", "BACK TO THE LAB"), func(): hub.select_tab("lab"),
			HubButton.NORMAL, Lang.t("Revenir à l'accueil du hub.", "Go back to the hub's home tab."))
	btns.add_child(back_button)


## Contenu supplémentaire (panneau PARTIE provisoire).
func extra(_v: VBoxContainer) -> void:
	pass


func _content() -> String:
	var c: Array = CONTENT.get(tab_id, ["", ""])
	return Lang.t(c[0], c[1])


func first_focus() -> Control:
	return back_button
