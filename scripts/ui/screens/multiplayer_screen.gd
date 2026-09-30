extends MenuScreen
## Choix du mode multijoueur.

func enter(_args := {}) -> void:
	var col := vbox(6)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -120
	add_child(col)
	col.add_child(title(Lang.t("MULTIJOUEUR", "MULTIPLAYER"), 48))
	col.add_child(text(Lang.t("Coopération de 2 à %d joueurs, par adresse IP.", "Co-op for 2 to %d players, over IP address.") % Net.MAX_SUPPORTED_PLAYERS, 18, UiStyle.DIM))
	col.add_child(text("", 10))
	var host := button(Lang.t("HÉBERGER UNE PARTIE", "HOST A GAME"), func(): menu.show_screen("host"), Lang.t("Ouvrir un salon : les autres vous rejoignent avec votre adresse IP.", "Open a lobby: the others join you with your IP address."))
	col.add_child(host)
	col.add_child(button(Lang.t("REJOINDRE UNE PARTIE", "JOIN A GAME"), func(): menu.show_screen("join"), Lang.t("Entrer l'adresse IP et le port de l'hôte.", "Enter the host's IP address and port.")))
	col.add_child(button(Lang.t("RETOUR", "BACK"), back))
	focus_later(host)


func back() -> void:
	menu.go_back()
