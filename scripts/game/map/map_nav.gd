class_name MapNav
extends RefCounted
## Navigation des zombies (serveur) : grille (NavGrid) ou navmesh (MeshNav).


## Chemin de `from` à `to` (points au sol) ; vide si `to` est inaccessible.
## `lane_bias` (-1 à 1) : écart latéral de l'agent sur les couloirs d'ancres
## des escaliers (MeshNav ; ignoré sur une grille, sans escalier).
func find_path(_from: Vector3, _to: Vector3, _lane_bias := 0.0) -> PackedVector3Array:
	return PackedVector3Array()


## Ligne de vue dégagée entre deux points au sol (murs, portes fermées, décor).
func world_line_clear(_from: Vector3, _to: Vector3) -> bool:
	return false


## Ligne de vue des yeux seule : on voit par-dessus les obstacles bas qui
## barrent la ligne droite. Par défaut, la même que world_line_clear.
func eye_line_clear(from: Vector3, to: Vector3) -> bool:
	return world_line_clear(from, to)


## Escalier de chaque point du dernier chemin rendu par find_path (0 : aucun,
## k + 1 : couloir d'ancres k). Vide : aucun point sur un escalier.
func last_lane_marks() -> PackedByteArray:
	return PackedByteArray()


## Le segment à plat de `a` à `b` passe-t-il sur (ou contre) un escalier ? La
## poursuite en ligne droite est alors interdite : le chemin passe par ses ancres.
func crosses_stairs(_a: Vector3, _b: Vector3) -> bool:
	return false


## Poussée (x, z) qui ramène un agent sorti de la largeur permise du couloir
## d'ancres `mark` (last_lane_marks) ; ZERO sinon.
func lane_push(_mark: int, _pos: Vector3) -> Vector3:
	return Vector3.ZERO


## Reste à parcourir (m) sur le couloir d'ancres `mark`, de `pos` jusqu'au
## point `exit` du même couloir (écart d'abscisse, plus la distance de `pos`
## à l'axe) : une même mesure pour toute la horde qui le prend dans ce sens.
## INF : pas de couloir.
func lane_left(_mark: int, _pos: Vector3, _exit: Vector3) -> float:
	return INF
