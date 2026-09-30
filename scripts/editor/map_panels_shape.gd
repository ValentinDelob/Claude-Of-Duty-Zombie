class_name MapPanelsShape
extends RefCounted
## Onglet Propriétés de l'éditeur de cartes, parties « formes libres » (à côté
## de MapPanels pour ne pas l'alourdir) : paramètres d'une forme de base posée
## (nombre de points d'un cercle, rayons, angle, branches d'un L) qui la
## régénèrent, rotation d'une pièce avec son contenu, angle au degré près
## d'un objet (pilier, escalier, piège, décor, luminaire, mur), réglages d'un
## mur courbe (rayon, ouverture, segments).


## Champ numérique qui applique `apply(v)` -> {ok...} : une étape d'annulation
## si c'est accepté, la raison du refus sinon (le champ revient à sa valeur).
static func _field(p: MapPanels, label: String, value: float, lo: float, hi: float, stp: float, suffix: String, apply: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = stp
	s.value = value
	s.suffix = suffix
	s.select_all_on_focus = true
	s.value_changed.connect(func(v):
		var before := p.ed.doc.snapshot()
		var res: Dictionary = apply.call(v)
		if res.get("ok", false):
			p.ed.push_undo_snapshot(before)
			p.ed.changed()
		else:
			p.ed.doc.restore(before)
			p.ed.canvas.show_refusal(res)
			p.refresh())
	p._row(p._props, label, s)
	return s


## Paramètres de la forme de base d'une pièce (clé « forme »), et rotation de
## la pièce avec son contenu.
static func room_shape(p: MapPanels, r: Dictionary) -> void:
	var rid := String(r.id)
	var doc := p.ed.doc
	if r.has("forme") and MapShapes.valid(r.forme):
		var f: Dictionary = r.forme
		p._title(p._props, MapShapes.name_of(f))
		var regen := func(key: String, v: float) -> Dictionary:
			var room := doc.find(rid)
			var g: Dictionary = room.forme.duplicate(true)
			g[key] = v
			if key == "points":
				g[key] = int(v)
			return MapTransform.regenerate(doc, room, g)
		if MapShapes.has_points(f):
			var s := _field(p, Lang.t("Points", "Points"), float(f.get("points", MapShapes.DEFAULT_POINTS)), MapShapes.MIN_POINTS, MapShapes.MAX_POINTS, 1, "",
				func(v): return regen.call("points", v))
			s.tooltip_text = Lang.t("Niveau de détail : 3 (triangle) à 64 points", "Level of detail: 3 (triangle) to 64 points")
		if String(f.type) == "cercle":
			_field(p, Lang.t("Rayon", "Radius"), float(f.rx), 1.0, MapShapes.MAX_RADIUS, 0.01, "m", func(v): return regen.call("rx", v))
		else:
			_field(p, Lang.t("Largeur", "Width"), float(f.rx) * 2.0, 1.5, MapShapes.MAX_RADIUS * 2.0, 0.01, "m", func(v): return regen.call("rx", v * 0.5))
			_field(p, Lang.t("Hauteur", "Height"), float(f.get("ry", f.rx)) * 2.0, 1.5, MapShapes.MAX_RADIUS * 2.0, 0.01, "m", func(v): return regen.call("ry", v * 0.5))
		if String(f.type) == "l":
			_field(p, Lang.t("Branches", "Arms"), roundf(float(f.get("bras", 0.5)) * 100.0), 20, 80, 1, "%", func(v): return regen.call("bras", v / 100.0))
		# Angle : la pièce tourne autour du centre de sa forme, avec son contenu.
		_field(p, Lang.t("Angle", "Angle"), float(f.get("angle", 0)), 0, 359, 1, "°", func(v):
			var room := doc.find(rid)
			var d := roundi(v) - MapTransform.angle_of(room)
			if d == 0:
				return {"ok": true}
			return MapTransform.apply(doc, room.duplicate(true), p.ed.attached_to(room), MapGeom.v2(room.forme.centre), float(d), doc.snapshot()))
		p._note(p._props, Lang.t("Changer un réglage régénère la forme (ouvertures et objets muraux restent sur leur mur). Déplacer un sommet à la main en fait un polygone libre.",
			"Changing a setting regenerates the shape (openings and wall items stay on their wall). Moving a corner by hand turns it into a free polygon."))
	else:
		# Pièce quelconque : rotation d'un angle choisi, avec son contenu.
		var s := _field(p, Lang.t("Pivoter de", "Rotate by"), 0, -180, 180, 1, "°", func(v):
			var room := doc.find(rid)
			if room.is_empty() or roundi(v) == 0:
				return {"ok": true}
			var c := MapGeom.bbox(doc.room_poly(room)).get_center()
			return MapTransform.apply(doc, room.duplicate(true), p.ed.attached_to(room), c, float(roundi(v)), doc.snapshot()))
		s.tooltip_text = Lang.t("La pièce tourne avec son contenu (poignée ronde : pas de 15°, Alt : au degré près)",
			"The room turns with its contents (round handle: 15° steps, Alt: to the degree)")


## Angle au degré près d'un objet qui tourne (pilier, escalier, piège, décor,
## luminaire, mur, mur courbe) : rotation autour de son centre.
static func angle_row(p: MapPanels, o: Dictionary) -> void:
	var oid := String(o.id)
	var doc := p.ed.doc
	var s := _field(p, Lang.t("Angle", "Angle"), MapTransform.angle_of(o), 0, 359, 1, "°", func(v):
		var e := doc.find(oid)
		if e.is_empty():
			return {"ok": false, "fr": "élément introuvable", "en": "element not found"}
		var d := roundi(v) - MapTransform.angle_of(e)
		if d == 0:
			return {"ok": true}
		return MapTransform.apply(doc, e.duplicate(true), [], MapTransform.pivot(doc, e), float(d), doc.snapshot()))
	s.tooltip_text = Lang.t("Degrés, sens horaire vu de dessus (poignée ronde : pas de 15°, Alt : au degré près ; R : 90°)",
		"Degrees, clockwise seen from above (round handle: 15° steps, Alt: to the degree; R: 90°)")


## Mur courbe : rayon, ouverture, segments.
static func arc_props(p: MapPanels, o: Dictionary) -> void:
	var oid := String(o.id)
	var doc := p.ed.doc
	var set_key := func(key: String, v: Variant) -> Dictionary:
		var e := doc.find(oid)
		var cand := e.duplicate(true)
		cand[key] = v
		var res := MapRules.check_arc(cand)
		if res.ok:
			e[key] = v
		return res
	_field(p, Lang.t("Rayon", "Radius"), float(o.get("rayon", 4.0)), 1.0, MapShapes.MAX_RADIUS, 0.01, "m", func(v): return set_key.call("rayon", snappedf(v, 0.001)))
	_field(p, Lang.t("Ouverture", "Opening"), float(o.get("ouverture", MapShapes.DEFAULT_OPENING)), 5, 360, 1, "°", func(v): return set_key.call("ouverture", float(roundi(v))))
	_field(p, Lang.t("Segments", "Segments"), float(o.get("segments", MapShapes.DEFAULT_SEGMENTS)), MapShapes.MIN_SEGMENTS, MapShapes.MAX_SEGMENTS, 1, "",
		func(v): return set_key.call("segments", int(v)))
	p._note(p._props, Lang.t("Arc de cercle en segments droits (vrais murs obliques en jeu). Plus de segments : plus rond.",
		"Arc made of straight segments (real oblique walls in game). More segments: rounder."))
