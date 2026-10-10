class_name MapCubeSnap
extends RefCounted
## Architecture sur la grille des cubes de 5 cm (format 20,
## docs/VOXEL_ARCHITECTURE_PLAN.md § 2.1 et § 2.5, GAME_CONCEPT.md § 4.19).
##
## Arrondit au cube de 5 cm (MapGeom.cube) :
##   - pièces : sommets du contour (deux sommets voisins confondus par
##     l'arrondi n'en font plus qu'un), centre et demi-côtés de leur « forme »,
##     « altitude », « plafond » ;
##   - murs libres : « a », « b », « epaisseur » ; murs courbes : « centre »,
##     « rayon », « epaisseur » ; piliers et escaliers : les coins de « rect »,
##     « altitude_haut » ;
##   - toute ouverture et tout objet : « altitude » (même fonction que pour les
##     pièces : un élément reste au niveau de sa pièce) ;
##   - ouvertures et objets muraux du jeu (courant, poste central, levier,
##     porte d'évacuation, station, caisse murale) : leur place LE LONG DU MUR,
##     gardée sur le mur arrondi (sur un mur droit : sur la grille ; sur un mur
##     en biais : le point de la grille sur le trait le plus proche, sinon une
##     distance au bout du mur en cubes) ;
##   - « hauteur_portes » de la carte.
## Le décor, les luminaires, les effets, les barrières invisibles, les pièges
## et les points de jeu (départ, apparitions...) gardent leurs règles
## (docs/VOXEL_DECOR_PLAN.md). Deux pièces voisines arrondies par la même
## fonction gardent leur bord commun. Les angles libres restent (rendu en
## escalier de cubes, lot B).
##
## Deux usages : la migration d'une carte d'un format plus ancien
## (EditorMap._migrate, snap_map) et chaque modification faite dans l'éditeur
## (MapEditor._commit_change, snap_edited : seuls les éléments changés).
## Rapport de migration (erreurs nouvelles du validateur) : new_errors ;
## copie de sauvegarde avant tout enregistrement : backup.

## Types d'objets de l'architecture (en plus des pièces, clé « contour »).
const ARCHI_TYPES := ["mur", "mur_courbe", "pilier", "escalier"]
## Objets muraux du jeu dont la place le long du mur est arrondie (le décor
## mural, les appliques et les effets muraux gardent la leur).
const WALL_ITEMS := ["courant", "poste_central", "levier", "evacuation", "station", "boite"]
## Dossier des copies de sauvegarde (dans le dossier des cartes ; « _ » :
## jamais listé comme une carte, EditorMap.list_maps).
const BACKUP_DIR := "_sauvegardes"
## Écart (m) entre l'objet mural et le trait de son mur pour qu'il y soit
## rattaché (les murs mitoyens sont regroupés à 3 cm, MapGeom.JOIN_TOL).
const WALL_TOL := 0.06


## Élément de l'architecture (pièce, mur, mur courbe, pilier, escalier) ?
static func is_architecture(e: Dictionary) -> bool:
	return e.has("contour") or String(e.get("type", "")) in ARCHI_TYPES


## Ouverture ou objet mural du jeu, placé le long d'un mur ?
static func is_wall_bound(e: Dictionary) -> bool:
	var t := String(e.get("type", ""))
	if t in MapRules.ouvertures_types():
		return true
	return t in WALL_ITEMS and e.has("mur")


## Toute la carte sur la grille des cubes. -> nombre de valeurs changées.
static func snap_map(doc: EditorMap) -> int:
	return _snap(doc, {}, true)


## Éléments `ids` ({id: true}) seulement (une modification de l'éditeur) ;
## avec `carte_too`, « hauteur_portes » aussi. -> nombre de valeurs changées.
static func snap_ids(doc: EditorMap, ids: Dictionary, carte_too := false) -> int:
	if ids.is_empty() and not carte_too:
		return 0
	return _snap(doc, ids, carte_too)


## Après une modification de l'éditeur : les éléments changés depuis
## `before` (EditorMap.snapshot), nouveaux compris, et les ouvertures et objets
## muraux posés sur un mur changé. -> nombre de valeurs changées.
static func snap_edited(before: Dictionary, doc: EditorMap) -> int:
	var old := {}
	for key in ["pieces", "ouvertures", "objets"]:
		var list: Variant = before.get(key, [])
		if list is Array:
			for e in list:
				if e is Dictionary:
					old[String(e.get("id", ""))] = e
	var ids := {}
	var walls_changed := []
	for list in [doc.pieces, doc.ouvertures, doc.objets]:
		for e in list:
			if not e is Dictionary:
				continue
			var eid := String(e.get("id", ""))
			if old.has(eid) and old[eid] == e:
				continue
			if is_architecture(e) or is_wall_bound(e) or e.has("altitude"):
				ids[eid] = true
			if e.has("contour") or String(e.get("type", "")) in ["mur", "mur_courbe"]:
				walls_changed.append(e)
	if not walls_changed.is_empty():
		# Ouvertures et objets muraux sur les murs changés : ils suivent l'arrondi.
		var segs := []
		for w in walls_changed:
			segs.append_array(_segments_of(w))
		for list in [doc.ouvertures, doc.objets]:
			for e in list:
				if e is Dictionary and is_wall_bound(e) and _find_wall(segs, e) >= 0:
					ids[String(e.get("id", ""))] = true
	var c_old: Variant = before.get("carte", {})
	var carte_too: bool = c_old is Dictionary and c_old.get("hauteur_portes") != doc.carte.get("hauteur_portes")
	return snap_ids(doc, ids, carte_too)


# ------------------------------------------------------------------ arrondi

## Compteur de valeurs changées (partagé par les fonctions d'arrondi).
class _Count:
	var n := 0


static func _snap(doc: EditorMap, only: Dictionary, carte_too: bool) -> int:
	var cnt := _Count.new()
	var take := func(e: Variant) -> bool:
		return e is Dictionary and (only.is_empty() or only.has(String(e.get("id", ""))))
	# Murs AVANT l'arrondi (pour garder chaque objet mural sur son mur).
	var segs := []
	for list in [doc.pieces, doc.objets]:
		for e in list:
			if e is Dictionary:
				segs.append_array(_segments_of(e))
	# Un mur qui n'est pas arrondi ici (élément inchangé dans l'éditeur) garde
	# ses bouts : l'objet reste sur lui.
	for s in segs:
		s["moves"] = only.is_empty() or only.has(String(s.owner))
	var bound := []   # [objet, indice du mur]
	for list in [doc.ouvertures, doc.objets]:
		for e in list:
			if take.call(e) and is_wall_bound(e):
				bound.append([e, _find_wall(segs, e)])
	for p in doc.pieces:
		if take.call(p):
			_snap_room(p, cnt)
	for o in doc.objets:
		if not take.call(o):
			continue
		match String(o.get("type", "")):
			"mur":
				for key in ["a", "b"]:
					_pt(o, key, cnt)
				_len(o, "epaisseur", cnt)
			"mur_courbe":
				_pt(o, "centre", cnt)
				_len(o, "rayon", cnt)
				_len(o, "epaisseur", cnt)
			"pilier", "escalier":
				_rect(o, cnt)
		_num(o, "altitude_haut", cnt)
	for list in [doc.pieces, doc.ouvertures, doc.objets]:
		for e in list:
			if take.call(e):
				_num(e, "altitude", cnt)
	for b in bound:
		_snap_wall_item(b[0], segs, int(b[1]), cnt)
	if carte_too:
		_num(doc.carte, "hauteur_portes", cnt)
	return cnt.n


static func _changed(a: float, b: float) -> bool:
	return absf(a - b) > 1e-6


## Coordonnée propre : sur la grille, la valeur exacte du cube ; sinon au
## millimètre (place sur un mur en biais).
static func _clean(v: float) -> float:
	return MapGeom.cube(v) if MapGeom.on_cube(v) else snappedf(v, 0.001)


## Nombre `key` de `e` (s'il est lisible) arrondi au cube.
static func _num(e: Dictionary, key: String, cnt: _Count) -> void:
	var v: Variant = e.get(key)
	if not ((v is float or v is int) and is_finite(float(v))):
		return
	var c := MapGeom.cube(float(v))
	if _changed(c, float(v)):
		cnt.n += 1
		e[key] = c


## Longueur `key` (épaisseur, rayon) : au cube, jamais sous un cube.
static func _len(e: Dictionary, key: String, cnt: _Count) -> void:
	var v: Variant = e.get(key)
	if not ((v is float or v is int) and is_finite(float(v))):
		return
	var c := maxf(MapGeom.CUBE, MapGeom.cube(float(v)))
	if _changed(c, float(v)):
		cnt.n += 1
		e[key] = c


## Point [x, y] `key` de `e` arrondi au cube.
static func _pt(e: Dictionary, key: String, cnt: _Count) -> void:
	var v: Variant = e.get(key)
	if not _is_pt(v):
		return
	e[key] = _cube_pt(v, cnt)


static func _is_pt(v: Variant) -> bool:
	return v is Array and v.size() >= 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int) \
		and is_finite(float(v[0])) and is_finite(float(v[1]))


static func _cube_pt(v: Array, cnt: _Count) -> Array:
	var x := MapGeom.cube(float(v[0]))
	var y := MapGeom.cube(float(v[1]))
	if _changed(x, float(v[0])):
		cnt.n += 1
	if _changed(y, float(v[1])):
		cnt.n += 1
	return [x, y]


## Rectangle [x0, y0, x1, y1] (pilier, escalier) : chaque coin au cube (la
## taille reste un nombre entier de cubes).
static func _rect(e: Dictionary, cnt: _Count) -> void:
	var r: Variant = e.get("rect")
	if not (r is Array and r.size() == 4 and r.all(func(x): return (x is float or x is int) and is_finite(float(x)))):
		return
	var out := []
	for x in r:
		var c := MapGeom.cube(float(x))
		if _changed(c, float(x)):
			cnt.n += 1
		out.append(c)
	e["rect"] = out


## Pièce : contour (sommets confondus fusionnés), forme, plafond.
static func _snap_room(p: Dictionary, cnt: _Count) -> void:
	var src: Variant = p.get("contour")
	if src is Array:
		var pts := []
		for q in src:
			if not _is_pt(q):
				pts.append(q)
				continue
			var c := _cube_pt(q, cnt)
			if not pts.is_empty() and pts[-1] == c:
				cnt.n += 1
				continue
			pts.append(c)
		while pts.size() > 3 and pts[0] == pts[-1]:
			pts.pop_back()
			cnt.n += 1
		p["contour"] = pts
	var f: Variant = p.get("forme")
	if f is Dictionary and MapShapes.valid(f):
		_pt(f, "centre", cnt)
		_len(f, "rx", cnt)
		_len(f, "ry", cnt)
	_num(p, "plafond", cnt)


# ------------------------------------------------------------------ objets le long d'un mur

## Traits des murs d'un élément, avant et après l'arrondi : [{a, b, na, nb,
## alt, half, owner}] (pièce : ses côtés ; mur libre ; mur courbe : ses
## segments, recalculés d'après son centre et son rayon arrondis). `half` :
## demi-épaisseur (un objet mural d'un mur épais est sur sa face).
static func _segments_of(e: Dictionary) -> Array:
	var out := []
	var alt := EditorMap.alt_of(e)
	var owner := String(e.get("id", ""))
	if e.get("contour") is Array:
		var poly := PackedVector2Array()
		for q in e.contour:
			if _is_pt(q):
				poly.append(MapGeom.v2(q))
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			out.append({"a": a, "b": b, "na": MapGeom.round_cube(a), "nb": MapGeom.round_cube(b), "alt": alt, "half": 0.0, "owner": owner})
		return out
	var half := float(e.get("epaisseur", 0.5)) * 0.5 if (e.get("epaisseur", 0.5) is float or e.get("epaisseur", 0.5) is int) else 0.25
	match String(e.get("type", "")):
		"mur":
			if _is_pt(e.get("a")) and _is_pt(e.get("b")):
				var a := MapGeom.v2(e.a)
				var b := MapGeom.v2(e.b)
				out.append({"a": a, "b": b, "na": MapGeom.round_cube(a), "nb": MapGeom.round_cube(b), "alt": alt, "half": half, "owner": owner})
		"mur_courbe":
			if _is_pt(e.get("centre")):
				var snapped := e.duplicate()
				snapped["centre"] = MapGeom.cube_arr(MapGeom.v2(e.centre))
				var rv: Variant = e.get("rayon")
				if (rv is float or rv is int) and is_finite(float(rv)):
					snapped["rayon"] = maxf(MapGeom.CUBE, MapGeom.cube(float(rv)))
				var olds := MapShapes.arc_segments(e)
				var news := MapShapes.arc_segments(snapped)
				for i in olds.size():
					var ns: Array = news[i] if i < news.size() else olds[i]
					out.append({"a": olds[i][0], "b": olds[i][1], "na": ns[0], "nb": ns[1], "alt": alt, "half": half, "owner": owner})
	return out


## Mur (indice dans `segs`) le plus proche de l'objet `o`, à son altitude ;
## -1 s'il n'est contre aucun mur.
static func _find_wall(segs: Array, o: Dictionary) -> int:
	if not _is_pt(o.get("position")):
		return -1
	var p := MapGeom.v2(o.position)
	var alt := EditorMap.alt_of(o)
	var best := -1
	var best_d := INF
	for i in segs.size():
		var s: Dictionary = segs[i]
		if absf(float(s.alt) - alt) > EditorMap.ALT_EQ:
			continue
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		if a.distance_to(b) < MapGeom.EPS:
			continue
		# Distance au trait, moins la demi-épaisseur au-delà de 0,25 m (face
		# d'un mur libre épais, MapTransform.on_free_wall).
		var d := MapGeom.dist_to_segment(p, a, b)
		var off := maxf(0.0, float(s.half) - MapGeom.WALL_HALF)
		d = absf(d - off) if off > 0.0 else d
		if d < best_d and d <= WALL_TOL:
			best_d = d
			best = i
	return best


## Objet mural `o` sur le mur `segs[i]` d'avant l'arrondi : même place
## relative sur le mur arrondi (mêmes bouts arrondis au cube), place le long
## du mur sur la grille des cubes ; sans mur : sa position arrondie au cube.
static func _snap_wall_item(o: Dictionary, segs: Array, i: int, cnt: _Count) -> void:
	if not _is_pt(o.get("position")):
		return
	var p := MapGeom.v2(o.position)
	var np := MapGeom.round_cube(p)
	if i >= 0:
		var s: Dictionary = segs[i]
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var na: Vector2 = s.na if s.get("moves", true) else a
		var nb: Vector2 = s.nb if s.get("moves", true) else b
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x)
		var along := (p - a).dot(t)
		# Écart au trait : sur le trait d'un côté de pièce ; sur la face d'un
		# mur libre épais (demi-épaisseur arrondie moins 0,25 m), de son côté.
		var thick := float(s.half) * 2.0
		if s.get("moves", true):
			thick = maxf(MapGeom.CUBE, MapGeom.cube(thick))
		var face := maxf(0.0, thick * 0.5 - MapGeom.WALL_HALF) if float(s.half) > 0.0 else 0.0
		var off := face * signf((p - a).dot(n))
		var nt := (nb - na).normalized() if na.distance_to(nb) > MapGeom.EPS else t
		var nn := Vector2(-nt.y, nt.x)
		var nlen := na.distance_to(nb)
		var nal := along * nlen / maxf(a.distance_to(b), MapGeom.EPS)
		# Mur droit (bouts sur la grille) : la place le long du mur au cube ;
		# l'écart au trait (face d'un mur libre épais) est gardé.
		np = na + nt * MapGeom.cube(nal) + nn * off
		if not MapGeom.is_axis_seg(na, nb):
			# Mur en biais : le point de la grille sur le trait le plus proche
			# (tous les 7 cm sur un mur à 45°), sinon la distance en cubes.
			var on_line := na + nt * nal
			var g := MapGeom.cube_near_line(on_line, na, nb)
			if absf((g - na).cross(nt)) < 0.001 and g.distance_to(on_line) <= MapGeom.CUBE:
				np = g + nn * off
		# Objet contre un mur en biais : direction du mur arrondi, même côté.
		if o.has("angle") and absf(MapGeom.item_wall_dir(o).dot(t)) < 0.05:
			var dv := MapGeom.item_wall_dir(o)
			var ang := snappedf(MapGeom.dir_deg(nn if dv.dot(nn) >= 0.0 else -nn), 0.01)
			if absf(fposmod(ang - float(o.angle) + 180.0, 360.0) - 180.0) > 0.005:
				cnt.n += 1
				o["angle"] = ang
	# Nombres en double précision (un Vector2 est en 32 bits : 25,1 deviendrait
	# 25.1000003814697) ; comparés à la position lue du fichier.
	var out := [_clean(np.x), _clean(np.y)]
	var src: Array = o.position
	if _changed(out[0], float(src[0])):
		cnt.n += 1
	if _changed(out[1], float(src[1])):
		cnt.n += 1
	o["position"] = out


# ------------------------------------------------------------------ rapport de migration

## Messages d'erreur du validateur d'une carte (MapRaster, MapValidator).
static func errors_of(doc: EditorMap) -> Array:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v.errors()


## Clé d'un message pour comparer deux validations : son texte sans les
## nombres (une position arrondie de 2 cm reste la même erreur).
static func error_key(m: Dictionary) -> String:
	var re := RegEx.create_from_string("-?[0-9]+([.,][0-9]+)?")
	return re.sub(String(m.get("fr", "")), "#", true)


## Erreurs de `after` absentes de `before` (même texte aux nombres près,
## comptées : une erreur de plus du même genre est nouvelle). -> messages.
static func new_errors(before: EditorMap, after: EditorMap) -> Array:
	var seen := {}
	for m in errors_of(before):
		var k := error_key(m)
		seen[k] = int(seen.get(k, 0)) + 1
	var out := []
	for m in errors_of(after):
		var k := error_key(m)
		if int(seen.get(k, 0)) > 0:
			seen[k] = int(seen[k]) - 1
		else:
			out.append(m)
	return out


# ------------------------------------------------------------------ copie de sauvegarde

## Copie de sauvegarde de la carte du dossier `dir` (format `fmt`, avant son
## passage aux cubes), AVANT tout enregistrement :
## <dossier des cartes>/_sauvegardes/<id>_f<format>_<date>/ (dossier entier :
## les cinq JSON, prefabs/ et textures/). Jamais deux fois la même : une copie
## de cette carte à ce format aux mêmes cinq fichiers sert encore.
## -> chemin de la copie ("" si `dir` n'est pas une carte du dossier des cartes
## ou si la copie a échoué).
static func backup(dir: String, fmt: int) -> String:
	var root := EditorMap.maps_root()
	var target := EditorMap._abs(dir).trim_suffix("/")
	var id := target.get_file()
	if target.get_base_dir() != EditorMap._abs(root).trim_suffix("/") or not EditorMap.valid_id(id) or id.begins_with("_"):
		return ""
	if not EditorMap.is_map_dir(target) or EditorMap._has_link(target):
		return ""
	var base := root.path_join(BACKUP_DIR)
	var prefix := "%s_f%d_" % [id, fmt]
	if DirAccess.dir_exists_absolute(base):
		var names := Array(DirAccess.get_directories_at(base))
		names.sort()
		for d in names:
			if String(d).begins_with(prefix) and _same_files(target, base.path_join(d)):
				return base.path_join(d)
	var stamp := Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "_")
	var dest := base.path_join(prefix + stamp)
	var n := 2
	while DirAccess.dir_exists_absolute(dest):
		dest = base.path_join("%s%s_%d" % [prefix, stamp, n])
		n += 1
	if _copy_tree(target, dest) != OK:
		push_warning("[MapCubeSnap] copie de sauvegarde impossible : %s -> %s" % [target, dest])
		return ""
	return dest


## Mêmes cinq fichiers JSON dans les deux dossiers ?
static func _same_files(a: String, b: String) -> bool:
	for f in EditorMap.FILES:
		var ta: Variant = EditorMap.read_text(a.path_join(f))
		var tb: Variant = EditorMap.read_text(b.path_join(f))
		if ta != tb:
			return false
	return true


## Copie récursive d'un dossier (sans lien symbolique : refusé avant).
static func _copy_tree(src: String, dest: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dest)
	if err != OK:
		return err
	var d := DirAccess.open(src)
	if d == null:
		return DirAccess.get_open_error()
	d.include_hidden = true
	for f in d.get_files():
		err = DirAccess.copy_absolute(src.path_join(f), dest.path_join(f))
		if err != OK:
			return err
	for s in d.get_directories():
		err = _copy_tree(src.path_join(s), dest.path_join(s))
		if err != OK:
			return err
	return OK
