class_name MenuScreen
extends Control
## Écran de menu (principal, héberger, salon, rejoindre...). Le MainMenu en
## affiche un seul à la fois et gère les transitions.

var menu: MenuHost


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

func title(label_text: String, font_size := 44) -> Label:
	return MenuStyle.title(label_text, font_size)


func text(t: String, font_size := 20, color := UiStyle.BONE) -> Label:
	return UiStyle.label(t, font_size, color)


## Bouton ; `hint` s'affiche en bas de l'écran quand il a le focus.
func button(label: String, cb: Callable, hint := "") -> Button:
	var b := MenuStyle.button(label, cb, hint)
	b.focus_entered.connect(func():
		if menu:
			menu.set_hint(hint))
	return b


## Donne le focus à `c` à l'image suivante, si l'écran est toujours affiché.
func focus_later(c: Control) -> void:
	(func():
		if is_instance_valid(c) and c.is_inside_tree() and c.focus_mode != Control.FOCUS_NONE \
				and menu != null and menu.current == self:
			c.grab_focus()).call_deferred()


func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v
