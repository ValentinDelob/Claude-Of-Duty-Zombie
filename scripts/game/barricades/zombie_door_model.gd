class_name ZombieDoorModel
extends RefCounted
## Modèle d'une porte à zombies (format 8 des cartes ; docs/MAP_OBJECTS.md
## § 9) : bâti (montants, traverse, chambranle, seuil) et battant(s) cassé(s)
## à mi-hauteur — seule la moitié basse reste sur ses gonds, planches aux
## bouts éclatés, le haut vide : les zombies l'enjambent comme l'allège d'une
## fenêtre — dans le plan de la face INTÉRIEURE du mur. Les planches de la barricade
## (Barricade, animées) sont clouées devant, dans la même tranche.
##
## Règle « vraie porte » : tout l'assemblage (bâti, battants, planches) tient
## dans une tranche de 10 cm (ENVELOPE) ; le reste de l'épaisseur du mur est
## l'embrasure, côté dehors (la cour des zombies). Vue de la salle, la porte
## est presque à fleur du mur, pas au fond d'un trou.
##
## Repère local de la Barricade : +Z vers l'intérieur, X le long du mur, Y en
## haut, origine au sol au milieu du mur. Construit par le jeu (aucun fichier
## importé, aucun élément graphique d'Activision), surfaces WorldLook ;
## aspect déterministe (graine de la fenêtre) sur toutes les machines.

## Tranche de l'assemblage (z local) : de l'arrière du bâti au chambranle.
const Z_BACK := 0.16
const Z_FRONT := 0.26
const ENVELOPE := Z_FRONT - Z_BACK
## Montants et traverse du bâti (largeur vue de face, profondeur).
const FRAME_W := 0.07
const FRAME_Z := Vector2(0.16, 0.24)
## Chambranle (moulure sur la face du mur, autour de l'ouverture).
const CASING_W := 0.075
const CASING_Z := Vector2(0.245, 0.26)
## Battant : planches verticales et traverses (barres), côté dehors.
const LEAF_Z := Vector2(0.18, 0.205)
const LEDGE_Z := Vector2(0.162, 0.18)
const STRAP_Z := Vector2(0.205, 0.209)
## Planches de la barricade (Barricade : plan des planches d'une porte).
const BOARD_Z := Vector2(0.21, 0.252)
## Haut moyen des battants cassés à mi-hauteur (bouts éclatés à ±10 cm) :
## hauteur de l'allège d'une fenêtre, que les zombies enjambent pareil.
const LEAF_TOP := 0.95


## Assemblage complet (nœud « DoorAssembly ») d'une porte de type `kind`
## (BarricadeRules.DOOR / DOUBLE_DOOR), de largeur `width` (m) et de hauteur
## `height` (haut de l'ouverture), graine `seed_v`.
static func build(kind: String, width: float, height: float, seed_v: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DoorAssembly"
	var parts := {}  # matériau -> SurfaceTool
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 101
	var hw := width * 0.5
	# --- Bâti : montants, traverse, seuil, chambranle -----------------------
	var fz := (FRAME_Z.x + FRAME_Z.y) * 0.5
	var fd := FRAME_Z.y - FRAME_Z.x
	for sx in [-1.0, 1.0]:
		_box(parts, "frame", Vector3(FRAME_W, height, fd), Vector3(sx * (hw - FRAME_W * 0.5), height * 0.5, fz))
	_box(parts, "frame", Vector3(width, FRAME_W, fd), Vector3(0, height - FRAME_W * 0.5, fz))
	_box(parts, "frame", Vector3(width, 0.025, ENVELOPE), Vector3(0, 0.0125, (Z_BACK + Z_FRONT) * 0.5))
	var cz := (CASING_Z.x + CASING_Z.y) * 0.5
	var cd := CASING_Z.y - CASING_Z.x
	for sx in [-1.0, 1.0]:
		_box(parts, "casing", Vector3(CASING_W, height + CASING_W, cd), Vector3(sx * (hw + CASING_W * 0.5), (height + CASING_W) * 0.5, cz))
		# Socle du chambranle (plinthe), un peu plus épais.
		_box(parts, "frame", Vector3(CASING_W + 0.01, 0.16, cd), Vector3(sx * (hw + CASING_W * 0.5), 0.08, cz))
	_box(parts, "casing", Vector3(width + CASING_W * 2.0 + 0.04, CASING_W, cd), Vector3(0, height + CASING_W * 0.5, cz))
	# --- Battant(s) : cassés à mi-hauteur, le haut vide (on enjambe) --------
	var clear := width - FRAME_W * 2.0
	var top_hinge := height - FRAME_W - 0.3
	if kind == BarricadeRules.DOUBLE_DOOR:
		var lw := clear * 0.5 - 0.01
		_half_leaf(parts, rng, Vector2(-clear * 0.5, 0.03), lw, 1.0)
		_half_leaf(parts, rng, Vector2(clear * 0.5, 0.03), lw, -1.0)
		_torn_strap(parts, rng, Vector2(-clear * 0.5, top_hinge), 1.0)
		_torn_strap(parts, rng, Vector2(clear * 0.5, top_hinge), -1.0)
	else:
		_half_leaf(parts, rng, Vector2(-clear * 0.5, 0.03), clear - 0.02, 1.0)
		_torn_strap(parts, rng, Vector2(-clear * 0.5, top_hinge), 1.0)
	for key in parts:
		var st: SurfaceTool = parts[key]
		var mi := MeshInstance3D.new()
		mi.name = "Door_" + String(key)
		mi.mesh = st.commit()
		mi.material_override = material(String(key))
		# Comme les planches : pas d'ombre portée (cubemaps des lampes).
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 40.0
		root.add_child(mi)
	return root


## Teintes des bois de la porte : battant (deux tons de planches peintes,
## peinture vert-de-gris écaillée sur bois brun), bâti et chambranle (brun
## sombre), distinctes du gris délavé des planches de la barricade.
const TINTS := {
	"leaf_a": Color(0.4, 0.29, 0.19),
	"leaf_b": Color(0.31, 0.22, 0.14),
	"frame": Color(0.22, 0.15, 0.1),
	"casing": Color(0.3, 0.22, 0.15),
}
static var _mats: Dictionary = {}
static var _grain: ImageTexture


## Matériau d'une partie : bois veiné procédural (projection triplanaire, sans
## UV), ou une surface du jeu (WorldLook.SURFACES : « metal » des pentures).
static func material(key: String) -> Material:
	if not TINTS.has(key):
		return WorldLook.surface(key)
	if _mats.has(key):
		return _mats[key]
	if _grain == null:
		var w := 64
		var h := 256
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var noise := FastNoiseLite.new()
		noise.seed = 23
		noise.frequency = 0.06
		for y in h:
			for x in w:
				# Veines verticales (les planches du battant sont debout).
				var grain := sin(x * 0.55 + noise.get_noise_2d(x * 3.0, y * 0.35) * 5.0) * 0.5 + 0.5
				var n := noise.get_noise_2d(x * 1.7, y * 1.7) * 0.5 + 0.5
				var k := 0.62 + grain * 0.22 + n * 0.16
				var c := Color(k, k * 0.97, k * 0.93)
				# Restes de peinture vert-de-gris, écaillée par plaques.
				var paint := noise.get_noise_2d(x * 0.9 + 400.0, y * 0.5)
				if paint > 0.3:
					c = c.lerp(Color(0.5, 0.56, 0.5), clampf((paint - 0.3) * 3.0, 0.0, 0.35))
				c.a = 1.0
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		_grain = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _grain
	m.albedo_color = TINTS[key]
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.6, 0.8, 1.6)
	m.roughness = 0.88
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = m
	return m


## Moitié basse d'un battant cassé à mi-hauteur : planches debout du seuil à
## LEAF_TOP environ, bouts du haut éclatés en dents de scie (hauteurs
## différentes, une planche plus courte), barres du bas et du haut, gonds en
## fer. `corner` : coin bas côté gonds ; `side` = +1 : gonds à gauche (le
## battant s'étend vers +X), -1 : gonds à droite. Rien au-dessus.
static func _half_leaf(parts: Dictionary, rng: RandomNumberGenerator, corner: Vector2, lw: float, side: float) -> void:
	var tilt := rng.randf_range(-0.012, 0.012)
	var xf := func(p: Vector2) -> Vector2:
		return corner + Vector2(p.x * side, p.y).rotated(tilt)
	var n := maxi(4, roundi(lw / 0.17))
	var bw := lw / n
	var short := rng.randi() % n
	for i in n:
		var x0 := bw * i + 0.004
		var x1 := bw * (i + 1) - 0.004
		# Cassée un peu plus bas côté libre (là où les coups ont porté).
		var top := LEAF_TOP + rng.randf_range(-0.04, 0.06) - float(i) / n * 0.1
		if i == short:
			top -= rng.randf_range(0.12, 0.2)
		var outline := _jagged_board(rng, x0, x1, 0.0, top, false, true)
		_slab(parts, "leaf_a" if i % 2 == 0 else "leaf_b", PackedVector2Array(Array(outline).map(xf)), LEAF_Z.x, LEAF_Z.y)
	# Barres (côté dehors) : celle du bas entière, celle du haut cassée au bout.
	_slab_rect(parts, "leaf_b", xf, Vector2(0.02, 0.16), Vector2(lw - 0.02, 0.3), LEDGE_Z)
	var bar := LEAF_TOP - 0.3
	_slab(parts, "leaf_b", PackedVector2Array(Array(_jagged_board(rng, 0.02, lw * rng.randf_range(0.7, 0.9), bar - 0.07, bar + 0.07, false, false, true)).map(xf)), LEDGE_Z.x, LEDGE_Z.y)
	# Gonds (bandes de fer), côté salle.
	_slab_rect(parts, "metal", xf, Vector2(-0.02, 0.2), Vector2(0.34, 0.25), STRAP_Z)
	_slab_rect(parts, "metal", xf, Vector2(-0.02, bar - 0.03), Vector2(0.3, bar + 0.02), STRAP_Z)


## Penture du haut restée sur le bâti, tordue, sans son battant (`side` comme
## _half_leaf).
static func _torn_strap(parts: Dictionary, rng: RandomNumberGenerator, hinge: Vector2, side: float) -> void:
	var bend := -side * rng.randf_range(0.25, 0.45)
	var xf := func(p: Vector2) -> Vector2:
		return hinge + Vector2(p.x * side, p.y).rotated(bend)
	_slab_rect(parts, "metal", xf, Vector2(-0.02, -0.05), Vector2(0.2, 0.0), STRAP_Z)


## Contour (sens trigonométrique) d'une planche de x0 à x1 et de y0 à y1, aux
## bouts éclatés en dents de scie (`jag_bottom`, `jag_top`) ; `jag_right` :
## barre horizontale cassée à son bout droit.
static func _jagged_board(rng: RandomNumberGenerator, x0: float, x1: float, y0: float, y1: float, jag_bottom: bool, jag_top: bool, jag_right := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var teeth := 3
	if jag_bottom:
		for k in teeth + 1:
			var x := lerpf(x0, x1, float(k) / teeth)
			out.append(Vector2(x, y0 + (rng.randf_range(-0.09, 0.0) if k % 2 == 1 else rng.randf_range(0.0, 0.05))))
	else:
		out.append(Vector2(x0, y0))
		out.append(Vector2(x1, y0))
	if jag_right:
		out.append(Vector2(x1 + rng.randf_range(0.03, 0.08), lerpf(y0, y1, 0.4)))
	if jag_top:
		for k in range(teeth, -1, -1):
			var x := lerpf(x0, x1, float(k) / teeth)
			out.append(Vector2(x, y1 + (rng.randf_range(0.0, 0.1) if k % 2 == 1 else rng.randf_range(-0.05, 0.0))))
	else:
		out.append(Vector2(x1, y1))
		out.append(Vector2(x0, y1))
	return out


static func _slab_rect(parts: Dictionary, key: String, xf: Callable, p0: Vector2, p1: Vector2, z: Vector2) -> void:
	var o := PackedVector2Array([p0, Vector2(p1.x, p0.y), p1, Vector2(p0.x, p1.y)])
	_slab(parts, key, PackedVector2Array(Array(o).map(xf)), z.x, z.y)


static func _st(parts: Dictionary, key: String) -> SurfaceTool:
	if not parts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[key] = st
	return parts[key]


## Pavé (taille, centre) dans le repère local.
static func _box(parts: Dictionary, key: String, size: Vector3, c: Vector3) -> void:
	var h := size * 0.5
	var r := PackedVector2Array([Vector2(c.x - h.x, c.y - h.y), Vector2(c.x + h.x, c.y - h.y), Vector2(c.x + h.x, c.y + h.y), Vector2(c.x - h.x, c.y + h.y)])
	_slab(parts, key, r, c.z - h.z, c.z + h.z)


## Prisme : contour `poly` (plan XY, un sens quelconque) extrudé de z0 à z1.
static func _slab(parts: Dictionary, key: String, poly: Variant, z0: float, z1: float) -> void:
	var p := PackedVector2Array(poly)
	if p.size() < 3:
		return
	# Sens trigonométrique (vu de +Z).
	var area := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		p.reverse()
	var tris := Geometry2D.triangulate_polygon(p)
	if tris.is_empty():
		return
	var st := _st(parts, key)
	# Face avant (+Z) et arrière (-Z).
	for i in range(0, tris.size(), 3):
		var a := p[tris[i]]
		var b := p[tris[i + 1]]
		var c := p[tris[i + 2]]
		_tri(st, Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(c.x, c.y, z1), Vector3.BACK)
		_tri(st, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(c.x, c.y, z0), Vector3.FORWARD)
	# Côtés (contour dans le sens trigonométrique : normale vers l'extérieur).
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		var e := b - a
		if e.length_squared() < 1e-10:
			continue
		var nrm := Vector3(e.y, -e.x, 0).normalized()
		var v0 := Vector3(a.x, a.y, z0)
		var v1 := Vector3(b.x, b.y, z0)
		var v2 := Vector3(b.x, b.y, z1)
		var v3 := Vector3(a.x, a.y, z1)
		_tri(st, v0, v1, v2, nrm)
		_tri(st, v0, v2, v3, nrm)


## Triangle tourné vers `nrm` (Godot : face avant dans le sens horaire vue de
## devant), normale plate.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> void:
	st.set_normal(nrm)
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
