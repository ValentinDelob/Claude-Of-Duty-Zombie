class_name Interactable
extends Node3D
## Base de tout objet avec lequel on interagit ([F]) : portes, caisse au
## hasard, pièges, courant, téléporteur, barricades...
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
## Hauteur (m) du nœud au-dessus du sol de son niveau : 0 pour un objet posé au
## sol (porte, caisse, machines) ; un objet mural est accroché plus haut.
var mount_height := 0.0
## Collisions propres (own_rids), gardées.
var _own_rid_cache: Array[RID] = []


## Altitude du sol de l'objet : on ne l'utilise que depuis ce niveau
## (InteractionSystem.same_level), jamais depuis le niveau du dessous ou du dessus.
func level_y() -> float:
	return global_position.y - mount_height


## Point de référence pour la distance et la visée.
func interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.1


## Serveur : point utilisé pour la distance d'interaction. Objet fixe : son
## interact_point() ; objet porté par un joueur (ReviveTarget) : calculé sur
## la position de référence de ce joueur (Player.srv_origin).
func srv_point() -> Vector3:
	return interact_point()


## Texte affiché au joueur local (vide = rien à faire ici).
func prompt(_pid: int) -> String:
	return ""


func can_interact(pid: int) -> bool:
	return prompt(pid) != ""


## Collisions propres de l'objet (porte, machine...), exclues des rayons de
## ligne de vue vers lui (InteractionSystem.stair_sight_ok). Liste gardée :
## construite au premier appel (pas de parcours de l'arbre à chaque image).
func own_rids() -> Array[RID]:
	if _own_rid_cache.is_empty():
		for n in find_children("*", "CollisionObject3D", true, false):
			_own_rid_cache.append((n as CollisionObject3D).get_rid())
	return _own_rid_cache


## Utilisable depuis l'œil `eye` (ligne de vue) ? Par défaut oui ; la boîte
## mystère vérifie qu'aucun mur n'est entre le joueur et elle (MysteryBox).
func sight_ok(_eye: Vector3) -> bool:
	return true


## Serveur : le joueur `pid` utilise l'objet (distance déjà validée).
func srv_use(_pid: int) -> void:
	pass


## Client : renvoyer la demande tant que [F] reste maintenu sur l'objet ?
## Seulement pour un srv_use idempotent (rien à payer, rien à rejouer).
func resend_while_held() -> bool:
	return false


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
