extends MenuScreen
## Choix du mode multijoueur.

func enter(_args := {}) -> void:
	var col := vbox(6)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -120
	add_child(col)
	col.add_child(title("MULTIJOUEUR", 48))
	col.add_child(text("Coopération de 2 à %d joueurs, par adresse IP." % Net.MAX_SUPPORTED_PLAYERS, 18, UiStyle.DIM))
	col.add_child(text("", 10))
	var host := button("HÉBERGER UNE PARTIE", func(): menu.show_screen("host"))
	col.add_child(host)
	if menu.SCREENS.has("join"):
		col.add_child(button("REJOINDRE UNE PARTIE", func(): menu.show_screen("join")))
	col.add_child(button("RETOUR", back))
	host.grab_focus.call_deferred()


func back() -> void:
	menu.go_back()
