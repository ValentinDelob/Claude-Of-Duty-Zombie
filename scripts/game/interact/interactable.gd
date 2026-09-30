class_name Interactable
extends Node3D
## Base de tout objet avec lequel on interagit ([F]) : portes, achats muraux,
## atouts, boîte mystère, Pack-a-Punch, pièges, courant, téléporteur...
##
## * Côté client : prompt(), can_interact() pour l'affichage.
## * Côté serveur : srv_use() valide et applique (points, état).
## * L'état est répliqué par InteractionSystem (get_state / apply_state).

## Identifiant stable, identique sur toutes les machines (ex. "door_1").
var interact_id := ""
var interact_range := 2.2
## Durée de maintien de [F] requise (0 = appui simple).
var hold_time := 0.0
var system: InteractionSystem


## Point de référence pour la distance et la visée.
func interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.1


## Texte affiché au joueur local (vide = rien à faire ici).
func prompt(_pid: int) -> String:
	return ""


func can_interact(pid: int) -> bool:
	return prompt(pid) != ""


## Serveur : le joueur `pid` utilise l'objet (distance déjà validée).
func srv_use(_pid: int) -> void:
	pass


## Serveur : le joueur relâche [F] (objets à maintien).
func srv_release(_pid: int) -> void:
	pass


func get_state() -> Dictionary:
	return {}


## Toutes les machines : applique un état reçu du serveur.
func apply_state(_state: Dictionary, _animate: bool) -> void:
	pass


## Serveur : diffuse l'état courant à tout le monde.
func broadcast_state() -> void:
	if system:
		system.broadcast(self)


static func cost_text(cost: int) -> String:
	return "[%d]" % cost


## Invite commune des objets qui attendent le courant.
static func need_power_text() -> String:
	return Lang.t("Le courant doit être rétabli", "Power must be activated first")
