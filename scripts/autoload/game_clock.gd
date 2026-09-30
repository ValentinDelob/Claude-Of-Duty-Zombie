extends Node
## Horloge de jeu : temps simulé (somme des pas de physique), et non l'heure
## murale. Tous les minuteurs de gameplay (cadence de tir, rechargements,
## réanimation, mèches, répliques…) la lisent :
##   - la pause solo les fige (l'arbre en pause n'avance plus la physique) ;
##   - une image bloquée ne fait pas « sauter » un rechargement ;
##   - les tests accélérés (--fixed-fps) avancent au rythme de la simulation.
## L'interpolation réseau reste en temps réel (arrivée des paquets).
## Premier autoload : son _physics_process passe avant celui des nœuds du jeu.

var _t := 0.0


func _physics_process(delta: float) -> void:
	_t += delta


## Secondes de jeu écoulées. Dans une image de rendu (entre deux pas de
## physique), ajoute la fraction du pas en cours pour rester fluide.
func now() -> float:
	if Engine.is_in_physics_frame():
		return _t
	return _t + Engine.get_physics_interpolation_fraction() * Engine.time_scale / Engine.physics_ticks_per_second


## Millisecondes de jeu écoulées (entier), pour les calculs en ms.
func msec() -> int:
	return int(now() * 1000.0)
