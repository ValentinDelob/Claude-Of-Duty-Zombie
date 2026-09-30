class_name MapIcons
extends RefCounted
## Icônes de l'inventaire de l'éditeur de cartes, dessinées par code (aucune
## image) : formes simples et lisibles, couleur de l'objet (MapCatalog).

const INK := Color(0.08, 0.08, 0.09)
const WHITE := Color(0.95, 0.94, 0.9)


static func draw(ci: CanvasItem, it: Dictionary, r: Rect2) -> void:
	if it.is_empty():
		return
	var c: Color = it.get("color", Color.WHITE)
	var p := r.grow(-r.size.x * 0.12)
	var cx := p.get_center()
	var s := p.size.x
	var id := String(it.get("id", ""))
	var font := UiStyle.font("impact")
	match id:
		"select":
			var pts := PackedVector2Array([p.position + Vector2(s * 0.2, s * 0.05), p.position + Vector2(s * 0.2, s * 0.85),
				p.position + Vector2(s * 0.42, s * 0.65), p.position + Vector2(s * 0.58, s * 0.95), p.position + Vector2(s * 0.7, s * 0.88),
				p.position + Vector2(s * 0.55, s * 0.6), p.position + Vector2(s * 0.82, s * 0.6)])
			ci.draw_colored_polygon(pts, WHITE)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), INK, 1.5)
		"gomme":
			var pts := PackedVector2Array([cx + Vector2(-s * 0.45, s * 0.1), cx + Vector2(-s * 0.05, -s * 0.35), cx + Vector2(s * 0.45, s * 0.1), cx + Vector2(s * 0.05, s * 0.45)])
			ci.draw_colored_polygon(pts, c)
			ci.draw_line(cx + Vector2(-s * 0.25, -s * 0.1), cx + Vector2(s * 0.25, s * 0.3), INK, 2.0)
		"piece_rect":
			ci.draw_rect(p.grow(-s * 0.08), c.darkened(0.55))
			ci.draw_rect(p.grow(-s * 0.08), c, false, maxf(2.0, s * 0.1))
		"piece_poly":
			var pts := PackedVector2Array()
			for i in 5:
				var a := -PI / 2 + i * TAU / 5
				pts.append(cx + Vector2(cos(a), sin(a)) * s * 0.45)
			ci.draw_colored_polygon(pts, c.darkened(0.55))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), c, maxf(2.0, s * 0.1))
		"mur":
			ci.draw_line(p.position + Vector2(s * 0.1, s * 0.85), p.position + Vector2(s * 0.9, s * 0.15), c.lightened(0.3), s * 0.22)
		"piece_cercle", "piece_ellipse", "piece_triangle", "piece_l":
			var pts := PackedVector2Array()
			match id:
				"piece_cercle":
					pts = MapShapes.regular(cx, s * 0.45, s * 0.45, 16)
				"piece_ellipse":
					pts = MapShapes.regular(cx, s * 0.48, s * 0.32, 20)
				"piece_triangle":
					pts = MapShapes.triangle(cx, s * 0.45, s * 0.4)
				_:
					pts = MapShapes.l_shape(cx, s * 0.42, s * 0.42, 0.45)
			ci.draw_colored_polygon(pts, c.darkened(0.55))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), c, maxf(2.0, s * 0.08))
			if id == "piece_cercle":
				for q in pts:
					ci.draw_circle(q, maxf(1.0, s * 0.03), WHITE)
		"mur_courbe":
			var arc := MapShapes.arc_points(cx + Vector2(-s * 0.3, s * 0.3), s * 0.62, 0.0, 90.0, 6)
			ci.draw_polyline(arc, c.lightened(0.3), s * 0.18)
		"pilier":
			ci.draw_rect(Rect2(cx - Vector2(s, s) * 0.3, Vector2(s, s) * 0.6), c.lightened(0.2))
			ci.draw_rect(Rect2(cx - Vector2(s, s) * 0.3, Vector2(s, s) * 0.6), INK, false, 2.0)
		"escalier":
			for i in 5:
				ci.draw_rect(Rect2(p.position + Vector2(s * 0.15, s * (0.1 + i * 0.16)), Vector2(s * 0.7, s * 0.1)), c)
			ci.draw_line(cx + Vector2(0, s * 0.4), cx - Vector2(0, s * 0.4), WHITE, 2.0)
			ci.draw_line(cx - Vector2(0, s * 0.4), cx + Vector2(-s * 0.15, -s * 0.22), WHITE, 2.0)
			ci.draw_line(cx - Vector2(0, s * 0.4), cx + Vector2(s * 0.15, -s * 0.22), WHITE, 2.0)
		"porte", "porte_courant":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.3, s * 0.45), Vector2(s * 0.6, s * 0.9)), c.darkened(0.2))
			ci.draw_rect(Rect2(cx - Vector2(s * 0.3, s * 0.45), Vector2(s * 0.6, s * 0.9)), INK, false, 2.0)
			ci.draw_circle(cx + Vector2(s * 0.16, s * 0.05), s * 0.05, INK)
			if id == "porte_courant":
				_bolt(ci, cx + Vector2(-s * 0.05, 0), s * 0.5, INK)
		"debris":
			for q in [[-0.25, 0.2, 0.18], [0.1, 0.25, 0.2], [0.28, 0.0, 0.14], [-0.05, -0.05, 0.16], [-0.3, -0.15, 0.1], [0.12, -0.28, 0.12]]:
				ci.draw_circle(cx + Vector2(q[0], q[1]) * s, q[2] * s, c.lightened(float(q[2]) * 0.5))
			ci.draw_line(cx + Vector2(-s * 0.45, s * 0.35), cx + Vector2(s * 0.45, -s * 0.2), c.darkened(0.4), s * 0.08)
		"passage":
			ci.draw_rect(Rect2(p.position, Vector2(s * 0.22, s)), c.darkened(0.3))
			ci.draw_rect(Rect2(p.position + Vector2(s * 0.78, 0), Vector2(s * 0.22, s)), c.darkened(0.3))
			ci.draw_arc(cx + Vector2(0, -s * 0.1), s * 0.28, PI, TAU, 16, c, 3.0)
		"fenetre":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.4, s * 0.35), Vector2(s * 0.8, s * 0.7)), c.darkened(0.5))
			for i in 3:
				ci.draw_line(cx + Vector2(-s * 0.4, s * (-0.2 + i * 0.2)), cx + Vector2(s * 0.4, s * (-0.12 + i * 0.2)), Color(0.55, 0.38, 0.2), s * 0.09)
			ci.draw_rect(Rect2(cx - Vector2(s * 0.4, s * 0.35), Vector2(s * 0.8, s * 0.7)), c, false, 2.0)
		"grenades":
			ci.draw_circle(cx + Vector2(0, s * 0.08), s * 0.3, c)
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.1, -s * 0.38), Vector2(s * 0.2, s * 0.16)), c.darkened(0.3))
			ci.draw_arc(cx + Vector2(s * 0.18, -s * 0.34), s * 0.1, 0, TAU, 12, WHITE, 1.5)
		"boite", "boite_depart":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.45, s * 0.25), Vector2(s * 0.9, s * 0.5)), Color(0.35, 0.22, 0.1))
			ci.draw_rect(Rect2(cx - Vector2(s * 0.45, s * 0.25), Vector2(s * 0.9, s * 0.5)), c, false, 2.0)
			_text(ci, font, "?", cx, s * 0.5, c)
			if id == "boite_depart":
				_star(ci, p.position + Vector2(s * 0.85, s * 0.12), s * 0.16, WHITE)
		"pap":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.35, s * 0.45), Vector2(s * 0.7, s * 0.9)), c.darkened(0.3))
			ci.draw_rect(Rect2(cx - Vector2(s * 0.25, s * 0.1), Vector2(s * 0.5, s * 0.25)), Color(0.1, 0.9, 1.0))
			ci.draw_rect(Rect2(cx - Vector2(s * 0.35, s * 0.45), Vector2(s * 0.7, s * 0.9)), c.lightened(0.3), false, 2.0)
		"courant":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.3, s * 0.4), Vector2(s * 0.6, s * 0.8)), Color(0.25, 0.25, 0.27))
			_bolt(ci, cx, s * 0.7, c)
		"teleporteur", "arrivee":
			ci.draw_circle(cx, s * 0.42, c.darkened(0.5))
			ci.draw_arc(cx, s * 0.42, 0, TAU, 24, c, 3.0)
			ci.draw_arc(cx, s * 0.22, 0, TAU, 20, c, 2.0)
			if id == "arrivee":
				ci.draw_circle(cx, s * 0.08, WHITE)
		"poste_central":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.4, s * 0.35), Vector2(s * 0.8, s * 0.55)), Color(0.15, 0.2, 0.2))
			ci.draw_rect(Rect2(cx - Vector2(s * 0.32, s * 0.28), Vector2(s * 0.64, s * 0.4)), c.lightened(0.4))
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.1, s * 0.2), Vector2(s * 0.2, s * 0.25)), Color(0.15, 0.2, 0.2))
		"piege":
			ci.draw_rect(p, c.darkened(0.6))
			ci.draw_rect(p, c, false, 2.0)
			_bolt(ci, cx, s * 0.8, Color(0.6, 0.85, 1.0))
		"levier":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.25, s * 0.1), Vector2(s * 0.5, s * 0.5)), Color(0.3, 0.3, 0.32))
			ci.draw_line(cx + Vector2(0, s * 0.1), cx + Vector2(s * 0.25, -s * 0.4), c.lightened(0.3), s * 0.1)
			ci.draw_circle(cx + Vector2(s * 0.25, -s * 0.4), s * 0.09, c.lightened(0.3))
		"depart":
			ci.draw_circle(cx + Vector2(0, -s * 0.25), s * 0.15, c)
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.18, -s * 0.08), Vector2(s * 0.36, s * 0.3)), c)
			ci.draw_line(cx + Vector2(-s * 0.1, s * 0.2), cx + Vector2(-s * 0.18, s * 0.45), c, s * 0.1)
			ci.draw_line(cx + Vector2(s * 0.1, s * 0.2), cx + Vector2(s * 0.18, s * 0.45), c, s * 0.1)
		"apparition":
			ci.draw_rect(Rect2(p.position + Vector2(0, s * 0.72), Vector2(s, s * 0.28)), Color(0.3, 0.22, 0.14))
			for i in 4:
				ci.draw_line(cx + Vector2(s * (-0.2 + i * 0.13), s * 0.25), cx + Vector2(s * (-0.26 + i * 0.16), -s * 0.3), Color(0.45, 0.55, 0.35), s * 0.08)
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.25, s * 0.1), Vector2(s * 0.5, s * 0.2)), Color(0.45, 0.55, 0.35))
		"lampe":
			ci.draw_circle(cx + Vector2(0, s * 0.05), s * 0.28, c)
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.12, -s * 0.42), Vector2(s * 0.24, s * 0.2)), Color(0.4, 0.4, 0.42))
			for i in 6:
				var a := i * TAU / 6
				ci.draw_line(cx + Vector2(cos(a), sin(a)) * s * 0.36, cx + Vector2(cos(a), sin(a)) * s * 0.46, c, 1.5)
		"caisse":
			ci.draw_rect(Rect2(cx - Vector2(s, s) * 0.38, Vector2(s, s) * 0.76), c)
			ci.draw_rect(Rect2(cx - Vector2(s, s) * 0.38, Vector2(s, s) * 0.76), INK, false, 2.0)
			ci.draw_line(cx - Vector2(s, s) * 0.38, cx + Vector2(s, s) * 0.38, INK, 1.5)
			ci.draw_line(cx + Vector2(s, -s) * 0.38, cx + Vector2(-s, s) * 0.38, INK, 1.5)
		"baril":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.28, s * 0.42), Vector2(s * 0.56, s * 0.84)), c)
			for y in [-0.2, 0.2]:
				ci.draw_line(cx + Vector2(-s * 0.28, s * y), cx + Vector2(s * 0.28, s * y), c.darkened(0.5), 2.0)
		_:
			if id.begins_with("prefab:"):
				_prefab(ci, id.substr(7), p, cx, s, c)
			elif id.begins_with("luminaire:"):
				_light(ci, id.substr(10), p, cx, s, c)
			elif id.begins_with("atout:"):
				# Bouteille de la couleur de l'atout, initiale dessus.
				ci.draw_rect(Rect2(cx + Vector2(-s * 0.2, -s * 0.15), Vector2(s * 0.4, s * 0.6)), c)
				ci.draw_rect(Rect2(cx + Vector2(-s * 0.08, -s * 0.42), Vector2(s * 0.16, s * 0.3)), c.darkened(0.25))
				ci.draw_rect(Rect2(cx + Vector2(-s * 0.2, -s * 0.15), Vector2(s * 0.4, s * 0.6)), INK, false, 1.5)
				_text(ci, font, String(it.get("fr", "?")).substr(0, 1), cx + Vector2(0, s * 0.15), s * 0.34, INK)
			elif id.begins_with("arme:"):
				var knife := id == "arme:bowie" or KnifeDB.exists(id.substr(5))
				if knife:
					ci.draw_colored_polygon(PackedVector2Array([cx + Vector2(-s * 0.1, -s * 0.45), cx + Vector2(s * 0.08, -s * 0.1), cx + Vector2(-s * 0.08, s * 0.05)]), WHITE)
					ci.draw_line(cx + Vector2(-s * 0.02, s * 0.0), cx + Vector2(s * 0.1, s * 0.42), Color(0.4, 0.25, 0.12), s * 0.12)
				else:
					# Silhouette d'arme à la craie.
					ci.draw_line(cx + Vector2(-s * 0.45, -s * 0.12), cx + Vector2(s * 0.45, -s * 0.12), c, s * 0.1)
					ci.draw_line(cx + Vector2(-s * 0.45, -s * 0.05), cx + Vector2(-s * 0.2, -s * 0.05), c, s * 0.12)
					ci.draw_line(cx + Vector2(-s * 0.1, -s * 0.08), cx + Vector2(-s * 0.18, s * 0.2), c, s * 0.1)
					ci.draw_line(cx + Vector2(s * 0.08, -s * 0.08), cx + Vector2(s * 0.12, s * 0.12), c, s * 0.07)
				_text(ci, font, str(int(it.get("price", 0))), cx + Vector2(0, s * 0.42), s * 0.26, Color(1.0, 0.85, 0.4))
			else:
				ci.draw_rect(p, c)
	var price := int(it.get("price", 0))
	if price > 0 and (id.begins_with("atout:") or id in ["porte", "debris", "boite", "pap"]):
		_text(ci, font, str(price), r.position + Vector2(r.size.x * 0.5, r.size.y * 0.97), r.size.x * 0.22, Color(1.0, 0.85, 0.4))


## Icône d'un décor (MapCatalog.PREFABS), vu de dessus ou de face.
static func _prefab(ci: CanvasItem, kind: String, p: Rect2, cx: Vector2, s: float, c: Color) -> void:
	match kind:
		"gravats", "gros_gravats", "eboulis", "debris_epars":
			var n: int = {"gravats": 6, "gros_gravats": 8, "eboulis": 7, "debris_epars": 9}[kind]
			for i in n:
				var a: float = i * 2.4
				var r := s * (0.08 + fposmod(i * 0.37, 0.1)) * (0.6 if kind == "debris_epars" else 1.0)
				ci.draw_circle(cx + Vector2(cos(a), sin(a)) * s * (0.1 + fposmod(i * 0.23, 0.3)), r, c.lightened(fposmod(i * 0.13, 0.3)))
			if kind == "eboulis":
				ci.draw_rect(Rect2(cx + Vector2(-s * 0.45, -s * 0.4), Vector2(s * 0.3, s * 0.12)), c.darkened(0.3))
		"planches":
			for i in 3:
				ci.draw_line(cx + Vector2(-s * 0.42, -s * 0.25 + i * s * 0.22), cx + Vector2(s * 0.42, -s * 0.12 + i * s * 0.2), c.lightened(i * 0.1), s * 0.12)
		"poutre":
			ci.draw_line(cx + Vector2(-s * 0.45, s * 0.3), cx + Vector2(s * 0.45, -s * 0.25), c.lightened(0.2), s * 0.18)
			ci.draw_circle(cx + Vector2(s * 0.3, s * 0.3), s * 0.1, c.darkened(0.2))
			ci.draw_circle(cx + Vector2(-s * 0.3, -s * 0.2), s * 0.08, c.darkened(0.2))
		"lustre_tombe":
			ci.draw_arc(cx, s * 0.35, 0, TAU, 16, c, 2.0)
			for i in 6:
				var a := i * TAU / 6
				ci.draw_circle(cx + Vector2(cos(a), sin(a)) * s * 0.35, s * 0.06, Color(0.95, 0.95, 1.0))
			ci.draw_line(cx + Vector2(-s * 0.2, 0), cx + Vector2(s * 0.2, 0), c, 2.0)
		"caisses":
			for q in [[-0.22, 0.12, 0.34], [0.2, 0.15, 0.3], [0.0, -0.2, 0.3]]:
				var r := Rect2(cx + Vector2(q[0] - q[2] * 0.5, q[1] - q[2] * 0.5) * s, Vector2(q[2], q[2]) * s)
				ci.draw_rect(r, c)
				ci.draw_rect(r, INK, false, 1.5)
		"tonneaux":
			for q in [[-0.2, -0.15], [0.2, -0.12], [0.0, 0.2]]:
				ci.draw_circle(cx + Vector2(q[0], q[1]) * s, s * 0.17, c)
				ci.draw_arc(cx + Vector2(q[0], q[1]) * s, s * 0.17, 0, TAU, 14, INK, 1.5)
		"sacs_sable":
			for row in 3:
				for i in 3 - (row % 2):
					var r := Rect2(cx + Vector2(-s * 0.42 + i * s * 0.3 + (row % 2) * s * 0.15, s * (0.12 - row * 0.2)), Vector2(s * 0.27, s * 0.17))
					ci.draw_rect(r, c)
					ci.draw_rect(r, c.darkened(0.4), false, 1.0)
		"table_renversee":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.45, s * 0.08), Vector2(s * 0.9, s * 0.14)), c)
			for sx in [-0.35, 0.35]:
				ci.draw_line(cx + Vector2(s * sx, s * 0.08), cx + Vector2(s * sx, -s * 0.35), c.lightened(0.2), s * 0.06)
		"chaise_renversee", "chaise":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.22, -s * 0.05), Vector2(s * 0.44, s * 0.08)), c)
			ci.draw_line(cx + Vector2(-s * 0.2, -s * 0.05), cx + Vector2(-s * 0.2, -s * 0.42), c, s * 0.06)
			for sx in [-0.2, 0.2]:
				ci.draw_line(cx + Vector2(s * sx, s * 0.03), cx + Vector2(s * sx, s * 0.38), c.lightened(0.2), s * 0.05)
			if kind == "chaise_renversee":
				ci.draw_line(cx + Vector2(-s * 0.4, s * 0.42), cx + Vector2(s * 0.4, s * 0.42), INK, 1.0)
		"bureau", "pupitre":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.42, -s * 0.12), Vector2(s * 0.84, s * 0.1)), c.lightened(0.2))
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.4, -s * 0.02), Vector2(s * 0.25, s * 0.38)), c)
			ci.draw_line(cx + Vector2(s * 0.36, -s * 0.02), cx + Vector2(s * 0.36, s * 0.36), c, s * 0.06)
		"etagere":
			ci.draw_rect(Rect2(cx - Vector2(s * 0.35, s * 0.42), Vector2(s * 0.7, s * 0.84)), c.darkened(0.2), false, 2.0)
			for i in 3:
				ci.draw_line(cx + Vector2(-s * 0.35, -s * 0.15 + i * s * 0.2), cx + Vector2(s * 0.35, -s * 0.15 + i * s * 0.2), c.lightened(0.2), 2.0)
				ci.draw_circle(cx + Vector2(-s * 0.18 + i * s * 0.16, -s * 0.24 + i * s * 0.2), s * 0.06, Color(0.2, 0.2, 0.22))
		"fauteuils", "fauteuil_casse":
			var n := 3 if kind == "fauteuils" else 1
			for i in n:
				var x := (i - (n - 1) * 0.5) * s * 0.3
				ci.draw_rect(Rect2(cx + Vector2(x - s * 0.13, -s * 0.3), Vector2(s * 0.26, s * 0.4)), c)
				ci.draw_rect(Rect2(cx + Vector2(x - s * 0.13, s * 0.1), Vector2(s * 0.26, s * 0.12)), c.darkened(0.3))
		"projecteur_film":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.25, -s * 0.2), Vector2(s * 0.45, s * 0.3)), c.lightened(0.2))
			ci.draw_circle(cx + Vector2(-s * 0.1, -s * 0.32), s * 0.12, c)
			ci.draw_circle(cx + Vector2(s * 0.15, -s * 0.32), s * 0.12, c)
			ci.draw_line(cx + Vector2(0, s * 0.1), cx + Vector2(0, s * 0.42), c, s * 0.08)
		"chariot":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.4, -s * 0.2), Vector2(s * 0.8, s * 0.35)), c, false, 2.0)
			ci.draw_line(cx + Vector2(-s * 0.4, -s * 0.02), cx + Vector2(s * 0.4, -s * 0.02), c, 2.0)
			for sx in [-0.3, 0.3]:
				ci.draw_circle(cx + Vector2(s * sx, s * 0.25), s * 0.08, INK)
		"epave_voiture":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.46, -s * 0.05), Vector2(s * 0.92, s * 0.22)), c)
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.26, -s * 0.24), Vector2(s * 0.46, s * 0.2)), c.darkened(0.15))
			for sx in [-0.28, 0.28]:
				ci.draw_circle(cx + Vector2(s * sx, s * 0.2), s * 0.1, INK)
		_:
			ci.draw_rect(p.grow(-s * 0.1), c)


## Icône d'un luminaire (MapCatalog.LIGHTS).
static func _light(ci: CanvasItem, kind: String, _p: Rect2, cx: Vector2, s: float, c: Color) -> void:
	var glow := Color(1.0, 0.9, 0.55)
	match kind:
		"ampoule":
			ci.draw_line(cx + Vector2(0, -s * 0.45), cx + Vector2(0, -s * 0.1), Color(0.3, 0.3, 0.3), 1.5)
			ci.draw_circle(cx + Vector2(0, s * 0.08), s * 0.2, glow)
		"suspension":
			ci.draw_line(cx + Vector2(0, -s * 0.45), cx + Vector2(0, -s * 0.18), Color(0.3, 0.3, 0.3), 1.5)
			ci.draw_colored_polygon(PackedVector2Array([cx + Vector2(-s * 0.08, -s * 0.2), cx + Vector2(s * 0.08, -s * 0.2),
				cx + Vector2(s * 0.35, s * 0.1), cx + Vector2(-s * 0.35, s * 0.1)]), c.darkened(0.3))
			ci.draw_circle(cx + Vector2(0, s * 0.14), s * 0.1, glow)
		"neon":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.45, -s * 0.12), Vector2(s * 0.9, s * 0.24)), Color(0.35, 0.36, 0.38))
			ci.draw_line(cx + Vector2(-s * 0.4, -s * 0.03), cx + Vector2(s * 0.4, -s * 0.03), Color(0.85, 0.95, 1.0), s * 0.07)
			ci.draw_line(cx + Vector2(-s * 0.4, s * 0.05), cx + Vector2(s * 0.4, s * 0.05), Color(0.85, 0.95, 1.0), s * 0.07)
		"lustre":
			ci.draw_arc(cx + Vector2(0, s * 0.05), s * 0.32, 0, PI, 14, c, 2.0)
			for i in 5:
				var a := PI * (0.1 + i * 0.2)
				ci.draw_circle(cx + Vector2(0, s * 0.05) + Vector2(cos(a), sin(a)) * s * 0.32, s * 0.06, glow)
			ci.draw_line(cx + Vector2(0, -s * 0.45), cx + Vector2(0, s * 0.05), c, 1.5)
		"applique":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.45, -s * 0.35), Vector2(s * 0.12, s * 0.7)), Color(0.4, 0.4, 0.42))
			ci.draw_line(cx + Vector2(-s * 0.33, 0), cx + Vector2(0, -s * 0.05), c, s * 0.06)
			ci.draw_circle(cx + Vector2(s * 0.08, -s * 0.08), s * 0.16, glow)
		"lampe_bureau":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.2, s * 0.32), Vector2(s * 0.4, s * 0.08)), Color(0.75, 0.6, 0.25))
			ci.draw_line(cx + Vector2(0, s * 0.32), cx + Vector2(-s * 0.12, -s * 0.05), Color(0.75, 0.6, 0.25), 2.0)
			ci.draw_colored_polygon(PackedVector2Array([cx + Vector2(-s * 0.18, -s * 0.15), cx + Vector2(0.0, -s * 0.3),
				cx + Vector2(s * 0.3, 0.0), cx + Vector2(s * 0.1, s * 0.08)]), c)
			ci.draw_circle(cx + Vector2(s * 0.12, s * 0.02), s * 0.07, glow)
		"projecteur":
			for sx in [-0.3, 0.0, 0.3]:
				ci.draw_line(cx + Vector2(0, -s * 0.05), cx + Vector2(s * sx, s * 0.42), Color(0.55, 0.55, 0.58), 1.5)
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.25, -s * 0.38), Vector2(s * 0.5, s * 0.32)), Color(0.55, 0.12, 0.08))
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.2, -s * 0.33), Vector2(s * 0.4, s * 0.22)), glow)
		"bougies":
			for q in [[-0.18, 0.3], [0.0, 0.2], [0.18, 0.12]]:
				ci.draw_rect(Rect2(cx + Vector2(q[0] - 0.05, 0.4 - q[1] * 1.3) * s, Vector2(0.1, q[1] * 1.3) * s), Color(0.9, 0.86, 0.75))
				ci.draw_circle(cx + Vector2(q[0], 0.4 - q[1] * 1.3 - 0.06) * s, s * 0.05, Color(1.0, 0.6, 0.2))
		"feu":
			ci.draw_rect(Rect2(cx + Vector2(-s * 0.25, -s * 0.05), Vector2(s * 0.5, s * 0.45)), Color(0.35, 0.22, 0.15))
			for q in [[-0.12, 0.3], [0.0, 0.45], [0.12, 0.32]]:
				ci.draw_colored_polygon(PackedVector2Array([cx + Vector2(q[0] - 0.1, -0.05) * s, cx + Vector2(q[0] + 0.1, -0.05) * s,
					cx + Vector2(q[0], -0.05 - q[1]) * s]), Color(1.0, 0.5, 0.1))
		_:
			ci.draw_circle(cx, s * 0.3, glow)


## Aperçu d'une surface du jeu (WorldLook.SURFACES) : petite image dessinée
## d'après ses deux couleurs et son motif (carrelage, bois, brique...), un peu
## éclaircie pour rester lisible. Gardée en mémoire.
static var _surface_tex: Dictionary = {}


static func surface_texture(key: String) -> ImageTexture:
	if _surface_tex.has(key):
		return _surface_tex[key]
	var look := MapCatalog.surface_look(key)
	var a: Color = (look[0] as Color) * 2.1
	var b: Color = (look[1] as Color) * 2.1
	a.a = 1.0
	b.a = 1.0
	var w := 40
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(a)
	var pat: int = look[2]
	for y in h:
		for x in w:
			var n := fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
			var c := a
			match pat:
				0, 4, 5:   # béton, plâtre, pierre : taches
					c = a.lerp(b, n * (0.45 if pat == 0 else 0.3))
					@warning_ignore("integer_division")
					if pat == 5 and (y % 8 == 0 or (x + (y / 8) * 5) % 12 == 0):
						c = b
				1:   # carrelage
					c = b if x % 8 == 0 or y % 8 == 0 else a.lerp(b, n * 0.12)
				2:   # bois : lames
					@warning_ignore("integer_division")
					c = b if y % 6 == 0 or (x + (y / 6) * 13) % 20 == 0 else a.lerp(b, 0.25 + 0.2 * sin(x * 0.7 + y))
				3:   # métal : rivets, brossé
					c = a.lerp(b, 0.1 + 0.2 * fposmod(y * 0.37, 1.0))
					if (x % 10 == 2 and y % 10 == 2):
						c = b
				6:   # plafond : dalles
					c = b if x % 10 == 0 or y % 10 == 0 else a
				7:   # moquette : losanges
					c = b if (x + y) % 8 == 0 or (x - y + 64) % 8 == 0 else a.lerp(b, n * 0.2)
				8:   # papier peint : rayures
					c = b if x % 6 < 2 else a
				9:   # brique
					@warning_ignore("integer_division")
					var row := y / 5
					c = b if y % 5 == 0 or (x + (row % 2) * 5) % 10 == 0 else a.lerp(b, n * 0.15)
				10:   # velours : plis
					c = a.lerp(b, 0.5 + 0.5 * sin(x * 0.8))
				11:   # pavés
					var cx := x % 8 - 4
					var cy := y % 8 - 4
					c = b if cx * cx + cy * cy > 12 else a.lerp(b, n * 0.2)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_surface_tex[key] = tex
	return tex


static func _text(ci: CanvasItem, font: Font, s: String, center: Vector2, size: float, col: Color) -> void:
	# Jamais plus petit que 8 px à 100 % (taille de l'interface : EditorUi).
	var fs := maxi(EditorUi.fs(8), int(size))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(font, center + Vector2(-w * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
	ci.draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _bolt(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(s * 0.1, -s * 0.5), c + Vector2(-s * 0.2, s * 0.05), c + Vector2(0, s * 0.05),
		c + Vector2(-s * 0.1, s * 0.5), c + Vector2(s * 0.2, -s * 0.05), c + Vector2(0, -s * 0.05)])
	ci.draw_colored_polygon(pts, col)


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)
