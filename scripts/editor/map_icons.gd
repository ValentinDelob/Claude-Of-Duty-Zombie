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
			if id.begins_with("atout:"):
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


static func _text(ci: CanvasItem, font: Font, s: String, center: Vector2, size: float, col: Color) -> void:
	var fs := maxi(8, int(size))
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
