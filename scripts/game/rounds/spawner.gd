class_name Spawner
extends RefCounted
## Choix des points d'apparition des zombies (serveur).
##
## * Seuls les points des zones ACTIVES (ouvertes par les joueurs) servent.
## * On préfère les points à distance moyenne des joueurs et hors de leur vue :
##   les zombies arrivent « d'ailleurs », pas sous le nez du joueur.
## * Recyclage : un zombie resté loin de tout joueur trop longtemps est retiré
##   et remis dans le quota de la manche (il réapparaîtra plus près).

const MIN_PLAYER_DIST := 7.0
const IDEAL_MIN := 9.0
const IDEAL_MAX := 26.0
const RECYCLE_DIST := 38.0
const RECYCLE_TIME := 18.0

class SpawnPoint:
	var pos: Vector3
	var zone: String
	## Cellule d'origine (cartes grille seulement).
	var cell: Vector2i

var game: Game
var points: Array[SpawnPoint] = []
var active_zones: Dictionary = {"a": true}
## Délai avant recyclage (modifiable par les tests).
var recycle_time := RECYCLE_TIME
var _rng := RandomNumberGenerator.new()
## zid -> secondes passées loin de tout joueur
var _far_time: Dictionary = {}


func _init(g: Game) -> void:
	game = g
	_rng.randomize()
	active_zones = {g.layout.start_zone(): true}
	# Zones ouvertes sans porte sur la zone de départ (ex. mezzanine).
	for linked in g.map_def.open_links.get(g.layout.start_zone(), []):
		active_zones[linked] = true
	for s in g.layout.zombie_spawns():
		var sp := SpawnPoint.new()
		sp.cell = s.get("cell", Vector2i(-1, -1))
		sp.pos = s.pos
		sp.zone = s.zone
		points.append(sp)


func activate_zone(zone: String) -> void:
	if zone != "" and not active_zones.has(zone):
		active_zones[zone] = true
		print("[Spawner] zone « %s » active" % zone)


func active_points() -> Array[SpawnPoint]:
	var out: Array[SpawnPoint] = []
	for sp in points:
		if active_zones.has(sp.zone):
			out.append(sp)
	return out


## Point d'apparition (Vector3) ou null si aucun n'est utilisable.
func pick_spawn_point() -> Variant:
	var candidates := active_points()
	if candidates.is_empty():
		return null
	var players: Array = _standing_players()
	if players.is_empty():
		players = game.players.values()
	var best_score := -INF
	var best: SpawnPoint = null
	for sp in candidates:
		var nearest := INF
		var seen := false
		for p: Player in players:
			var d := p.global_position.distance_to(sp.pos)
			nearest = minf(nearest, d)
			if not seen and _in_view(p, sp.pos, d):
				seen = true
		if nearest < MIN_PLAYER_DIST:
			continue
		var score := 0.0
		if nearest >= IDEAL_MIN and nearest <= IDEAL_MAX:
			score += 10.0
		else:
			score -= absf(nearest - clampf(nearest, IDEAL_MIN, IDEAL_MAX)) * 0.4
		if seen:
			score -= 6.0
		score += _rng.randf() * 5.0
		if score > best_score:
			best_score = score
			best = sp
	return best.pos if best else null


func _standing_players() -> Array:
	var out := []
	for p: Player in game.players.values():
		var pd := game.session.get_data(p.peer_id)
		if pd and pd.life == PlayerData.Life.ALIVE:
			out.append(p)
	return out


## Le joueur voit-il ce point ? (devant lui et ligne de vue dégagée au sol)
func _in_view(p: Player, pos: Vector3, dist: float) -> bool:
	if dist > 40.0:
		return false
	var fwd := -p.global_transform.basis.z
	var to := (pos - p.global_position)
	to.y = 0.0
	if fwd.dot(to.normalized()) < 0.35:
		return false
	return game.nav.world_line_clear(p.global_position, pos)


## Serveur, appelé régulièrement : recycle les zombies égarés. Retourne le
## nombre de zombies retirés (à remettre dans le quota de la manche).
func recycle(delta: float) -> int:
	var removed := 0
	var players: Array = _standing_players()
	if players.is_empty():
		return 0
	for z: Zombie in game.zombies.alive.duplicate():
		if z.state == Zombie.State.EMERGE:
			continue
		var nearest := INF
		for p: Player in players:
			nearest = minf(nearest, p.global_position.distance_to(z.global_position))
		if nearest > RECYCLE_DIST or (nearest > 16.0 and z.stuck_time() > 6.0):
			_far_time[z.id] = _far_time.get(z.id, 0.0) + delta
		else:
			_far_time.erase(z.id)
		if _far_time.get(z.id, 0.0) >= recycle_time:
			_far_time.erase(z.id)
			game.zombies.despawn(z.id)
			removed += 1
	return removed
