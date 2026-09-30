extends MenuScreen
## Écran principal : SOLO (sélection de carte) / MULTIJOUEUR / OPTIONS / DOSSIER DE COMBAT / CRÉDITS /
## QUITTER.

var _first: Button
var _col: VBoxContainer
var logo: MenuLogo


func enter(_args := {}) -> void:
	_col = vbox(2)
	_col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_col.offset_left = 84
	_col.offset_top = -342
	add_child(_col)
	logo = MenuLogo.new()
	_col.add_child(logo)
	_col.add_child(text("", 4))
	_first = button("SOLO", _solo, Lang.t("Survivre seul face aux hordes. Combien de manches tiendrez-vous ?", "Survive the hordes alone. How many rounds can you last?"))
	_col.add_child(_first)
	_col.add_child(button(Lang.t("MULTIJOUEUR", "MULTIPLAYER"), func(): menu.show_screen("multiplayer"), Lang.t("Coopération de 2 à %d survivants, par adresse IP.", "Co-op for 2 to %d survivors, over IP address.") % Net.MAX_SUPPORTED_PLAYERS))
	_col.add_child(button("OPTIONS", func(): menu.show_screen("options"), Lang.t("Commandes, affichage, son.", "Controls, display, sound.")))
	_col.add_child(button(Lang.t("DOSSIER DE COMBAT", "COMBAT RECORD"), func(): menu.show_screen("career"), Lang.t("Vos statistiques de survie, partie après partie.", "Your survival stats, game after game.")))
	_col.add_child(button(Lang.t("CRÉDITS", "CREDITS"), func(): menu.show_screen("credits"), Lang.t("Ceux qui ont bâti ce bunker.", "The ones who built this bunker.")))
	_col.add_child(button(Lang.t("ÉDITEUR DE CARTES", "MAP EDITOR"), _editor, Lang.t("Dessinez vos propres cartes et jouez-les aussitôt.", "Draw your own maps and play them right away.")))
	_col.add_child(button(Lang.t("QUITTER", "QUIT"), _quit, Lang.t("Retour à la surface.", "Back to the surface.")))
	focus_later(_first)


## SOLO : choix de la carte d'abord (comme Black Ops), qui lance la partie.
func _solo() -> void:
	if not _leaving:
		menu.show_screen("map_select")


## ÉDITEUR DE CARTES : scène de l'éditeur (docs/MAP_AUTHORING.md).
func _editor() -> void:
	if _lock():
		menu.fade_to_black(0.4, func(): get_tree().change_scene_to_file(MapEditor.SCENE))


func _quit() -> void:
	if _lock():
		menu.fade_to_black(0.6, Router.quit_game)


var _leaving := false


## Plus aucune action possible pendant le fondu final. Faux si déjà verrouillé.
func _lock() -> bool:
	if _leaving:
		return false
	_leaving = true
	for c in _col.get_children():
		if c is Button:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not c.has_focus():
				c.disabled = true
	return true


func back() -> void:
	pass
