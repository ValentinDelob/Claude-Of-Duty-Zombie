class_name Spawner
extends RefCounted
## Choix des points d'apparition des zombies (serveur).
##
## * Seuls les points des zones ACTIVES (ouvertes par les joueurs) servent.
## * On préfère les points à distance moyenne des joueurs et hors de leur vue :
##   les zombies arrivent « d'ailleurs », pas sous le nez du joueur. Un point
##   à moins de MIN_PLAYER_DIST est exclu, sauf derrière une fenêtre (BO1 :
##   le zombie apparaît dehors et vient à sa fenêtre, même si le joueur s'y
##   tient).
## * Fenêtre : au plus BarricadeRules.WINDOW_QUEUE_MAX zombies qui attendent
##   derrière elle ; au-delà, son point est sauté (le zombie reste à venir).
## * Recyclage : un zombie resté loin de tout joueur trop longtemps est retiré
##   et remis dans le quota de la manche (il réapparaîtra plus près).

const MIN_PLAYER_DIST := 7.0
const IDEAL_MIN := 9.0
const IDEAL_MAX := 26.0
const RECYCLE_DIST := 38.0
const RECYCLE_TIME := 18.0
## Distance (m, à plat) sous laquelle un point d'apparition est occupé.
const SPAWN_CLEARANCE := 0.8
## Même règle derrière une fenêtre : un zombie au contact (2 x Zombie.RADIUS).
const WINDOW_SPAWN_CLEARANCE := 0.6
## Filet de BO1 (round_spawn_failsafe) : moins de 24 pouces (0,6 m) en 30 s,
## 10 s de plus pour un rampant.
const FAILSAFE_TIME := 30.0
const FAILSAFE_CRAWLER_EXTRA := 10.0
const FAILSAFE_MOVE := 0.6

class SpawnPoint:
	var pos: Vector3
	var zone: String
	## Cellule d'origine (cartes grille seulement).
	var cell: Vector2i
	## Fenêtre devant laquelle ce point se trouve (dehors), ou null.
	var window: Barricade

var game: Game
var points: Array[SpawnPoint] = []
var active_zones: Dictionary = {"a": true}
## Délai avant recyclage (modifiable par les tests).
var recycle_time := RECYCLE_TIME
var _rng := RandomNumberGenerator.new()
## zid -> secondes passées loin de tout joueur
var _far_time: Dictionary = {}
## Filet : zid -> [position de référence, instant (GameClock) où il y était].
var _failsafe: Dictionary = {}
var _windows_resolved := false


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
	var taken := zombie_positions()
	_resolve_windows()
	for sp in candidates:
		# Derrière une fenêtre : au plus WINDOW_QUEUE_MAX zombies qui
		# attendent (une place chacun, BO1 : attack_spots) ; les suivants
		# attendent leur tour dans le quota de la manche.
		if sp.window and BarricadeRules.queue_full(sp.window.waiting_count()):
			continue
		# Un seul zombie à la fois par point (comme les points de sortie de
		# BO1) : deux zombies apparus au même endroit se superposent
		# exactement (non solides pendant l'émergence) et restent bloqués
		# l'un dans l'autre ensuite (aucune direction pour se séparer).
		# Derrière une fenêtre, le zombie de la place du milieu se tient à
		# 0,78 m du point : seul un zombie au contact (2 rayons) le bloque.
		if occupied(sp.pos, taken, WINDOW_SPAWN_CLEARANCE if sp.window else SPAWN_CLEARANCE):
			continue
		var nearest := INF
		var seen := false
		for p: Player in players:
			var d := p.global_position.distance_to(sp.pos)
			nearest = minf(nearest, d)
			if not seen and _in_view(p, sp.pos, d):
				seen = true
		# Distance mini pour les zombies qui sortent du sol seulement : comme
		# dans BO1, ceux d'une fenêtre apparaissent dehors et viennent à leur
		# fenêtre même si le joueur s'y tient (sinon, collé à la seule
		# fenêtre d'une petite salle, plus aucun zombie n'apparaissait).
		if nearest < MIN_PLAYER_DIST and not sp.window:
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
	@warning_ignore("incompatible_ternary")
	return best.pos if best else null


## Positions des zombies et chiens en vie (serveur).
func zombie_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for z: Zombie in game.zombies.alive:
		out.append(z.global_position)
	return out


## Règle pure : un zombie (même niveau) se tient-il sur ce point ?
static func occupied(pos: Vector3, taken: PackedVector3Array, clearance := SPAWN_CLEARANCE) -> bool:
	for q in taken:
		if absf(q.y - pos.y) < 1.0 and Vector2(q.x - pos.x, q.z - pos.z).length() < clearance:
			return true
	return false


## Rattache chaque point à sa fenêtre (une fois : les fenêtres sont
## construites après le Spawner).
func _resolve_windows() -> void:
	if _windows_resolved or game.barricades == null:
		return
	_windows_resolved = true
	for sp in points:
		sp.window = game.barricades.window_for_spawn(sp.pos)


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
	prune_far_time(_far_time, game.zombies.alive)
	var players: Array = _standing_players()
	if players.is_empty():
		return 0
	prune_far_time(_failsafe, game.zombies.alive)
	var now := GameClock.now()
	for z: Zombie in game.zombies.alive.duplicate():
		if z.state == Zombie.State.EMERGE:
			continue
		# Filet de BO1 (round_spawn_failsafe) : un zombie qui n'a pas bougé
		# de 60 cm en 30 s (40 s pour un rampant) est retiré et remis dans le
		# quota, même près des joueurs (coincé dans le décor à 10 m, il
		# bloquait la fin de la manche). Pas pendant qu'il arrache une planche,
		# enjambe une fenêtre ou frappe.
		if z.state in [Zombie.State.BARRIER, Zombie.State.VAULT, Zombie.State.ATTACK] or z.lured:
			_failsafe.erase(z.id)
		elif not _failsafe.has(z.id) or (_failsafe[z.id][0] as Vector3).distance_to(z.global_position) >= FAILSAFE_MOVE:
			_failsafe[z.id] = [z.global_position, now]
		elif failsafe_due(float(_failsafe[z.id][1]), now, z.is_crawler()):
			print("[Spawner] zombie %d immobile depuis %.0f s en %s : retiré (filet de BO1)" % [z.id, now - float(_failsafe[z.id][1]), z.global_position])
			_failsafe.erase(z.id)
			_far_time.erase(z.id)
			game.zombies.despawn(z.id)
			removed += 1
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


## Règle pure du filet : immobile depuis `since` (s de jeu), retiré à `now` ?
static func failsafe_due(since: float, now: float, crawler: bool) -> bool:
	return now - since >= FAILSAFE_TIME + (FAILSAFE_CRAWLER_EXTRA if crawler else 0.0)


## Oublie le temps passé loin des joueurs des zombies qui ne sont plus
## vivants (tués, retirés) : la table ne grossit plus toute la partie, et un
## futur zombie au même identifiant (recyclés après 65000) repart de zéro.
static func prune_far_time(far_time: Dictionary, alive: Array[Zombie]) -> void:
	if far_time.is_empty():
		return
	var ids := {}
	for z in alive:
		ids[z.id] = true
	for zid in far_time.keys():
		if not ids.has(zid):
			far_time.erase(zid)
