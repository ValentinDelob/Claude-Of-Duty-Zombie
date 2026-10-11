class_name GameName
extends RefCounted
## Nom du jeu, en UN SEUL endroit du code (GAME_CONCEPT.md §6 et §7 : le nom
## définitif n'est pas encore choisi, il changera d'un coup). Le logo du menu
## titre (MenuLogo), les crédits, le journal de démarrage et le rapport de
## plantage le lisent ici.
##
## Pour renommer le jeu : changer NAME, puis `application/config/name` de
## project.godot et `application/product_name` d'export_presets.cfg
## (tests/test_game_name.gd vérifie que project.godot suit), le lanceur
## (launcher/) et les contrôles de tools/release.sh et tools/promote.sh, qui
## cherchent « <nom> v<build> » dans le journal du jeu.

const NAME := "Claude of Duty Zombie"


## Nom affiché en capitales (logo, crédits).
static func display() -> String:
	return NAME.to_upper()


## Mots du nom en capitales (mise en page du logo).
static func words() -> PackedStringArray:
	return display().split(" ", false)
