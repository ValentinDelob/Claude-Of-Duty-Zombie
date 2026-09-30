class_name MeshNav
extends MapNav
## Navigation des zombies sur une carte en maillage (serveur uniquement).
##
## Même interface que NavGrid pour les zombies, chiens et apparitions :
## find_path(from, to) (vide si la cible est inaccessible) et
## world_line_clear(from, to). Le navmesh est cuit au chargement à partir des
## collisions statiques (murs, sols, escaliers, portes fermées, fenêtres,
## décor) ; chaque porte payante est un passage (NavigationLink3D) activé à
## son ouverture : tant qu'elle est fermée, les deux côtés ne sont pas reliés.

const CELL_SIZE := 0.2
const CELL_HEIGHT := 0.1
## Au-delà de cette distance entre la fin du chemin et la cible, la cible est
## considérée comme inaccessible (porte fermée, autre île du navmesh).
const REACH_TOLERANCE := 0.8
## Hauteur des rayons de ligne de vue (poitrine).
const EYE := 1.1

var map: RID
var region: NavigationRegion3D
var links: Dictionary = {}  # bloqueur -> NavigationLink3D
var _world: Node3D
var _points: Array[Vector3] = []
## Recherche de chemin : paramètres et résultat réutilisés, mêmes réglages que
## map_get_path(map, from, to, true) (A*, entonnoir, couche 1), sans les
## métadonnées que map_get_path construit à chaque appel puis jette.
var _query := NavigationPathQueryParameters3D.new()
var _result := NavigationPathQueryResult3D.new()
## closest_point(to) par cible : toute la horde vise la même position du
## joueur pendant un pas. Vidé à chaque pas physique et dès que la carte de
## navigation change (nouvelle itération du serveur, porte, cuisson) :
## closest_point ne dépend que de la cible et de la carte.
var _goals := {}
var _goals_physics := -1
var _goals_iteration := -1
## Rayon de ligne de vue réutilisé (seuls les deux points changent).
var _los_q: PhysicsRayQueryParameters3D


func setup(world: Node3D) -> void:
	_world = world
	map = world.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	_query.map = map
	_query.navigation_layers = 1
	_query.pathfinding_algorithm = NavigationPathQueryParameters3D.PATHFINDING_ALGORITHM_ASTAR
	_query.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	_query.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_NONE
	region = NavigationRegion3D.new()
	region.name = "NavRegion"
	world.add_child(region)


## Cuit le navmesh d'après les collisions présentes sous `world` (appelé une
## fois la carte, les portes et les fenêtres construites).
func bake() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = CELL_SIZE
	nm.cell_height = CELL_HEIGHT
	nm.agent_radius = 0.4
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 42.0
	nm.region_min_size = 4.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | Barricade.BARRIER_LAYER
	var src := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(nm, src, _world)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	region.navigation_mesh = nm
	NavigationServer3D.map_force_update(map)
	_goals.clear()
	print("[MeshNav] navmesh cuit en %d ms (%d polygones)" % [Time.get_ticks_msec() - t0, nm.get_polygon_count()])


## Passage fermé à travers une porte : de `a` à `b` (au sol, de part et d'autre).
func add_link(key: String, a: Vector3, b: Vector3) -> void:
	var l := NavigationLink3D.new()
	l.name = "Link_" + key
	l.bidirectional = true
	l.start_position = a
	l.end_position = b
	l.enabled = false
	_world.add_child(l)
	links[key] = l
	_goals.clear()


func set_blocked(key: String, blocked: bool) -> void:
	var l: NavigationLink3D = links.get(key)
	if l:
		l.enabled = not blocked
		NavigationServer3D.map_force_update(map)
		_goals.clear()


func closest_point(pos: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, pos)


func is_walkable(pos: Vector3) -> bool:
	var c := closest_point(pos)
	return Vector2(c.x - pos.x, c.z - pos.z).length() < 0.5 and absf(c.y - pos.y) < 1.0


## Chemin (points au sol) ; vide si `to` n'est pas accessible depuis `from`.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var goal := goal_point(to)
	_query.start_position = from
	_query.target_position = goal
	NavigationServer3D.query_path(_query, _result)
	var path := _result.path
	if path.is_empty() or path[path.size() - 1].distance_to(goal) > REACH_TOLERANCE:
		return PackedVector3Array()
	return path


## closest_point(to), mis en cache tant que la carte de navigation est la
## même (numéro d'itération du serveur) et pour un seul pas physique.
func goal_point(to: Vector3) -> Vector3:
	var fp := Engine.get_physics_frames()
	var it := NavigationServer3D.map_get_iteration_id(map)
	if fp != _goals_physics or it != _goals_iteration:
		_goals_physics = fp
		_goals_iteration = it
		_goals.clear()
	var g: Variant = _goals.get(to)
	if g == null:
		g = closest_point(to)
		_goals[to] = g
	return g


## Ligne de vue dégagée à hauteur de poitrine (murs, portes, fenêtres, décor).
func world_line_clear(from: Vector3, to: Vector3) -> bool:
	if _los_q == null:
		_los_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.UP, 1 | Barricade.BARRIER_LAYER)
	_los_q.from = from + Vector3.UP * EYE
	_los_q.to = to + Vector3.UP * EYE
	return _world.get_world_3d().direct_space_state.intersect_ray(_los_q).is_empty()


## Points du navmesh tirés au hasard (apparitions des chiens), dégagés.
func random_points(n: int) -> Array[Vector3]:
	if _points.is_empty():
		for i in n:
			var p := NavigationServer3D.map_get_random_point(map, 1, true)
			if is_walkable(p):
				_points.append(p)
	return _points
