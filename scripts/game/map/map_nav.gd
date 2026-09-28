class_name MapNav
extends RefCounted
## Navigation des zombies (serveur) : grille (NavGrid) ou navmesh (MeshNav).


## Chemin de `from` à `to` (points au sol) ; vide si `to` est inaccessible.
func find_path(_from: Vector3, _to: Vector3) -> PackedVector3Array:
	return PackedVector3Array()


## Ligne de vue dégagée entre deux points au sol (murs, portes fermées, décor).
func world_line_clear(_from: Vector3, _to: Vector3) -> bool:
	return false
