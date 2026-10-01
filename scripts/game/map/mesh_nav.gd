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
##
## Escaliers (StairGen, StairLane) : chaque escalier de la carte a un couloir
## d'ancres. Un chemin du navmesh qui l'emprunte est réécrit : chemin jusqu'à
## l'ancre du bout où l'on arrive, points du couloir à l'écart latéral de
## l'agent (`lane_bias`), puis chemin depuis l'ancre de l'autre bout (dans les
## deux sens). Les zombies montent et descendent ainsi par l'axe des volées,
## jamais en frôlant un bord, un garde-corps ou l'angle d'un palier.

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
## Couloirs d'ancres des escaliers (set_stairs, après la cuisson).
var lanes: Array[StairLane] = []
## Escalier de chaque point du dernier chemin (last_lane_marks).
var _marks := PackedByteArray()
## Requête des morceaux de chemin vers et depuis les ancres.
var _sub_query := NavigationPathQueryParameters3D.new()
var _sub_result := NavigationPathQueryResult3D.new()
## Chemins depuis une ancre vers une cible (toute la horde vers le même
## joueur), gardés un pas physique et tant que la carte de navigation est la même.
var _tails := {}
## Pas d'échantillonnage d'un chemin pour reconnaître un escalier emprunté.
const LANE_SAMPLE := 0.25
## Distance maximale entre une ancre et le navmesh pour qu'elle serve.
const ANCHOR_SNAP := 0.6


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
	_sub_query.map = map
	_sub_query.navigation_layers = 1
	_sub_query.pathfinding_algorithm = _query.pathfinding_algorithm
	_sub_query.path_postprocessing = _query.path_postprocessing
	_sub_query.metadata_flags = _query.metadata_flags
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
		for sl in lanes:
			if sl.doors.has(key):
				_refresh_stair_link(sl)
		NavigationServer3D.map_force_update(map)
		_goals.clear()


func closest_point(pos: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, pos)


func is_walkable(pos: Vector3) -> bool:
	var c := closest_point(pos)
	return Vector2(c.x - pos.x, c.z - pos.z).length() < 0.5 and absf(c.y - pos.y) < 1.0


## Chemin (points au sol) ; vide si `to` n'est pas accessible depuis `from`.
## `lane_bias` (-1 à 1) : écart latéral de l'agent sur les couloirs d'ancres.
func find_path(from: Vector3, to: Vector3, lane_bias := 0.0) -> PackedVector3Array:
	_marks = PackedByteArray()
	var goal := goal_point(to)
	_query.start_position = from
	_query.target_position = goal
	NavigationServer3D.query_path(_query, _result)
	var path := _result.path
	if path.is_empty() or path[path.size() - 1].distance_to(goal) > REACH_TOLERANCE:
		return PackedVector3Array()
	if lanes.is_empty() or not ensure_anchors():
		return path
	var marks := PackedByteArray()
	marks.resize(path.size())
	var res := _thread_lanes(path, marks, goal, lane_bias, 0)
	_marks = res[1]
	return res[0]


func last_lane_marks() -> PackedByteArray:
	return _marks


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


# ------------------------------------------------------------------ escaliers

## Couloirs d'ancres des escaliers de la carte (entrées « stairs » de la
## description). Chaque ancre est posée sur le navmesh (devant le pied ou
## au-delà du haut, décalée le long du bord si le décor en masque le milieu) ;
## un escalier dont un bout n'a aucune place libre est signalé et laissé au
## navmesh seul.
func set_stairs(stairs: Array) -> void:
	lanes.clear()
	_tails.clear()
	_plans.clear()
	_anchored = false
	for i in stairs.size():
		var st: Dictionary = stairs[i]
		var pl := StairGen.plan(st)
		lanes.append(StairLane.from_plan(pl, i, "%s %s" % [String(st.get("room", "?")), StairGen.kind_of(st)]))
		_plans.append(pl)


## Plans des escaliers, gardés pour poser les ancres (ensure_anchors).
var _plans: Array = []
var _anchored := false


## Ancres posées sur le navmesh dès que le serveur de navigation a synchronisé
## la carte cuite (la synchronisation est asynchrone : avant, aucun point du
## navmesh n'est connu). Rend false tant que ce n'est pas fait.
func ensure_anchors() -> bool:
	if _anchored:
		return true
	if lanes.is_empty() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	if NavigationServer3D.map_get_closest_point(map, lanes[0].pts[0]) == Vector3.ZERO and lanes[0].pts[0] != Vector3.ZERO:
		return false
	_anchored = true
	for l in lanes:
		var pl: Dictionary = _plans[l.index]
		_anchor_end(l, pl, 0)
		_anchor_end(l, pl, 1)
		l._finish()
		if not l.ok:
			print("[MeshNav] escalier %d (%s) : %s ; couloir d'ancres désactivé" % [l.index, l.name, l.problem])
			continue
		# Passage seulement si le navmesh ne relie pas déjà les deux ancres par
		# les marches (escalier trop étroit, rogné) : ailleurs, les chemins
		# restent ceux du navmesh, réécrits par le couloir.
		var walk := _path_len_plain(_sub_path(l.pts[0], l.pts[l.pts.size() - 1]))
		if walk > l.length() * 2.0 + 4.0:
			_add_stair_link(l)
	NavigationServer3D.map_force_update(map)
	return true


static func _path_len_plain(p: PackedVector3Array) -> float:
	if p.is_empty():
		return INF
	var total := 0.0
	for i in p.size() - 1:
		total += p[i].distance_to(p[i + 1])
	return total


## Passage du navmesh (NavigationLink3D) d'une ancre à l'autre : l'escalier
## relie toujours ses deux sols, même quand le navmesh, rogné du rayon de
## l'agent, est trop mince sur ses marches (escalier de service d'un mètre).
## Une porte payante sur le couloir (haut des marches contre une porte de
## KINO) le coupe tant qu'elle est fermée : jamais de raccourci par une porte.
func _add_stair_link(l: StairLane) -> void:
	for key in links:
		var dl: NavigationLink3D = links[key]
		# Plan de la porte : en travers de son passage (de part et d'autre).
		var s2 := Vector2(dl.start_position.x, dl.start_position.z)
		var e2 := Vector2(dl.end_position.x, dl.end_position.z)
		var dn := (e2 - s2).normalized()
		var dt := Vector2(-dn.y, dn.x) * 1.6
		var da := (s2 + e2) * 0.5 - dt
		var db := (s2 + e2) * 0.5 + dt
		var dy := (dl.start_position.y + dl.end_position.y) * 0.5
		for i in l.pts.size() - 1:
			var pa := l.pts[i]
			var pb := l.pts[i + 1]
			if dy < minf(pa.y, pb.y) - 1.2 or dy > maxf(pa.y, pb.y) + 1.2:
				continue
			if Geometry2D.segment_intersects_segment(da, db, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)) != null:
				l.doors.append(String(key))
				break
	var sl := NavigationLink3D.new()
	sl.name = "StairLink_%d" % l.index
	sl.bidirectional = true
	sl.start_position = l.pts[0]
	sl.end_position = l.pts[l.pts.size() - 1]
	# Coût du passage = longueur du couloir (pas la ligne droite d'une ancre à
	# l'autre) : depuis le milieu des marches, on ne remonte pas le prendre.
	sl.travel_cost = maxf(1.0, l.length() / maxf(sl.start_position.distance_to(sl.end_position), 0.1)) * 1.05
	_world.add_child(sl)
	l.link = sl
	_refresh_stair_link(l)


func _refresh_stair_link(l: StairLane) -> void:
	if l.link == null:
		return
	var open := true
	for key in l.doors:
		var dl: NavigationLink3D = links.get(key)
		if dl and not dl.enabled:
			open = false
	l.link.enabled = open


## Place l'ancre du bout `end` (0 : pied, 1 : haut) sur le navmesh.
func _anchor_end(l: StairLane, pl: Dictionary, end: int) -> void:
	var edge: Dictionary = pl.foot if end == 0 else pl.exit
	var i := 0 if end == 0 else l.pts.size() - 1
	var nominal := l.pts[i]
	var n: Vector2 = edge.n
	var t := Vector2(-n.y, n.x)
	var m: Vector2 = edge.m
	var reach := maxf(float(edge.h) - StairGen.AGENT_RADIUS - 0.1, 0.0)
	var best := Vector3.INF
	for gap: float in [StairGen.ENTRY_GAP if end == 0 else StairGen.EXIT_GAP, 0.55, 1.2, 1.6]:
		for k: float in [0.0, 0.33, -0.33, 0.66, -0.66, 1.0, -1.0]:
			var q := m + n * gap + t * (k * reach)
			var cand := Vector3(q.x, nominal.y, q.y)
			var c := closest_point(cand)
			if Vector2(c.x - cand.x, c.z - cand.z).length() < 0.15 and absf(c.y - cand.y) < 0.4:
				best = Vector3(cand.x, c.y, cand.z)
				break
		if best != Vector3.INF:
			break
	if best == Vector3.INF:
		var c := closest_point(nominal)
		if Vector2(c.x - nominal.x, c.z - nominal.z).length() < ANCHOR_SNAP and absf(c.y - nominal.y) < 0.4:
			best = c
	if best == Vector3.INF:
		l.ok = false
		l.problem += ("pied %s sans sol libre devant (navmesh le plus proche : %s) ; " if end == 0 else "haut %s sans sol libre au-delà (navmesh le plus proche : %s) ; ") \
			% [str(nominal), str(closest_point(nominal))]
		return
	l.pts[i] = best
	var dl := (Vector2(best.x, best.z) - m).dot(t)
	if absf(dl) > 0.2:
		# Ancre décalée (le décor masque le milieu du pied, comme les rangées de
		# fauteuils devant les marches de la scène de KINO) : on entre dans les
		# marches en face d'elle, sans écart, puis on rejoint l'axe.
		var j := 1 if end == 0 else l.pts.size() - 2
		var q := m + t * dl
		l.pts[j] = Vector3(q.x, l.pts[j].y, q.y)
		l.half[i] = 0.0
		l.half[j] = minf(l.half[j], 0.15)
		# Puis droit dans les marches, en face de l'ancre, avant de rejoindre
		# l'axe : pas de biais au ras du pied, contre le décor qui le masque.
		# Les points de la volée droite qui part de ce bord passent en face de
		# l'ancre ; s'il n'y en a pas, un point est ajouté à 0,8 m.
		var step := 1 if end == 0 else -1
		var k := j + step
		var moved := false
		var prev2 := m
		while k > 0 and k < l.pts.size() - 1:
			var pk := Vector2(l.pts[k].x, l.pts[k].z)
			var along := (pk - m).dot(-n)
			# Toute la volée droite qui part de ce bord (pas au-delà d'un virage).
			var seg := pk - prev2
			if seg.length() > 0.01 and seg.normalized().dot(-n) < 0.98:
				break
			prev2 = pk
			var nq := m - n * along + t * dl
			l.pts[k] = Vector3(nq.x, l.pts[k].y, nq.y)
			l.half[k] = minf(l.half[k], 0.15)
			moved = true
			k += step
		if not moved:
			var k2 := j + step
			var into := q - n * 0.8
			var far := Vector2(l.pts[k2].x, l.pts[k2].z)
			var y := lerpf(l.pts[j].y, l.pts[k2].y, clampf(0.8 / maxf((far - m).dot(-n), 0.8), 0.0, 1.0))
			var at := 2 if end == 0 else l.pts.size() - 2
			l.pts.insert(at, Vector3(into.x, y, into.y))
			l.half.insert(at, 0.15)


## Réécrit `path` autour du premier escalier emprunté (puis, récursivement,
## des suivants sur les morceaux d'avant et d'après).
func _thread_lanes(path: PackedVector3Array, marks: PackedByteArray, goal: Vector3, bias: float, depth: int) -> Array:
	if depth > 3 or path.size() < 2:
		return [path, marks]
	var from_seg := 0
	while from_seg < path.size() - 1:
		var hit := _first_lane(path, from_seg)
		if hit.is_empty():
			return [path, marks]
		var l: StairLane = hit.lane
		var start_in: bool = hit.start_in
		var end_in: bool = hit.end_in
		# Déjà engagé entre l'ancre et les marches : on continue d'où l'on est.
		if not start_in and from_seg == 0 and not l.engaged(path[0]).is_empty():
			start_in = true
		if not end_in and not l.engaged(goal).is_empty():
			end_in = true
		if not start_in and not end_in and l.end_of(hit.enter) == l.end_of(hit.leave):
			from_seg = int(hit.leave_seg) + 1   # frôle un bout sans le traverser
			continue
		var S := l.length()
		var s_from: float = float(l.project(path[0])[0]) if start_in else (0.0 if l.end_of(hit.enter) == 0 else S)
		var s_to: float = float(l.project(goal)[0]) if end_in else (S if l.end_of(hit.leave) == 1 else 0.0)
		if start_in and not end_in:
			# Sur les marches : le bout le plus court jusqu'à la cible (couloir
			# puis chemin depuis l'ancre), pas celui que le navmesh, rogné sur
			# des marches étroites, aurait pris en remontant chercher le passage.
			var down := s_from + _path_len(_tail(l, 0, goal), l)
			var upw := (S - s_from) + _path_len(_tail(l, l.pts.size() - 1, goal), l)
			if down < INF or upw < INF:
				s_to = 0.0 if down <= upw else S
			# Au ras du pied (ou du haut), et l'on repart de ce même côté : le
			# chemin longe l'escalier sans le prendre (bande devant les marches
			# de la scène de KINO), on le laisse au navmesh.
			var foot_s := l.cum[1]
			var top_s := l.cum[l.cum.size() - 2]
			if (s_to == 0.0 and s_from <= foot_s + 0.5) or (s_to == S and s_from >= top_s - 0.5):
				from_seg = int(hit.leave_seg) + 1
				continue
		if absf(s_to - s_from) < 0.3:
			from_seg = int(hit.leave_seg) + 1
			continue
		# Après les marches, le chemin depuis l'ancre reviendrait sur l'escalier
		# (il longe son pied, comme la bande devant les marches de la scène de
		# KINO, au ras des fauteuils) : ce passage reste au navmesh, qui y suit
		# la bande au plus près ; l'ancre y ferait un détour contre le décor.
		var to_end := not end_in
		var raw_tail := PackedVector3Array()
		if not end_in:
			raw_tail = _tail(l, l.pts.size() - 1 if s_to > s_from else 0, goal)
			if raw_tail.is_empty():
				return [path, marks]
			if _path_len(raw_tail, l) == INF:
				from_seg = int(hit.leave_seg) + 1
				continue
		var mid := l.points_between(s_from, s_to, bias, to_end, not start_in)
		if mid.is_empty():
			return [path, marks]
		var head := PackedVector3Array([path[0]])
		var head_m := PackedByteArray([0])
		if not start_in:
			head = _sub_path(path[0], mid[0])
			if head.is_empty():
				return [path, marks]
			head_m = PackedByteArray()
			head_m.resize(head.size())
			var hr := _thread_lanes(head, head_m, mid[0], bias, depth + 1)
			head = hr[0]
			head_m = hr[1]
			if head.size() > 1 and head[head.size() - 1].distance_to(mid[0]) < 0.3:
				head.remove_at(head.size() - 1)
				head_m.remove_at(head_m.size() - 1)
		var tail := PackedVector3Array([goal])
		var tail_m := PackedByteArray([0])
		if not end_in:
			tail = raw_tail
			tail_m = PackedByteArray()
			tail_m.resize(tail.size())
			var tres := _thread_lanes(tail, tail_m, goal, bias, depth + 1)
			tail = tres[0]
			tail_m = tres[1]
			# Premier point : l'ancre (sans écart), déjà rejointe par le couloir.
			if tail.size() > 1:
				tail.remove_at(0)
				tail_m.remove_at(0)
		var out := head.duplicate()
		var om := head_m.duplicate()
		out.append_array(mid)
		var mk := PackedByteArray()
		mk.resize(mid.size())
		mk.fill(l.index + 1)
		om.append_array(mk)
		out.append_array(tail)
		om.append_array(tail_m)
		return [out, om]
	return [path, marks]


## Premier escalier emprunté par `path` à partir du segment `from_seg` :
## {lane, enter, leave (points), leave_seg, start_in, end_in} ou {}.
func _first_lane(path: PackedVector3Array, from_seg: int) -> Dictionary:
	var cur: StairLane = null
	var hit := {}
	# Seuls les escaliers sous l'emprise du chemin (vue de dessus) comptent.
	var box := Rect2(Vector2(path[from_seg].x, path[from_seg].z), Vector2.ZERO)
	for k in range(from_seg + 1, path.size()):
		box = box.expand(Vector2(path[k].x, path[k].z))
	var near: Array[StairLane] = []
	for l in lanes:
		if l.ok and box.grow(0.5).intersects(l.aabb):
			near.append(l)
	if near.is_empty():
		return hit
	for k in range(from_seg, path.size() - 1):
		var a := path[k]
		var b := path[k + 1]
		# Passage de l'escalier (NavigationLink3D d'une ancre à l'autre) : ligne
		# droite qui peut sortir de l'emprise (en L) ; reconnu par ses deux bouts.
		if cur == null:
			for l in near:
				if not l.ok or l.link == null:
					continue
				var e0 := l.pts[0]
				var e1 := l.pts[l.pts.size() - 1]
				if (a.distance_to(e0) < 0.35 and b.distance_to(e1) < 0.35) or (a.distance_to(e1) < 0.35 and b.distance_to(e0) < 0.35):
					return {"lane": l, "enter": a, "leave": b, "leave_seg": k, "start_in": false, "end_in": false}
		var n := maxi(1, ceili(a.distance_to(b) / LANE_SAMPLE))
		for j in n + (1 if k == path.size() - 2 else 0):
			var q := a.lerp(b, float(j) / n)
			if cur == null:
				for l in near:
					if l.ok and l.contains(q):
						cur = l
						hit = {"lane": l, "enter": q, "leave": q, "leave_seg": k,
							"start_in": from_seg == 0 and k == 0 and j == 0, "end_in": false}
						break
			elif cur.contains(q):
				hit.leave = q
				hit.leave_seg = k
			else:
				return hit
	if cur != null:
		hit.end_in = true
	return hit


## Longueur d'un chemin ; INF s'il est vide ou s'il reprend l'escalier `l`
## (par son passage ou par ses marches : il ferait demi-tour dessus).
static func _path_len(p: PackedVector3Array, l: StairLane) -> float:
	if p.is_empty():
		return INF
	var e0 := l.pts[0]
	var e1 := l.pts[l.pts.size() - 1]
	var total := 0.0
	for i in p.size() - 1:
		var a := p[i]
		var b := p[i + 1]
		if (a.distance_to(e0) < 0.35 and b.distance_to(e1) < 0.35) or (a.distance_to(e1) < 0.35 and b.distance_to(e0) < 0.35):
			return INF
		var n := maxi(1, ceili(a.distance_to(b) / 0.5))
		for j in range(1, n + 1):
			if l.contains(a.lerp(b, float(j) / n)):
				return INF
		total += a.distance_to(b)
	return total


## Chemin du navmesh de `a` à `b` (vide s'il n'y arrive pas).
func _sub_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var goal := closest_point(b)
	_sub_query.start_position = a
	_sub_query.target_position = goal
	NavigationServer3D.query_path(_sub_query, _sub_result)
	var p := _sub_result.path
	if p.is_empty() or p[p.size() - 1].distance_to(goal) > REACH_TOLERANCE or goal.distance_to(b) > ANCHOR_SNAP + 0.4:
		return PackedVector3Array()
	return p


## Chemin depuis l'ancre `i` du couloir `l` vers `goal`, partagé par la horde
## pendant un pas physique (même carte de navigation).
func _tail(l: StairLane, i: int, goal: Vector3) -> PackedVector3Array:
	var fp := Engine.get_physics_frames()
	var it := NavigationServer3D.map_get_iteration_id(map)
	if int(_tails.get("_f", -1)) != fp or int(_tails.get("_i", -1)) != it:
		_tails.clear()
		_tails["_f"] = fp
		_tails["_i"] = it
	var key := [l.index, i, goal]
	var v: Variant = _tails.get(key)
	if v == null:
		v = _sub_path(l.pts[i], goal)
		_tails[key] = v
	return v


func crosses_stairs(a: Vector3, b: Vector3) -> bool:
	if not _anchored:
		return false
	for l in lanes:
		if l.ok and l.crosses(a, b):
			return true
	return false


func lane_push(mark: int, pos: Vector3) -> Vector3:
	if mark <= 0 or mark > lanes.size():
		return Vector3.ZERO
	return lanes[mark - 1].push_back(pos)
