class_name MenuHost
extends Control
## Hôte d'écrans de menu (MenuScreen) : le menu principal (MainMenu) et le
## menu pause de la partie (PauseMenu), qui réutilise l'écran d'options.
## Les écrans ne parlent qu'à cette interface ; chaque hôte la surcharge.

var current: MenuScreen
var current_name := ""


## Affiche l'écran `screen_name` (voir MainMenu.SCREENS).
func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
	pass


## Revient à l'écran précédent.
func go_back() -> void:
	pass


## Texte d'aide en bas de l'écran (description de l'élément sélectionné).
func set_hint(_t: String) -> void:
	pass


## Lancement d'une partie (fondu cinématique dans le menu principal).
func launch(then: Callable, _duration := 1.8) -> void:
	then.call()


## Fondu au noir puis `then`.
func fade_to_black(_duration: float, then: Callable) -> void:
	then.call()
