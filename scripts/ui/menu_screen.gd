class_name MenuScreen
extends Control
## Écran de menu (principal, héberger, salon, rejoindre...). Le MainMenu en
## affiche un seul à la fois et gère les transitions.

var menu: MainMenu


## Appelé à l'affichage de l'écran.
func enter(_args := {}) -> void:
	pass


## Appelé quand l'écran est quitté.
func exit() -> void:
	pass


## Retour arrière (Échap).
func back() -> void:
	pass


# --------------------------------------------------------------------------
# Construction rapide de widgets (le style est centralisé dans MenuStyle)
# --------------------------------------------------------------------------

func title(text: String, size := 44) -> Label:
	return MenuStyle.title(text, size)


func text(t: String, size := 20, color := UiStyle.BONE) -> Label:
	return UiStyle.label(t, size, color)


func button(label: String, cb: Callable) -> Button:
	return MenuStyle.button(label, cb)


func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v
