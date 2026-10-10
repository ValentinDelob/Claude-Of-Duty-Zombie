class_name MapTestKit
extends RefCounted
## Outils des tests pour les cartes de l'éditeur construites en code.
##
## Format 18 : chaque carte jouable a une porte d'évacuation accessible depuis
## le départ ; format 19 : une station de construction (MapValidator). Les
## cartes de test d'avant n'en avaient pas : add_evac pose les deux objets
## obligatoires avec la vraie règle de pose de l'éditeur
## (MapRules.place_wall_item), contre un mur de la salle de départ (sinon
## d'une autre pièce).

const ID := "evac_t"
const STATION_ID := "station_t"


## Pose les objets obligatoires qui manquent : porte d'évacuation contre un
## mur de la pièce du départ des joueurs (sinon de la première pièce), puis
## station de construction (add_station). Rend la carte (chaînable) ; échec
## (aucun mur libre) : carte inchangée pour cet objet.
static func add_evac(m: EditorMap) -> EditorMap:
	if not _has(m, "evacuation") and not _add_against_walls(m, "evacuation", ID):
		push_warning("[MapTestKit] aucune place pour la porte d'évacuation")
	return add_station(m)


## Pose la station de construction (format 19) contre un mur, de préférence
## de la salle de départ ; rien si la carte en a déjà une.
static func add_station(m: EditorMap) -> EditorMap:
	if not _has(m, "station") and not _add_against_walls(m, "station", STATION_ID):
		push_warning("[MapTestKit] aucune place pour la station de construction")
	return m


## Pose la porte d'évacuation contre le mur le plus proche de `mouse` (point
## de l'éditeur dans la pièce du départ), comme un clic de l'éditeur : pour un
## test qui pose ensuite d'autres objets contre les murs et doit garder la
## porte à l'écart. Rien si la carte en a déjà une ; échec : carte inchangée.
## La station de construction est posée ensuite comme dans add_evac.
static func add_evac_at(m: EditorMap, mouse: Vector2) -> EditorMap:
	if _has(m, "evacuation"):
		return add_station(m)
	var done := false
	for room in _candidate_rooms(m):
		if MapGeom.contains(m.room_poly(room), mouse) and _place(m, room, mouse, "evacuation", ID):
			done = true
			break
	if not done:
		push_warning("[MapTestKit] porte d'évacuation impossible en %s" % str(mouse))
	return add_station(m)


static func _has(m: EditorMap, type: String) -> bool:
	return m.objets.any(func(o): return o is Dictionary and String(o.get("type", "")) == type)


## Première place libre contre un mur des pièces candidates : du milieu de
## chaque mur vers ses bouts (0, +0,5, -0,5, +1...).
static func _add_against_walls(m: EditorMap, type: String, id: String) -> bool:
	for room in _candidate_rooms(m):
		var k := m.level_of(room)
		if k < 0:
			continue
		var poly := m.room_poly(room)
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var length := a.distance_to(b)
			if length < 2.0:
				continue
			var t := (b - a) / length
			var nrm := Vector2(-t.y, t.x)
			var offs := [0.0]
			for j in range(1, int(length)):
				offs.append(j * 0.5)
				offs.append(-j * 0.5)
			for off: float in offs:
				var p := a.lerp(b, 0.5) + t * off
				for side in [1.0, -1.0]:
					var mouse: Vector2 = p + nrm * 0.3 * side
					if MapGeom.contains(poly, mouse) and _place(m, room, mouse, type, id):
						return true
	return false


## Essaie la règle de pose de l'éditeur au point `mouse` de la pièce `room`.
static func _place(m: EditorMap, room: Dictionary, mouse: Vector2, type: String, id: String) -> bool:
	var k := m.level_of(room)
	if k < 0:
		return false
	var res := MapRules.place_wall_item(m, k, {"type": type}, mouse)
	if not bool(res.get("ok", false)):
		return false
	# « altitude » en dernier, comme après une conversion d'un format plus ancien.
	var o := {"id": id, "type": type, "position": res.position}
	MapRules.apply_wall(o, res)
	o["altitude"] = EditorMap.alt_of(room)
	m.objets.append(o)
	return true


## Pièces candidates : celle du départ des joueurs d'abord, puis celles de la
## zone de départ, puis les autres.
static func _candidate_rooms(m: EditorMap) -> Array:
	var out := []
	for o in m.objets:
		if o is Dictionary and String(o.get("type", "")) == "depart" and o.has("position"):
			var p := MapGeom.v2(o.position)
			for r in m.pieces:
				if not out.has(r) and EditorMap.alt_of(r) == EditorMap.alt_of(o) and MapGeom.contains(m.room_poly(r), p):
					out.append(r)
	for r in m.pieces:
		if String(r.get("zone", "")) == m.depart and not out.has(r):
			out.append(r)
	for r in m.pieces:
		if not out.has(r):
			out.append(r)
	return out
