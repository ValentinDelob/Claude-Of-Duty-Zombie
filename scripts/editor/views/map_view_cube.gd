class_name MapViewCube
extends Control
## ViewCube de l'éditeur de cartes (docs/EDITOR_VIEWS.md, § 4 ; maquette :
## cubeNet / cubeIso). En haut à droite de chaque vue :
##   - vue orthographique : la face courante de face (carré étiqueté), ses 4
##     faces voisines en bandes trapézoïdales autour (cliquables : bascule du
##     plan), 4 petits coins (passage en 3D vue de ce coin), maison (vue
##     d'origine de la fenêtre), menu ▾, flèches ◄ ► (façade suivante, vues
##     de côté) ou rose N, E, S, O (vue Dessus) ;
##   - vue 3D : cube isométrique qui suit la caméra ; ses faces visibles
##     (bascule vers ce plan), arêtes et coins (caméra placée sur cette
##     direction) sont cliquables.
## Survol : fond #4D4233, bord #D99940, bulle d'aide. Étiquettes dans la
## langue du jeu. Les tailles de la maquette sont à 100 % d'interface.

signal target_clicked(id: String)

## Net : face (S), bandes (D), total (T = S + 2 D), à 100 %.
const S := 40.0
const D := 11.0
const COL_FACE := Color("2A2B2F")
const COL_FACE_LINE := Color("4D4D54")
const COL_CUR := Color("3A3B40")
const COL_CUR_LINE := Color("6a6a72")
const COL_HOVER := Color("4D4233")
const COL_HOVER_LINE := Color("D99940")
const COL_CORNER := Color("323338")
const COL_CORNER_LINE := Color("55555c")
const COL_ICON := Color("A9A291")
const COL_BONE := Color("DBD1B8")

## Voisins d'une face dans le net : [haut, bas, gauche, droite] à l'écran.
const NEIGH := {
	"dessus": ["arriere", "avant", "gauche", "droite"],
	"dessous": ["arriere", "avant", "droite", "gauche"],
	"avant": ["dessus", "dessous", "gauche", "droite"],
	"arriere": ["dessus", "dessous", "droite", "gauche"],
	"droite": ["dessus", "dessous", "avant", "arriere"],
	"gauche": ["dessus", "dessous", "arriere", "avant"],
}
## Tour des façades (flèche ► ; ◄ : à l'envers).
const FACADES := ["avant", "droite", "arriere", "gauche"]
## Direction de chaque face (repère de la carte : x est, y sud, z haut), du
## centre vers la caméra.
const FACE_DIR := {"dessus": Vector3(0, 0, 1), "dessous": Vector3(0, 0, -1), "avant": Vector3(0, 1, 0),
	"arriere": Vector3(0, -1, 0), "droite": Vector3(1, 0, 0), "gauche": Vector3(-1, 0, 0)}

## Vue ortho : plan montré ("3d" : cube isométrique).
var plane := "dessus"
## Vue 3D : direction de la caméra (repère de la carte, du centre vers la
## caméra) et bases de l'écran qui en découlent (droite, haut).
var cam_back := Vector3(1, 1, 1).normalized()
var cam_right := Vector3(1, -1, 0).normalized()
var cam_up := Vector3(-1, -1, 2).normalized()
## Oriente le cube isométrique : `back` = du centre vers la caméra (repère de
## la carte). Sans roulis : le haut de l'écran reste vers Z.
func set_view_dir(back: Vector3) -> void:
	if back.length() < 0.001:
		return
	back = back.normalized()
	var r := back.cross(Vector3(0, 0, 1))
	if r.length() < 0.001:
		r = Vector3(1, 0, 0)
	cam_back = back
	cam_right = r.normalized()
	cam_up = cam_right.cross(back).normalized()
	queue_redraw()


## Fenêtre active (opacité 100 %, sinon 75 % ; 100 % au survol).
var active := true
var hover := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func u(v: float) -> float:
	return v * EditorUi.factor()


## Taille du contrôle (px) : le net, la maison à gauche, les flèches dessous.
func wanted_size() -> Vector2:
	return Vector2(u(S + 2 * D + 30), u(S + 2 * D + 34))


## Origine (px) du net dans le contrôle.
func _net_origin() -> Vector2:
	return Vector2(u(20), u(10))


# ------------------------------------------------------------------ cibles

## Directions (repère de la carte) des 26 cibles d'un cube : 6 faces, 12
## arêtes, 8 coins. Identifiants : « f:avant », « e:avant+droite »,
## « c:avant+droite+dessus ».
static func all_targets() -> Dictionary:
	var out := {}
	var faces := FACE_DIR.keys()
	for f in faces:
		out["f:" + String(f)] = FACE_DIR[f]
	for i in faces.size():
		for j in range(i + 1, faces.size()):
			var a: Vector3 = FACE_DIR[faces[i]]
			var b: Vector3 = FACE_DIR[faces[j]]
			if a.dot(b) == 0.0:
				out["e:" + _key([faces[i], faces[j]])] = (a + b).normalized()
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var names := ["droite" if sx > 0 else "gauche", "avant" if sy > 0 else "arriere", "dessus" if sz > 0 else "dessous"]
				out["c:" + _key(names)] = Vector3(sx, sy, sz).normalized()
	return out


static func _key(names: Array) -> String:
	var order := ["avant", "arriere", "droite", "gauche", "dessus", "dessous"]
	var l := names.duplicate()
	l.sort_custom(func(a, b): return order.find(a) < order.find(b))
	return "+".join(l)


## Direction (repère de la carte) d'une cible ; Vector3.ZERO si inconnue.
static func target_dir(id: String) -> Vector3:
	return all_targets().get(id, Vector3.ZERO)


## Cible d'un coin du net : le coin de la face courante entre deux voisines.
static func net_corner(face: String, corner: int) -> String:
	# corner : 0 haut-gauche, 1 haut-droite, 2 bas-gauche, 3 bas-droite.
	var n: Array = NEIGH[face]
	var v: String = n[0] if corner < 2 else n[1]
	var h: String = n[2] if corner % 2 == 0 else n[3]
	return "c:" + _key([face, v, h])


## Façade suivante (◄ : sens = -1, ► : +1) ; une vue Dessus ou Dessous n'en a pas.
static func next_facade(face: String, dir: int) -> String:
	var i := FACADES.find(face)
	if i < 0:
		return face
	return FACADES[posmod(i + dir, FACADES.size())]


## Polygones (px, dans le contrôle) des cibles du net : [{id, poly}] ; la
## face courante d'abord.
func net_shapes() -> Array:
	var o := _net_origin()
	var s := u(S)
	var d := u(D)
	var t := s + 2.0 * d
	var n: Array = NEIGH.get(plane, NEIGH.dessus)
	var x := o.x
	var y := o.y
	var out := [{"id": "cur", "poly": PackedVector2Array([Vector2(x + d, y + d), Vector2(x + d + s, y + d), Vector2(x + d + s, y + d + s), Vector2(x + d, y + d + s)])}]
	out.append({"id": "f:" + String(n[0]), "poly": PackedVector2Array([Vector2(x, y), Vector2(x + t, y), Vector2(x + d + s, y + d), Vector2(x + d, y + d)])})
	out.append({"id": "f:" + String(n[1]), "poly": PackedVector2Array([Vector2(x + d, y + d + s), Vector2(x + d + s, y + d + s), Vector2(x + t, y + t), Vector2(x, y + t)])})
	out.append({"id": "f:" + String(n[2]), "poly": PackedVector2Array([Vector2(x, y), Vector2(x + d, y + d), Vector2(x + d, y + d + s), Vector2(x, y + t)])})
	out.append({"id": "f:" + String(n[3]), "poly": PackedVector2Array([Vector2(x + t, y), Vector2(x + t, y + t), Vector2(x + d + s, y + d + s), Vector2(x + d + s, y + d)])})
	var c := u(6)
	var corners := [Vector2(x, y), Vector2(x + t - c, y), Vector2(x, y + t - c), Vector2(x + t - c, y + t - c)]
	for i in 4:
		var p: Vector2 = corners[i]
		out.append({"id": net_corner(plane, i), "poly": PackedVector2Array([p, p + Vector2(c, 0), p + Vector2(c, c), p + Vector2(0, c)]), "corner": true})
	# Maison, menu, flèches de façade.
	out.append({"id": "home", "poly": _rect_poly(Rect2(Vector2(x - u(17), y + u(1)), Vector2(u(15), u(15))))})
	out.append({"id": "menu", "poly": _rect_poly(Rect2(Vector2(x + t + u(1), y + t - u(10)), Vector2(u(12), u(14))))})
	if plane in FACADES:
		out.append({"id": "prev", "poly": _rect_poly(Rect2(Vector2(x, y + t + u(3)), Vector2(u(12), u(12))))})
		out.append({"id": "next", "poly": _rect_poly(Rect2(Vector2(x + t - u(12), y + t + u(3)), Vector2(u(12), u(12))))})
	return out


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Cube isométrique (vue 3D) : centre et demi-côté (px).
func _iso_center() -> Vector2:
	return Vector2(size.x * 0.5, u(44))


## Projection (px) d'un point du cube unité (coordonnées de la carte, -0,5 à 0,5).
func iso_px(p: Vector3) -> Vector2:
	var a := u(22)
	return _iso_center() + Vector2(p.dot(cam_right), -p.dot(cam_up)) * a * 1.6


## Cibles du cube isométrique visibles (faces vers la caméra), les plus
## petites d'abord (coins, arêtes, faces) : [{id, poly | seg | pt}].
func iso_shapes() -> Array:
	var view := cam_back
	var out := []
	var targets := all_targets()
	var faces := []
	for id in targets:
		var dir: Vector3 = targets[id]
		if id.begins_with("f:") and dir.dot(view) > 0.05:
			var f: String = id.substr(2)
			faces.append(f)
			out.append({"id": id, "poly": _face_poly(dir), "depth": dir.dot(view)})
	# Arêtes entre deux faces visibles (ou au bord) et coins visibles.
	for id in targets:
		var dir: Vector3 = targets[id]
		if id.begins_with("e:"):
			var parts: PackedStringArray = id.substr(2).split("+")
			if not (parts[0] in faces or parts[1] in faces):
				continue
			var a: Vector3 = FACE_DIR[parts[0]] * 0.5 + FACE_DIR[parts[1]] * 0.5
			var t: Vector3 = FACE_DIR[parts[0]].cross(FACE_DIR[parts[1]]) * 0.5
			out.push_front({"id": id, "seg": [iso_px(a - t), iso_px(a + t)]})
		elif id.begins_with("c:"):
			var parts: PackedStringArray = id.substr(2).split("+")
			if not Array(parts).any(func(p): return p in faces):
				continue
			out.push_front({"id": id, "pt": iso_px(dir * 0.5 * sqrt(3.0))})
	out.append({"id": "home", "poly": _rect_poly(Rect2(_iso_center() + Vector2(-u(48), -u(36)), Vector2(u(15), u(15))))})
	return out


func _face_poly(n: Vector3) -> PackedVector2Array:
	# Deux axes du plan de la face.
	var a := Vector3(n.z, n.x, n.y) * 0.5
	var b := n.cross(a * 2.0) * 0.5
	var c := n * 0.5
	return PackedVector2Array([iso_px(c - a - b), iso_px(c + a - b), iso_px(c + a + b), iso_px(c - a + b)])


## Cible sous le pixel `p` (repère du contrôle) ; "" sinon.
func target_at(p: Vector2) -> String:
	var shapes := iso_shapes() if plane == "3d" else net_shapes()
	for sh in shapes:
		if sh.has("pt"):
			if (sh.pt as Vector2).distance_to(p) <= u(5):
				return String(sh.id)
		elif sh.has("seg"):
			if Geometry2D.get_closest_point_to_segment(p, sh.seg[0], sh.seg[1]).distance_to(p) <= u(3.5):
				return String(sh.id)
	# Coins du net d'abord (dessus des bandes), puis le reste.
	for sh in shapes:
		if sh.has("poly") and bool(sh.get("corner", false)) and Geometry2D.is_point_in_polygon(p, sh.poly):
			return String(sh.id)
	for sh in shapes:
		if sh.has("poly") and not bool(sh.get("corner", false)) and Geometry2D.is_point_in_polygon(p, sh.poly):
			return String(sh.id)
	return ""


func _has_point(p: Vector2) -> bool:
	return target_at(p) != ""


## Nom d'une cible pour la bulle d'aide (« DESSUS · pavé 7 »).
static func target_name(id: String) -> String:
	if id.begins_with("f:"):
		var f := id.substr(2)
		var key := {"dessus": "7", "avant": "1", "droite": "3", "dessous": "Ctrl+7", "arriere": "Ctrl+1", "gauche": "Ctrl+3"}
		return "%s · %s" % [MapView.plane_name(f), Lang.t("pavé %s", "numpad %s") % String(key.get(f, ""))]
	if id.begins_with("e:") or id.begins_with("c:"):
		var names := Array(id.substr(2).split("+")).map(func(x): return MapView.plane_name(String(x)).to_lower())
		return Lang.t("3D : %s", "3D: %s") % "-".join(names)
	match id:
		"home":
			return Lang.t("Vue d'origine de la fenêtre", "This window's home view")
		"menu":
			return Lang.t("Plans, vue d'origine, recadrer", "Planes, home view, frame")
		"prev":
			return Lang.t("Façade précédente", "Previous side")
		"next":
			return Lang.t("Façade suivante", "Next side")
	return ""


# ------------------------------------------------------------------ entrées

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := target_at((event as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			tooltip_text = target_name(h)
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var t := target_at(mb.position)
			if t != "" and t != "cur":
				target_clicked.emit(t)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != "":
		hover = ""
		queue_redraw()


# ------------------------------------------------------------------ dessin

func _draw() -> void:
	modulate.a = 1.0 if active or hover != "" else 0.75
	if plane == "3d":
		_draw_iso()
	else:
		_draw_net()


func _fill(shape: Dictionary, base: Color, line: Color) -> void:
	var hov := hover == String(shape.id)
	draw_colored_polygon(shape.poly, COL_HOVER if hov else base)
	var p: PackedVector2Array = shape.poly
	draw_polyline(p + PackedVector2Array([p[0]]), COL_HOVER_LINE if hov else line, 1.0)


func _draw_net() -> void:
	var shapes := net_shapes()
	var font := MapView.bold_font(700)
	for sh in shapes:
		var id := String(sh.id)
		if id.begins_with("f:"):
			_fill(sh, COL_FACE, COL_FACE_LINE)
	_fill(shapes[0], COL_CUR, COL_CUR_LINE)
	for sh in shapes:
		if bool(sh.get("corner", false)):
			var hov := hover == String(sh.id)
			draw_colored_polygon(sh.poly, COL_HOVER if hov else COL_CORNER)
			var p: PackedVector2Array = sh.poly
			draw_polyline(p + PackedVector2Array([p[0]]), COL_HOVER_LINE if hov else COL_CORNER_LINE, 0.8)
	# Nom de la face courante.
	var name := MapView.plane_name(plane)
	var fs := MapView._fs(7.5 if name.length() > 6 else 8.5)
	var c: Vector2 = (shapes[0].poly[0] + shapes[0].poly[2]) * 0.5
	var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.38), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_BONE)
	var o := _net_origin()
	var t := u(S + 2 * D)
	# Maison.
	_draw_home(Vector2(o.x - u(15), o.y + u(8)), hover == "home")
	# Menu ▾.
	var mf := UiStyle.font("body")
	draw_string(mf, Vector2(o.x + t + u(3), o.y + t + u(1)), "▾", HORIZONTAL_ALIGNMENT_LEFT, -1, MapView._fs(11), COL_HOVER_LINE if hover == "menu" else COL_ICON)
	if plane in FACADES:
		var y := o.y + t + u(9)
		draw_colored_polygon(PackedVector2Array([Vector2(o.x + u(2), y), Vector2(o.x + u(9), y - u(4)), Vector2(o.x + u(9), y + u(4))]), COL_HOVER_LINE if hover == "prev" else COL_ICON)
		draw_colored_polygon(PackedVector2Array([Vector2(o.x + t - u(2), y), Vector2(o.x + t - u(9), y - u(4)), Vector2(o.x + t - u(9), y + u(4))]), COL_HOVER_LINE if hover == "next" else COL_ICON)
	elif plane == "dessus":
		# Rose : N au-dessus (en gras), S, E, O autour.
		var rf := MapView._fs(9)
		_center_text(font, Vector2(o.x + t * 0.5, o.y - u(4)), Lang.t("N", "N"), rf, COL_BONE)
		_center_text(mf, Vector2(o.x + t * 0.5, o.y + t + u(11)), Lang.t("S", "S"), rf, COL_ICON)
		_center_text(mf, Vector2(o.x + t + u(7), o.y + t * 0.5 + u(3)), Lang.t("E", "E"), rf, COL_ICON)
		_center_text(mf, Vector2(o.x - u(7), o.y + t * 0.5 + u(3)), Lang.t("O", "W"), rf, COL_ICON)


func _center_text(font: Font, at: Vector2, txt: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_home(at: Vector2, hov: bool) -> void:
	var col := COL_HOVER_LINE if hov else COL_ICON
	var pts := PackedVector2Array([at, at + Vector2(u(6), -u(5.5)), at + Vector2(u(12), 0), at + Vector2(u(12), u(6)), at + Vector2(0, u(6)), at])
	draw_polyline(pts, col, 1.2)
	draw_rect(Rect2(at + Vector2(u(4), u(2)), Vector2(u(4), u(4))), col)


func _draw_iso() -> void:
	var shapes := iso_shapes()
	var faces := shapes.filter(func(s): return s.has("poly") and String(s.id).begins_with("f:"))
	faces.sort_custom(func(a, b): return float(a.depth) < float(b.depth))
	var font := MapView.bold_font(700)
	var shade := {"f:dessus": Color("34353a"), "f:dessous": Color("222326")}
	for f in faces:
		_fill(f, shade.get(String(f.id), Color("2c2d31")), COL_CUR_LINE)
		var p: PackedVector2Array = f.poly
		var c := (p[0] + p[2]) * 0.5
		var name := MapView.plane_name(String(f.id).substr(2))
		var fs := MapView._fs(6.5)
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if (p[1] - p[0]).length() > w * 0.8:
			draw_string(font, c + Vector2(-w * 0.5, fs * 0.38), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_BONE)
	for sh in shapes:
		if sh.has("seg") and hover == String(sh.id):
			draw_line(sh.seg[0], sh.seg[1], COL_HOVER_LINE, 3.0)
		elif sh.has("pt"):
			draw_circle(sh.pt, u(3), COL_HOVER_LINE if hover == String(sh.id) else COL_CORNER_LINE)
	var hc := _iso_center() + Vector2(-u(48), -u(30))
	_draw_home(hc, hover == "home")
