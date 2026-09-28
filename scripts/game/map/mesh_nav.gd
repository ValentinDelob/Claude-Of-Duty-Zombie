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


func setup(world: Node3D) -> void:
	_world = world
	map = world.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
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


func set_blocked(key: String, blocked: bool) -> void:
	var l: NavigationLink3D = links.get(key)
	if l:
		l.enabled = not blocked
		NavigationServer3D.map_force_update(map)


func closest_point(pos: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, pos)


func is_walkable(pos: Vector3) -> bool:
	var c := closest_point(pos)
	return Vector2(c.x - pos.x, c.z - pos.z).length() < 0.5 and absf(c.y - pos.y) < 1.0


## Chemin (points au sol) ; vide si `to` n'est pas accessible depuis `from`.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var goal := closest_point(to)
	var path := NavigationServer3D.map_get_path(map, from, goal, true)
	if path.is_empty() or path[path.size() - 1].distance_to(goal) > REACH_TOLERANCE:
		return PackedVector3Array()
	return path


## Ligne de vue dégagée à hauteur de poitrine (murs, portes, fenêtres, décor).
func world_line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * EYE, to + Vector3.UP * EYE, 1 | Barricade.BARRIER_LAYER)
	return _world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Points du navmesh tirés au hasard (apparitions des chiens), dégagés.
func random_points(n: int) -> Array[Vector3]:
	if _points.is_empty():
		for i in n:
			var p := NavigationServer3D.map_get_random_point(map, 1, true)
			if is_walkable(p):
				_points.append(p)
	return _points
