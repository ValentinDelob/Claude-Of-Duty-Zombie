class_name HubPlayStubPanel
extends HubPlaceholderPanel
## Onglet PARTIE provisoire (jusqu'au lot E, docs/HUB_PLAN.md §8) : lance une
## partie par le CHEMIN ACTUEL des menus — SOLO ouvre l'écran de sélection de
## carte (`map_select`), COOP l'écran MULTIJOUEUR (héberger / rejoindre, puis
## le salon `lobby`). Retour (Échap) depuis ces écrans : retour au hub.

var solo_button: HubButton
var coop_button: HubButton


func extra(v: VBoxContainer) -> void:
	v.add_child(HubBox.gap(0, 6))
	var row := HubBox.hbox(10)
	v.add_child(row)
	solo_button = hub_button("SOLO", _solo, HubButton.PRIMARY,
			Lang.t("Choisir une carte et lancer une partie seul.", "Pick a map and start a game alone."))
	solo_button.big = true
	solo_button.min_width = 180
	row.add_child(solo_button)
	coop_button = hub_button(Lang.t("COOP", "CO-OP"), _coop, HubButton.NORMAL,
			Lang.t("Coopération de 2 à %d survivants, par adresse IP : héberger ou rejoindre.",
				"Co-op for 2 to %d survivors, over IP address: host or join.") % Net.MAX_SUPPORTED_PLAYERS)
	coop_button.big = true
	coop_button.min_width = 180
	row.add_child(coop_button)


func _solo() -> void:
	if hub and hub.menu:
		hub.menu.show_screen("map_select")


func _coop() -> void:
	if hub and hub.menu:
		hub.menu.show_screen("multiplayer")


func first_focus() -> Control:
	return solo_button


func prompts() -> Array:
	return [[HubPrompts.ACCEPT, Lang.t("Lancer", "Start")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]
