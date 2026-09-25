class_name Spawner
extends RefCounted
## Choix des points d'apparition des zombies (serveur).

const MIN_PLAYER_DIST := 6.0
const PREFERRED_MAX_DIST := 30.0

var game: Game
var points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _init(g: Game) -> void:
	game = g
	_rng.randomize()
	for c in g.map_data.markers.get("Z", []):
		points.append(MapData.cell_to_world(c))


## Point d'apparition : ni trop près ni trop loin des joueurs. null si aucun.
func pick_spawn_point() -> Variant:
	if points.is_empty():
		return null
	var good: Array[Vector3] = []
	for pt in points:
		var nearest := INF
		for p: Player in game.players.values():
			nearest = minf(nearest, p.global_position.distance_to(pt))
		if nearest >= MIN_PLAYER_DIST and nearest <= PREFERRED_MAX_DIST:
			good.append(pt)
	var pool := good if not good.is_empty() else points
	return pool[_rng.randi() % pool.size()]
