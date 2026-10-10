class_name MapTestKit
extends RefCounted
## Outils des tests pour les cartes de l'éditeur construites en code.
##
## Format 18 : chaque carte jouable a une porte d'évacuation accessible depuis
## le départ (MapValidator). Les cartes de test d'avant n'en avaient pas :
## add_evac en pose une avec la vraie règle de pose de l'éditeur
## (MapRules.place_wall_item) contre un mur de la salle de départ.

const ID := "evac_t"


## Pose une porte d'évacuation contre un mur de la pièce du départ des
## joueurs (sinon de la première pièce) ; rien si la carte en a déjà une.
## Rend la carte (chaînable) ; échec (aucun mur libre) : carte inchangée.
static func add_evac(m: EditorMap) -> EditorMap:
	if m.objets.any(func(o): return o is Dictionary and String(o.get("type", "")) == "evacuation"):
		return m
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
			# Du milieu du mur vers ses bouts (0, +0,5, -0,5, +1...) : la
			# première place libre.
			var offs := [0.0]
			for j in range(1, int(length)):
				offs.append(j * 0.5)
				offs.append(-j * 0.5)
			for off: float in offs:
				var p := a.lerp(b, 0.5) + t * off
				for side in [1.0, -1.0]:
					var mouse: Vector2 = p + nrm * 0.3 * side
					if not MapGeom.contains(poly, mouse):
						continue
					var tmpl := {"type": "evacuation"}
					var res := MapRules.place_wall_item(m, k, tmpl, mouse)
					if not bool(res.get("ok", false)):
						continue
					# « altitude » en dernier, comme après une conversion d'un format plus ancien.
					var o := {"id": ID, "type": "evacuation", "position": res.position}
					MapRules.apply_wall(o, res)
					o["altitude"] = EditorMap.alt_of(room)
					m.objets.append(o)
					return m
	push_warning("[MapTestKit] aucune place pour la porte d'évacuation")
	return m


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
