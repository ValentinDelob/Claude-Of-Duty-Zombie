class_name MapLayout
extends RefCounted
## Géométrie d'une carte, vue par les systèmes de jeu : zones, emplacements des
## objets, navigation des zombies et bloqueurs (portes fermées, fenêtres...).
##
## Deux implémentations : GridMapLayout (cartes ASCII actuelles, plates) et,
## pour les cartes en maillage à plusieurs niveaux, une implémentation 3D. Ce
## qui DÉCRIT la carte (nom, musique, ambiance, prix des portes, départs de la
## boîte...) reste dans MapDef.
##
## Positions en mètres, repère Godot ; les points renvoyés sont au niveau du sol.

var def: MapDef
## Navigation des zombies (serveur uniquement, null sur les clients) :
## find_path(from, to) -> PackedVector3Array, world_line_clear(from, to) -> bool.
var nav: MapNav


## Construit la navigation (serveur).
func create_nav() -> void:
	pass


## Construit la géométrie et le décor dans `world`. Retourne
## l'objet qui porte `power` (PowerGrid), `flicker` et `warmup_materials`.
func build(_world: Node3D) -> RefCounted:
	return null


## Zone (lettre ou identifiant) de la position, "" hors zone.
func zone_at(_pos: Vector3) -> String:
	return ""


## Zone ouverte au départ.
func start_zone() -> String:
	return "a"


## Bloque ou débloque la navigation d'un bloqueur nommé (MapMarker.block).
func set_blocked(_key: String, _blocked: bool) -> void:
	pass


## La position est-elle praticable (navigation, portes fermées comprises) ?
func is_walkable_at(_pos: Vector3) -> bool:
	return true


## Points de départ des joueurs (au sol).
func player_spawns() -> Array[Vector3]:
	return []


## Points d'apparition des zombies : [{pos, zone}].
func zombie_spawns() -> Array:
	return []


## Points dégagés où un chien de l'enfer peut apparaître (calculé une fois).
func open_floor_points() -> Array[Vector3]:
	return []


## Portes payantes : MapMarker (pos au sol au milieu de l'ouverture) avec
## data = {cost, width, height, depth, yaw, zones}, block = bloqueur de la porte.
func doors() -> Array[MapMarker]:
	return []


## Interrupteur du courant (null : courant présent dès le départ).
func power_switch() -> MapMarker:
	return null


## Emplacements de la caisse au hasard (ordre stable : index de
## MapDef.box_start). Le jeu n'en garde qu'un (Game._build_mystery_box).
func box_spots() -> Array[MapMarker]:
	return []


## Téléporteur : {pad: Vector3, exit: Vector3, mainframe: MapMarker ou null},
## vide si la carte n'en a pas.
func teleporter() -> Dictionary:
	return {}


## Zone d'arrivée du téléporteur ("" si aucune).
func teleporter_exit_zone() -> String:
	return ""


## Pièges : MapMarker du levier avec data = {area: AABB, cells: Array}.
func traps() -> Array[MapMarker]:
	return []


## Fenêtres barricadées (BarricadeLayout.Opening), ordre stable.
func windows() -> Array:
	return []


## Point de préchauffage des shaders (salle de départ).
func warm_point() -> Vector3:
	var s := player_spawns()
	return s[0] if not s.is_empty() else Vector3(2, 0, 2)


## Fin de construction (serveur) : cartes en maillage, cuisson du navmesh
## une fois la carte, les portes et les fenêtres en place.
func finish_nav(_world: Node3D) -> void:
	pass


## Carte à plusieurs niveaux (les zombies suivent le sol au lieu de rester à y = 0).
func is_multilevel() -> bool:
	return false


## Point au sol sous `pos` (cartes plates : y = 0 au plus bas).
func ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x, maxf(pos.y, 0.0), pos.z)


## Hauteur du sol sous `pos` (cartes plates : 0).
func floor_y(_pos: Vector3) -> float:
	return 0.0


## Orientation des joueurs à l'apparition (lacet ; PI : vers +z).
func player_spawn_yaw() -> float:
	return PI
